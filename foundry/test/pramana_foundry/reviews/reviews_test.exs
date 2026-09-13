defmodule PramanaFoundry.ReviewsTest do
  use ExUnit.Case, async: true

  alias PramanaFoundry.Reviews

  @policy %{
    "review_matrix" => %{
      "routine" => "omp_gemini_reviewer",
      "high_risk" => "omp_codex_sol_reviewer"
    }
  }

  describe "derive_reviewer_profile/2" do
    test "derives high_risk profile for P0 tickets" do
      ticket = %{"priority" => "P0", "risk" => "routine", "work_class" => "ordinary"}
      assert Reviews.derive_reviewer_profile(ticket, @policy) == {:ok, "omp_codex_sol_reviewer"}
    end

    test "derives high_risk profile for workflow_recovery risk" do
      ticket = %{"priority" => "P1", "risk" => "workflow_recovery", "work_class" => "ordinary"}
      assert Reviews.derive_reviewer_profile(ticket, @policy) == {:ok, "omp_codex_sol_reviewer"}
    end

    test "derives high_risk profile for milestone_architecture work class" do
      ticket = %{
        "priority" => "P1",
        "risk" => "routine",
        "work_class" => "milestone_architecture"
      }

      assert Reviews.derive_reviewer_profile(ticket, @policy) == {:ok, "omp_codex_sol_reviewer"}
    end

    test "derives routine profile for ordinary P1 tickets" do
      ticket = %{"priority" => "P1", "risk" => "routine", "work_class" => "ordinary"}
      assert Reviews.derive_reviewer_profile(ticket, @policy) == {:ok, "omp_gemini_reviewer"}
    end
  end

  describe "validate_artifact/4" do
    @check_command ["sh", "-c", "cd workflow && exec mise exec -- mix test"]
    @ticket %{
      "task_id" => "T1",
      "review_required_checks" => [@check_command],
      "checkout" => nil
    }
    @assignment %{
      "run_id" => "run-1",
      "reviewer_run_id" => "reviewer-run-1",
      "handoff" => %{"commit" => "commit-sha-1234"}
    }

    @valid_review %{
      "schema_version" => 1,
      "run_id" => "reviewer-run-1",
      "task_id" => "T1",
      "commit" => "commit-sha-1234",
      "verdict" => "approved",
      "findings" => [],
      "remaining_risks" => [],
      "checks" => [
        %{"command" => @check_command, "exit_code" => 0}
      ]
    }

    test "validates schema-compliant approved review artifact" do
      assert {:ok, _} =
               Reviews.validate_artifact(@valid_review, @ticket, @assignment,
                 skip_git_checks: true
               )
    end

    test "rejects review artifact with unexpected fields" do
      bad_review = Map.put(@valid_review, "extra_field", "forbidden")

      assert {:error, msg} =
               Reviews.validate_artifact(bad_review, @ticket, @assignment, skip_git_checks: true)

      assert msg =~ "fields must be exactly"
    end

    test "rejects review artifact when required checks do not match" do
      bad_checks_review = %{
        @valid_review
        | "checks" => [
            %{"command" => ["sh", "-c", "echo different"], "exit_code" => 0}
          ]
      }

      assert {:error, msg} =
               Reviews.validate_artifact(bad_checks_review, @ticket, @assignment,
                 skip_git_checks: true
               )

      assert msg =~ "review checks must exactly match review_required_checks"
    end

    test "rejects approved review artifact when check failed (non-zero exit_code)" do
      failed_check_review = %{
        @valid_review
        | "checks" => [
            %{"command" => @check_command, "exit_code" => 1}
          ]
      }

      assert {:error, msg} =
               Reviews.validate_artifact(failed_check_review, @ticket, @assignment,
                 skip_git_checks: true
               )

      assert msg =~ "cannot contain non-zero exit_code"
    end

    test "rejects review artifact when task_id or run_id mismatch" do
      mismatched_run = %{@valid_review | "run_id" => "other-run"}

      assert {:error, msg} =
               Reviews.validate_artifact(mismatched_run, @ticket, @assignment,
                 skip_git_checks: true
               )

      assert msg =~ "run_id mismatch"
    end

    test "accepts review with run_id matching reviewer_run_id on assignment" do
      assignment = Map.merge(@assignment, %{"reviewer_run_id" => "reviewer-run-42"})
      review = %{@valid_review | "run_id" => "reviewer-run-42"}

      assert {:ok, _} =
               Reviews.validate_artifact(review, @ticket, assignment, skip_git_checks: true)
    end

    test "rejects review with only the developer handoff run_id" do
      assignment =
        Map.merge(@assignment, %{
          "run_id" => "developer-run",
          "handoff" => %{"commit" => "commit-sha-1234", "run_id" => "handoff-run-99"}
        })
        |> Map.delete("reviewer_run_id")

      review = %{@valid_review | "run_id" => "handoff-run-99"}

      assert {:error, msg} =
               Reviews.validate_artifact(review, @ticket, assignment, skip_git_checks: true)

      assert msg =~ "independently issued reviewer run_id"
    end

    test "rejects review when run_id matches none of assignment/handoff/reviewer" do
      assignment =
        Map.merge(@assignment, %{
          "run_id" => "dev-1",
          "reviewer_run_id" => "reviewer-1",
          "handoff" => %{"commit" => "commit-sha-1234", "run_id" => "handoff-1"}
        })

      review = %{@valid_review | "run_id" => "completely-unknown"}

      assert {:error, msg} =
               Reviews.validate_artifact(review, @ticket, assignment, skip_git_checks: true)

      assert msg =~ "run_id mismatch"
    end
  end
end
