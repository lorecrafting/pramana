Code.require_file("../../support/kernel_walk.ex", __DIR__)
Code.require_file("../../support/kernel_search.ex", __DIR__)

defmodule PramanaFoundry.Workflow.R4GuardReachabilityTest do
  @moduledoc """
  Which of the kernel's refusals can actually happen.

  A guard that cannot fire is not defence in depth; it is dead code that reads as a
  safeguard, and this subcommit shipped one - `require_reviewer_open` was added, claimed in
  a commit message as a fix, and could never fire. It was found by a reviewer reading code.
  This finds that class mechanically: every error atom the kernel declares is compared with
  every refusal the exhaustive search actually provokes.

  It immediately found something else. The proposer had only ever offered cooperative
  events, so every guard protecting against a *forged reference* - naming another attempt,
  re-reserving a live check, resuming to a phase the ticket never stored - was declared and
  never exercised by any walk. Those proposals now exist, and four of those guards fire.
  """
  use ExUnit.Case, async: true

  alias PramanaFoundry.Test.KernelSearch

  @depth 7

  # Refusals about malformed payloads and out-of-order envelopes. The proposer builds only
  # well-formed events in sequence, so these are exercised by the table tests instead, and
  # their absence here is by construction rather than a finding. `malformed_post_state` is
  # the closure guard (kernel property 6): with well-formed payloads no accepted transition
  # can produce a malformed state, so it fires only from the fixture in r4_exhaustive_test.
  @validation ~w(malformed_post_state invalid_admission_phase invalid_blocked_result invalid_cancellation_disposition
                 invalid_check_status invalid_control_entity invalid_control_fact
                 invalid_control_flag invalid_disposition invalid_execution_identity
                 invalid_execution_lifecycle invalid_freeze_disposition
                 invalid_integration_outcome invalid_resume_phase invalid_state
                 invalid_stop_status invalid_verdict kernel_raised out_of_order_event
                 stale_entity_revision entity_id_disagrees_with_payload unknown_entity
                 duplicate_proposal)a

  # Guards that cannot fire within this bound, each with the reason. Two kinds only:
  #
  #   * "deeper than the bound" - the integration family sits roughly a dozen events in,
  #     past depth 7. Raising the depth reaches them; the bound is a cost choice.
  #   * "genuinely unreachable" - no sequence can provoke it. Each of these is a claim that
  #     a reviewer can challenge, and is written down so that it can be.
  @unreachable %{
    # Deeper than the bound.
    workers_not_closed: "integration row: ~12 events",
    integration_already_issued: "integration row",
    issuer_not_terminated: "integration retry",
    ref_receipt_recorded: "integration row",
    ref_receipt_admits_only_integrated: "integration row",
    integration_occurred: "cancel finalisation after a ref receipt",
    verdict_already_recorded: "second verdict on one reviewer: past depth",
    verdict_names_another_candidate: "forged candidate id is not yet proposed",
    check_already_settled:
      "re-recording a settled check needs nine events - admit, launch, freeze, seal, " <>
        "close, checks_started, check_planned, check_recorded, check_recorded - and the " <>
        "bound is seven",
    # Genuinely unreachable, and each says why.
    checks_not_passed:
      "shadowed by the attempt-phase guard directly above it. `review_planned` requires " <>
        "the attempt in `awaiting_review`, and `maybe_finish_checks` is the only thing " <>
        "that puts it there - which it does exactly when every check has passed. No " <>
        "event can add or relabel a check afterwards, since check_planned, " <>
        "check_recorded and check_settled all require the `checking` phase. Recorded " <>
        "here after pinning r4_coverage_test's `{:error, _}` to its atom showed the " <>
        "scenario naming this guard was being refused by the phase instead. Was listed " <>
        "as deeper-than-the-bound, which was wrong: raising the depth does not reach it.",
    reviewer_already_closed:
      "once reviewer_closed nils the review on the no-verdict branch, every route to a " <>
        "closed reviewer on a reviewing attempt is refused earlier by phase or by the " <>
        "recorded-verdict guard. Kept because the rule is right; it does no work today.",
    no_stored_resume_phase:
      "every path into `blocked` now stores a resume target, so a blocked ticket without " <>
        "one cannot exist. The guard is the invariant's belt-and-braces.",
    candidate_frozen:
      "shadowed by a phase transition. `require_no_candidate` guards the failed/timed_out " <>
        "settlement, which requires an `active` attempt - and artifact_frozen sets the " <>
        "candidate and moves the attempt to candidate_frozen in the same step, so an " <>
        "active attempt never holds a candidate. Belt-and-braces for an invariant the " <>
        "phase already enforces.",
    unknown_entity_kind:
      "dead by construction, and the argument is inductive rather than bounded. " <>
        "`@entity_kind_of` is built as `Map.new(@types, ...)`, so its key set is exactly " <>
        "the type vocabulary; `Event.validate/1` runs first in `Kernel.apply/2` and " <>
        "requires `event[\"type\"] in @types`. A total map looked up with a key proven to " <>
        "be in its domain cannot return `:error`. The decisive half is event.ex:192, which " <>
        "performs the identical lookup - `event[\"entity_kind\"] == @entity_kind_of[type]` - " <>
        "after :191 has required the kind be one of @entity_kinds, so a missing key yields " <>
        "nil and validate refuses before kernel.ex:80 runs at all. Unlike the " <>
        "`reviewer_closed` argument that a looser predicate falsified with 3,612 witnesses, " <>
        "this one is local to a single `with` over an immutable event and a compile-time " <>
        "map built from one attribute; there is no state to evolve. Surfaced only in this " <>
        "session, when the extractor was widened to see the `ok_or/2` spelling it uses."
  }

  # Both tests want the same traversal, and computing it twice doubled the cost of the
  # slowest suite in the workflow set for no information.
  setup_all do
    {:ok, fired: KernelSearch.rejection_reasons(@depth)}
  end

  test "every refusal the kernel declares either fires, or is recorded as unreachable",
       %{fired: fired} do
    never =
      KernelSearch.declared_reasons()
      |> MapSet.difference(fired)
      |> MapSet.difference(MapSet.new(@validation))

    recorded = MapSet.new(Map.keys(@unreachable))

    undocumented = MapSet.difference(never, recorded) |> Enum.sort()
    resurrected = MapSet.difference(recorded, never) |> Enum.sort()

    assert undocumented == [],
           "guards that can never fire and are not recorded as such: #{inspect(undocumented)}. " <>
             "Either the guard is dead, or nothing proposes what would trip it."

    assert resurrected == [],
           "guards recorded as unreachable that now fire: #{inspect(resurrected)}. " <>
             "Remove them from @unreachable - and check whether the reason given was ever true."
  end

  # The red control for the inventory itself. This test asserted a mechanical inventory of
  # the declared error set for three reviews while scanning for one of the two spellings a
  # refusal is written in, so it could not see `:unknown_entity_kind` at kernel.ex:80 and
  # said nothing. A fixture carrying every shape - both declaration spellings, and the
  # `ok_or/2` definition clause that must not be read as a declaration - fails if the
  # extractor narrows again.
  test "the reason extractor sees both spellings and not the ok_or definition" do
    fixture = """
    def apply(state, event) do
      with :ok <- check_state(state),
           {:ok, kind} <- Event.entity_kind(event["type"]) |> ok_or(:piped_spelling),
           {:ok, x} <- ok_or(lookup(event), :argument_spelling) do
        {:ok, state}
      end
    end

    defp check_state(state), do: if(valid?(state), do: :ok, else: {:error, :literal_spelling})
    defp ok_or({:ok, value}, _reason), do: {:ok, value}
    defp ok_or(:error, reason), do: {:error, reason}
    """

    found = KernelSearch.reasons_in(fixture)

    assert MapSet.member?(found, :literal_spelling)
    assert MapSet.member?(found, :piped_spelling)
    assert MapSet.member?(found, :argument_spelling)

    refute MapSet.member?(found, :error),
           "the ok_or/2 definition clause is being read as a declaration of `:error`"

    refute MapSet.member?(found, :ok),
           "the ok_or/2 success clause is being read as a declaration"
  end

  test "the forged-reference guards are exercised", %{fired: fired} do
    for guard <- ~w(not_the_active_attempt unknown_attempt retained_attempt_must_be_reused
                    check_already_exists resume_phase_disagrees)a do
      assert MapSet.member?(fired, guard),
             "#{guard} never fires: the proposer stopped offering the forged reference " <>
               "that trips it, so the guard is unexercised again"
    end
  end
end
