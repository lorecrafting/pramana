defmodule PramanaFoundry.Workflow.KernelPlanTest do
  @moduledoc """
  `Kernel.Plan`, the role-generic builders `decide/3` will call (FR-08B subcommit 2, commit
  2). `TransitionPlan.validate/1` is the oracle for every plan; `RecordCodec` is the oracle
  for the event/projection bijection and the `expected_revisions` key grammar.
  """
  use ExUnit.Case, async: true

  alias PramanaFoundry.DurableStore.{RecordCodec, TransitionPlan}
  alias PramanaFoundry.Test.Harness
  alias PramanaFoundry.Workflow.Kernel.{Event, Plan, State}

  # ── Prestates, driven through the harness ──────────────────────────────────────────

  defp drive({state, sequence}, specs) do
    Enum.reduce(specs, {state, sequence}, fn {type, entity_id, payload}, {state, sequence} ->
      {:ok, kind} = Event.entity_kind(type)

      revision =
        if kind == "control",
          do: state["control"]["revision"],
          else: get_in(state, ["tickets", entity_id, "revision"]) || 0

      event = %{
        "schema_version" => 1,
        "event_id" => "evt-#{type}-#{sequence + 1}",
        "type" => type,
        "sequence" => sequence + 1,
        "entity_kind" => kind,
        "entity_id" => entity_id,
        "entity_revision" => revision,
        "payload" => payload
      }

      assert {:ok, next} = Harness.apply(state, event)
      {next, sequence + 1}
    end)
  end

  defp queued do
    drive({State.new(), 0}, [
      {"ticket_admitted", "T1",
       %{
         "ticket_id" => "T1",
         "objective_id" => nil,
         "spec_revision_id" => "spec-1",
         "spec" => %{},
         "phase" => "queued",
         "reason" => nil
       }}
    ])
  end

  defp developing do
    drive(queued(), [
      {"launch_planned", "T1",
       %{"ticket_id" => "T1", "attempt_id" => "A1", "authority" => authority("X1")}}
    ])
  end

  # R4a: queued with the attempt retained, the execution closed.
  defp settled do
    drive(developing(), [
      {"launch_settled", "T1",
       %{
         "ticket_id" => "T1",
         "attempt_id" => "A1",
         "execution_id" => "X1",
         "settlement" => %{"schema_version" => 1}
       }}
    ])
  end

  defp paused do
    drive(queued(), [
      {"control_changed", "control",
       %{
         "control" => %{"schema_version" => 1, "control_id" => "ctl-1", "control_revision" => 1},
         "paused" => true,
         "draining" => false,
         "stop_status" => "running"
       }}
    ])
  end

  defp authority(execution_id) do
    %{
      "schema_version" => 1,
      "effect_id" => "eff-#{execution_id}",
      "role" => "developer",
      "work_owner" => "own-1",
      "ticket_id" => "T1",
      "attempt_id" => "A1",
      "execution_id" => execution_id,
      "policy_id" => "pol-1",
      "policy_revision" => 0,
      "control_id" => "ctl-1",
      "control_revision" => 0,
      "predecessor_effect_id" => nil,
      "infrastructure_generation" => 0
    }
  end

  defp launch_operations(execution_id) do
    [
      %{
        "type" => "reserve",
        "reservation_id" => "C1/reservation",
        "ledger_id" => "ledger-1",
        "generation" => 0,
        "owner_kind" => "effect",
        "owner_id" => "C1/effect",
        "units" => 1
      },
      %{
        "type" => "create_effect",
        "effect_id" => "C1/effect",
        "operation" => "launch",
        "scope" => "ticket:T1",
        "ticket_id" => "T1",
        "attempt_id" => "A1",
        "execution_id" => execution_id,
        "policy_id" => "pol-1",
        "policy_revision" => 0,
        "control_id" => "ctl-1",
        "control_revision" => 0,
        "request" => %{"request_id" => "C1/request", "role" => "developer"},
        "reservation_ids" => ["C1/reservation"],
        "leases" => []
      },
      %{
        "type" => "claim_effect",
        "effect_id" => "C1/effect",
        "claim_id" => "C1/claim",
        "writer_epoch" => "epoch-A"
      },
      %{"type" => "issue_claim", "claim_id" => "C1/claim", "writer_epoch" => "epoch-A"}
    ]
  end

  defp launch_spec,
    do: %{"planned" => "launch_planned", "operations" => launch_operations("C1/execution")}

  defp nonstart_spec do
    %{
      "settled" => "launch_settled",
      "operation" => %{"type" => "settle_claim", "claim_id" => "C1/claim"},
      "ticket_id" => "T1",
      "attempt_id" => "A1",
      "execution_id" => "X1",
      "reason" => "developer_launch_infrastructure",
      "resume_phase" => "developing"
    }
  end

  defp proposal(plan, discriminator) do
    Enum.find(plan["alternatives"], &(&1["discriminator"] == discriminator))["proposal"]
  end

  defp key(prefix, namespace, id),
    do:
      prefix <>
        Base.url_encode64(namespace, padding: false) <>
        "/" <> Base.url_encode64(id, padding: false)

  defp assert_bijection(plan) do
    for %{"proposal" => p} <- plan["alternatives"],
        do: assert({:ok, _} = RecordCodec.projection_plan(p["events"], p["projections"]))
  end

  # ── Builders ───────────────────────────────────────────────────────────────────────

  describe "block/3" do
    test "one unconditional ticket_blocked, the ticket read at its durable revision" do
      {state, _} = queued()

      spec = %{"ticket_id" => "T1", "reason" => "draining", "resume_phase" => "queued"}
      assert {:ok, plan} = Plan.block(state, "C1", spec)
      assert {:ok, ^plan} = TransitionPlan.validate(plan)
      assert_bijection(plan)

      assert plan["discriminator_kind"] == "unconditional_v1"
      assert plan["protected_operations"] == []
      assert plan["bindings"] == []
      # Kernel revision 1 is projection revision 0.
      assert plan["domain_reads"] == [%{"kind" => "ticket", "entity_id" => "T1", "revision" => 0}]
      assert plan["expected_domain_revision"] == 1

      [event] = proposal(plan, "unconditional")["events"]
      [projection] = proposal(plan, "unconditional")["projections"]
      assert event["event_id"] == "C1/e0"
      assert event["type"] == "ticket_blocked"
      assert event["payload"]["projection"]["namespace"] == "foundry.ticket.v1"
      assert projection["expected_revision"] == 0
      assert projection["revision"] == 1
      assert projection["value"]["phase"] == "blocked"
      assert projection["value"]["reason"] == "draining"
    end
  end

  describe "nonstart/3" do
    test "below the limit settles; at the limit settles and blocks, chained on one ticket" do
      {state, _} = developing()

      assert {:ok, plan} = Plan.nonstart(state, "C1", nonstart_spec())
      assert {:ok, ^plan} = TransitionPlan.validate(plan)
      assert_bijection(plan)

      assert plan["discriminator_kind"] == "infrastructure_limit_v1"

      assert plan["bindings"] == [
               %{
                 "name" => "settlement",
                 "operation_ordinal" => 0,
                 "output_kind" => "nonstart_settlement_v1",
                 "destination_slot" => "launch_settled.settlement"
               }
             ]

      below = proposal(plan, "below_infrastructure_limit")
      reached = proposal(plan, "infrastructure_limit_reached")

      assert Enum.map(below["events"], & &1["type"]) == ["launch_settled"]
      assert Enum.map(reached["events"], & &1["type"]) == ["launch_settled", "ticket_blocked"]
      assert hd(below["events"])["payload"]["settlement"] == %{"binding" => "settlement"}

      assert Enum.map(reached["projections"], &{&1["expected_revision"], &1["revision"]}) ==
               [{1, 2}, {2, 3}]

      assert List.last(below["projections"])["value"]["phase"] == "queued"
      assert List.last(reached["projections"])["value"]["phase"] == "blocked"

      assert List.last(reached["projections"])["value"]["reason"] ==
               "developer_launch_infrastructure"
    end

    test "a settle the reducer refuses is a rejection, not a plan" do
      {state, _} = queued()
      assert {:reject, :wrong_source_phase} = Plan.nonstart(state, "C1", nonstart_spec())
    end

    test "a staged operation of the wrong type is a caller error" do
      {state, _} = developing()
      spec = put_in(nonstart_spec(), ["operation", "type"], "close_attempt")
      assert {:error, :invalid_operations} = Plan.nonstart(state, "C1", spec)
    end
  end

  describe "close_attempt/3" do
    test "close_attempt, attempt_settled, then cancellation_finalized" do
      {state, _} =
        drive(settled(), [{"cancellation_requested", "T1", %{"ticket_id" => "T1"}}])

      spec = %{
        "ticket_id" => "T1",
        "attempt_id" => "A1",
        "disposition" => "cancelled",
        "reason_code" => "cancel_requested",
        "then" => [
          {"cancellation_finalized", %{"ticket_id" => "T1", "disposition" => "cancelled"}}
        ]
      }

      assert {:ok, plan} = Plan.close_attempt(state, "C1", spec)
      assert {:ok, ^plan} = TransitionPlan.validate(plan)
      assert_bijection(plan)

      assert plan["protected_operations"] == [
               %{
                 "schema_version" => 1,
                 "ordinal" => 0,
                 "type" => "close_attempt",
                 "input" => %{
                   "type" => "close_attempt",
                   "scope" => "ticket:T1",
                   "ticket_id" => "T1",
                   "attempt_id" => "A1"
                 }
               }
             ]

      unconditional = proposal(plan, "unconditional")

      assert Enum.map(unconditional["events"], & &1["type"]) ==
               ["attempt_settled", "cancellation_finalized"]

      assert List.last(unconditional["projections"])["value"]["phase"] == "cancelled"
    end
  end

  describe "launch/3" do
    test "stages the four launch operations and plans the execution the effect names" do
      {state, _} = queued()

      assert {:ok, plan} = Plan.launch(state, "C1", launch_spec())
      assert_bijection(plan)

      assert Enum.map(plan["protected_operations"], & &1["type"]) ==
               ~w(reserve create_effect claim_effect issue_claim)

      assert plan["bindings"] == [
               %{
                 "name" => "authority",
                 "operation_ordinal" => 3,
                 "output_kind" => "launch_authority_v1",
                 "destination_slot" => "launch_planned.authority"
               }
             ]

      # The control singleton is read, so a pause committed before submit fails CAS.
      assert plan["domain_reads"] == [
               %{"kind" => "ticket", "entity_id" => "T1", "revision" => 0},
               %{"kind" => "state", "entity_id" => "control", "revision" => "absent"}
             ]

      [projection] = proposal(plan, "unconditional")["projections"]
      assert projection["value"]["phase"] == "developing"
      assert projection["value"]["active_attempt_id"] == "A1"

      assert projection["value"]["attempts"]["A1"]["executions"]["C1/execution"]["lifecycle"] ==
               "pending"
    end

    # Commit 0 admits claim_effect to TransitionPlan's operation types.
    test "the launch plan validates" do
      {state, _} = queued()
      assert {:ok, plan} = Plan.launch(state, "C1", launch_spec())
      assert {:ok, ^plan} = TransitionPlan.validate(plan)
    end

    test "a launch the reducer refuses under pause is a rejection" do
      {state, _} = paused()
      assert {:reject, :control_paused} = Plan.launch(state, "C1", launch_spec())
    end

    test "operations out of order are a caller error" do
      {state, _} = queued()
      spec = Map.update!(launch_spec(), "operations", &Enum.reverse/1)
      assert {:error, :invalid_operations} = Plan.launch(state, "C1", spec)
    end
  end

  # ── expected_revisions ─────────────────────────────────────────────────────────────

  describe "expected_revisions/2" do
    test "a written read is projection/, a read-only one dependency/, a root ledger its own" do
      {state, _} = queued()
      assert {:ok, plan} = Plan.launch(state, "C1", launch_spec())
      protected = %{Plan.root_ledger_key("ledger-1", 0) => 3}

      assert {:ok, revisions} = Plan.expected_revisions(plan, protected)

      assert revisions == %{
               key("projection/", "foundry.ticket.v1", "T1") => 0,
               key("dependency/", "foundry.state.v1", "control") => "absent",
               ("root_ledger/" <> Base.url_encode64("ledger-1", padding: false) <> "/0") => 3
             }

      assert {:ok, ^revisions} = RecordCodec.normalize_revision_reads(revisions)

      command = %{"command_id" => "C1", "expected_revisions" => %{}}

      assert {:ok, %{"expected_revisions" => ^revisions}} =
               Plan.command(command, plan, protected)
    end

    # A command-level `ledger/` or `policy/` key reads the legacy tables, not the root rows.
    test "a protected key other than a root ledger's is refused" do
      {state, _} = queued()
      assert {:ok, plan} = Plan.launch(state, "C1", launch_spec())

      for key <- ["allocation", "ledger/" <> Base.url_encode64("ledger-1", padding: false)] do
        assert {:error, :invalid_fact_key} = Plan.expected_revisions(plan, %{key => 0})
      end
    end
  end
end
