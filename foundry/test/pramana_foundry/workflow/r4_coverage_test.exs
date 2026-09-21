Code.require_file("../../support/r4_rows.ex", __DIR__)

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

  alias PramanaFoundry.Test.R4Rows
  alias PramanaFoundry.Workflow.Kernel, as: WorkflowKernel
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
    nonstart_reviewer:
      ~S|below-limit return is driven; "At the limit, ticket becomes `blocked(reviewer_launch_infrastructure)`" needs the R4a limit product, blocker B3 in subcommit 2|,
    # Re-keyed: this entry quoted "or blocked(check_infrastructure)/exhausted", which is
    # `check_infrastructure_failed`'s outcome text, not this row's. The row it named had no
    # entry at all, so its clause was both undriven and unrecorded. A quoted clause that
    # belongs to a different row is worse than none: it reads as coverage of a row nobody
    # covered. The test below now checks every @partial quote against its own row.
    nonstart_worker:
      ~S|preserve-phase retry is driven; "apply that phase's existing infrastructure retry/block row" needs the R4a limit product|,
    check_infrastructure_failed:
      ~S|"pending same phase" is driven; "or blocked(check_infrastructure)/exhausted" needs the same limit product|,
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

  # The clauses each scenario asserts, quoted from the contract's own outcome cell. A test
  # checks every one of these is still a substring of `R4Rows.outcome(id)`, which is what
  # makes the outcome side of this harness drift-proof rather than a hand transcription
  # nothing checks.
  @clauses %{
    objective_steering: ["PM proposal is evidence, not authority"],
    admission: ["queued or blocked with reason"],
    amend_or_park: ["New future spec revision or explicit blocked state"],
    launch: ["create its launch intent and enter developing"],
    freeze_success: [
      "Attempt candidate_frozen; ticket awaiting_review",
      "seal productive capability/deadline generation"
    ],
    freeze_failure: ["blocked(freeze_failure) when unavailable", "never a frozen result"],
    developer_exit_after_freeze: [
      "Cleanup observation only; preserve frozen candidate",
      "No new developer and no attempt failure"
    ],
    no_valid_candidate: ["Attempt terminal failed/timed_out"],
    blocked_result: [
      "Terminal blocked attempt, blocked ticket; close developer, no review",
      "Resume/rescope requires explicit command and fresh attempt"
    ],
    malformed_submission: [
      "Durable rejected submission, charge one validation action",
      "further submission allowed only while stream open",
      "exhaustion closes execution and exhausts ticket"
    ],
    checks_start: ["checking attempt, awaiting_review ticket", "retaining immutable candidate"],
    checks_passed: ["awaiting_review attempt"],
    check_assertion_failed: [
      "Terminal needs_correction attempt",
      "failed candidate never goes to approval",
      "queue fresh developer after all check workers close"
    ],
    check_infrastructure_failed: [
      "Preserve candidate, bounded new check-run reservation after cleanup",
      "pending same phase",
      "Unknown check retains lease and blocks retry"
    ],
    review_start: [
      "reviewing attempt/ticket, independent reviewer launch with its own reservation"
    ],
    verdict_approved: ["after verified close ready_to_integrate"],
    verdict_correction: [
      "Terminal needs_correction attempt",
      "close/seal reviewer, then queued fresh developer"
    ],
    verdict_rejected: ["Terminal rejected attempt/ticket"],
    reviewer_crash: [
      "Preserve candidate, close reviewer then bounded new reviewer execution",
      "developer ledger untouched"
    ],
    integration_start: ["integrating ticket/attempt"],
    base_moved: ["Terminal superseded_base attempt"],
    integration_success: [
      "integrated ticket; terminal integrated attempt",
      "Exit notifications cannot overwrite this"
    ],
    integration_failure: ["or blocked(integration_failure)"],
    resume: ["return to stored resume_phase"],
    reset: [
      "Keep old attempt terminal",
      "queue a fresh developer attempt using retained evidence as context"
    ],
    terminal_rejection: ["Reject transition; preserve terminal facts"],
    cancel_requested: ["hold phase/evidence while issued effects reconcile"],
    cancel_finalized: [
      "If no integration occurred: cancelled ticket and active attempt terminal cancelled",
      "If integration occurred: integrated and cancel_finalized(after_integration)"
    ],
    nonstart_developer: [
      "Keep the **same nonterminal attempt**",
      "return ticket `developing → queued` with `resume_phase: developing` and reason `developer_launch_non_started`",
      "Below the infrastructure limit, queue a bounded developer retry"
    ],
    nonstart_reviewer: [
      "Keep attempt and ticket `awaiting_review`",
      "Close only the failed reviewer execution; never enter developer retry or correction"
    ],
    nonstart_pm: [
      "Keep the same objective/spec-planning owner; infer no proposal",
      "Admit no ticket and create no objective allocation"
    ],
    nonstart_worker: [
      "Preserve its candidate/deployment phase and verified inputs",
      "consumes its finite role-specific infrastructure allowance",
      "infer no successful check/build/ref/release receipt"
    ]
  }

  # Every clause of every outcome cell that no scenario asserts.
  #
  # `@clauses` checks that what a scenario cites still exists in the contract. This is the
  # converse, and it is the one that was missing: nothing checked whether the contract said
  # things no scenario tested. The third review found that gap by reading - uncited clauses
  # in `integration_failure`, `freeze_failure`, `admission` and `checks_passed` - which is
  # exactly the work a list like this does mechanically.
  #
  # 54 clauses are asserted and 59 are not, so the coverage suite currently tests a little
  # under half of what R4 and R4a say. That is a fair statement of where this subcommit is,
  # and it is the first time the number has been knowable. Entries leave this list only by
  # being asserted; a clause appearing here that is not recorded fails the test, so a
  # contract edit cannot quietly add an untested requirement.
  #
  # Many of these belong to later subcommits by construction - allocation, budgets, leases
  # and drain are protected policy this kernel may not restate - and those will move to
  # @partial as their rows gain the mechanism. They are listed rather than excused because
  # "a later subcommit owns it" is a claim, and claims in this repair have needed checking.
  @uncited %{
    admission: [
      "Common admission validates full assignment/policy/budget allocation",
      "malformed spec rejected"
    ],
    amend_or_park: [
      "active assignments never edited",
      "amendment does not reset budgets"
    ],
    base_moved: [
      "fresh bounded rebase developer plus renewed checks/review",
      "blocked under drain or budget exhaustion"
    ],
    blocked_result: [
      "close developer, no review."
    ],
    cancel_finalized: [
      "already terminal dispositions retained.",
      "suppress deployment"
    ],
    cancel_requested: [
      "Set orthogonal control, cancel pending/unissued effects, request owned interrupts"
    ],
    checks_passed: [
      "queue independent reviewer",
      "checks with explicit policy-empty set follow same guarded transition"
    ],
    developer_exit_after_freeze: [
      "preserve frozen candidate."
    ],
    freeze_failure: [
      "Retain submitted bytes",
      "bounded starts.check retry after owned worker closure",
      "unknown preserves lease."
    ],
    freeze_success: [
      "kernel requests developer close through broker immediately"
    ],
    integration_failure: [
      "Same phase with bounded integration-effect retry after old issuer termination",
      "Conflict uses moved-base row",
      "unknown blocks reconciliation"
    ],
    integration_start: [
      "root integration intent, then R1 claim/issue"
    ],
    integration_success: [
      "deployment is separate."
    ],
    launch: [
      "Create a fresh attempt unless R4a retained a resumable developer attempt",
      "Pre-intent denial remains queued and consumes no start unit or infrastructure ordinal"
    ],
    no_valid_candidate: [
      "after cleanup queue fresh bounded attempt or exhaust",
      "normal exit alone is not success"
    ],
    nonstart_developer: [
      "Release launch resources.",
      "Release its checkout/conflict lease only after proving the checkout was never exposed or mutated, then reacquire/revalidate it before retry",
      "otherwise retain the lease and block affected work.",
      "At the limit, ticket becomes `blocked(developer_launch_infrastructure)` while the attempt remains active and resumable.",
      "Exhaustion of current developer allocation instead makes the attempt terminal `exhausted` and ticket `exhausted`"
    ],
    nonstart_pm: [
      "infer no proposal.",
      "Release launch-only resources.",
      "Below the PM limit, return to its PM queue",
      "at the limit or without current allocation, block as `pm_launch_infrastructure` or `pm_budget`."
    ],
    nonstart_reviewer: [
      "never enter developer retry or correction.",
      "Release reviewer launch resources",
      "retain candidate custody and candidate/check leases.",
      "Below the limit, return to the durable reviewer queue.",
      "At the limit, ticket becomes `blocked(reviewer_launch_infrastructure)` with `resume_phase: awaiting_review`",
      "the same attempt/candidate remain resumable.",
      "Missing current reviewer allocation yields `blocked(reviewer_budget)` or `exhausted` under protected policy, without discarding or approving the candidate"
    ],
    nonstart_worker: [
      "apply that phase's existing infrastructure retry/block row.",
      "Release only proved-unused launch resources."
    ],
    objective_steering: [
      "Durable objective and bounded PM reservation"
    ],
    reset: [
      "block if that role lacks allocation",
      "never reset prior consumption"
    ],
    resume: [
      "Revalidate spec/control/policy and existing allocation",
      "fresh attempt only if prior attempt terminal.",
      "Partial/rescope and explicit operator blocks require steering, not automatic unblocking"
    ],
    review_start: [
      "R4a returns a proved non-start to this same candidate/role queue"
    ],
    reviewer_crash: [
      "exhaust if unavailable"
    ],
    terminal_rejection: [
      "preserve terminal facts.",
      "New work requires explicit admission linked to predecessor, with parent-funded allocation"
    ],
    verdict_approved: [
      "Close/seal reviewer",
      "no Git success inferred"
    ],
    verdict_correction: [
      "never re-prompt old developer"
    ],
    verdict_rejected: [
      "cleanup pending separately",
      "later work needs explicitly admitted revision"
    ]
  }

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

    # The from-cell side of this harness was drift-proof and the outcome side was not:
    # `R4Rows.outcome/1` existed and was called nowhere, so editing a contract outcome cell
    # left every test green while the scenarios went on asserting the old outcome. Each
    # scenario's assertions are a hand transcription of that cell, which is the exact
    # translation step where the first two corrections failed.
    #
    # Citing the clause does not prove the scenario asserts it - nothing short of the
    # assertion itself can - but it does pin the transcription to the contract's words, so
    # a reworded or deleted clause fails here instead of silently leaving a scenario
    # asserting something the contract no longer says.
    test "every clause a scenario claims to assert is still in the contract's outcome cell" do
      for {id, clauses} <- @clauses do
        outcome = R4Rows.outcome(id)

        assert is_binary(outcome), "#{id} matches no contract row, so its clauses are unanchored"

        for clause <- clauses do
          assert String.contains?(outcome, clause),
                 "#{id} cites a clause the contract's outcome cell no longer contains:\n" <>
                   "  cited:   #{inspect(clause)}\n" <>
                   "  outcome: #{inspect(outcome)}"
        end
      end
    end

    # A @partial entry quotes the clause it cannot yet express. That quote must come from
    # its own row's outcome cell - one entry quoted another row's text, which read as
    # coverage of a row nothing covered and left the real row unrecorded.
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

    test "every row with a scenario cites at least one clause of its outcome" do
      uncited = Enum.reject(R4Rows.ids(), &Map.has_key?(@clauses, &1))

      assert uncited == [],
             "rows whose scenario asserts nothing traceable to the contract: #{inspect(uncited)}"
    end

    test "no clause of any outcome cell is silently untested" do
      fragments = fn text ->
        text
        |> String.split(~r/;|(?<=\.)\s+/)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == "" or String.length(&1) < 12))
      end

      cited = @clauses |> Map.values() |> List.flatten()

      uncited =
        for id <- R4Rows.ids(),
            fragment <- fragments.(R4Rows.outcome(id)),
            not Enum.any?(cited, fn c ->
              String.contains?(fragment, c) or String.contains?(c, fragment)
            end),
            do: {id, fragment}

      recorded =
        for {id, fs} <- @uncited, f <- fs, do: {id, f}

      surprising = Enum.sort(uncited) -- Enum.sort(recorded)
      resolved = Enum.sort(recorded) -- Enum.sort(uncited)

      assert surprising == [],
             "contract clauses nothing asserts and nothing records:\n" <>
               Enum.map_join(surprising, "\n", fn {id, f} -> "  #{id}: #{inspect(f)}" end)

      assert resolved == [],
             "clauses now asserted but still listed as uncited - shrink @uncited:\n" <>
               Enum.map_join(resolved, "\n", fn {id, f} -> "  #{id}: #{inspect(f)}" end)
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

    assert {:error, :wrong_attempt_phase} = WorkflowKernel.apply(frozen_state, forged),
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

    assert {:error, :exit_not_verified} = WorkflowKernel.apply(sealed_only, forged)

    # "after cleanup queue fresh bounded attempt" - the fresh attempt waits for cleanup.
    {settled, sequence} = {ticket, sequence} |> then(fn _ -> {state, 40} end)

    open_worker =
      event("launch_planned", "T1", settled["tickets"]["T1"]["revision"], sequence + 1, %{
        "ticket_id" => "T1",
        "attempt_id" => "A2",
        "authority" => authority("X2", "developer")
      })

    assert {:ok, _} = WorkflowKernel.apply(settled, open_worker),
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

    assert {:error, :no_blocked_result} = WorkflowKernel.apply(fresh, forged)
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

    assert {:error, :submission_stream_sealed} = WorkflowKernel.apply(sealed, forged)

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

    assert {:error, _} = WorkflowKernel.apply(failed, forged)
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

    assert {:error, :no_correction_evidence} = WorkflowKernel.apply(state, forged),
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

    assert {:error, :check_already_exists} = WorkflowKernel.apply(failed, forged)

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

    assert {:error, :check_already_exists} = WorkflowKernel.apply(unknown, forged)
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

      assert {:error, :ref_receipt_recorded} = WorkflowKernel.apply(before_settle, forged),
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

    assert {:error, :ticket_terminal} = WorkflowKernel.apply(state, forged)
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

    assert {:error, :wrong_execution_role} = WorkflowKernel.apply(state, forged)

    # "Below the infrastructure limit, queue a bounded developer retry" - and the retry has
    # to be launchable from where a resume actually puts the ticket. R4a stores
    # resume_phase: developing, so resuming lands in `developing` holding the retained
    # attempt whose only developer execution is the closed non-start.
    {resumed, _} =
      drive(nonstart(), [
        {"ticket_parked", "T1",
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

    assert {:error, :developer_already_running} = WorkflowKernel.apply(live, forged)

    # R4's freeze row is "developing; success artifact validates and freezes" - a developer
    # has to have been running to produce one. A ticket resumed to developing holds only
    # the closed non-start, so without this guard it could freeze a candidate for a
    # developer that never ran.
    {parked, sequence} =
      drive(nonstart(), [
        {"ticket_parked", "T1",
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

    assert {:error, :no_running_developer} = WorkflowKernel.apply(parked, forged)
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

      case WorkflowKernel.apply(state, built) do
        {:ok, next} ->
          assert State.valid?(next), "#{type} produced a state its own validator rejects"
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
