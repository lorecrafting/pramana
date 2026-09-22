Code.require_file("../../support/kernel_walk.ex", __DIR__)
Code.require_file("../../support/kernel_search.ex", __DIR__)

defmodule PramanaFoundry.Workflow.R4ExhaustiveTest do
  @moduledoc """
  Invariants proved over every state the kernel can reach within a bounded depth.

  The seeded walks sample; the row coverage drives hand-built sequences; this enumerates.
  Each asks a different question, and the defects that blocked this subcommit three times
  were the ones only enumeration finds cheaply — a transition the contract forbids being
  accepted, and a transition accepted out of the order the contract requires.

  Concretely: `attempt_settled(rejected)` from `developing` is two events from the empty
  state, `cancellation_finalized(after_integration)` is three, and a fresh developer
  launching beside an open check worker is well inside this bound. Each of those cost an
  independent review round to find by reading.

  A violation reports the exact event sequence that produced it.
  """
  use ExUnit.Case, async: true

  alias PramanaFoundry.Test.{Harness, KernelSearch}
  alias PramanaFoundry.Workflow.Kernel.State

  @depth 7

  setup_all do
    {:ok, states: KernelSearch.search(@depth)}
  end

  test "every reachable state satisfies the kernel's own validator", %{states: states} do
    check(states, fn state ->
      if State.well_formed?(state),
        do: :ok,
        else: {:violation, "well_formed?/1 rejects a state apply/2 produced"}
    end)
  end

  # "A ticket owning live work has an attempt, or a cancel that can finish it" used to be a
  # separate test here, with its own hand-written copy of the same predicate and the same
  # cancel exception. It is deleted rather than kept, and the reason is the finding it was
  # half of: `State.phase_agreement/3` encodes that identical rule and had the
  # exception MISSING, and the relations test that would have said so could not fail. So the
  # suite held two encodings of one contract row, one correct and dead, one incorrect and
  # green — and the green one is precisely what made the dead one look corroborated. The rule
  # now exists once, in the oracle, asserted by the relations test below. Rule 4.

  # R4's resume row returns a blocked ticket "to stored resume_phase". A blocked ticket
  # without one can never be resumed by any event, which is a terminal state R4 does not
  # list as terminal.
  test "a blocked ticket can always be resumed", %{states: states} do
    check(states, fn state ->
      Enum.find_value(state["tickets"], :ok, fn {id, ticket} ->
        if ticket["phase"] == "blocked" and is_nil(ticket["resume_phase"]),
          do: {:violation, "ticket #{id} is blocked with no resume_phase"}
      end)
    end)
  end

  # "An attempt holding a ref receipt can only be terminally integrated" was a separate test
  # here, and it is deleted for the same reason as the cancel one above and found the same way.
  # It hand-wrote `State.receipt_custody/2`'s predicate — and the two DISAGREED:
  # this test used `disposition != "integrated"`, matching the kernel, while the oracle licensed
  # `cancelled` as well. Two encodings of one contract row, disagreeing, both with 0 of 58,324
  # preconditioned states, so neither could ever say so. The review of EV-5 caught it; the
  # oracle is corrected to the kernel's rule and this duplicate goes. Rule 4, applied to the
  # second row rather than only the first — which is what the first pass should have done, since
  # the table that exposed the vacuity listed both.

  # The converse: an integrated ticket is B1's headline counterexample if it has no receipt.
  test "an integrated ticket always has a ref receipt behind it", %{states: states} do
    check(states, fn state ->
      Enum.find_value(state["tickets"], :ok, fn {id, ticket} ->
        if ticket["phase"] == "integrated" and
             not Enum.any?(ticket["attempts"], fn {_a, at} -> is_binary(at["ref_receipt_id"]) end),
           do: {:violation, "ticket #{id} is integrated with no ref receipt on any attempt"}
      end)
    end)
  end

  test "a terminal attempt always keeps its disposition and its evidence", %{states: states} do
    check(states, fn state ->
      Enum.find_value(state["tickets"], :ok, fn {_tid, ticket} ->
        Enum.find_value(ticket["prior_attempt_ids"], fn aid ->
          attempt = ticket["attempts"][aid]

          cond do
            is_nil(attempt) ->
              {:violation, "prior attempt #{aid} was dropped from the ticket"}

            attempt["phase"] != "terminal" ->
              {:violation, "prior attempt #{aid} is not terminal"}

            is_nil(attempt["disposition"]) ->
              {:violation, "prior attempt #{aid} has no disposition"}

            true ->
              nil
          end
        end)
      end)
    end)
  end

  # ── The oracle the fourth review said was missing ─────────────────────────────────

  # Every test above asks a question about ONE transition: was this admitted, or refused,
  # and with which atom. None asks whether the facts in the resulting state cohere. The
  # stale-resume defect is the demonstration: this search REACHED the bad state — three of
  # them at this exact depth — and no oracle called it illegal, so it was found by two
  # reviewers reading instead. `State.well_formed?/1` accepted it, correctly, because nothing
  # about it was malformed.
  test "every reachable state satisfies the contract's relations, not just its shapes",
       %{states: states} do
    check(states, fn state ->
      case State.violations(state) do
        [] -> :ok
        violations -> {:violation, Enum.join(violations, "; ")}
      end
    end)
  end

  # Red control. An invariant oracle that reports nothing is indistinguishable from one
  # that checks nothing, and five mechanisms in this subcommit shipped in exactly that
  # condition. So the oracle has to demonstrate it fires on the defect it was built for.
  #
  # The state is no longer reachable, which is the point — and is also why the first
  # version of this control was hand-written and WRONG: `State.well_formed?/1` rejected it, so it
  # would have "passed" by tripping a different check entirely. It is now built from a real
  # reachable state with exactly one field corrupted, which is precisely what the defect
  # did: `artifact_frozen` still leaves the stale `developing` target, and before the
  # honesty fix a block-and-unblock could put the ticket back on it.
  # red control: phase_agreement_attempt
  test "the oracle catches the state the search had already reached", %{states: states} do
    {reachable, _path} =
      Enum.find(states, fn {state, _path} ->
        Enum.any?(state["tickets"] || %{}, fn {_id, t} ->
          t["phase"] == "awaiting_review" and t["resume_phase"] == "developing" and
            get_in(t, ["attempts", t["active_attempt_id"], "phase"]) == "candidate_frozen"
        end)
      end) ||
        flunk("the precondition state is gone; this control is testing nothing")

    assert State.violations(reachable) == [],
           "the uncorrupted state must be clean, or the corruption below proves nothing"

    bad = put_in(reachable, ["tickets", "T1", "phase"], "developing")

    assert State.well_formed?(bad),
           "the red control must be WELL-FORMED, or it proves nothing this validator " <>
             "did not already prove"

    violations = State.violations(bad)

    assert Enum.any?(violations, &(&1 =~ "ticket developing with attempt candidate_frozen")),
           "phase agreement did not fire on the defect it exists for: #{inspect(violations)}"

    assert length(violations) == 1,
           "exactly one relation should break from exactly one corrupted field: " <>
             inspect(violations)
  end

  # Red control for the WIRING, which is a different thing from the oracle and is the thing
  # that was actually broken. The oracle above fired correctly for months while the test that
  # applies it to the search could not fail. An oracle with a red control and a harness
  # without one produces exactly the confident, clean, vacuous result rule 1 exists to stop.
  test "check/2 fails the suite when an invariant reports a violation", %{states: states} do
    assert_raise ExUnit.AssertionError, fn ->
      check(states, fn _state -> {:violation, "a violation the harness must not swallow"} end)
    end
  end

  # And the exact defect, pinned by its exact shape rather than by "some error": the relations
  # test returned `{:error, msg}` where `check/2` matched only `{:violation, msg}`. Rule 5's
  # reasoning applied to a harness — a control satisfied by any failure is satisfied by the
  # wrong one.
  test "check/2 refuses a return shape it does not understand", %{states: states} do
    assert_raise ArgumentError, fn ->
      check(states, fn _state -> {:error, "the shape that made this test file vacuous"} end)
    end

    assert_raise ArgumentError, fn -> check(states, fn _state -> nil end) end
  end

  # Red control for the cancel exception added to `phase_agreement/3`. An exception that
  # swallows the whole clause is indistinguishable from deleting it, and this clause is the
  # one that makes three `require_attempt_phase(~w(active))` sites redundant — so weakening
  # it silently would cost those three sites their argument. One reachable state, one field
  # flipped: with the cancel withdrawn, the same state must violate.
  # red control: phase_agreement_nil
  test "the cancel exception does not disarm phase agreement", %{states: states} do
    {reachable, _path} =
      Enum.find(states, fn {state, _path} ->
        Enum.any?(state["tickets"] || %{}, fn {_id, t} ->
          t["phase"] == "developing" and is_nil(t["active_attempt_id"]) and t["cancel_requested"]
        end)
      end) || flunk("the precondition state is gone; this control is testing nothing")

    assert State.violations(reachable) == [],
           "a cancelled ticket holding its working phase is R4:490, not a violation"

    bad = put_in(reachable, ["tickets", "T1", "cancel_requested"], false)

    # Weaker than the same line in the control above, and labelled so rather than left to read
    # as if it were equivalent: `State.well_formed?/1` constrains `cancel_requested` only by
    # `is_boolean` (`state.ex:148`), so `true -> false` could not have failed it. It is kept
    # because a corrupted control that is malformed proves nothing, but the teeth of this test
    # are the two assertions around it, not this one.
    assert State.well_formed?(bad)

    assert Enum.any?(
             State.violations(bad),
             &(&1 =~ "developing with no active attempt and no pending cancel")
           ),
           "withdrawing the cancel must expose a ticket nothing can move: " <>
             inspect(State.violations(bad))
  end

  # Red control for the kernel's closure guard (property 6, `require_well_formed/1`). This
  # fixture used to be the harness's: `ticket_admitted` copied `reason` into the ticket
  # unchecked, so a map there produced an accepted state `well_formed?/1` rejected, and the
  # test showed the harness catching it. The kernel now refuses that transition itself, so
  # the harness's shape assertion was a tautology with no constructible red control and was
  # deleted; this is the assertion that turns red when the sweep neutralises the guard.
  #
  # Pinned to its atom (rule 5): `:invalid_state` cannot be the refuser, because the same
  # event with a well-formed `reason` is accepted from the same input state. The refusal is
  # the value, not the event.
  test "a transition whose post-state the validator rejects is refused, not written" do
    event = %{
      "schema_version" => 1,
      "event_id" => "harness-shape",
      "type" => "ticket_admitted",
      "entity_kind" => "ticket",
      "entity_id" => "T9",
      "entity_revision" => 0,
      "sequence" => 1,
      "payload" => %{
        "ticket_id" => "T9",
        "objective_id" => nil,
        "spec_revision_id" => "spec-1",
        "spec" => %{},
        "phase" => "queued",
        "reason" => %{"not" => "an identifier"}
      }
    }

    assert {:error, :malformed_post_state} = Harness.apply(State.new(), event)

    assert {:ok, _} = Harness.apply(State.new(), put_in(event, ["payload", "reason"], nil)),
           "the same event with a well-formed value must be accepted, or the refusal is not the guard's"
  end

  # ── One red control per invariant family (rule 1) ─────────────────────────────────

  # `invariant?/1` now judges every accepted transition the suite drives, not only the states
  # this search reaches, so each family owes a fixture that MUST fail. Each is built by
  # corrupting exactly one field of a state the search actually reached — the first
  # hand-written control in this file was rejected by the shape validator and would have
  # "passed" by tripping a different check entirely.
  #
  # Two families are controlled by the tests above and are named there rather than repeated:
  # `phase_agreement_attempt` by "the oracle catches the state the search had already
  # reached", `phase_agreement_nil` by "the cancel exception does not disarm phase agreement".

  test "every invariant family has a red control naming it" do
    source = File.read!(__ENV__.file)

    for family <- State.invariant_families() do
      assert source =~ "red control: #{family}",
             "#{family} has no red control in this file"
    end

    absent = "red control: " <> Enum.join(["no", "such", "family"], "_")

    refute source =~ absent,
           "the scan matches anything, so it proves nothing"
  end

  # `invariant_families/0` drives the harness's counter indices AND the red-control scan, but
  # nothing tied it to the map `measure/1` actually returns. A family added to the list and
  # not to the map would read as `held 0` on every run — which the report labels "vacuous",
  # the one word that makes a missing family look like a known, accepted condition.
  test "every declared family is one measure/1 actually returns", %{states: states} do
    {state, _path} = Enum.random(states)

    assert Enum.sort(Map.keys(State.measure(state))) == Enum.sort(State.invariant_families())

    assert Enum.sort(Map.keys(State.measure(State.new()))) ==
             Enum.sort(State.invariant_families())
  end

  test "red control: resume_target", %{states: states} do
    {reachable, _path} =
      Enum.find(states, fn {state, _path} ->
        Enum.any?(state["tickets"] || %{}, fn {_id, t} -> t["phase"] == "blocked" end)
      end) || flunk("the precondition state is gone; this control is testing nothing")

    assert State.violations(reachable) == []

    bad = put_in(reachable, ["tickets", "T1", "resume_phase"], nil)

    assert State.well_formed?(bad),
           "the red control must be WELL-FORMED, or it proves nothing the validator did not"

    assert State.violations(bad) == ["T1: blocked with no resume target"]
  end

  # The precondition is "holds a candidate", so the corruption adds one to an attempt that is
  # legitimately `active` — rather than moving a candidate-holding attempt back to `active`,
  # which would break phase agreement in the same step and leave the family untested.
  test "red control: candidate_custody", %{states: states} do
    {reachable, _path} =
      Enum.find(states, fn {state, _path} ->
        Enum.any?(state["tickets"] || %{}, fn {_id, t} ->
          get_in(t, ["attempts", t["active_attempt_id"], "phase"]) == "active"
        end)
      end) || flunk("the precondition state is gone; this control is testing nothing")

    assert State.violations(reachable) == []

    active_id = reachable["tickets"]["T1"]["active_attempt_id"]
    bad = put_in(reachable, ["tickets", "T1", "attempts", active_id, "candidate_id"], "cand-x")

    assert State.well_formed?(bad),
           "the red control must be WELL-FORMED, or it proves nothing the validator did not"

    assert State.violations(bad) == ["T1/#{active_id}: holds candidate cand-x while active"]
  end

  # The family with no witness anywhere in the reachable set — 0 of 58,324 hold its
  # precondition, because a ref receipt sits roughly a dozen events from empty. That is
  # exactly why it needs this: a clause nothing exercises and nothing can fail is rule 1's
  # vacuous mechanism, and the denominator alone does not distinguish "never violated" from
  # "never evaluated". The receipt is planted on a reachable terminal attempt rather than a
  # state being hand-built, so the rest of the fixture is still something the kernel produced.
  test "red control: receipt_custody", %{states: states} do
    {reachable, attempt_id} =
      Enum.find_value(states, fn {state, _path} ->
        Enum.find_value(state["tickets"]["T1"]["attempts"] || %{}, fn {id, attempt} ->
          if attempt["phase"] == "terminal" and attempt["disposition"] != "integrated",
            do: {state, id}
        end)
      end) || flunk("the precondition state is gone; this control is testing nothing")

    assert State.violations(reachable) == []

    {held?, _} = State.measure(reachable)[:receipt_custody]
    refute held?, "the uncorrupted state already holds the precondition; plant nothing"

    bad = put_in(reachable, ["tickets", "T1", "attempts", attempt_id, "ref_receipt_id"], "rcpt-x")

    assert State.well_formed?(bad),
           "the red control must be WELL-FORMED, or it proves nothing the validator did not"

    disposition = reachable["tickets"]["T1"]["attempts"][attempt_id]["disposition"]

    assert State.violations(bad) == [
             "T1/#{attempt_id}: holds a ref receipt but settled #{disposition}"
           ]
  end

  # Red control for the HARNESS, which is a different thing from the oracle and is the half
  # that was actually broken last time: the oracle fired correctly for months while the test
  # applying it to the search could not fail. Pinned to the relation by name rather than to
  # "some assertion error", per rule 5 — a control satisfied by any failure is satisfied by
  # the wrong one.
  test "the harness fails a test when an accepted transition violates a relation", %{
    states: states
  } do
    {reachable, _path} =
      Enum.find(states, fn {state, _path} ->
        Enum.any?(state["tickets"] || %{}, fn {_id, t} -> t["phase"] == "blocked" end)
      end) || flunk("the precondition state is gone; this control is testing nothing")

    bad = put_in(reachable, ["tickets", "T1", "resume_phase"], nil)
    assert State.well_formed?(bad)

    # A control event: it advances the control entity and touches no ticket, so the successor
    # carries the corruption forward unchanged and the harness is the only thing that can
    # object.
    event = %{
      "schema_version" => 1,
      "event_id" => "harness-control",
      "type" => "control_changed",
      "entity_kind" => "control",
      "entity_id" => "control",
      "entity_revision" => bad["control"]["revision"],
      "sequence" => (bad["last_sequence"] || 0) + 1,
      "payload" => %{
        "control" => %{
          "schema_version" => 1,
          "control_id" => "ctl-harness",
          "control_revision" => bad["control"]["control_revision"] + 1
        },
        "paused" => true,
        "draining" => false,
        "stop_status" => "running"
      }
    }

    # Through the harness's own escape hatch, not the kernel directly. Asking the kernel for
    # its verdict here is legitimate — the point is that the harness, not the kernel, is what
    # rejects — but spelling it as a direct call put a call site in the suite that
    # `r4_no_direct_apply_test.exs` could not see, which independent review caught.
    assert {:ok, _} = Harness.apply_unchecked(bad, event),
           "the kernel must ACCEPT this event, or the harness is never reached"

    error = assert_raise ExUnit.AssertionError, fn -> Harness.apply(bad, event) end

    assert error.message =~ "blocked with no resume target",
           "the harness failed for some other reason: #{error.message}"
  end

  test "the search actually explored a meaningful space", %{states: states} do
    # Guards the guard: an invariant proved over three states proves nothing, and a broken
    # proposer would silently shrink the space rather than fail.
    assert length(states) > 10_000, "only #{length(states)} states reached at depth #{@depth}"

    phases =
      states
      |> Enum.flat_map(fn {state, _path} ->
        Enum.map(state["tickets"], fn {_i, t} -> t["phase"] end)
      end)
      |> MapSet.new()

    for phase <- ~w(queued developing awaiting_review blocked) do
      assert phase in phases, "exhaustive search never reached ticket phase #{phase}"
    end
  end

  # The `_ -> nil` clause this once ended with is how the relations test above spent its whole
  # life unable to fail: its lambda returned `{:error, msg}`, nothing matched `{:violation,
  # msg}`, and the catch-all swallowed 1,002 violations without a word. Nine tests route
  # through here, so one strict clause closes the class for all of them rather than fixing the
  # one lambda that happened to drift. An unrecognised return is now louder than a violation.
  defp check(states, invariant) do
    violation =
      Enum.find_value(states, fn {state, path} ->
        case invariant.(state) do
          {:violation, message} -> {message, path}
          :ok -> nil
          other -> raise ArgumentError, unexpected_return(other)
        end
      end)

    case violation do
      nil ->
        :ok

      {message, path} ->
        flunk("""
        #{message}

        Reached by #{length(path)} accepted events:
        #{KernelSearch.render(path)}
        """)
    end
  end

  defp unexpected_return(other) do
    "an invariant passed to check/2 returned #{inspect(other)}. It must return :ok or " <>
      "{:violation, message} — any other shape is silently ignored, which is exactly how " <>
      "the relations test above could not fail for as long as it existed."
  end
end
