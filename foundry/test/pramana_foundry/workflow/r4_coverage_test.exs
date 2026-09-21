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
  @unexpressible %{
    base_moved: "no event produces superseded_base; R4's moved-base row has no vocabulary",
    malformed_submission:
      "submission_rejected is a no-op: no durable rejected submission, no validation charge, no exhaustion",
    check_infrastructure_failed:
      "finding 4: a timed_out check settles needs_correction, and a fresh passing run cannot clear the old one",
    nonstart_reviewer:
      "finding 5: ticket_parked no longer accepts awaiting_review, so blocked(reviewer_launch_infrastructure) is gone",
    nonstart_worker: "finding 5: same, for blocked(check_infrastructure) from checking",
    reset: "ticket_reset has no producer for reset_fact_v1; recorded prerequisite for subcommit 3"
  }

  describe "the row inventory tracks the contract" do
    test "every contract transition row has a declared handle, and vice versa" do
      contract = MapSet.new(R4Rows.contract_rows(), &elem(&1, 0))
      declared = MapSet.new(R4Rows.ids(), &R4Rows.declared_from/1)

      assert MapSet.difference(contract, declared) |> Enum.to_list() == [],
             "contract rows with no handle - the contract gained a row this suite ignores"

      assert MapSet.difference(declared, contract) |> Enum.to_list() == [],
             "handles matching no contract row - a row was edited or removed"
    end
  end

  describe "every contract row is driven" do
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
