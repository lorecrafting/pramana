defmodule PramanaFoundry.AssignmentsTest do
  use ExUnit.Case, async: true

  alias PramanaFoundry.Assignments

  @base_rev "d83f8f0cedc34780d25cba452545ce9883d416a5"
  @commit "1111222233334444555566667777888899990000"
  @check ["sh", "-c", "cd workflow && exec mise exec -- mix test"]

  @ticket %{
    "task_id" => "T1",
    "base_revision" => @base_rev,
    "scope" => ["workflow/lib/pramana_foundry/**"],
    "exclusions" => ["automation/**"],
    "required_checks" => [@check],
    "checkout" => nil
  }

  @assignment %{
    "run_id" => "run-1",
    "ticket" => @ticket
  }

  @completed_handoff %{
    "schema_version" => 1,
    "task_id" => "T1",
    "run_id" => "run-1",
    "assigned_base" => @base_rev,
    "commit" => @commit,
    "changed_files" => ["workflow/lib/pramana_foundry/scheduler.ex"],
    "reproduction_evidence" => %{"before" => "broken", "after" => "fixed"},
    "checks" => [%{"command" => @check, "exit_code" => 0}],
    "remaining_risks" => [],
    "status" => "completed",
    "outcome" => "Implemented feature"
  }

  describe "validate_handoff/4 completed" do
    test "validates compliant completed handoff" do
      assert {:ok, _} =
               Assignments.validate_handoff(@completed_handoff, @ticket, @assignment,
                 skip_git_checks: true
               )
    end

    test "rejects handoff when changed file is outside scope" do
      bad_scope = %{@completed_handoff | "changed_files" => ["outside/file.ex"]}
      assert {:error, msg} = Assignments.validate_handoff(bad_scope, @ticket, @assignment)
      assert msg =~ "outside ticket scope"
    end

    test "rejects handoff when changed file is excluded" do
      bad_exclusion = %{@completed_handoff | "changed_files" => ["automation/file.py"]}
      assert {:error, msg} = Assignments.validate_handoff(bad_exclusion, @ticket, @assignment)
      assert msg =~ "matches ticket exclusion"
    end

    test "rejects handoff when required checks do not match" do
      bad_check = %{
        @completed_handoff
        | "checks" => [%{"command" => ["echo", "wrong"], "exit_code" => 0}]
      }

      assert {:error, msg} = Assignments.validate_handoff(bad_check, @ticket, @assignment)
      assert msg =~ "must exactly match ticket required_checks"
    end
  end

  describe "validate_handoff/4 blocked" do
    test "validates compliant blocked handoff" do
      blocked = %{
        "schema_version" => 1,
        "task_id" => "T1",
        "run_id" => "run-1",
        "status" => "blocked",
        "reason" => "Prerequisite missing",
        "diagnostic_evidence" => ["Observed missing file"]
      }

      assert {:ok, _} = Assignments.validate_handoff(blocked, @ticket, @assignment)
    end

    test "rejects blocked handoff without diagnostic_evidence" do
      blocked = %{
        "schema_version" => 1,
        "task_id" => "T1",
        "run_id" => "run-1",
        "status" => "blocked",
        "reason" => "Missing evidence",
        "diagnostic_evidence" => []
      }

      assert {:error, msg} = Assignments.validate_handoff(blocked, @ticket, @assignment)
      assert msg =~ "requires non-empty diagnostic_evidence"
    end
  end

  describe "handle_review/2 corrections" do
    test "approved review returns :approved without incrementing correction count" do
      review = %{"verdict" => "approved"}
      assert {:ok, :approved, updated} = Assignments.handle_review(@assignment, review)
      assert Map.get(updated, "correction_count", 0) == 0
    end

    test "first and second rejected reviews prepare correction assignments" do
      review1 = %{
        "verdict" => "rejected",
        "commit" => "c1",
        "findings" => ["fix line 10"],
        "checks" => []
      }

      assert {:ok, :correction_needed, a1} = Assignments.handle_review(@assignment, review1)
      assert a1["correction_count"] == 1
      assert a1["status"] == "queued"
      assert length(a1["correction_history"]) == 1

      review2 = %{
        "verdict" => "rejected",
        "commit" => "c2",
        "findings" => ["fix line 20"],
        "checks" => []
      }

      assert {:ok, :correction_needed, a2} = Assignments.handle_review(a1, review2)
      assert a2["correction_count"] == 2
      assert a2["status"] == "queued"
      assert length(a2["correction_history"]) == 2
    end

    test "third rejection exceeds limit (2) and parks ticket" do
      review = %{
        "verdict" => "rejected",
        "commit" => "c3",
        "findings" => ["still failing"],
        "checks" => []
      }

      a2 = Map.put(@assignment, "correction_count", 2)

      assert {:error, :max_corrections_exceeded, parked} = Assignments.handle_review(a2, review)
      assert parked["status"] == "parked"
      assert parked["blocker"] =~ "maximum corrections exceeded (2)"
    end
  end
end
