Code.require_file("../../support/kernel_walk.ex", __DIR__)
Code.require_file("../../support/kernel_search.ex", __DIR__)
Code.require_file("../../support/semantic_invariants.ex", __DIR__)

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

  alias PramanaFoundry.Test.{KernelSearch, SemanticInvariants}
  alias PramanaFoundry.Workflow.Kernel.State

  @depth 7

  setup_all do
    {:ok, states: KernelSearch.search(@depth)}
  end

  test "every reachable state satisfies the kernel's own validator", %{states: states} do
    check(states, fn state ->
      if State.valid?(state),
        do: :ok,
        else: {:violation, "valid?/1 rejects a state apply/2 produced"}
    end)
  end

  # "A ticket owning live work has an attempt, or a cancel that can finish it" used to be a
  # separate test here, with its own hand-written copy of the same predicate and the same
  # cancel exception. It is deleted rather than kept, and the reason is the finding it was
  # half of: `SemanticInvariants.phase_agreement/3` encodes that identical rule and had the
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

  # R4: "integrated ticket; terminal integrated attempt ... Exit notifications cannot
  # overwrite this."
  test "an attempt holding a ref receipt can only be terminally integrated", %{states: states} do
    check(states, fn state ->
      Enum.find_value(state["tickets"], :ok, fn {_tid, ticket} ->
        Enum.find_value(ticket["attempts"], fn {aid, attempt} ->
          if is_binary(attempt["ref_receipt_id"]) and attempt["phase"] == "terminal" and
               attempt["disposition"] != "integrated",
             do:
               {:violation,
                "attempt #{aid} holds #{attempt["ref_receipt_id"]} but settled " <>
                  inspect(attempt["disposition"])}
        end)
      end)
    end)
  end

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
  # reviewers reading instead. `State.valid?/1` accepted it, correctly, because nothing
  # about it was malformed.
  test "every reachable state satisfies the contract's relations, not just its shapes",
       %{states: states} do
    check(states, fn state ->
      case SemanticInvariants.violations(state) do
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
  # version of this control was hand-written and WRONG: `State.valid?/1` rejected it, so it
  # would have "passed" by tripping a different check entirely. It is now built from a real
  # reachable state with exactly one field corrupted, which is precisely what the defect
  # did: `artifact_frozen` still leaves the stale `developing` target, and before the
  # honesty fix a block-and-unblock could put the ticket back on it.
  test "the oracle catches the state the search had already reached", %{states: states} do
    {reachable, _path} =
      Enum.find(states, fn {state, _path} ->
        Enum.any?(state["tickets"] || %{}, fn {_id, t} ->
          t["phase"] == "awaiting_review" and t["resume_phase"] == "developing" and
            get_in(t, ["attempts", t["active_attempt_id"], "phase"]) == "candidate_frozen"
        end)
      end) ||
        flunk("the precondition state is gone; this control is testing nothing")

    assert SemanticInvariants.violations(reachable) == [],
           "the uncorrupted state must be clean, or the corruption below proves nothing"

    bad = put_in(reachable, ["tickets", "T1", "phase"], "developing")

    assert State.valid?(bad),
           "the red control must be WELL-FORMED, or it proves nothing this validator " <>
             "did not already prove"

    violations = SemanticInvariants.violations(bad)

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
  test "the cancel exception does not disarm phase agreement", %{states: states} do
    {reachable, _path} =
      Enum.find(states, fn {state, _path} ->
        Enum.any?(state["tickets"] || %{}, fn {_id, t} ->
          t["phase"] == "developing" and is_nil(t["active_attempt_id"]) and t["cancel_requested"]
        end)
      end) || flunk("the precondition state is gone; this control is testing nothing")

    assert SemanticInvariants.violations(reachable) == [],
           "a cancelled ticket holding its working phase is R4:490, not a violation"

    bad = put_in(reachable, ["tickets", "T1", "cancel_requested"], false)

    assert State.valid?(bad),
           "the red control must be WELL-FORMED, or it proves nothing this validator " <>
             "did not already prove"

    assert Enum.any?(
             SemanticInvariants.violations(bad),
             &(&1 =~ "developing with no active attempt and no pending cancel")
           ),
           "withdrawing the cancel must expose a ticket nothing can move: " <>
             inspect(SemanticInvariants.violations(bad))
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
