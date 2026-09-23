defmodule PramanaFoundry.DurableStore.LedgerRestartProbeTest do
  # spec/ledger/README.md findings 2 and 3: each drove the store, through accepted
  # commands, to a state the restart check (ProtectedPrimitives.validate) refuses. Each
  # test drives the real API to the refusing operation, then reopens the database.
  use ExUnit.Case, async: false

  alias PramanaFoundry.DurableStore.{Database, Gateway}

  setup do
    root =
      Path.join(
        "/private/tmp",
        "ledger-restart-#{System.pid()}-#{System.unique_integer([:positive, :monotonic])}"
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
             "value" => %{"allowed_operations" => ["launch"], "allowed_scopes" => ["ticket:T-L"]}
           }},
          {"SEED-CONTROL",
           %{
             "type" => "set_control",
             "control_id" => "control-1",
             "value" => %{"status" => "active"}
           }},
          {"SEED-LEDGER-A", grant("root-a")},
          {"SEED-LEDGER-B", grant("root-b")}
        ] do
      assert %{"disposition" => "accepted"} = run(gw, id, op), id
    end

    %{gw: gw, path: path}
  end

  test "finding 2: an effect cannot hold reservations on two ledgers", %{gw: gw, path: path} do
    assert %{"disposition" => "accepted"} = run(gw, "R1", reserve("r1", "root-a", "e1"))
    assert %{"disposition" => "accepted"} = run(gw, "R2", reserve("r2", "root-b", "e1"))

    result = run(gw, "E1", effect("e1", ["r1", "r2"]))

    # Without the refusal, closing root-b cancelled e1 and stranded r1's hold on root-a.
    assert %{"disposition" => "accepted"} =
             run(gw, "CLOSE-B", %{
               "type" => "close_generation",
               "ledger_id" => "root-b",
               "generation" => 0
             })

    # Reopen before asserting the refusal, so a red control shows the restart check's verdict.
    assert_reopens(path)

    assert %{"disposition" => "rejected", "reason_code" => "reservation_ledger_mismatch"} =
             result
  end

  test "finding 3: create_effect must activate every proposed reservation it owns",
       %{gw: gw, path: path} do
    assert %{"disposition" => "accepted"} = run(gw, "R1", reserve("r1", "root-a", "e1"))
    assert %{"disposition" => "accepted"} = run(gw, "R2", reserve("r2", "root-a", "e1"))

    result = run(gw, "E1", effect("e1", ["r1"]))
    assert_reopens(path)

    assert %{"disposition" => "rejected", "reason_code" => "unlisted_owned_reservation"} =
             result
  end

  test "finding 3: reserve refuses an owner effect that already exists", %{gw: gw, path: path} do
    assert %{"disposition" => "accepted"} = run(gw, "R1", reserve("r1", "root-a", "e1"))
    assert %{"disposition" => "accepted"} = run(gw, "E1", effect("e1", ["r1"]))

    result = run(gw, "R2", reserve("r2", "root-a", "e1"))
    assert_reopens(path)
    assert %{"disposition" => "rejected", "reason_code" => "reservation_owner_exists"} = result
  end

  # Reopen property F1 (seed 49): reset closes the old generation's delegated subtree, and
  # each closed descendant needs its snapshot in the result or restart refuses the ledger.
  test "a root reset records every closed descendant", %{gw: gw, path: path} do
    assert %{"disposition" => "accepted"} = run(gw, "D1", delegate("root-a", 0, "child-a", 1))

    assert %{"disposition" => "accepted", "facts" => facts} =
             run(gw, "RESET", reset("root-a", nil, nil))

    assert_reopens(path)
    assert [{"child-a", 0, "closed"}, {"root-a", 0, "closed"}] = closed(facts)
  end

  test "a child reset records every closed descendant", %{gw: gw, path: path} do
    assert %{"disposition" => "accepted"} = run(gw, "D1", delegate("root-a", 0, "mid", 1))
    assert %{"disposition" => "accepted"} = run(gw, "D2", delegate("mid", 0, "leaf", 1))

    assert %{"disposition" => "accepted", "facts" => facts} =
             run(gw, "RESET", reset("mid", "root-a", 0))

    assert_reopens(path)
    assert [{"leaf", 0, "closed"}, {"mid", 0, "closed"}] = closed(facts)
  end

  # Reopen property F2 (seed 56): a released reservation still names its owner, so the
  # effect would have to list it; no longer proposed, it cannot be listed, and the id is spent.
  test "create_effect refuses an owner with a released reservation", %{gw: gw, path: path} do
    assert %{"disposition" => "accepted"} = run(gw, "R1", reserve("r1", "root-a", "e1"))

    assert %{"disposition" => "accepted"} =
             run(gw, "REL1", %{
               "type" => "release_reservation",
               "reservation_id" => "r1",
               "proof" => "unissued"
             })

    assert %{"disposition" => "accepted"} = run(gw, "R2", reserve("r2", "root-a", "e1"))

    result = run(gw, "E1", effect("e1", ["r2"]))
    assert_reopens(path)
    assert %{"disposition" => "rejected", "reason_code" => "unlisted_owned_reservation"} = result
  end

  defp closed(facts),
    do:
      facts["ledgers"]
      |> Enum.map(&{&1["ledger_id"], &1["generation"], &1["status"]})
      |> Enum.sort()

  defp delegate(parent, parent_generation, child, units),
    do: %{
      "type" => "delegate_allocation",
      "parent_ledger_id" => parent,
      "parent_generation" => parent_generation,
      "child_ledger_id" => child,
      "child_generation" => 0,
      "dimension" => "starts.developer",
      "units" => units
    }

  defp reset(ledger_id, parent, parent_generation),
    do: %{
      "type" => "reset_generation",
      "ledger_id" => ledger_id,
      "old_generation" => 0,
      "new_generation" => 1,
      "parent_ledger_id" => parent,
      "parent_generation" => parent_generation,
      "units" => 1
    }

  defp assert_reopens(path) do
    stop_supervised!(Gateway)
    assert {:ok, conn} = Database.open(path)
    Database.close(conn)
  end

  defp grant(ledger_id),
    do: %{
      "type" => "grant_ledger",
      "ledger_id" => ledger_id,
      "generation" => 0,
      "dimension" => "starts.developer",
      "units" => 2
    }

  defp reserve(id, ledger_id, owner),
    do: %{
      "type" => "reserve",
      "reservation_id" => id,
      "ledger_id" => ledger_id,
      "generation" => 0,
      "owner_kind" => "effect",
      "owner_id" => owner,
      "units" => 1
    }

  defp effect(id, reservation_ids),
    do: %{
      "type" => "create_effect",
      "effect_id" => id,
      "request" => %{"request_id" => "request-" <> id, "role" => "developer"},
      "operation" => "launch",
      "scope" => "ticket:T-L",
      "ticket_id" => "T-L",
      "attempt_id" => "attempt-l",
      "execution_id" => "execution-" <> id,
      "policy_id" => "policy-1",
      "policy_revision" => 0,
      "control_id" => "control-1",
      "control_revision" => 0,
      "reservation_ids" => reservation_ids,
      "leases" => []
    }

  # Empty read set first, then the revisions the store says it needs.
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
