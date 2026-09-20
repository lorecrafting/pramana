defmodule PramanaFoundry.DurableStore.AtomicBundleTest do
  use ExUnit.Case, async: false

  alias Exqlite.Sqlite3
  alias PramanaFoundry.DurableStore.{Authority, Database, Gateway}

  setup do
    root =
      Path.join(
        canonical_tmp(),
        "atomic-bundle-#{System.pid()}-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir!(root)
    path = Path.join(root, "authority.sqlite3")
    capability = make_ref()
    assert :ok = Gateway.initialize(path)

    gateway =
      start_supervised!(
        {Gateway, path: path, protected_capability: capability, writer_epoch: "epoch-A"}
      )

    on_exit(fn -> File.rm_rf!(root) end)
    %{gateway: gateway, capability: capability, path: path}
  end

  test "non-start settlement and domain transition are one idempotent commit", ctx do
    seed_issued_launch!(ctx)
    bundle = nonstart_bundle("atomic-1")

    assert {:ok, result, :committed} =
             Gateway.atomic_bundle(ctx.gateway, ctx.capability, "operator", bundle)

    assert result["disposition"] == "accepted"

    assert [%{"operation_type" => "settle_claim", "result" => protected_result}] =
             result["operations"]

    settlement = protected_result["facts"]["infrastructure_settlement"]
    assert settlement["role"] == "developer"
    assert settlement["work_owner"] == "T1:A1:developer"
    assert settlement["infrastructure_generation"] == 0
    assert settlement["predecessor_effect_id"] == nil
    assert settlement["failure_class"] == "backend_refused_start"
    assert settlement["ordinal"] == 1

    assert {:ok, %{"status" => "non_started"}} = fact(ctx, "claim", "claim_id", "claim-1")

    assert {:ok, %{"status" => "released"}} =
             fact(ctx, "reservation", "reservation_id", "reservation-1")

    assert {:ok, ^result, :idempotent} =
             Gateway.atomic_bundle(ctx.gateway, ctx.capability, "operator", bundle)

    backup = Path.join(Path.dirname(ctx.path), "atomic-backup.sqlite3")
    assert {:ok, %{content: live_content}} = Gateway.backup(ctx.gateway, backup)
    assert live_content["atomic_bundles"].count == 1
    assert live_content["root_infrastructure_settlements"].count == 1
    assert live_content["durable_operations"].count > 1
    assert {:ok, copied} = Database.open(backup)
    assert {:ok, %{content: ^live_content}} = Authority.read(copied, :all)
    assert :ok = Database.close(copied)
  end

  test "developer, reviewer and PM non-start settlements survive reopen", ctx do
    for {role, suffix} <- [{"developer", "dev"}, {"reviewer", "review"}, {"pm", "pm"}] do
      seed_issued_launch!(ctx, role, suffix)

      assert {:ok, result, :committed} =
               Gateway.atomic_bundle(
                 ctx.gateway,
                 ctx.capability,
                 "operator",
                 nonstart_bundle("role-#{suffix}", suffix, role)
               )

      settlement =
        get_in(result, [
          "operations",
          Access.at(0),
          "result",
          "facts",
          "infrastructure_settlement"
        ])

      assert settlement["role"] == role
      assert settlement["work_owner"] == "T#{suffix}:A#{suffix}:#{role}"
    end

    stop_supervised!(Gateway)

    reopened =
      start_supervised!(
        {Gateway, path: ctx.path, protected_capability: ctx.capability, writer_epoch: "epoch-B"},
        id: :role_reopen
      )

    for {_role, suffix} <- [{"developer", "dev"}, {"reviewer", "review"}, {"pm", "pm"}] do
      effect_id = "effect-#{suffix}"

      assert {:ok, %{"effect_id" => ^effect_id, "ordinal" => 1}} =
               Gateway.protected_query(reopened, ctx.capability, %{
                 "schema_version" => 1,
                 "type" => "infrastructure_settlement",
                 "effect_id" => effect_id
               })
    end
  end

  test "a protected rejection rolls back all earlier operations and durably rejects domain work",
       ctx do
    envelope =
      domain_envelope("atomic-reject")
      |> Map.put("operations", [
        %{
          "schema_version" => 1,
          "expected_revisions" => %{"policy/transient" => "absent"},
          "operation" => %{
            "type" => "set_policy",
            "policy_id" => "transient",
            "value" => %{"allowed_operations" => []}
          }
        },
        %{
          "schema_version" => 1,
          "expected_revisions" => %{},
          "operation" => %{
            "type" => "reserve",
            "reservation_id" => "missing-reservation",
            "ledger_id" => "missing-ledger",
            "generation" => 0,
            "owner_kind" => "effect",
            "owner_id" => "missing-effect",
            "units" => 1
          }
        }
      ])

    assert {:ok, result, :rejected} =
             Gateway.atomic_bundle(ctx.gateway, ctx.capability, "operator", envelope)

    assert result["disposition"] == "rejected"
    assert {:error, :policy_not_found} = fact(ctx, "policy", "policy_id", "transient")

    assert {:ok, ^result, :idempotent} =
             Gateway.atomic_bundle(ctx.gateway, ctx.capability, "operator", envelope)

    assert_dependent_stage!(ctx)
  end

  defp assert_dependent_stage!(ctx) do
    accept_current!(ctx, %{
      "type" => "set_policy",
      "policy_id" => "dependent-policy",
      "value" => %{
        "allowed_operations" => ["launch"],
        "allowed_scopes" => ["ticket:dependent"]
      }
    })

    accept_current!(ctx, %{
      "type" => "set_control",
      "control_id" => "dependent-control",
      "value" => %{"status" => "active"}
    })

    accept_current!(ctx, %{
      "type" => "grant_ledger",
      "ledger_id" => "dependent-ledger",
      "generation" => 0,
      "dimension" => "starts.developer",
      "units" => 1
    })

    envelope =
      domain_envelope("dependent-stage")
      |> Map.put("operations", [
        %{
          "schema_version" => 1,
          "expected_revisions" => %{
            "ledger/dependent-ledger/0" => 0,
            "reservation/dependent-reservation" => "absent"
          },
          "operation" => %{
            "type" => "reserve",
            "reservation_id" => "dependent-reservation",
            "ledger_id" => "dependent-ledger",
            "generation" => 0,
            "owner_kind" => "effect",
            "owner_id" => "dependent-effect",
            "units" => 1
          }
        },
        %{
          "schema_version" => 1,
          "expected_revisions" => %{
            "effect/dependent-effect" => "absent",
            "policy/dependent-policy" => 0,
            "control/dependent-control" => 0,
            "reservation/dependent-reservation" => "absent"
          },
          "operation" => %{
            "type" => "create_effect",
            "effect_id" => "dependent-effect",
            "request" => %{
              "request_id" => "dependent-request",
              "role" => "developer",
              "profile" => "sol",
              "phase_generation" => 0,
              "operation_ordinal" => 0
            },
            "operation" => "launch",
            "scope" => "ticket:dependent",
            "ticket_id" => "dependent",
            "attempt_id" => "attempt",
            "execution_id" => "dependent-execution",
            "policy_id" => "dependent-policy",
            "policy_revision" => 0,
            "control_id" => "dependent-control",
            "control_revision" => 0,
            "reservation_ids" => ["dependent-reservation"],
            "leases" => []
          }
        }
      ])

    assert {:ok, %{"disposition" => "accepted", "operations" => operations}, :committed} =
             Gateway.atomic_bundle(ctx.gateway, ctx.capability, "operator", envelope)

    assert Enum.map(operations, & &1["execution_status"]) == ["committed", "committed"]
    assert {:ok, %{"status" => "pending"}} = fact(ctx, "effect", "effect_id", "dependent-effect")

    assert {:ok, %{"status" => "reserved", "revision" => 1}} =
             fact(ctx, "reservation", "reservation_id", "dependent-reservation")
  end

  test "protected, domain and pre-commit failures roll back the complete bundle", ctx do
    stop_supervised!(Gateway)

    for fault <- [:after_protected, :after_domain, :before_commit] do
      path = Path.join(Path.dirname(ctx.path), "#{fault}.sqlite3")
      assert :ok = Gateway.initialize(path)

      gateway =
        start_supervised!(
          {Gateway,
           path: path, protected_capability: ctx.capability, writer_epoch: "epoch-A", fault: fault},
          id: {:fault_gateway, fault}
        )

      envelope = policy_bundle("fault-#{fault}", "policy-#{fault}")

      assert {:error, {:storage_unavailable, _reason}} =
               Gateway.atomic_bundle(gateway, ctx.capability, "operator", envelope)

      stop_supervised!({:fault_gateway, fault})

      reopened =
        start_supervised!(
          {Gateway, path: path, protected_capability: ctx.capability, writer_epoch: "epoch-B"},
          id: {:reopened_gateway, fault}
        )

      assert {:error, :policy_not_found} =
               Gateway.protected_query(reopened, ctx.capability, %{
                 "schema_version" => 1,
                 "type" => "policy",
                 "policy_id" => "policy-#{fault}"
               })

      assert {:error, :not_found} = Gateway.command(reopened, "fault-#{fault}")
      stop_supervised!({:reopened_gateway, fault})
    end
  end

  test "a lost reply after commit reopens to the exact v2 result", ctx do
    stop_supervised!(Gateway)
    envelope = domain_envelope("lost-reply")

    gateway =
      start_supervised!(
        {Gateway,
         path: ctx.path,
         protected_capability: ctx.capability,
         writer_epoch: "epoch-A",
         fault: :after_commit_before_reply},
        id: :lost_reply_gateway
      )

    assert {:error, {:outcome_unknown, "lost-reply"}} =
             Gateway.atomic_bundle(gateway, ctx.capability, "operator", envelope)

    stop_supervised!(:lost_reply_gateway)

    reopened =
      start_supervised!(
        {Gateway, path: ctx.path, protected_capability: ctx.capability, writer_epoch: "epoch-B"},
        id: :lost_reply_reopened
      )

    assert {:ok, result, :idempotent} =
             Gateway.atomic_bundle(reopened, ctx.capability, "operator", envelope)

    assert result["schema_version"] == 2
    assert result["disposition"] == "accepted"
    assert result["command_id"] == "lost-reply"
  end

  test "global identity rejects changed actors, payloads and operation order", ctx do
    first = policy_bundle("identity-1", "policy-A")

    assert {:ok, _result, :committed} =
             Gateway.atomic_bundle(ctx.gateway, ctx.capability, "operator", first)

    changed_payload = put_in(first, ["inputs", "transition_id"], "different")

    assert {:error, :idempotency_conflict} =
             Gateway.atomic_bundle(ctx.gateway, ctx.capability, "operator", changed_payload)

    changed_actor = Map.put(first, "actor_id", "other")

    assert {:error, :idempotency_conflict} =
             Gateway.atomic_bundle(ctx.gateway, ctx.capability, "other", changed_actor)

    reordered =
      domain_envelope("identity-order")
      |> Map.put("operations", [
        %{
          "schema_version" => 1,
          "expected_revisions" => %{"policy/order-policy" => "absent"},
          "operation" => %{
            "type" => "set_policy",
            "policy_id" => "order-policy",
            "value" => %{"allowed_operations" => [], "allowed_scopes" => []}
          }
        },
        %{
          "schema_version" => 1,
          "expected_revisions" => %{"control/order-control" => "absent"},
          "operation" => %{
            "type" => "set_control",
            "control_id" => "order-control",
            "value" => %{"status" => "active"}
          }
        }
      ])

    reversed = Map.update!(reordered, "operations", &Enum.reverse/1)

    assert {:ok, _result, :committed} =
             Gateway.atomic_bundle(ctx.gateway, ctx.capability, "operator", reordered)

    assert {:error, :idempotency_conflict} =
             Gateway.atomic_bundle(ctx.gateway, ctx.capability, "operator", reversed)

    unknown =
      domain_envelope("unknown-op")
      |> Map.put("operations", [
        %{
          "schema_version" => 1,
          "expected_revisions" => %{},
          "operation" => %{"type" => "arbitrary_root_update"}
        }
      ])

    assert {:error, :invalid_atomic_operation} =
             Gateway.atomic_bundle(ctx.gateway, ctx.capability, "operator", unknown)

    assert %{mode: :ready} = Gateway.status(ctx.gateway)
  end

  test "protected v1 history migrates to typed singleton operations and reruns safely", ctx do
    accept_current!(ctx, %{
      "type" => "set_policy",
      "policy_id" => "v1-policy",
      "value" => %{"allowed_operations" => [], "allowed_scopes" => []}
    })

    legacy = domain_envelope("v1-domain")

    assert {:ok, _result, :committed} =
             Gateway.transact(ctx.gateway, "operator", legacy["command"], legacy["proposal"])

    stop_supervised!(Gateway)
    assert {:ok, raw} = Sqlite3.open(ctx.path, mode: :readwrite)
    assert :ok = Sqlite3.execute(raw, "PRAGMA foreign_keys = OFF")

    for table <- ~w(root_infrastructure_settlements durable_operations atomic_bundles) do
      assert :ok = Sqlite3.execute(raw, "DROP TABLE #{table}")
    end

    assert :ok =
             Database.execute(
               raw,
               "UPDATE metadata SET value = '1' WHERE key = 'protected_schema_version'"
             )

    assert :ok =
             Database.execute(
               raw,
               "DELETE FROM metadata WHERE key = 'migration_atomic_bundle_v2'"
             )

    assert :ok = Sqlite3.close(raw)
    assert :ok = Gateway.migrate(ctx.path)
    assert :ok = Gateway.migrate(ctx.path)
    assert {:ok, conn} = Database.open(ctx.path)
    assert {:ok, %{content: content}} = Authority.read(conn, :all)
    assert content["atomic_bundles"].count == 0
    assert content["durable_operations"].count == 3
    assert :ok = Database.close(conn)
  end

  test "duplicate non-start cannot advance infrastructure and conflicting receipt quarantines",
       ctx do
    seed_issued_launch!(ctx)

    assert {:ok, first, :committed} =
             Gateway.atomic_bundle(
               ctx.gateway,
               ctx.capability,
               "operator",
               nonstart_bundle("receipt-first")
             )

    assert get_in(first, [
             "operations",
             Access.at(0),
             "result",
             "facts",
             "infrastructure_settlement",
             "ordinal"
           ]) == 1

    duplicate =
      nonstart_bundle("receipt-duplicate")
      |> put_in(["operations", Access.at(0), "expected_revisions"], %{
        "claim/claim-1" => 2,
        "effect/effect-1" => 3,
        "policy/policy-1" => 0,
        "control/control-1" => 0,
        "reservation/reservation-1" => 4,
        "ledger/ledger-1/0" => 2,
        "receipt/receipt-1" => 0,
        "settlement/effect-1" => 0,
        infrastructure_key("developer", "1") => 1
      })

    assert {:ok, %{"disposition" => "rejected"}, :rejected} =
             Gateway.atomic_bundle(ctx.gateway, ctx.capability, "operator", duplicate)

    conflict =
      nonstart_bundle("receipt-conflict")
      |> put_in(["operations", Access.at(0), "expected_revisions"], %{
        "claim/claim-1" => 2,
        "effect/effect-1" => 3,
        "policy/policy-1" => 0,
        "control/control-1" => 0,
        "reservation/reservation-1" => 4,
        "ledger/ledger-1/0" => 2,
        "receipt/receipt-2" => "absent"
      })
      |> put_in(["operations", Access.at(0), "operation", "receipt_id"], "receipt-2")
      |> put_in(["operations", Access.at(0), "operation", "outcome"], "failed")
      |> put_in(["operations", Access.at(0), "operation", "proof"], "delivered")

    assert {:ok, %{"disposition" => "quarantined"}, :quarantined} =
             Gateway.atomic_bundle(ctx.gateway, ctx.capability, "operator", conflict)

    assert {:ok, %{"status" => "reconciliation_required"}} =
             fact(ctx, "claim", "claim_id", "claim-1")

    assert {:ok, %{"ordinal" => 1}} =
             Gateway.protected_query(ctx.gateway, ctx.capability, %{
               "schema_version" => 1,
               "type" => "infrastructure_settlement",
               "effect_id" => "effect-1"
             })
  end

  defp seed_issued_launch!(ctx, role \\ "developer", suffix \\ "1") do
    policy_id = "policy-#{suffix}"
    control_id = "control-#{suffix}"
    ledger_id = "ledger-#{suffix}"
    reservation_id = "reservation-#{suffix}"
    effect_id = "effect-#{suffix}"
    claim_id = "claim-#{suffix}"
    request_id = "request-#{suffix}"
    ticket_id = "T#{suffix}"
    attempt_id = "A#{suffix}"

    accept_current!(ctx, %{
      "type" => "set_policy",
      "policy_id" => policy_id,
      "value" => %{
        "allowed_operations" => ["launch"],
        "allowed_scopes" => ["ticket:#{ticket_id}"],
        "infrastructure_attempt_limits" => %{role => 3}
      }
    })

    accept_current!(ctx, %{
      "type" => "set_control",
      "control_id" => control_id,
      "value" => %{"status" => "active"}
    })

    accept_current!(ctx, %{
      "type" => "grant_ledger",
      "ledger_id" => ledger_id,
      "generation" => 0,
      "dimension" => "starts.#{role}",
      "units" => 2
    })

    accept_current!(ctx, %{
      "type" => "reserve",
      "reservation_id" => reservation_id,
      "ledger_id" => ledger_id,
      "generation" => 0,
      "owner_kind" => "effect",
      "owner_id" => effect_id,
      "units" => 1
    })

    accept_current!(ctx, %{
      "type" => "create_effect",
      "effect_id" => effect_id,
      "request" => %{
        "request_id" => request_id,
        "role" => role,
        "profile" => "sol",
        "phase_generation" => 0,
        "operation_ordinal" => 0
      },
      "operation" => "launch",
      "scope" => "ticket:#{ticket_id}",
      "ticket_id" => ticket_id,
      "attempt_id" => attempt_id,
      "execution_id" => "execution-#{suffix}",
      "policy_id" => policy_id,
      "policy_revision" => 0,
      "control_id" => control_id,
      "control_revision" => 0,
      "reservation_ids" => [reservation_id],
      "leases" => []
    })

    accept_current!(ctx, %{
      "type" => "claim_effect",
      "effect_id" => effect_id,
      "claim_id" => claim_id,
      "writer_epoch" => "epoch-A"
    })

    accept_current!(ctx, %{
      "type" => "issue_claim",
      "claim_id" => claim_id,
      "writer_epoch" => "epoch-A"
    })
  end

  defp nonstart_bundle(id, suffix \\ "1", role \\ "developer") do
    domain_envelope(id)
    |> Map.put("operations", [
      %{
        "schema_version" => 1,
        "expected_revisions" => %{
          "claim/claim-#{suffix}" => 1,
          "effect/effect-#{suffix}" => 2,
          "policy/policy-#{suffix}" => 0,
          "control/control-#{suffix}" => 0,
          "reservation/reservation-#{suffix}" => 3,
          "ledger/ledger-#{suffix}/0" => 1,
          "receipt/receipt-#{suffix}" => "absent",
          "settlement/effect-#{suffix}" => "absent",
          infrastructure_key(role, suffix) => 0
        },
        "operation" => %{
          "type" => "settle_claim",
          "claim_id" => "claim-#{suffix}",
          "receipt_id" => "receipt-#{suffix}",
          "request_id" => "request-#{suffix}",
          "outcome" => "non_started",
          "proof" => "issuer_quiescent",
          "payload" => %{
            "quiescence_epoch" => "epoch-A",
            "failure_class" => "backend_refused_start"
          }
        }
      }
    ])
  end

  defp policy_bundle(id, policy_id) do
    domain_envelope(id)
    |> Map.put("operations", [
      %{
        "schema_version" => 1,
        "expected_revisions" => %{"policy/#{policy_id}" => "absent"},
        "operation" => %{
          "type" => "set_policy",
          "policy_id" => policy_id,
          "value" => %{"allowed_operations" => [], "allowed_scopes" => []}
        }
      }
    ])
  end

  defp domain_envelope(id) do
    event_id = "event-#{id}"

    %{
      "schema_version" => 2,
      "actor_id" => "operator",
      "inputs" => %{"recorded_at" => "2026-09-20T00:00:00Z", "transition_id" => id},
      "command" => %{
        "schema_version" => 1,
        "command_id" => id,
        "expected_revisions" => %{projection_key(id) => "absent"},
        "type" => "enqueue",
        "target_ids" => %{"ticket_id" => id},
        "payload" => %{"reason" => "launch_non_started"}
      },
      "operations" => [],
      "proposal" => %{
        "schema_version" => 1,
        "result" => %{"schema_version" => 1, "disposition" => "accepted"},
        "events" => [
          %{
            "schema_version" => 1,
            "event_id" => event_id,
            "type" => "ticket_enqueued",
            "payload" => %{
              "projection" => %{
                "namespace" => "atomic-v2",
                "entity_id" => id,
                "revision" => 0,
                "value" => %{"phase" => "queued"}
              }
            }
          }
        ],
        "projections" => [
          %{
            "schema_version" => 1,
            "namespace" => "atomic-v2",
            "entity_id" => id,
            "expected_revision" => -1,
            "revision" => 0,
            "last_event_id" => event_id,
            "value" => %{"phase" => "queued"}
          }
        ],
        "intents" => []
      }
    }
  end

  defp accept_current!(ctx, operation) do
    request = root_command(unique_id(), %{}, operation)

    assert {:ok, initial, :committed} =
             Gateway.protected_command(ctx.gateway, ctx.capability, "operator", request)

    if initial["disposition"] == "rejected" and
         initial["reason_code"] == "incomplete_read_set" do
      reads = initial["facts"]["required_revisions"]

      assert {:ok, %{"disposition" => "accepted"}, :committed} =
               Gateway.protected_command(
                 ctx.gateway,
                 ctx.capability,
                 "operator",
                 root_command(unique_id(), reads, operation)
               )
    else
      assert initial["disposition"] == "accepted"
    end
  end

  defp root_command(id, reads, operation) do
    %{
      "schema_version" => 1,
      "command_id" => id,
      "expected_revisions" => reads,
      "operation" => operation
    }
  end

  defp fact(ctx, type, key, value) do
    Gateway.protected_query(ctx.gateway, ctx.capability, %{
      "schema_version" => 1,
      "type" => type,
      key => value
    })
  end

  defp projection_key(id) do
    "projection/" <>
      Base.url_encode64("atomic-v2", padding: false) <>
      "/" <> Base.url_encode64(id, padding: false)
  end

  defp infrastructure_key(role, suffix) do
    owner = "T#{suffix}:A#{suffix}:#{role}"

    "infrastructure/" <>
      Base.url_encode64(role, padding: false) <>
      "/" <> Base.url_encode64(owner, padding: false) <> "/0"
  end

  defp unique_id, do: "root-#{System.unique_integer([:positive, :monotonic])}"

  defp canonical_tmp,
    do: if(File.dir?("/private/tmp"), do: "/private/tmp", else: System.tmp_dir!())
end
