defmodule PramanaFoundry.Workflow.DecideE2ETest do
  @moduledoc """
  `Kernel.decide/3` end to end through `Gateway.atomic_bundle/4`: one test per plan shape
  (FR08B-SUBCOMMIT2-DECIDE-DESIGN-2026-09-23.md, Testing).

  The test plays the adapter the design leaves to O1: it queries protected facts, probes
  each staged operation's prestate reads, and submits the plan `decide/3` returned. Kernel
  state is never carried between commands. Before every decision it is rebuilt from the
  committed durable events alone, so every step is also the restart trace, and after every
  commit the rebuilt ticket must equal the projection the plan committed - the
  substitution law, checked against the store rather than against the planner's own dry
  run.
  """
  use ExUnit.Case, async: false

  alias Exqlite.Sqlite3
  alias PramanaFoundry.DurableStore.{Database, Gateway, ProtectedPrimitives}
  alias PramanaFoundry.Test.Harness
  alias PramanaFoundry.Workflow.Kernel, as: WorkflowKernel
  alias PramanaFoundry.Workflow.Kernel.{Event, Executions, Plan, State}

  setup do
    tmp = if File.dir?("/private/tmp"), do: "/private/tmp", else: System.tmp_dir!()
    root = Path.join(tmp, "decide-e2e-#{System.pid()}-#{System.unique_integer([:positive])}")
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

  # ── The adapter ────────────────────────────────────────────────────────────────────

  # `reviewer` is the reviewer's `{infrastructure limit, units}` on its own ledger,
  # `ledger-r`, so a reviewer launch never draws on the developer's.
  # `extra` is merged into the policy value.
  defp seed!(ctx, limit, units, {reviewer_limit, reviewer_units} \\ {3, 2}, extra \\ %{}) do
    root!(ctx, %{
      "type" => "set_policy",
      "policy_id" => "policy-1",
      "value" =>
        Map.merge(
          %{
            "allowed_operations" => ["launch"],
            "allowed_scopes" => ["ticket:T1"],
            "infrastructure_attempt_limits" => %{
              "developer" => limit,
              "reviewer" => reviewer_limit
            }
          },
          extra
        )
    })

    root!(ctx, %{
      "type" => "grant_ledger",
      "ledger_id" => "ledger-r",
      "generation" => 0,
      "dimension" => "starts.reviewer",
      "units" => reviewer_units
    })

    root!(ctx, %{
      "type" => "set_control",
      "control_id" => "control-1",
      "value" => %{"status" => "active"}
    })

    root!(ctx, %{
      "type" => "grant_ledger",
      "ledger_id" => "ledger-1",
      "generation" => 0,
      "dimension" => "starts.developer",
      "units" => units
    })

    admit!(ctx)
  end

  # A root command, retried once with the read set the protected layer names.
  defp root!(ctx, operation) do
    request = fn reads ->
      %{
        "schema_version" => 1,
        "command_id" => "root-#{System.unique_integer([:positive, :monotonic])}",
        "expected_revisions" => reads,
        "operation" => operation
      }
    end

    assert {:ok, first, :committed} =
             Gateway.protected_command(ctx.gateway, ctx.capability, "operator", request.(%{}))

    if first["reason_code"] == "incomplete_read_set" do
      reads = first["facts"]["required_revisions"]

      assert {:ok, %{"disposition" => "accepted"} = accepted, :committed} =
               Gateway.protected_command(
                 ctx.gateway,
                 ctx.capability,
                 "operator",
                 request.(reads)
               )

      accepted
    else
      assert first["disposition"] == "accepted", inspect(first)
      first
    end
  end

  # Admission is subcommit 5's ingress; the test commits it through the same generic
  # builder, with no protected operation.
  defp admit!(ctx) do
    payload = %{
      "ticket_id" => "T1",
      "objective_id" => nil,
      "spec_revision_id" => "spec-1",
      "spec" => %{},
      "phase" => "queued",
      "reason" => nil
    }

    ingress!(ctx, "ADMIT", %{"events" => [{"ticket_admitted", "T1", payload}]})
  end

  defp ingress!(ctx, id, spec) do
    assert {:ok, plan} = Plan.unconditional(replay(ctx), id, spec)

    command = %{
      "schema_version" => 1,
      "command_id" => id,
      "type" => "enqueue",
      "target_ids" => %{"ticket_id" => "T1"},
      "payload" => %{}
    }

    assert {:ok, decision} = Plan.decision({:ok, plan}, command)
    assert {:ok, %{"disposition" => "accepted"}, :committed} = submit(ctx, decision)
  end

  defp command(id, type, payload \\ %{"role" => "developer"}) do
    %{
      "schema_version" => 1,
      "command_id" => id,
      "type" => type,
      "target_ids" => %{"ticket_id" => "T1"},
      "payload" => payload,
      "expected_revisions" => %{}
    }
  end

  defp launch_facts(ctx, predecessor \\ nil, ledger_id \\ "ledger-1") do
    {:ok, policy} = query(ctx, %{"type" => "policy", "policy_id" => "policy-1"})
    {:ok, control} = query(ctx, %{"type" => "control", "control_id" => "control-1"})

    {:ok, ledger} =
      query(ctx, %{"type" => "ledger", "ledger_id" => ledger_id, "generation" => 0})

    %{
      "policy" => policy,
      "control" => control,
      "allocation" => ledger,
      "writer_epoch" => "epoch-A",
      "predecessor_effect_id" => predecessor
    }
  end

  defp settle_facts(launch_id) do
    %{
      "settle_claim" => %{
        "type" => "settle_claim",
        "claim_id" => Plan.id(launch_id, "claim"),
        "receipt_id" => Plan.id(launch_id, "receipt"),
        "request_id" => Plan.id(launch_id, "request"),
        "outcome" => "non_started",
        "proof" => "issuer_quiescent",
        "payload" => %{
          "quiescence_epoch" => "epoch-A",
          "failure_class" => "backend_refused_start"
        }
      }
    }
  end

  defp query(ctx, query),
    do: Gateway.protected_query(ctx.gateway, ctx.capability, Map.put(query, "schema_version", 1))

  defp decide(ctx, command, facts), do: WorkflowKernel.decide(replay(ctx), command, facts)

  # Each staged operation carries the prestate reads Gateway requires it to state. `actor`
  # is the authenticated principal Core records as the effect issuer.
  defp submit(ctx, %{"command" => command, "plan" => plan}, actor \\ "operator") do
    conn = open(ctx)

    {operations, _prior} =
      Enum.map_reduce(plan["protected_operations"], [], fn %{"input" => op}, prior ->
        assert {:ok, reads} =
                 ProtectedPrimitives.required_bundle_prestate_revisions(
                   conn,
                   op,
                   Enum.reverse(prior)
                 )

        {%{"schema_version" => 1, "expected_revisions" => reads, "operation" => op}, [op | prior]}
      end)

    assert :ok = Sqlite3.close(conn)

    Gateway.atomic_bundle(ctx.gateway, ctx.capability, actor, %{
      "schema_version" => 2,
      "actor_id" => actor,
      "inputs" => %{
        "recorded_at" => "2026-09-23T00:00:00Z",
        "transition_id" => command["command_id"]
      },
      "command" => command,
      "operations" => operations,
      "plan" => plan
    })
  end

  defp commit!(ctx, decision, actor \\ "operator") do
    assert {:ok, result, :committed} = submit(ctx, decision, actor)
    assert result["disposition"] == "accepted", inspect(result)
    assert_substitution_law(ctx)
    result
  end

  # ── Replay ─────────────────────────────────────────────────────────────────────────

  # Kernel state from the committed durable events alone: entity kind from the event
  # type, entity id and revision from the projection the event carries, sequence from the
  # store. Nothing the planner computed is read.
  defp replay(ctx) do
    conn = open(ctx)

    assert {:ok, rows} =
             Database.query(conn, "SELECT seq, event FROM events ORDER BY seq", [])

    assert :ok = Sqlite3.close(conn)
    namespaces = Map.values(Plan.namespaces())

    Enum.reduce(rows, State.new(), fn [seq, bytes], state ->
      event = decode(bytes)
      projection = event["payload"]["projection"]

      if event["type"] in Event.types() and projection["namespace"] in namespaces do
        {:ok, kind} = Event.entity_kind(event["type"])

        envelope = %{
          "schema_version" => 1,
          "event_id" => event["event_id"],
          "type" => event["type"],
          "sequence" => seq,
          "entity_kind" => kind,
          "entity_id" => projection["entity_id"],
          "entity_revision" => projection["revision"],
          "payload" => Map.delete(event["payload"], "projection")
        }

        assert {:ok, next} = Harness.apply(state, envelope)
        next
      else
        state
      end
    end)
  end

  defp assert_substitution_law(ctx) do
    conn = open(ctx)

    assert {:ok, [[bytes]]} =
             Database.query(
               conn,
               "SELECT projection FROM projections WHERE namespace = ? AND entity_id = ?",
               ["foundry.ticket.v1", "T1"]
             )

    assert :ok = Sqlite3.close(conn)
    replayed = replay(ctx)["tickets"]["T1"] |> JSON.encode!() |> JSON.decode!()
    assert decode(bytes)["value"] == replayed
  end

  defp ticket(ctx), do: replay(ctx)["tickets"]["T1"]

  defp open(ctx) do
    assert {:ok, conn} = Sqlite3.open(ctx.path, mode: :readonly)
    conn
  end

  defp decode(bytes), do: bytes |> JSON.decode!()

  defp launch_decision(ctx, id, predecessor \\ nil) do
    assert {:ok, decision} =
             decide(ctx, command(id, "plan_launch"), launch_facts(ctx, predecessor))

    decision
  end

  # Control and cancel ingress are subcommit 5's. The control change binds the fact a
  # set_control on a second root control produces, so the launch's own control-1 and the
  # operations' read sets are untouched and only the kernel's control entity moves.
  defp control!(ctx, flags) do
    ingress!(ctx, "CONTROL", %{
      "operations" => [
        %{
          "type" => "set_control",
          "control_id" => "control-2",
          "value" => %{"status" => "active"}
        }
      ],
      "bindings" => [{"control", 0, "control_fact_v1", "control_changed.control"}],
      "stand_ins" => %{
        "control" => %{
          "schema_version" => 1,
          "control_id" => "control-2",
          "control_revision" => 0
        }
      },
      "events" => [
        {"control_changed", "control",
         Map.merge(
           %{
             "control" => %{"binding" => "control"},
             "paused" => false,
             "draining" => false,
             "stop_status" => "running"
           },
           flags
         )}
      ]
    })
  end

  defp cancel!(ctx) do
    ingress!(ctx, "CANCEL", %{
      "events" => [{"cancellation_requested", "T1", %{"ticket_id" => "T1"}}]
    })
  end

  # Delegates the ledger's remaining units away, so current allocation is genuinely short.
  # (A bare reserve would not do: a reservation holds nothing until its effect activates it.)
  defp drain_ledger!(ctx, ledger_id \\ "ledger-1", dimension \\ "starts.developer") do
    {:ok, %{"available" => available}} =
      query(ctx, %{"type" => "ledger", "ledger_id" => ledger_id, "generation" => 0})

    root!(ctx, %{
      "type" => "delegate_allocation",
      "parent_ledger_id" => ledger_id,
      "parent_generation" => 0,
      "child_ledger_id" => ledger_id <> "-other",
      "child_generation" => 0,
      "dimension" => dimension,
      "units" => available
    })

    assert {:ok, %{"available" => 0}} =
             query(ctx, %{"type" => "ledger", "ledger_id" => ledger_id, "generation" => 0})
  end

  # ── Scenarios ──────────────────────────────────────────────────────────────────────

  # Launch, then a proved non-start, through decide/3. Returns the launch command id.
  defp launch_and_nonstart!(ctx) do
    commit!(ctx, launch_decision(ctx, "L1"))
    assert {:ok, settle} = decide(ctx, command("S1", "settle_nonstart"), settle_facts("L1"))
    {commit!(ctx, settle), "L1"}
  end

  describe "settle_nonstart (R4a.01)" do
    test "below the limit: queued, attempt retained, execution closed, one ordinal", ctx do
      seed!(ctx, 3, 2)
      {result, _} = launch_and_nonstart!(ctx)
      assert result["selected_discriminator"] == "below_infrastructure_limit"

      # The restart trace (REPAIR-PLAN "restart after settlement but before redispatch"):
      # state rebuilt from durable events alone holds one owner, one ordinal and no live
      # execution.
      ticket = ticket(ctx)
      assert ticket["phase"] == "queued"
      assert ticket["resume_phase"] == "developing"
      assert ticket["reason"] == "developer_launch_non_started"
      assert ticket["active_attempt_id"] == "L1/attempt"
      assert Map.keys(ticket["attempts"]) == ["L1/attempt"]
      assert ticket["infrastructure"]["ordinals"]["developer"] == 1
      assert Executions.open_executions(ticket) == []

      assert {:ok, settlement} =
               query(ctx, %{"type" => "infrastructure_settlement", "effect_id" => "L1/effect"})

      assert settlement["ordinal"] == 1
    end

    test "at the limit: blocked(developer_launch_infrastructure), resumable", ctx do
      seed!(ctx, 1, 2)
      {result, _} = launch_and_nonstart!(ctx)
      assert result["selected_discriminator"] == "infrastructure_limit_reached"

      ticket = ticket(ctx)
      assert ticket["phase"] == "blocked"
      assert ticket["reason"] == "developer_launch_infrastructure"
      assert ticket["resume_phase"] == "developing"
      assert ticket["attempts"]["L1/attempt"]["phase"] == "active"
      assert Executions.open_executions(ticket) == []
    end

    test "a settle with no open developer is refused by the reducer, not planned", ctx do
      seed!(ctx, 3, 2)

      assert {:reject, :wrong_source_phase} =
               decide(ctx, command("S0", "settle_nonstart"), settle_facts("L0"))
    end
  end

  describe "plan_launch (R4.04, R4a controls)" do
    test "a fresh launch creates the attempt and its pending developer intent", ctx do
      seed!(ctx, 3, 2)
      commit!(ctx, launch_decision(ctx, "L1"))

      ticket = ticket(ctx)
      assert ticket["phase"] == "developing"
      assert ticket["active_attempt_id"] == "L1/attempt"
      [{"L1/execution", intent}] = Map.to_list(ticket["attempts"]["L1/attempt"]["executions"])
      assert {intent.role, intent.lifecycle} == {"developer", "pending"}

      assert {:ok, %{"status" => "issued", "operation_ordinal" => 0}} =
               query(ctx, %{"type" => "effect", "effect_id" => "L1/effect"})
    end

    # R4.04.o1: "Create a fresh attempt unless R4a retained a resumable developer attempt".
    test "the retry after a non-start reuses the retained attempt and names its predecessor",
         ctx do
      seed!(ctx, 3, 2)
      launch_and_nonstart!(ctx)
      commit!(ctx, launch_decision(ctx, "L2", "L1/effect"))

      ticket = ticket(ctx)
      assert ticket["phase"] == "developing"
      assert Map.keys(ticket["attempts"]) == ["L1/attempt"]

      assert Map.keys(ticket["attempts"]["L1/attempt"]["executions"]) ==
               ["L1/execution", "L2/execution"]

      assert {:ok, effect} = query(ctx, %{"type" => "effect", "effect_id" => "L2/effect"})
      assert {effect["attempt_id"], effect["operation_ordinal"]} == {"L1/attempt", 1}
      assert effect["predecessor_effect_id"] == "L1/effect"
    end

    test "drain blocks the retained attempt with its resume phase", ctx do
      seed!(ctx, 3, 2)
      launch_and_nonstart!(ctx)
      control!(ctx, %{"draining" => true})

      assert {:ok, decision} =
               decide(ctx, command("L2", "plan_launch"), launch_facts(ctx, "L1/effect"))

      assert decision["plan"]["protected_operations"] == []
      commit!(ctx, decision)

      ticket = ticket(ctx)
      assert {ticket["phase"], ticket["reason"]} == {"blocked", "draining"}
      assert ticket["resume_phase"] == "developing"
      assert ticket["attempts"]["L1/attempt"]["phase"] == "active"
      assert ticket["infrastructure"]["ordinals"]["developer"] == 1
    end

    test "drain rejects a fresh launch, which stays queued", ctx do
      seed!(ctx, 3, 2)
      control!(ctx, %{"draining" => true})

      assert {:reject, :control_draining} =
               decide(ctx, command("L1", "plan_launch"), launch_facts(ctx))

      assert ticket(ctx)["phase"] == "queued"
    end

    # R4a.01.o9.
    test "short allocation exhausts the retained attempt and the ticket", ctx do
      seed!(ctx, 3, 2)
      launch_and_nonstart!(ctx)
      drain_ledger!(ctx)

      assert {:ok, decision} =
               decide(ctx, command("L2", "plan_launch"), launch_facts(ctx, "L1/effect"))

      assert Enum.map(decision["plan"]["protected_operations"], & &1["type"]) == ["close_attempt"]
      commit!(ctx, decision)

      ticket = ticket(ctx)
      assert ticket["phase"] == "exhausted"
      assert ticket["active_attempt_id"] == nil
      assert ticket["attempts"]["L1/attempt"]["disposition"] == "exhausted"
    end

    # F1 of the subcommit 2 review: the exhaustion plan stages only close_attempt, whose
    # read set holds no ledger, so the allocation it chose on is a declared command-level
    # read. Units returned between decide/3 and submit must fail CAS, not commit exhausted.
    test "allocation returned after the exhaustion decision refuses it", ctx do
      seed!(ctx, 3, 2)
      launch_and_nonstart!(ctx)
      drain_ledger!(ctx)

      assert {:ok, decision} =
               decide(ctx, command("L2", "plan_launch"), launch_facts(ctx, "L1/effect"))

      assert Enum.map(decision["plan"]["protected_operations"], & &1["type"]) == ["close_attempt"]

      root!(ctx, %{
        "type" => "return_allocation",
        "child_ledger_id" => "ledger-other",
        "child_generation" => 0,
        "units" => 1
      })

      assert {:ok, %{"available" => 1}} =
               query(ctx, %{"type" => "ledger", "ledger_id" => "ledger-1", "generation" => 0})

      assert {:ok, %{"disposition" => "rejected"} = result, _} = submit(ctx, decision)
      assert result["reason_code"] == "revision_conflict", inspect(result)
      assert ticket(ctx)["phase"] == "queued"
      assert ticket(ctx)["attempts"]["L1/attempt"]["phase"] == "active"
    end

    # R4.04.o3: "Pre-intent denial remains queued and consumes no start unit or
    # infrastructure ordinal".
    test "short allocation is a pre-intent denial for a fresh launch", ctx do
      seed!(ctx, 3, 2)
      drain_ledger!(ctx)
      facts = launch_facts(ctx)

      assert {:reject, :allocation_unavailable} = decide(ctx, command("L1", "plan_launch"), facts)

      ticket = ticket(ctx)
      assert ticket["phase"] == "queued"
      assert ticket["attempts"] == %{}
      assert ticket["infrastructure"]["ordinals"]["developer"] == 0
      # No start unit held: the protected facts read back unchanged.
      assert launch_facts(ctx) == facts
    end

    test "pause is decided before drain, and pending cancel before both", ctx do
      seed!(ctx, 3, 2)
      launch_and_nonstart!(ctx)
      control!(ctx, %{"paused" => true, "draining" => true})
      facts = launch_facts(ctx, "L1/effect")

      assert {:reject, :control_paused} = decide(ctx, command("L2", "plan_launch"), facts)

      cancel!(ctx)
      assert {:reject, :cancel_pending} = decide(ctx, command("L2", "plan_launch"), facts)
    end

    test "cancel pending is decided before drain would block", ctx do
      seed!(ctx, 3, 2)
      launch_and_nonstart!(ctx)
      control!(ctx, %{"draining" => true})
      cancel!(ctx)

      assert {:reject, :cancel_pending} =
               decide(ctx, command("L2", "plan_launch"), launch_facts(ctx, "L1/effect"))
    end

    test "cancel pending is decided before allocation would exhaust", ctx do
      seed!(ctx, 3, 2)
      launch_and_nonstart!(ctx)
      drain_ledger!(ctx)
      cancel!(ctx)

      assert {:reject, :cancel_pending} =
               decide(ctx, command("L2", "plan_launch"), launch_facts(ctx, "L1/effect"))
    end

    test "pause is decided before allocation would exhaust", ctx do
      seed!(ctx, 3, 2)
      launch_and_nonstart!(ctx)
      drain_ledger!(ctx)
      control!(ctx, %{"paused" => true})

      assert {:reject, :control_paused} =
               decide(ctx, command("L2", "plan_launch"), launch_facts(ctx, "L1/effect"))
    end

    # The control singleton is a declared read: a pause committed between decide/3 and
    # submit fails the launch's CAS, and nothing it staged survives.
    test "a pause committed after the decision refuses the launch", ctx do
      seed!(ctx, 3, 2)
      decision = launch_decision(ctx, "L1")
      control!(ctx, %{"paused" => true})

      assert {:ok, %{"disposition" => "rejected"} = result, _} = submit(ctx, decision)
      assert inspect(result) =~ "revision_conflict"
      assert {:error, :not_found} = query(ctx, %{"type" => "effect", "effect_id" => "L1/effect"})
      assert ticket(ctx)["phase"] == "queued"
    end

    test "malformed facts are an error" do
      assert {:error, :invalid_facts} =
               WorkflowKernel.decide(State.new(), command("L1", "plan_launch"), %{})
    end
  end

  # ── Reviewer (subcommit 3) ─────────────────────────────────────────────────────────

  @reviewer %{"role" => "reviewer"}

  # The developer's launch through decide/3, then its frozen candidate, sealed and closed
  # developer and a policy-empty check set, which leaves ticket and attempt awaiting_review.
  # Freeze and checks are subcommit 4's workers; their events carry no slot, so the test
  # commits them through the generic builder.
  defp awaiting_review!(ctx) do
    commit!(ctx, launch_decision(ctx, "L1"))
    base = %{"ticket_id" => "T1", "attempt_id" => "L1/attempt"}

    ingress!(ctx, "FROZEN", %{
      "events" => [
        {"artifact_frozen", "T1",
         Map.merge(base, %{
           "candidate_id" => "cand-1",
           "observation_id" => "obs-1",
           "sealed_generation" => "gen-1"
         })},
        {"stream_sealed", "T1",
         Map.merge(base, %{"execution_id" => "L1/execution", "last_accepted_sequence" => 7})},
        {"developer_closed", "T1", Map.put(base, "execution_id", "L1/execution")},
        {"checks_started", "T1", Map.put(base, "policy_empty", true)}
      ]
    })

    ticket = ticket(ctx)

    assert {ticket["phase"], ticket["attempts"]["L1/attempt"]["phase"]} ==
             {"awaiting_review", "awaiting_review"}
  end

  defp review_decision(ctx, id, predecessor \\ nil) do
    assert {:ok, decision} =
             decide(ctx, command(id, "plan_launch", @reviewer), review_facts(ctx, predecessor))

    decision
  end

  defp review_facts(ctx, predecessor \\ nil), do: launch_facts(ctx, predecessor, "ledger-r")

  defp ledger(ctx, id) do
    {:ok, ledger} = query(ctx, %{"type" => "ledger", "ledger_id" => id, "generation" => 0})
    Map.take(ledger, ~w(available held consumed))
  end

  describe "plan_launch, reviewer (R4.15, D1)" do
    # R4.15.o1: "reviewing attempt/ticket, independent reviewer launch with its own
    # reservation".
    test "plans the reviewer launch on its own ledger; the ticket enters reviewing", ctx do
      seed!(ctx, 3, 2)
      awaiting_review!(ctx)
      developer_ledger = ledger(ctx, "ledger-1")
      commit!(ctx, review_decision(ctx, "V1"))

      ticket = ticket(ctx)
      attempt = ticket["attempts"]["L1/attempt"]
      assert {ticket["phase"], attempt["phase"]} == {"reviewing", "reviewing"}
      assert attempt["review"]["execution_id"] == "V1/execution"
      assert attempt["review"]["candidate_id"] == "cand-1"

      assert {attempt["executions"]["V1/execution"].role,
              attempt["executions"]["V1/execution"].lifecycle} ==
               {"reviewer", "pending"}

      assert {:ok, effect} = query(ctx, %{"type" => "effect", "effect_id" => "V1/effect"})

      assert {effect["role"], effect["attempt_id"], effect["operation_ordinal"]} ==
               {"reviewer", "L1/attempt", 0}

      assert ledger(ctx, "ledger-r")["held"] == 1
      assert ledger(ctx, "ledger-1") == developer_ledger
    end

    # R4a: "Drain forbids developer and PM replacement launches ...; reviewer ... retries
    # remain eligible under the existing drain rule."
    test "drain does not gate the reviewer", ctx do
      seed!(ctx, 3, 2)
      awaiting_review!(ctx)
      control!(ctx, %{"draining" => true})
      commit!(ctx, review_decision(ctx, "V1"))
      assert ticket(ctx)["phase"] == "reviewing"
    end

    # D1: pause "forbids issue until resume" for every role, the reviewer's included.
    test "pause rejects before intent; the ticket stays awaiting_review", ctx do
      seed!(ctx, 3, 2)
      awaiting_review!(ctx)
      control!(ctx, %{"paused" => true})

      assert {:reject, :control_paused} =
               decide(ctx, command("V1", "plan_launch", @reviewer), review_facts(ctx))

      assert ticket(ctx)["phase"] == "awaiting_review"
    end

    test "pending cancel rejects, and is decided before pause", ctx do
      seed!(ctx, 3, 2)
      awaiting_review!(ctx)
      control!(ctx, %{"paused" => true})
      cancel!(ctx)

      assert {:reject, :cancel_pending} =
               decide(ctx, command("V1", "plan_launch", @reviewer), review_facts(ctx))
    end

    # R4.15.f3 "reviewer capacity available", and R4a's pre-intent denial: "creates no
    # execution, claim or reservation: the ... review ... stays in its scheduling phase".
    test "short reviewer allocation is a pre-intent denial", ctx do
      seed!(ctx, 3, 2)
      awaiting_review!(ctx)
      drain_ledger!(ctx, "ledger-r", "starts.reviewer")
      facts = review_facts(ctx)

      assert {:reject, :allocation_unavailable} =
               decide(ctx, command("V1", "plan_launch", @reviewer), facts)

      ticket = ticket(ctx)
      assert ticket["phase"] == "awaiting_review"
      assert ticket["infrastructure"]["ordinals"]["reviewer"] == 0
      assert review_facts(ctx) == facts
    end

    test "eligibility is the reducer's: a developing ticket is refused, not planned", ctx do
      seed!(ctx, 3, 2)
      commit!(ctx, launch_decision(ctx, "L1"))

      assert {:reject, :wrong_source_phase} =
               decide(ctx, command("V1", "plan_launch", @reviewer), review_facts(ctx))
    end

    # R4.15.o1 "independent reviewer": Core refuses the reviewer effect when its issuer is
    # the developer's principal (FR08B-REVIEWER-INDEPENDENCE-DESIGN-2026-09-23.md); decide/3
    # plans it identically either way, so the refusal is a pre-intent denial.
    test "a reviewer launched under the developer's principal is refused by Core", ctx do
      seed!(ctx, 3, 2, {3, 2}, %{"independent_of_roles" => %{"reviewer" => ["developer"]}})
      awaiting_review!(ctx)
      decision = review_decision(ctx, "V1")

      assert {:ok, %{"disposition" => "rejected"} = result, _} =
               submit(ctx, decision, "operator")

      assert inspect(result) =~ "principal_not_independent"
      assert {:error, :not_found} = query(ctx, %{"type" => "effect", "effect_id" => "V1/effect"})
      assert ticket(ctx)["phase"] == "awaiting_review"
      assert ledger(ctx, "ledger-r")["held"] == 0

      # Neighbour: a fresh command under a distinct principal is admitted.
      commit!(ctx, review_decision(ctx, "V2"), "reviewer-principal")
      assert ticket(ctx)["phase"] == "reviewing"

      assert {:ok, %{"issuer" => "reviewer-principal"}} =
               query(ctx, %{"type" => "effect", "effect_id" => "V2/effect"})
    end

    test "a pause committed after the decision refuses the reviewer launch", ctx do
      seed!(ctx, 3, 2)
      awaiting_review!(ctx)
      decision = review_decision(ctx, "V1")
      control!(ctx, %{"paused" => true})

      assert {:ok, %{"disposition" => "rejected"} = result, _} = submit(ctx, decision)
      assert inspect(result) =~ "revision_conflict"
      assert {:error, :not_found} = query(ctx, %{"type" => "effect", "effect_id" => "V1/effect"})
    end
  end

  # A reviewer launch, then its proved non-start, through decide/3.
  defp review_nonstart!(ctx) do
    awaiting_review!(ctx)
    commit!(ctx, review_decision(ctx, "V1"))

    assert {:ok, settle} =
             decide(ctx, command("W1", "settle_nonstart", @reviewer), settle_facts("V1"))

    commit!(ctx, settle)
  end

  describe "settle_nonstart, reviewer (R4a.02)" do
    test "below the limit: back to awaiting_review with the same candidate", ctx do
      seed!(ctx, 3, 2)
      result = review_nonstart!(ctx)
      assert result["selected_discriminator"] == "below_infrastructure_limit"

      ticket = ticket(ctx)
      attempt = ticket["attempts"]["L1/attempt"]
      # o1, o2: attempt and ticket awaiting_review, the same candidate, no disposition.
      assert {ticket["phase"], attempt["phase"]} == {"awaiting_review", "awaiting_review"}
      assert {attempt["candidate_id"], attempt["disposition"]} == {"cand-1", nil}
      # o3, o4: only the reviewer closed; the developer's allowance untouched.
      assert attempt["executions"]["V1/execution"].lifecycle == "closed"

      assert ticket["infrastructure"]["ordinals"] |> Map.take(~w(developer reviewer)) ==
               %{"developer" => 0, "reviewer" => 1}

      assert Executions.open_executions(ticket) == []
      # o5: the reviewer launch unit is released, not consumed.
      assert ledger(ctx, "ledger-r") == %{"available" => 2, "held" => 0, "consumed" => 0}

      assert {:ok, %{"role" => "reviewer", "ordinal" => 1}} =
               query(ctx, %{"type" => "infrastructure_settlement", "effect_id" => "V1/effect"})

      # o7: "return to the durable reviewer queue" - the next reviewer launch plans on the
      # same attempt, ordinal 1, naming its predecessor.
      commit!(ctx, review_decision(ctx, "V2", "V1/effect"))
      assert ticket(ctx)["attempts"]["L1/attempt"]["review"]["execution_id"] == "V2/execution"

      assert {:ok, %{"operation_ordinal" => 1, "predecessor_effect_id" => "V1/effect"}} =
               query(ctx, %{"type" => "effect", "effect_id" => "V2/effect"})
    end

    # o8, o9.
    test "at the limit: blocked(reviewer_launch_infrastructure), resuming awaiting_review",
         ctx do
      seed!(ctx, 3, 2, {1, 2})
      result = review_nonstart!(ctx)
      assert result["selected_discriminator"] == "infrastructure_limit_reached"

      ticket = ticket(ctx)
      assert {ticket["phase"], ticket["reason"]} == {"blocked", "reviewer_launch_infrastructure"}
      assert ticket["resume_phase"] == "awaiting_review"
      assert ticket["active_attempt_id"] == "L1/attempt"
      assert ticket["attempts"]["L1/attempt"]["phase"] == "awaiting_review"
      assert ticket["attempts"]["L1/attempt"]["candidate_id"] == "cand-1"
    end

    # o10: missing current reviewer allocation blocks, without discarding or approving the
    # candidate.
    test "short allocation after a non-start blocks(reviewer_budget)", ctx do
      seed!(ctx, 3, 2)
      review_nonstart!(ctx)
      drain_ledger!(ctx, "ledger-r", "starts.reviewer")

      assert {:ok, decision} =
               decide(
                 ctx,
                 command("V2", "plan_launch", @reviewer),
                 review_facts(ctx, "V1/effect")
               )

      assert decision["plan"]["protected_operations"] == []
      commit!(ctx, decision)

      ticket = ticket(ctx)
      assert {ticket["phase"], ticket["reason"]} == {"blocked", "reviewer_budget"}
      assert ticket["resume_phase"] == "awaiting_review"
      attempt = ticket["attempts"]["L1/attempt"]
      assert {attempt["phase"], attempt["candidate_id"]} == {"awaiting_review", "cand-1"}
      assert attempt["review"] == nil
    end

    test "a settle with no reviewer bound is refused by the reducer, not planned", ctx do
      seed!(ctx, 3, 2)
      awaiting_review!(ctx)

      assert {:reject, :wrong_source_phase} =
               decide(ctx, command("W1", "settle_nonstart", @reviewer), settle_facts("V1"))
    end
  end

  # A delivered receipt for a launch's claim: the protected outcome the adapter reconciles
  # for an execution that ran. close_attempt needs every effect of the attempt settled.
  defp delivered!(ctx, launch_id, outcome) do
    root!(ctx, %{
      "type" => "settle_claim",
      "claim_id" => Plan.id(launch_id, "claim"),
      "receipt_id" => Plan.id(launch_id, "receipt"),
      "request_id" => Plan.id(launch_id, "request"),
      "outcome" => outcome,
      "proof" => "delivered",
      "payload" => %{}
    })
  end

  defp reviewer_evidence!(ctx, id, type, execution_id) do
    base = %{"ticket_id" => "T1", "attempt_id" => "L1/attempt", "execution_id" => execution_id}

    payload =
      if type == "stream_sealed", do: Map.put(base, "last_accepted_sequence", 3), else: base

    ingress!(ctx, id, %{"events" => [{type, "T1", payload}]})
  end

  # Awaiting review, a reviewer launched, its stream sealed and both launches delivered.
  defp sealed_review!(ctx) do
    awaiting_review!(ctx)
    commit!(ctx, review_decision(ctx, "V1"))
    reviewer_evidence!(ctx, "SEAL-V1", "stream_sealed", "V1/execution")
    delivered!(ctx, "L1", "succeeded")
    delivered!(ctx, "V1", "succeeded")
  end

  defp verdict(ctx, verdict, candidate \\ "cand-1") do
    decide(
      ctx,
      command(
        "D1",
        "submit_review",
        Map.merge(@reviewer, %{"verdict" => verdict, "candidate_id" => candidate})
      ),
      %{}
    )
  end

  describe "submit_review, reviewer (R4.16-R4.18)" do
    # R4.16: the approval is recorded; the verified close then makes it ready_to_integrate.
    test "approved records the verdict; the verified close advances", ctx do
      seed!(ctx, 3, 2)
      sealed_review!(ctx)
      assert {:ok, decision} = verdict(ctx, "approved")
      assert decision["plan"]["protected_operations"] == []
      commit!(ctx, decision)

      ticket = ticket(ctx)
      assert ticket["phase"] == "reviewing"
      assert ticket["attempts"]["L1/attempt"]["review"]["verdict"] == "approved"

      reviewer_evidence!(ctx, "CLOSE-V1", "reviewer_closed", "V1/execution")
      assert ticket(ctx)["phase"] == "ready_to_integrate"
    end

    # R4.17: terminal needs_correction through close_attempt; the reviewer closes after;
    # then a fresh developer attempt.
    test "correction terminalises the attempt; a fresh developer follows the close", ctx do
      seed!(ctx, 3, 2)
      sealed_review!(ctx)
      assert {:ok, decision} = verdict(ctx, "correction")
      assert Enum.map(decision["plan"]["protected_operations"], & &1["type"]) == ["close_attempt"]
      commit!(ctx, decision)

      ticket = ticket(ctx)
      attempt = ticket["attempts"]["L1/attempt"]
      assert {ticket["phase"], ticket["active_attempt_id"]} == {"queued", nil}

      assert {attempt["disposition"], attempt["review"]["verdict"]} ==
               {"needs_correction", "correction"}

      # The reviewer is still open, so no successor launches until its close.
      assert {:reject, :cleanup_incomplete} =
               decide(ctx, command("L2", "plan_launch"), launch_facts(ctx))

      reviewer_evidence!(ctx, "CLOSE-V1", "reviewer_closed", "V1/execution")
      commit!(ctx, launch_decision(ctx, "L2"))
      assert ticket(ctx)["active_attempt_id"] == "L2/attempt"
    end

    # R4.18.
    test "rejected terminalises attempt and ticket", ctx do
      seed!(ctx, 3, 2)
      sealed_review!(ctx)
      assert {:ok, decision} = verdict(ctx, "rejected")
      commit!(ctx, decision)

      ticket = ticket(ctx)
      assert ticket["phase"] == "rejected"
      assert ticket["attempts"]["L1/attempt"]["disposition"] == "rejected"
    end

    test "close_attempt refuses while an effect of the attempt is unsettled", ctx do
      seed!(ctx, 3, 2)
      awaiting_review!(ctx)
      commit!(ctx, review_decision(ctx, "V1"))
      reviewer_evidence!(ctx, "SEAL-V1", "stream_sealed", "V1/execution")
      assert {:ok, decision} = verdict(ctx, "rejected")

      assert {:ok, %{"disposition" => "rejected"} = result, _} = submit(ctx, decision)
      assert inspect(result) =~ "attempt_not_settled"
      assert ticket(ctx)["phase"] == "reviewing"
    end

    test "a verdict naming another candidate is refused by the reducer", ctx do
      seed!(ctx, 3, 2)
      sealed_review!(ctx)
      assert {:reject, :verdict_names_another_candidate} = verdict(ctx, "correction", "cand-2")
    end
  end

  # A reviewer that ran, sealed its stream with no verdict and closed.
  defp crashed!(ctx) do
    awaiting_review!(ctx)
    commit!(ctx, review_decision(ctx, "V1"))
    reviewer_evidence!(ctx, "SEAL-V1", "stream_sealed", "V1/execution")
    reviewer_evidence!(ctx, "CLOSE-V1", "reviewer_closed", "V1/execution")
    delivered!(ctx, "V1", "failed")
  end

  describe "reviewer crash (R4.19)" do
    test "the candidate survives and a bounded new reviewer launches", ctx do
      seed!(ctx, 3, 2)
      crashed!(ctx)
      developer_ledger = ledger(ctx, "ledger-1")

      ticket = ticket(ctx)

      assert {ticket["phase"], ticket["attempts"]["L1/attempt"]["candidate_id"]} ==
               {"awaiting_review", "cand-1"}

      commit!(ctx, review_decision(ctx, "V2", "V1/effect"))
      assert ticket(ctx)["attempts"]["L1/attempt"]["review"]["execution_id"] == "V2/execution"

      assert {:ok, %{"operation_ordinal" => 1, "predecessor_effect_id" => "V1/effect"}} =
               query(ctx, %{"type" => "effect", "effect_id" => "V2/effect"})

      # R4.19.o2: the developer ledger untouched.
      assert ledger(ctx, "ledger-1") == developer_ledger
      assert ticket(ctx)["infrastructure"]["ordinals"]["developer"] == 0
    end

    # R4.19.o3: "exhaust if unavailable".
    test "short reviewer allocation after a crash exhausts attempt and ticket", ctx do
      seed!(ctx, 3, 2)
      crashed!(ctx)
      delivered!(ctx, "L1", "succeeded")
      drain_ledger!(ctx, "ledger-r", "starts.reviewer")

      assert {:ok, decision} =
               decide(
                 ctx,
                 command("V2", "plan_launch", @reviewer),
                 review_facts(ctx, "V1/effect")
               )

      assert Enum.map(decision["plan"]["protected_operations"], & &1["type"]) == ["close_attempt"]
      commit!(ctx, decision)

      ticket = ticket(ctx)
      assert ticket["phase"] == "exhausted"
      assert ticket["attempts"]["L1/attempt"]["disposition"] == "exhausted"
    end
  end

  describe "finalize_cancellation (R4.28)" do
    # R4.28.o1: "If no integration occurred: cancelled ticket and active attempt terminal
    # cancelled".
    test "the retained attempt settles cancelled through close_attempt, then finalizes", ctx do
      seed!(ctx, 3, 2)
      launch_and_nonstart!(ctx)
      cancel!(ctx)

      assert {:ok, decision} = decide(ctx, command("F1", "finalize_cancellation", %{}), %{})
      assert Enum.map(decision["plan"]["protected_operations"], & &1["type"]) == ["close_attempt"]
      commit!(ctx, decision)

      ticket = ticket(ctx)
      assert ticket["phase"] == "cancelled"
      assert ticket["active_attempt_id"] == nil
      assert ticket["attempts"]["L1/attempt"]["disposition"] == "cancelled"
    end

    test "with no attempt there is nothing to close: finalization alone", ctx do
      seed!(ctx, 3, 2)
      cancel!(ctx)

      assert {:ok, decision} = decide(ctx, command("F1", "finalize_cancellation", %{}), %{})
      assert decision["plan"]["protected_operations"] == []
      commit!(ctx, decision)
      assert ticket(ctx)["phase"] == "cancelled"
    end

    test "an uncancelled ticket is refused by the reducer, not planned", ctx do
      seed!(ctx, 3, 2)
      launch_and_nonstart!(ctx)

      assert {:reject, :cancel_not_requested} =
               decide(ctx, command("F1", "finalize_cancellation", %{}), %{})
    end
  end

  # Why `Plan.decision/2` derives no protected key: at command level `policy/<id>` reads
  # the legacy authority table, so the root policy at revision 0 reads "absent" and a
  # launch that states the truth is refused. When this goes green-for-the-wrong-reason
  # (Core reads root rows there), decide/3 should start stating the facts it read.
  test "a command-level protected key does not read the root policy", ctx do
    seed!(ctx, 3, 2)
    decision = launch_decision(ctx, "L1")
    key = "policy/" <> Base.url_encode64("policy-1", padding: false)

    assert {:ok, %{"reason_code" => "revision_conflict"}, _} =
             submit(ctx, put_in(decision, ["command", "expected_revisions", key], 0))
  end

  describe "decide/3 input" do
    test "an unclaimed command or role is an error, not a rejection" do
      state = State.new()

      assert {:error, :unsupported_command} =
               WorkflowKernel.decide(state, command("X", "plan_launch", %{"role" => "pm"}), %{})

      assert {:error, :unsupported_command} =
               WorkflowKernel.decide(state, command("X", "enqueue"), %{})

      assert {:error, :invalid_command} = WorkflowKernel.decide(state, %{}, %{})
      assert {:error, :invalid_state} = WorkflowKernel.decide(%{}, command("X", "enqueue"), %{})
    end
  end
end
