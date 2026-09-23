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

  defp seed!(ctx, limit, units) do
    root!(ctx, %{
      "type" => "set_policy",
      "policy_id" => "policy-1",
      "value" => %{
        "allowed_operations" => ["launch"],
        "allowed_scopes" => ["ticket:T1"],
        "infrastructure_attempt_limits" => %{"developer" => limit}
      }
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

  defp launch_facts(ctx, predecessor \\ nil) do
    {:ok, policy} = query(ctx, %{"type" => "policy", "policy_id" => "policy-1"})
    {:ok, control} = query(ctx, %{"type" => "control", "control_id" => "control-1"})

    {:ok, ledger} =
      query(ctx, %{"type" => "ledger", "ledger_id" => "ledger-1", "generation" => 0})

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

  # Each staged operation carries the prestate reads Gateway requires it to state.
  defp submit(ctx, %{"command" => command, "plan" => plan}) do
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

    Gateway.atomic_bundle(ctx.gateway, ctx.capability, "operator", %{
      "schema_version" => 2,
      "actor_id" => "operator",
      "inputs" => %{
        "recorded_at" => "2026-09-23T00:00:00Z",
        "transition_id" => command["command_id"]
      },
      "command" => command,
      "operations" => operations,
      "plan" => plan
    })
  end

  defp commit!(ctx, decision) do
    assert {:ok, result, :committed} = submit(ctx, decision)
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

  # The launch decide/3 does not plan yet: the four operations built here, the plan by
  # the generic builder.
  defp launch_decision(ctx, id) do
    facts = launch_facts(ctx)

    operations = [
      %{
        "type" => "reserve",
        "reservation_id" => Plan.id(id, "reservation"),
        "ledger_id" => "ledger-1",
        "generation" => 0,
        "owner_kind" => "effect",
        "owner_id" => Plan.id(id, "effect"),
        "units" => 1
      },
      %{
        "type" => "create_effect",
        "effect_id" => Plan.id(id, "effect"),
        "operation" => "launch",
        "scope" => "ticket:T1",
        "ticket_id" => "T1",
        "attempt_id" => Plan.id(id, "attempt"),
        "execution_id" => Plan.id(id, "execution"),
        "policy_id" => "policy-1",
        "policy_revision" => facts["policy"]["revision"],
        "control_id" => "control-1",
        "control_revision" => facts["control"]["revision"],
        "request" => %{"request_id" => Plan.id(id, "request"), "role" => "developer"},
        "reservation_ids" => [Plan.id(id, "reservation")],
        "leases" => []
      },
      %{
        "type" => "claim_effect",
        "effect_id" => Plan.id(id, "effect"),
        "claim_id" => Plan.id(id, "claim"),
        "writer_epoch" => "epoch-A"
      },
      %{"type" => "issue_claim", "claim_id" => Plan.id(id, "claim"), "writer_epoch" => "epoch-A"}
    ]

    spec = %{"planned" => "launch_planned", "operations" => operations}

    assert {:ok, decision} =
             Plan.decision(Plan.launch(replay(ctx), id, spec), command(id, "plan_launch"))

    decision
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

  # Why `Plan.decision/2` derives no protected key: at command level `policy/<id>` reads
  # the legacy authority table, so the root policy at revision 0 reads "absent" and a
  # launch that states the truth is refused. When this goes green-for-the-wrong-reason
  # (Core reads root rows there), decide/3 should start stating the facts it read.
  test "a command-level protected key does not read the root policy", ctx do
    seed!(ctx, 3, 2)
    decision = launch_decision(ctx, "L1")
    key = Plan.protected_key("policy", "policy-1")

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
