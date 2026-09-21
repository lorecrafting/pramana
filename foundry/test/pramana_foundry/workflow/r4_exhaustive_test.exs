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

  # Phases in which R4 has the ticket owning live work. A ticket cannot be in one of these
  # with no attempt to own it: that is the shape of the defect the third review found, where
  # a blocked attempt's stale resume target returned the ticket to `developing` with nothing
  # running and nothing able to run.
  @active_phases ~w(developing awaiting_review reviewing ready_to_integrate integrating)

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

  # The cancel exception is R4's, not a weakening: "nonterminal ticket; cancel requested |
  # ... **hold phase/evidence while issued effects reconcile**". A cancelled attempt leaves
  # its ticket holding `developing` with nothing active until `cancellation_finalized`
  # moves it to `cancelled`, and that is legal precisely because finalisation can still
  # reach it. Without a pending cancel the same shape is the defect the third review found:
  # a ticket owning live work that nothing can move.
  #
  # The first version of this invariant omitted the exception, and the exhaustive search
  # produced the four-event counterexample that showed it was the invariant that was wrong,
  # not the kernel. That is the search doing its job in both directions.
  test "a ticket owning live work has an attempt, or a cancel that can finish it",
       %{states: states} do
    check(states, fn state ->
      Enum.find_value(state["tickets"], :ok, fn {id, ticket} ->
        if ticket["phase"] in @active_phases and is_nil(ticket["active_attempt_id"]) and
             not ticket["cancel_requested"],
           do:
             {:violation,
              "ticket #{id} is #{ticket["phase"]} with no active attempt and no pending cancel"}
      end)
    end)
  end

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
        violations -> {:error, Enum.join(violations, "; ")}
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

  defp check(states, invariant) do
    violation =
      Enum.find_value(states, fn {state, path} ->
        case invariant.(state) do
          {:violation, message} -> {message, path}
          _ -> nil
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
end
