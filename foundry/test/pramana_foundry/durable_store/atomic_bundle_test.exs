defmodule PramanaFoundry.DurableStore.AtomicBundleTest do
  use ExUnit.Case, async: false

  alias Exqlite.Sqlite3

  alias PramanaFoundry.DurableStore.{
    Authority,
    Database,
    Encoding,
    Gateway,
    ProtectedPrimitives,
    TransitionPlan
  }

  alias PramanaFoundry.Observations
  alias PramanaFoundry.Observations.Query

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

    assert {:ok, observation} =
             Gateway.protected_query(ctx.gateway, ctx.capability, %{
               "schema_version" => 1,
               "type" => "effect_observation_page",
               "effect_id" => "effect-1",
               "limit" => 50,
               "max_bytes" => 65_536,
               "cursor" => nil
             })

    assert observation["infrastructure_settlement"] == settlement

    assert observation["settlement"] == %{
             "schema_version" => 1,
             "status" => "non_started",
             "receipt_history" => "complete"
           }

    assert Enum.any?(observation["relations"], &(&1["kind"] == "receipt"))

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

    assert {:ok, raw} = Sqlite3.open(ctx.path, mode: :readwrite)
    assert :ok = Sqlite3.execute(raw, "DELETE FROM root_infrastructure_settlements")
    assert :ok = Sqlite3.close(raw)

    assert {:error, {:protected_corrupt, "effect_observation_page", "effect-1"}} =
             Gateway.protected_query(ctx.gateway, ctx.capability, %{
               "schema_version" => 1,
               "type" => "effect_observation_page",
               "effect_id" => "effect-1",
               "limit" => 50,
               "max_bytes" => 65_536,
               "cursor" => nil
             })
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

    for {fault, injected} <- [
          after_protected: :injected_after_protected,
          after_domain: :injected_after_domain,
          before_commit: :injected_crash_before_commit
        ] do
      path = Path.join(Path.dirname(ctx.path), "#{fault}.sqlite3")
      assert :ok = Gateway.initialize(path)

      gateway =
        start_supervised!(
          {Gateway,
           path: path, protected_capability: ctx.capability, writer_epoch: "epoch-A", fault: fault},
          id: {:fault_gateway, fault}
        )

      envelope = policy_bundle("fault-#{fault}", "policy-#{fault}")

      assert {:error, {:storage_unavailable, ^injected}} =
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

  test "malformed nested bundle operation result enters recovery", ctx do
    assert {:ok, _result, :committed} =
             Gateway.atomic_bundle(
               ctx.gateway,
               ctx.capability,
               "operator",
               policy_bundle("scalar-outcome", "scalar-policy")
             )

    gateway =
      corrupt_bundle_result!(ctx, "scalar-outcome", false, fn result ->
        Map.put(result, "operations", [17])
      end)

    assert %{mode: :recovery} = Gateway.status(gateway)
  end

  test "copied settlement carrier is bound to authoritative receipt-derived settlement", ctx do
    seed_issued_launch!(ctx)

    assert {:ok, _result, :committed} =
             Gateway.atomic_bundle(
               ctx.gateway,
               ctx.capability,
               "operator",
               nonstart_bundle("forged-settlement-carrier")
             )

    gateway =
      corrupt_bundle_result!(ctx, "forged-settlement-carrier", true, fn result ->
        [operation] = result["operations"]

        operation =
          put_in(
            operation,
            ["result", "facts", "infrastructure_settlement", "ordinal"],
            900
          )

        Map.put(result, "operations", [operation])
      end)

    assert %{mode: :recovery} = Gateway.status(gateway)
  end

  test "accepted non-start requires the settlement carrier key", ctx do
    seed_issued_launch!(ctx)

    assert {:ok, _result, :committed} =
             Gateway.atomic_bundle(
               ctx.gateway,
               ctx.capability,
               "operator",
               nonstart_bundle("missing-settlement-carrier")
             )

    gateway =
      corrupt_bundle_result!(ctx, "missing-settlement-carrier", true, fn result ->
        [operation] = result["operations"]

        operation =
          update_in(operation, ["result", "facts"], &Map.delete(&1, "infrastructure_settlement"))

        Map.put(result, "operations", [operation])
      end)

    assert %{mode: :recovery} = Gateway.status(gateway)
  end

  test "accepted non-start rejects an explicit null settlement carrier", ctx do
    seed_issued_launch!(ctx)

    assert {:ok, _result, :committed} =
             Gateway.atomic_bundle(
               ctx.gateway,
               ctx.capability,
               "operator",
               nonstart_bundle("null-settlement-carrier")
             )

    gateway =
      corrupt_bundle_result!(ctx, "null-settlement-carrier", true, fn result ->
        [operation] = result["operations"]
        operation = put_in(operation, ["result", "facts", "infrastructure_settlement"], nil)
        Map.put(result, "operations", [operation])
      end)

    assert %{mode: :recovery} = Gateway.status(gateway)
  end

  test "accepted operations without settlement facts remain valid when the key is absent", ctx do
    assert {:ok, result, :committed} =
             Gateway.atomic_bundle(
               ctx.gateway,
               ctx.capability,
               "operator",
               policy_bundle("no-settlement-required", "ordinary-policy")
             )

    assert [operation] = result["operations"]
    refute Map.has_key?(operation["result"]["facts"], "infrastructure_settlement")

    stop_supervised!(Gateway)

    reopened =
      start_supervised!(
        {Gateway, path: ctx.path, protected_capability: ctx.capability, writer_epoch: "epoch-B"}
      )

    assert %{mode: :ready} = Gateway.status(reopened)
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

    assert %{status: :ok, items: [item]} =
             Observations.query(
               %Query{include_pointers: false, effect_ids: ["effect-1"]},
               ctx.gateway,
               ctx.capability
             )

    assert item.fact["status"] == "reconciliation_required"

    assert item.fact["outcome"] == %{
             "status" => "unknown",
             "reason" => "reconciliation_required",
             "receipt_history" => ["non_started"]
           }

    assert item.fact["infrastructure_settlement"]["ordinal"] == 1
  end

  test "bounded settlement rejects every scalar that diverges from accepted provenance", ctx do
    seed_issued_launch!(ctx)

    assert {:ok, _, :committed} =
             Gateway.atomic_bundle(
               ctx.gateway,
               ctx.capability,
               "operator",
               nonstart_bundle("settlement-provenance")
             )

    assert {:ok, raw} = Sqlite3.open(ctx.path, mode: :readwrite)

    for {column, wrong} <- [
          {"role", "pm"},
          {"work_owner", "wrong-owner"},
          {"infrastructure_generation", 99},
          {"predecessor_effect_id", "wrong-predecessor"},
          {"failure_class", "wrong-failure"},
          {"ordinal", 900}
        ] do
      assert {:ok, [[original]]} =
               Database.query(
                 raw,
                 "SELECT " <>
                   column <>
                   " FROM root_infrastructure_settlements WHERE effect_id = ?",
                 ["effect-1"]
               )

      assert :ok =
               Database.execute(
                 raw,
                 "UPDATE root_infrastructure_settlements SET " <>
                   column <>
                   " = ? WHERE effect_id = ?",
                 [wrong, "effect-1"]
               )

      assert {:error, {:protected_corrupt, "effect_observation_page", "effect-1"}} =
               Gateway.protected_query(ctx.gateway, ctx.capability, %{
                 "schema_version" => 1,
                 "type" => "effect_observation_page",
                 "effect_id" => "effect-1",
                 "limit" => 50,
                 "max_bytes" => 65_536,
                 "cursor" => nil
               })

      assert :ok =
               Database.execute(
                 raw,
                 "UPDATE root_infrastructure_settlements SET " <>
                   column <>
                   " = ? WHERE effect_id = ?",
                 [original, "effect-1"]
               )
    end

    assert :ok = Sqlite3.close(raw)
  end

  defp seed_issued_launch!(ctx, role \\ "developer", suffix \\ "1", limit \\ 3) do
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
        "infrastructure_attempt_limits" => %{role => limit}
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

  defp corrupt_bundle_result!(ctx, command_id, sync_operation?, transform) do
    stop_supervised!(Gateway)
    assert {:ok, conn} = Sqlite3.open(ctx.path, mode: :readwrite)

    assert {:ok, [[bytes]]} =
             Database.query(conn, "SELECT result FROM atomic_bundles WHERE command_id = ?", [
               command_id
             ])

    result = bytes |> :json.decode() |> normalize_json() |> transform.()
    assert {:ok, encoded} = Encoding.json(result)

    assert :ok =
             Database.execute(conn, "UPDATE atomic_bundles SET result = ? WHERE command_id = ?", [
               {:blob, encoded},
               command_id
             ])

    if sync_operation? do
      [%{"execution_status" => status, "result" => operation_result}] = result["operations"]

      assert {:ok, encoded_operation} =
               Encoding.json(%{
                 "schema_version" => 1,
                 "execution_status" => status,
                 "operation_result" => operation_result
               })

      assert :ok =
               Database.execute(
                 conn,
                 "UPDATE durable_operations SET result = ? WHERE owner_kind = 'bundle_v2' AND owner_id = ? AND ordinal = 0",
                 [{:blob, encoded_operation}, command_id]
               )
    end

    assert :ok = Sqlite3.close(conn)

    start_supervised!(
      {Gateway, path: ctx.path, protected_capability: ctx.capability, writer_epoch: "epoch-B"}
    )
  end

  defp normalize_json(:null), do: nil

  defp normalize_json(value) when is_map(value),
    do: Map.new(value, fn {key, nested} -> {key, normalize_json(nested)} end)

  defp normalize_json(value) when is_list(value), do: Enum.map(value, &normalize_json/1)
  defp normalize_json(value), do: value

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

  describe "infrastructure discriminator" do
    defp discriminator_conn(ctx) do
      assert {:ok, conn} = Sqlite3.open(ctx.path, mode: :readonly)
      on_exit(fn -> Sqlite3.close(conn) end)
      conn
    end

    defp settled_effect!(ctx) do
      seed_issued_launch!(ctx)

      assert {:ok, _, :committed} =
               Gateway.atomic_bundle(
                 ctx.gateway,
                 ctx.capability,
                 "operator",
                 nonstart_bundle("disc")
               )

      assert {:ok, settlement} = fact(ctx, "infrastructure_settlement", "effect_id", "effect-1")
      settlement
    end

    test "an ordinal below the policy limit selects the permissive branch", ctx do
      settlement = settled_effect!(ctx)
      conn = discriminator_conn(ctx)

      assert settlement["ordinal"] == 1

      assert {:ok, "below_infrastructure_limit"} =
               ProtectedPrimitives.infrastructure_discriminator(conn, "effect-1", settlement)
    end

    # The seeded policy allows three developer attempts. The comparison itself is
    # exercised by presenting an ordinal at that limit; only role and ordinal are read
    # from the settlement, so this is a faithful test of the boundary.
    test "an ordinal at the policy limit selects the exhausted branch", ctx do
      settlement = settled_effect!(ctx)
      conn = discriminator_conn(ctx)

      assert {:ok, "infrastructure_limit_reached"} =
               ProtectedPrimitives.infrastructure_discriminator(
                 conn,
                 "effect-1",
                 Map.put(settlement, "ordinal", 3)
               )
    end

    test "a settlement role disagreeing with the effect fails closed", ctx do
      settlement = settled_effect!(ctx)
      conn = discriminator_conn(ctx)

      assert {:error, :infrastructure_limit_undecidable} =
               ProtectedPrimitives.infrastructure_discriminator(
                 conn,
                 "effect-1",
                 Map.put(settlement, "role", "reviewer")
               )
    end

    test "a non-positive ordinal fails closed", ctx do
      settlement = settled_effect!(ctx)
      conn = discriminator_conn(ctx)

      assert {:error, :infrastructure_limit_undecidable} =
               ProtectedPrimitives.infrastructure_discriminator(
                 conn,
                 "effect-1",
                 Map.put(settlement, "ordinal", 0)
               )
    end

    test "an unknown effect fails closed", ctx do
      settlement = settled_effect!(ctx)
      conn = discriminator_conn(ctx)

      assert {:error, :infrastructure_limit_undecidable} =
               ProtectedPrimitives.infrastructure_discriminator(conn, "effect-absent", settlement)
    end

    test "a settlement that is not a map fails closed", ctx do
      settled_effect!(ctx)
      conn = discriminator_conn(ctx)

      assert {:error, :infrastructure_limit_undecidable} =
               ProtectedPrimitives.infrastructure_discriminator(conn, "effect-1", nil)
    end

    test "a policy revised after the effect was created fails closed", ctx do
      settlement = settled_effect!(ctx)

      accept_current!(ctx, %{
        "type" => "set_policy",
        "policy_id" => "policy-1",
        "value" => %{
          "allowed_operations" => ["launch"],
          "allowed_scopes" => ["ticket:T1"],
          "infrastructure_attempt_limits" => %{"developer" => 9}
        }
      })

      conn = discriminator_conn(ctx)

      assert {:error, :infrastructure_limit_undecidable} =
               ProtectedPrimitives.infrastructure_discriminator(conn, "effect-1", settlement)
    end
  end

  describe "plan-bearing atomic bundles" do
    defp plan_alternative(id, phase, with_marker?) do
      event_id = "event-#{id}"

      payload =
        %{
          "projection" => %{
            "namespace" => "atomic-v2",
            "entity_id" => id,
            "revision" => 0,
            "value" => %{"phase" => phase}
          }
        }
        |> then(fn p ->
          if with_marker?, do: Map.put(p, "settlement", %{"binding" => "settled"}), else: p
        end)

      %{
        "schema_version" => 1,
        "result" => %{"schema_version" => 1, "disposition" => "accepted"},
        "events" => [
          %{
            "schema_version" => 1,
            "event_id" => event_id,
            "type" => "launch_settled",
            "payload" => payload
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
            "value" => %{"phase" => phase}
          }
        ],
        "intents" => []
      }
    end

    defp nonstart_plan_bundle(id) do
      nonstart_bundle(id)
      |> Map.delete("proposal")
      |> Map.put("plan", %{
        "schema_version" => 1,
        "command_id" => id,
        "disposition" => "accepted",
        "reason_code" => nil,
        "expected_domain_revision" => 0,
        "domain_reads" => [],
        "protected_operations" => [
          %{"schema_version" => 1, "ordinal" => 0, "type" => "settle_claim", "input" => %{}}
        ],
        "bindings" => [
          %{
            "name" => "settled",
            "operation_ordinal" => 0,
            "output_kind" => "nonstart_settlement_v1",
            "destination_slot" => "launch_settled.settlement"
          }
        ],
        "discriminator_kind" => "infrastructure_limit_v1",
        "alternatives" => [
          %{
            "discriminator" => "below_infrastructure_limit",
            "proposal" => plan_alternative(id, "queued", true)
          },
          # Both alternatives bind the settlement. R4a records the proved non-start
          # whichever branch is taken; only the resulting phase differs. A declared
          # binding with no destination in the selected alternative is a plan error, and
          # the codec correctly rejects it as binding_slot_absent.
          %{
            "discriminator" => "infrastructure_limit_reached",
            "proposal" => plan_alternative(id, "blocked", true)
          }
        ]
      })
    end

    test "a plan binds its authoritative settlement and commits", ctx do
      seed_issued_launch!(ctx)

      assert {:ok, %{"disposition" => "accepted"}, :committed} =
               Gateway.atomic_bundle(
                 ctx.gateway,
                 ctx.capability,
                 "operator",
                 nonstart_plan_bundle("PLAN1")
               )

      # The settlement the protected layer assigned inside this transaction reached the
      # committed domain event. Nothing predicted or copied it.
      assert {:ok, settlement} = fact(ctx, "infrastructure_settlement", "effect_id", "effect-1")
      assert settlement["ordinal"] == 1

      assert {:ok, events} = Gateway.recent_events(ctx.gateway, 20)
      assert Enum.any?(events, &(&1.event_type == "launch_settled"))
    end

    test "the protected discriminator selects the alternative, not the caller", ctx do
      seed_issued_launch!(ctx)

      assert {:ok, %{"disposition" => "accepted"}, :committed} =
               Gateway.atomic_bundle(
                 ctx.gateway,
                 ctx.capability,
                 "operator",
                 nonstart_plan_bundle("PLAN2")
               )

      # Ordinal 1 is below the seeded developer limit of 3, so the protected derivation
      # must have chosen the below-limit alternative and queued rather than blocked.
      assert {:ok, raw} = Sqlite3.open(ctx.path, mode: :readonly)

      assert {:ok, [[bytes]]} =
               Database.query(
                 raw,
                 "SELECT projection FROM projections WHERE namespace = ? AND entity_id = ?",
                 ["atomic-v2", "PLAN2"]
               )

      assert :ok = Sqlite3.close(raw)
      assert %{"value" => %{"phase" => "queued"}} = bytes |> :json.decode() |> normalize_json()
    end

    test "an envelope carrying both a plan and a proposal is refused", ctx do
      seed_issued_launch!(ctx)

      both = Map.put(nonstart_plan_bundle("PLAN3"), "proposal", %{})

      assert {:error, :invalid_atomic_bundle} =
               Gateway.atomic_bundle(ctx.gateway, ctx.capability, "operator", both)
    end

    test "an envelope carrying neither is refused", ctx do
      seed_issued_launch!(ctx)

      neither = Map.delete(nonstart_plan_bundle("PLAN4"), "plan")

      assert {:error, :invalid_atomic_bundle} =
               Gateway.atomic_bundle(ctx.gateway, ctx.capability, "operator", neither)
    end

    test "a rejected plan is an ordinary rejection, not an infrastructure failure", ctx do
      seed_issued_launch!(ctx)

      # No alternative matches either value the protected derivation can return.
      unknown =
        nonstart_plan_bundle("PLAN5")
        |> update_in(["plan", "alternatives"], fn [a, b] ->
          [%{a | "discriminator" => "alt-a"}, %{b | "discriminator" => "alt-b"}]
        end)

      assert {:ok, %{"disposition" => "rejected"}, _} =
               Gateway.atomic_bundle(ctx.gateway, ctx.capability, "operator", unknown)

      # The Gateway must remain usable for every actor. Untagged, this error reached the
      # generic catch-all, was reported as storage_unavailable, and put the whole
      # GenServer into permanent recovery mode.
      assert %{mode: :ready} = Gateway.status(ctx.gateway)

      assert {:ok, _, :committed} =
               Gateway.atomic_bundle(
                 ctx.gateway,
                 ctx.capability,
                 "operator",
                 nonstart_plan_bundle("PLAN6")
               )
    end

    test "a rejected plan is durably recorded so a lost reply can find it", ctx do
      seed_issued_launch!(ctx)

      unknown =
        nonstart_plan_bundle("PLAN7")
        |> update_in(["plan", "alternatives"], fn [a, b] ->
          [%{a | "discriminator" => "alt-a"}, %{b | "discriminator" => "alt-b"}]
        end)

      assert {:ok, first, _} =
               Gateway.atomic_bundle(ctx.gateway, ctx.capability, "operator", unknown)

      assert first["disposition"] == "rejected"

      # The identical command returns its original result rather than re-deciding.
      assert {:ok, ^first, :idempotent} =
               Gateway.atomic_bundle(ctx.gateway, ctx.capability, "operator", unknown)
    end

    test "the selected discriminator is recorded, because it cannot be recomputed", ctx do
      seed_issued_launch!(ctx)

      assert {:ok, result, :committed} =
               Gateway.atomic_bundle(
                 ctx.gateway,
                 ctx.capability,
                 "operator",
                 nonstart_plan_bundle("PLAN8")
               )

      assert result["selected_discriminator"] == "below_infrastructure_limit"
    end

    test "the committed event carries the authoritative settlement itself", ctx do
      seed_issued_launch!(ctx)

      assert {:ok, _, :committed} =
               Gateway.atomic_bundle(
                 ctx.gateway,
                 ctx.capability,
                 "operator",
                 nonstart_plan_bundle("PLAN9")
               )

      assert {:ok, authoritative} =
               fact(ctx, "infrastructure_settlement", "effect_id", "effect-1")

      # Read the committed event itself rather than trusting that binding happened.
      assert {:ok, raw} = Sqlite3.open(ctx.path, mode: :readonly)

      assert {:ok, [[bytes]]} =
               Database.query(raw, "SELECT event FROM events WHERE event_type = ?", [
                 "launch_settled"
               ])

      assert :ok = Sqlite3.close(raw)
      event = bytes |> :json.decode() |> normalize_json()

      assert event["payload"]["settlement"] == authoritative
    end

    test "alternative selection does not depend on declaration order", ctx do
      seed_issued_launch!(ctx)

      # Same plan with the alternatives reversed. The true answer is still below-limit,
      # so a "pick the first alternative" implementation would now choose blocked.
      reversed =
        nonstart_plan_bundle("PLAN10")
        |> update_in(["plan", "alternatives"], &Enum.reverse/1)

      assert {:ok, _, :committed} =
               Gateway.atomic_bundle(ctx.gateway, ctx.capability, "operator", reversed)

      assert {:ok, raw} = Sqlite3.open(ctx.path, mode: :readonly)

      assert {:ok, [[bytes]]} =
               Database.query(
                 raw,
                 "SELECT projection FROM projections WHERE namespace = ? AND entity_id = ?",
                 ["atomic-v2", "PLAN10"]
               )

      assert :ok = Sqlite3.close(raw)
      assert %{"value" => %{"phase" => "queued"}} = bytes |> :json.decode() |> normalize_json()
    end

    test "the exhausted branch is reachable through the full path", ctx do
      # Seed with a limit of 1 so the first settlement's ordinal already reaches it.
      seed_issued_launch!(ctx, "developer", "1", 1)

      assert {:ok, result, :committed} =
               Gateway.atomic_bundle(
                 ctx.gateway,
                 ctx.capability,
                 "operator",
                 nonstart_plan_bundle("PLAN11")
               )

      assert result["selected_discriminator"] == "infrastructure_limit_reached"

      assert {:ok, raw} = Sqlite3.open(ctx.path, mode: :readonly)

      assert {:ok, [[bytes]]} =
               Database.query(
                 raw,
                 "SELECT projection FROM projections WHERE namespace = ? AND entity_id = ?",
                 ["atomic-v2", "PLAN11"]
               )

      assert :ok = Sqlite3.close(raw)
      assert %{"value" => %{"phase" => "blocked"}} = bytes |> :json.decode() |> normalize_json()
    end

    test "a plan whose declared operations disagree with the envelope is refused", ctx do
      seed_issued_launch!(ctx)

      incoherent =
        nonstart_plan_bundle("PLAN12")
        |> put_in(["plan", "protected_operations"], [
          %{"schema_version" => 1, "ordinal" => 0, "type" => "set_control", "input" => %{}}
        ])

      # Refused at normalization rather than tolerated until derive_output/2 happens to
      # catch the consequence against the real staged result.
      assert {:error, :plan_operations_mismatch} =
               Gateway.atomic_bundle(ctx.gateway, ctx.capability, "operator", incoherent)
    end

    test "the discriminator needs the settlement its own plan binds", ctx do
      seed_issued_launch!(ctx)

      # A plan that binds no settlement cannot supply the infrastructure discriminator,
      # even though the envelope stages a settle_claim whose settlement a global scan
      # would have found and silently used.
      unbound =
        nonstart_plan_bundle("PLAN13")
        |> put_in(["plan", "bindings"], [
          %{
            "name" => "settled",
            "operation_ordinal" => 0,
            "output_kind" => "control_fact_v1",
            "destination_slot" => "control_changed.control"
          }
        ])

      assert {:ok, %{"disposition" => "rejected", "reason_code" => reason}, _} =
               Gateway.atomic_bundle(ctx.gateway, ctx.capability, "operator", unbound)

      assert reason == "discriminator_settlement_unavailable"
    end

    defp commit_plan!(ctx, id) do
      seed_issued_launch!(ctx)

      assert {:ok, _, :committed} =
               Gateway.atomic_bundle(
                 ctx.gateway,
                 ctx.capability,
                 "operator",
                 nonstart_plan_bundle(id)
               )
    end

    defp reopen_status(ctx) do
      stop_supervised!(Gateway)

      reopened =
        start_supervised!({Gateway, path: ctx.path, protected_capability: ctx.capability})

      Gateway.status(reopened)
    end

    test "a plan-bound commit survives reopen and verified backup unchanged", ctx do
      commit_plan!(ctx, "REV1")

      assert {:ok, _} = Gateway.backup(ctx.gateway, ctx.path <> ".rev-backup")
      assert %{mode: :ready} = reopen_status(ctx)
    end

    # Verified non-vacuous: neutralising valid_plan_binding?/4 makes this test fail,
    # so the new revalidation is what detects it, not a pre-existing check.
    test "mutating a committed carrier is detected on reopen", ctx do
      commit_plan!(ctx, "REV2")
      stop_supervised!(Gateway)

      # Rewrite the committed event's bound settlement. The protected root can no longer
      # reproduce this event by re-running the binding, so it must refuse.
      assert {:ok, raw} = Sqlite3.open(ctx.path, mode: :readwrite)

      assert {:ok, [[bytes]]} =
               Database.query(raw, "SELECT event FROM events WHERE event_type = ?", [
                 "launch_settled"
               ])

      tampered =
        bytes
        |> :json.decode()
        |> normalize_json()
        |> put_in(["payload", "settlement", "ordinal"], 99)

      assert {:ok, encoded} = Encoding.json(tampered)

      assert :ok =
               Database.execute(raw, "UPDATE events SET event = ? WHERE event_type = ?", [
                 {:blob, encoded},
                 "launch_settled"
               ])

      assert :ok = Sqlite3.close(raw)

      reopened =
        start_supervised!({Gateway, path: ctx.path, protected_capability: ctx.capability})

      assert %{mode: :recovery} = Gateway.status(reopened)
    end

    test "a coherently tampered commit that contradicts policy is still detected", ctx do
      commit_plan!(ctx, "REV3")
      stop_supervised!(Gateway)

      # The hole correction 1 closes. Flipping the recorded discriminator ALONE is caught
      # by the pre-existing events comparison and proves nothing about reconstruction: the
      # binder's output for the other alternative simply differs from the committed
      # events. The tamper that matters rewrites the events and projection to the other
      # alternative too, so the store is internally coherent and only contradicts the
      # policy that was in force. Before reconstruction, that reopened clean.
      assert {:ok, raw} = Sqlite3.open(ctx.path, mode: :readwrite)

      assert {:ok, [[envelope_bytes, result_bytes]]} =
               Database.query(
                 raw,
                 "SELECT canonical_envelope, result FROM atomic_bundles WHERE command_id = ?",
                 ["REV3"]
               )

      envelope = envelope_bytes |> :json.decode() |> normalize_json()
      result = result_bytes |> :json.decode() |> normalize_json()

      # Ask the trusted binder itself for the other alternative's carriers, so the tamper
      # is exactly what a correct commit of the blocked branch would have written.
      assert {:ok, blocked} =
               TransitionPlan.bind(
                 envelope["plan"],
                 "infrastructure_limit_reached",
                 result["operations"]
               )

      [blocked_event] = blocked["events"]
      assert {:ok, event_encoded} = Encoding.json(blocked_event)

      assert :ok =
               Database.execute(raw, "UPDATE events SET event = ? WHERE event_type = ?", [
                 {:blob, event_encoded},
                 "launch_settled"
               ])

      [blocked_projection] = blocked["projections"]
      assert {:ok, projection_encoded} = Encoding.json(blocked_projection)

      assert :ok =
               Database.execute(
                 raw,
                 "UPDATE projections SET projection = ? WHERE namespace = ? AND entity_id = ?",
                 [{:blob, projection_encoded}, "atomic-v2", "REV3"]
               )

      assert {:ok, tampered_result} =
               Encoding.json(
                 Map.put(result, "selected_discriminator", "infrastructure_limit_reached")
               )

      assert :ok =
               Database.execute(
                 raw,
                 "UPDATE atomic_bundles SET result = ? WHERE command_id = ?",
                 [
                   {:blob, tampered_result},
                   "REV3"
                 ]
               )

      assert :ok = Sqlite3.close(raw)

      reopened =
        start_supervised!({Gateway, path: ctx.path, protected_capability: ctx.capability})

      assert %{mode: :recovery} = Gateway.status(reopened)
    end

    test "reconstruction is revision-aware, so a later policy revision is safe", ctx do
      commit_plan!(ctx, "REV4")

      # Revising the policy makes head-row recomputation fail closed. Revalidation
      # reconstructs from root_policy_history at the effect's recorded policy_revision
      # instead, so the historical commit still revalidates. A head-row recomputation
      # would report this valid commit as corrupt.
      accept_current!(ctx, %{
        "type" => "set_policy",
        "policy_id" => "policy-1",
        "value" => %{
          "allowed_operations" => ["launch"],
          "allowed_scopes" => ["ticket:T1"],
          "infrastructure_attempt_limits" => %{"developer" => 9}
        }
      })

      assert {:ok, _} = Gateway.backup(ctx.gateway, ctx.path <> ".rev4-backup")
      assert %{mode: :ready} = reopen_status(ctx)
    end
  end
end
