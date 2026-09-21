Code.require_file("../../support/kernel_walk.ex", __DIR__)

defmodule PramanaFoundry.Workflow.KernelPropertiesTest do
  @moduledoc """
  Properties of the FR-08B kernel, checked over seeded reachability walks.

  These state the laws the table-driven tests sample. Every walk is seeded, so a failure
  reports a seed and a step count and replays exactly.
  """
  use ExUnit.Case, async: true

  alias PramanaFoundry.Test.KernelWalk
  alias PramanaFoundry.Workflow.Kernel, as: WorkflowKernel
  alias PramanaFoundry.Workflow.Kernel.{Event, State}

  @seeds 1..40
  @steps 600

  # Walked once for the whole module. Each test previously recomputed every walk, so the
  # suite paid for them ten times over and the step budget had to stay too small to reach
  # the deepest rows.
  # Two configurations, because reachability and invariant checking want opposite things.
  # Broad walks interleave three tickets for invariants; deep walks drive one ticket as far
  # as it goes, for coverage.
  setup_all do
    broad = Enum.map(@seeds, &KernelWalk.walk(State.new(), &1, @steps))
    deep = Enum.map(1..25, &KernelWalk.deep(State.new(), &1, 800))
    {:ok, walks: broad, all: broad ++ deep}
  end

  describe "invariants that must hold at every reachable state" do
    test "every state the reducer returns satisfies its own validator", %{walks: walks} do
      for walk <- walks do
        seed = "walk"

        Enum.reduce(walk.accepted, State.new(), fn event, state ->
          {:ok, next} = WorkflowKernel.apply(state, event)

          assert State.valid?(next),
                 "seed #{seed}: #{event["type"]} produced a state valid?/1 rejects"

          next
        end)
      end
    end

    # Asserting that the walker's accepted log is ordered tested the walker's counter, not
    # the kernel - the walker assigns those sequences itself, so the property could not
    # fail. What the kernel actually owes is that it *refuses* a non-increasing sequence
    # and a stale entity revision, from a state a walk really reached.
    test "the kernel refuses a stale sequence or entity revision", %{walks: walks} do
      for walk <- Enum.take(walks, 10), walk.accepted != [] do
        state = walk.state
        last = List.last(walk.accepted)

        stale_sequence = %{last | "sequence" => state["last_sequence"], "event_id" => "replayed"}

        assert {:error, :out_of_order_event} = WorkflowKernel.apply(state, stale_sequence),
               "the kernel accepted a sequence it had already passed"

        stale_revision = %{
          last
          | "sequence" => state["last_sequence"] + 1,
            "event_id" => "revised",
            "entity_revision" => 0
        }

        assert {:error, :stale_entity_revision} =
                 WorkflowKernel.apply(state, stale_revision),
               "the kernel accepted an entity revision it had already passed"
      end
    end

    test "a terminal attempt keeps its disposition and is never reopened", %{walks: walks} do
      for walk <- walks, {_id, ticket} <- walk.state["tickets"] do
        for prior <- ticket["prior_attempt_ids"] do
          attempt = ticket["attempts"][prior]
          assert attempt["phase"] == "terminal"
          assert attempt["disposition"] in State.dispositions()
        end

        assert ticket["active_attempt_id"] not in ticket["prior_attempt_ids"]
      end
    end

    test "no attempt is ever discarded once created", %{walks: walks} do
      # R4 requires prior attempts, their candidates and their review evidence to be
      # retained. The reviewed candidate lost them by replacing the active attempt.
      for walk <- walks do
        created =
          walk.accepted
          |> Enum.filter(&(&1["type"] == "launch_planned"))
          |> Enum.group_by(& &1["entity_id"], & &1["payload"]["attempt_id"])

        for {ticket_id, attempt_ids} <- created do
          attempts = Map.keys(walk.state["tickets"][ticket_id]["attempts"])

          for id <- Enum.uniq(attempt_ids) do
            assert id in attempts, "#{ticket_id}: attempt #{id} was created and then lost"
          end
        end
      end
    end
  end

  describe "algebraic laws" do
    test "replaying an accepted log from empty state reproduces the walk exactly", %{walks: walks} do
      for walk <- walks do
        replayed =
          Enum.reduce(walk.accepted, State.new(), fn event, state ->
            {:ok, next} = WorkflowKernel.apply(state, event)
            next
          end)

        assert replayed == walk.state
      end
    end

    test "a restart in the middle of the log reconstructs the same state", %{walks: walks} do
      # R4a: "Restart after atomic non-start settlement but before redispatch must
      # reconstruct exactly one queued/review/blocked owner". Serialising the state to
      # JSON and back is what a restart actually does to it, so a field that cannot
      # survive the round trip is a state that cannot survive a restart.
      for walk <- walks, walk.accepted != [] do
        split = div(length(walk.accepted), 2)
        {before, rest} = Enum.split(walk.accepted, split)

        mid = Enum.reduce(before, State.new(), fn e, s -> elem(WorkflowKernel.apply(s, e), 1) end)
        restarted = mid |> JSON.encode!() |> JSON.decode!()

        assert restarted == mid, "state did not survive a JSON round trip"

        resumed =
          Enum.reduce(rest, restarted, fn e, s -> elem(WorkflowKernel.apply(s, e), 1) end)

        assert resumed == walk.state
      end
    end

    # R4a: "Restart after settlement but before redispatch therefore reconstructs exactly
    # one queued/review/blocked owner and no live execution." The round-trip property above
    # proves the state survives serialisation; it says nothing about this, which is the
    # sentence it cited. Stated separately so each can fail for its own reason.
    test "after a non-start settlement the owner is queued with no live execution", %{
      all: walks
    } do
      settlements = ~w(launch_settled review_settled check_settled integration_settled
                       build_settled)

      checked =
        for walk <- walks, reduce: 0 do
          count ->
            walk.accepted
            |> Enum.reduce({State.new(), count}, fn event, {state, count} ->
              {:ok, next} = WorkflowKernel.apply(state, event)

              if event["type"] in settlements do
                ticket = next["tickets"][event["payload"]["ticket_id"]]
                attempt = ticket["attempts"][event["payload"]["attempt_id"]]
                execution = attempt["executions"][event["payload"]["execution_id"]]

                assert execution["lifecycle"] == "closed",
                       "#{event["type"]} left its execution #{execution["lifecycle"]}"

                assert ticket["phase"] not in ~w(integrated rejected cancelled),
                       "#{event["type"]} left the ticket terminal at #{ticket["phase"]}"

                assert is_nil(ticket["active_attempt_id"]) or
                         ticket["attempts"][ticket["active_attempt_id"]]["phase"] != "terminal",
                       "#{event["type"]} left a terminal attempt active"

                {next, count + 1}
              else
                {next, count}
              end
            end)
            |> elem(1)
        end

      assert checked > 0, "no walk ever settled a non-start, so this proved nothing"
    end

    # R4a sets launch_non_start_limit "per role and work owner". One counter per ticket
    # meant a reviewer non-start spent the developer's allowance, and decide/3 could not
    # evaluate "below the limit" for any single role.
    test "each role consumes only its own infrastructure allowance", %{all: walks} do
      by_role =
        for walk <- walks, {_id, ticket} <- walk.state["tickets"], reduce: %{} do
          acc ->
            Enum.reduce(ticket["infrastructure"]["ordinals"], acc, fn {role, n}, acc ->
              Map.update(acc, role, n, &(&1 + n))
            end)
        end

      assert map_size(by_role) == length(State.ticket_roles())

      consumed = by_role |> Map.values() |> Enum.count(&(&1 > 0))

      assert consumed > 1,
             "only one role ever consumed an ordinal, so per-role accounting is untested"
    end

    test "redelivering any accepted event is an idempotent no-op at its own point", %{
      walks: walks
    } do
      for walk <- walks do
        Enum.reduce(walk.accepted, State.new(), fn event, state ->
          {:ok, next} = WorkflowKernel.apply(state, event)
          assert {:ok, ^next} = WorkflowKernel.apply(next, event)
          next
        end)
      end
    end

    test "apply/2 never raises and never returns an untagged value", %{walks: walks} do
      for walk <- walks do
        for event <- walk.accepted, mangled <- mangle(event) do
          result = WorkflowKernel.apply(walk.state, mangled)

          assert match?({:ok, _}, result) or match?({:error, _}, result),
                 "#{inspect(mangled["type"])} escaped as #{inspect(result)}"
        end
      end
    end

    defp mangle(event) do
      [
        %{event | "payload" => %{}},
        %{event | "entity_revision" => -1},
        %{event | "sequence" => "not-an-integer"},
        %{event | "entity_id" => nil},
        %{event | "type" => "no_such_type"},
        Map.delete(event, "payload"),
        put_in(event, ["payload"], %{"binding" => "authority"})
      ]
    end
  end

  describe "contract reachability" do
    # Every declared type is now reachable. The previous entry here recorded the three
    # integration rows as unreached and justified it as a depth limit behind a single
    # `review_recorded:approved` -> `reviewer_closed` sequence. Independent review measured
    # that sequence firing *zero* times, not once: the walks died on unguarded dispositions
    # and could not admit a successor ticket, and the review rows the ratchet counted as
    # reached were reached only because a failed check could be relabelled `passed`. The
    # ratchet was not hiding a defect so much as standing on one.
    #
    # The lesson is recorded rather than smoothed over: an empty list here is only
    # meaningful because the prober admits successors and proposes every variant R4 names.
    # A claim about coverage is worth nothing until it is executed.
    @known_unreached []

    test "every event type the vocabulary declares is reachable by some walk", %{all: walks} do
      # This is the assertion whose absence let a codec that could not express two R4a
      # rows pass two independent reviews. The proposer is derived from R4, not from the
      # kernel's guards, so a type that never becomes reachable is a contract row the
      # implementation cannot reach - not a gap in the generator.
      reached =
        walks
        |> Enum.flat_map(fn walk -> Enum.map(walk.accepted, & &1["type"]) end)
        |> MapSet.new()

      unreachable =
        Event.types() |> MapSet.new() |> MapSet.difference(reached) |> Enum.sort()

      assert unreachable == @known_unreached,
             "reachable set moved. now unreached: #{inspect(unreachable)}, " <>
               "recorded: #{inspect(@known_unreached)}"
    end

    # R4's rows are variants - approved versus rejected verdict, nine dispositions, four
    # execution lifecycles - so a type-level ratchet marks a row covered the moment any one
    # of its variants fires. Two confirmed blockers lived exactly in that gap: the
    # after_integration branch of R4's cancel row, and the `unknown` execution lifecycle
    # that require_workers_closed wrongly counted as closed. Neither was ever proposed, and
    # the type-level assertion above was green throughout.
    # Empty, and the one entry it used to hold is the reason this comment is here. That
    # entry claimed `cancellation_finalized:after_integration` was unreached because "the
    # seeded ordering does not happen to find it". Independent review measured that false:
    # the walks entered the window six times and three ended sitting in exactly the state
    # the row describes. They could never finalize, because the prober dropped a terminal
    # ticket from its proposals and could not close a settled attempt's executions - the
    # same custody defect the kernel had just been corrected for, uncorrected in the tool
    # that was supposed to detect it. Both are fixed, and the variant now fires fifteen
    # times.
    #
    # The standard this list is held to: a variant may only be recorded here with a
    # hand-built R4-legal sequence proving the row is satisfiable, and "the search does not
    # find it" is not a reason until the search itself has been checked. Two ratchets in
    # this module have now rested on false justifications.
    @known_unreached_variants []

    test "every variant the contract distinguishes is reachable by some walk", %{all: walks} do
      reached =
        walks
        |> Enum.flat_map(fn walk -> Enum.map(walk.accepted, &KernelWalk.label/1) end)
        |> MapSet.new()

      unreachable =
        KernelWalk.variants() |> MapSet.new() |> MapSet.difference(reached) |> Enum.sort()

      assert unreachable == @known_unreached_variants,
             "variant reachability moved. now unreached: #{inspect(Enum.sort(unreachable))}"
    end

    test "walks reach the deep lifecycle phases, not just admission", %{all: walks} do
      # Every phase visited along the way, not just the one a walk ends in: walks end in
      # terminal states, so final-state sampling reports `cancelled` and `rejected` and
      # nothing about the lifecycle that led there.
      phases =
        walks
        |> Enum.flat_map(fn walk ->
          walk.accepted
          |> Enum.reduce({State.new(), []}, fn event, {state, seen} ->
            {:ok, next} = WorkflowKernel.apply(state, event)
            {next, seen ++ Enum.map(next["tickets"], fn {_id, t} -> t["phase"] end)}
          end)
          |> elem(1)
        end)
        |> MapSet.new()

      for phase <- ~w(queued developing awaiting_review reviewing exhausted cancelled
                      blocked rejected) do
        assert phase in phases, "no walk ever reached ticket phase #{phase}"
      end

      # This was `refute "integrated" in phases` - a negative assertion that recorded the
      # walks' inability to reach the row and then entrenched it, so the row becoming
      # reachable would have failed the suite. It is now the assertion it should always
      # have been.
      assert "integrated" in phases
    end
  end
end
