defmodule PramanaFoundry.DurableStore.LiveRefusalProbeTest do
  # Commands that should be ordinary refusals but surfaced as storage errors, which flip the
  # live Gateway into recovery mode for every actor. Found by reopen_property_test.exs with
  # FOUNDRY_REOPEN_LIVE=1 on 2026-09-23. Each test asserts the refusal, that the live Gateway
  # is still :ready, and that the store reopens :ready.
  use ExUnit.Case, async: false

  alias PramanaFoundry.DurableStore.Gateway

  setup do
    root =
      Path.join(
        "/private/tmp",
        "live-refusal-#{System.pid()}-#{System.unique_integer([:positive, :monotonic])}"
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
          {"SEED-CONTROL", control("active")},
          {"SEED-LEDGER",
           %{
             "type" => "grant_ledger",
             "ledger_id" => "root",
             "generation" => 0,
             "dimension" => "starts.developer",
             "units" => 3
           }}
        ] do
      assert %{"disposition" => "accepted"} = run(gw, id, op), id
    end

    %{gw: gw, path: path, capability: capability}
  end

  describe "L1: cancelling an effect whose hold was already released" do
    # release_reservation accepts a pending (or claimed) effect's hold. A later cancel, direct
    # or cascaded from set_control, re-released it and failed with
    # {:error, :reservation_release_not_permitted}. The cancel now skips the returned hold,
    # which counts its units once.

    test "set_control cancel_requested cancels a pending effect", ctx do
      pending!(ctx.gw, "1")
      released!(ctx.gw, "1")

      assert %{"disposition" => "accepted"} = run(ctx.gw, "CANCEL", control("cancel_requested"))
      cancelled!(ctx, "1", nil)
    end

    test "cancel_effect unissued cancels a pending effect", ctx do
      pending!(ctx.gw, "1")
      released!(ctx.gw, "1")

      assert %{"disposition" => "accepted"} =
               run(ctx.gw, "CANCEL", %{
                 "type" => "cancel_effect",
                 "effect_id" => "effect-1",
                 "proof" => "unissued"
               })

      cancelled!(ctx, "1", nil)
    end

    test "set_control cancel_requested cancels a claimed effect", ctx do
      claimed!(ctx.gw, "1")
      released!(ctx.gw, "1")

      assert %{"disposition" => "accepted"} = run(ctx.gw, "CANCEL", control("cancel_requested"))
      cancelled!(ctx, "1", "cancelled")
    end
  end

  test "L2: claim_effect reusing another effect's claim_id is refused", ctx do
    claimed!(ctx.gw, "1")
    pending!(ctx.gw, "2")

    assert %{"disposition" => "rejected", "reason_code" => "claim_id_in_use"} =
             run(ctx.gw, "CLAIM-2", claim("2", "1"))

    ready!(ctx.gw)
    assert fact(ctx.gw, "effect", "effect-2")["status"] == "pending"
    assert fact(ctx.gw, "claim", "claim-1")["effect_id"] == "effect-1"
    reopen!(ctx)
  end

  test "L3: the same unknown observation under a second receipt_id is refused", ctx do
    claimed!(ctx.gw, "1")
    assert %{"disposition" => "accepted"} = run(ctx.gw, "ISSUE-1", issue("1"))
    assert %{"disposition" => "accepted"} = run(ctx.gw, "R-A", unknown("1", "receipt-a"))

    assert %{"disposition" => "rejected", "reason_code" => "duplicate_receipt_observation"} =
             run(ctx.gw, "R-B", unknown("1", "receipt-b"))

    ready!(ctx.gw)
    assert fact(ctx.gw, "claim", "claim-1")["status"] == "unknown"
    reopen!(ctx)
  end

  # Found by the class grep, not the generator: create_effect checked each lease spec against
  # root_leases but not against the other specs, so the claim's insert failed.
  describe "L4: an effect naming one lease or resource twice is refused" do
    for {name, leases} <- [
          {"lease_id",
           [
             %{"lease_id" => "lease-1", "resource_id" => "slot-a"},
             %{"lease_id" => "lease-1", "resource_id" => "slot-b"}
           ]},
          {"resource_id",
           [
             %{"lease_id" => "lease-a", "resource_id" => "slot-1"},
             %{"lease_id" => "lease-b", "resource_id" => "slot-1"}
           ]}
        ] do
      @leases leases
      test "a repeated #{name}", ctx do
        assert %{"disposition" => "accepted"} = run(ctx.gw, "RESERVE-1", reserve("1"))
        op = Map.put(effect_op("1"), "leases", @leases)

        assert %{"disposition" => "rejected", "reason_code" => "lease_conflict"} =
                 run(ctx.gw, "EFFECT-1", op)

        ready!(ctx.gw)
        reopen!(ctx)
      end
    end
  end

  defp released!(gw, n) do
    assert %{"disposition" => "accepted"} = run(gw, "RELEASE-" <> n, release(n))
    ready!(gw)
  end

  # The cancel is accepted, the hold's unit is back in the ledger exactly once, and the
  # store is :ready live and after reopen.
  defp cancelled!(ctx, n, claim_status) do
    ready!(ctx.gw)
    assert fact(ctx.gw, "effect", "effect-" <> n)["status"] == "cancelled"
    assert fact(ctx.gw, "reservation", "reservation-" <> n)["status"] == "released"

    if claim_status,
      do: assert(fact(ctx.gw, "claim", "claim-" <> n)["status"] == claim_status)

    ctx = reopen!(ctx)
    assert %{"available" => 3, "held" => 0} = ledger(ctx.gw)
  end

  defp ledger({gateway, capability}) do
    assert {:ok, fact} =
             Gateway.protected_query(gateway, capability, %{
               "schema_version" => 1,
               "type" => "ledger",
               "ledger_id" => "root",
               "generation" => 0
             })

    fact
  end

  defp ready!({gateway, _capability}),
    do: assert(%{mode: :ready, reason: nil} = Gateway.status(gateway))

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

    ready!({gateway, ctx.capability})
    %{ctx | gw: {gateway, ctx.capability}}
  end

  defp pending!(gw, n) do
    steps = [
      {"RESERVE-" <> n, reserve(n)},
      {"EFFECT-" <> n, effect_op(n)}
    ]

    for {id, op} <- steps do
      assert %{"disposition" => "accepted"} = run(gw, id, op), id
    end
  end

  defp reserve(n),
    do: %{
      "type" => "reserve",
      "reservation_id" => "reservation-" <> n,
      "ledger_id" => "root",
      "generation" => 0,
      "owner_kind" => "effect",
      "owner_id" => "effect-" <> n,
      "units" => 1
    }

  defp effect_op(n),
    do: %{
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
    }

  defp claimed!(gw, n) do
    pending!(gw, n)
    assert %{"disposition" => "accepted"} = run(gw, "CLAIM-" <> n, claim(n, n))
  end

  defp control(status),
    do: %{"type" => "set_control", "control_id" => "control-1", "value" => %{"status" => status}}

  defp release(n),
    do: %{
      "type" => "release_reservation",
      "reservation_id" => "reservation-" <> n,
      "proof" => "unissued"
    }

  defp claim(effect, claim),
    do: %{
      "type" => "claim_effect",
      "effect_id" => "effect-" <> effect,
      "claim_id" => "claim-" <> claim,
      "writer_epoch" => "writer-epoch-fr08a"
    }

  defp issue(n),
    do: %{
      "type" => "issue_claim",
      "claim_id" => "claim-" <> n,
      "writer_epoch" => "writer-epoch-fr08a"
    }

  defp unknown(n, receipt_id),
    do: %{
      "type" => "settle_claim",
      "claim_id" => "claim-" <> n,
      "receipt_id" => receipt_id,
      "request_id" => "request-" <> n,
      "outcome" => "unknown",
      "proof" => "outcome_unknown",
      "payload" => %{"provider" => "synthetic-fixture"}
    }

  defp fact({gateway, capability}, type, id) do
    assert {:ok, fact} =
             Gateway.protected_query(gateway, capability, %{
               "schema_version" => 1,
               "type" => type,
               "#{type}_id" => id
             })

    fact
  end

  # A storage error is returned as is, so a test can assert it is not one.
  defp run({gateway, capability}, id, operation) do
    case protected(gateway, capability, id <> "-PROBE", %{}, operation) do
      {:ok, %{"reason_code" => "incomplete_read_set"} = first, :committed} ->
        case protected(gateway, capability, id, first["facts"]["required_revisions"], operation) do
          {:ok, result, :committed} -> result
          other -> other
        end

      {:ok, result, :committed} ->
        result

      other ->
        other
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
