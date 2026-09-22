Code.require_file("../../support/r4_rows.ex", __DIR__)
Code.require_file("../../support/kernel_walk.ex", __DIR__)
# For `KernelSearch.declared_reasons/0` only - the from-cell classification below pins
# obligations to refusal atoms, and re-deriving that inventory here is how the declared-
# reason scan came to miss one of its two spellings for three reviews.
Code.require_file("../../support/kernel_search.ex", __DIR__)

defmodule PramanaFoundry.Workflow.R4CoverageTest do
  @moduledoc """
  Every R4 and R4a transition row, driven through the kernel.

  Two independent reviews blocked this kernel with the same finding shape: a guard refuses
  the reported counterexample while the row it claims to implement cannot be driven at all.
  Both times the gap was found by a reviewer reading prose against code. Neither the table
  tests nor the reachability walks could see it, because both ask what the kernel accepts
  rather than what the contract requires.

  This asks the other question. Each row gets a scenario that drives it and asserts the
  outcome the contract states, or is explicitly recorded as unexpressible with the reason.
  A row with neither fails. The row set itself is parsed from the contract, so neither the
  inventory nor this suite can drift away from it.
  """
  use ExUnit.Case, async: true

  alias PramanaFoundry.Test.{KernelSearch, R4Rows}
  alias PramanaFoundry.Test.Harness
  alias PramanaFoundry.Workflow.Kernel.{Event, State}

  # Rows the kernel cannot drive today. Each entry names the review finding that reported
  # it. This is a ratchet over *contract rows*, which is the thing that matters - unlike a
  # ratchet over event types the prober happened to reach, a row here is unambiguous: the
  # contract requires it and the kernel cannot do it.
  # Empty: every R4 and R4a row can now be driven through the reducer. That is a claim
  # about *this* module only - subcommit 1 is the pure kernel, so a row driving here means
  # the reducer can express it, not that the whole mechanism behind it works. `reset` is
  # the clearest case: it drives, because the kernel validates its payload's shape, while
  # `reset_fact_v1` still has no producer in the durable codec, so nothing can yet bind the
  # protected fact the payload carries. The gaps that remain live in @partial and in the
  # recorded prerequisites, not here.
  @unexpressible %{}

  # Rows the kernel drives, but only part of. A row is more than one clause, and calling a
  # mostly-working row "unexpressible" hides what works while calling it "driven" hides
  # what does not. Each entry names the exact clause, so the gap stays visible without
  # understating the row.
  @partial %{
    # Re-keyed: this entry quoted "or blocked(check_infrastructure)/exhausted", which is
    # `check_infrastructure_failed`'s outcome text, not this row's. The row it named had no
    # entry at all, so its clause was both undriven and unrecorded. A quoted clause that
    # belongs to a different row is worse than none: it reads as coverage of a row nobody
    # covered. The test below now checks every @partial quote against its own row.
    nonstart_worker:
      ~S|preserve-phase retry and its infrastructure block both drive; "consumes its finite role-specific infrastructure allowance" is recorded but the allowance itself is protected policy, so nothing here can reach its limit|,
    # Once an attempt terminalises, the ticket is queued with no active attempt, and
    # exhaustion can only be settled on an active one. R4 offers exhaustion as an
    # alternative outcome of these rows, and choosing it turns on allocation - protected
    # policy the kernel may not restate - so it needs the same limit product as the R4a
    # at-limit clauses rather than new vocabulary invented here.
    check_assertion_failed:
      ~S|the terminal needs_correction outcome is driven; "or blocked(drain)/exhausted" needs the R4a limit product|,
    verdict_correction:
      ~S|the terminal needs_correction outcome is driven; "or blocked(drain)/exhausted" needs the same|,
    no_valid_candidate: ~S|"queue fresh bounded attempt" is driven; "or exhaust" needs the same|
  }

  # The obligations each scenario asserts: `{clause id, the contract's words}`.
  #
  # The ID is annotated into the contract's outcome cell and parsed out at test time, so a
  # citation names one obligation rather than pointing somewhere into a row. A test checks
  # the quote against THAT obligation, which is what the old whole-cell check could not do:
  # a citation that drifted onto a neighbouring clause read as clean.
  #
  # Most quotes here are the full obligation, because the obligation boundaries were derived
  # from these very quotes when the IDs went in. That is not redundancy - the quote is the
  # transcription, and an editorial reword of a clause a scenario still asserts is meant to
  # fail here and be re-read, not to pass silently.
  @clauses %{
    admission: [
      {"R4.02.o2", "queued or blocked with reason"}
    ],
    amend_or_park: [
      {"R4.03.o1", "New future spec revision or explicit blocked state"}
    ],
    base_moved: [
      {"R4.21.o1", "Terminal superseded_base attempt"}
    ],
    blocked_result: [
      {"R4.09.o1", "Terminal blocked attempt, blocked ticket"},
      {"R4.09.o2", "close developer"},
      {"R4.09.o4", "Resume/rescope requires explicit command and fresh attempt"}
    ],
    cancel_finalized: [
      {"R4.28.o1",
       "If no integration occurred: cancelled ticket and active attempt terminal cancelled"},
      {"R4.28.o3", "If integration occurred: integrated and cancel_finalized(after_integration)"}
    ],
    cancel_requested: [
      {"R4.27.o2", "hold phase/evidence while issued effects reconcile"}
    ],
    check_assertion_failed: [
      {"R4.13.o1", "Terminal needs_correction attempt"},
      {"R4.13.o2", "queue fresh developer after all check workers close"},
      {"R4.13.o3", "failed candidate never goes to approval"}
    ],
    check_infrastructure_failed: [
      {"R4.14.o1", "Preserve candidate, bounded new check-run reservation after cleanup"},
      {"R4.14.o2", "pending same phase"},
      {"R4.14.o3", "or blocked(check_infrastructure)/exhausted"},
      {"R4.14.o4", "Unknown check retains lease and blocks retry"}
    ],
    checks_passed: [
      {"R4.12.o1", "awaiting_review attempt"}
    ],
    checks_start: [
      {"R4.11.o1", "checking attempt, awaiting_review ticket"},
      {"R4.11.o3", "retaining immutable candidate"}
    ],
    developer_exit_after_freeze: [
      {"R4.07.o1", "Cleanup observation only"},
      {"R4.07.o2", "preserve frozen candidate"},
      {"R4.07.o3", "No new developer and no attempt failure"}
    ],
    freeze_failure: [
      {"R4.06.o3", "blocked(freeze_failure) when unavailable"},
      {"R4.06.o6", "never a frozen result"}
    ],
    freeze_success: [
      {"R4.05.o1", "Attempt candidate_frozen"},
      {"R4.05.o2", "ticket awaiting_review"},
      {"R4.05.o3", "seal productive capability/deadline generation"}
    ],
    integration_failure: [
      {"R4.23.o2", "or blocked(integration_failure)"}
    ],
    integration_start: [
      {"R4.20.o1", "integrating ticket/attempt"}
    ],
    integration_success: [
      {"R4.22.o1", "integrated ticket"},
      {"R4.22.o2", "terminal integrated attempt"},
      {"R4.22.o4", "Exit notifications cannot overwrite this"}
    ],
    launch: [
      {"R4.04.o2", "create its launch intent and enter developing"}
    ],
    malformed_submission: [
      {"R4.10.o1", "Durable rejected submission, charge one validation action"},
      {"R4.10.o2", "further submission allowed only while stream open"},
      {"R4.10.o4", "exhaustion closes execution and exhausts ticket"}
    ],
    no_valid_candidate: [
      {"R4.08.o1", "Attempt terminal failed/timed_out"}
    ],
    nonstart_developer: [
      {"R4a.01.o1", "Keep the **same nonterminal attempt**"},
      {"R4a.01.o3",
       "return ticket `developing → queued` with `resume_phase: developing` and reason `developer_launch_non_started`"},
      {"R4a.01.o7", "Below the infrastructure limit, queue a bounded developer retry"},
      {"R4a.01.o8",
       "At the limit, ticket becomes `blocked(developer_launch_infrastructure)` while the attempt remains active and resumable"}
    ],
    nonstart_pm: [
      {"R4a.03.o1", "Keep the same objective/spec-planning owner"},
      {"R4a.03.o2", "infer no proposal"},
      {"R4a.03.o6", "Admit no ticket and create no objective allocation"}
    ],
    nonstart_reviewer: [
      {"R4a.02.o1", "Keep attempt and ticket `awaiting_review`"},
      {"R4a.02.o3", "Close only the failed reviewer execution"},
      {"R4a.02.o4", "never enter developer retry or correction"},
      {"R4a.02.o9", "the same attempt/candidate remain resumable"}
    ],
    nonstart_worker: [
      {"R4a.04.o1", "Preserve its candidate/deployment phase and verified inputs"},
      {"R4a.04.o5", "consumes its finite role-specific infrastructure allowance"},
      {"R4a.04.o6", "infer no successful check/build/ref/release receipt"}
    ],
    objective_steering: [
      {"R4.01.o2", "PM proposal is evidence, not authority"}
    ],
    reset: [
      {"R4.25.o1", "Keep old attempt terminal"},
      {"R4.25.o2", "queue a fresh developer attempt using retained evidence as context"}
    ],
    resume: [
      {"R4.24.o2", "return to stored resume_phase"}
    ],
    review_start: [
      {"R4.15.o1",
       "reviewing attempt/ticket, independent reviewer launch with its own reservation"}
    ],
    reviewer_crash: [
      {"R4.19.o1", "Preserve candidate, close reviewer then bounded new reviewer execution"},
      {"R4.19.o2", "developer ledger untouched"}
    ],
    terminal_rejection: [
      {"R4.26.o1", "Reject transition"},
      {"R4.26.o2", "preserve terminal facts"}
    ],
    verdict_approved: [
      {"R4.16.o2", "after verified close ready_to_integrate"}
    ],
    verdict_correction: [
      {"R4.17.o1", "Terminal needs_correction attempt"},
      {"R4.17.o2", "close/seal reviewer, then queued fresh developer"}
    ],
    verdict_rejected: [
      {"R4.18.o1", "Terminal rejected attempt/ticket"}
    ]
  }

  # Every obligation of every outcome cell that no scenario asserts.
  #
  # `@clauses` checks that what a scenario cites still exists in the contract. This is the
  # converse, and it is the one that was missing: nothing checked whether the contract said
  # things no scenario tested. The third review found that gap by reading - uncited clauses
  # in `integration_failure`, `freeze_failure`, `admission` and `checks_passed` - which is
  # exactly the work a list like this does mechanically.
  #
  # The count is no longer carried by hand here, because every hand-carried count in this
  # file has been wrong: the comment this replaces said "54 asserted and 59 are not" while
  # the lists held 57 and 57. `mix test` prints the split from the lists themselves, and
  # `partition/3` asserts the two exactly tile the contract's obligations. Entries leave
  # this list only by being asserted; an obligation the contract states that appears in
  # neither list fails, so a contract edit cannot quietly add an untested requirement, and
  # an obligation in BOTH fails, which is the double count the punctuation unit allowed.
  #
  # Many of these belong to later subcommits by construction - allocation, budgets, leases
  # and drain are protected policy this kernel may not restate - and those will move to
  # @partial as their rows gain the mechanism. They are listed rather than excused because
  # "a later subcommit owns it" is a claim, and claims in this repair have needed checking.
  @uncited [
    {"R4.01.o1", "Durable objective and bounded PM reservation"},
    {"R4.02.o1", "Common admission validates full assignment/policy/budget allocation"},
    {"R4.02.o3", "malformed spec rejected"},
    {"R4.03.o2", "active assignments never edited"},
    {"R4.03.o3", "amendment does not reset budgets"},
    {"R4.04.o1", "Create a fresh attempt unless R4a retained a resumable developer attempt"},
    {"R4.04.o3",
     "Pre-intent denial remains queued and consumes no start unit or infrastructure ordinal"},
    {"R4.05.o4", "kernel requests developer close through broker immediately"},
    {"R4.06.o1", "Retain submitted bytes"},
    {"R4.06.o2", "bounded starts.check retry after owned worker closure"},
    {"R4.06.o4", "unknown preserves lease."},
    {"R4.06.o5", "Git/scope validation failure is invalid submission"},
    {"R4.08.o2", "after cleanup queue fresh bounded attempt or exhaust"},
    {"R4.08.o3", "normal exit alone is not success"},
    {"R4.09.o3", "no review"},
    {"R4.10.o3", "and budget remains"},
    {"R4.11.o2", "schedule root-mandated check workers before reviewer"},
    {"R4.12.o2", "queue independent reviewer"},
    {"R4.12.o3", "checks with explicit policy-empty set follow same guarded transition"},
    {"R4.15.o2", "R4a returns a proved non-start to this same candidate/role queue"},
    {"R4.16.o1", "Close/seal reviewer"},
    {"R4.16.o3", "no Git success inferred"},
    {"R4.17.o3", "or blocked(drain)/exhausted; never re-prompt old developer"},
    {"R4.18.o2", "cleanup pending separately"},
    {"R4.18.o3", "later work needs explicitly admitted revision"},
    {"R4.19.o3", "exhaust if unavailable"},
    {"R4.20.o2", "root integration intent, then R1 claim/issue"},
    {"R4.21.o2", "fresh bounded rebase developer plus renewed checks/review"},
    {"R4.21.o3", "blocked under drain or budget exhaustion"},
    {"R4.22.o3", "deployment is separate."},
    {"R4.23.o1", "Same phase with bounded integration-effect retry after old issuer termination"},
    {"R4.23.o3", "Conflict uses moved-base row"},
    {"R4.23.o4", "unknown blocks reconciliation"},
    {"R4.24.o1", "Revalidate spec/control/policy and existing allocation"},
    {"R4.24.o3", "fresh attempt only if prior attempt terminal."},
    {"R4.24.o4",
     "Partial/rescope and explicit operator blocks require steering, not automatic unblocking"},
    {"R4.25.o3", "with newly bound checks/review"},
    {"R4.25.o4", "block if that role lacks allocation"},
    {"R4.25.o5", "never reset prior consumption"},
    {"R4.26.o3",
     "New work requires explicit admission linked to predecessor, with parent-funded allocation"},
    {"R4.27.o1",
     "Set orthogonal control, cancel pending/unissued effects, request owned interrupts"},
    {"R4.28.o2", "already terminal dispositions retained."},
    {"R4.28.o4", "suppress deployment"},
    {"R4a.01.o2", "and immutable base/spec/policy lineage"},
    {"R4a.01.o4", "Release launch resources."},
    {"R4a.01.o5",
     "Release its checkout/conflict lease only after proving the checkout was never exposed or mutated, then reacquire/revalidate it before retry"},
    {"R4a.01.o6", "otherwise retain the lease and block affected work."},
    {"R4a.01.o9",
     "Exhaustion of current developer allocation instead makes the attempt terminal `exhausted` and ticket `exhausted`"},
    {"R4a.02.o2", "immutable candidate/check receipts and reviewer ownership"},
    {"R4a.02.o5", "Release reviewer launch resources"},
    {"R4a.02.o6", "retain candidate custody and candidate/check leases."},
    {"R4a.02.o7", "Below the limit, return to the durable reviewer queue."},
    {"R4a.02.o8",
     "At the limit, ticket becomes `blocked(reviewer_launch_infrastructure)` with `resume_phase: awaiting_review`"},
    {"R4a.02.o10",
     "Missing current reviewer allocation yields `blocked(reviewer_budget)` or `exhausted` under protected policy, without discarding or approving the candidate"},
    {"R4a.03.o3", "Release launch-only resources."},
    {"R4a.03.o4", "Below the PM limit, return to its PM queue"},
    {"R4a.03.o5",
     "at the limit or without current allocation, block as `pm_launch_infrastructure` or `pm_budget`."},
    {"R4a.04.o2", "apply that phase's existing infrastructure retry/block row."},
    {"R4a.04.o3", "Release only proved-unused launch resources."},
    {"R4a.04.o4", "A retry references the predecessor and"}
  ]

  # EV-2 and EV-6 annotate clause IDs into the contract's governing tables. That edit is the
  # highest-consequence one in this system - 32 from-cells are matched character for
  # character by `R4Rows.declared_from/1`, and every `@clauses` entry is a substring of an
  # outcome cell - so the stripper that makes it provably content-preserving has to be a
  # mechanism that has already been seen to fail before it certifies anything.
  #
  # These drive `parse/1` on fixture text rather than the real contract, because the real
  # contract carries no markers yet: a stripper tested against it today passes by doing
  # nothing, which is the vacuous first run rule 1 exists to catch.
  describe "clause-ID markers strip back to contract text" do
    @plain_table """
    | From-state / input / guard | Domain outcome and owned actions |
    |---|---|
    | queued; no pause/drain/cancel | Create a fresh attempt |
    | draft; valid PM create | queued or blocked with reason |
    """

    @annotated_table """
    | From-state / input / guard | Domain outcome and owned actions |
    |---|---|
    | queued {R4.04.f1}; no pause {R4.04.f2}/drain {R4.04.f3}/cancel {R4.04.f4} | Create a fresh attempt {R4.04.o1} |
    | draft {R4.02.f1}; valid PM create {R4.02.f2} | queued or blocked with reason {R4.02.o1} |
    """

    test "an annotated table parses to exactly the rows the plain table does" do
      assert R4Rows.parse(@annotated_table) == R4Rows.parse(@plain_table)
    end

    # Red control per rule 1. Without it the test above is satisfied by a `parse/1` that
    # returns [] for both, or by a stripper that deletes whole cells.
    test "a word changed under the annotation is not absorbed by stripping" do
      tampered = String.replace(@annotated_table, "fresh", "new")

      refute R4Rows.parse(tampered) == R4Rows.parse(@plain_table)
      assert R4Rows.parse(@plain_table) != []
    end

    # The stripper removes a marker and at most ONE preceding space. It must not tidy
    # anything else: `bin/contract_annotation_diff.exs` proves an annotation changed no
    # content by stripping and diffing, and a stripper that normalises whitespace would
    # report a sloppy edit as clean. This pins the conservatism the proof rests on.
    test "stripping normalises nothing beyond the marker and one space" do
      assert R4Rows.strip_ids("queued {R4.04.f1};") == "queued;"
      assert R4Rows.strip_ids("queued  {R4.04.f1};") == "queued ;"
      assert R4Rows.strip_ids("queued{R4.04.f1};") == "queued;"
      assert R4Rows.strip_ids("  spaced  ") == "  spaced  "
    end

    # An ID that does not match the marker shape survives stripping and therefore shows up
    # as a diff. A typo that silently vanished would be a marker the coverage number never
    # counts, in a file nothing else re-reads.
    test "a malformed marker is left in place rather than silently removed" do
      assert R4Rows.strip_ids("queued {R4.4.f1};") == "queued {R4.4.f1};"
      assert R4Rows.strip_ids("queued {R5.04.f1};") == "queued {R5.04.f1};"
      assert R4Rows.strip_ids("queued {R4.04.x1};") == "queued {R4.04.x1};"
    end
  end

  # ── EV-6: the from-state half of every row ──────────────────────────────────────────
  #
  # `@clauses` and `@uncited` above count OUTCOME cells only. A from-cell was a verbatim
  # lookup key and nothing more, so its conjuncts were never enumerated, never asserted and
  # never recorded as uncited. An unimplemented outcome clause shows up as uncited and is
  # countable; an unimplemented precondition showed up nowhere. Row :467 is the witness -
  # "no pause/drain/cancel", consulted by no guard, violated two events from empty, and
  # found by a person reading prose against code at the cost of a review round.
  #
  # The contract now carries an ID per from-cell obligation. Each must be classified:
  #
  #   {:guarded, atoms, why}  the reducer owns it and refuses; each atom must be one the
  #                           kernel actually declares
  #   {:protected, why}       a protected fact the kernel may not restate - eligibility,
  #                           authenticated grants, "proved no ref change"
  #   {:unguarded, why}       reducer-owned, nothing refuses it. A recorded defect
  #   {:input, why}           the conjunct names the event that selects the handler, not a
  #                           precondition on state. Discharged by dispatch and
  #                           `Event.validate/2`, and there is no guard to look for
  #   {:effect, why}          implemented as a BRANCH INSIDE THE EFFECT: the event is
  #                           accepted either way and the conjunct decides the outcome.
  #                           No atom, no require_* site, and the row still drives, so no
  #                           mechanism here can see it - its defence is the outcome-side
  #                           clause of the same row, tracked by @clauses
  #
  # The last two categories were not in the first design. They were forced by reading, and
  # both would otherwise have been recorded as :unguarded - a defect where the contract is
  # in fact implemented. That is why this list shrinks a row at a time: classifying 69
  # obligations in one sitting against a category set derived from one row would have
  # produced a confident inventory of holes that are not there.
  #
  # WHAT THIS DOES NOT DO, so it is not rediscovered as a surprise:
  #
  #   * It proves an obligation HAS a guard, never that the named guard is the RIGHT one.
  #     A plausible atom from the wrong handler passes. Only a person reading the row
  #     against the handler catches that, which is the human step EVIDENCE-TOOLS names as
  #     unmechanisable.
  #   * It says nothing about whether a TEST exercises the guard. That is the mutation
  #     sweep's question, at call-site granularity.
  #   * `declared_reasons/0` reads `kernel.ex` with regexes, so a refusal spelled a third
  #     way reads as absent. That direction is safe: a false gap, never a false clean.
  @from_obligations %{
    # Verified by reading `do_transition("launch_planned", ...)` at kernel.ex:425-435.
    "R4.04.f1" =>
      {:guarded, [:wrong_source_phase],
       "require_phase/2 at the head of the with chain. NOTE the guard admits ~w(queued developing) where the row says queued; the outcome cell's \"unless R4a retained a resumable developer attempt\" is the candidate licence for that widening, and nothing pins it"},
    "R4.04.f2" =>
      {:protected,
       "dependencies/resources/profile/reservation eligibility is protected policy the kernel may not restate - the same category require_settlement_source/2 records at its own site"},
    # R4.02 "draft". The kernel encodes "draft" as the ABSENCE of a ticket and enforces it
    # before dispatch: `resolve_entity/3` (kernel.ex:144-153) refuses a creating event that
    # names an existing entity, and `do_transition("ticket_admitted", :absent, ...)` (:259)
    # matches only that case. No require_* guard is involved, which is the point - see the
    # four refusal shapes recorded in EVIDENCE-TOOLS.
    "R4.02.f1" =>
      {:guarded, [:entity_already_exists],
       "draft means no ticket in state; enforced pre-dispatch by resolve_entity/3 and by the :absent function head, not by a guard in the handler body"},
    "R4.02.f2" =>
      {:input,
       "specific spec or valid PM create is the row's input, not a precondition on state; :invalid_admission_phase refuses the TARGET phase rather than the from-state"},

    # R4.03. Both handlers for this row guard the phase, and the phase set agrees with the
    # row exactly - unlike R4.04, where the guard admits one the row does not name.
    "R4.03.f1" =>
      {:guarded, [:wrong_source_phase],
       "ticket_amended (kernel.ex:290) and ticket_parked (:303) both require_phase ~w(queued blocked), which is the row's cell exactly"},
    "R4.03.f2" =>
      {:input, "PM amend/park is the row's input, carried by two event types rather than one"},
    "R4.24.f1" =>
      {:guarded, [:wrong_source_phase],
       "ticket_unblocked (kernel.ex:337) require_phase ~w(blocked), which is the row's cell exactly"},

    # R4.27 is guarded by an inline `if` rather than a require_* call, so the guard mutation
    # sweep cannot neutralise it: its population is every non-definition require_*( site.
    # One of 24 refusal sites outside that population; `bin/refusal_sites.exs` prints them.
    "R4.27.f1" =>
      {:guarded, [:ticket_terminal],
       "cancellation_requested (kernel.ex:392) refuses a terminal phase with an inline if, OUTSIDE the mutation sweep's population - the guard is real, and nothing at call-site granularity can check that a test exercises it"},
    "R4.27.f2" =>
      {:input,
       "cancel requested is the row's input; the control flag it sets is this row's outcome, not its precondition"},
    "R4.28.f1" =>
      {:guarded, [:cancel_not_requested],
       "cancellation_finalized (kernel.ex:403) require_cancel_requested/1"},
    "R4.28.f2" =>
      {:guarded, [:attempt_still_active, :executions_not_closed],
       "require_no_active_attempt/1 and require_all_executions_closed/1 at kernel.ex:404-405. NOTE require_all_executions_closed/1 and require_cleanup_complete/1 are the SAME predicate under two names and two atoms, so a test pinning either exercises identical logic"},
    # R4.11. The handler guards MORE than the row states: `checks_started` requires ticket
    # phase awaiting_review as well, which this row's cell does not name. Stronger than the
    # contract is safe; the note exists because the reverse also occurs, at R4.04 and R4.20.
    "R4.11.f1" =>
      {:guarded, [:wrong_attempt_phase],
       "checks_started (kernel.ex:638) require_attempt_phase ~w(candidate_frozen). The row's cell names the ATTEMPT phase; the handler additionally requires ticket phase awaiting_review, which the row does not mention"},
    "R4.11.f2" =>
      {:guarded, [:developer_not_closed],
       "checks_started (kernel.ex:639) require_developer_closed/1"},
    "R4.11.f3" =>
      {:protected,
       "check capacity is allocation, which is protected policy the kernel may not restate - the same category as R4.04's eligibility conjunct"},

    # R4.12.f2 is the first conjunct found to be implemented as a BRANCH IN THE EFFECT rather
    # than as a guard. Nothing refuses it: `check_recorded` accepts, records the receipt, and
    # `maybe_finish_checks/1` advances the attempt only when every status is passed. Calling
    # it :unguarded would manufacture a defect where the contract is in fact implemented.
    "R4.12.f1" =>
      {:guarded, [:wrong_attempt_phase],
       "check_recorded (kernel.ex:693) require_attempt_phase ~w(checking)"},
    "R4.12.f2" =>
      {:effect,
       "maybe_finish_checks/1 evaluates it inside the effect body and advances the attempt to awaiting_review only when it holds. There is no atom, no require_* site and the row still drives, so no mechanism in the evidence set can see it; its defence is the outcome-side clause of this same row, tracked by @clauses"},

    # R4.15.
    "R4.15.f1" =>
      {:guarded, [:wrong_source_phase, :wrong_attempt_phase],
       "review_planned (kernel.ex:712 and :714) requires both ticket and attempt phase awaiting_review"},
    "R4.15.f2" =>
      {:guarded, [:checks_not_passed], "review_planned (kernel.ex:715) require_checks_passed/1"},
    "R4.15.f3" =>
      {:protected, "reviewer capacity is allocation, protected policy the kernel may not restate"},

    # R4.16-R4.18 share one handler, review_recorded, and one phase guard. The verdict value
    # selects the branch, so for the correction and rejected rows the second conjunct is the
    # input; only the approved row's conjunct carries guarded content of its own.
    "R4.16.f1" =>
      {:guarded, [:wrong_attempt_phase],
       "review_recorded (kernel.ex:768) require_attempt_phase ~w(reviewing)"},
    "R4.16.f2" =>
      {:guarded, [:invalid_verdict, :verdict_names_another_candidate],
       "require_verdict/1 and require_review_candidate/2 at kernel.ex:770-771 carry \"valid\" and \"exact-candidate\"; \"approved\" itself selects the outcome branch and is the input"},
    "R4.17.f1" =>
      {:guarded, [:wrong_attempt_phase],
       "review_recorded (kernel.ex:768), shared with R4.16 and R4.18"},
    "R4.17.f2" => {:input, "the verdict value selects this row's branch within review_recorded"},
    "R4.18.f1" =>
      {:guarded, [:wrong_attempt_phase],
       "review_recorded (kernel.ex:768), shared with R4.16 and R4.17"},
    "R4.18.f2" => {:input, "the verdict value selects this row's branch within review_recorded"},

    # R4.20's guard admits a phase the row does not name - the R4.04 shape again, and here
    # the licence is explicit: R4.21's from-cell IS "ready_to_integrate/integrating", and the
    # two rows share integration_planned.
    "R4.20.f1" =>
      {:guarded, [:wrong_source_phase],
       "integration_planned (kernel.ex:852) require_phase ~w(ready_to_integrate integrating). The row names only ready_to_integrate; the widening is licensed by R4.21, which shares this handler and names both"},

    # R4.22.
    "R4.22.f1" =>
      {:guarded, [:wrong_source_phase],
       "integration_recorded (kernel.ex:891) require_phase ~w(integrating)"},
    "R4.22.f3" =>
      {:guarded, [:workers_not_closed],
       "integration_recorded (kernel.ex:895) require_workers_closed/1"},
    "R4.05.f1" =>
      {:guarded, [:wrong_source_phase],
       "artifact_frozen (kernel.ex:460) require_phase ~w(developing), the row's cell exactly"},

    # R4.06.f2's "before valid candidate" is carried by the ATTEMPT phase, not by a guard
    # naming candidates: `artifact_frozen` sets the attempt to candidate_frozen (kernel.ex:469),
    # so require_attempt_phase ~w(active) at :501 admits only an attempt that has not frozen one.
    # Nothing states that connection at either site; it was derived by reading both.
    "R4.06.f1" =>
      {:guarded, [:wrong_source_phase],
       "freeze_failed (kernel.ex:499) require_phase ~w(developing)"},
    "R4.06.f2" =>
      {:guarded, [:wrong_attempt_phase, :invalid_freeze_disposition],
       "\"before valid candidate\" is require_attempt_phase ~w(active) at :501, which excludes an attempt artifact_frozen has already moved to candidate_frozen; the failure kind is the inline :invalid_freeze_disposition"},
    "R4.09.f1" =>
      {:guarded, [:wrong_source_phase],
       "artifact_blocked (kernel.ex:482) require_phase ~w(developing)"},
    "R4.09.f2" =>
      {:guarded, [:invalid_blocked_result],
       "artifact_blocked (kernel.ex:485) require_blocked_result/1"},

    # R4.10's cell is a category - "any open submission phase" - and the kernel spells it as
    # an enumeration plus a stream check. If a third submission phase is ever added, the row
    # stays true and the guard silently stops implementing it. Nothing here would notice.
    "R4.10.f1" =>
      {:guarded, [:wrong_source_phase, :submission_stream_sealed],
       "submission_rejected (kernel.ex:537) require_phase ~w(developing reviewing) enumerates the open submission phases, and require_open_submission_stream/1 at :539 carries \"open\""},
    "R4.10.f2" => {:input, "a malformed result is what this event type reports"},

    # R4.12, R4.13 and R4.14 share check_recorded and its one phase guard, the way R4.16-R4.18
    # share review_recorded. The status value selects the branch, so it is the input;
    # require_check_status/1 only validates that it is one of the known statuses.
    "R4.13.f1" =>
      {:guarded, [:wrong_attempt_phase],
       "check_recorded (kernel.ex:693) require_attempt_phase ~w(checking)"},
    "R4.13.f2" => {:input, "the recorded status selects this row's branch within check_recorded"},
    "R4.14.f1" =>
      {:guarded, [:wrong_attempt_phase],
       "check_recorded (kernel.ex:693), shared with R4.12 and R4.13"},
    "R4.14.f2" => {:input, "the recorded status selects this row's branch within check_recorded"},

    # R4.26 is refused pre-dispatch, not in a handler: refuse_terminal_ticket/2 runs in the
    # envelope pipeline. One of the 24 sites outside the sweep's population, and the second
    # producer of :ticket_terminal - which is why guard reachability, keyed by atom, cannot
    # tell this site from R4.27's inline if.
    "R4.26.f1" =>
      {:guarded, [:ticket_terminal],
       "refuse_terminal_ticket/2 (kernel.ex:212-219), a pre-dispatch check rather than a guard in any handler"},
    "R4.26.f2" =>
      {:guarded, [:ticket_terminal],
       "\"ordinary\" is encoded as that same predicate's exclusions - @terminal_cleanup_events and finalizing_integrated_cancel?/2 are admitted on a terminal ticket, everything else is refused"},
    "R4.04.f3" =>
      {:unguarded,
       "B3. paused and draining are written by control_changed (kernel.ex:977-984) and read by no transition in the kernel; cancel_requested is not consulted here either. Outstanding and designed - subcommit 2 owns the fix, and this entry is what makes it countable until then"}
  }

  # Every other from-cell obligation. Classifying one is a per-row reading pass against its
  # handler, and doing them in a sitting is the shape that produced six of this subcommit's
  # defects - "verify the property on item one, assert it of the list". 42 of 72 are
  # classified; this list holds the other 30 and can only shrink.
  #
  # Three are deliberately still here rather than guessed. R4.24.f2 is a disjunction whose
  # branches have different dispositions - "explicit resume" is the input, "recorded
  # dependency/resource recovery" is a protected fact. R4.28.f3 "cleanup reconciled" is
  # equated by the kernel with "every execution closed", which may be narrower than the
  # contract's cleanup notion; saying which needs a read of the contract, not of the kernel.
  #
  # R4.07.f1 "candidate_frozen" is the one that looks like a second :unguarded and is not
  # being recorded as one yet. `execution_observed` has no phase guard at all, so the row's
  # from-state is not gated there - but the row's outcome is "cleanup observation only", which
  # is phase-independent, and the transitions the row FORBIDS are refused by other handlers
  # (its scenario pins :wrong_attempt_phase on a forged settlement). So the precondition may be
  # enforced by the absence of a transition rather than by a guard, which is a structure none
  # of the five dispositions expresses. Inventing a sixth on one witness is the mistake this
  # list exists to avoid; it needs a second example before it is a category.
  #
  # The measurement that killed the shortcut: a blanket rule for the phase conjunct would
  # have been WRONG for 20 of the kernel's 37 `do_transition` clauses. 17 call
  # `require_phase/2` (:wrong_source_phase), 10 call `require_attempt_phase/2`
  # (:wrong_attempt_phase), and the rest - `ticket_admitted`, `cancellation_requested`,
  # `cancellation_finalized`, `attempt_settled` and `control_changed` among them - guard the
  # phase some third way or not at all. That is rule 4's partial generalisation waiting to
  # happen, so the list shrinks a row at a time and this test holds the ratchet.
  @from_unclassified [
    "R4.01.f1",
    "R4.01.f2",
    "R4.05.f2",
    "R4.07.f1",
    "R4.07.f2",
    "R4.08.f1",
    "R4.08.f2",
    "R4.08.f3",
    "R4.19.f1",
    "R4.19.f2",
    "R4.19.f3",
    "R4.20.f2",
    "R4.21.f1",
    "R4.21.f2",
    "R4.22.f2",
    "R4.23.f1",
    "R4.23.f2",
    "R4.23.f3",
    "R4.24.f2",
    "R4.25.f1",
    "R4.25.f2",
    "R4.25.f3",
    "R4.28.f3",
    "R4a.01.f1",
    "R4a.01.f2",
    "R4a.02.f1",
    "R4a.02.f2",
    "R4a.03.f1",
    "R4a.03.f2",
    "R4a.04.f1"
  ]

  describe "every from-cell obligation is classified" do
    test "the classification covers the contract's from-cell IDs exactly, and no more" do
      found = check(contract_from_ids(), @from_obligations, @from_unclassified, MapSet.new())

      assert found.unclassified_and_unrecorded == [],
             "from-cell obligations the contract carries that nothing classifies: " <>
               inspect(found.unclassified_and_unrecorded)

      assert found.recorded_but_absent == [],
             "classified IDs that no longer appear in the contract - a row was edited: " <>
               inspect(found.recorded_but_absent)
    end

    test "every guarded obligation names a refusal the kernel declares" do
      declared = KernelSearch.declared_reasons()
      found = check(contract_from_ids(), @from_obligations, @from_unclassified, declared)

      assert found.absent_guard == [],
             "obligations pinned to a refusal the kernel never declares - either the guard " <>
               "was never written, or it is spelled a way declared_reasons/0 cannot see:\n" <>
               Enum.map_join(found.absent_guard, "\n", fn {id, a} -> "  #{id}: #{inspect(a)}" end)
    end

    test "every obligation that is not simply guarded states why" do
      for {id, disposition} <- @from_obligations do
        why = reason(disposition)

        assert is_binary(why) and String.length(why) > 20,
               "#{id} is recorded as #{elem(disposition, 0)} with no reason worth the record"
      end
    end

    # Red control per rule 1. Without it every assertion above is satisfied by a `check/4`
    # that returns empty lists, which is how five mechanisms in this subcommit shipped
    # confident, clean and entirely vacuous.
    test "a conjunct no refusal pins is reported" do
      declared = KernelSearch.declared_reasons()
      bogus = Map.put(@from_obligations, "R4.04.f3", {:guarded, [:no_such_guard], "fixture"})

      assert check(contract_from_ids(), bogus, @from_unclassified, declared).absent_guard ==
               [{"R4.04.f3", :no_such_guard}]

      dropped = Map.delete(@from_obligations, "R4.04.f1")
      found = check(contract_from_ids(), dropped, @from_unclassified, declared)
      assert found.unclassified_and_unrecorded == ["R4.04.f1"]

      extra =
        check(contract_from_ids(), @from_obligations, ["R4.99.f1" | @from_unclassified], declared)

      assert extra.recorded_but_absent == ["R4.99.f1"]
    end
  end

  defp contract_from_ids, do: Enum.flat_map(R4Rows.ids(), &R4Rows.from_ids/1)

  defp contract_outcome_ids, do: Enum.flat_map(R4Rows.ids(), &R4Rows.outcome_ids/1)

  # An ID names its row - "R4.09.o3" is the ninth R4 row - but the mapping from row number
  # to handle lives in the contract's ordering, not in the ID, so it is looked up rather
  # than computed. Computing it would be a second encoding of the row order.
  defp row_of(id) do
    row = Enum.find(R4Rows.ids(), fn r -> id in R4Rows.outcome_ids(r) end)
    {row, if(row, do: Map.new(R4Rows.obligations(row, :outcome)), else: %{})}
  end

  defp partition(ids, clauses, uncited) do
    asserted = for {_row, entries} <- clauses, {id, _quote} <- entries, do: id
    recorded = Enum.map(uncited, &elem(&1, 0))

    %{
      total: length(ids),
      asserted: length(asserted),
      recorded: length(recorded),
      unaccounted: Enum.sort(ids -- (asserted ++ recorded)),
      both: Enum.sort(asserted -- (asserted -- recorded)),
      absent: Enum.sort(Enum.uniq(asserted ++ recorded) -- ids)
    }
  end

  defp check(ids, obligations, unclassified, declared) do
    recorded = Map.keys(obligations) ++ unclassified

    %{
      unclassified_and_unrecorded: Enum.sort(ids -- recorded),
      recorded_but_absent: Enum.sort(recorded -- ids),
      absent_guard:
        for(
          {id, {:guarded, atoms, _}} <- obligations,
          atom <- atoms,
          not MapSet.member?(declared, atom),
          do: {id, atom}
        )
    }
  end

  defp reason({:guarded, _atoms, why}), do: why
  defp reason({:protected, why}), do: why
  defp reason({:unguarded, why}), do: why
  defp reason({:input, why}), do: why
  defp reason({:effect, why}), do: why

  describe "the row inventory tracks the contract" do
    # Compared as sorted lists, not sets. A set comparison passed when a duplicate
    # from-cell with a contradictory outcome was appended to the contract, because the
    # duplicate collapsed into the existing member - the third review demonstrated it.
    test "every contract transition row has a declared handle, and vice versa" do
      contract = Enum.map(R4Rows.contract_rows(), &elem(&1, 0))
      declared = Enum.map(R4Rows.ids(), &R4Rows.declared_from/1)

      assert Enum.sort(contract) -- Enum.sort(declared) == [],
             "contract rows with no handle - the contract gained or duplicated a row"

      assert Enum.sort(declared) -- Enum.sort(contract) == [],
             "handles matching no contract row - a row was edited or removed"

      assert length(contract) == length(Enum.uniq(contract)),
             "the contract has two rows with the same from-state cell"
    end

    # The outcome side was a hand transcription nothing checked until the third review, and
    # then a transcription checked against the whole CELL: a quote had only to appear
    # somewhere in the row. The clause unit itself was `String.split(~r/;|(?<=\.)\s+/)` -
    # punctuation - and a fragment counted as asserted whenever it merely CONTAINED a cited
    # quote. Measured before this changed, by a probe that read these very maps:
    #
    #   * 7 obligations were invisible, each sharing a fragment with an asserted quote.
    #     "Git/scope validation failure is invalid submission" did not exist to the number
    #     because "never a frozen result" sat beside it.
    #   * 7 spans were claimed twice - a cited quote spanning a `;` while the clause after
    #     the `;` was separately recorded as uncited, differing only by a trailing period,
    #     which is exactly why `String.contains?/2` never reported the contradiction.
    #   * 4 of those uncited entries were stale: the scenario asserts the clause.
    #
    # Now every obligation carries an ID in the contract and belongs to exactly one of
    # @clauses or @uncited. A citation names the ID and quotes it, so the quote is checked
    # against THAT obligation rather than against the whole cell, and a citation drifting
    # onto a neighbouring clause fails here.
    test "every cited clause still quotes the obligation it names" do
      for {row, entries} <- @clauses, {id, quote} <- entries do
        obligations = Map.new(R4Rows.obligations(row, :outcome))

        assert Map.has_key?(obligations, id),
               "#{row} cites #{id}, which the contract's outcome cell no longer carries"

        assert String.contains?(obligations[id], quote),
               "#{row}'s citation of #{id} is no longer the contract's words:\n" <>
                 "  cited:      #{inspect(quote)}\n" <>
                 "  obligation: #{inspect(obligations[id])}"
      end
    end

    # A @partial entry quotes the clause it cannot yet express. That quote must come from
    # its own row's outcome cell - one entry quoted another row's text, which read as
    # coverage of a row nobody covered and left the real row unrecorded.
    test "every partial entry quotes a clause of its own row" do
      for {id, note} <- @partial do
        outcome = R4Rows.outcome(id)
        assert is_binary(outcome), "#{id} matches no contract row"

        quoted = Regex.scan(~r/"([^"]{12,})"/, note) |> Enum.map(&List.last/1)

        assert quoted != [], "#{id} records no quoted clause, so what is deferred is unstated"

        for clause <- quoted do
          assert String.contains?(outcome, clause),
                 "#{id} defers a clause that is not in its own outcome cell:\n" <>
                   "  quoted:  #{inspect(clause)}\n" <>
                   "  outcome: #{inspect(outcome)}"
        end
      end
    end

    test "every uncited clause still quotes the obligation it names" do
      for {id, text} <- @uncited do
        {row, obligations} = row_of(id)

        assert Map.has_key?(obligations, id),
               "#{id} is recorded as uncited but #{row}'s outcome cell no longer carries it"

        assert obligations[id] == text,
               "#{id}'s recorded text drifted from the contract:\n" <>
                 "  recorded: #{inspect(text)}\n" <>
                 "  contract: #{inspect(obligations[id])}"
      end
    end

    # The coverage number, with no heuristic left in it: every obligation the contract
    # states is asserted by some scenario or recorded as unasserted, and never both.
    test "every row with a scenario cites at least one obligation of its outcome" do
      silent = Enum.reject(R4Rows.ids(), &Map.has_key?(@clauses, &1))

      assert silent == [],
             "rows whose scenario asserts nothing traceable to the contract: #{inspect(silent)}"
    end

    test "every outcome obligation is asserted or recorded, and never both" do
      found = partition(contract_outcome_ids(), @clauses, @uncited)

      # Rule 2: the claim ships with its denominator, computed from the lists rather than
      # carried in a comment. Every hand-carried count in this file has been wrong.
      IO.puts(
        "\nR4/R4a outcome obligations: #{found.total} - " <>
          "#{found.asserted} asserted, #{found.recorded} recorded uncited"
      )

      assert found.unaccounted == [],
             "contract obligations that nothing asserts and nothing records:\n" <>
               Enum.map_join(found.unaccounted, "\n", &"  #{&1}")

      assert found.both == [],
             "obligations counted as asserted AND as uncited - the double count this " <>
               "replaced the punctuation splitter to make impossible:\n" <>
               Enum.map_join(found.both, "\n", &"  #{&1}")

      assert found.absent == [],
             "asserted or recorded IDs the contract no longer carries:\n" <>
               Enum.map_join(found.absent, "\n", &"  #{&1}")
    end

    # Red control per rule 1. Each of the three assertions above is satisfied by a
    # `partition/3` that returns empty lists, which is the shape five mechanisms in this
    # subcommit shipped in.
    test "an obligation in both lists, in neither, or in no row is reported" do
      ids = contract_outcome_ids()
      [{sample, _} | _] = @uncited

      both = partition(ids, Map.put(@clauses, :admission, [{sample, "x"}]), @uncited)
      assert sample in both.both

      dropped = partition(ids, @clauses, Enum.reject(@uncited, &(elem(&1, 0) == sample)))
      assert dropped.unaccounted == [sample]

      invented = partition(ids, @clauses, [{"R4.99.o1", "x"} | @uncited])
      assert invented.absent == ["R4.99.o1"]
    end
  end

  describe "every contract row is driven" do
    # One test per row. The aggregate test below still holds the ratchets, but it stops at
    # its first failure, so a run reporting one broken row said nothing about the other
    # thirty-one. Naming each row also makes a failure legible without reading the harness.
    for row <- R4Rows.ids() do
      test "#{row}" do
        assert run(unquote(row)) in [:driven, :unexpressible],
               "#{unquote(row)} has no scenario and is not recorded as unexpressible"
      end
    end

    test "each row has a scenario that drives it, or is recorded as unexpressible" do
      results = Map.new(R4Rows.ids(), fn id -> {id, run(id)} end)

      undriven =
        results
        |> Enum.filter(fn {_id, result} -> result == :no_scenario end)
        |> Enum.map(&elem(&1, 0))

      assert undriven == [],
             "rows with no scenario at all: #{inspect(undriven)}. " <>
               "A contract row must be driven or explicitly recorded as unexpressible."

      unexpressible =
        results
        |> Enum.filter(fn {_id, result} -> result == :unexpressible end)
        |> Enum.map(&elem(&1, 0))
        |> Enum.sort()

      assert unexpressible == Enum.sort(Map.keys(@unexpressible)),
             "the unexpressible set moved. now: #{inspect(unexpressible)}, " <>
               "recorded: #{inspect(Enum.sort(Map.keys(@unexpressible)))}"
    end

    test "every partially expressible row is still declared, and still driven" do
      for {id, _clause} <- @partial do
        assert id in R4Rows.ids(), "#{id} is not a contract row"
        assert run(id) == :driven, "#{id} is recorded as partial but no longer drives"
      end
    end
  end

  defp run(id) do
    if Map.has_key?(@unexpressible, id) do
      :unexpressible
    else
      scenario(id)
    end
  end

  # ── Scenarios ──────────────────────────────────────────────────────────────────────
  # Each drives its row and asserts the outcome the contract states. A rejection inside
  # drive/2 flunks, so "returns :driven" means every event was accepted.

  defp scenario(:objective_steering) do
    {state, _} =
      drive({State.new(), 0}, [
        {"objective_created", "OBJ1", %{"objective_id" => "OBJ1", "planning_owner_id" => "pm-1"}},
        {"pm_proposal_recorded", "OBJ1",
         %{"proposal_id" => "P1", "objective_id" => "OBJ1", "operation" => "create_ticket"}}
      ])

    objective = state["objectives"]["OBJ1"]
    assert objective["planning_owner_id"] == "pm-1"
    # "PM proposal is evidence, not authority" - recording one admits no ticket.
    assert map_size(objective["proposals"]) == 1
    assert state["tickets"] == %{}
    :driven
  end

  defp scenario(:admission) do
    {state, _} = admitted()
    assert state["tickets"]["T1"]["phase"] == "queued"
    :driven
  end

  defp scenario(:amend_or_park) do
    {state, _} =
      drive(admitted(), [
        {"ticket_amended", "T1",
         %{"ticket_id" => "T1", "spec_revision_id" => "spec-2", "spec" => %{}}},
        {"ticket_parked", "T1",
         %{"ticket_id" => "T1", "reason" => "dependency", "resume_phase" => "queued"}}
      ])

    ticket = state["tickets"]["T1"]
    assert ticket["phase"] == "blocked"
    assert ticket["spec_revision_id"] == "spec-2"
    assert ticket["resume_phase"] == "queued"
    :driven
  end

  defp scenario(:launch) do
    {state, _} = developing()
    ticket = state["tickets"]["T1"]
    assert ticket["phase"] == "developing"
    assert ticket["attempts"]["A1"]["phase"] == "active"
    :driven
  end

  defp scenario(:freeze_success) do
    {state, _} = frozen()
    ticket = state["tickets"]["T1"]
    assert ticket["phase"] == "awaiting_review"
    assert ticket["attempts"]["A1"]["phase"] == "candidate_frozen"
    assert ticket["attempts"]["A1"]["candidate_id"] == "cand-1"
    assert ticket["attempts"]["A1"]["sealed_generation"] == "gen-1"
    :driven
  end

  defp scenario(:freeze_failure) do
    {state, _} =
      drive(developing(), [
        {"freeze_failed", "T1",
         %{
           "ticket_id" => "T1",
           "attempt_id" => "A1",
           "disposition" => "blocked",
           "reason" => "freeze_failure"
         }}
      ])

    ticket = state["tickets"]["T1"]
    assert ticket["phase"] == "blocked"
    assert ticket["reason"] == "freeze_failure"
    # "Retain submitted bytes ... never a frozen result" - no candidate is inferred.
    assert is_nil(ticket["attempts"]["A1"]["candidate_id"])
    :driven
  end

  defp scenario(:developer_exit_after_freeze) do
    {state, _} =
      drive(frozen(), [
        {"execution_observed", "T1",
         %{
           "ticket_id" => "T1",
           "attempt_id" => "A1",
           "execution_id" => "X1",
           "observation" => "closing",
           "lifecycle" => "closing"
         }}
      ])

    attempt = state["tickets"]["T1"]["attempts"]["A1"]
    # "Cleanup observation only; preserve frozen candidate. No new developer and no
    # attempt failure."
    assert attempt["candidate_id"] == "cand-1"
    assert attempt["phase"] == "candidate_frozen"
    assert attempt["executions"]["X1"]["lifecycle"] == "closing"

    # "No new developer and **no attempt failure**". R4 gives candidate_frozen only this
    # cleanup row, so exhaustion has no source here - and exhaustion is the one disposition
    # whose guard is otherwise deliberately permissive, because every row producing it
    # turns on protected allocation the kernel may not restate. This is the hole that
    # argument leaves, stated as the refusal it is.
    {frozen_state, sequence} = frozen()

    forged =
      event("attempt_settled", "T1", frozen_state["tickets"]["T1"]["revision"], sequence + 1, %{
        "ticket_id" => "T1",
        "attempt_id" => "A1",
        "disposition" => "exhausted",
        "reason_code" => "developer_allocation",
        "settlement" => settlement()
      })

    assert {:error, :wrong_attempt_phase} = Harness.apply(frozen_state, forged),
           "an attempt was exhausted from candidate_frozen, which R4 gives no exhaustion row"

    :driven
  end

  defp scenario(:no_valid_candidate) do
    {state, _} =
      drive(developing(), [
        {"stream_sealed", "T1",
         %{
           "ticket_id" => "T1",
           "attempt_id" => "A1",
           "execution_id" => "X1",
           "last_accepted_sequence" => 4
         }},
        # "verified exit/timeout" - the seal makes "no valid candidate" a fact, the close
        # makes the exit verified. This scenario previously settled with the developer
        # still pending, which is how it failed to notice the guard was missing.
        {"developer_closed", "T1",
         %{"ticket_id" => "T1", "attempt_id" => "A1", "execution_id" => "X1"}},
        {"attempt_settled", "T1",
         %{
           "ticket_id" => "T1",
           "attempt_id" => "A1",
           "disposition" => "failed",
           "reason_code" => "no_valid_candidate",
           "settlement" => settlement()
         }}
      ])

    ticket = state["tickets"]["T1"]
    assert ticket["attempts"]["A1"]["phase"] == "terminal"
    assert ticket["attempts"]["A1"]["disposition"] == "failed"
    assert ticket["phase"] == "queued"
    # R4's "Execution result" entity state: a sealed stream with no candidate is `none`.
    assert ticket["attempts"]["A1"]["executions"]["X1"]["result"] == "none"

    # "verified exit/timeout", stated as the refusal. A sealed stream alone is not a
    # verified exit, and settling on one synthesizes a failure for a developer that may
    # never have run.
    {sealed_only, sequence} =
      drive(developing(), [
        {"stream_sealed", "T1",
         %{
           "ticket_id" => "T1",
           "attempt_id" => "A1",
           "execution_id" => "X1",
           "last_accepted_sequence" => 4
         }}
      ])

    forged =
      event("attempt_settled", "T1", sealed_only["tickets"]["T1"]["revision"], sequence + 1, %{
        "ticket_id" => "T1",
        "attempt_id" => "A1",
        "disposition" => "failed",
        "reason_code" => "no_valid_candidate",
        "settlement" => settlement()
      })

    assert {:error, :exit_not_verified} = Harness.apply(sealed_only, forged)

    # "after cleanup queue fresh bounded attempt" - the fresh attempt waits for cleanup.
    {settled, sequence} = {ticket, sequence} |> then(fn _ -> {state, 40} end)

    open_worker =
      event("launch_planned", "T1", settled["tickets"]["T1"]["revision"], sequence + 1, %{
        "ticket_id" => "T1",
        "attempt_id" => "A2",
        "authority" => authority("X2", "developer")
      })

    assert {:ok, _} = Harness.apply(settled, open_worker),
           "cleanup was complete, so a fresh attempt should launch"

    :driven
  end

  defp scenario(:blocked_result) do
    {state, _} =
      drive(developing(), [
        {"artifact_blocked", "T1",
         %{
           "ticket_id" => "T1",
           "attempt_id" => "A1",
           "observation_id" => "obs-2",
           "result" => "blocked",
           "reason" => "needs_decision"
         }},
        {"stream_sealed", "T1",
         %{
           "ticket_id" => "T1",
           "attempt_id" => "A1",
           "execution_id" => "X1",
           "last_accepted_sequence" => 5
         }},
        {"developer_closed", "T1",
         %{"ticket_id" => "T1", "attempt_id" => "A1", "execution_id" => "X1"}},
        {"attempt_settled", "T1",
         %{
           "ticket_id" => "T1",
           "attempt_id" => "A1",
           "disposition" => "blocked",
           "reason_code" => "needs_decision",
           "settlement" => settlement()
         }}
      ])

    ticket = state["tickets"]["T1"]
    # "Terminal blocked attempt, blocked ticket; close developer, no review."
    assert ticket["attempts"]["A1"]["disposition"] == "blocked"
    assert ticket["phase"] == "blocked"
    assert ticket["attempts"]["A1"]["executions"]["X1"]["lifecycle"] == "closed"

    # The row is "valid blocked/partial **result**". Without one there is no blocked
    # attempt to seal, and settling anyway left the ticket developing with no active
    # attempt - a state R4 does not have.
    {fresh, sequence} = developing()

    forged =
      event("attempt_settled", "T1", fresh["tickets"]["T1"]["revision"], sequence + 1, %{
        "ticket_id" => "T1",
        "attempt_id" => "A1",
        "disposition" => "blocked",
        "reason_code" => nil,
        "settlement" => settlement()
      })

    assert {:error, :no_blocked_result} = Harness.apply(fresh, forged)
    :driven
  end

  defp scenario(:malformed_submission) do
    {state, sequence} =
      drive(developing(), [
        {"submission_rejected", "T1",
         %{
           "ticket_id" => "T1",
           "attempt_id" => "A1",
           "observation_id" => "obs-3",
           "reason" => "malformed"
         }},
        {"submission_rejected", "T1",
         %{
           "ticket_id" => "T1",
           "attempt_id" => "A1",
           "observation_id" => "obs-4",
           "reason" => "malformed"
         }}
      ])

    attempt = state["tickets"]["T1"]["attempts"]["A1"]
    # "Durable rejected submission, charge one validation action" - each rejection is a
    # separate charge, and the attempt is not terminalised by one.
    assert attempt["rejected_submissions"] == 2
    assert attempt["phase"] == "active"
    assert is_nil(attempt["candidate_id"])

    # "further submission allowed only while stream open".
    {sealed, sequence} =
      drive({state, sequence}, [
        {"stream_sealed", "T1",
         %{
           "ticket_id" => "T1",
           "attempt_id" => "A1",
           "execution_id" => "X1",
           "last_accepted_sequence" => 9
         }}
      ])

    forged =
      event("submission_rejected", "T1", sealed["tickets"]["T1"]["revision"], sequence + 1, %{
        "ticket_id" => "T1",
        "attempt_id" => "A1",
        "observation_id" => "obs-5",
        "reason" => "malformed"
      })

    assert {:error, :submission_stream_sealed} = Harness.apply(sealed, forged)

    # "exhaustion closes execution and exhausts ticket" - the budget is protected
    # allocation, so exhaustion arrives as a settlement rather than being derived here.
    {exhausted, _} =
      drive({sealed, sequence}, [
        {"attempt_settled", "T1",
         %{
           "ticket_id" => "T1",
           "attempt_id" => "A1",
           "disposition" => "exhausted",
           "reason_code" => "validation_budget",
           "settlement" => settlement()
         }},
        {"developer_closed", "T1",
         %{"ticket_id" => "T1", "attempt_id" => "A1", "execution_id" => "X1"}}
      ])

    ticket = exhausted["tickets"]["T1"]
    assert ticket["phase"] == "exhausted"
    assert ticket["attempts"]["A1"]["executions"]["X1"]["lifecycle"] == "closed"
    :driven
  end

  defp scenario(:checks_start) do
    {state, _} = checking()
    ticket = state["tickets"]["T1"]
    assert ticket["phase"] == "awaiting_review"
    assert ticket["attempts"]["A1"]["phase"] == "checking"
    assert ticket["attempts"]["A1"]["candidate_id"] == "cand-1"
    :driven
  end

  defp scenario(:checks_passed) do
    {state, _} =
      drive(checking(), [
        {"check_planned", "T1",
         %{
           "ticket_id" => "T1",
           "attempt_id" => "A1",
           "check_id" => "C1",
           "authority" => authority("K1", "check")
         }},
        {"check_recorded", "T1",
         %{
           "ticket_id" => "T1",
           "attempt_id" => "A1",
           "check_id" => "C1",
           "status" => "passed",
           "reason_code" => nil
         }}
      ])

    assert state["tickets"]["T1"]["attempts"]["A1"]["phase"] == "awaiting_review"
    :driven
  end

  defp scenario(:check_assertion_failed) do
    {state, _} =
      drive(checking(), [
        {"check_planned", "T1",
         %{
           "ticket_id" => "T1",
           "attempt_id" => "A1",
           "check_id" => "C1",
           "authority" => authority("K1", "check")
         }},
        {"check_recorded", "T1",
         %{
           "ticket_id" => "T1",
           "attempt_id" => "A1",
           "check_id" => "C1",
           "status" => "failed",
           "reason_code" => "assertion_failed"
         }},
        {"worker_closed", "T1",
         %{"ticket_id" => "T1", "attempt_id" => "A1", "execution_id" => "K1"}},
        {"attempt_settled", "T1",
         %{
           "ticket_id" => "T1",
           "attempt_id" => "A1",
           "disposition" => "needs_correction",
           "reason_code" => "assertion_failed",
           "settlement" => settlement()
         }}
      ])

    ticket = state["tickets"]["T1"]
    # "Terminal needs_correction attempt; queue fresh developer after all check workers
    # close ... failed candidate never goes to approval."
    assert ticket["attempts"]["A1"]["disposition"] == "needs_correction"
    assert ticket["phase"] == "queued"
    assert ticket["attempts"]["A1"]["executions"]["K1"]["lifecycle"] == "closed"

    # "failed candidate never goes to approval" - stated as a refusal, since that is what
    # the clause is.
    #
    # Pinned to its exact atom, and that changed what this asserts. As `{:error, _}` it
    # passed while claiming to exercise `require_checks_passed`, and neutralising that
    # guard left it green: `maybe_finish_checks` only advances an attempt to
    # `awaiting_review` once every check has passed, so a failed check leaves the attempt
    # in `checking` and `review_planned` is refused one guard earlier, on the attempt
    # phase. The clause holds - a failed candidate cannot reach approval - but the
    # mechanism enforcing it is the phase, not the check-status guard. That guard is
    # consequently unreachable and is now recorded as such in the reachability suite.
    {failed, sequence} =
      drive(checking(), [
        {"check_planned", "T1",
         %{
           "ticket_id" => "T1",
           "attempt_id" => "A1",
           "check_id" => "C1",
           "authority" => authority("K1", "check")
         }},
        {"check_recorded", "T1",
         %{
           "ticket_id" => "T1",
           "attempt_id" => "A1",
           "check_id" => "C1",
           "status" => "failed",
           "reason_code" => "assertion_failed"
         }}
      ])

    forged =
      event("review_planned", "T1", failed["tickets"]["T1"]["revision"], sequence + 1, %{
        "ticket_id" => "T1",
        "attempt_id" => "A1",
        "authority" => authority("R1", "reviewer")
      })

    assert {:error, :wrong_attempt_phase} = Harness.apply(failed, forged)
    assert failed["tickets"]["T1"]["attempts"]["A1"]["phase"] == "checking"
    :driven
  end

  defp scenario(:check_infrastructure_failed) do
    {state, sequence} =
      drive(checking(), [
        {"check_planned", "T1",
         %{
           "ticket_id" => "T1",
           "attempt_id" => "A1",
           "check_id" => "C1",
           "authority" => authority("K1", "check")
         }},
        {"check_recorded", "T1",
         %{
           "ticket_id" => "T1",
           "attempt_id" => "A1",
           "check_id" => "C1",
           "status" => "timed_out",
           "reason_code" => "timed_out"
         }}
      ])

    ticket = state["tickets"]["T1"]
    # "Preserve candidate ... pending same phase" - not a terminal attempt.
    assert ticket["attempts"]["A1"]["candidate_id"] == "cand-1"
    assert ticket["attempts"]["A1"]["phase"] == "checking"
    assert ticket["attempts"]["A1"]["disposition"] == nil

    # The distinction between this row and row 12, stated as the refusal it is. Without
    # this the scenario passed whether or not the kernel told the rows apart: nothing else
    # in it depends on failed_check?/1, so counting a timeout as an assertion failure -
    # exactly the misreading this correction is for - left every assertion green.
    forged =
      event("attempt_settled", "T1", ticket["revision"], sequence + 1, %{
        "ticket_id" => "T1",
        "attempt_id" => "A1",
        "disposition" => "needs_correction",
        "reason_code" => "timed_out",
        "settlement" => settlement()
      })

    assert {:error, :no_correction_evidence} = Harness.apply(state, forged),
           "a timed-out check terminalised the attempt row 13 says to preserve"

    # "bounded new check-run reservation after cleanup": the worker closes, a new run is
    # reserved for the same check, and passing it clears the attempt to review.
    {state, _} =
      drive({state, sequence}, [
        {"worker_closed", "T1",
         %{"ticket_id" => "T1", "attempt_id" => "A1", "execution_id" => "K1"}},
        {"check_planned", "T1",
         %{
           "ticket_id" => "T1",
           "attempt_id" => "A1",
           "check_id" => "C1",
           "authority" => authority("K2", "check")
         }},
        {"check_recorded", "T1",
         %{
           "ticket_id" => "T1",
           "attempt_id" => "A1",
           "check_id" => "C1",
           "status" => "passed",
           "reason_code" => nil
         }}
      ])

    assert state["tickets"]["T1"]["attempts"]["A1"]["phase"] == "awaiting_review"

    # Row 12 is the other row: an assertion failure may never be re-reserved, or a failed
    # candidate would reach approval by retrying instead of by relabelling.
    {failed, sequence} =
      drive(checking(), [
        {"check_planned", "T1",
         %{
           "ticket_id" => "T1",
           "attempt_id" => "A1",
           "check_id" => "C1",
           "authority" => authority("K1", "check")
         }},
        {"check_recorded", "T1",
         %{
           "ticket_id" => "T1",
           "attempt_id" => "A1",
           "check_id" => "C1",
           "status" => "failed",
           "reason_code" => "assertion_failed"
         }}
      ])

    forged =
      event("check_planned", "T1", failed["tickets"]["T1"]["revision"], sequence + 1, %{
        "ticket_id" => "T1",
        "attempt_id" => "A1",
        "check_id" => "C1",
        "authority" => authority("K2", "check")
      })

    assert {:error, :check_already_exists} = Harness.apply(failed, forged)

    # "Unknown check retains lease and blocks retry."
    {unknown, sequence} =
      drive(checking(), [
        {"check_planned", "T1",
         %{
           "ticket_id" => "T1",
           "attempt_id" => "A1",
           "check_id" => "C1",
           "authority" => authority("K1", "check")
         }},
        {"check_recorded", "T1",
         %{
           "ticket_id" => "T1",
           "attempt_id" => "A1",
           "check_id" => "C1",
           "status" => "unknown",
           "reason_code" => nil
         }}
      ])

    forged =
      event("check_planned", "T1", unknown["tickets"]["T1"]["revision"], sequence + 1, %{
        "ticket_id" => "T1",
        "attempt_id" => "A1",
        "check_id" => "C1",
        "authority" => authority("K2", "check")
      })

    assert {:error, :check_already_exists} = Harness.apply(unknown, forged)

    # "or blocked(check_infrastructure)/exhausted" - the row's other alternative, which
    # was deferred with the R4a at-limit clauses and is reachable for the same reason they
    # now are. The candidate survives the block, which is what makes it a retry rather than
    # a failure.
    {blocked, _} =
      drive({state, 60}, [
        {"ticket_blocked", "T1",
         %{
           "ticket_id" => "T1",
           "reason" => "check_infrastructure",
           "resume_phase" => "awaiting_review"
         }}
      ])

    at_limit = blocked["tickets"]["T1"]
    assert at_limit["phase"] == "blocked"
    assert at_limit["reason"] == "check_infrastructure"
    assert at_limit["attempts"]["A1"]["candidate_id"] == "cand-1"
    :driven
  end

  defp scenario(:review_start) do
    {state, _} = reviewing()
    ticket = state["tickets"]["T1"]
    assert ticket["phase"] == "reviewing"
    assert ticket["attempts"]["A1"]["phase"] == "reviewing"
    assert ticket["attempts"]["A1"]["review"]["candidate_id"] == "cand-1"
    :driven
  end

  defp scenario(:verdict_approved) do
    {state, _} = ready_to_integrate()
    ticket = state["tickets"]["T1"]
    # "Close/seal reviewer; after verified close ready_to_integrate."
    assert ticket["phase"] == "ready_to_integrate"
    assert ticket["attempts"]["A1"]["executions"]["R1"]["lifecycle"] == "closed"
    :driven
  end

  defp scenario(:verdict_correction) do
    {state, _} =
      drive(verdict("correction"), [
        {"attempt_settled", "T1",
         %{
           "ticket_id" => "T1",
           "attempt_id" => "A1",
           "disposition" => "needs_correction",
           "reason_code" => nil,
           "settlement" => settlement()
         }},
        {"reviewer_closed", "T1",
         %{"ticket_id" => "T1", "attempt_id" => "A1", "execution_id" => "R1"}}
      ])

    ticket = state["tickets"]["T1"]
    # "Terminal needs_correction attempt; close/seal reviewer, then queued fresh developer."
    assert ticket["attempts"]["A1"]["disposition"] == "needs_correction"
    assert ticket["attempts"]["A1"]["executions"]["R1"]["lifecycle"] == "closed"
    assert ticket["phase"] == "queued"
    :driven
  end

  defp scenario(:verdict_rejected) do
    {state, _} =
      drive(verdict("rejected"), [
        {"attempt_settled", "T1",
         %{
           "ticket_id" => "T1",
           "attempt_id" => "A1",
           "disposition" => "rejected",
           "reason_code" => nil,
           "settlement" => settlement()
         }}
      ])

    ticket = state["tickets"]["T1"]
    assert ticket["attempts"]["A1"]["disposition"] == "rejected"
    assert ticket["phase"] == "rejected"
    :driven
  end

  defp scenario(:reviewer_crash) do
    {state, sequence} =
      drive(reviewing(), [
        {"stream_sealed", "T1",
         %{
           "ticket_id" => "T1",
           "attempt_id" => "A1",
           "execution_id" => "R1",
           "last_accepted_sequence" => 12
         }},
        {"reviewer_closed", "T1",
         %{"ticket_id" => "T1", "attempt_id" => "A1", "execution_id" => "R1"}}
      ])

    ticket = state["tickets"]["T1"]
    # "Preserve candidate, close reviewer then bounded new reviewer execution."
    assert ticket["attempts"]["A1"]["candidate_id"] == "cand-1"
    assert ticket["attempts"]["A1"]["executions"]["R1"]["lifecycle"] == "closed"
    assert ticket["phase"] == "awaiting_review"
    assert ticket["attempts"]["A1"]["phase"] == "awaiting_review"
    # The attempt is preserved, not terminalised.
    assert ticket["attempts"]["A1"]["disposition"] == nil

    # "bounded new reviewer execution" - a fresh reviewer can actually be launched.
    {state, _} =
      drive({state, sequence}, [
        {"review_planned", "T1",
         %{
           "ticket_id" => "T1",
           "attempt_id" => "A1",
           "authority" => authority("R2", "reviewer")
         }}
      ])

    assert state["tickets"]["T1"]["attempts"]["A1"]["review"]["execution_id"] == "R2"

    # "developer ledger untouched": the reviewer's crash consumed no developer allowance.
    assert state["tickets"]["T1"]["infrastructure"]["ordinals"]["developer"] == 0
    assert state["tickets"]["T1"]["infrastructure"]["ordinals"]["reviewer"] == 0
    :driven
  end

  defp scenario(:integration_start) do
    {state, _} = integrating()
    assert state["tickets"]["T1"]["phase"] == "integrating"
    assert state["tickets"]["T1"]["attempts"]["A1"]["phase"] == "integrating"
    :driven
  end

  defp scenario(:integration_success) do
    {state, _} =
      drive(integrating(), [
        {"integration_recorded", "T1",
         %{
           "ticket_id" => "T1",
           "attempt_id" => "A1",
           "execution_id" => "I1",
           "outcome" => "ref_created",
           "ref_receipt_id" => "ref-1"
         }},
        {"attempt_settled", "T1",
         %{
           "ticket_id" => "T1",
           "attempt_id" => "A1",
           "disposition" => "integrated",
           "reason_code" => nil,
           "settlement" => settlement()
         }}
      ])

    ticket = state["tickets"]["T1"]
    assert ticket["phase"] == "integrated"
    assert ticket["attempts"]["A1"]["disposition"] == "integrated"
    assert ticket["attempts"]["A1"]["ref_receipt_id"] == "ref-1"

    # "Exit notifications cannot overwrite this." Driving the row is half of it; the row
    # also forbids every later contradiction of the receipt, which is what the first
    # correction left open.
    {before_settle, sequence} =
      drive(integrating(), [
        {"integration_recorded", "T1",
         %{
           "ticket_id" => "T1",
           "attempt_id" => "A1",
           "execution_id" => "I1",
           "outcome" => "ref_created",
           "ref_receipt_id" => "ref-1"
         }}
      ])

    revision = before_settle["tickets"]["T1"]["revision"]

    for {type, payload} <- [
          {"integration_recorded",
           %{
             "ticket_id" => "T1",
             "attempt_id" => "A1",
             "execution_id" => "I1",
             "outcome" => "ref_created",
             "ref_receipt_id" => "ref-2"
           }},
          {"integration_recorded",
           %{
             "ticket_id" => "T1",
             "attempt_id" => "A1",
             "execution_id" => "I1",
             "outcome" => "infrastructure_failed",
             "ref_receipt_id" => nil
           }},
          {"integration_settled",
           %{
             "ticket_id" => "T1",
             "attempt_id" => "A1",
             "execution_id" => "I1",
             "settlement" => settlement()
           }},
          {"integration_planned",
           %{
             "ticket_id" => "T1",
             "attempt_id" => "A1",
             "authority" => authority("I2", "integration")
           }}
        ] do
      forged = event(type, "T1", revision, sequence + 1, payload)

      assert {:error, :ref_receipt_recorded} = Harness.apply(before_settle, forged),
             "#{type} was accepted after a ref receipt was recorded"
    end

    :driven
  end

  defp scenario(:integration_failure) do
    {state, _} =
      drive(integrating(), [
        {"integration_recorded", "T1",
         %{
           "ticket_id" => "T1",
           "attempt_id" => "A1",
           "execution_id" => "I1",
           "outcome" => "infrastructure_failed",
           "ref_receipt_id" => nil
         }}
      ])

    ticket = state["tickets"]["T1"]
    assert ticket["phase"] == "blocked"
    assert ticket["reason"] == "integration_failure"
    :driven
  end

  defp scenario(:base_moved) do
    {state, _} =
      drive(ready_to_integrate(), [
        {"attempt_settled", "T1",
         %{
           "ticket_id" => "T1",
           "attempt_id" => "A1",
           "disposition" => "superseded_base",
           "reason_code" => "base_moved",
           "settlement" => settlement()
         }}
      ])

    ticket = state["tickets"]["T1"]
    # "Terminal superseded_base attempt; fresh bounded rebase developer plus renewed
    # checks/review."
    assert ticket["attempts"]["A1"]["disposition"] == "superseded_base"
    assert ticket["phase"] == "queued"

    # The candidate and its review are retained as prior evidence, not discarded.
    assert ticket["attempts"]["A1"]["candidate_id"] == "cand-1"
    assert "A1" in ticket["prior_attempt_ids"]
    :driven
  end

  defp scenario(:resume) do
    {state, _} =
      drive(
        drive(admitted(), [
          {"ticket_parked", "T1",
           %{"ticket_id" => "T1", "reason" => "dependency", "resume_phase" => "queued"}}
        ]),
        [{"ticket_unblocked", "T1", %{"ticket_id" => "T1", "phase" => "queued"}}]
      )

    ticket = state["tickets"]["T1"]
    assert ticket["phase"] == "queued"
    assert is_nil(ticket["reason"])
    assert is_nil(ticket["resume_phase"])
    :driven
  end

  defp scenario(:reset) do
    # Reset from a ticket that has actually spent an allowance. Starting from a fresh
    # attempt made the "never reset prior consumption" assertion vacuous: zero before and
    # zero after is true of every state.
    {consumed, sequence} = nonstart()

    {exhausted, sequence} =
      drive({consumed, sequence}, [
        {"attempt_settled", "T1",
         %{
           "ticket_id" => "T1",
           "attempt_id" => "A1",
           "disposition" => "exhausted",
           "reason_code" => "developer_allocation",
           "settlement" => settlement()
         }}
      ])

    assert exhausted["tickets"]["T1"]["phase"] == "exhausted"

    {state, _} =
      drive({exhausted, sequence}, [
        {"ticket_reset", "T1", %{"ticket_id" => "T1", "generation" => %{"schema_version" => 1}}}
      ])

    ticket = state["tickets"]["T1"]
    # "Keep old attempt terminal; queue a fresh developer attempt using retained evidence
    # as context ... never reset prior consumption."
    assert ticket["phase"] == "queued"
    assert ticket["attempts"]["A1"]["phase"] == "terminal"
    assert ticket["attempts"]["A1"]["disposition"] == "exhausted"
    assert "A1" in ticket["prior_attempt_ids"]
    assert ticket["infrastructure"]["generation"] == 1

    # Finding 6: this asserted the developer ordinal was zero after a reset, from a state
    # where it had always been zero - true of any state, and so evidence of nothing. The
    # reset path now runs from an attempt that actually consumed an ordinal, so the
    # assertion distinguishes "the new generation starts clean" from "nothing ever
    # happened". Which of those R4a intends is argued at `ticket_reset` in the kernel and is
    # open to challenge; what is not open is asserting it without exercising it.
    assert consumed["tickets"]["T1"]["infrastructure"]["ordinals"]["developer"] == 1,
           "the fixture did not consume an ordinal, so the reset assertion proves nothing"

    assert ticket["infrastructure"]["ordinals"]["developer"] == 0

    # Note the boundary: this drives in the *reducer*. `ticket_reset`'s generation binds
    # reset_fact_v1, which has no producer in the durable codec, so the protected fact the
    # payload carries cannot yet be derived. That is a recorded subcommit 3 prerequisite,
    # not a kernel gap, and it is why "driven here" is not "works end to end".
    :driven
  end

  defp scenario(:terminal_rejection) do
    {state, sequence} =
      drive(verdict("rejected"), [
        {"attempt_settled", "T1",
         %{
           "ticket_id" => "T1",
           "attempt_id" => "A1",
           "disposition" => "rejected",
           "reason_code" => nil,
           "settlement" => settlement()
         }}
      ])

    forged =
      event("launch_planned", "T1", state["tickets"]["T1"]["revision"], sequence + 1, %{
        "ticket_id" => "T1",
        "attempt_id" => "A2",
        "authority" => authority("X2", "developer")
      })

    assert {:error, :ticket_terminal} = Harness.apply(state, forged)
    assert state["tickets"]["T1"]["attempts"]["A1"]["disposition"] == "rejected"
    :driven
  end

  defp scenario(:cancel_requested) do
    {state, _} =
      drive(developing(), [{"cancellation_requested", "T1", %{"ticket_id" => "T1"}}])

    ticket = state["tickets"]["T1"]
    # "Set orthogonal control ... hold phase/evidence while issued effects reconcile."
    assert ticket["cancel_requested"]
    assert ticket["phase"] == "developing"
    assert ticket["active_attempt_id"] == "A1"
    :driven
  end

  defp scenario(:cancel_finalized) do
    {state, _} =
      drive(developing(), [
        {"cancellation_requested", "T1", %{"ticket_id" => "T1"}},
        {"stream_sealed", "T1",
         %{
           "ticket_id" => "T1",
           "attempt_id" => "A1",
           "execution_id" => "X1",
           "last_accepted_sequence" => 4
         }},
        {"developer_closed", "T1",
         %{"ticket_id" => "T1", "attempt_id" => "A1", "execution_id" => "X1"}},
        {"attempt_settled", "T1",
         %{
           "ticket_id" => "T1",
           "attempt_id" => "A1",
           "disposition" => "cancelled",
           "reason_code" => nil,
           "settlement" => settlement()
         }},
        {"cancellation_finalized", "T1", %{"ticket_id" => "T1", "disposition" => "cancelled"}}
      ])

    ticket = state["tickets"]["T1"]
    assert ticket["phase"] == "cancelled"
    assert ticket["attempts"]["A1"]["disposition"] == "cancelled"
    :driven
  end

  defp scenario(:nonstart_developer) do
    {state, _} =
      drive(developing(), [
        {"launch_settled", "T1",
         %{
           "ticket_id" => "T1",
           "attempt_id" => "A1",
           "execution_id" => "X1",
           "settlement" => settlement()
         }}
      ])

    ticket = state["tickets"]["T1"]
    # "Keep the same nonterminal attempt ... return ticket developing -> queued with
    # resume_phase: developing and reason developer_launch_non_started."
    assert ticket["phase"] == "queued"
    assert ticket["resume_phase"] == "developing"
    assert ticket["reason"] == "developer_launch_non_started"
    assert ticket["active_attempt_id"] == "A1"
    assert ticket["attempts"]["A1"]["phase"] != "terminal"
    assert ticket["attempts"]["A1"]["executions"]["X1"]["lifecycle"] == "closed"
    assert ticket["infrastructure"]["ordinals"]["developer"] == 1

    # R4a: a proved non-start "closes **that** execution". A settlement naming another
    # role's execution closed it instead - the developer settlement could close a build
    # execution, spend the developer's allowance, and leave the developer running.
    {state, sequence} =
      drive(developing(), [
        {"build_planned", "T1",
         %{
           "ticket_id" => "T1",
           "attempt_id" => "A1",
           "build_id" => "B1",
           "authority" => authority("BX1", "build")
         }}
      ])

    forged =
      event("launch_settled", "T1", state["tickets"]["T1"]["revision"], sequence + 1, %{
        "ticket_id" => "T1",
        "attempt_id" => "A1",
        "execution_id" => "BX1",
        "settlement" => settlement()
      })

    assert {:error, :wrong_execution_role} = Harness.apply(state, forged)

    # "Below the infrastructure limit, queue a bounded developer retry" - and the retry has
    # to be launchable from where a resume actually puts the ticket. R4a stores
    # resume_phase: developing, so resuming lands in `developing` holding the retained
    # attempt whose only developer execution is the closed non-start.
    {resumed, _} =
      drive(nonstart(), [
        {"ticket_blocked", "T1",
         %{
           "ticket_id" => "T1",
           "reason" => "developer_launch_infrastructure",
           "resume_phase" => "developing"
         }},
        {"ticket_unblocked", "T1", %{"ticket_id" => "T1", "phase" => "developing"}},
        {"launch_planned", "T1",
         %{
           "ticket_id" => "T1",
           "attempt_id" => "A1",
           "authority" => authority("X2", "developer")
         }}
      ])

    attempt = resumed["tickets"]["T1"]["attempts"]["A1"]
    assert resumed["tickets"]["T1"]["phase"] == "developing"
    assert attempt["executions"]["X2"]["lifecycle"] == "pending"
    # The retained attempt is reused, not replaced, and the old non-start is retained.
    assert attempt["executions"]["X1"]["lifecycle"] == "closed"
    assert map_size(resumed["tickets"]["T1"]["attempts"]) == 1

    # A second developer may not be launched beside a live one.
    {live, sequence} = resumed |> then(&{&1, 99})

    forged =
      event("launch_planned", "T1", live["tickets"]["T1"]["revision"], sequence + 1, %{
        "ticket_id" => "T1",
        "attempt_id" => "A1",
        "authority" => authority("X3", "developer")
      })

    assert {:error, :developer_already_running} = Harness.apply(live, forged)

    # R4's freeze row is "developing; success artifact validates and freezes" - a developer
    # has to have been running to produce one. A ticket resumed to developing holds only
    # the closed non-start, so without this guard it could freeze a candidate for a
    # developer that never ran.
    {parked, sequence} =
      drive(nonstart(), [
        {"ticket_blocked", "T1",
         %{
           "ticket_id" => "T1",
           "reason" => "developer_launch_infrastructure",
           "resume_phase" => "developing"
         }},
        {"ticket_unblocked", "T1", %{"ticket_id" => "T1", "phase" => "developing"}}
      ])

    forged =
      event("artifact_frozen", "T1", parked["tickets"]["T1"]["revision"], sequence + 1, %{
        "ticket_id" => "T1",
        "attempt_id" => "A1",
        "candidate_id" => "cand-x",
        "observation_id" => "obs-x",
        "sealed_generation" => "gen-x"
      })

    assert {:error, :no_running_developer} = Harness.apply(parked, forged)
    :driven
  end

  defp scenario(:nonstart_reviewer) do
    {state, _} =
      drive(reviewing(), [
        {"review_settled", "T1",
         %{
           "ticket_id" => "T1",
           "attempt_id" => "A1",
           "execution_id" => "R1",
           "settlement" => settlement()
         }}
      ])

    ticket = state["tickets"]["T1"]
    # "Keep attempt and ticket awaiting_review, immutable candidate/check receipts and
    # reviewer ownership. Close only the failed reviewer execution; never enter developer
    # retry or correction."
    assert ticket["phase"] == "awaiting_review"
    assert ticket["attempts"]["A1"]["phase"] == "awaiting_review"
    assert ticket["attempts"]["A1"]["candidate_id"] == "cand-1"
    assert ticket["attempts"]["A1"]["checks"]["C1"]["status"] == "passed"
    assert ticket["attempts"]["A1"]["executions"]["R1"]["lifecycle"] == "closed"
    assert ticket["attempts"]["A1"]["disposition"] == nil

    # "never enter developer retry": the developer's allowance is untouched.
    assert ticket["infrastructure"]["ordinals"]["reviewer"] == 1
    assert ticket["infrastructure"]["ordinals"]["developer"] == 0

    # "At the limit, ticket becomes `blocked(reviewer_launch_infrastructure)` with
    # `resume_phase: awaiting_review`; the same attempt/candidate remain resumable."
    #
    # This clause was deferred to subcommit 2 on the argument that reaching it would mean
    # widening ticket_parked and re-conflating R4's PM park row with R4a's infrastructure
    # block. The third review pointed out the deferral was inconsistent: the developer's
    # identical clause was being driven through ticket_parked already, working only because
    # a developer non-start happens to land in `queued`. That is a phase coincidence, not a
    # principle. `ticket_blocked` is the row's own event, so all three at-limit clauses now
    # drive and none of them borrows the park.
    {blocked, _} =
      drive({state, 50}, [
        {"ticket_blocked", "T1",
         %{
           "ticket_id" => "T1",
           "reason" => "reviewer_launch_infrastructure",
           "resume_phase" => "awaiting_review"
         }}
      ])

    at_limit = blocked["tickets"]["T1"]
    assert at_limit["phase"] == "blocked"
    assert at_limit["reason"] == "reviewer_launch_infrastructure"
    assert at_limit["resume_phase"] == "awaiting_review"
    # "the same attempt/candidate remain resumable"
    assert at_limit["active_attempt_id"] == "A1"
    assert at_limit["attempts"]["A1"]["candidate_id"] == "cand-1"
    assert at_limit["attempts"]["A1"]["checks"]["C1"]["status"] == "passed"
    :driven
  end

  defp scenario(:nonstart_worker) do
    {state, _} =
      drive(checking(), [
        {"check_planned", "T1",
         %{
           "ticket_id" => "T1",
           "attempt_id" => "A1",
           "check_id" => "C1",
           "authority" => authority("K1", "check")
         }},
        {"check_settled", "T1",
         %{
           "ticket_id" => "T1",
           "attempt_id" => "A1",
           "check_id" => "C1",
           "execution_id" => "K1",
           "settlement" => settlement()
         }}
      ])

    ticket = state["tickets"]["T1"]
    # "Preserve its candidate/deployment phase and verified inputs; apply that phase's
    # existing infrastructure retry/block row ... infer no successful check receipt."
    assert ticket["attempts"]["A1"]["phase"] == "checking"
    assert ticket["attempts"]["A1"]["candidate_id"] == "cand-1"
    assert ticket["attempts"]["A1"]["executions"]["K1"]["lifecycle"] == "closed"
    refute Map.has_key?(ticket["attempts"]["A1"]["checks"], "C1")

    # "consumes its finite role-specific infrastructure allowance".
    assert ticket["infrastructure"]["ordinals"]["check"] == 1
    assert ticket["infrastructure"]["ordinals"]["developer"] == 0
    :driven
  end

  defp scenario(:nonstart_pm) do
    {state, _} =
      drive({State.new(), 0}, [
        {"objective_created", "OBJ1", %{"objective_id" => "OBJ1", "planning_owner_id" => "pm-1"}},
        {"pm_launch_planned", "OBJ1",
         %{
           "objective_id" => "OBJ1",
           "planning_owner_id" => "pm-1",
           "authority" => authority("PM1", "pm")
         }},
        {"pm_launch_settled", "OBJ1", %{"objective_id" => "OBJ1", "settlement" => settlement()}}
      ])

    objective = state["objectives"]["OBJ1"]
    # "Keep the same objective/spec-planning owner; infer no proposal. ... Admit no ticket."
    assert objective["planning_owner_id"] == "pm-1"
    assert objective["proposals"] == %{}
    assert state["tickets"] == %{}
    assert objective["infrastructure"]["ordinals"]["pm"] == 1
    :driven
  end

  defp scenario(_id), do: :no_scenario

  # ── Fixtures ───────────────────────────────────────────────────────────────────────

  defp nonstart do
    drive(developing(), [
      {"launch_settled", "T1",
       %{
         "ticket_id" => "T1",
         "attempt_id" => "A1",
         "execution_id" => "X1",
         "settlement" => settlement()
       }}
    ])
  end

  defp admitted do
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
    drive(admitted(), [
      {"launch_planned", "T1",
       %{
         "ticket_id" => "T1",
         "attempt_id" => "A1",
         "authority" => authority("X1", "developer")
       }}
    ])
  end

  defp frozen do
    drive(developing(), [
      {"artifact_frozen", "T1",
       %{
         "ticket_id" => "T1",
         "attempt_id" => "A1",
         "candidate_id" => "cand-1",
         "observation_id" => "obs-1",
         "sealed_generation" => "gen-1"
       }}
    ])
  end

  defp checking do
    drive(frozen(), [
      {"stream_sealed", "T1",
       %{
         "ticket_id" => "T1",
         "attempt_id" => "A1",
         "execution_id" => "X1",
         "last_accepted_sequence" => 7
       }},
      {"developer_closed", "T1",
       %{"ticket_id" => "T1", "attempt_id" => "A1", "execution_id" => "X1"}},
      {"checks_started", "T1",
       %{"ticket_id" => "T1", "attempt_id" => "A1", "policy_empty" => false}}
    ])
  end

  defp reviewing do
    drive(checking(), [
      {"check_planned", "T1",
       %{
         "ticket_id" => "T1",
         "attempt_id" => "A1",
         "check_id" => "C1",
         "authority" => authority("K1", "check")
       }},
      {"check_recorded", "T1",
       %{
         "ticket_id" => "T1",
         "attempt_id" => "A1",
         "check_id" => "C1",
         "status" => "passed",
         "reason_code" => nil
       }},
      {"review_planned", "T1",
       %{
         "ticket_id" => "T1",
         "attempt_id" => "A1",
         "authority" => authority("R1", "reviewer")
       }}
    ])
  end

  defp verdict(value) do
    drive(reviewing(), [
      {"stream_sealed", "T1",
       %{
         "ticket_id" => "T1",
         "attempt_id" => "A1",
         "execution_id" => "R1",
         "last_accepted_sequence" => 12
       }},
      {"review_recorded", "T1",
       %{
         "ticket_id" => "T1",
         "attempt_id" => "A1",
         "candidate_id" => "cand-1",
         "verdict" => value
       }}
    ])
  end

  defp ready_to_integrate do
    drive(verdict("approved"), [
      {"reviewer_closed", "T1",
       %{"ticket_id" => "T1", "attempt_id" => "A1", "execution_id" => "R1"}}
    ])
  end

  defp integrating do
    drive(ready_to_integrate(), [
      {"worker_closed", "T1",
       %{"ticket_id" => "T1", "attempt_id" => "A1", "execution_id" => "K1"}},
      {"integration_planned", "T1",
       %{
         "ticket_id" => "T1",
         "attempt_id" => "A1",
         "authority" => authority("I1", "integration")
       }}
    ])
  end

  # ── Builders ───────────────────────────────────────────────────────────────────────

  defp event(type, entity_id, revision, sequence, payload) do
    {:ok, kind} = Event.entity_kind(type)

    %{
      "schema_version" => 1,
      "event_id" => "evt-#{type}-#{sequence}",
      "type" => type,
      "sequence" => sequence,
      "entity_kind" => kind,
      "entity_id" => entity_id,
      "entity_revision" => revision,
      "payload" => payload
    }
  end

  defp authority(execution_id, role) do
    %{
      "schema_version" => 1,
      "effect_id" => "eff-#{execution_id}",
      "role" => role,
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

  defp settlement, do: %{"schema_version" => 1}

  defp drive({state, sequence}, specs) do
    Enum.reduce(specs, {state, sequence}, fn {type, entity_id, payload}, {state, sequence} ->
      sequence = sequence + 1
      built = event(type, entity_id, revision_of(state, type, entity_id), sequence, payload)

      case Harness.apply(state, built) do
        {:ok, next} ->
          assert State.well_formed?(next), "#{type} produced a state its own validator rejects"
          {next, sequence}

        {:error, reason} ->
          flunk("#{type} rejected as #{inspect(reason)}")
      end
    end)
  end

  defp revision_of(state, type, entity_id) do
    {:ok, kind} = Event.entity_kind(type)

    case kind do
      "control" -> state["control"]["revision"]
      "objective" -> get_in(state, ["objectives", entity_id, "revision"]) || 0
      "ticket" -> get_in(state, ["tickets", entity_id, "revision"]) || 0
    end
  end
end
