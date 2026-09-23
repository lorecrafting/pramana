defmodule PramanaFoundry.DurableStore.QuarantineExitProbeTest do
  # FR-10 design Q3 (foundry/docs/fr-10/FR10-DESIGN-2026-09-23.md §8): characterization
  # probe. Pins what ordinary protected commands actually do to a claim/effect that
  # quarantine_conflicting_receipt moved to reconciliation_required. Not a fix: where a
  # test says "settles it", that is current behaviour, not endorsed behaviour.
  use ExUnit.Case, async: false

  alias PramanaFoundry.DurableStore.Gateway

  @claim "claim-observation"
  @effect "effect-observation"
  @reservation "reservation-observation"
  @request "request-observation"

  setup do
    root =
      Path.join(
        "/private/tmp",
        "quarantine-exit-#{System.pid()}-#{System.unique_integer([:positive, :monotonic])}"
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
    seed_issued!(gw)
    %{gw: gw}
  end

  describe "route A: unknown receipt, then a conflicting receipt under the same receipt id" do
    setup %{gw: gw} do
      assert %{"disposition" => "accepted"} =
               run(gw, "R1-UNKNOWN", settle("receipt-1", "unknown"))

      assert state(gw).reservation == "issued_unknown"

      assert %{"disposition" => "rejected", "reason_code" => "conflicting_receipt"} =
               run(gw, "R1-CONFLICT", settle("receipt-1", "succeeded"))

      assert %{claim: "reconciliation_required", effect: "reconciliation_required"} = state(gw)
      :ok
    end

    test "non-receipt commands are refused and leave the claim quarantined", %{gw: gw} do
      before = state(gw)

      for {id, op, reason} <- non_receipt_attempts("claim_already_issued") do
        assert %{"disposition" => "rejected", "reason_code" => ^reason} = run(gw, id, op)
      end

      assert state(gw) == before
      assert before.reservation == "issued_unknown"
      assert before.ledger["held"] == 1
    end

    test "an exact replay of the unknown receipt is accepted and changes nothing", %{gw: gw} do
      before = state(gw)

      assert %{"disposition" => "accepted", "facts" => %{"claim" => %{"status" => status}}} =
               run(gw, "R1-REPLAY", settle("receipt-1", "unknown"))

      assert status == "reconciliation_required"
      assert state(gw) == before
    end

    test "a second unknown receipt re-quarantines and leaves the claim quarantined", %{gw: gw} do
      assert %{"disposition" => "rejected", "reason_code" => "conflicting_receipt"} =
               run(gw, "R2-UNKNOWN", settle("receipt-2", "unknown"))

      assert %{claim: "reconciliation_required", reservation: "issued_unknown"} = state(gw)
    end

    test "a fresh succeeded receipt settles it and consumes the reservation", %{gw: gw} do
      assert %{"disposition" => "accepted"} =
               run(gw, "R3-SUCCEEDED", settle("receipt-3", "succeeded"))

      assert %{claim: "succeeded", effect: "succeeded", reservation: "consumed", ledger: ledger} =
               state(gw)

      assert %{"held" => 0, "consumed" => 1} = ledger
    end

    test "a fresh failed receipt settles it and consumes the reservation", %{gw: gw} do
      assert %{"disposition" => "accepted"} = run(gw, "R3-FAILED", settle("receipt-3", "failed"))
      assert %{claim: "failed", effect: "failed", reservation: "consumed"} = state(gw)
    end

    test "a fresh non_started receipt settles it and releases the reservation", %{gw: gw} do
      assert %{"disposition" => "accepted"} =
               run(gw, "R3-NON-STARTED", settle("receipt-3", "non_started"))

      assert %{claim: "non_started", effect: "non_started", reservation: "released", ledger: l} =
               state(gw)

      assert %{"held" => 0, "available" => 1, "consumed" => 0} = l
    end

    test "control cancel and generation close leave it quarantined; a fresh receipt still settles it",
         %{gw: gw} do
      assert %{"disposition" => "accepted", "facts" => facts} =
               run(gw, "CONTROL-CANCEL", %{
                 "type" => "set_control",
                 "control_id" => "control-1",
                 "value" => %{"status" => "cancel_requested"}
               })

      assert inspect(facts) =~ @claim

      assert %{"disposition" => "accepted"} =
               run(gw, "CLOSE-GEN", %{
                 "type" => "close_generation",
                 "ledger_id" => "root",
                 "generation" => 0
               })

      assert %{claim: "reconciliation_required", reservation: "issued_unknown", ledger: l} =
               state(gw)

      assert %{"status" => "closed", "held" => 1} = l

      assert %{"disposition" => "accepted"} =
               run(gw, "R3-AFTER-CLOSE", settle("receipt-3", "succeeded"))

      assert %{claim: "succeeded", reservation: "consumed", ledger: %{"consumed" => 1}} =
               state(gw)
    end
  end

  describe "route B: conflicting receipt on a terminal (succeeded) effect" do
    setup %{gw: gw} do
      assert %{"disposition" => "accepted"} =
               run(gw, "R1-SUCCEEDED", settle("receipt-1", "succeeded"))

      assert %{"disposition" => "rejected", "reason_code" => "conflicting_receipt"} =
               run(gw, "R1-CONFLICT", settle("receipt-1", "failed"))

      assert %{claim: "reconciliation_required", reservation: "consumed"} = state(gw)
      :ok
    end

    test "non-receipt commands are refused and leave the claim quarantined", %{gw: gw} do
      before = state(gw)

      for {id, op, reason} <- non_receipt_attempts("reservation_release_not_permitted") do
        assert %{"disposition" => "rejected", "reason_code" => ^reason} = run(gw, id, op)
      end

      assert state(gw) == before
    end

    test "fresh receipts of every outcome re-quarantine and leave the claim quarantined",
         %{gw: gw} do
      before = state(gw)

      for outcome <- ~w(succeeded failed non_started unknown) do
        assert %{"disposition" => "rejected", "reason_code" => "conflicting_receipt"} =
                 run(gw, "FRESH-" <> outcome, settle("receipt-" <> outcome, outcome))
      end

      assert %{state(gw) | claim_revision: nil} == %{before | claim_revision: nil}
      assert before.reservation == "consumed"
    end

    test "an exact replay of the original receipt is accepted and leaves the claim quarantined",
         %{gw: gw} do
      before = state(gw)

      assert %{"disposition" => "accepted", "facts" => %{"claim" => %{"status" => status}}} =
               run(gw, "R1-REPLAY", settle("receipt-1", "succeeded"))

      assert status == "reconciliation_required"
      assert state(gw) == before
    end
  end

  defp non_receipt_attempts(release_reason) do
    [
      {"RECLAIM",
       %{
         "type" => "reclaim_claim",
         "claim_id" => @claim,
         "prior_writer_epoch" => "writer-epoch-old",
         "new_writer_epoch" => "writer-epoch-fr08a",
         "proof" => "issuer_quiescent"
       }, "claim_takeover_not_permitted"},
      {"ISSUE", issue(), "claim_issue_not_permitted"},
      {"CANCEL-UNISSUED", cancel("unissued"), "cancellation_not_permitted"},
      {"CANCEL-QUIESCENT", cancel("issuer_quiescent"), "cancellation_not_permitted"},
      {"CANCEL-ACK", cancel("control_ack"), "cancellation_not_permitted"},
      {"RELEASE",
       %{
         "type" => "release_reservation",
         "reservation_id" => @reservation,
         "proof" => "unissued"
       }, release_reason},
      {"CLOSE-ATTEMPT",
       %{
         "type" => "close_attempt",
         "scope" => "ticket:T-Q3",
         "ticket_id" => "T-Q3",
         "attempt_id" => "attempt-observation"
       }, "attempt_not_settled"}
    ]
  end

  defp issue,
    do: %{"type" => "issue_claim", "claim_id" => @claim, "writer_epoch" => "writer-epoch-fr08a"}

  defp cancel(proof), do: %{"type" => "cancel_effect", "effect_id" => @effect, "proof" => proof}

  defp settle(receipt_id, outcome) do
    {proof, payload} =
      case outcome do
        "unknown" -> {"outcome_unknown", %{"provider" => "synthetic-fixture"}}
        "non_started" -> {"issuer_quiescent", %{"quiescence_epoch" => "writer-epoch-fr08a"}}
        _ -> {"delivered", %{"provider" => "synthetic-fixture"}}
      end

    %{
      "type" => "settle_claim",
      "claim_id" => @claim,
      "receipt_id" => receipt_id,
      "request_id" => @request,
      "outcome" => outcome,
      "proof" => proof,
      "payload" => payload
    }
  end

  defp state({gateway, capability}) do
    fact = fn query ->
      assert {:ok, fact} = Gateway.protected_query(gateway, capability, query)
      fact
    end

    claim = fact.(q("claim", "claim_id", @claim))

    ledger =
      fact.(%{
        "schema_version" => 1,
        "type" => "ledger",
        "ledger_id" => "root",
        "generation" => 0
      })

    %{
      claim: claim["status"],
      claim_revision: claim["revision"],
      effect: fact.(q("effect", "effect_id", @effect))["status"],
      reservation: fact.(q("reservation", "reservation_id", @reservation))["status"],
      ledger: Map.take(ledger, ~w(status available held consumed retired))
    }
  end

  defp q(type, key, value), do: %{"schema_version" => 1, "type" => type, key => value}

  # Same as current!/4 in protected_primitives_test.exs: empty read set, then the
  # revisions the store says it needs.
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

  # seed_observation_effect!/4 from protected_primitives_test.exs, then issued.
  defp seed_issued!(gw) do
    steps = [
      {"SEED-POLICY",
       %{
         "type" => "set_policy",
         "policy_id" => "policy-1",
         "value" => %{"allowed_operations" => ["launch"], "allowed_scopes" => ["ticket:T-Q3"]}
       }},
      {"SEED-CONTROL",
       %{"type" => "set_control", "control_id" => "control-1", "value" => %{"status" => "active"}}},
      {"SEED-LEDGER",
       %{
         "type" => "grant_ledger",
         "ledger_id" => "root",
         "generation" => 0,
         "dimension" => "starts.developer",
         "units" => 1
       }},
      {"SEED-RESERVE",
       %{
         "type" => "reserve",
         "reservation_id" => @reservation,
         "ledger_id" => "root",
         "generation" => 0,
         "owner_kind" => "effect",
         "owner_id" => @effect,
         "units" => 1
       }},
      {"SEED-EFFECT",
       %{
         "type" => "create_effect",
         "effect_id" => @effect,
         "request" => %{"request_id" => @request, "role" => "developer", "profile" => "sol"},
         "operation" => "launch",
         "scope" => "ticket:T-Q3",
         "ticket_id" => "T-Q3",
         "attempt_id" => "attempt-observation",
         "execution_id" => "execution-observation",
         "policy_id" => "policy-1",
         "policy_revision" => 0,
         "control_id" => "control-1",
         "control_revision" => 0,
         "reservation_ids" => [@reservation],
         "leases" => [%{"lease_id" => "lease-observation", "resource_id" => "slot-observation"}]
       }},
      {"SEED-CLAIM",
       %{
         "type" => "claim_effect",
         "effect_id" => @effect,
         "claim_id" => @claim,
         "writer_epoch" => "writer-epoch-fr08a"
       }},
      {"SEED-ISSUE", issue()}
    ]

    for {id, op} <- steps do
      assert %{"disposition" => "accepted"} = run(gw, id, op), id
    end
  end
end
