defmodule PramanaFoundry.DurableStore.ReviewIndependenceTest do
  # Reviewer independence (REPAIR-PLAN.md#reviewer-independence-amendment), refused by Core
  # through the real Gateway. The operator policy's `independent_of_roles` names the roles;
  # no controller-supplied field takes part. Each refusal commits nothing, and a neighbouring
  # call with an independent principal is admitted, so the refusal is not vacuous.
  use ExUnit.Case, async: false

  alias PramanaFoundry.DurableStore.Gateway

  @independence %{"reviewer" => ["developer"]}

  setup do
    root =
      Path.join(
        canonical_tmp(),
        "review-independence-#{System.pid()}-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir!(root)
    path = Path.join(root, "authority.sqlite3")
    capability = make_ref()

    assert :ok =
             Gateway.initialize(path,
               installation_id: "installation-fr08b",
               repository_id: "repository-fr08b"
             )

    gateway =
      start_supervised!(
        {Gateway,
         path: path, protected_capability: capability, writer_epoch: "writer-epoch-fr08b"}
      )

    on_exit(fn -> File.rm_rf!(root) end)
    %{gateway: gateway, capability: capability}
  end

  test "a review issued by the producing principal is refused; another principal is admitted",
       ctx do
    seed!(ctx, @independence)

    assert %{"disposition" => "accepted"} =
             current!(ctx, "principal-A", effect("dev-1", "developer"))

    assert %{"disposition" => "rejected", "reason_code" => "principal_not_independent"} =
             current!(ctx, "principal-A", effect("rev-1", "reviewer"))

    assert {:error, :not_found} = fact(ctx, "effect", "effect_id", "rev-1")

    assert %{"disposition" => "accepted"} =
             current!(ctx, "principal-B", effect("rev-1", "reviewer"))

    assert {:ok, %{"issuer" => "principal-B"}} = fact(ctx, "effect", "effect_id", "rev-1")
  end

  test "a review whose predecessor chain holds the producing principal is refused", ctx do
    seed!(ctx, %{})

    assert %{"disposition" => "accepted"} =
             current!(ctx, "principal-A", effect("dev-1", "developer"))

    # Admitted while the policy required nothing, then superseded by a retry.
    assert %{"disposition" => "accepted"} =
             current!(ctx, "principal-A", effect("rev-1", "reviewer"))

    assert %{"disposition" => "accepted"} = current!(ctx, "operator", cancel("rev-1"))
    assert %{"disposition" => "accepted"} = current!(ctx, "operator", set_policy(@independence))

    # A fresh principal does not launder the chain it continues.
    assert %{"disposition" => "rejected", "reason_code" => "principal_not_independent"} =
             current!(
               ctx,
               "principal-B",
               effect("rev-2", "reviewer", ordinal: 1, predecessor: "rev-1", policy_revision: 1)
             )

    assert {:error, :not_found} = fact(ctx, "effect", "effect_id", "rev-2")

    # Neighbour: the same fresh principal, in an attempt with no tainted chain, is admitted.
    assert %{"disposition" => "accepted"} =
             current!(
               ctx,
               "principal-A",
               effect("dev-2", "developer", attempt_id: "A2", policy_revision: 1)
             )

    assert %{"disposition" => "accepted"} =
             current!(
               ctx,
               "principal-B",
               effect("rev-3", "reviewer", attempt_id: "A2", policy_revision: 1)
             )
  end

  test "an execution's inbox actor is one of its principals, whichever is recorded first", ctx do
    seed!(ctx, @independence)

    assert %{"disposition" => "accepted"} =
             current!(ctx, "principal-A", effect("dev-1", "developer"))

    assert %{"disposition" => "accepted"} =
             current!(ctx, "principal-H", append("execution-dev-1"))

    assert %{"disposition" => "accepted"} =
             current!(ctx, "principal-B", effect("rev-1", "reviewer"))

    # The producer's inbox actor may not author the review's results.
    assert %{"disposition" => "rejected", "reason_code" => "principal_not_independent"} =
             current!(ctx, "principal-H", append("execution-rev-1"))

    assert {:error, _} = fact(ctx, "inbox", "execution_id", "execution-rev-1")

    assert %{"disposition" => "accepted"} =
             current!(ctx, "principal-C", append("execution-rev-1"))

    # An inbox pinned to the producer's actor before the effect exists taints the effect.
    assert %{"disposition" => "accepted"} =
             current!(ctx, "principal-A", effect("dev-2", "developer", attempt_id: "A2"))

    assert %{"disposition" => "accepted"} =
             current!(ctx, "principal-A", append("execution-rev-2"))

    assert %{"disposition" => "rejected", "reason_code" => "principal_not_independent"} =
             current!(ctx, "principal-D", effect("rev-2", "reviewer", attempt_id: "A2"))

    assert {:error, :not_found} = fact(ctx, "effect", "effect_id", "rev-2")

    assert %{"disposition" => "accepted"} =
             current!(
               ctx,
               "principal-D",
               effect("rev-2", "reviewer", attempt_id: "A2", execution_id: "execution-rev-2b")
             )
  end

  test "the requirement cannot be skipped by what the controller sends or when", ctx do
    seed!(ctx, @independence)

    assert %{"disposition" => "accepted"} =
             current!(ctx, "principal-A", effect("dev-1", "developer"))

    # The request has no independence field to omit; one added to waive it changes nothing.
    assert %{"disposition" => "rejected", "reason_code" => "principal_not_independent"} =
             current!(
               ctx,
               "principal-A",
               effect("rev-1", "reviewer",
                 extra: %{"independent_of_effect_id" => nil, "independence" => "waived"}
               )
             )

    # Order does not help: a producer launched after the review is refused too.
    assert %{"disposition" => "accepted"} =
             current!(ctx, "principal-B", effect("rev-1", "reviewer", attempt_id: "A2"))

    assert %{"disposition" => "rejected", "reason_code" => "principal_not_independent"} =
             current!(ctx, "principal-B", effect("dev-2", "developer", attempt_id: "A2"))

    assert %{"disposition" => "accepted"} =
             current!(ctx, "principal-A", effect("dev-2", "developer", attempt_id: "A2"))

    # A malformed requirement fails closed.
    assert %{"disposition" => "accepted"} =
             current!(ctx, "operator", set_policy(%{"reviewer" => "developer"}))

    assert %{"disposition" => "rejected", "reason_code" => "principal_not_independent"} =
             current!(
               ctx,
               "principal-Z",
               effect("dev-3", "developer", attempt_id: "A3", policy_revision: 1)
             )
  end

  # Review finding I1: the pairing an attempt's effects pinned binds the rest of the attempt.
  test "a pairing dropped from the policy after the producer still binds the attempt", ctx do
    seed!(ctx, @independence)

    assert %{"disposition" => "accepted"} =
             current!(ctx, "principal-A", effect("dev-1", "developer"))

    assert %{"disposition" => "accepted"} = current!(ctx, "operator", set_policy(%{}))

    assert %{"disposition" => "rejected", "reason_code" => "principal_not_independent"} =
             current!(ctx, "principal-A", effect("rev-1", "reviewer", policy_revision: 1))

    assert {:error, :not_found} = fact(ctx, "effect", "effect_id", "rev-1")

    assert %{"disposition" => "accepted"} =
             current!(ctx, "principal-B", effect("rev-1", "reviewer", policy_revision: 1))
  end

  test "a review under a second policy without the pairing is still bound", ctx do
    seed!(ctx, @independence)

    assert %{"disposition" => "accepted"} =
             current!(ctx, "principal-A", effect("dev-1", "developer"))

    assert %{"disposition" => "accepted"} =
             current!(ctx, "operator", set_policy(%{}, "policy-2"))

    assert %{"disposition" => "rejected", "reason_code" => "principal_not_independent"} =
             current!(ctx, "principal-A", effect("rev-1", "reviewer", policy_id: "policy-2"))

    assert {:error, :not_found} = fact(ctx, "effect", "effect_id", "rev-1")

    assert %{"disposition" => "accepted"} =
             current!(ctx, "principal-B", effect("rev-1", "reviewer", policy_id: "policy-2"))
  end

  test "a first inbox append after the pairing is dropped is still bound", ctx do
    seed!(ctx, @independence)

    assert %{"disposition" => "accepted"} =
             current!(ctx, "principal-A", effect("dev-1", "developer"))

    assert %{"disposition" => "accepted"} =
             current!(ctx, "principal-B", effect("rev-1", "reviewer"))

    assert %{"disposition" => "accepted"} = current!(ctx, "operator", set_policy(%{}))

    assert %{"disposition" => "rejected", "reason_code" => "principal_not_independent"} =
             current!(ctx, "principal-A", append("execution-rev-1"))

    assert {:error, _} = fact(ctx, "inbox", "execution_id", "execution-rev-1")

    assert %{"disposition" => "accepted"} =
             current!(ctx, "principal-C", append("execution-rev-1"))
  end

  defp seed!(ctx, independence) do
    assert %{"disposition" => "accepted"} = current!(ctx, "operator", set_policy(independence))

    assert %{"disposition" => "accepted"} =
             current!(ctx, "operator", %{
               "type" => "set_control",
               "control_id" => "control-1",
               "value" => %{"status" => "active"}
             })
  end

  defp set_policy(independence, policy_id \\ "policy-1") do
    %{
      "type" => "set_policy",
      "policy_id" => policy_id,
      "value" => %{
        "allowed_operations" => ["launch"],
        "allowed_scopes" => ["ticket:T1"],
        "independent_of_roles" => independence
      }
    }
  end

  defp cancel(id), do: %{"type" => "cancel_effect", "effect_id" => id, "proof" => "unissued"}

  defp append(execution_id) do
    %{
      "type" => "append_inbox",
      "execution_id" => execution_id,
      "sequence" => 1,
      "item_kind" => "result",
      "payload" => %{}
    }
  end

  defp effect(id, role, opts \\ []) do
    predecessor = Keyword.get(opts, :predecessor)

    request =
      %{
        "request_id" => "request-#{id}",
        "role" => role,
        "phase_generation" => 0,
        "operation_ordinal" => Keyword.get(opts, :ordinal, 0)
      }
      |> then(&if predecessor, do: Map.put(&1, "predecessor_effect_id", predecessor), else: &1)
      |> Map.merge(Keyword.get(opts, :extra, %{}))

    %{
      "type" => "create_effect",
      "effect_id" => id,
      "request" => request,
      "operation" => "launch",
      "scope" => "ticket:T1",
      "ticket_id" => "T1",
      "attempt_id" => Keyword.get(opts, :attempt_id, "A1"),
      "execution_id" => Keyword.get(opts, :execution_id, "execution-#{id}"),
      "policy_id" => Keyword.get(opts, :policy_id, "policy-1"),
      "policy_revision" => Keyword.get(opts, :policy_revision, 0),
      "control_id" => "control-1",
      "control_revision" => 0,
      "reservation_ids" => [],
      "leases" => []
    }
  end

  # Submits with an empty read set, then again with the revisions the store says it needs.
  defp current!(ctx, actor, operation) do
    id = "cmd-#{System.unique_integer([:positive, :monotonic])}"
    assert {:ok, first, :committed} = protected(ctx, actor, id <> "-PROBE", %{}, operation)

    if first["reason_code"] == "incomplete_read_set" do
      assert {:ok, result, :committed} =
               protected(ctx, actor, id, first["facts"]["required_revisions"], operation)

      result
    else
      first
    end
  end

  defp protected(ctx, actor, id, reads, operation) do
    Gateway.protected_command(ctx.gateway, ctx.capability, actor, %{
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

  defp canonical_tmp do
    if File.dir?("/private/tmp"), do: "/private/tmp", else: System.tmp_dir!()
  end
end
