defmodule PramanaFoundry.Workflow.KernelTest do
  @moduledoc """
  Subcommit 1 of the FR-08B kernel correction: the pure state and event contract.

  The first describe block reproduces the counterexamples of the independent pure-kernel
  review (`docs/fr-08/fr08b-pure-kernel-review.md`, candidate `a00decc`) and asserts the
  corrected behaviour, so each stays a regression control rather than a one-time argument.
  """
  use ExUnit.Case, async: true

  alias PramanaFoundry.Test.Harness
  alias PramanaFoundry.DurableStore.RecordCodec
  alias PramanaFoundry.Workflow.Kernel.{Event, State}

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

  defp authority(execution_id), do: authority(execution_id, "developer")

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

  # Applies events in order, asserting each one is accepted. Sequence and entity revision
  # are tracked here so a test states its lifecycle rather than its bookkeeping. The
  # starting sequence is threaded explicitly, because durable sequence is strictly
  # increasing across the whole log: a helper that restarted it at zero would be building
  # histories the reducer is right to reject.
  defp drive({state, sequence}, specs) do
    Enum.reduce(specs, {state, sequence}, fn {type, entity_id, payload}, {state, sequence} ->
      sequence = sequence + 1
      revision = revision_of(state, type, entity_id)
      built = event(type, entity_id, revision, sequence, payload)

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
      "ticket" -> get_in(state, ["tickets", entity_id, "revision"]) || 0
      "objective" -> get_in(state, ["objectives", entity_id, "revision"]) || 0
    end
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

  # The step before `checking`: candidate frozen, developer closed, checks not yet
  # started. Split out because `checks_started`'s own guards can only be aimed at the
  # state that sits directly in front of it.
  defp candidate_frozen do
    drive(admitted(), [
      {"launch_planned", "T1",
       %{"ticket_id" => "T1", "attempt_id" => "A1", "authority" => authority("X1")}},
      {"artifact_frozen", "T1",
       %{
         "ticket_id" => "T1",
         "attempt_id" => "A1",
         "candidate_id" => "cand-1",
         "observation_id" => "obs-1",
         "sealed_generation" => "gen-1"
       }},
      {"stream_sealed", "T1",
       %{
         "ticket_id" => "T1",
         "attempt_id" => "A1",
         "execution_id" => "X1",
         "last_accepted_sequence" => 7
       }},
      {"developer_closed", "T1",
       %{"ticket_id" => "T1", "attempt_id" => "A1", "execution_id" => "X1"}}
    ])
  end

  defp checking do
    drive(candidate_frozen(), [
      {"checks_started", "T1",
       %{"ticket_id" => "T1", "attempt_id" => "A1", "policy_empty" => false}}
    ])
  end

  # ── Builders for the subcommit 1 review's counterexamples ─────────────────────────

  defp developing do
    drive(admitted(), [
      {"launch_planned", "T1",
       %{"ticket_id" => "T1", "attempt_id" => "A1", "authority" => authority("X1")}}
    ])
  end

  # A check driven to the given terminal status, so relabelling it can be attempted.
  defp checked(status) do
    drive(checking(), [
      {"check_planned", "T1",
       %{
         "ticket_id" => "T1",
         "attempt_id" => "A1",
         "check_id" => "C1",
         "authority" => authority("K1")
       }},
      {"check_recorded", "T1",
       %{
         "ticket_id" => "T1",
         "attempt_id" => "A1",
         "check_id" => "C1",
         "status" => status,
         "reason_code" => "assertion_failed"
       }}
    ])
  end

  # R4: "reviewing; correction verdict | Terminal needs_correction attempt; close/seal
  # reviewer, **then** queued fresh developer". The attempt settles first, so the reviewer
  # execution must remain closable afterwards.
  defp correction_settled do
    drive(reviewing(), [
      {"stream_sealed", "T1",
       %{
         "ticket_id" => "T1",
         "attempt_id" => "A1",
         "execution_id" => "R1",
         "last_accepted_sequence" => 11
       }},
      {"review_recorded", "T1",
       %{
         "ticket_id" => "T1",
         "attempt_id" => "A1",
         "candidate_id" => "cand-1",
         "verdict" => "correction"
       }},
      {"attempt_settled", "T1",
       %{
         "ticket_id" => "T1",
         "attempt_id" => "A1",
         "disposition" => "needs_correction",
         "reason_code" => nil,
         "settlement" => %{"schema_version" => 1}
       }}
    ])
  end

  # Everything R4's integration row requires before an issuer is planned: approved,
  # reviewer and check workers closed, no integration execution yet.
  defp ready_to_integrate do
    drive(reviewing(), [
      {"stream_sealed", "T1",
       %{
         "ticket_id" => "T1",
         "attempt_id" => "A1",
         "execution_id" => "R1",
         "last_accepted_sequence" => 11
       }},
      {"review_recorded", "T1",
       %{
         "ticket_id" => "T1",
         "attempt_id" => "A1",
         "candidate_id" => "cand-1",
         "verdict" => "approved"
       }},
      {"reviewer_closed", "T1",
       %{"ticket_id" => "T1", "attempt_id" => "A1", "execution_id" => "R1"}},
      {"worker_closed", "T1",
       %{"ticket_id" => "T1", "attempt_id" => "A1", "execution_id" => "K1"}}
    ])
  end

  defp approved_and_closed do
    drive(ready_to_integrate(), [
      {"integration_planned", "T1",
       %{
         "ticket_id" => "T1",
         "attempt_id" => "A1",
         "authority" => authority("I1", "integration")
       }}
    ])
  end

  defp integrating_with_receipt do
    drive(approved_and_closed(), [
      {"integration_recorded", "T1",
       %{
         "ticket_id" => "T1",
         "attempt_id" => "A1",
         "execution_id" => "I1",
         "outcome" => "ref_created",
         "ref_receipt_id" => "ref-1"
       }}
    ])
  end

  # The same state, except the check worker is `unknown` rather than closed.
  defp integrating_with_unknown_worker do
    drive(
      drive(reviewing(), [
        {"stream_sealed", "T1",
         %{
           "ticket_id" => "T1",
           "attempt_id" => "A1",
           "execution_id" => "R1",
           "last_accepted_sequence" => 11
         }},
        {"review_recorded", "T1",
         %{
           "ticket_id" => "T1",
           "attempt_id" => "A1",
           "candidate_id" => "cand-1",
           "verdict" => "approved"
         }},
        {"reviewer_closed", "T1",
         %{"ticket_id" => "T1", "attempt_id" => "A1", "execution_id" => "R1"}},
        {"execution_observed", "T1",
         %{
           "ticket_id" => "T1",
           "attempt_id" => "A1",
           "execution_id" => "K1",
           "observation" => "unknown",
           "lifecycle" => "unknown"
         }},
        {"integration_planned", "T1",
         %{
           "ticket_id" => "T1",
           "attempt_id" => "A1",
           "authority" => authority("I1", "integration")
         }}
      ]),
      []
    )
  end

  # A reviewing attempt that also owns a check execution, so a settlement can be aimed at
  # the wrong one.
  defp reviewing_with_check_execution do
    drive(checking(), [
      {"check_planned", "T1",
       %{
         "ticket_id" => "T1",
         "attempt_id" => "A1",
         "check_id" => "C9",
         "authority" => authority("K9", "check")
       }},
      {"check_recorded", "T1",
       %{
         "ticket_id" => "T1",
         "attempt_id" => "A1",
         "check_id" => "C9",
         "status" => "passed",
         "reason_code" => nil
       }},
      {"review_planned", "T1",
       %{"ticket_id" => "T1", "attempt_id" => "A1", "authority" => authority("R1", "reviewer")}}
    ])
  end

  describe "the lifecycle vocabulary stays disjoint from the durable one" do
    # The codec enforces disjointness at compile time for the names it already holds, but
    # nothing checked the kernel's 36 against it, so a collision would only surface when
    # subcommit 2 extended the codec and the build broke. `ticket_resumed` was exactly that:
    # recorded as a required rename in the vocabulary design, then lost when the FR-08B
    # enumeration was written. This is the assertion whose absence let that happen.
    test "no kernel event type reuses a legacy durable event type" do
      collisions =
        MapSet.intersection(
          MapSet.new(Event.types()),
          MapSet.new(RecordCodec.legacy_event_types())
        )

      assert MapSet.size(collisions) == 0,
             "kernel types collide with the immutable legacy vocabulary: " <>
               "#{inspect(Enum.sort(collisions))}. Legacy names may never be reused; " <>
               "rename the lifecycle event."
    end

    # The other half: every name the codec already holds must still be one the kernel
    # declares, or the codec would accept a lifecycle event the reducer cannot apply.
    test "every durable lifecycle type is a kernel event type" do
      orphans =
        MapSet.difference(
          MapSet.new(RecordCodec.lifecycle_event_types()),
          MapSet.new(Event.types())
        )

      assert MapSet.size(orphans) == 0,
             "durable lifecycle types the kernel cannot apply: #{inspect(Enum.sort(orphans))}"
    end
  end

  describe "guards the mutation sweep found untested" do
    # Eleven of sixty-seven guard call sites survived neutralisation: removing them left
    # all 105 tests green. Two others survived because they cannot fire at all and are
    # recorded in the guard-reachability suite; these eleven can fire and nothing tripped
    # them. The suite had been reporting confidence it had not earned.
    #
    # The first entry is the one that stings: verdict write-once was a correction from the
    # *first* independent review, written up as fixed, with nothing testing it.

    test "a verdict is write-once" do
      {state, sequence} = verdict_recorded("approved")

      forged =
        event("review_recorded", "T1", state["tickets"]["T1"]["revision"], sequence + 1, %{
          "ticket_id" => "T1",
          "attempt_id" => "A1",
          "candidate_id" => "cand-1",
          "verdict" => "rejected"
        })

      assert {:error, :verdict_already_recorded} = Harness.apply(state, forged)
    end

    test "a verdict outside the contract's vocabulary is refused" do
      {state, sequence} = sealed_reviewer()

      forged =
        event("review_recorded", "T1", state["tickets"]["T1"]["revision"], sequence + 1, %{
          "ticket_id" => "T1",
          "attempt_id" => "A1",
          "candidate_id" => "cand-1",
          "verdict" => "looks_fine"
        })

      assert {:error, :invalid_verdict} = Harness.apply(state, forged)
    end

    # R4: a `closed` lifecycle "requires verified process/session termination or proved
    # non-start", so closure has its own guarded events and an observation may never
    # produce it. This is B2's finding stated as a property of the vocabulary.
    test "an observation cannot close an execution" do
      {state, sequence} = developing()

      forged =
        event("execution_observed", "T1", state["tickets"]["T1"]["revision"], sequence + 1, %{
          "ticket_id" => "T1",
          "attempt_id" => "A1",
          "execution_id" => "X1",
          "observation" => "exited",
          "lifecycle" => "closed"
        })

      assert {:error, :invalid_execution_lifecycle} = Harness.apply(state, forged)
    end

    test "worker closure is refused for a non-worker execution" do
      {state, sequence} = developing()

      forged =
        event("worker_closed", "T1", state["tickets"]["T1"]["revision"], sequence + 1, %{
          "ticket_id" => "T1",
          "attempt_id" => "A1",
          "execution_id" => "X1"
        })

      assert {:error, :wrong_execution_role} = Harness.apply(state, forged)
    end

    test "closure addressed to an attempt that does not exist is refused" do
      {state, sequence} = developing()

      forged =
        event("developer_closed", "T1", state["tickets"]["T1"]["revision"], sequence + 1, %{
          "ticket_id" => "T1",
          "attempt_id" => "A-ghost",
          "execution_id" => "X1"
        })

      assert {:error, :unknown_attempt} = Harness.apply(state, forged)
    end

    test "closure naming an execution the attempt does not own is refused" do
      {state, sequence} = developing()

      forged =
        event("developer_closed", "T1", state["tickets"]["T1"]["revision"], sequence + 1, %{
          "ticket_id" => "T1",
          "attempt_id" => "A1",
          "execution_id" => "X-ghost"
        })

      assert {:error, :unknown_execution} = Harness.apply(state, forged)
    end

    # R4a settles a reviewer non-start against the attempt that owns the review. A
    # settlement naming another attempt is a forged reference.
    test "a review settlement naming another attempt is refused" do
      {state, sequence} = reviewing()

      forged =
        event("review_settled", "T1", state["tickets"]["T1"]["revision"], sequence + 1, %{
          "ticket_id" => "T1",
          "attempt_id" => "A-other",
          "execution_id" => "R1",
          "settlement" => %{"schema_version" => 1}
        })

      assert {:error, :not_the_active_attempt} = Harness.apply(state, forged)
    end

    test "a review settlement is refused unless the ticket is reviewing" do
      {state, sequence} = checking()

      forged =
        event("review_settled", "T1", state["tickets"]["T1"]["revision"], sequence + 1, %{
          "ticket_id" => "T1",
          "attempt_id" => "A1",
          "execution_id" => "R1",
          "settlement" => %{"schema_version" => 1}
        })

      assert {:error, :wrong_source_phase} = Harness.apply(state, forged)
    end

    # R4: "any **open submission phase**; malformed result". A ticket that is neither
    # developing nor reviewing has no open submission to reject.
    test "a submission rejection is refused outside an open submission phase" do
      {state, sequence} = admitted()

      forged =
        event("submission_rejected", "T1", state["tickets"]["T1"]["revision"], sequence + 1, %{
          "ticket_id" => "T1",
          "attempt_id" => "A1",
          "observation_id" => "obs-9",
          "reason" => "malformed"
        })

      assert {:error, :wrong_source_phase} = Harness.apply(state, forged)
    end

    test "a control change outside the stop vocabulary is refused" do
      {state, sequence} = admitted()

      forged =
        event("control_changed", "control", state["control"]["revision"], sequence + 1, %{
          "control" => control_fact(),
          "paused" => false,
          "draining" => false,
          "stop_status" => "halting"
        })

      assert {:error, :invalid_stop_status} = Harness.apply(state, forged)
    end

    test "a control flag that is not a boolean is refused" do
      {state, sequence} = admitted()

      forged =
        event("control_changed", "control", state["control"]["revision"], sequence + 1, %{
          "control" => control_fact(),
          "paused" => "yes",
          "draining" => false,
          "stop_status" => "running"
        })

      assert {:error, :invalid_control_flag} = Harness.apply(state, forged)
    end

    # ── The second sweep, after the assertions were pinned ──────────────────────────
    #
    # Nineteen of sixty-six sites survived the next full sweep, and the count was real:
    # neutralising one by hand left all five suites green. Three causes, and only the
    # third was a guard that cannot fire.
    #
    # The first is why the count had looked smaller than it was. A refusal asserted as
    # `{:error, _}` is satisfied by *any* guard in the `with`, so neutralising the one
    # the test was named for still matched — via whichever guard refused next. Every
    # assertion below names its exact atom, and several of the states had to be rebuilt
    # once pinning showed the scenario was proving a different guard than its name said.
    #
    # The second is guards added late enough that no row scenario reached them. A guard
    # arriving with its correction and without its test is the shape this repair has
    # shipped four times now.
    #
    # The sibling pattern recurs here too: `require_boolean(payload["paused"])` was
    # exercised and `require_boolean(payload["draining"])` directly below it was not,
    # because the one test that sent a non-boolean sent it as `paused` and stopped at the
    # first guard. The same holds for both `require_execution` call sites and all four
    # `require_phase(ticket, ~w(developing))` sites.

    test "a reset is refused unless the ticket is exhausted" do
      {state, sequence} = admitted()

      forged =
        event("ticket_reset", "T1", state["tickets"]["T1"]["revision"], sequence + 1, %{
          "ticket_id" => "T1",
          "generation" => 1
        })

      assert {:error, :wrong_source_phase} = Harness.apply(state, forged)
    end

    # R4a's developer non-start row starts from `developing`. Aimed at a ticket past that
    # phase it must be refused on the phase, not on whatever the execution happens to be:
    # without this guard the settlement reaches `close_execution` and is refused for
    # closing an already-closed execution, which is a different claim entirely.
    test "a launch settlement is refused unless the ticket is developing" do
      {state, sequence} = checking()

      forged =
        event("launch_settled", "T1", state["tickets"]["T1"]["revision"], sequence + 1, %{
          "ticket_id" => "T1",
          "attempt_id" => "A1",
          "execution_id" => "X1",
          "settlement" => %{"schema_version" => 1}
        })

      assert {:error, :wrong_source_phase} = Harness.apply(state, forged)
    end

    # R4 row 9 is "developing; **valid blocked/partial result**". `valid` is a sealed
    # result value, and it belongs to the freeze row; routing it through this one would
    # block a ticket on a successful build.
    test "an artifact block carrying a non-blocked result is refused" do
      {state, sequence} = developing()

      forged =
        event("artifact_blocked", "T1", state["tickets"]["T1"]["revision"], sequence + 1, %{
          "ticket_id" => "T1",
          "attempt_id" => "A1",
          "observation_id" => "obs-2",
          "result" => "valid",
          "reason" => "dependency missing"
        })

      assert {:error, :invalid_blocked_result} = Harness.apply(state, forged)
    end

    test "a freeze failure naming another attempt is refused" do
      {state, sequence} = developing()

      forged =
        event("freeze_failed", "T1", state["tickets"]["T1"]["revision"], sequence + 1, %{
          "ticket_id" => "T1",
          "attempt_id" => "A-other",
          "disposition" => "retry",
          "reason" => "import failed"
        })

      assert {:error, :not_the_active_attempt} = Harness.apply(state, forged)
    end

    test "checks cannot start before the ticket is awaiting review" do
      {state, sequence} = developing()

      forged =
        event("checks_started", "T1", state["tickets"]["T1"]["revision"], sequence + 1, %{
          "ticket_id" => "T1",
          "attempt_id" => "A1",
          "policy_empty" => false
        })

      assert {:error, :wrong_source_phase} = Harness.apply(state, forged)
    end

    # R4: "candidate_frozen; developer closed, check capacity eligible". A second
    # `checks_started` would restart the check phase over an attempt already in it, and
    # `maybe_finish_checks` would then read a half-built check set.
    test "checks cannot start twice on one attempt" do
      {state, sequence} = checking()

      forged =
        event("checks_started", "T1", state["tickets"]["T1"]["revision"], sequence + 1, %{
          "ticket_id" => "T1",
          "attempt_id" => "A1",
          "policy_empty" => false
        })

      assert {:error, :wrong_attempt_phase} = Harness.apply(state, forged)
    end

    # `policy_empty` decides whether an empty check set finishes the phase, so a
    # non-boolean would make `maybe_finish_checks` truthy on any value at all.
    test "a non-boolean empty-policy flag is refused" do
      {state, sequence} = candidate_frozen()

      forged =
        event("checks_started", "T1", state["tickets"]["T1"]["revision"], sequence + 1, %{
          "ticket_id" => "T1",
          "attempt_id" => "A1",
          "policy_empty" => "no"
        })

      assert {:error, :invalid_control_flag} = Harness.apply(state, forged)
    end

    test "a check status outside the contract's vocabulary is refused" do
      {state, sequence} =
        drive(checking(), [
          {"check_planned", "T1",
           %{
             "ticket_id" => "T1",
             "attempt_id" => "A1",
             "check_id" => "C1",
             "authority" => authority("K1", "check")
           }}
        ])

      forged =
        event("check_recorded", "T1", state["tickets"]["T1"]["revision"], sequence + 1, %{
          "ticket_id" => "T1",
          "attempt_id" => "A1",
          "check_id" => "C1",
          "status" => "green",
          "reason_code" => nil
        })

      assert {:error, :invalid_check_status} = Harness.apply(state, forged)
    end

    test "a reviewer closure naming an attempt that does not exist is refused" do
      {state, sequence} = reviewing()

      forged =
        event("reviewer_closed", "T1", state["tickets"]["T1"]["revision"], sequence + 1, %{
          "ticket_id" => "T1",
          "attempt_id" => "A-ghost",
          "execution_id" => "R1"
        })

      assert {:error, :unknown_attempt} = Harness.apply(state, forged)
    end

    test "a reviewer closure naming an execution the attempt does not own is refused" do
      {state, sequence} = reviewing()

      forged =
        event("reviewer_closed", "T1", state["tickets"]["T1"]["revision"], sequence + 1, %{
          "ticket_id" => "T1",
          "attempt_id" => "A1",
          "execution_id" => "X-ghost"
        })

      assert {:error, :unknown_execution} = Harness.apply(state, forged)
    end

    # R4a proves a non-start by closing the execution it names. A settlement naming an
    # execution the attempt never had proves nothing, and without this guard it is
    # refused for the execution's *role* instead — reading as a role mismatch when the
    # execution does not exist at all.
    test "a launch settlement naming an execution the attempt does not own is refused" do
      {state, sequence} = developing()

      forged =
        event("launch_settled", "T1", state["tickets"]["T1"]["revision"], sequence + 1, %{
          "ticket_id" => "T1",
          "attempt_id" => "A1",
          "execution_id" => "X-ghost",
          "settlement" => %{"schema_version" => 1}
        })

      assert {:error, :unknown_execution} = Harness.apply(state, forged)
    end

    # R4: "Same phase with bounded integration-effect retry **after old issuer
    # termination**". A second issuer planned while the first is still open is two
    # concurrent integration effects against one base.
    test "an integration retry is refused while the previous issuer is open" do
      {state, sequence} = approved_and_closed()

      forged =
        event("integration_planned", "T1", state["tickets"]["T1"]["revision"], sequence + 1, %{
          "ticket_id" => "T1",
          "attempt_id" => "A1",
          "authority" => authority("I2", "integration")
        })

      assert {:error, :issuer_not_terminated} = Harness.apply(state, forged)
    end

    test "a settlement disposition outside the contract's vocabulary is refused" do
      {state, sequence} = developing()

      forged =
        event("attempt_settled", "T1", state["tickets"]["T1"]["revision"], sequence + 1, %{
          "ticket_id" => "T1",
          "attempt_id" => "A1",
          "disposition" => "shipped",
          "reason_code" => nil,
          "settlement" => %{"schema_version" => 1}
        })

      assert {:error, :invalid_disposition} = Harness.apply(state, forged)
    end

    # tickets.ex `require_reset_facts`: the bound generation is a non-empty list of
    # reset_fact_v1 facts, one per dimension (FR-08B protected items spec, item 2).
    test "a reset carrying no reset facts, a malformed one, or one dimension twice is refused" do
      {state, sequence} =
        drive(developing(), [
          {"attempt_settled", "T1",
           %{
             "ticket_id" => "T1",
             "attempt_id" => "A1",
             "disposition" => "exhausted",
             "reason_code" => nil,
             "settlement" => %{"schema_version" => 1}
           }}
        ])

      revision = state["tickets"]["T1"]["revision"]

      reset =
        &event("ticket_reset", "T1", revision, sequence + 1, %{
          "ticket_id" => "T1",
          "generation" => &1
        })

      for generation <- [
            nil,
            [],
            %{"schema_version" => 1},
            [Map.delete(reset_fact(), "ledger_id")],
            [reset_fact(), reset_fact()]
          ] do
        assert {:error, :invalid_reset_facts} = Harness.apply(state, reset.(generation)),
               "accepted generation #{inspect(generation)}"
      end

      assert {:ok, _} = Harness.apply(state, reset.([reset_fact()]))
    end

    defp reset_fact,
      do: %{
        "schema_version" => 1,
        "ledger_id" => "ticket-T1",
        "dimension" => "starts.developer",
        "generation" => 1,
        "authorized" => 1
      }

    # kernel.ex's `attempt_settled` `require_active_attempt`. Survived the 2026-09-22
    # coverage-guided sweep: no test sent a settlement naming anything but the active
    # attempt. `require_settlement_source` judges the ACTIVE attempt, so without this guard
    # a disposition valid for A2 is written onto the prior, already-terminal A1 - the
    # retained-evidence custody `prior_attempt_ids` exists for.
    test "a settlement naming a prior attempt is refused; the same event for the active one is not" do
      {state, sequence} =
        drive(developing(), [
          {"attempt_settled", "T1",
           %{
             "ticket_id" => "T1",
             "attempt_id" => "A1",
             "disposition" => "exhausted",
             "reason_code" => nil,
             "settlement" => %{"schema_version" => 1}
           }},
          {"stream_sealed", "T1",
           %{
             "ticket_id" => "T1",
             "attempt_id" => "A1",
             "execution_id" => "X1",
             "last_accepted_sequence" => 7
           }},
          {"developer_closed", "T1",
           %{"ticket_id" => "T1", "attempt_id" => "A1", "execution_id" => "X1"}},
          {"ticket_reset", "T1", %{"ticket_id" => "T1", "generation" => [reset_fact()]}},
          {"launch_planned", "T1",
           %{
             "ticket_id" => "T1",
             "attempt_id" => "A2",
             "authority" => Map.put(authority("X2"), "attempt_id", "A2")
           }}
        ])

      settle = fn attempt_id ->
        event("attempt_settled", "T1", state["tickets"]["T1"]["revision"], sequence + 1, %{
          "ticket_id" => "T1",
          "attempt_id" => attempt_id,
          "disposition" => "exhausted",
          "reason_code" => nil,
          "settlement" => %{"schema_version" => 1}
        })
      end

      assert {:error, :not_the_active_attempt} = Harness.apply(state, settle.("A1"))
      assert {:ok, _} = Harness.apply(state, settle.("A2"))
    end

    # R4: "ready_to_integrate/integrating; accepted base moved **before issuance**". From
    # `developing` no base has been accepted, so there is nothing for a move to supersede
    # — without the guard the attempt terminalises `superseded_base` from a phase the row
    # does not list.
    test "superseded_base is refused from an attempt that never reached integration" do
      {state, sequence} = developing()

      forged =
        event("attempt_settled", "T1", state["tickets"]["T1"]["revision"], sequence + 1, %{
          "ticket_id" => "T1",
          "attempt_id" => "A1",
          "disposition" => "superseded_base",
          "reason_code" => nil,
          "settlement" => %{"schema_version" => 1}
        })

      assert {:error, :wrong_attempt_phase} = Harness.apply(state, forged)
    end

    # The sibling of the `paused` test above. Both flags are orthogonal controls and both
    # are copied into the control entity; only the first had a test.
    test "a non-boolean drain flag is refused" do
      {state, sequence} = admitted()

      forged =
        event("control_changed", "control", state["control"]["revision"], sequence + 1, %{
          "control" => control_fact(),
          "paused" => false,
          "draining" => "no",
          "stop_status" => "running"
        })

      assert {:error, :invalid_control_flag} = Harness.apply(state, forged)
    end
  end

  # ── The subcommit 1 review's counterexamples ───────────────────────────────────────

  describe "subcommit 1 review — terminal states reachable only through their lifecycle" do
    # Finding 1. attempt_settled guarded only the `integrated` disposition, so eight of the
    # nine were reachable from any phase. R4 gives each of them a source row.
    test "a developing attempt cannot settle rejected without a rejected verdict" do
      {state, sequence} = developing()

      forged =
        event("attempt_settled", "T1", state["tickets"]["T1"]["revision"], sequence + 1, %{
          "ticket_id" => "T1",
          "attempt_id" => "A1",
          "disposition" => "rejected",
          "reason_code" => nil,
          "settlement" => %{"schema_version" => 1}
        })

      assert {:error, :no_rejected_verdict} = Harness.apply(state, forged)
    end

    test "an attempt cannot settle cancelled when no cancel was requested" do
      {state, sequence} = developing()

      forged =
        event("attempt_settled", "T1", state["tickets"]["T1"]["revision"], sequence + 1, %{
          "ticket_id" => "T1",
          "attempt_id" => "A1",
          "disposition" => "cancelled",
          "reason_code" => nil,
          "settlement" => %{"schema_version" => 1}
        })

      assert {:error, :cancel_not_requested} = Harness.apply(state, forged)
    end

    # R4: "reviewing; sealed stream no valid verdict and reviewer crash/timeout | Preserve
    # candidate, close reviewer then bounded new reviewer execution". The candidate must
    # survive; before this guard a reviewer timeout terminalised the attempt and threw the
    # frozen candidate away.
    test "a reviewer timeout does not terminalise the attempt" do
      {state, sequence} = reviewing()

      forged =
        event("attempt_settled", "T1", state["tickets"]["T1"]["revision"], sequence + 1, %{
          "ticket_id" => "T1",
          "attempt_id" => "A1",
          "disposition" => "timed_out",
          "reason_code" => "reviewer_timeout",
          "settlement" => %{"schema_version" => 1}
        })

      assert {:error, :wrong_attempt_phase} = Harness.apply(state, forged)
    end

    # Finding 2, and blocker B1's headline counterexample one step removed: three events
    # from an empty state produced an integrated ticket with no attempt at all.
    test "cancellation cannot finalize as after_integration with nothing integrated" do
      {state, sequence} =
        drive(admitted(), [{"cancellation_requested", "T1", %{"ticket_id" => "T1"}}])

      forged =
        event("cancellation_finalized", "T1", state["tickets"]["T1"]["revision"], sequence + 1, %{
          "ticket_id" => "T1",
          "disposition" => "after_integration"
        })

      assert {:error, :no_integration_to_finalize} = Harness.apply(state, forged)
    end

    # Finding 7. The split stopped R4's integration row contradicting itself but left its
    # halves independent, so an attempt that had just created a ref could settle `failed`.
    test "an attempt holding a ref receipt can only settle integrated" do
      {state, sequence} = integrating_with_receipt()

      forged =
        event("attempt_settled", "T1", state["tickets"]["T1"]["revision"], sequence + 1, %{
          "ticket_id" => "T1",
          "attempt_id" => "A1",
          "disposition" => "failed",
          "reason_code" => nil,
          "settlement" => %{"schema_version" => 1}
        })

      assert {:error, :ref_receipt_admits_only_integrated} = Harness.apply(state, forged)
    end
  end

  describe "subcommit 1 review — custody, write-once evidence and closure" do
    # Finding 4. Correction 7 of 202b8e4 made the verdict write-once and left the check
    # receipt writable. Every attempt that reached review in the property suite got there
    # this way.
    test "a settled check cannot be relabelled" do
      {state, sequence} = checked("failed")

      forged =
        event("check_recorded", "T1", state["tickets"]["T1"]["revision"], sequence + 1, %{
          "ticket_id" => "T1",
          "attempt_id" => "A1",
          "check_id" => "C1",
          "status" => "passed",
          "reason_code" => nil
        })

      assert {:error, :check_already_settled} = Harness.apply(state, forged)
    end

    # Finding 3. Executions were addressed through the active-attempt pointer, so every one
    # became unreachable the instant its attempt settled - and R4 orders closure *after*
    # settlement in four rows.
    test "an execution in a settled attempt can still be closed" do
      {state, sequence} = correction_settled()

      closed =
        event("reviewer_closed", "T1", state["tickets"]["T1"]["revision"], sequence + 1, %{
          "ticket_id" => "T1",
          "attempt_id" => "A1",
          "execution_id" => "R1"
        })

      assert {:ok, next} = Harness.apply(state, closed)
      assert State.well_formed?(next)

      assert next["tickets"]["T1"]["attempts"]["A1"]["executions"]["R1"]["lifecycle"] ==
               "closed"
    end

    # Finding 8. R4a: an `unknown` execution "permits no replacement launch until R1
    # reconciliation"; R4: "If cleanup is unknown, block affected work and retain capacity".
    test "an unknown worker execution does not satisfy the integration row" do
      {state, sequence} = integrating_with_unknown_worker()

      forged =
        event("integration_recorded", "T1", state["tickets"]["T1"]["revision"], sequence + 1, %{
          "ticket_id" => "T1",
          "attempt_id" => "A1",
          "execution_id" => "I1",
          "outcome" => "ref_created",
          "ref_receipt_id" => "ref-1"
        })

      assert {:error, :workers_not_closed} = Harness.apply(state, forged)
    end

    # Finding 10. Correction 8 bound reviewer_closed to its reviewer execution and left
    # review_settled unbound, so a settlement could close a check execution and leak the
    # reviewer's.
    test "a review settlement cannot close another role's execution" do
      {state, sequence} = reviewing_with_check_execution()

      forged =
        event("review_settled", "T1", state["tickets"]["T1"]["revision"], sequence + 1, %{
          "ticket_id" => "T1",
          "attempt_id" => "A1",
          "execution_id" => "K9",
          "settlement" => %{"schema_version" => 1}
        })

      assert {:error, :not_the_reviewer_execution} = Harness.apply(state, forged)
    end

    # Finding 9, the confirmed prober circularity. R4's resume row returns a ticket "to
    # stored resume_phase"; `blocked` is not a phase to return to, and accepting it left a
    # ticket blocked with no reason and no target, unresumable forever.
    test "a park cannot promise to resume at blocked" do
      {state, sequence} = admitted()

      forged =
        event("ticket_parked", "T1", state["tickets"]["T1"]["revision"], sequence + 1, %{
          "ticket_id" => "T1",
          "reason" => "dependency",
          "resume_phase" => "blocked"
        })

      assert {:error, :invalid_resume_phase} = Harness.apply(state, forged)
    end
  end

  # ── The reviewed candidate's counterexamples ───────────────────────────────────────

  describe "B1 — apply/2 is a guarded reducer, not a snapshot installer" do
    test "an unknown event type cannot create an integrated ticket from empty state" do
      # The reviewed candidate accepted any nonempty type and merged generic changes, so
      # this exact event produced an integrated ticket with no candidate, checks, review,
      # claim or ref receipt.
      forged =
        event("ticket_admitted", "T1", 0, 1, %{
          "ticket_id" => "T1",
          "objective_id" => nil,
          "spec_revision_id" => "spec-1",
          "spec" => %{},
          "phase" => "integrated",
          "reason" => nil
        })

      assert {:error, :invalid_admission_phase} = Harness.apply(State.new(), forged)

      unknown = %{forged | "type" => "ticket_integrated"}
      assert {:error, :invalid_semantic_event} = Harness.apply(State.new(), unknown)
    end

    test "no event outside the closed vocabulary reaches a merge" do
      for type <- ["", "integrate", "ticket_admitted ", "TICKET_ADMITTED", "__struct__"] do
        forged = event("ticket_admitted", "T1", 0, 1, %{}) |> Map.put("type", type)
        assert {:error, :invalid_semantic_event} = Harness.apply(State.new(), forged)
      end
    end

    test "an integrated ticket is reachable only through its lifecycle" do
      {state, _} = full_lifecycle()
      assert state["tickets"]["T1"]["phase"] == "integrated"

      attempt = state["tickets"]["T1"]["attempts"]["A1"]
      assert attempt["disposition"] == "integrated"
      assert attempt["candidate_id"] == "cand-1"
      assert attempt["review"]["verdict"] == "approved"
      assert attempt["checks"]["C1"]["status"] == "passed"
    end

    test "an older event applied after a newer one is rejected, not installed" do
      {state, sequence} = admitted()

      stale =
        event("ticket_amended", "T1", state["tickets"]["T1"]["revision"], sequence, %{
          "ticket_id" => "T1",
          "spec_revision_id" => "spec-2",
          "spec" => %{}
        })

      assert {:error, :out_of_order_event} = Harness.apply(state, stale)
    end

    test "a stale entity revision is rejected even when the sequence advances" do
      {state, sequence} = admitted()

      stale =
        event("ticket_amended", "T1", 0, sequence + 1, %{
          "ticket_id" => "T1",
          "spec_revision_id" => "spec-2",
          "spec" => %{}
        })

      assert state["tickets"]["T1"]["revision"] == 1
      assert {:error, :stale_entity_revision} = Harness.apply(state, stale)
    end

    test "a redelivery of the event an entity last applied is an idempotent no-op" do
      {state, sequence} = admitted()

      redelivered =
        event("ticket_admitted", "T1", 0, sequence, %{
          "ticket_id" => "T1",
          "objective_id" => nil,
          "spec_revision_id" => "spec-1",
          "spec" => %{},
          "phase" => "queued",
          "reason" => nil
        })

      assert {:ok, ^state} = Harness.apply(state, redelivered)
    end

    test "well_formed?/1 rejects the malformed nested state that made decide/3 raise" do
      # The reviewed candidate's validator checked outer containers and four control
      # fields, so this state passed and then raised inside a source guard.
      assert State.well_formed?(State.new())
      refute State.well_formed?(put_in(State.new(), ["tickets"], %{"T1" => 7}))

      refute State.well_formed?(
               put_in(State.new(), ["tickets"], %{"T1" => %{"phase" => "queued"}})
             )
    end

    test "well_formed?/1 rejects additional protected-looking top-level facts" do
      refute State.well_formed?(Map.put(State.new(), "root_policy", %{"limit" => 99}))
      refute State.well_formed?(Map.put(State.new(), "ledgers", %{}))
    end

    test "a map key that disagrees with the identifier it holds is invalid" do
      {state, _} = admitted()
      ticket = state["tickets"]["T1"]
      refute State.well_formed?(put_in(state, ["tickets"], %{"T2" => ticket}))
    end

    test "apply/2 is total over every state well_formed?/1 accepts" do
      {lifecycle, _} = full_lifecycle()
      {mid, _} = checking()
      {early, _} = admitted()

      states = [State.new(), early, mid, lifecycle]

      events =
        for type <- Event.types() do
          {:ok, keys} = Event.payload_keys(type)
          {:ok, kind} = Event.entity_kind(type)
          entity_id = if kind == "control", do: "control", else: "T1"
          payload = Map.new(keys, fn key -> {key, hostile_value(key)} end)
          event(type, entity_id, 0, 1, payload)
        end

      # One of two calls that skip the harness's assertions; `r4_no_direct_apply_test.exs`
      # pins the exact set. This test probes apply/2 with deliberately hostile payloads and
      # claims only totality: ok or error, never a raise. A hostile payload the kernel accepts
      # is well-formed by construction now (property 6) but may still break a relation the
      # harness asserts, and that would be a different claim — see `Harness.apply_unchecked/2`.
      for state <- states, built <- events do
        result = Harness.apply_unchecked(state, built)

        assert match?({:ok, _}, result) or match?({:error, _}, result),
               "#{built["type"]} raised or returned an untagged value"
      end
    end

    defp hostile_value("ticket_id"), do: "T1"
    defp hostile_value("objective_id"), do: "T1"
    defp hostile_value(key) when key in ~w(attempt_id), do: "A1"
    defp hostile_value(_key), do: %{"unexpected" => [1, nil, %{}]}
  end

  describe "B2 — custody per the R4 rows" do
    test "checks cannot start without verified developer closure" do
      {state, sequence} =
        drive(admitted(), [
          {"launch_planned", "T1",
           %{"ticket_id" => "T1", "attempt_id" => "A1", "authority" => authority("X1")}},
          {"artifact_frozen", "T1",
           %{
             "ticket_id" => "T1",
             "attempt_id" => "A1",
             "candidate_id" => "cand-1",
             "observation_id" => "obs-1",
             "sealed_generation" => "gen-1"
           }}
        ])

      premature =
        event("checks_started", "T1", state["tickets"]["T1"]["revision"], sequence + 10, %{
          "ticket_id" => "T1",
          "attempt_id" => "A1",
          "policy_empty" => false
        })

      assert {:error, :developer_not_closed} = Harness.apply(state, premature)
    end

    test "developer closure requires the input stream to be sealed first" do
      {state, sequence} =
        drive(admitted(), [
          {"launch_planned", "T1",
           %{"ticket_id" => "T1", "attempt_id" => "A1", "authority" => authority("X1")}},
          {"artifact_frozen", "T1",
           %{
             "ticket_id" => "T1",
             "attempt_id" => "A1",
             "candidate_id" => "cand-1",
             "observation_id" => "obs-1",
             "sealed_generation" => "gen-1"
           }}
        ])

      unsealed =
        event("developer_closed", "T1", state["tickets"]["T1"]["revision"], sequence + 1, %{
          "ticket_id" => "T1",
          "attempt_id" => "A1",
          "execution_id" => "X1"
        })

      assert {:error, :stream_not_sealed} = Harness.apply(state, unsealed)
    end

    test "a review verdict is refused before the reviewer stream is sealed" do
      {state, sequence} = reviewing()

      premature =
        event("review_recorded", "T1", state["tickets"]["T1"]["revision"], sequence + 1, %{
          "ticket_id" => "T1",
          "attempt_id" => "A1",
          "candidate_id" => "cand-1",
          "verdict" => "approved"
        })

      assert {:error, :reviewer_stream_not_sealed} = Harness.apply(state, premature)
    end

    test "a verdict naming another candidate is refused" do
      {state, sequence} =
        drive(reviewing(), [
          {"stream_sealed", "T1",
           %{
             "ticket_id" => "T1",
             "attempt_id" => "A1",
             "execution_id" => "R1",
             "last_accepted_sequence" => 3
           }}
        ])

      wrong =
        event("review_recorded", "T1", state["tickets"]["T1"]["revision"], sequence + 20, %{
          "ticket_id" => "T1",
          "attempt_id" => "A1",
          "candidate_id" => "cand-other",
          "verdict" => "approved"
        })

      assert {:error, :verdict_names_another_candidate} = Harness.apply(state, wrong)
    end

    test "a failed candidate cannot reach review" do
      {state, sequence} =
        drive(checking(), [
          {"check_planned", "T1",
           %{
             "ticket_id" => "T1",
             "attempt_id" => "A1",
             "check_id" => "C1",
             "authority" => authority("K1")
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

      attempt = state["tickets"]["T1"]["attempts"]["A1"]
      assert attempt["phase"] == "checking", "a failed check must not advance to review"

      premature =
        event("review_planned", "T1", state["tickets"]["T1"]["revision"], sequence + 20, %{
          "ticket_id" => "T1",
          "attempt_id" => "A1",
          "authority" => authority("R1")
        })

      assert {:error, :wrong_attempt_phase} = Harness.apply(state, premature)
    end

    test "integration cannot record a ref receipt while a check worker is still open" do
      # R4: "successful ref receipt and prior role/check workers closed". This is the gap
      # the enumeration missed: it named closure events for the developer and the reviewer
      # and none for the check, build and integration workers, so the integration row was
      # unreachable until worker_closed existed.
      {state, sequence} =
        drive(reviewing(), [
          {"stream_sealed", "T1",
           %{
             "ticket_id" => "T1",
             "attempt_id" => "A1",
             "execution_id" => "R1",
             "last_accepted_sequence" => 3
           }},
          {"review_recorded", "T1",
           %{
             "ticket_id" => "T1",
             "attempt_id" => "A1",
             "candidate_id" => "cand-1",
             "verdict" => "approved"
           }},
          {"reviewer_closed", "T1",
           %{"ticket_id" => "T1", "attempt_id" => "A1", "execution_id" => "R1"}},
          {"integration_planned", "T1",
           %{"ticket_id" => "T1", "attempt_id" => "A1", "authority" => authority("I1")}}
        ])

      premature =
        event("integration_recorded", "T1", state["tickets"]["T1"]["revision"], sequence + 1, %{
          "ticket_id" => "T1",
          "attempt_id" => "A1",
          "execution_id" => "I1",
          "outcome" => "ref_created",
          "ref_receipt_id" => "ref-1"
        })

      assert {:error, :workers_not_closed} = Harness.apply(state, premature)
    end

    test "an ordinary observation cannot close an execution" do
      {state, sequence} = checking()

      forged =
        event("execution_observed", "T1", state["tickets"]["T1"]["revision"], sequence + 1, %{
          "ticket_id" => "T1",
          "attempt_id" => "A1",
          "execution_id" => "X1",
          "observation" => "process exited",
          "lifecycle" => "closed"
        })

      # X1 is already closed by this point, and closure is terminal, so the stronger guard
      # answers first. Both refusals are correct; the point is that no observation reopens
      # or closes an execution.
      assert {:error, :execution_already_closed} = Harness.apply(state, forged)

      open =
        event("execution_observed", "T1", state["tickets"]["T1"]["revision"], sequence + 1, %{
          "ticket_id" => "T1",
          "attempt_id" => "A1",
          "execution_id" => "K1",
          "observation" => "process exited",
          "lifecycle" => "closed"
        })

      assert {:error, :unknown_execution} = Harness.apply(state, open)
    end

    test "worker_closed refuses an execution that is not a worker" do
      {state, sequence} = checking()

      forged =
        event("worker_closed", "T1", state["tickets"]["T1"]["revision"], sequence + 1, %{
          "ticket_id" => "T1",
          "attempt_id" => "A1",
          "execution_id" => "X1"
        })

      assert {:error, :wrong_execution_role} = Harness.apply(state, forged)
    end

    test "settling an attempt retains it as a prior attempt with all its evidence" do
      {state, _} = full_lifecycle()
      ticket = state["tickets"]["T1"]

      assert ticket["active_attempt_id"] == nil
      assert ticket["prior_attempt_ids"] == ["A1"]
      assert Map.has_key?(ticket["attempts"], "A1")
      assert map_size(ticket["attempts"]["A1"]["executions"]) == 4
    end

    test "a launch cannot overwrite an attempt that already exists" do
      {state, sequence} = checking()

      reused =
        event("launch_planned", "T1", state["tickets"]["T1"]["revision"], sequence + 1, %{
          "ticket_id" => "T1",
          "attempt_id" => "A1",
          "authority" => authority("X2")
        })

      # Refused on the phase guard before identity is even considered; the ticket is not
      # queued while a candidate is under check.
      assert {:error, :wrong_source_phase} = Harness.apply(state, reused)
    end
  end

  describe "R4's cancel row, second branch" do
    # "cancel_requested; every owned session AND non-session claim terminal, cleanup
    # reconciled | ... If integration occurred: integrated and
    # cancel_finalized(after_integration)".
    #
    # The seeded walks do not reach this variant: it needs the cancel to be requested
    # inside the narrow window while the ticket is `integrating`, and the walk's ordering
    # rarely lands there. That is a limitation of the search, and this test is what makes
    # the distinction checkable rather than asserted - the previous ratchet entry claimed a
    # depth limit for three other rows and independent review measured the claim false.
    # The lifecycle both tests need, up to and including the finalisation.
    defp cancel_racing_integration do
      drive({State.new(), 0}, [
        {"ticket_admitted", "T1",
         %{
           "ticket_id" => "T1",
           "objective_id" => nil,
           "spec_revision_id" => "spec-1",
           "spec" => %{},
           "phase" => "queued",
           "reason" => nil
         }},
        {"launch_planned", "T1",
         %{"ticket_id" => "T1", "attempt_id" => "A1", "authority" => authority("X0")}},
        {"artifact_frozen", "T1",
         %{
           "ticket_id" => "T1",
           "attempt_id" => "A1",
           "candidate_id" => "cand-1",
           "observation_id" => "obs-1",
           "sealed_generation" => "gen-1"
         }},
        {"stream_sealed", "T1",
         %{
           "ticket_id" => "T1",
           "attempt_id" => "A1",
           "execution_id" => "X0",
           "last_accepted_sequence" => 3
         }},
        {"developer_closed", "T1",
         %{"ticket_id" => "T1", "attempt_id" => "A1", "execution_id" => "X0"}},
        # R4: "checks with explicit policy-empty set follow same guarded transition".
        {"checks_started", "T1",
         %{"ticket_id" => "T1", "attempt_id" => "A1", "policy_empty" => true}},
        {"review_planned", "T1",
         %{
           "ticket_id" => "T1",
           "attempt_id" => "A1",
           "authority" => authority("R1", "reviewer")
         }},
        {"stream_sealed", "T1",
         %{
           "ticket_id" => "T1",
           "attempt_id" => "A1",
           "execution_id" => "R1",
           "last_accepted_sequence" => 9
         }},
        {"review_recorded", "T1",
         %{
           "ticket_id" => "T1",
           "attempt_id" => "A1",
           "candidate_id" => "cand-1",
           "verdict" => "approved"
         }},
        {"reviewer_closed", "T1",
         %{"ticket_id" => "T1", "attempt_id" => "A1", "execution_id" => "R1"}},
        {"integration_planned", "T1",
         %{
           "ticket_id" => "T1",
           "attempt_id" => "A1",
           "authority" => authority("I1", "integration")
         }},
        # The race: cancel is requested while the integration is already in flight.
        {"cancellation_requested", "T1", %{"ticket_id" => "T1"}},
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
           "settlement" => %{"schema_version" => 1}
         }},
        # Closure after settlement, which the active-attempt addressing made impossible.
        {"worker_closed", "T1",
         %{"ticket_id" => "T1", "attempt_id" => "A1", "execution_id" => "I1"}},
        {"cancellation_finalized", "T1",
         %{"ticket_id" => "T1", "disposition" => "after_integration"}}
      ])
    end

    test "a cancel that races a successful integration finalizes as after_integration" do
      {state, _} = cancel_racing_integration()

      ticket = state["tickets"]["T1"]
      assert ticket["phase"] == "integrated"
      assert ticket["attempts"]["A1"]["disposition"] == "integrated"
      assert ticket["cancel_requested"]
    end

    test "the cancelled branch is refused once an integration has occurred" do
      {state, sequence} = cancel_racing_integration()

      forged =
        event("cancellation_finalized", "T1", state["tickets"]["T1"]["revision"], sequence + 1, %{
          "ticket_id" => "T1",
          "disposition" => "cancelled"
        })

      assert {:error, :integration_occurred} = Harness.apply(state, forged)
    end
  end

  describe "R4a settlement keeps the attempt and consumes an ordinal" do
    test "a developer non-start returns the ticket to queued with the same attempt" do
      {state, _} =
        drive(admitted(), [
          {"launch_planned", "T1",
           %{"ticket_id" => "T1", "attempt_id" => "A1", "authority" => authority("X1")}},
          {"launch_settled", "T1",
           %{
             "ticket_id" => "T1",
             "attempt_id" => "A1",
             "execution_id" => "X1",
             "settlement" => %{"schema_version" => 1}
           }}
        ])

      ticket = state["tickets"]["T1"]
      assert ticket["phase"] == "queued"
      assert ticket["resume_phase"] == "developing"
      assert ticket["reason"] == "developer_launch_non_started"
      assert ticket["active_attempt_id"] == "A1"
      assert ticket["attempts"]["A1"]["phase"] == "active"
      assert ticket["infrastructure"]["ordinals"]["developer"] == 1
      assert ticket["attempts"]["A1"]["executions"]["X1"]["lifecycle"] == "closed"
    end

    test "a reviewer non-start returns the same frozen candidate to awaiting_review" do
      {state, _} =
        drive(reviewing(), [
          {"review_settled", "T1",
           %{
             "ticket_id" => "T1",
             "attempt_id" => "A1",
             "execution_id" => "R1",
             "settlement" => %{"schema_version" => 1}
           }}
        ])

      ticket = state["tickets"]["T1"]
      assert ticket["phase"] == "awaiting_review"
      assert ticket["attempts"]["A1"]["phase"] == "awaiting_review"
      assert ticket["attempts"]["A1"]["candidate_id"] == "cand-1"
      assert ticket["infrastructure"]["ordinals"]["reviewer"] == 1
    end
  end

  describe "the control entity is a singleton, orthogonal to ticket phase" do
    test "control changes apply to the fixed control identifier" do
      {state, _} =
        drive({State.new(), 0}, [
          {"control_changed", "control",
           %{
             "paused" => true,
             "draining" => false,
             "stop_status" => "running",
             "control" => %{
               "schema_version" => 1,
               "control_id" => "ctl-1",
               "control_revision" => 4
             }
           }}
        ])

      assert state["control"]["paused"]
      assert state["control"]["control_revision"] == 4
    end

    test "a control event addressed to any other identifier is refused" do
      forged =
        event("control_changed", "control", 0, 1, %{
          "paused" => true,
          "draining" => false,
          "stop_status" => "running",
          "control" => %{"schema_version" => 1, "control_id" => "ctl-1", "control_revision" => 1}
        })
        |> Map.put("entity_id", "T1")

      assert {:error, :invalid_control_entity} = Harness.apply(State.new(), forged)
    end

    test "a caller-shaped control fact cannot stand in for the protected one" do
      forged =
        event("control_changed", "control", 0, 1, %{
          "paused" => true,
          "draining" => false,
          "stop_status" => "running",
          "control" => %{"control_id" => "ctl-1", "control_revision" => 1}
        })

      assert {:error, :invalid_control_fact} = Harness.apply(State.new(), forged)
    end
  end

  describe "the event vocabulary is closed and exactly covered" do
    test "every type has an exact payload key set and an entity kind" do
      for type <- Event.types() do
        assert {:ok, keys} = Event.payload_keys(type)
        assert keys == Enum.uniq(keys)
        assert {:ok, kind} = Event.entity_kind(type)
        assert kind in ~w(ticket objective control)
      end
    end

    test "the kernel covers every durable lifecycle type, and 23 are not yet durable" do
      # The kernel's vocabulary must be a superset of the durable one, or a type the store
      # already accepts would have no reducer. The converse gap is the extension FR-08B
      # still owes: these 23 names cannot be persisted until RecordCodec's lifecycle set
      # grows, which gates subcommit 2. Asserting the exact number keeps that extension a
      # deliberate act rather than something discovered when a write fails.
      durable = PramanaFoundry.DurableStore.RecordCodec.lifecycle_event_types()

      assert durable -- Event.types() == [],
             "a durable lifecycle type has no reducer clause"

      assert length(Event.types() -- durable) == 23
    end

    test "a payload missing or gaining one key is rejected" do
      base = %{
        "ticket_id" => "T1",
        "objective_id" => nil,
        "spec_revision_id" => "spec-1",
        "spec" => %{},
        "phase" => "queued",
        "reason" => nil
      }

      assert :ok = Event.validate(event("ticket_admitted", "T1", 0, 1, base))

      assert {:error, :invalid_semantic_event} =
               Event.validate(event("ticket_admitted", "T1", 0, 1, Map.delete(base, "reason")))

      assert {:error, :invalid_semantic_event} =
               Event.validate(event("ticket_admitted", "T1", 0, 1, Map.put(base, "extra", 1)))
    end

    test "a template admits a binding marker where a bound event carries a fact" do
      planned =
        event("launch_planned", "T1", 0, 1, %{
          "ticket_id" => "T1",
          "attempt_id" => "A1",
          "authority" => %{"binding" => "authority"}
        })

      assert :ok = Event.validate(planned, template: true)
      assert {:error, :invalid_semantic_event} = Event.validate(planned)
    end

    test "a marker-shaped value with an extra key is not a marker" do
      planned =
        event("launch_planned", "T1", 0, 1, %{
          "ticket_id" => "T1",
          "attempt_id" => "A1",
          "authority" => %{"binding" => "authority", "value" => "forged"}
        })

      assert {:error, :invalid_semantic_event} = Event.validate(planned, template: true)
    end
  end

  # ── Longer lifecycles used by several tests ────────────────────────────────────────

  defp control_fact,
    do: %{"schema_version" => 1, "control_id" => "ctl-1", "control_revision" => 1}

  # A reviewing attempt whose reviewer stream is sealed, so a verdict may be recorded.
  defp sealed_reviewer do
    drive(reviewing(), [
      {"stream_sealed", "T1",
       %{
         "ticket_id" => "T1",
         "attempt_id" => "A1",
         "execution_id" => "R1",
         "last_accepted_sequence" => 12
       }}
    ])
  end

  defp verdict_recorded(value) do
    drive(sealed_reviewer(), [
      {"review_recorded", "T1",
       %{
         "ticket_id" => "T1",
         "attempt_id" => "A1",
         "candidate_id" => "cand-1",
         "verdict" => value
       }}
    ])
  end

  defp reviewing do
    drive(checking(), [
      {"check_planned", "T1",
       %{
         "ticket_id" => "T1",
         "attempt_id" => "A1",
         "check_id" => "C1",
         "authority" => authority("K1")
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
       %{"ticket_id" => "T1", "attempt_id" => "A1", "authority" => authority("R1")}}
    ])
  end

  defp full_lifecycle do
    drive(reviewing(), [
      {"stream_sealed", "T1",
       %{
         "ticket_id" => "T1",
         "attempt_id" => "A1",
         "execution_id" => "R1",
         "last_accepted_sequence" => 3
       }},
      {"review_recorded", "T1",
       %{
         "ticket_id" => "T1",
         "attempt_id" => "A1",
         "candidate_id" => "cand-1",
         "verdict" => "approved"
       }},
      {"reviewer_closed", "T1",
       %{"ticket_id" => "T1", "attempt_id" => "A1", "execution_id" => "R1"}},
      {"worker_closed", "T1",
       %{"ticket_id" => "T1", "attempt_id" => "A1", "execution_id" => "K1"}},
      {"integration_planned", "T1",
       %{"ticket_id" => "T1", "attempt_id" => "A1", "authority" => authority("I1")}},
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
         "settlement" => %{"schema_version" => 1}
       }}
    ])
  end

  # ── The fourth review's reproduced defects ─────────────────────────────────────────

  describe "review 4 — a non-start may not erase evidence that already exists" do
    # R4a's non-start rows exist for a worker that never ran. They are not a way to undo
    # what a worker that DID run produced. Both defects below are the same shape as the
    # settlement-role binding corrected after review three, one level further out: the
    # developer and integration siblings were guarded and the reviewer and check ones were
    # not, so "as one rule over the vocabulary" was again true of part of the vocabulary.

    # R4: "validated review result takes precedence over later execution exit status", and
    # R4a: a proved non-start is "not charged as a launch failure". One event erased an
    # approved verdict, returned the ticket to awaiting_review and charged the ordinal.
    for verdict <- ~w(approved rejected correction) do
      test "a reviewer non-start cannot erase a recorded #{verdict} verdict" do
        {state, sequence} = verdict_recorded(unquote(verdict))

        forged =
          event("review_settled", "T1", state["tickets"]["T1"]["revision"], sequence + 1, %{
            "ticket_id" => "T1",
            "attempt_id" => "A1",
            "execution_id" => "R1",
            "settlement" => %{"schema_version" => 1}
          })

        assert {:error, :verdict_already_recorded} = Harness.apply(state, forged)
      end
    end

    # R4 makes a check receipt a write-once sealed result, and the integration row requires
    # "all mandatory check receipts passed". Settling a check that had already recorded
    # `passed` deleted the receipt, after which the attempt could reach awaiting_review
    # with a mandatory check simply absent - which `require_checks_passed` cannot see,
    # because it folds over the checks that are still there.
    test "a check non-start cannot delete a receipt that already recorded" do
      {state, sequence} =
        drive(checking(), [
          {"check_planned", "T1",
           %{
             "ticket_id" => "T1",
             "attempt_id" => "A1",
             "check_id" => "C1",
             "authority" => authority("K1", "check")
           }},
          {"check_planned", "T1",
           %{
             "ticket_id" => "T1",
             "attempt_id" => "A1",
             "check_id" => "C2",
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

      forged =
        event("check_settled", "T1", state["tickets"]["T1"]["revision"], sequence + 1, %{
          "ticket_id" => "T1",
          "attempt_id" => "A1",
          "check_id" => "C1",
          "execution_id" => "K1",
          "settlement" => %{"schema_version" => 1}
        })

      assert {:error, :check_already_settled} = Harness.apply(state, forged)
    end
  end

  describe "review 4 — an advancing transition retires its resume target" do
    # Both reviewers reproduced this independently. `launch_settled` stores resume_phase
    # `developing`; the retry succeeds and `artifact_frozen` advances the ticket to
    # awaiting_review without clearing it; `require_honest_resume_target` accepted the
    # stored value from ANY phase, so a block could resurrect an obsolete recovery point
    # and the unblock returned a candidate_frozen attempt to `developing`.
    #
    # The implementer found this state, called it harmless because the guards refuse
    # everything from there, and deferred it. That was wrong twice over: a ticket from
    # which no productive event is accepted is a livelock, not a safe refusal, and
    # `launch_planned` is accepted - opening a third developer execution on an attempt that
    # has already frozen its candidate.
    test "a stale resume target cannot be named once the ticket has moved on" do
      {state, sequence} =
        drive(admitted(), [
          {"launch_planned", "T1",
           %{"ticket_id" => "T1", "attempt_id" => "A1", "authority" => authority("X1")}},
          {"launch_settled", "T1",
           %{
             "ticket_id" => "T1",
             "attempt_id" => "A1",
             "execution_id" => "X1",
             "settlement" => %{"schema_version" => 1}
           }},
          {"launch_planned", "T1",
           %{"ticket_id" => "T1", "attempt_id" => "A1", "authority" => authority("X2")}},
          {"artifact_frozen", "T1",
           %{
             "ticket_id" => "T1",
             "attempt_id" => "A1",
             "candidate_id" => "cand-1",
             "observation_id" => "obs-1",
             "sealed_generation" => "gen-1"
           }}
        ])

      assert state["tickets"]["T1"]["phase"] == "awaiting_review"

      assert state["tickets"]["T1"]["resume_phase"] == "developing",
             "the stale target is the precondition; if this changes the defect moved"

      forged =
        event("ticket_blocked", "T1", state["tickets"]["T1"]["revision"], sequence + 1, %{
          "ticket_id" => "T1",
          "reason" => "reviewer_launch_infrastructure",
          "resume_phase" => "developing"
        })

      assert {:error, :resume_target_not_current_phase} = Harness.apply(state, forged)
    end

    # R4a's developer non-start is the case the stored target exists for: the ticket lands
    # in `queued` holding resume_phase `developing` and a retained attempt the row calls
    # resumable, so a block from `queued` must be able to keep `developing` rather than
    # overwrite it with `queued`. This is why the fix is scoped to phase rather than
    # removing the stored alternative.
    test "R4a's developer non-start target survives a block from queued" do
      {state, sequence} =
        drive(admitted(), [
          {"launch_planned", "T1",
           %{"ticket_id" => "T1", "attempt_id" => "A1", "authority" => authority("X1")}},
          {"launch_settled", "T1",
           %{
             "ticket_id" => "T1",
             "attempt_id" => "A1",
             "execution_id" => "X1",
             "settlement" => %{"schema_version" => 1}
           }}
        ])

      assert state["tickets"]["T1"]["phase"] == "queued"

      {blocked, _} =
        drive({state, sequence}, [
          {"ticket_blocked", "T1",
           %{
             "ticket_id" => "T1",
             "reason" => "developer_launch_infrastructure",
             "resume_phase" => "developing"
           }}
        ])

      assert blocked["tickets"]["T1"]["resume_phase"] == "developing"
    end
  end

  describe "review 4 — variants the walks reach only by luck" do
    # `integration_recorded:infrastructure_failed` sits about twelve events from empty, so
    # whether a seeded random walk arrives is trajectory luck. The ratchet stood at zero
    # unreached by luck, and the resume-target fix changed refusals early enough to change
    # trajectories — the guard it touches is called only from ticket_parked and
    # ticket_blocked, neither of which is on the integration path, so coverage did not
    # regress; the sampling did.
    #
    # A driven witness does not depend on a seed.
    test "an integration effect can fail on infrastructure without a ref receipt" do
      {state, _sequence} =
        drive(approved_and_closed(), [
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
      attempt = ticket["attempts"]["A1"]

      # R4's row for this outcome is "or blocked(integration_failure)", not the
      # same-phase retry of `no_ref_change`. The first draft of this test asserted the
      # retry, from reading the comment above the branch rather than the branch.
      assert ticket["phase"] == "blocked"
      assert ticket["reason"] == "integration_failure"

      # R4's row is "Same phase ... after old issuer termination; or blocked(...)", so the
      # target is `integrating`. It stored `ready_to_integrate` while leaving the attempt
      # `integrating`, which `ticket_unblocked` turned into a `@legal_pairs` violation.
      assert ticket["resume_phase"] == "integrating"
      assert attempt["phase"] == "integrating", "the block does not advance the attempt"
      assert is_nil(attempt["ref_receipt_id"]), "R4: no Git success inferred"
    end
  end

  # ── Every remaining call site, one row each ────────────────────────────────────────

  describe "review 5 — a block must leave the attempt where its resume target promises" do
    # `integration_settled` moves ticket AND attempt to `ready_to_integrate` in one pipe.
    # The `infrastructure_failed` branch beside it moved only the ticket, which is the
    # seventh instance of this subcommit's most repeated defect shape: a rule applied to one
    # sibling and not the other.
    #
    # Nothing complained while blocked, because `blocked` is not a key in `@legal_pairs` and
    # so the oracle is silent there by construction. The violation appears one event later,
    # when `ticket_unblocked` honours a resume target the attempt never followed. That delay
    # is why `State.well_formed?/1` — correctly — accepts every step: nothing is malformed.
    #
    # No search reaches it. It is roughly 14 events from empty against a depth-7 bound, the
    # same reason the stale-resume defect needed a hand-driven sequence. The assertion is on
    # the oracle rather than on the two phase strings so that the whole relation is the
    # regression control, not the one field this branch happened to get wrong.
    test "integration infrastructure failure does not strand the attempt at integrating" do
      {state, sequence} = approved_and_closed()
      ticket = state["tickets"]["T1"]

      assert ticket["phase"] == "integrating"

      assert get_in(ticket, ["attempts", ticket["active_attempt_id"], "phase"]) == "integrating",
             "the precondition is a matched pair; if this changes the defect moved"

      {state, sequence} =
        drive({state, sequence}, [
          {"integration_recorded", "T1",
           %{
             "ticket_id" => "T1",
             "attempt_id" => "A1",
             "execution_id" => "I1",
             "outcome" => "infrastructure_failed",
             "ref_receipt_id" => nil
           }}
        ])

      assert state["tickets"]["T1"]["phase"] == "blocked"

      assert state["tickets"]["T1"]["resume_phase"] == "integrating",
             "R4's row for this outcome is Same phase after old issuer termination"

      assert State.violations(state) == [],
             "blocked is not a @legal_pairs key, so a stranded attempt is invisible here"

      {state, _sequence} =
        drive({state, sequence}, [
          {"ticket_unblocked", "T1", %{"ticket_id" => "T1", "phase" => "integrating"}}
        ])

      ticket = state["tickets"]["T1"]

      assert State.well_formed?(state),
             "nothing is malformed, which is why the shape validator never caught this"

      # Pinned directly as well as through the oracle. Asserting only the oracle made this
      # control depend on one line of `@legal_pairs`: deleting that key turned the test green
      # with the defect present, and nothing else in the suite pins the pair.
      assert get_in(ticket, ["attempts", ticket["active_attempt_id"], "phase"]) == "integrating"

      assert State.violations(state) == [],
             "ticket and attempt must agree wherever the resume target lands"
    end

    # The first fix for the row above moved the ATTEMPT to `ready_to_integrate` and left the
    # resume target alone. That satisfied `@legal_pairs` and broke a contract-backed refusal:
    # `require_settlement_source`'s `superseded_base` branch tests issuance only while the
    # attempt is `integrating`, on the stated premise that "from ready_to_integrate no
    # integration effect exists yet". An attempt parked at `ready_to_integrate` while holding
    # a running integration execution falsifies that premise, and R4's
    # "accepted base moved **before issuance**" row then accepts a settlement after issuance.
    #
    # Both oracles were silent on it: `State.well_formed?/1` and `State.invariant?/1` accept the
    # post-settle state, and `:integration_already_issued` sits in the guard-reachability
    # `@unreachable` list, so no ratchet had a witness to lose. Found by an independent
    # review, which is the argument for this test existing rather than the invariant alone.
    #
    # Driven over the whole in-flight vocabulary rather than `running` alone. The guard is
    # a membership test against a four-value list, and a control that witnesses one member
    # is the partial generalisation this repo keeps producing: `starting`, `closing` and
    # `unknown` would each have gone unwitnessed. `unknown` is the one that has to be
    # argued rather than read off - it is on the issued side because R1's ledger holds
    # `issued_unknown` "unavailable for reuse" and R4's integration row says "unknown
    # blocks reconciliation", so an effect whose outcome cannot be established is not an
    # effect that was never issued.
    test "every in-flight integration lifecycle refuses a superseded_base settlement" do
      for lifecycle <- ~w(starting running closing unknown) do
        {blocked, sequence} =
          drive(approved_and_closed(), [
            {"execution_observed", "T1",
             %{
               "ticket_id" => "T1",
               "attempt_id" => "A1",
               "execution_id" => "I1",
               "observation" => lifecycle,
               "lifecycle" => lifecycle
             }},
            {"integration_recorded", "T1",
             %{
               "ticket_id" => "T1",
               "attempt_id" => "A1",
               "execution_id" => "I1",
               "outcome" => "infrastructure_failed",
               "ref_receipt_id" => nil
             }}
          ])

        supersede = fn state, sequence ->
          Harness.apply(
            state,
            event("attempt_settled", "T1", state["tickets"]["T1"]["revision"], sequence + 1, %{
              "ticket_id" => "T1",
              "attempt_id" => "A1",
              "disposition" => "superseded_base",
              "reason_code" => nil,
              "settlement" => %{"schema_version" => 1}
            })
          )
        end

        assert {:error, :integration_already_issued} = supersede.(blocked, sequence),
               "#{lifecycle}: the effect is in flight; the block does not un-issue it"

        {resumed, sequence} =
          drive({blocked, sequence}, [
            {"ticket_unblocked", "T1", %{"ticket_id" => "T1", "phase" => "integrating"}}
          ])

        assert {:error, :integration_already_issued} = supersede.(resumed, sequence),
               "#{lifecycle}: resuming must not launder an issued effect into a settleable one"
      end
    end

    # The same guard from the other side, and the defect the row above only pointed at.
    # `integration_issued?` used to read "any integration execution is not `pending`",
    # which is a question about the attempt's history rather than about its current
    # effect. After the bounded retry R4 requires - "Same phase with bounded
    # integration-effect retry **after old issuer termination**" - the closed first issuer
    # made the unissued second one unsettleable, so R4's
    # "accepted base moved **before issuance**" row was unexpressible for a retried
    # integration. Reachable with none of the resume-target delta above, which is why it
    # is a defect of its own rather than a consequence of that one.
    test "a retried integration settles superseded_base while its new effect is unissued" do
      {retrying, sequence} =
        drive(approved_and_closed(), [
          {"execution_observed", "T1",
           %{
             "ticket_id" => "T1",
             "attempt_id" => "A1",
             "execution_id" => "I1",
             "observation" => "running",
             "lifecycle" => "running"
           }},
          {"integration_recorded", "T1",
           %{
             "ticket_id" => "T1",
             "attempt_id" => "A1",
             "execution_id" => "I1",
             "outcome" => "no_ref_change",
             "ref_receipt_id" => nil
           }},
          {"worker_closed", "T1",
           %{"ticket_id" => "T1", "attempt_id" => "A1", "execution_id" => "I1"}},
          {"integration_planned", "T1",
           %{
             "ticket_id" => "T1",
             "attempt_id" => "A1",
             "authority" => authority("I2", "integration")
           }}
        ])

      executions = get_in(retrying, ["tickets", "T1", "attempts", "A1", "executions"])

      # Pinned directly, not only through the settlement: if the fixture stopped producing
      # a closed issuer beside a pending one it would stop exercising the defect and still
      # pass.
      assert executions["I1"]["lifecycle"] == "closed"
      assert executions["I2"]["lifecycle"] == "pending"

      settle =
        event("attempt_settled", "T1", retrying["tickets"]["T1"]["revision"], sequence + 1, %{
          "ticket_id" => "T1",
          "attempt_id" => "A1",
          "disposition" => "superseded_base",
          "reason_code" => nil,
          "settlement" => %{"schema_version" => 1}
        })

      assert {:ok, settled} = Harness.apply(retrying, settle),
             "the current effect is still pending, which is what the row means by before issuance"

      assert get_in(settled, ["tickets", "T1", "attempts", "A1", "disposition"]) ==
               "superseded_base"
    end

    # The state the in-flight predicate is WRONG about, pinned to the guard that actually
    # refuses it. `worker_closed` carries one guard, `require_attempt`, and is the one
    # route to `closed` that `require_no_ref_receipt` does not stand in front of - so an
    # integration effect that landed can be closed, and `integration_issued?` then reads
    # false on an attempt holding a ref receipt. The original claim here was that a closed
    # integration execution never carries an effect that landed; it does, three events
    # from a fixture the suite already had, and an independent review drove it.
    #
    # Behaviour is correct, by `require_receipt_for_integration` sitting EARLIER in
    # `attempt_settled`'s `with` chain than `require_settlement_source`. That ordering is
    # the whole guarantee, and nothing pinned it: the existing
    # `:ref_receipt_admits_only_integrated` test never closes the execution first, so it
    # passes whether or not `integration_issued?` would also have refused. Pinned by exact
    # atom per rule 5, because a shared `{:error, _}` here would be satisfied by the guard
    # that is not doing the work.
    test "a landed integration effect that has been closed still refuses superseded_base" do
      {closed, sequence} =
        drive(integrating_with_receipt(), [
          {"worker_closed", "T1",
           %{"ticket_id" => "T1", "attempt_id" => "A1", "execution_id" => "I1"}}
        ])

      attempt = get_in(closed, ["tickets", "T1", "attempts", "A1"])

      assert attempt["executions"]["I1"]["lifecycle"] == "closed"
      assert attempt["ref_receipt_id"] == "ref-1"
      assert attempt["phase"] == "integrating"

      settle =
        event("attempt_settled", "T1", closed["tickets"]["T1"]["revision"], sequence + 1, %{
          "ticket_id" => "T1",
          "attempt_id" => "A1",
          "disposition" => "superseded_base",
          "reason_code" => nil,
          "settlement" => %{"schema_version" => 1}
        })

      assert {:error, :ref_receipt_admits_only_integrated} =
               Harness.apply(closed, settle),
             "the receipt guard is what refuses this, not the issuance predicate"
    end
  end

  # ── B3: control crossing at the issue point ────────────────────────────────────────

  # Builds the next event against `state`'s own bookkeeping and applies it, so a refusal
  # and its control are the same event from two states that differ only in the condition.
  # `authority/2` as compile-time data, for the tables below; `@auth` further down is the
  # same map without the per-execution keys.
  @b3_auth %{
    "schema_version" => 1,
    "effect_id" => "eff-X1",
    "role" => "developer",
    "work_owner" => "own-1",
    "ticket_id" => "T1",
    "attempt_id" => "A1",
    "execution_id" => "X1",
    "policy_id" => "pol-1",
    "policy_revision" => 0,
    "control_id" => "ctl-1",
    "control_revision" => 0,
    "predecessor_effect_id" => nil,
    "infrastructure_generation" => 0
  }

  defp plan({state, sequence}, type, payload) do
    Harness.apply(
      state,
      event(type, "T1", revision_of(state, type, "T1"), sequence + 1, payload)
    )
  end

  defp with_control({state, sequence}, paused, draining) do
    drive({state, sequence}, [
      {"control_changed", "control",
       %{
         "control" => control_fact(),
         "paused" => paused,
         "draining" => draining,
         "stop_status" => "running"
       }}
    ])
  end

  defp with_cancel(fixture),
    do: drive(fixture, [{"cancellation_requested", "T1", %{"ticket_id" => "T1"}}])

  describe "B3 — R4.04.f3: no developer issue under pause or drain" do
    # R4: "queued; dependencies/resources/profile/reservation eligible; no pause/drain/cancel
    # | ... create its launch intent and enter developing". One test per conjunct, each with
    # the same event accepted from the same lifecycle with only that conjunct withdrawn. The
    # cancel conjunct is the launch_planned row of the shared cancel table below.
    @launch %{"ticket_id" => "T1", "attempt_id" => "A1", "authority" => @b3_auth}

    test "launch_planned under pause refuses with control_paused" do
      assert {:error, :control_paused} =
               plan(with_control(admitted(), true, false), "launch_planned", @launch)

      assert {:ok, _} = plan(with_control(admitted(), false, false), "launch_planned", @launch)
    end

    test "launch_planned under drain refuses with control_draining" do
      assert {:error, :control_draining} =
               plan(with_control(admitted(), false, true), "launch_planned", @launch)

      assert {:ok, _} = plan(with_control(admitted(), false, false), "launch_planned", @launch)
    end
  end

  describe "B3 — a pending cancel refuses every ticket-scoped *_planned" do
    # R4.27.o1 "cancel pending/unissued effects" and R4a's cancel "never retries". One shared
    # guard, `require_no_pending_cancel/1`, called from each handler; one test per handler.
    # The handler set is derived from the vocabulary, so a sixth ticket-scoped planning event
    # fails here until it has a case - rule 4 enforced rather than remembered.
    @cancel_cases %{
      "launch_planned" =>
        {:admitted, %{"ticket_id" => "T1", "attempt_id" => "A1", "authority" => @b3_auth}},
      "check_planned" =>
        {:checking,
         %{
           "ticket_id" => "T1",
           "attempt_id" => "A1",
           "check_id" => "C1",
           "authority" => Map.merge(@b3_auth, %{"execution_id" => "K1", "role" => "check"})
         }},
      "build_planned" =>
        {:checking,
         %{
           "ticket_id" => "T1",
           "attempt_id" => "A1",
           "build_id" => "B1",
           "authority" => Map.merge(@b3_auth, %{"execution_id" => "B1", "role" => "build"})
         }},
      "review_planned" =>
        {:checked_passed,
         %{
           "ticket_id" => "T1",
           "attempt_id" => "A1",
           "authority" => Map.merge(@b3_auth, %{"execution_id" => "R1", "role" => "reviewer"})
         }},
      "integration_planned" =>
        {:ready_to_integrate,
         %{
           "ticket_id" => "T1",
           "attempt_id" => "A1",
           "authority" => Map.merge(@b3_auth, %{"execution_id" => "I1", "role" => "integration"})
         }}
    }

    test "the cases cover exactly the ticket-scoped planning events the vocabulary declares" do
      planning =
        for type <- Event.types(),
            String.ends_with?(type, "_planned"),
            Event.entity_kind(type) == {:ok, "ticket"},
            do: type

      assert Enum.sort(planning) == Enum.sort(Map.keys(@cancel_cases))
    end

    for {type, {fixture, payload}} <- @cancel_cases do
      test "#{type} under a pending cancel refuses with cancel_pending" do
        fixture = b3_fixture(unquote(fixture))
        payload = unquote(Macro.escape(payload))

        assert {:error, :cancel_pending} = plan(with_cancel(fixture), unquote(type), payload)
        assert {:ok, _} = plan(fixture, unquote(type), payload)
      end
    end
  end

  describe "B3 — a proved non-start settles under cancel, then cancellation finalizes" do
    # R4a: "Cancel settles the proved non-start/refund and finalizes cancellation when no
    # other issued work remains; it never retries." Tests only: every step below was
    # already accepted before B3, and none of it is new behaviour. The retry refusal in each
    # is the cancel guard seen from the state the settlement leaves behind.
    defp settle_and_finalize(fixture, settle_specs, retry_type, retry_payload) do
      settled = drive(with_cancel(fixture), settle_specs)

      assert {:error, :cancel_pending} = plan(settled, retry_type, retry_payload)

      {state, _} =
        drive(settled, [
          {"attempt_settled", "T1",
           %{
             "ticket_id" => "T1",
             "attempt_id" => "A1",
             "disposition" => "cancelled",
             "reason_code" => nil,
             "settlement" => %{"schema_version" => 1}
           }},
          {"cancellation_finalized", "T1", %{"ticket_id" => "T1", "disposition" => "cancelled"}}
        ])

      ticket = state["tickets"]["T1"]
      assert ticket["phase"] == "cancelled"
      assert ticket["attempts"]["A1"]["disposition"] == "cancelled"
      ticket
    end

    defp nonstart(type, execution_id, extra \\ %{}),
      do:
        {type, "T1",
         Map.merge(
           %{
             "ticket_id" => "T1",
             "attempt_id" => "A1",
             "execution_id" => execution_id,
             "settlement" => %{"schema_version" => 1}
           },
           extra
         )}

    test "developer" do
      ticket =
        settle_and_finalize(developing(), [nonstart("launch_settled", "X1")], "launch_planned", %{
          "ticket_id" => "T1",
          "attempt_id" => "A1",
          "authority" => authority("X2")
        })

      assert ticket["infrastructure"]["ordinals"]["developer"] == 1
    end

    test "reviewer" do
      ticket =
        settle_and_finalize(
          reviewing(),
          [
            nonstart("review_settled", "R1"),
            {"worker_closed", "T1",
             %{"ticket_id" => "T1", "attempt_id" => "A1", "execution_id" => "K1"}}
          ],
          "review_planned",
          %{"ticket_id" => "T1", "attempt_id" => "A1", "authority" => authority("R2", "reviewer")}
        )

      assert ticket["infrastructure"]["ordinals"]["reviewer"] == 1
    end

    test "check" do
      ticket =
        settle_and_finalize(
          checking_with_check(),
          [nonstart("check_settled", "K1", %{"check_id" => "C1"})],
          "check_planned",
          %{
            "ticket_id" => "T1",
            "attempt_id" => "A1",
            "check_id" => "C1",
            "authority" => authority("K2", "check")
          }
        )

      assert ticket["infrastructure"]["ordinals"]["check"] == 1
    end

    test "integration" do
      ticket =
        settle_and_finalize(
          approved_and_closed(),
          [nonstart("integration_settled", "I1")],
          "integration_planned",
          %{
            "ticket_id" => "T1",
            "attempt_id" => "A1",
            "authority" => authority("I2", "integration")
          }
        )

      assert ticket["infrastructure"]["ordinals"]["integration"] == 1
    end
  end

  defp b3_fixture(:admitted), do: admitted()
  defp b3_fixture(:checking), do: checking()
  defp b3_fixture(:checked_passed), do: checked("passed")
  defp b3_fixture(:ready_to_integrate), do: ready_to_integrate()

  describe "each guard call site, not each guard" do
    # The sweep used to neutralise by global string replacement, so identical call-site
    # text was mutated in every handler holding it and one red test anywhere cleared the
    # lot. It reported 66 call sites. There are 108. Swept per occurrence, 37 had never
    # been exercised — up to eleven untested siblings hiding behind one tested handler.
    #
    # One row per site. `state` names the fixture, which is the state in which every guard
    # BEFORE the target passes, so the refusal can only come from the target; `atom` is
    # pinned, because a shared `{:error, _}` is exactly what hid this class for three
    # reviews. The pairing that matters is state-and-payload to atom.
    #
    # Rows used to carry a kernel line number too. It is gone, and the reason is worth
    # keeping: the numbers were wrong the day they were committed - the commit that added
    # this table also added 23 kernel lines, so every label below :350 was already off by
    # eleven - and drift since is piecewise, not uniform. It was a claim with no check, in a
    # table whose entire purpose is that claims get checked. It also actively misled: the
    # `attempt_settled`/`blocked` row below was first written against a line read off a
    # six-clause `case` by eye, exercised a different branch that was already covered, and
    # passed while the site it named stayed a sweep survivor.
    #
    # The sweep is the measurement; these rows are not. Site identity comes back for free
    # when the coverage-guided design lands - see docs/COVERAGE-GUIDED-SWEEP.md - and it
    # will be derived rather than typed.
    #
    # Follow-up not taken here, from the fifth review: key each row on the guard CALL TEXT
    # instead, which is what the sweep prints verbatim and what SWEEP_SITES consumes. It does
    # not drift, it matches the survivor list directly, it tells the six sites sharing
    # `:wrong_attempt_phase` apart by their branch, and it can assert cheaply - the kernel
    # source either contains that text or the guard was removed or renamed, which is the one
    # time a row should fail. Better than either deletion or renumber-and-assert; deferred
    # only because it is not what this candidate is for.
    # `authority/2` is a function and @sites is a module attribute, so the attribute is
    # built before the function exists. Same map, spelled as compile-time data.
    @auth %{
      "schema_version" => 1,
      "work_owner" => "own-1",
      "ticket_id" => "T1",
      "attempt_id" => "A1",
      "policy_id" => "pol-1",
      "policy_revision" => 0,
      "control_id" => "ctl-1",
      "control_revision" => 0,
      "predecessor_effect_id" => nil,
      "infrastructure_generation" => 0
    }

    @sites [
      # ticket_amended (290), ticket_blocked (323-324), ticket_reset, cancellation_finalized (392)
      {:blocked_with_active_attempt, "ticket_amended",
       %{"ticket_id" => "T1", "spec_revision_id" => "spec-2", "spec" => %{}},
       :attempt_still_active},
      {:developing, "ticket_blocked",
       %{"ticket_id" => "T1", "reason" => "drain", "resume_phase" => "blocked"},
       :invalid_resume_phase},
      {:developing, "ticket_blocked",
       %{"ticket_id" => "T1", "reason" => "drain", "resume_phase" => "reviewing"},
       :resume_target_not_current_phase},
      {:cancel_requested_with_attempt, "cancellation_finalized",
       %{"ticket_id" => "T1", "disposition" => "cancelled"}, :attempt_still_active},

      # `require_attempt_phase(~w(active))` in artifact_frozen, artifact_blocked and
      # freeze_failed had exactly one reachable witness between them, and it was the
      # stale-resume defect. Fixing that defect removed it: no
      # reachable state now has a `developing` ticket whose active attempt is not `active`
      # (searched after the fix — 58,324 states at depth 7, none).
      #
      # They are therefore redundant with `require_phase(~w(developing))` above them GIVEN
      # the invariant `ticket.phase == developing => active attempt.phase == active`, which
      # `State.invariant?/1` asserts over every state the search reaches — true only as of
      # EV-5. This sentence stood here while `r4_exhaustive_test.exs`'s relations test could
      # not fail, so the redundancy argument was resting on an oracle that was applied to
      # nothing. The three sites kept their `@unreachable`-adjacent standing on a mechanism
      # that had never once reported. They are NOT
      # recorded as unreachable: a bounded search is not a proof, and treating absence as
      # one is the habit this review told us to drop. Deleting them is the right end state
      # and is a decision for review, not a side effect of a defect fix.
      # The developing family: phase, active attempt, attempt phase — in four handlers.
      {:developing, "launch_settled",
       %{
         "ticket_id" => "T1",
         "attempt_id" => "A-other",
         "execution_id" => "X1",
         "settlement" => %{"schema_version" => 1}
       }, :not_the_active_attempt},
      {:checking, "artifact_frozen",
       %{
         "ticket_id" => "T1",
         "attempt_id" => "A1",
         "candidate_id" => "cand-2",
         "observation_id" => "obs-9",
         "sealed_generation" => "gen-2"
       }, :wrong_source_phase},
      {:developing, "artifact_frozen",
       %{
         "ticket_id" => "T1",
         "attempt_id" => "A-other",
         "candidate_id" => "cand-2",
         "observation_id" => "obs-9",
         "sealed_generation" => "gen-2"
       }, :not_the_active_attempt},
      {:checking, "artifact_blocked",
       %{
         "ticket_id" => "T1",
         "attempt_id" => "A1",
         "observation_id" => "obs-9",
         "result" => "blocked",
         "reason" => "dep"
       }, :wrong_source_phase},
      {:developing, "artifact_blocked",
       %{
         "ticket_id" => "T1",
         "attempt_id" => "A-other",
         "observation_id" => "obs-9",
         "result" => "blocked",
         "reason" => "dep"
       }, :not_the_active_attempt},
      {:checking, "freeze_failed",
       %{
         "ticket_id" => "T1",
         "attempt_id" => "A1",
         "disposition" => "retry",
         "reason" => "import"
       }, :wrong_source_phase},
      {:developing, "submission_rejected",
       %{
         "ticket_id" => "T1",
         "attempt_id" => "A-other",
         "observation_id" => "obs-9",
         "reason" => "malformed"
       }, :not_the_active_attempt},

      # Closure and observation address an attempt by name, so a forged name is the test.
      {:developing, "execution_observed",
       %{
         "ticket_id" => "T1",
         "attempt_id" => "A-ghost",
         "execution_id" => "X1",
         "observation" => "running",
         "lifecycle" => "running"
       }, :unknown_attempt},
      {:developing, "stream_sealed",
       %{
         "ticket_id" => "T1",
         "attempt_id" => "A-ghost",
         "execution_id" => "X1",
         "last_accepted_sequence" => 3
       }, :unknown_attempt},
      {:developing, "stream_sealed",
       %{
         "ticket_id" => "T1",
         "attempt_id" => "A1",
         "execution_id" => "X-ghost",
         "last_accepted_sequence" => 3
       }, :unknown_execution},
      {:developing, "worker_closed",
       %{"ticket_id" => "T1", "attempt_id" => "A-ghost", "execution_id" => "X1"},
       :unknown_attempt},

      # The check family.
      {:candidate_frozen, "checks_started",
       %{"ticket_id" => "T1", "attempt_id" => "A-other", "policy_empty" => false},
       :not_the_active_attempt},
      {:checking, "check_planned",
       %{
         "ticket_id" => "T1",
         "attempt_id" => "A-other",
         "check_id" => "C2",
         "authority" =>
           Map.merge(@auth, %{"execution_id" => "K2", "role" => "check", "effect_id" => "eff-K2"})
       }, :not_the_active_attempt},
      {:candidate_frozen, "check_settled",
       %{
         "ticket_id" => "T1",
         "attempt_id" => "A1",
         "check_id" => "C1",
         "execution_id" => "K1",
         "settlement" => %{"schema_version" => 1}
       }, :wrong_attempt_phase},
      {:checking_with_check, "check_settled",
       %{
         "ticket_id" => "T1",
         "attempt_id" => "A-other",
         "check_id" => "C1",
         "execution_id" => "K1",
         "settlement" => %{"schema_version" => 1}
       }, :not_the_active_attempt},
      {:candidate_frozen, "check_recorded",
       %{
         "ticket_id" => "T1",
         "attempt_id" => "A1",
         "check_id" => "C1",
         "status" => "passed",
         "reason_code" => nil
       }, :wrong_attempt_phase},
      {:checking_with_check, "check_recorded",
       %{
         "ticket_id" => "T1",
         "attempt_id" => "A-other",
         "check_id" => "C1",
         "status" => "passed",
         "reason_code" => nil
       }, :not_the_active_attempt},
      {:checking_with_check, "check_recorded",
       %{
         "ticket_id" => "T1",
         "attempt_id" => "A1",
         "check_id" => "C-ghost",
         "status" => "passed",
         "reason_code" => nil
       }, :unknown_check},

      # The review family.
      {:developing, "review_planned",
       %{
         "ticket_id" => "T1",
         "attempt_id" => "A1",
         "authority" =>
           Map.merge(@auth, %{
             "execution_id" => "R1",
             "role" => "reviewer",
             "effect_id" => "eff-R1"
           })
       }, :wrong_source_phase},
      {:checked_passed, "review_planned",
       %{
         "ticket_id" => "T1",
         "attempt_id" => "A-other",
         "authority" =>
           Map.merge(@auth, %{
             "execution_id" => "R1",
             "role" => "reviewer",
             "effect_id" => "eff-R1"
           })
       }, :not_the_active_attempt},
      {:sealed_reviewer, "review_recorded",
       %{
         "ticket_id" => "T1",
         "attempt_id" => "A-other",
         "candidate_id" => "cand-1",
         "verdict" => "approved"
       }, :not_the_active_attempt},

      # The integration family, which no walk reaches: it sits about a dozen events in.
      {:ready_to_integrate, "integration_planned",
       %{
         "ticket_id" => "T1",
         "attempt_id" => "A-other",
         "authority" =>
           Map.merge(@auth, %{
             "execution_id" => "I1",
             "role" => "integration",
             "effect_id" => "eff-I1"
           })
       }, :not_the_active_attempt},
      {:developing, "integration_settled",
       %{
         "ticket_id" => "T1",
         "attempt_id" => "A1",
         "execution_id" => "I1",
         "settlement" => %{"schema_version" => 1}
       }, :wrong_source_phase},
      {:approved_and_closed, "integration_settled",
       %{
         "ticket_id" => "T1",
         "attempt_id" => "A-other",
         "execution_id" => "I1",
         "settlement" => %{"schema_version" => 1}
       }, :not_the_active_attempt},
      {:approved_and_closed, "integration_recorded",
       %{
         "ticket_id" => "T1",
         "attempt_id" => "A-other",
         "execution_id" => "I1",
         "outcome" => "ref_created",
         "ref_receipt_id" => "ref-1"
       }, :not_the_active_attempt},
      {:approved_and_closed, "integration_recorded",
       %{
         "ticket_id" => "T1",
         "attempt_id" => "A1",
         "execution_id" => "X-ghost",
         "outcome" => "ref_created",
         "ref_receipt_id" => "ref-1"
       }, :unknown_execution},

      # Build executions are planned and settled against the active attempt like any other.
      {:developing, "build_planned",
       %{
         "ticket_id" => "T1",
         "attempt_id" => "A-other",
         "build_id" => "B1",
         "authority" =>
           Map.merge(@auth, %{"execution_id" => "B1", "role" => "build", "effect_id" => "eff-B1"})
       }, :not_the_active_attempt},
      {:developing, "build_settled",
       %{
         "ticket_id" => "T1",
         "attempt_id" => "A-other",
         "build_id" => "B1",
         "execution_id" => "B1",
         "settlement" => %{"schema_version" => 1}
       }, :not_the_active_attempt},

      # Found by the 2026-09-21 full sweep, which reported 14 survivors where 9 were
      # recorded: the six "unable to fire" plus the three below that lost their witness to
      # the stale-resume fix. These three are ordinary untested guards, two of them in
      # handlers whose OTHER guards were all covered - the partial-generalisation shape
      # again, at the level of the handler rather than the rule.
      {:developing, "ticket_amended",
       %{"ticket_id" => "T1", "spec_revision_id" => "spec-2", "spec" => %{}},
       :wrong_source_phase},
      {:developing, "ticket_parked",
       %{"ticket_id" => "T1", "reason" => "drain", "resume_phase" => "developing"},
       :wrong_source_phase},
      # The `"blocked"` branch of require_settlement_source, NOT the failed/timed_out one
      # at :1585 - which the sweep had already caught, and which a first version of this
      # row targeted by mistake while claiming :1595. The scoped re-sweep is what found
      # that: the row was green, the site it named still survived.
      {:checking, "attempt_settled",
       %{
         "ticket_id" => "T1",
         "attempt_id" => "A1",
         "disposition" => "blocked",
         "reason_code" => "dependency",
         "settlement" => %{"schema_version" => 1}
       }, :wrong_attempt_phase}
    ]

    # The two survivors from that sweep that get NO row, and why they do not need one.
    #
    # `require_settlement_source` dispatches on disposition, and two of its branches guard a
    # phase behind a stronger condition:
    #
    #   "integrated" -> require_attempt_phase(~w(integrating))
    #   "rejected"   -> require_attempt_phase(~w(reviewing))
    #
    # Each is shadowed at its call site. Measured, not argued: settling `integrated` from
    # `ready_to_integrate` is refused by `require_receipt_for_integration` with
    # `:no_ref_receipt`, and settling `rejected` without one is refused by the verdict check
    # with `:no_rejected_verdict`. Reaching the phase guard needs a state where the shadowing
    # condition holds and the phase does not.
    #
    # The unseeded search cannot speak to this at all: at depth 7 over 58,324 states, ZERO
    # have an active attempt holding a ref receipt and ZERO have one with any recorded
    # verdict. That denominator is why these are not `State.invariant?/1` relations - such a
    # check would run over 58,324 states none of which can trip it.
    #
    # So the question was put where it lives, which is what kernel.ex's `reviewer_closed`
    # comment already does for the same shape. Seeded from `integrating_with_receipt` and
    # from a rejected verdict, at depth 6:
    #
    #   ref receipt   => integrating:  29,109 states, 20,488 hold the precondition, 0 violate
    #   rejected verdict => reviewing: 79,163 states, 39,024 hold the precondition, 0 violate
    #
    # And the inductive arguments, which are what make these more than enumerations. The two
    # are NOT the same shape, and the first version of this comment treated them as one.
    #
    # The verdict site is direct. `review_recorded` guards the ATTEMPT's phase itself -
    # `require_attempt_phase(ticket, ~w(reviewing))` - and writes the verdict to that same
    # attempt, so establishment needs no intermediate step. Preservation is the seeded run
    # above plus `require_no_recorded_verdict`, which makes a recorded verdict sticky.
    #
    # The receipt site needs one more link, and the first version of this argument was
    # vacuous at exactly that link. The receipt is written at one site, under
    # `require_phase(~w(integrating))` - the TICKET's phase - and lands on the active
    # attempt, so the base case needs ticket-integrating => attempt-integrating. Citing
    # `State.invariant?/1`'s `@legal_pairs` for that is worth nothing here: it is asserted
    # over the unseeded depth-7 set, which holds zero integrating tickets, as @unreachable's
    # own "integration row: ~12 events" says. Thousands of witnesses for the developing row
    # are not witnesses for this one. The argument that does hold is structural coupling, and
    # it needs its enumeration stated rather than assumed - an earlier version of this said
    # "set at exactly one site" without grepping for the writers, and that was false.
    #
    # Two transitions put a ticket in `integrating`. `integration_planned` sets ticket and
    # attempt in the same pipe, so it couples by construction. `ticket_unblocked` restores a
    # stored resume target, and `@blockable_phases` includes `integrating` while
    # `ticket_blocked` does not touch the attempt - so block-then-unblock writes
    # ticket-`integrating` without ever naming the attempt. What makes that safe is that the
    # target was coupled when it was stored, and that nothing rewrites the active attempt's
    # phase during the blocked window. The second half is MEASURED, not argued: `kernel_walk`
    # proposes `ticket_blocked` and `ticket_unblocked`, so the blocked window lies inside the
    # seeded run above, and none of its 20,488 receipt-holders violated.
    #
    # "Cleared together" holds for this invariant either way. `integration_recorded`'s
    # `infrastructure_failed` branch moves the ticket to `blocked` and leaves the attempt at
    # `integrating`. It cannot carry a receipt - that branch runs under
    # `require_no_ref_receipt` and writes none - so it is inert for THIS invariant. It used
    # to produce a reachable `@legal_pairs` violation by storing `ready_to_integrate` as the
    # resume target while leaving the attempt `integrating`; the target is now `integrating`,
    # which is what R4's row for that outcome says, so block-then-unblock restores the
    # coupled pair rather than a mismatched one.
    #
    # The seeded run seeds from a state that already holds the receipt, so it measures
    # preservation and not establishment - it could not have caught any of this.
    #
    # Both guards are therefore redundant given an invariant, not unwitnessed. They stay,
    # for the same reason the other belt-and-braces guards stay, and neither is recorded in
    # `@unreachable`: the atom fires elsewhere.

    for {fixture, type, payload, atom} <- @sites do
      test "#{type} from #{fixture} refuses with #{atom}" do
        {state, sequence} = fixture(unquote(fixture))

        forged =
          event(
            unquote(type),
            "T1",
            state["tickets"]["T1"]["revision"],
            sequence + 1,
            unquote(Macro.escape(payload))
          )

        assert {:error, unquote(atom)} = Harness.apply(state, forged)
      end
    end

    # Named rather than `apply/3`, which cannot reach a private function — and keeping the
    # fixtures private is worth one dispatcher, since making fifteen builders public to
    # satisfy a table would be the table changing the code it tests.
    defp fixture(:developing), do: developing()
    defp fixture(:candidate_frozen), do: candidate_frozen()
    defp fixture(:checking), do: checking()
    defp fixture(:checking_with_check), do: checking_with_check()
    defp fixture(:checked_passed), do: checked("passed")
    defp fixture(:sealed_reviewer), do: sealed_reviewer()
    defp fixture(:ready_to_integrate), do: ready_to_integrate()
    defp fixture(:approved_and_closed), do: approved_and_closed()
    defp fixture(:blocked_with_active_attempt), do: blocked_with_active_attempt()
    defp fixture(:cancel_requested_with_attempt), do: cancel_requested_with_attempt()
  end

  # ── States the second sweep needed, each one searched for rather than guessed ───────

  # R4 row 9 leaves the attempt active while the ticket blocks, so `queued/blocked with an
  # active attempt` is a real state — 22,879 of them at depth 7 — and it is what
  # `ticket_amended`'s refusal is for.
  defp blocked_with_active_attempt do
    drive(developing(), [
      {"artifact_blocked", "T1",
       %{
         "ticket_id" => "T1",
         "attempt_id" => "A1",
         "observation_id" => "obs-2",
         "result" => "blocked",
         "reason" => "dependency missing"
       }}
    ])
  end

  defp cancel_requested_with_attempt do
    drive(developing(), [{"cancellation_requested", "T1", %{"ticket_id" => "T1"}}])
  end

  # A ticket back in `developing` whose attempt has already frozen its candidate. Found by
  # exhaustive search, not constructed by hand — three such states exist at depth 7 and
  # this is the shortest path to one. `launch_settled` stores resume_phase `developing`;
  # `artifact_frozen` advances the ticket to awaiting_review without clearing it; a block
  # may then honestly name the stale stored target, and the unblock returns a
  # candidate_frozen attempt to `developing`.
  #
  # Whether `artifact_frozen` ought to clear the stale resume target is a live question for
  # review — it is R4 semantics, not a test concern, and is not changed here. What matters
  # for these three sites is that the state is reachable and the guards refuse it.

  defp checking_with_check do
    drive(checking(), [
      {"check_planned", "T1",
       %{
         "ticket_id" => "T1",
         "attempt_id" => "A1",
         "check_id" => "C1",
         "authority" => authority("K1", "check")
       }}
    ])
  end
end
