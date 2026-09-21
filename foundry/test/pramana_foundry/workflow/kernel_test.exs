defmodule PramanaFoundry.Workflow.KernelTest do
  @moduledoc """
  Subcommit 1 of the FR-08B kernel correction: the pure state and event contract.

  The first describe block reproduces the counterexamples of the independent pure-kernel
  review (`docs/fr-08/fr08b-pure-kernel-review.md`, candidate `a00decc`) and asserts the
  corrected behaviour, so each stays a regression control rather than a one-time argument.
  """
  use ExUnit.Case, async: true

  alias PramanaFoundry.Workflow.Kernel, as: WorkflowKernel
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

  # Drives a ticket to a frozen candidate with the developer closed and checks started.
  defp checking do
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
       %{"ticket_id" => "T1", "attempt_id" => "A1", "execution_id" => "X1"}},
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

  defp approved_and_closed do
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
       %{"ticket_id" => "T1", "attempt_id" => "A1", "execution_id" => "K1"}},
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

      assert {:error, :verdict_already_recorded} = WorkflowKernel.apply(state, forged)
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

      assert {:error, :invalid_verdict} = WorkflowKernel.apply(state, forged)
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

      assert {:error, :invalid_execution_lifecycle} = WorkflowKernel.apply(state, forged)
    end

    test "worker closure is refused for a non-worker execution" do
      {state, sequence} = developing()

      forged =
        event("worker_closed", "T1", state["tickets"]["T1"]["revision"], sequence + 1, %{
          "ticket_id" => "T1",
          "attempt_id" => "A1",
          "execution_id" => "X1"
        })

      assert {:error, :wrong_execution_role} = WorkflowKernel.apply(state, forged)
    end

    test "closure addressed to an attempt that does not exist is refused" do
      {state, sequence} = developing()

      forged =
        event("developer_closed", "T1", state["tickets"]["T1"]["revision"], sequence + 1, %{
          "ticket_id" => "T1",
          "attempt_id" => "A-ghost",
          "execution_id" => "X1"
        })

      assert {:error, :unknown_attempt} = WorkflowKernel.apply(state, forged)
    end

    test "closure naming an execution the attempt does not own is refused" do
      {state, sequence} = developing()

      forged =
        event("developer_closed", "T1", state["tickets"]["T1"]["revision"], sequence + 1, %{
          "ticket_id" => "T1",
          "attempt_id" => "A1",
          "execution_id" => "X-ghost"
        })

      assert {:error, :unknown_execution} = WorkflowKernel.apply(state, forged)
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

      assert {:error, :not_the_active_attempt} = WorkflowKernel.apply(state, forged)
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

      assert {:error, :wrong_source_phase} = WorkflowKernel.apply(state, forged)
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

      assert {:error, :wrong_source_phase} = WorkflowKernel.apply(state, forged)
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

      assert {:error, :invalid_stop_status} = WorkflowKernel.apply(state, forged)
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

      assert {:error, :invalid_control_flag} = WorkflowKernel.apply(state, forged)
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

      assert {:error, :no_rejected_verdict} = WorkflowKernel.apply(state, forged)
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

      assert {:error, :cancel_not_requested} = WorkflowKernel.apply(state, forged)
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

      assert {:error, :wrong_attempt_phase} = WorkflowKernel.apply(state, forged)
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

      assert {:error, :no_integration_to_finalize} = WorkflowKernel.apply(state, forged)
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

      assert {:error, :ref_receipt_admits_only_integrated} = WorkflowKernel.apply(state, forged)
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

      assert {:error, :check_already_settled} = WorkflowKernel.apply(state, forged)
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

      assert {:ok, next} = WorkflowKernel.apply(state, closed)
      assert State.valid?(next)

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

      assert {:error, :workers_not_closed} = WorkflowKernel.apply(state, forged)
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

      assert {:error, :not_the_reviewer_execution} = WorkflowKernel.apply(state, forged)
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

      assert {:error, :invalid_resume_phase} = WorkflowKernel.apply(state, forged)
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

      assert {:error, :invalid_admission_phase} = WorkflowKernel.apply(State.new(), forged)

      unknown = %{forged | "type" => "ticket_integrated"}
      assert {:error, :invalid_semantic_event} = WorkflowKernel.apply(State.new(), unknown)
    end

    test "no event outside the closed vocabulary reaches a merge" do
      for type <- ["", "integrate", "ticket_admitted ", "TICKET_ADMITTED", "__struct__"] do
        forged = event("ticket_admitted", "T1", 0, 1, %{}) |> Map.put("type", type)
        assert {:error, :invalid_semantic_event} = WorkflowKernel.apply(State.new(), forged)
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

      assert {:error, :out_of_order_event} = WorkflowKernel.apply(state, stale)
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
      assert {:error, :stale_entity_revision} = WorkflowKernel.apply(state, stale)
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

      assert {:ok, ^state} = WorkflowKernel.apply(state, redelivered)
    end

    test "valid?/1 rejects the malformed nested state that made decide/3 raise" do
      # The reviewed candidate's validator checked outer containers and four control
      # fields, so this state passed and then raised inside a source guard.
      assert State.valid?(State.new())
      refute State.valid?(put_in(State.new(), ["tickets"], %{"T1" => 7}))
      refute State.valid?(put_in(State.new(), ["tickets"], %{"T1" => %{"phase" => "queued"}}))
    end

    test "valid?/1 rejects additional protected-looking top-level facts" do
      refute State.valid?(Map.put(State.new(), "root_policy", %{"limit" => 99}))
      refute State.valid?(Map.put(State.new(), "ledgers", %{}))
    end

    test "a map key that disagrees with the identifier it holds is invalid" do
      {state, _} = admitted()
      ticket = state["tickets"]["T1"]
      refute State.valid?(put_in(state, ["tickets"], %{"T2" => ticket}))
    end

    test "apply/2 is total over every state valid?/1 accepts" do
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

      for state <- states, built <- events do
        result = WorkflowKernel.apply(state, built)

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

      assert {:error, :developer_not_closed} = WorkflowKernel.apply(state, premature)
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

      assert {:error, :stream_not_sealed} = WorkflowKernel.apply(state, unsealed)
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

      assert {:error, :reviewer_stream_not_sealed} = WorkflowKernel.apply(state, premature)
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

      assert {:error, :verdict_names_another_candidate} = WorkflowKernel.apply(state, wrong)
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

      assert {:error, :wrong_attempt_phase} = WorkflowKernel.apply(state, premature)
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

      assert {:error, :workers_not_closed} = WorkflowKernel.apply(state, premature)
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
      assert {:error, :execution_already_closed} = WorkflowKernel.apply(state, forged)

      open =
        event("execution_observed", "T1", state["tickets"]["T1"]["revision"], sequence + 1, %{
          "ticket_id" => "T1",
          "attempt_id" => "A1",
          "execution_id" => "K1",
          "observation" => "process exited",
          "lifecycle" => "closed"
        })

      assert {:error, :unknown_execution} = WorkflowKernel.apply(state, open)
    end

    test "worker_closed refuses an execution that is not a worker" do
      {state, sequence} = checking()

      forged =
        event("worker_closed", "T1", state["tickets"]["T1"]["revision"], sequence + 1, %{
          "ticket_id" => "T1",
          "attempt_id" => "A1",
          "execution_id" => "X1"
        })

      assert {:error, :wrong_execution_role} = WorkflowKernel.apply(state, forged)
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
      assert {:error, :wrong_source_phase} = WorkflowKernel.apply(state, reused)
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

      assert {:error, :integration_occurred} = WorkflowKernel.apply(state, forged)
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

      assert {:error, :invalid_control_entity} = WorkflowKernel.apply(State.new(), forged)
    end

    test "a caller-shaped control fact cannot stand in for the protected one" do
      forged =
        event("control_changed", "control", 0, 1, %{
          "paused" => true,
          "draining" => false,
          "stop_status" => "running",
          "control" => %{"control_id" => "ctl-1", "control_revision" => 1}
        })

      assert {:error, :invalid_control_fact} = WorkflowKernel.apply(State.new(), forged)
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
end
