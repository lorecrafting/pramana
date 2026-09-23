defmodule PramanaFoundry.ManualLane.BackendTest do
  @moduledoc """
  T3 against a Gateway the test starts (THIN-LANE-DESIGN-2026-09-23.md §3). After every
  step the state rebuilt from the store must equal the committed projection (the
  substitution law), and every store state a test leaves reopens `:ready`.
  """
  use ExUnit.Case, async: false

  alias Exqlite.Sqlite3
  alias PramanaFoundry.DurableStore.{Database, Gateway}
  alias PramanaFoundry.ManualLane.{Backend, Replay}

  # W1's `WorkPacket` is built concurrently; until it lands the packet is the effect.
  defmodule StubPacket do
    def build(ticket, effect, _policy) when is_map(ticket), do: {:ok, effect}
  end

  @dev "human:raymond"
  @rev "agent:fable:s1"
  @spec_ %{
    "base_revision" => String.duplicate("a", 40),
    "base_ref" => "main",
    "title" => "t",
    "scope" => ["foundry/**"],
    "acceptance_criteria" => ["passes"]
  }

  setup do
    root = Path.join("/private/tmp", "manual-lane-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    path = Path.join(root, "authority.sqlite3")
    capability = make_ref()
    :ok = Gateway.initialize(path)

    gateway =
      start_supervised!(
        {Gateway, path: path, protected_capability: capability, writer_epoch: "epoch-A"}
      )

    on_exit(fn -> File.rm_rf!(root) end)

    ctx = %{
      gateway: gateway,
      capability: capability,
      path: path,
      writer_epoch: "epoch-A",
      work_packet: StubPacket
    }

    %{lane: ctx}
  end

  # ── Seed (W3's job in production) ────────────────────────────────────────────────

  defp seed!(ctx, dev_limit \\ 3, rev_limit \\ 3) do
    ids = Backend.ids()

    ops = [
      %{
        "type" => "set_policy",
        "policy_id" => ids.policy_id,
        "value" => %{
          "allowed_operations" => ["launch"],
          "allowed_scopes" => [],
          "allowed_roles" => ["developer", "reviewer"],
          "infrastructure_attempt_limits" => %{"developer" => dev_limit, "reviewer" => rev_limit},
          "independent_of_roles" => %{"reviewer" => ["developer"]},
          "check_set" => []
        }
      },
      %{
        "type" => "set_control",
        "control_id" => ids.control_id,
        "value" => %{"status" => "active"}
      }
      | for {role, ledger} <- ids.ledgers do
          %{
            "type" => "grant_ledger",
            "ledger_id" => ledger,
            "generation" => 0,
            "dimension" => "starts." <> role,
            "units" => 3
          }
        end
    ]

    for {op, i} <- Enum.with_index(ops) do
      assert {:ok, %{"disposition" => "accepted"}, _} =
               Replay.root(ctx, "operator", "seed-#{i}", op)
    end

    assert {:ok, _} = Backend.admit(ctx, "ML-1", @spec_)
    law!(ctx)
  end

  defp attest(principal, extra \\ %{}) do
    Map.merge(
      %{
        "evidence_kind" => "operator_attestation",
        "attested_by" => principal,
        "statement" => "it ran"
      },
      extra
    )
  end

  @quiet %{"issuer_gone" => true, "channel_quiet" => true}

  # Developer launched, delivered, frozen, sealed, closed and checks started (policy-empty).
  defp awaiting_review!(ctx) do
    assert {:ok, %{"execution_id" => exec, "attempt_id" => attempt}} =
             Backend.launch(ctx, "ML-1", "developer", @dev)

    law!(ctx)
    assert {:ok, _} = Backend.deliver(ctx, "ML-1", "developer", @dev, attest(@dev))
    base = %{"ticket_id" => "ML-1", "attempt_id" => attempt}

    assert {:ok, _} =
             Backend.ingress(
               ctx,
               "ML-1/freeze/#{exec}",
               "ML-1",
               [
                 {"artifact_frozen",
                  Map.merge(base, %{
                    "candidate_id" => "cand-1",
                    "observation_id" => "obs-1",
                    "sealed_generation" => "gen-1"
                  })},
                 {"stream_sealed",
                  Map.merge(base, %{"execution_id" => exec, "last_accepted_sequence" => 0})},
                 {"developer_closed", Map.put(base, "execution_id", exec)},
                 {"checks_started", Map.put(base, "policy_empty", true)}
               ],
               @dev
             )

    law!(ctx)
    assert ticket(ctx)["phase"] == "awaiting_review"
    exec
  end

  defp ticket(ctx), do: Backend.state(ctx)["tickets"]["ML-1"]

  defp effect(ctx, id) do
    {:ok, effect} = Replay.query(ctx, %{"type" => "effect", "effect_id" => id})
    effect
  end

  defp ledger(ctx, role) do
    {:ok, l} =
      Replay.query(ctx, %{
        "type" => "ledger",
        "ledger_id" => Backend.ids().ledgers[role],
        "generation" => 0
      })

    Map.take(l, ~w(available held consumed))
  end

  # The substitution law: replayed ticket == committed projection.
  defp law!(ctx) do
    {:ok, conn} = Sqlite3.open(ctx.path, mode: :readonly)

    {:ok, [[bytes]]} =
      Database.query(
        conn,
        "SELECT projection FROM projections WHERE namespace = ? AND entity_id = ?",
        ["foundry.ticket.v1", "ML-1"]
      )

    :ok = Sqlite3.close(conn)
    replayed = ticket(ctx) |> JSON.encode!() |> JSON.decode!()
    assert JSON.decode!(bytes)["value"] == replayed
  end

  # Stops the Gateway and reopens the same store under a new epoch: it must be :ready.
  defp reopen!(ctx) do
    stop_supervised!(Gateway)
    epoch = "epoch-#{System.unique_integer([:positive])}"

    gateway =
      start_supervised!(
        {Gateway, path: ctx.path, protected_capability: ctx.capability, writer_epoch: epoch},
        id: Gateway
      )

    assert %{mode: :ready, reason: nil} = Gateway.status(gateway)
    law!(%{ctx | gateway: gateway})
    %{ctx | gateway: gateway, writer_epoch: epoch}
  end

  # ── Q5 first: does settle_claim accept the attestation keys? ─────────────────────

  test "Q5: a non-start receipt carrying the attestation keys is accepted by Core", %{lane: ctx} do
    seed!(ctx)
    assert {:ok, %{"effect_id" => effect_id}} = Backend.launch(ctx, "ML-1", "developer", @dev)

    assert {:ok, %{"selected_discriminator" => "below_infrastructure_limit"}} =
             Backend.settle(ctx, "ML-1", "developer", @dev, :non_started, attest(@dev, @quiet))

    [claim] = effect(ctx, effect_id)["claims"]
    [receipt] = claim["receipts"]

    assert Map.take(receipt["payload"], ~w(evidence_kind attested_by issuer_gone channel_quiet)) ==
             %{
               "evidence_kind" => "operator_attestation",
               "attested_by" => @dev,
               "issuer_gone" => true,
               "channel_quiet" => true
             }

    assert receipt["payload"]["failure_class"] == "operator_attested_non_start"
    assert ticket(ctx)["phase"] == "queued"
    reopen!(ctx)
  end

  # ── Full path ────────────────────────────────────────────────────────────────────

  test "admit, launch, deliver, freeze, independent review, approved: ready_to_integrate",
       %{lane: ctx} do
    seed!(ctx)
    ctx = reopen!(ctx)
    assert ticket(ctx)["phase"] == "queued"
    dev_exec = awaiting_review!(ctx)
    ctx = reopen!(ctx)

    assert {:ok, %{"issuer" => @rev, "role" => "reviewer", "status" => "issued"}} =
             Backend.launch(ctx, "ML-1", "reviewer", @rev)

    law!(ctx)
    assert ticket(ctx)["phase"] == "reviewing"
    ctx = reopen!(ctx)

    assert {:ok, %{"ticket" => %{"phase" => "ready_to_integrate"} = t}} =
             Backend.review(ctx, "ML-1", @rev, "approved", "cand-1", attest(@rev))

    law!(ctx)
    attempt = t["attempts"][t["active_attempt_id"]]
    assert attempt["review"]["verdict"] == "approved"
    assert effect(ctx, attempt["review"]["execution_id"] |> effect_id())["status"] == "succeeded"
    assert effect(ctx, effect_id(dev_exec))["issuer"] == @dev

    # Replaying review is idempotent: every step is already committed.
    assert {:ok, %{"ticket" => %{"phase" => "ready_to_integrate"}}} =
             Backend.review(ctx, "ML-1", @rev, "approved", "cand-1", attest(@rev))

    reopen!(ctx)
  end

  defp effect_id(execution_id), do: String.replace_suffix(execution_id, "/execution", "/effect")

  test "launching twice creates exactly one effect and returns the same packet", %{lane: ctx} do
    seed!(ctx)
    assert {:ok, first} = Backend.launch(ctx, "ML-1", "developer", @dev)
    assert {:ok, ^first} = Backend.launch(ctx, "ML-1", "developer", @dev)
    attempt = ticket(ctx)["attempts"][ticket(ctx)["active_attempt_id"]]
    assert map_size(attempt["executions"]) == 1
    assert ledger(ctx, "developer")["held"] == 1
    reopen!(ctx)
  end

  # ── Independence ─────────────────────────────────────────────────────────────────

  test "red control: a reviewer under the developer's principal is refused by Core, pre-intent",
       %{lane: ctx} do
    seed!(ctx)
    awaiting_review!(ctx)

    assert {:reject, :principal_not_independent} =
             Backend.launch(ctx, "ML-1", "reviewer", @dev)

    law!(ctx)
    assert ticket(ctx)["phase"] == "awaiting_review"
    assert ledger(ctx, "reviewer")["held"] == 0

    # Neighbour: the distinct principal is not blocked by the refused command.
    assert {:ok, %{"issuer" => @rev}} = Backend.launch(ctx, "ML-1", "reviewer", @rev)
    assert ticket(ctx)["phase"] == "reviewing"
    reopen!(ctx)
  end

  # ── Verdicts ─────────────────────────────────────────────────────────────────────

  test "correction terminalises the attempt and requeues the ticket", %{lane: ctx} do
    seed!(ctx)
    awaiting_review!(ctx)
    {:ok, _} = Backend.launch(ctx, "ML-1", "reviewer", @rev)

    assert {:ok, %{"ticket" => t}} =
             Backend.review(ctx, "ML-1", @rev, "correction", "cand-1", attest(@rev))

    assert {t["phase"], t["active_attempt_id"]} == {"queued", nil}
    law!(ctx)

    # A fresh developer attempt follows under a fresh id.
    assert {:ok, %{"status" => "issued", "operation_ordinal" => 0}} =
             Backend.launch(ctx, "ML-1", "developer", @dev)

    reopen!(ctx)
  end

  test "rejected terminalises attempt and ticket", %{lane: ctx} do
    seed!(ctx)
    awaiting_review!(ctx)
    {:ok, _} = Backend.launch(ctx, "ML-1", "reviewer", @rev)

    assert {:ok, %{"ticket" => %{"phase" => "rejected"}}} =
             Backend.review(ctx, "ML-1", @rev, "rejected", "cand-1", attest(@rev))

    law!(ctx)
    reopen!(ctx)
  end

  # ── Non-starts ───────────────────────────────────────────────────────────────────

  test "developer non-start below the limit requeues; the retry names its predecessor",
       %{lane: ctx} do
    seed!(ctx)
    {:ok, %{"effect_id" => first}} = Backend.launch(ctx, "ML-1", "developer", @dev)

    assert {:ok, %{"selected_discriminator" => "below_infrastructure_limit"}} =
             Backend.settle(ctx, "ML-1", "developer", @dev, :non_started, attest(@dev, @quiet))

    law!(ctx)
    assert ticket(ctx)["phase"] == "queued"

    assert {:ok, %{"predecessor_effect_id" => ^first, "operation_ordinal" => 1}} =
             Backend.launch(ctx, "ML-1", "developer", @dev)

    reopen!(ctx)
  end

  test "developer non-start at the limit blocks", %{lane: ctx} do
    seed!(ctx, 1)
    {:ok, _} = Backend.launch(ctx, "ML-1", "developer", @dev)

    assert {:ok, %{"selected_discriminator" => "infrastructure_limit_reached"}} =
             Backend.settle(ctx, "ML-1", "developer", @dev, :non_started, attest(@dev, @quiet))

    assert {ticket(ctx)["phase"], ticket(ctx)["reason"]} ==
             {"blocked", "developer_launch_infrastructure"}

    law!(ctx)
    reopen!(ctx)
  end

  test "reviewer non-start below the limit returns to awaiting_review", %{lane: ctx} do
    seed!(ctx)
    awaiting_review!(ctx)
    {:ok, _} = Backend.launch(ctx, "ML-1", "reviewer", @rev)

    assert {:ok, %{"selected_discriminator" => "below_infrastructure_limit"}} =
             Backend.settle(ctx, "ML-1", "reviewer", @rev, :non_started, attest(@rev, @quiet))

    assert ticket(ctx)["phase"] == "awaiting_review"
    assert ledger(ctx, "reviewer") == %{"available" => 3, "held" => 0, "consumed" => 0}
    law!(ctx)
    reopen!(ctx)
  end

  test "reviewer non-start at the limit blocks", %{lane: ctx} do
    seed!(ctx, 3, 1)
    awaiting_review!(ctx)
    {:ok, _} = Backend.launch(ctx, "ML-1", "reviewer", @rev)

    assert {:ok, %{"selected_discriminator" => "infrastructure_limit_reached"}} =
             Backend.settle(ctx, "ML-1", "reviewer", @rev, :non_started, attest(@rev, @quiet))

    assert {ticket(ctx)["phase"], ticket(ctx)["reason"]} ==
             {"blocked", "reviewer_launch_infrastructure"}

    law!(ctx)
    reopen!(ctx)
  end

  for missing <- ["issuer_gone", "channel_quiet"] do
    test "red control: a non-start attestation without #{missing} is refused", %{lane: ctx} do
      seed!(ctx)
      {:ok, %{"effect_id" => id}} = Backend.launch(ctx, "ML-1", "developer", @dev)
      partial = attest(@dev, Map.put(@quiet, unquote(missing), false))

      assert {:reject, :quiescence_not_attested} =
               Backend.settle(ctx, "ML-1", "developer", @dev, :non_started, partial)

      assert {:reject, :quiescence_not_attested} =
               Backend.settle(
                 ctx,
                 "ML-1",
                 "developer",
                 @dev,
                 :non_started,
                 Map.delete(partial, unquote(missing))
               )

      assert effect(ctx, id)["status"] == "issued"
      reopen!(ctx)
    end
  end

  test "red control: a receipt without an operator attestation is refused", %{lane: ctx} do
    seed!(ctx)
    {:ok, %{"effect_id" => id}} = Backend.launch(ctx, "ML-1", "developer", @dev)

    for bad <- [
          %{},
          Map.delete(attest(@dev), "evidence_kind"),
          attest(@rev),
          attest(@dev, %{"statement" => "  "})
        ] do
      assert {:reject, :attestation_required} =
               Backend.deliver(ctx, "ML-1", "developer", @dev, bad)
    end

    assert effect(ctx, id)["status"] == "issued"
    reopen!(ctx)
  end

  # ── Unknown ──────────────────────────────────────────────────────────────────────

  test "an unknown settlement keeps its units held", %{lane: ctx} do
    seed!(ctx)
    {:ok, %{"effect_id" => id}} = Backend.launch(ctx, "ML-1", "developer", @dev)

    assert {:ok, _} =
             Backend.settle(ctx, "ML-1", "developer", @dev, :unknown, attest(@dev))

    assert effect(ctx, id)["status"] == "unknown"
    assert ledger(ctx, "developer")["held"] == 1
    law!(ctx)
    ctx = reopen!(ctx)
    assert ledger(ctx, "developer")["held"] == 1
  end

  test "red control: settle(:unknown) after succeeded is refused", %{lane: ctx} do
    seed!(ctx)
    {:ok, %{"effect_id" => id}} = Backend.launch(ctx, "ML-1", "developer", @dev)
    {:ok, _} = Backend.deliver(ctx, "ML-1", "developer", @dev, attest(@dev))

    assert {:reject, :effect_already_settled} =
             Backend.settle(ctx, "ML-1", "developer", @dev, :unknown, attest(@dev))

    assert effect(ctx, id)["status"] == "succeeded"
    reopen!(ctx)
  end

  # ── Ingress and admission ────────────────────────────────────────────────────────

  test "red control: an ingress of review_recorded is refused", %{lane: ctx} do
    seed!(ctx)

    assert {:reject, :ingress_type_not_allowed} =
             Backend.ingress(ctx, "X", "ML-1", [{"review_recorded", %{}}], "operator")

    reopen!(ctx)
  end

  test "red control: a non-lane ticket id is refused at admission", %{lane: ctx} do
    seed!(ctx)
    assert {:reject, :ticket_id_not_lane} = Backend.admit(ctx, "T-1-abc", @spec_)
    assert Backend.state(ctx)["tickets"]["T-1-abc"] == nil
    reopen!(ctx)
  end
end
