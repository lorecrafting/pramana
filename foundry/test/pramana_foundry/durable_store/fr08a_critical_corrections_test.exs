defmodule PramanaFoundry.DurableStore.FR08ACriticalCorrectionsTest do
  use ExUnit.Case, async: false

  alias PramanaFoundry.DurableStore.{Encoding, Gateway}

  setup do
    root =
      Path.join(
        canonical_tmp(),
        "fr08a-critical-#{System.pid()}-#{System.unique_integer([:positive, :monotonic])}"
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

  test "takeover requires an explicit quiescent reclaim before issue", ctx do
    ctx = seed_effect(ctx)
    accept_current!(ctx, claim_operation("epoch-A"))

    stop_supervised!(Gateway)

    gateway =
      start_supervised!(
        {Gateway, path: ctx.path, protected_capability: ctx.capability, writer_epoch: "epoch-B"},
        id: :epoch_b_gateway
      )

    ctx = %{ctx | gateway: gateway}

    assert_rejected!(ctx, issue_operation("epoch-A"), "claim_issue_not_permitted")

    accept_current!(ctx, %{
      "type" => "reclaim_claim",
      "claim_id" => "claim-1",
      "prior_writer_epoch" => "epoch-A",
      "new_writer_epoch" => "epoch-B",
      "proof" => "issuer_quiescent"
    })

    assert accept_current!(ctx, issue_operation("epoch-B"))["facts"]["claim"]["status"] ==
             "issued"
  end

  test "semantic identity, dimensions and recursive closure reject authority bypasses", ctx do
    seed_policy_control(ctx)
    accept_current!(ctx, grant("root", "starts.developer", 10))
    accept_current!(ctx, grant("validation", "validations", 2))
    accept_current!(ctx, reserve("wrong-dimension", "validation", "effect-wrong"))

    assert_rejected!(
      ctx,
      effect("effect-wrong", "execution-wrong", "request-wrong"),
      "operation_dimension_mismatch"
    )

    assert {:ok, %{"status" => "proposed"}} =
             fact(ctx, "reservation", "reservation_id", "wrong-dimension")

    assert {:ok, %{"available" => 2, "held" => 0}} = ledger(ctx, "validation")

    accept_current!(ctx, delegate("root", "child", 4))
    accept_current!(ctx, delegate("child", "grandchild", 2))

    accept_current!(ctx, %{"type" => "close_generation", "ledger_id" => "root", "generation" => 0})

    assert {:ok, %{"status" => "closed"}} = ledger(ctx, "child")
    assert {:ok, %{"status" => "closed"}} = ledger(ctx, "grandchild")

    assert_rejected!(
      ctx,
      %{
        "type" => "return_allocation",
        "child_ledger_id" => "child",
        "child_generation" => 0,
        "units" => 1
      },
      "allocation_return_not_permitted"
    )
  end

  test "control cancellation revokes claimed descendants and preserves no implicit credit", ctx do
    ctx = seed_effect(ctx)
    accept_current!(ctx, claim_operation("epoch-A"))

    cancellation =
      accept_current!(ctx, %{
        "type" => "set_control",
        "control_id" => "control-1",
        "value" => %{"status" => "cancel_requested"}
      })

    assert cancellation["facts"]["outstanding_claim_ids"] == []
    assert {:ok, %{"status" => "cancelled"}} = fact(ctx, "claim", "claim_id", "claim-1")
    assert {:ok, %{"status" => "cancelled"}} = fact(ctx, "effect", "effect_id", "effect-1")
    assert {:ok, %{"available" => 5, "held" => 0}} = ledger(ctx, "root")
    assert_rejected!(ctx, issue_operation("epoch-A"), "claim_issue_not_permitted")
  end

  test "root failpoints roll back before commit and recover a lost reply exactly once", ctx do
    stop_supervised!(Gateway)

    request =
      command("fault-command", %{"policy/fault-policy" => "absent"}, policy("fault-policy"))

    before =
      start_supervised!(
        {Gateway,
         path: ctx.path,
         protected_capability: ctx.capability,
         writer_epoch: "epoch-A",
         fault: :before_commit},
        id: :before_commit_gateway
      )

    assert {:error, {:storage_unavailable, :injected_crash_before_commit}} =
             Gateway.protected_command(before, ctx.capability, "operator", request)

    stop_supervised!(:before_commit_gateway)

    clean =
      start_supervised!(
        {Gateway, path: ctx.path, protected_capability: ctx.capability, writer_epoch: "epoch-A"},
        id: :clean_after_rollback
      )

    assert {:error, :policy_not_found} =
             fact(%{ctx | gateway: clean}, "policy", "policy_id", "fault-policy")

    stop_supervised!(:clean_after_rollback)

    after_commit =
      start_supervised!(
        {Gateway,
         path: ctx.path,
         protected_capability: ctx.capability,
         writer_epoch: "epoch-A",
         fault: :after_commit_before_reply},
        id: :after_commit_gateway
      )

    assert {:error, {:storage_unavailable, :injected_after_commit_before_reply}} =
             Gateway.protected_command(after_commit, ctx.capability, "operator", request)

    stop_supervised!(:after_commit_gateway)

    recovered =
      start_supervised!(
        {Gateway, path: ctx.path, protected_capability: ctx.capability, writer_epoch: "epoch-B"},
        id: :recovered_gateway
      )

    assert {:ok, result, :idempotent} =
             Gateway.protected_command(recovered, ctx.capability, "operator", request)

    assert result["disposition"] == "accepted"
    assert result["command_sequence"] == 1
  end

  test "legacy and root authority operate in explicit mutually exclusive modes", ctx do
    assert {:ok, _, :committed} = legacy_write(ctx)

    assert {:ok, %{"authority_mode" => "legacy"}} =
             Gateway.protected_snapshot(ctx.gateway, ctx.capability)

    assert {:error, :legacy_authority_mode_active} =
             Gateway.protected_command(
               ctx.gateway,
               ctx.capability,
               "operator",
               command("root-after-legacy", %{"policy/policy-1" => "absent"}, policy("policy-1"))
             )

    other_path = Path.join(Path.dirname(ctx.path), "root-first.sqlite3")
    assert :ok = Gateway.initialize(other_path)
    other_capability = make_ref()

    other =
      start_supervised!(
        {Gateway,
         path: other_path, protected_capability: other_capability, writer_epoch: "epoch-root"},
        id: :root_first_gateway
      )

    other_ctx = %{ctx | gateway: other, capability: other_capability, path: other_path}
    accept_current!(other_ctx, policy("policy-1"))

    assert {:error, :legacy_protected_route_retired} = legacy_write(other_ctx)

    assert {:ok, %{"authority_mode" => "root"}} =
             Gateway.protected_snapshot(other, other_capability)
  end

  defp seed_effect(ctx) do
    seed_policy_control(ctx)
    accept_current!(ctx, grant("root", "starts.developer", 5))
    accept_current!(ctx, reserve("reservation-1", "root", "effect-1"))
    accept_current!(ctx, effect("effect-1", "execution-1", "request-1"))
    ctx
  end

  defp seed_policy_control(ctx) do
    accept_current!(ctx, policy("policy-1"))

    accept_current!(ctx, %{
      "type" => "set_control",
      "control_id" => "control-1",
      "value" => %{"status" => "active"}
    })
  end

  defp policy(id) do
    %{
      "type" => "set_policy",
      "policy_id" => id,
      "value" => %{
        "allowed_operations" => ["launch"],
        "allowed_scopes" => ["ticket:T1"]
      }
    }
  end

  defp grant(id, dimension, units) do
    %{
      "type" => "grant_ledger",
      "ledger_id" => id,
      "generation" => 0,
      "dimension" => dimension,
      "units" => units
    }
  end

  defp delegate(parent, child, units) do
    %{
      "type" => "delegate_allocation",
      "parent_ledger_id" => parent,
      "parent_generation" => 0,
      "child_ledger_id" => child,
      "child_generation" => 0,
      "dimension" => "starts.developer",
      "units" => units
    }
  end

  defp reserve(id, ledger, effect_id) do
    %{
      "type" => "reserve",
      "reservation_id" => id,
      "ledger_id" => ledger,
      "generation" => 0,
      "owner_kind" => "effect",
      "owner_id" => effect_id,
      "units" => 1
    }
  end

  defp effect(id, execution, request) do
    reservation = if id == "effect-1", do: "reservation-1", else: "wrong-dimension"

    %{
      "type" => "create_effect",
      "effect_id" => id,
      "request" => %{"request_id" => request, "role" => "developer", "profile" => "sol"},
      "operation" => "launch",
      "scope" => "ticket:T1",
      "ticket_id" => "T1",
      "attempt_id" => "A1",
      "execution_id" => execution,
      "policy_id" => "policy-1",
      "policy_revision" => 0,
      "control_id" => "control-1",
      "control_revision" => 0,
      "reservation_ids" => [reservation],
      "leases" => []
    }
  end

  defp claim_operation(epoch),
    do: %{
      "type" => "claim_effect",
      "effect_id" => "effect-1",
      "claim_id" => "claim-1",
      "writer_epoch" => epoch
    }

  defp issue_operation(epoch),
    do: %{"type" => "issue_claim", "claim_id" => "claim-1", "writer_epoch" => epoch}

  defp accept_current!(ctx, operation) do
    assert {:ok, %{"disposition" => "accepted"} = result, :committed} =
             submit_current(ctx, operation)

    result
  end

  defp assert_rejected!(ctx, operation, reason) do
    assert {:ok, %{"disposition" => "rejected", "reason_code" => ^reason}, :committed} =
             submit_current(ctx, operation)
  end

  defp submit_current(ctx, operation) do
    first = command(unique_id(), %{}, operation)

    assert {:ok, initial, :committed} =
             Gateway.protected_command(ctx.gateway, ctx.capability, "operator", first)

    case initial do
      %{"disposition" => "rejected", "reason_code" => "incomplete_read_set"} ->
        Gateway.protected_command(
          ctx.gateway,
          ctx.capability,
          "operator",
          command(unique_id(), initial["facts"]["required_revisions"], operation)
        )

      _ ->
        {:ok, initial, :committed}
    end
  end

  defp legacy_write(ctx) do
    operation = %{"operation" => "check"}

    {:ok, digest} =
      Encoding.semantic_digest("pramana-foundry-effect-request-v1", %{
        "effect_id" => "legacy-effect",
        "operation" => operation
      })

    bundle = %{
      schema_version: 1,
      result: %{schema_version: 1, disposition: "accepted"},
      events: [],
      projections: [],
      intents: [
        %{
          schema_version: 1,
          effect_id: "legacy-effect",
          request_digest: digest,
          status: "pending",
          value: operation
        }
      ]
    }

    facts = %{
      writer_epoch: "legacy-epoch",
      required_revisions: %{},
      ledger_generations: [
        %{
          schema_version: 1,
          generation_id: "legacy-generation",
          parent_generation_id: nil,
          allocation: 1,
          consumed: 0
        }
      ],
      effect_authorizations: [
        %{
          effect_id: "legacy-effect",
          claim_id: "legacy-claim",
          generation_id: "legacy-generation",
          reservation_id: "legacy-reservation",
          dimension: "starts.developer",
          units: 1
        }
      ]
    }

    Gateway.transact_verified(
      ctx.gateway,
      ctx.capability,
      "operator",
      %{
        "schema_version" => 1,
        "command_id" => unique_id(),
        "expected_revisions" => %{},
        "type" => "legacy_event_append",
        "target_ids" => %{},
        "payload" => %{}
      },
      bundle,
      facts
    )
  end

  defp command(id, reads, operation) do
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

  defp ledger(ctx, id) do
    Gateway.protected_query(ctx.gateway, ctx.capability, %{
      "schema_version" => 1,
      "type" => "ledger",
      "ledger_id" => id,
      "generation" => 0
    })
  end

  defp unique_id, do: "critical-#{System.unique_integer([:positive, :monotonic])}"

  defp canonical_tmp,
    do: if(File.dir?("/private/tmp"), do: "/private/tmp", else: System.tmp_dir!())
end
