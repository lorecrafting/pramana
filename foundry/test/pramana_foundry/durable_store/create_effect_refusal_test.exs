defmodule PramanaFoundry.DurableStore.CreateEffectRefusalTest do
  # The Core rows of the workflow contract's enforcement matrix, refused through the real
  # Gateway: each refusal leaves the store unchanged, and the same call one step inside
  # the bound is accepted, so the refusal is not vacuous.
  use ExUnit.Case, async: false

  alias PramanaFoundry.DurableStore.Gateway

  setup do
    root =
      Path.join(
        canonical_tmp(),
        "create-effect-refusal-#{System.pid()}-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir!(root)
    path = Path.join(root, "authority.sqlite3")
    capability = make_ref()

    assert :ok =
             Gateway.initialize(path,
               installation_id: "installation-fr08a",
               repository_id: "repository-fr08a"
             )

    gateway =
      start_supervised!(
        {Gateway,
         path: path, protected_capability: capability, writer_epoch: "writer-epoch-fr08a"}
      )

    on_exit(fn -> File.rm_rf!(root) end)
    %{gateway: gateway, capability: capability}
  end

  test "create_effect is refused under an inactive control, and admitted once active", ctx do
    seed!(ctx)

    # Core has no paused or stopped control state; pause and drain are controller rows.
    assert %{"disposition" => "rejected", "reason_code" => "invalid_control_state"} =
             current!(ctx, set_control("paused"))

    assert %{"disposition" => "accepted"} = current!(ctx, set_control("cancel_requested"))

    assert %{"disposition" => "rejected", "reason_code" => "control_not_active"} =
             current!(ctx, effect("effect-1", 0, nil, control_revision: 1))

    assert {:error, :not_found} = fact(ctx, "effect", "effect_id", "effect-1")

    assert %{"disposition" => "accepted"} = current!(ctx, set_control("active"))

    assert %{"disposition" => "accepted"} =
             current!(ctx, effect("effect-1", 0, nil, control_revision: 2))
  end

  # Units are debited when create_effect activates a reservation, not when it is proposed,
  # so the bound is checked twice: at reserve and again at activation.
  test "a reservation or an effect over the ledger's available units is refused", ctx do
    seed!(ctx)
    before = ledger!(ctx)
    assert before["available"] == 2

    assert %{"disposition" => "rejected", "reason_code" => "reservation_not_permitted"} =
             current!(ctx, reserve("reservation-1", 3))

    assert {:error, :not_found} = fact(ctx, "reservation", "reservation_id", "reservation-1")
    assert ledger!(ctx) == before

    assert %{"disposition" => "accepted"} = current!(ctx, reserve("reservation-1", 2))
    assert %{"disposition" => "accepted"} = current!(ctx, reserve("reservation-2", 1, "effect-2"))

    assert %{"disposition" => "accepted"} =
             current!(ctx, effect("effect-1", 0, nil, reservation_ids: ["reservation-1"]))

    spent = ledger!(ctx)
    assert spent["available"] == 0

    assert %{"disposition" => "rejected", "reason_code" => "reservation_activation_not_permitted"} =
             current!(
               ctx,
               effect("effect-2", 0, nil, attempt_id: "A2", reservation_ids: ["reservation-2"])
             )

    assert {:error, :not_found} = fact(ctx, "effect", "effect_id", "effect-2")
    assert ledger!(ctx) == spent
  end

  test "a successor naming a superseded predecessor is refused, and one naming the latest admitted",
       ctx do
    seed!(ctx)
    assert %{"disposition" => "accepted"} = current!(ctx, effect("effect-1", 0, nil))
    assert %{"disposition" => "accepted"} = current!(ctx, cancel("effect-1"))
    assert %{"disposition" => "accepted"} = current!(ctx, effect("effect-2", 1, "effect-1"))
    assert %{"disposition" => "accepted"} = current!(ctx, cancel("effect-2"))

    # effect-1 is terminal but no longer current: effect-2 superseded it.
    assert %{"disposition" => "rejected", "reason_code" => "predecessor_not_terminal"} =
             current!(ctx, effect("effect-3", 1, "effect-1"))

    assert {:error, :not_found} = fact(ctx, "effect", "effect_id", "effect-3")

    assert %{"disposition" => "accepted"} = current!(ctx, effect("effect-3", 2, "effect-2"))
  end

  test "a retry past the role's non-start allowance is refused, and admitted one step inside it",
       ctx do
    seed!(ctx, 1)
    assert %{"disposition" => "accepted"} = current!(ctx, reserve("reservation-1", 1))

    assert %{"disposition" => "accepted"} =
             current!(ctx, effect("effect-1", 0, nil, reservation_ids: ["reservation-1"]))

    assert %{"disposition" => "accepted"} =
             current!(ctx, %{
               "type" => "claim_effect",
               "effect_id" => "effect-1",
               "claim_id" => "claim-1",
               "writer_epoch" => "writer-epoch-fr08a"
             })

    assert %{"disposition" => "accepted"} =
             current!(ctx, %{
               "type" => "issue_claim",
               "claim_id" => "claim-1",
               "writer_epoch" => "writer-epoch-fr08a"
             })

    assert %{"disposition" => "accepted"} =
             current!(ctx, %{
               "type" => "settle_claim",
               "claim_id" => "claim-1",
               "receipt_id" => "receipt-1",
               "request_id" => "request-effect-1",
               "outcome" => "non_started",
               "proof" => "issuer_quiescent",
               "payload" => %{
                 "quiescence_epoch" => "writer-epoch-fr08a",
                 "failure_class" => "backend_refused_start"
               }
             })

    # One non-start recorded against a limit of one: the allowance is spent.
    assert %{"disposition" => "rejected", "reason_code" => "nonstart_allowance_exhausted"} =
             current!(ctx, effect("effect-2", 1, "effect-1"))

    assert {:error, :not_found} = fact(ctx, "effect", "effect_id", "effect-2")

    assert %{"disposition" => "accepted"} = current!(ctx, set_policy(2))

    assert %{"disposition" => "accepted"} =
             current!(ctx, effect("effect-2", 1, "effect-1", policy_revision: 1))
  end

  defp seed!(ctx, limit \\ 3) do
    assert %{"disposition" => "accepted"} = current!(ctx, set_policy(limit))
    assert %{"disposition" => "accepted"} = current!(ctx, set_control("active"))

    assert %{"disposition" => "accepted"} =
             current!(ctx, %{
               "type" => "grant_ledger",
               "ledger_id" => "ledger-1",
               "generation" => 0,
               "dimension" => "starts.developer",
               "units" => 2
             })
  end

  defp set_policy(limit) do
    %{
      "type" => "set_policy",
      "policy_id" => "policy-1",
      "value" => %{
        "allowed_operations" => ["launch"],
        "allowed_scopes" => ["ticket:T1"],
        "infrastructure_attempt_limits" => %{"developer" => limit}
      }
    }
  end

  defp set_control(status) do
    %{"type" => "set_control", "control_id" => "control-1", "value" => %{"status" => status}}
  end

  defp reserve(id, units, owner \\ "effect-1") do
    %{
      "type" => "reserve",
      "reservation_id" => id,
      "ledger_id" => "ledger-1",
      "generation" => 0,
      "owner_kind" => "effect",
      "owner_id" => owner,
      "units" => units
    }
  end

  defp cancel(id), do: %{"type" => "cancel_effect", "effect_id" => id, "proof" => "unissued"}

  defp effect(id, ordinal, predecessor, opts \\ []) do
    request =
      %{
        "request_id" => "request-#{id}",
        "role" => "developer",
        "profile" => "sol",
        "phase_generation" => 0,
        "operation_ordinal" => ordinal
      }
      |> then(&if predecessor, do: Map.put(&1, "predecessor_effect_id", predecessor), else: &1)

    %{
      "type" => "create_effect",
      "effect_id" => id,
      "request" => request,
      "operation" => "launch",
      "scope" => "ticket:T1",
      "ticket_id" => "T1",
      "attempt_id" => Keyword.get(opts, :attempt_id, "A1"),
      "execution_id" => "execution-#{id}",
      "policy_id" => "policy-1",
      "policy_revision" => Keyword.get(opts, :policy_revision, 0),
      "control_id" => "control-1",
      "control_revision" => Keyword.get(opts, :control_revision, 0),
      "reservation_ids" => Keyword.get(opts, :reservation_ids, []),
      "leases" => []
    }
  end

  # Submits with an empty read set, then again with the revisions the store says it needs.
  defp current!(ctx, operation) do
    id = "root-#{System.unique_integer([:positive, :monotonic])}"
    assert {:ok, first, :committed} = protected(ctx, id <> "-PROBE", %{}, operation)

    if first["reason_code"] == "incomplete_read_set" do
      assert {:ok, result, :committed} =
               protected(ctx, id, first["facts"]["required_revisions"], operation)

      result
    else
      first
    end
  end

  defp protected(ctx, id, reads, operation) do
    Gateway.protected_command(ctx.gateway, ctx.capability, "operator", %{
      "schema_version" => 1,
      "command_id" => id,
      "expected_revisions" => reads,
      "operation" => operation
    })
  end

  defp fact(ctx, type, key, value) do
    Gateway.protected_query(ctx.gateway, ctx.capability, %{
      "schema_version" => 1,
      "type" => type,
      key => value
    })
  end

  defp ledger!(ctx) do
    assert {:ok, ledger} =
             Gateway.protected_query(ctx.gateway, ctx.capability, %{
               "schema_version" => 1,
               "type" => "ledger",
               "ledger_id" => "ledger-1",
               "generation" => 0
             })

    ledger
  end

  defp canonical_tmp do
    if File.dir?("/private/tmp"), do: "/private/tmp", else: System.tmp_dir!()
  end
end
