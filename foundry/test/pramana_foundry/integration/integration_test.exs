defmodule PramanaFoundry.IntegrationTest do
  use ExUnit.Case, async: true

  alias PramanaFoundry.Integration

  @base_rev "d83f8f0cedc34780d25cba452545ce9883d416a5"
  @cand_rev "9999888877776666555544443333222211110000"

  @assignment %{
    "task_id" => "T1",
    "status" => "review_approved",
    "review" => %{"verdict" => "approved"},
    "ticket" => %{
      "task_id" => "T1",
      "base_revision" => @base_rev,
      "checkout" => nil
    },
    "handoff" => %{"commit" => @cand_rev}
  }

  describe "serial singleton owner" do
    test "allows single owner, rejects concurrent second candidate" do
      state = %{"accepted_revision" => @base_rev, "integration" => %{}}

      assert {:ok, state_owned} = Integration.acquire_owner(state, "T1", @cand_rev)
      assert state_owned["integration"]["owner"] == "T1"

      assert {:error, :integration_busy} =
               Integration.acquire_owner(state_owned, "T2", "other-commit")

      # Releasing owner allows next
      state_released = Integration.release_owner(state_owned, "T1")
      assert state_released["integration"]["owner"] == nil

      assert {:ok, _} = Integration.acquire_owner(state_released, "T2", "other-commit")
    end
  end

  describe "readiness validation" do
    test "pause blocks promotion" do
      state = %{"accepted_revision" => @base_rev, "paused" => true}
      assert {:error, msg} = Integration.validate_readiness(state, @assignment)
      assert msg =~ "promotion blocked: supervisor is paused"
    end

    test "stop blocks promotion" do
      state = %{"accepted_revision" => @base_rev, "stop_requested" => true}
      assert {:error, msg} = Integration.validate_readiness(state, @assignment)
      assert msg =~ "promotion blocked: stop requested"
    end

    test "stale candidate base revision parks/rejects" do
      state = %{"accepted_revision" => "new-advanced-base-rev"}
      assert {:error, msg} = Integration.validate_readiness(state, @assignment)
      assert msg =~ "stale candidate"
    end
  end

  describe "combined gate checks and failure" do
    test "gate check failure preserves accepted revision and parks assignment" do
      state = %{
        "accepted_revision" => @base_rev,
        "assignments" => %{"T1" => @assignment},
        "integration" => %{"owner" => "T1", "candidate" => @cand_rev}
      }

      checks = [
        ["sh", "-c", "cd workflow && exec mise exec -- mix test"],
        ["mise", "exec", "--", "mix", "precommit"]
      ]

      # Mock runner that fails the second check
      failing_runner = fn
        ["sh", "-c", _], _path -> {"ok", 0}
        ["mise" | _], _path -> {"precommit failed", 1}
      end

      assert {:error, {:check_failed, _cmd, 1, _output}} =
               Integration.run_gate_checks("/tmp/cand", checks, failing_runner)

      # Fail integration
      assert {:ok, updated_state, updated_assignment} =
               Integration.fail_integration(state, @assignment, "gate precommit failed")

      # Accepted revision is strictly preserved!
      assert updated_state["accepted_revision"] == @base_rev
      assert updated_assignment["status"] == "parked"
      assert updated_state["integration"]["owner"] == nil
    end
  end

  describe "promotion and stop gating" do
    test "successful promotion advances accepted revision" do
      state = %{
        "accepted_revision" => @base_rev,
        "assignments" => %{"T1" => @assignment},
        "integration" => %{"owner" => "T1", "candidate" => @cand_rev}
      }

      assert {:ok, promoted_state, promoted_assignment} =
               Integration.promote_candidate(state, @assignment)

      assert promoted_state["accepted_revision"] == @cand_rev
      assert promoted_assignment["status"] == "integrated"
      assert promoted_state["integration"]["owner"] == nil
    end

    test "candidate cannot be promoted from success evidence observed during or after stop" do
      state = %{
        "accepted_revision" => @base_rev,
        "assignments" => %{"T1" => @assignment},
        "integration" => %{"owner" => "T1", "candidate" => @cand_rev},
        "stop_requested" => true
      }

      assert {:error, msg} = Integration.promote_candidate(state, @assignment)
      assert msg =~ "cannot be promoted from success evidence observed during or after a stop"
    end
  end
end
