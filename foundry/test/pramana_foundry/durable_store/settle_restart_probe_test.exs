defmodule PramanaFoundry.DurableStore.SettleRestartProbeTest do
  # settle_claim defects that committed a state the restart check
  # (ProtectedPrimitives.validate, run when the database opens) then refused:
  #
  # L1 (foundry/spec/ledger/README.md, finding 1): a settle_claim reusing another claim's
  #   receipt_id quarantined a claimed-but-never-issued (or cancelled) claim.
  # B (foundry/spec/fr10/README.md, finding B): a late `unknown` receipt moved an already
  #   settled effect to reconciliation_required, stranding its retry.
  #
  # Each test drives the real gateway, checks the operation's outcome, then reopens the store.
  use ExUnit.Case, async: false

  alias PramanaFoundry.DurableStore.Gateway

  setup do
    root =
      Path.join(
        "/private/tmp",
        "settle-restart-#{System.pid()}-#{System.unique_integer([:positive, :monotonic])}"
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
    gw = {gateway, capability}

    for {id, op} <- [
          {"SEED-POLICY",
           %{
             "type" => "set_policy",
             "policy_id" => "policy-1",
             "value" => %{"allowed_operations" => ["launch"], "allowed_scopes" => ["ticket:T-S"]}
           }},
          {"SEED-CONTROL",
           %{
             "type" => "set_control",
             "control_id" => "control-1",
             "value" => %{"status" => "active"}
           }},
          {"SEED-LEDGER",
           %{
             "type" => "grant_ledger",
             "ledger_id" => "root",
             "generation" => 0,
             "dimension" => "starts.developer",
             "units" => 2
           }}
        ] do
      assert %{"disposition" => "accepted"} = run(gw, id, op), id
    end

    %{gw: gw, path: path, capability: capability}
  end

  describe "L1: settling a claim that was never issued" do
    setup %{gw: gw} do
      claimed!(gw, "1")
      assert %{"disposition" => "accepted"} = run(gw, "ISSUE-1", issue("1"))
      assert %{"disposition" => "accepted"} = run(gw, "R1", settle("1", "receipt-1", "unknown"))
      claimed!(gw, "2")
      :ok
    end

    test "a claimed claim reusing another claim's receipt_id is refused, not quarantined", ctx do
      before = state(ctx.gw, "2")
      assert before.claim == "claimed"

      assert %{"disposition" => "rejected", "reason_code" => "claim_settlement_not_permitted"} =
               run(ctx.gw, "R2-REUSE", settle("2", "receipt-1", "unknown"))

      assert state(ctx.gw, "2") == before
      reopen!(ctx)
    end

    test "a cancelled claim reusing another claim's receipt_id is refused, not quarantined",
         ctx do
      assert %{"disposition" => "accepted"} =
               run(ctx.gw, "CANCEL-2", %{
                 "type" => "cancel_effect",
                 "effect_id" => "effect-2",
                 "proof" => "issuer_quiescent"
               })

      before = state(ctx.gw, "2")
      assert before.claim == "cancelled"

      assert %{"disposition" => "rejected", "reason_code" => "claim_settlement_not_permitted"} =
               run(ctx.gw, "R2-REUSE", settle("2", "receipt-1", "unknown"))

      assert state(ctx.gw, "2") == before
      # No reopen here: the issuer_quiescent cancel above already leaves a store that
      # fails the restart check ({:protected_corrupt, "root_ledgers", :transition}), a
      # separate defect in cancel_effect, not in settle_claim.
    end
  end

  describe "B: a late unknown receipt after a known outcome" do
    setup %{gw: gw} do
      claimed!(gw, "1")
      assert %{"disposition" => "accepted"} = run(gw, "ISSUE-1", issue("1"))
      assert %{"disposition" => "accepted"} = run(gw, "R1", settle("1", "receipt-1", "failed"))
      :ok
    end

    test "is stored and leaves the settled claim and effect unchanged", ctx do
      before = state(ctx.gw, "1")
      assert %{claim: "failed", effect: "failed", reservation: "consumed"} = before

      assert %{"disposition" => "accepted", "facts" => facts} =
               run(ctx.gw, "R0-LATE", settle("1", "receipt-0", "unknown"))

      assert %{"receipt_id" => "receipt-0", "outcome" => "unknown"} = facts["receipt"]
      assert state(ctx.gw, "1") == before

      # An exact replay of the stale receipt is idempotent.
      assert %{"disposition" => "accepted"} =
               run(ctx.gw, "R0-LATE-AGAIN", settle("1", "receipt-0", "unknown"))

      assert state(ctx.gw, "1") == before
      ctx = reopen!(ctx)
      assert state(ctx.gw, "1") == before
    end

    test "a conflicting known outcome still quarantines", ctx do
      assert %{"disposition" => "rejected", "reason_code" => "conflicting_receipt"} =
               run(ctx.gw, "R2-CONFLICT", settle("1", "receipt-2", "succeeded"))

      assert %{claim: "reconciliation_required"} = state(ctx.gw, "1")
      reopen!(ctx)
    end
  end

  defp reopen!(ctx) do
    stop_supervised!(Gateway)

    assert {:ok, gateway} =
             start_supervised(
               {Gateway,
                path: ctx.path,
                protected_capability: ctx.capability,
                writer_epoch: "writer-epoch-fr08a"},
               id: :reopened
             )

    # A store that fails the restart check opens in recovery mode, not :ready.
    assert %{mode: :ready, reason: nil} = Gateway.status(gateway)
    %{ctx | gw: {gateway, ctx.capability}}
  end

  defp claimed!(gw, n) do
    steps = [
      {"RESERVE-" <> n,
       %{
         "type" => "reserve",
         "reservation_id" => "reservation-" <> n,
         "ledger_id" => "root",
         "generation" => 0,
         "owner_kind" => "effect",
         "owner_id" => "effect-" <> n,
         "units" => 1
       }},
      {"EFFECT-" <> n,
       %{
         "type" => "create_effect",
         "effect_id" => "effect-" <> n,
         "request" => %{
           "request_id" => "request-" <> n,
           "role" => "developer",
           "profile" => "sol"
         },
         "operation" => "launch",
         "scope" => "ticket:T-S",
         "ticket_id" => "T-S",
         "attempt_id" => "attempt-" <> n,
         "execution_id" => "execution-" <> n,
         "policy_id" => "policy-1",
         "policy_revision" => 0,
         "control_id" => "control-1",
         "control_revision" => 0,
         "reservation_ids" => ["reservation-" <> n],
         "leases" => [%{"lease_id" => "lease-" <> n, "resource_id" => "slot-" <> n}]
       }},
      {"CLAIM-" <> n,
       %{
         "type" => "claim_effect",
         "effect_id" => "effect-" <> n,
         "claim_id" => "claim-" <> n,
         "writer_epoch" => "writer-epoch-fr08a"
       }}
    ]

    for {id, op} <- steps do
      assert %{"disposition" => "accepted"} = run(gw, id, op), id
    end
  end

  defp issue(n),
    do: %{
      "type" => "issue_claim",
      "claim_id" => "claim-" <> n,
      "writer_epoch" => "writer-epoch-fr08a"
    }

  defp settle(n, receipt_id, outcome) do
    {proof, payload} =
      case outcome do
        "unknown" -> {"outcome_unknown", %{"provider" => "synthetic-fixture"}}
        _ -> {"delivered", %{"provider" => "synthetic-fixture"}}
      end

    %{
      "type" => "settle_claim",
      "claim_id" => "claim-" <> n,
      "receipt_id" => receipt_id,
      "request_id" => "request-" <> n,
      "outcome" => outcome,
      "proof" => proof,
      "payload" => payload
    }
  end

  defp state({gateway, capability}, n) do
    fact = fn query ->
      assert {:ok, fact} = Gateway.protected_query(gateway, capability, query)
      fact
    end

    claim = fact.(q("claim", "claim_id", "claim-" <> n))

    %{
      claim: claim["status"],
      claim_revision: claim["revision"],
      effect: fact.(q("effect", "effect_id", "effect-" <> n))["status"],
      reservation: fact.(q("reservation", "reservation_id", "reservation-" <> n))["status"]
    }
  end

  defp q(type, key, value), do: %{"schema_version" => 1, "type" => type, key => value}

  # Same as run/3 in quarantine_exit_probe_test.exs.
  defp run({gateway, capability}, id, operation) do
    assert {:ok, first, :committed} =
             protected(gateway, capability, id <> "-PROBE", %{}, operation)

    if first["reason_code"] == "incomplete_read_set" do
      assert {:ok, result, :committed} =
               protected(gateway, capability, id, first["facts"]["required_revisions"], operation)

      result
    else
      first
    end
  end

  defp protected(gateway, capability, id, reads, operation) do
    Gateway.protected_command(gateway, capability, "operator", %{
      "schema_version" => 1,
      "command_id" => id,
      "expected_revisions" => reads,
      "operation" => operation
    })
  end
end
