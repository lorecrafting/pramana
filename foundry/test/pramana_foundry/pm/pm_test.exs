defmodule PramanaFoundry.PMTest do
  use ExUnit.Case, async: true

  alias PramanaFoundry.PM

  @base_rev "d83f8f0cedc34780d25cba452545ce9883d416a5"

  describe "transactional PM proposal batches" do
    setup do
      state = %{
        "accepted_revision" => @base_rev,
        "assignments" => %{
          "T1" => %{
            "status" => "queued",
            "ticket" => %{
              "task_id" => "T1",
              "base_revision" => @base_rev,
              "priority" => "P2",
              "dependencies" => []
            }
          }
        },
        "queue" => ["T1"],
        "scheduler" => %{}
      }

      %{state: state}
    end

    test "applies all-or-none: rollbacks when second proposal is invalid", %{state: state} do
      proposals = [
        %{
          "operation" => "create",
          "ticket" => %{
            "task_id" => "T2",
            "base_revision" => @base_rev,
            "priority" => "P1",
            "dependencies" => []
          },
          "reason" => "add T2"
        },
        %{
          "operation" => "create",
          "ticket" => %{
            "task_id" => "T3",
            "base_revision" => "wrong-stale-base",
            "priority" => "P1",
            "dependencies" => []
          },
          "reason" => "add T3 with bad base"
        }
      ]

      assert {:error, reason} = PM.apply_proposals(state, proposals)
      assert reason =~ "does not equal accepted revision"

      # Verify state rolled back completely: T2 was not added!
      refute Map.has_key?(state["assignments"], "T2")
      assert state["queue"] == ["T1"]
    end

    test "successful batch creates and modifies assignments atomically", %{state: state} do
      proposals = [
        %{
          "operation" => "create",
          "ticket" => %{
            "task_id" => "T2",
            "base_revision" => @base_rev,
            "priority" => "P1",
            "dependencies" => ["T1"]
          },
          "reason" => "add T2 dependent on T1"
        },
        %{
          "operation" => "reprioritize",
          "task_id" => "T1",
          "priority" => "P0",
          "reason" => "elevate T1"
        }
      ]

      assert {:ok, new_state} = PM.apply_proposals(state, proposals)
      assert Map.has_key?(new_state["assignments"], "T2")
      assert new_state["assignments"]["T1"]["ticket"]["priority"] == "P0"
      assert new_state["queue"] == ["T1", "T2"]
    end

    test "rejects dependency cycle", %{state: state} do
      proposals = [
        %{
          "operation" => "create",
          "ticket" => %{
            "task_id" => "T2",
            "base_revision" => @base_rev,
            "dependencies" => ["T3"]
          },
          "reason" => "add T2"
        },
        %{
          "operation" => "create",
          "ticket" => %{
            "task_id" => "T3",
            "base_revision" => @base_rev,
            "dependencies" => ["T2"]
          },
          "reason" => "add T3"
        }
      ]

      assert {:error, reason} = PM.apply_proposals(state, proposals)
      assert reason =~ "cycle"
    end
  end

  describe "planning attempt cap semantics" do
    test "reason normalization replaces volatile hexadecimal run IDs" do
      reason1 =
        "artifact /artifacts/planning/b37dad30185b47dba03a4758540546a7.json missing fields: [outcome]"

      reason2 =
        "artifact /artifacts/planning/89abcdef0123456789abcdef0123456789ab.json missing fields: [outcome]"

      assert PM.normalize_reason(reason1) == PM.normalize_reason(reason2)
      assert PM.normalize_reason(reason1) =~ "<hex>"
    end

    test "consecutive rejections with same reason increment streak and trigger halt" do
      pm_state = %{"accepted_revision" => @base_rev}

      # Attempt 1: rejection
      reason = "artifact /path/run-1111222233334444.json missing fields"
      pm_state = PM.record_disposition(pm_state, "rejected", reason)
      assert get_in(pm_state, ["consecutive_rejections_by_revision", @base_rev, "count"]) == 1

      # Attempt 2: rejection with different run ID but same reason -> count becomes 2
      reason_fresh_run = "artifact /path/run-5555666677778888.json missing fields"
      pm_state = PM.record_disposition(pm_state, "rejected", reason_fresh_run)
      assert get_in(pm_state, ["consecutive_rejections_by_revision", @base_rev, "count"]) == 2

      # Attempt 3: rejection with another run ID -> count becomes 3 (threshold reached!)
      reason_third = "artifact /path/run-aaaabbbbccccdddd.json missing fields"
      pm_state = PM.record_disposition(pm_state, "rejected", reason_third)
      assert get_in(pm_state, ["consecutive_rejections_by_revision", @base_rev, "count"]) == 3

      halt = PM.halt_reason(pm_state, @base_rev, max_attempts_per_revision: 3)
      assert halt != nil
      assert halt["counter"] == "consecutive_rejections"
      assert halt["count"] == 3
      assert halt["clears_with"] == "reset-pm-attempts"
    end

    test "differing rejection reasons reset streak to 1, converging rather than halting" do
      pm_state = %{"accepted_revision" => @base_rev}

      pm_state = PM.record_disposition(pm_state, "rejected", "first error reason")
      assert get_in(pm_state, ["consecutive_rejections_by_revision", @base_rev, "count"]) == 1

      pm_state = PM.record_disposition(pm_state, "rejected", "different second error reason")
      assert get_in(pm_state, ["consecutive_rejections_by_revision", @base_rev, "count"]) == 1

      assert PM.halt_reason(pm_state, @base_rev, max_attempts_per_revision: 3) == nil
    end

    test "total attempts storm ceiling halts planning when reached" do
      pm_state = %{"accepted_revision" => @base_rev}

      pm_state =
        Enum.reduce(1..10, pm_state, fn i, acc ->
          acc
          |> PM.increment_attempt(@base_rev)
          |> PM.record_disposition("rejected", "error #{i}")
        end)

      halt = PM.halt_reason(pm_state, @base_rev, max_total_attempts_per_revision: 10)
      assert halt != nil
      assert halt["counter"] == "total_attempts"
      assert halt["count"] == 10
    end

    test "accepted proposal clears the streak" do
      pm_state = %{"accepted_revision" => @base_rev}
      pm_state = PM.record_disposition(pm_state, "rejected", "error")
      assert get_in(pm_state, ["consecutive_rejections_by_revision", @base_rev, "count"]) == 1

      pm_state = PM.record_disposition(pm_state, "accepted", "all proposals valid")
      refute Map.has_key?(pm_state["consecutive_rejections_by_revision"], @base_rev)
    end

    test "suspension is a halt, not a verdict, neither extending nor breaking the count" do
      pm_state = %{"accepted_revision" => @base_rev}
      pm_state = PM.record_disposition(pm_state, "rejected", "error")
      assert get_in(pm_state, ["consecutive_rejections_by_revision", @base_rev, "count"]) == 1

      pm_state = PM.record_disposition(pm_state, "suspended", "paused by operator")
      # Streak count is still 1
      assert get_in(pm_state, ["consecutive_rejections_by_revision", @base_rev, "count"]) == 1
    end

    test "human-issued reset_pm_attempts control clears the halt" do
      pm_state = %{
        "accepted_revision" => @base_rev,
        "attempts_by_revision" => %{@base_rev => 5},
        "consecutive_rejections_by_revision" => %{
          @base_rev => %{"count" => 3, "reason" => "repeated defect"}
        },
        "planning_attempt_halt" => %{"revision" => @base_rev}
      }

      payload = %{
        "authority" => "human",
        "issued_by" => "operator",
        "issued_at" => "2026-09-10T12:00:00Z",
        "revision" => @base_rev
      }

      assert {:ok, record, updated_pm} = PM.reset_attempts(pm_state, payload, @base_rev)
      assert record["previous_attempts"] == 5
      assert record["previous_consecutive_rejections"] == 3
      assert record["previous_rejection_reason"] == "repeated defect"

      # Counters cleared!
      refute Map.has_key?(updated_pm["attempts_by_revision"], @base_rev)
      refute Map.has_key?(updated_pm["consecutive_rejections_by_revision"], @base_rev)
      refute Map.has_key?(updated_pm, "planning_attempt_halt")
      assert PM.halt_reason(updated_pm, @base_rev) == nil
    end

    test "non-human authority or mismatched revision rejects reset_pm_attempts" do
      pm_state = %{}
      assert {:error, msg} = PM.reset_attempts(pm_state, %{"authority" => "ai"}, @base_rev)
      assert msg =~ "human authority"

      payload = %{
        "authority" => "human",
        "issued_by" => "op",
        "issued_at" => "now",
        "revision" => "other-rev"
      }

      assert {:error, msg} = PM.reset_attempts(pm_state, payload, @base_rev)
      assert msg =~ "current accepted revision"
    end
  end
end
