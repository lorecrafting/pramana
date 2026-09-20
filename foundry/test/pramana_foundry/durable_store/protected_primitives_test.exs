defmodule PramanaFoundry.DurableStore.ProtectedPrimitivesTest do
  use ExUnit.Case, async: false

  alias PramanaFoundry.DurableStore.Gateway
  alias Exqlite.Sqlite3
  alias PramanaFoundry.DurableStore.{Authority, Database}

  setup do
    root =
      Path.join(
        canonical_tmp(),
        "protected-primitives-#{System.pid()}-#{System.unique_integer([:positive, :monotonic])}"
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
    %{gateway: gateway, capability: capability, path: path}
  end

  test "capability authentication, complete CAS, inbox sealing and late evidence survive restart",
       %{
         gateway: gateway,
         capability: capability,
         path: path
       } do
    policy = %{
      "type" => "set_policy",
      "policy_id" => "policy-1",
      "value" => %{
        "allowed_operations" => ["launch"],
        "allowed_scopes" => ["ticket:T1"]
      }
    }

    assert {:error, :unauthorized_protected_operation} =
             Gateway.protected_command(
               gateway,
               make_ref(),
               "operator",
               command("P-UNAUTH", %{"policy/policy-1" => "absent"}, policy)
             )

    assert {:ok, accepted, :committed} =
             protected(
               gateway,
               capability,
               "P-1",
               %{"policy/policy-1" => "absent"},
               policy
             )

    assert accepted["disposition"] == "accepted"

    assert {:ok, ^accepted, :idempotent} =
             protected(
               gateway,
               capability,
               "P-1",
               %{"policy/policy-1" => "absent"},
               policy
             )

    assert {:error, :idempotency_conflict} =
             Gateway.protected_command(
               gateway,
               capability,
               "different-actor",
               command("P-1", %{"policy/policy-1" => "absent"}, policy)
             )

    changed_policy = put_in(policy["value"]["allowed_operations"], ["launch", "prompt"])

    assert {:ok, rejected, :committed} =
             protected(
               gateway,
               capability,
               "P-STALE",
               %{"policy/policy-1" => "absent"},
               changed_policy
             )

    assert rejected["disposition"] == "rejected"
    assert rejected["reason_code"] == "stale_read_set"

    append_result = %{
      "type" => "append_inbox",
      "execution_id" => "execution-1",
      "sequence" => 1,
      "item_kind" => "result",
      "payload" => %{"candidate_id" => "candidate-1"}
    }

    assert {:ok, _, :committed} =
             protected(
               gateway,
               capability,
               "I-1",
               %{"inbox/execution-1" => "absent"},
               append_result
             )

    append_exit = %{
      "type" => "append_inbox",
      "execution_id" => "execution-1",
      "sequence" => 2,
      "item_kind" => "exit",
      "payload" => %{"status" => 1}
    }

    assert {:ok, _, :committed} =
             protected(
               gateway,
               capability,
               "I-2",
               %{"inbox/execution-1" => 0},
               append_exit
             )

    seal = %{"type" => "seal_inbox", "execution_id" => "execution-1", "last_sequence" => 2}

    assert {:ok, _, :committed} =
             protected(
               gateway,
               capability,
               "I-SEAL",
               %{"inbox/execution-1" => 1},
               seal
             )

    late = %{
      "type" => "append_inbox",
      "execution_id" => "execution-1",
      "sequence" => 3,
      "item_kind" => "result",
      "payload" => %{"candidate_id" => "too-late"}
    }

    assert {:ok, _, :committed} =
             protected(
               gateway,
               capability,
               "I-LATE",
               %{"inbox/execution-1" => 2},
               late
             )

    assert {:ok, inbox} =
             Gateway.protected_query(gateway, capability, %{
               "schema_version" => 1,
               "type" => "inbox",
               "execution_id" => "execution-1"
             })

    assert inbox["sealed_sequence"] == 2
    assert inbox["last_sequence"] == 3

    assert inbox["resolution"] == %{
             "status" => "result",
             "sequence" => 1,
             "payload" => %{"candidate_id" => "candidate-1"}
           }

    assert List.last(inbox["items"])["disposition"] == "late"

    assert {:ok, snapshot} = Gateway.protected_snapshot(gateway, capability)
    assert snapshot["installation_id"] == "installation-fr08a"
    assert snapshot["repository_id"] == "repository-fr08a"
    assert snapshot["writer_epoch"] == "writer-epoch-fr08a"
    assert snapshot["last_protected_command_sequence"] == 6

    assert snapshot["pointers"]["selected_deployment"]["producer_status"] == "absent"

    stop_supervised!(Gateway)

    restarted =
      start_supervised!(
        {Gateway,
         path: path, protected_capability: capability, writer_epoch: "writer-epoch-after-restart"},
        id: :restarted_gateway
      )

    assert {:ok, ^inbox} =
             Gateway.protected_query(restarted, capability, %{
               "schema_version" => 1,
               "type" => "inbox",
               "execution_id" => "execution-1"
             })
  end

  test "parent-funded ledger, claims, leases and settlement conserve authority", %{
    gateway: gateway,
    capability: capability,
    path: path
  } do
    seed_policy_and_control(gateway, capability)

    grant = %{
      "type" => "grant_ledger",
      "ledger_id" => "objective",
      "generation" => 0,
      "dimension" => "starts.developer",
      "units" => 5
    }

    assert {:ok, _, :committed} =
             protected(
               gateway,
               capability,
               "L-GRANT",
               %{"ledger/objective/0" => "absent"},
               grant
             )

    delegate = %{
      "type" => "delegate_allocation",
      "parent_ledger_id" => "objective",
      "parent_generation" => 0,
      "child_ledger_id" => "ticket-T1",
      "child_generation" => 0,
      "dimension" => "starts.developer",
      "units" => 3
    }

    assert {:ok, _, :committed} =
             protected(
               gateway,
               capability,
               "L-DELEGATE",
               %{"ledger/objective/0" => 0, "ledger/ticket-T1/0" => "absent"},
               delegate
             )

    assert {:ok, rejected, :committed} =
             protected(
               gateway,
               capability,
               "L-MINT",
               %{"ledger/objective/0" => 0, "ledger/minted/0" => "absent"},
               %{delegate | "child_ledger_id" => "minted", "units" => 99}
             )

    assert rejected["reason_code"] == "stale_read_set"

    reserve = %{
      "type" => "reserve",
      "reservation_id" => "reservation-1",
      "ledger_id" => "ticket-T1",
      "generation" => 0,
      "owner_kind" => "effect",
      "owner_id" => "effect-1",
      "units" => 1
    }

    assert {:ok, _, :committed} =
             protected(
               gateway,
               capability,
               "L-RESERVE",
               %{
                 "ledger/ticket-T1/0" => 0,
                 "reservation/reservation-1" => "absent"
               },
               reserve
             )

    effect = %{
      "type" => "create_effect",
      "effect_id" => "effect-1",
      "request" => %{
        "request_id" => "provider-request-1",
        "role" => "developer",
        "profile" => "sol"
      },
      "operation" => "launch",
      "scope" => "ticket:T1",
      "ticket_id" => "T1",
      "attempt_id" => "A1",
      "execution_id" => "X1",
      "policy_id" => "policy-1",
      "policy_revision" => 0,
      "control_id" => "control-1",
      "control_revision" => 0,
      "reservation_ids" => ["reservation-1"],
      "leases" => [%{"lease_id" => "lease-1", "resource_id" => "slot-1"}]
    }

    assert {:ok, missing, :committed} =
             protected(
               gateway,
               capability,
               "E-INCOMPLETE",
               %{
                 "effect/effect-1" => "absent",
                 "policy/policy-1" => 0,
                 "control/control-1" => 0,
                 "reservation/reservation-1" => 1,
                 "lease/lease-1" => "absent"
               },
               effect
             )

    assert missing["reason_code"] == "incomplete_read_set"

    assert {:ok, create_result, :committed} =
             protected(
               gateway,
               capability,
               "E-CREATE",
               %{
                 "effect/effect-1" => "absent",
                 "policy/policy-1" => 0,
                 "control/control-1" => 0,
                 "reservation/reservation-1" => 0,
                 "ledger/ticket-T1/0" => 0,
                 "lease/lease-1" => "absent"
               },
               effect
             )

    assert create_result["disposition"] == "accepted", inspect(create_result)

    claim = %{
      "type" => "claim_effect",
      "effect_id" => "effect-1",
      "claim_id" => "claim-1",
      "writer_epoch" => "writer-epoch-fr08a"
    }

    assert {:ok, claim_result, :committed} =
             protected(
               gateway,
               capability,
               "E-CLAIM",
               %{
                 "effect/effect-1" => 0,
                 "claim/claim-1" => "absent",
                 "reservation/reservation-1" => 1,
                 "ledger/ticket-T1/0" => 1,
                 "policy/policy-1" => 0,
                 "control/control-1" => 0,
                 "lease/lease-1" => "absent"
               },
               claim
             )

    assert claim_result["disposition"] == "accepted", inspect(claim_result)

    issue = %{
      "type" => "issue_claim",
      "claim_id" => "claim-1",
      "writer_epoch" => "writer-epoch-fr08a"
    }

    assert {:ok, issue_result, :committed} =
             protected(
               gateway,
               capability,
               "E-ISSUE",
               %{
                 "claim/claim-1" => 0,
                 "effect/effect-1" => 1,
                 "policy/policy-1" => 0,
                 "control/control-1" => 0,
                 "reservation/reservation-1" => 2,
                 "ledger/ticket-T1/0" => 1,
                 "lease/lease-1" => 0
               },
               issue
             )

    assert issue_result["disposition"] == "accepted", inspect(issue_result)

    cancel_after_issue = %{
      "type" => "cancel_effect",
      "effect_id" => "effect-1",
      "proof" => "control_ack"
    }

    assert {:ok, cancel_result, :committed} =
             protected(
               gateway,
               capability,
               "E-CANCEL",
               %{
                 "effect/effect-1" => 2,
                 "policy/policy-1" => 0,
                 "control/control-1" => 0,
                 "claim/claim-1" => 1,
                 "reservation/reservation-1" => 3,
                 "ledger/ticket-T1/0" => 1,
                 "lease/lease-1" => 0
               },
               cancel_after_issue
             )

    assert cancel_result["disposition"] == "accepted", inspect(cancel_result)
    assert cancel_result["facts"]["outstanding_claim_ids"] == ["claim-1"]

    settle = %{
      "type" => "settle_claim",
      "claim_id" => "claim-1",
      "receipt_id" => "receipt-1",
      "request_id" => "provider-request-1",
      "outcome" => "succeeded",
      "proof" => "delivered",
      "payload" => %{"provider" => "synthetic-fixture"}
    }

    settle_reads = %{
      "claim/claim-1" => 1,
      "effect/effect-1" => 2,
      "policy/policy-1" => 0,
      "control/control-1" => 0,
      "reservation/reservation-1" => 3,
      "ledger/ticket-T1/0" => 1,
      "lease/lease-1" => 0,
      "receipt/receipt-1" => "absent"
    }

    assert {:ok, settled, :committed} =
             protected(gateway, capability, "E-SETTLE", settle_reads, settle)

    assert settled["facts"]["claim"]["status"] == "succeeded"

    assert {:ok, ledger} =
             Gateway.protected_query(gateway, capability, %{
               "schema_version" => 1,
               "type" => "ledger",
               "ledger_id" => "ticket-T1",
               "generation" => 0
             })

    assert ledger["authorized"] == 3
    assert ledger["available"] == 2
    assert ledger["held"] == 0
    assert ledger["consumed"] == 1

    assert ledger["authorized"] ==
             ledger["available"] + ledger["held"] + ledger["consumed"] +
               ledger["delegated"] + ledger["retired"]

    assert {:ok, ^settled, :idempotent} =
             protected(gateway, capability, "E-SETTLE", settle_reads, settle)

    conflict = %{settle | "outcome" => "failed"}

    assert {:ok, conflict_result, :committed} =
             protected(
               gateway,
               capability,
               "E-CONFLICT",
               %{
                 "claim/claim-1" => 2,
                 "effect/effect-1" => 3,
                 "policy/policy-1" => 0,
                 "control/control-1" => 0,
                 "reservation/reservation-1" => 4,
                 "ledger/ticket-T1/0" => 2,
                 "lease/lease-1" => 1,
                 "receipt/receipt-1" => 0
               },
               conflict
             )

    assert conflict_result["disposition"] == "rejected"
    assert conflict_result["reason_code"] == "conflicting_receipt"

    assert {:ok, effect_fact} =
             Gateway.protected_query(gateway, capability, %{
               "schema_version" => 1,
               "type" => "effect",
               "effect_id" => "effect-1"
             })

    assert effect_fact["status"] == "reconciliation_required"

    assert {:ok, unchanged_ledger} =
             Gateway.protected_query(gateway, capability, %{
               "schema_version" => 1,
               "type" => "ledger",
               "ledger_id" => "ticket-T1",
               "generation" => 0
             })

    assert unchanged_ledger["consumed"] == 1
    assert unchanged_ledger["available"] == 2

    stop_supervised!(Gateway)

    restarted =
      start_supervised!(
        {Gateway,
         path: path, protected_capability: capability, writer_epoch: "writer-epoch-fr08a"},
        id: :settled_restart
      )

    assert %{mode: :ready} = Gateway.status(restarted)

    assert {:ok, %{"status" => "reconciliation_required"}} =
             Gateway.protected_query(
               restarted,
               capability,
               query("effect", "effect_id", "effect-1")
             )
  end

  test "accepted v1-shaped stores migrate additively and rerun without changing legacy content",
       %{
         gateway: _gateway,
         capability: capability,
         path: path
       } do
    assert {:ok, before_conn} = Database.open(path)
    assert {:ok, before_content} = Authority.content(before_conn)
    assert :ok = Database.close(before_conn)

    legacy_tables =
      ~w(inputs commands command_results events projections effects ledger_generations claims reservations receipts leases policy_revisions control_revisions artifact_references import_runs legacy_records sqlite_sequence)

    legacy_before = Map.take(before_content, legacy_tables)
    stop_supervised!(Gateway)

    assert {:ok, raw} = Sqlite3.open(path, mode: :readwrite)
    assert :ok = Sqlite3.execute(raw, "PRAGMA foreign_keys = OFF")

    for table <-
          ~w(root_infrastructure_settlements durable_operations atomic_bundles root_leases root_receipts root_reservations root_claims root_effects root_ledgers root_control_history root_controls root_policy_history root_policies authenticated_inbox_items authenticated_inboxes root_pointers root_commands) do
      assert :ok = Sqlite3.execute(raw, "DROP TABLE #{table}")
    end

    assert :ok =
             Database.execute(
               raw,
               "DELETE FROM metadata WHERE key IN ('protected_schema_version', 'migration_fr08a_v1', 'migration_atomic_bundle_v2')"
             )

    assert :ok = Sqlite3.close(raw)

    assert :ok = Gateway.migrate(path)
    assert :ok = Gateway.migrate(path)

    assert {:ok, after_conn} = Database.open(path)
    assert {:ok, after_content} = Authority.content(after_conn)
    assert Map.take(after_content, legacy_tables) == legacy_before
    assert :ok = Database.close(after_conn)

    migrated =
      start_supervised!(
        {Gateway,
         path: path, protected_capability: capability, writer_epoch: "writer-after-migration"},
        id: :migrated_gateway
      )

    assert {:ok, snapshot} = Gateway.protected_snapshot(migrated, capability)
    assert snapshot["protected_schema_version"] == "2"
    assert snapshot["pointers"]["accepted_source"]["producer_status"] == "absent"
  end

  test "reset closes an allocation, revokes unissued authority and parent-funds the new generation",
       %{gateway: gateway, capability: capability} do
    seed_policy_and_control(gateway, capability)

    accept!(gateway, capability, "R-GRANT", %{"ledger/objective/0" => "absent"}, %{
      "type" => "grant_ledger",
      "ledger_id" => "objective",
      "generation" => 0,
      "dimension" => "starts.developer",
      "units" => 5
    })

    accept!(
      gateway,
      capability,
      "R-DELEGATE",
      %{"ledger/objective/0" => 0, "ledger/ticket-reset/0" => "absent"},
      %{
        "type" => "delegate_allocation",
        "parent_ledger_id" => "objective",
        "parent_generation" => 0,
        "child_ledger_id" => "ticket-reset",
        "child_generation" => 0,
        "dimension" => "starts.developer",
        "units" => 3
      }
    )

    accept!(
      gateway,
      capability,
      "R-RESERVE",
      %{"ledger/ticket-reset/0" => 0, "reservation/reset-reservation" => "absent"},
      %{
        "type" => "reserve",
        "reservation_id" => "reset-reservation",
        "ledger_id" => "ticket-reset",
        "generation" => 0,
        "owner_kind" => "effect",
        "owner_id" => "reset-effect",
        "units" => 2
      }
    )

    effect = %{
      "type" => "create_effect",
      "effect_id" => "reset-effect",
      "request" => %{
        "request_id" => "reset-provider-request",
        "role" => "developer",
        "profile" => "sol"
      },
      "operation" => "launch",
      "scope" => "ticket:T1",
      "ticket_id" => "T1",
      "attempt_id" => "RESET-A1",
      "execution_id" => "RESET-X1",
      "policy_id" => "policy-1",
      "policy_revision" => 0,
      "control_id" => "control-1",
      "control_revision" => 0,
      "reservation_ids" => ["reset-reservation"],
      "leases" => [%{"lease_id" => "reset-lease", "resource_id" => "reset-slot"}]
    }

    accept!(
      gateway,
      capability,
      "R-EFFECT",
      %{
        "effect/reset-effect" => "absent",
        "policy/policy-1" => 0,
        "control/control-1" => 0,
        "reservation/reset-reservation" => 0,
        "ledger/ticket-reset/0" => 0,
        "lease/reset-lease" => "absent"
      },
      effect
    )

    accept!(
      gateway,
      capability,
      "R-CLAIM",
      %{
        "effect/reset-effect" => 0,
        "claim/reset-claim" => "absent",
        "reservation/reset-reservation" => 1,
        "ledger/ticket-reset/0" => 1,
        "policy/policy-1" => 0,
        "control/control-1" => 0,
        "lease/reset-lease" => "absent"
      },
      %{
        "type" => "claim_effect",
        "effect_id" => "reset-effect",
        "claim_id" => "reset-claim",
        "writer_epoch" => "writer-epoch-fr08a"
      }
    )

    reset = %{
      "type" => "reset_generation",
      "ledger_id" => "ticket-reset",
      "old_generation" => 0,
      "new_generation" => 1,
      "parent_ledger_id" => "objective",
      "parent_generation" => 0,
      "units" => 1
    }

    assert {:ok, incomplete, :committed} =
             protected(
               gateway,
               capability,
               "R-RESET-INCOMPLETE",
               %{
                 "ledger/ticket-reset/0" => 1,
                 "ledger/ticket-reset/1" => "absent",
                 "ledger/objective/0" => 1
               },
               reset
             )

    assert incomplete["reason_code"] == "incomplete_read_set"

    accept!(
      gateway,
      capability,
      "R-RESET",
      %{
        "ledger/ticket-reset/0" => 1,
        "ledger/ticket-reset/1" => "absent",
        "ledger/objective/0" => 1,
        "reservation/reset-reservation" => 2,
        "effect/reset-effect" => 1,
        "claim/reset-claim" => 0,
        "policy/policy-1" => 0,
        "control/control-1" => 0,
        "lease/reset-lease" => 0
      },
      reset
    )

    assert {:ok, old} =
             Gateway.protected_query(gateway, capability, ledger_query("ticket-reset", 0))

    assert {:ok, fresh} =
             Gateway.protected_query(gateway, capability, ledger_query("ticket-reset", 1))

    assert {:ok, claim} =
             Gateway.protected_query(
               gateway,
               capability,
               query("claim", "claim_id", "reset-claim")
             )

    assert {:ok, effect_fact} =
             Gateway.protected_query(
               gateway,
               capability,
               query("effect", "effect_id", "reset-effect")
             )

    assert {:ok, lease} =
             Gateway.protected_query(
               gateway,
               capability,
               query("lease", "lease_id", "reset-lease")
             )

    assert old["status"] == "closed"
    assert old["available"] == 0
    assert old["held"] == 0
    assert old["retired"] == 3
    assert fresh["status"] == "open"
    assert fresh["authorized"] == 1
    assert fresh["available"] == 1
    assert claim["status"] == "cancelled"
    assert effect_fact["status"] == "cancelled"
    assert lease["status"] == "released"

    accept!(
      gateway,
      capability,
      "R-RETURN",
      %{"ledger/ticket-reset/1" => 0, "ledger/objective/0" => 2},
      %{
        "type" => "return_allocation",
        "child_ledger_id" => "ticket-reset",
        "child_generation" => 1,
        "units" => 1
      }
    )

    assert {:ok, returned} =
             Gateway.protected_query(gateway, capability, ledger_query("ticket-reset", 1))

    assert returned["authorized"] == 0
    assert returned["available"] == 0
  end

  test "effect observation query is capability-bound, paginated and stale after any append", %{
    gateway: gateway,
    capability: capability
  } do
    seed_observation_effect!(gateway, capability, "ticket-observation")

    request = effect_observation_query("effect-observation", 1, 8_192)

    assert {:error, :unauthorized_protected_operation} =
             Gateway.protected_query(gateway, make_ref(), request)

    assert {:ok, first} = Gateway.protected_query(gateway, capability, request)
    assert first["effect"]["effect_id"] == "effect-observation"
    assert first["infrastructure_settlement"] == nil
    assert first["settlement"]["receipt_history"] == "complete"
    assert [%{"kind" => "claim", "claim_id" => "claim-observation"}] = first["relations"]
    assert first["page"]["truncated"]
    assert first["page"]["truncated_reason"] == "item_limit"
    assert first["page"]["size_bytes"] <= 8_192

    cursor = first["page"]["next_cursor"]
    refute inspect(cursor) =~ "effect-observation"
    refute inspect(cursor) =~ "ticket-observation"

    assert {:ok, second} =
             Gateway.protected_query(gateway, capability, %{request | "cursor" => cursor})

    assert [%{"kind" => "reservation", "reservation_id" => "reservation-observation"}] =
             second["relations"]

    assert {:ok, third} =
             Gateway.protected_query(gateway, capability, %{
               request
               | "cursor" => second["page"]["next_cursor"]
             })

    assert [%{"kind" => "lease", "lease_id" => "lease-observation"}] = third["relations"]
    assert third["page"]["next_cursor"] == nil
    assert third["settlement"]["receipt_history"] == "complete"

    assert {:error, :invalid_protected_query} =
             Gateway.protected_query(gateway, capability, %{
               request
               | "cursor" => Map.put(cursor, "section", "root_claims")
             })

    assert {:error, :invalid_protected_query} =
             Gateway.protected_query(gateway, capability, %{
               request
               | "cursor" => Map.put(cursor, "scope_digest", String.duplicate("0", 64))
             })

    assert {:error, :stale_protected_cursor} =
             Gateway.protected_query(gateway, capability, %{
               request
               | "cursor" => Map.put(cursor, "source_digest", String.duplicate("0", 64))
             })

    accept!(gateway, capability, "OBS-CONTROL-UPDATE", %{"control/control-1" => 0}, %{
      "type" => "set_control",
      "control_id" => "control-1",
      "value" => %{"status" => "active", "revision_note" => "append"}
    })

    assert {:error, :stale_protected_cursor} =
             Gateway.protected_query(gateway, capability, %{request | "cursor" => cursor})
  end

  test "effect observation rejects oversized scalar before returning protected data", %{
    gateway: gateway,
    capability: capability
  } do
    secret_ticket = "sk-" <> String.duplicate("a", 300)
    seed_observation_effect!(gateway, capability, secret_ticket, claim?: false)

    assert {:error, :protected_observation_oversized} =
             Gateway.protected_query(
               gateway,
               capability,
               effect_observation_query("effect-observation", 20, 8_192)
             )
  end

  test "effect observation cursor survives clean reopen and verified backup but not another source",
       %{
         gateway: gateway,
         capability: capability,
         path: path
       } do
    seed_observation_effect!(gateway, capability, "ticket-observation")
    request = effect_observation_query("effect-observation", 1, 8_192)
    assert {:ok, first} = Gateway.protected_query(gateway, capability, request)
    cursor = first["page"]["next_cursor"]

    backup = Path.join(Path.dirname(path), "bounded-observation-backup.sqlite3")
    assert {:ok, _evidence} = Gateway.backup(gateway, backup)

    stop_supervised!(Gateway)

    reopened =
      start_supervised!(
        {Gateway,
         path: path, protected_capability: capability, writer_epoch: "writer-epoch-reopened"},
        id: :bounded_observation_reopened
      )

    assert {:ok, reopened_page} =
             Gateway.protected_query(reopened, capability, %{request | "cursor" => cursor})

    assert [%{"kind" => "reservation"}] = reopened_page["relations"]
    stop_supervised!(:bounded_observation_reopened)

    copied =
      start_supervised!(
        {Gateway,
         path: backup, protected_capability: capability, writer_epoch: "writer-epoch-backup"},
        id: :bounded_observation_backup
      )

    assert {:ok, backup_page} =
             Gateway.protected_query(copied, capability, %{request | "cursor" => cursor})

    assert backup_page["relations"] == reopened_page["relations"]
    stop_supervised!(:bounded_observation_backup)

    assert {:ok, raw} = Sqlite3.open(backup, mode: :readwrite)

    assert :ok =
             Sqlite3.execute(
               raw,
               "UPDATE metadata SET value = 'repository-other' WHERE key = 'repository_id'"
             )

    assert :ok = Sqlite3.close(raw)

    other_source =
      start_supervised!(
        {Gateway,
         path: backup, protected_capability: capability, writer_epoch: "writer-epoch-other"},
        id: :bounded_observation_other_source
      )

    assert {:error, :stale_protected_cursor} =
             Gateway.protected_query(other_source, capability, %{request | "cursor" => cursor})
  end

  defp seed_policy_and_control(gateway, capability) do
    assert {:ok, _, :committed} =
             protected(
               gateway,
               capability,
               "SEED-POLICY",
               %{"policy/policy-1" => "absent"},
               %{
                 "type" => "set_policy",
                 "policy_id" => "policy-1",
                 "value" => %{
                   "allowed_operations" => ["launch"],
                   "allowed_scopes" => ["ticket:T1"]
                 }
               }
             )

    assert {:ok, _, :committed} =
             protected(
               gateway,
               capability,
               "SEED-CONTROL",
               %{"control/control-1" => "absent"},
               %{
                 "type" => "set_control",
                 "control_id" => "control-1",
                 "value" => %{"status" => "active"}
               }
             )
  end

  defp seed_observation_effect!(gateway, capability, ticket_id, opts \\ []) do
    accept!(gateway, capability, "SEED-POLICY", %{"policy/policy-1" => "absent"}, %{
      "type" => "set_policy",
      "policy_id" => "policy-1",
      "value" => %{
        "allowed_operations" => ["launch"],
        "allowed_scopes" => ["ticket:#{ticket_id}"]
      }
    })

    accept!(gateway, capability, "SEED-CONTROL", %{"control/control-1" => "absent"}, %{
      "type" => "set_control",
      "control_id" => "control-1",
      "value" => %{"status" => "active"}
    })

    accept!(gateway, capability, "OBS-LEDGER", %{"ledger/root/0" => "absent"}, %{
      "type" => "grant_ledger",
      "ledger_id" => "root",
      "generation" => 0,
      "dimension" => "starts.developer",
      "units" => 1
    })

    accept!(
      gateway,
      capability,
      "OBS-RESERVATION",
      %{"ledger/root/0" => 0, "reservation/reservation-observation" => "absent"},
      %{
        "type" => "reserve",
        "reservation_id" => "reservation-observation",
        "ledger_id" => "root",
        "generation" => 0,
        "owner_kind" => "effect",
        "owner_id" => "effect-observation",
        "units" => 1
      }
    )

    accept!(
      gateway,
      capability,
      "OBS-EFFECT",
      %{
        "effect/effect-observation" => "absent",
        "policy/policy-1" => 0,
        "control/control-1" => 0,
        "reservation/reservation-observation" => 0,
        "ledger/root/0" => 0,
        "lease/lease-observation" => "absent"
      },
      %{
        "type" => "create_effect",
        "effect_id" => "effect-observation",
        "request" => %{
          "request_id" => "request-observation",
          "role" => "developer",
          "profile" => "sol"
        },
        "operation" => "launch",
        "scope" => "ticket:#{ticket_id}",
        "ticket_id" => ticket_id,
        "attempt_id" => "attempt-observation",
        "execution_id" => "execution-observation",
        "policy_id" => "policy-1",
        "policy_revision" => 0,
        "control_id" => "control-1",
        "control_revision" => 0,
        "reservation_ids" => ["reservation-observation"],
        "leases" => [%{"lease_id" => "lease-observation", "resource_id" => "slot-observation"}]
      }
    )

    if Keyword.get(opts, :claim?, true) do
      accept!(
        gateway,
        capability,
        "OBS-CLAIM",
        %{
          "effect/effect-observation" => 0,
          "claim/claim-observation" => "absent",
          "reservation/reservation-observation" => 1,
          "ledger/root/0" => 1,
          "policy/policy-1" => 0,
          "control/control-1" => 0,
          "lease/lease-observation" => "absent"
        },
        %{
          "type" => "claim_effect",
          "effect_id" => "effect-observation",
          "claim_id" => "claim-observation",
          "writer_epoch" => "writer-epoch-fr08a"
        }
      )
    end
  end

  defp effect_observation_query(effect_id, limit, max_bytes) do
    %{
      "schema_version" => 1,
      "type" => "effect_observation_page",
      "effect_id" => effect_id,
      "limit" => limit,
      "max_bytes" => max_bytes,
      "cursor" => nil
    }
  end

  defp protected(gateway, capability, id, reads, operation) do
    Gateway.protected_command(gateway, capability, "operator", command(id, reads, operation))
  end

  defp accept!(gateway, capability, id, reads, operation) do
    assert {:ok, %{"disposition" => "accepted"} = result, :committed} =
             protected(gateway, capability, id, reads, operation)

    result
  end

  defp query(type, key, value), do: %{"schema_version" => 1, "type" => type, key => value}

  defp ledger_query(id, generation) do
    %{"schema_version" => 1, "type" => "ledger", "ledger_id" => id, "generation" => generation}
  end

  defp command(id, reads, operation) do
    %{
      "schema_version" => 1,
      "command_id" => id,
      "expected_revisions" => reads,
      "operation" => operation
    }
  end

  defp canonical_tmp do
    if File.dir?("/private/tmp"), do: "/private/tmp", else: System.tmp_dir!()
  end
end
