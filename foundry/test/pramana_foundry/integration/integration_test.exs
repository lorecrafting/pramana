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

  describe "suspended public boundary" do
    test "owner acquisition and release are effect-free refusals" do
      state = %{"accepted_revision" => @base_rev, "integration" => %{}}

      assert {:error, message} = Integration.acquire_owner(state, "T1", @cand_rev)
      assert message =~ "integration is suspended before effects"
      assert {:error, ^message} = Integration.release_owner(state, "T1")
      assert state == %{"accepted_revision" => @base_rev, "integration" => %{}}
    end
  end

  describe "readiness validation" do
    test "pause blocks promotion" do
      state = %{"accepted_revision" => @base_rev, "paused" => true}
      assert {:error, msg} = Integration.validate_readiness(state, @assignment)
      assert msg =~ "integration is suspended before effects"
    end

    test "stop blocks promotion" do
      state = %{"accepted_revision" => @base_rev, "stop_requested" => true}
      assert {:error, msg} = Integration.validate_readiness(state, @assignment)
      assert msg =~ "integration is suspended before effects"
    end

    test "stale candidate base revision parks/rejects" do
      state = %{"accepted_revision" => "new-advanced-base-rev"}
      assert {:error, msg} = Integration.validate_readiness(state, @assignment)
      assert msg =~ "integration is suspended before effects"
    end
  end

  describe "combined gate checks and failure" do
    test "gate checks and failure mutation refuse before runner or state effects" do
      state = %{
        "accepted_revision" => @base_rev,
        "assignments" => %{"T1" => @assignment},
        "integration" => %{"owner" => "T1", "candidate" => @cand_rev}
      }

      checks = [
        ["sh", "-c", "cd workflow && exec mise exec -- mix test"],
        ["mise", "exec", "--", "mix", "precommit"]
      ]

      runner = fn command, path ->
        send(self(), {:runner_invoked, command, path})
        {"unexpected", 0}
      end

      assert {:error, message} = Integration.run_gate_checks("/tmp/cand", checks, runner)
      assert message =~ "integration is suspended before effects"
      refute_received {:runner_invoked, _, _}

      assert {:error, ^message} =
               Integration.fail_integration(state, @assignment, "gate precommit failed")

      assert state["accepted_revision"] == @base_rev
      assert state["assignments"]["T1"] == @assignment
      assert state["integration"]["owner"] == "T1"
    end
  end

  describe "promotion and stop gating" do
    test "legacy memory-only promotion is suspended without advancing accepted revision" do
      state = %{
        "accepted_revision" => @base_rev,
        "assignments" => %{"T1" => @assignment},
        "integration" => %{"owner" => "T1", "candidate" => @cand_rev}
      }

      assert {:error, message} = Integration.promote_candidate(state, @assignment)
      assert message =~ "integration is suspended before effects"
      assert state["accepted_revision"] == @base_rev
      assert state["assignments"]["T1"]["status"] == "review_approved"
      assert state["integration"]["owner"] == "T1"
    end

    test "candidate cannot be promoted from success evidence observed during or after stop" do
      state = %{
        "accepted_revision" => @base_rev,
        "assignments" => %{"T1" => @assignment},
        "integration" => %{"owner" => "T1", "candidate" => @cand_rev},
        "stop_requested" => true
      }

      assert {:error, msg} = Integration.promote_candidate(state, @assignment)
      assert msg =~ "integration is suspended before effects"
    end
  end
end
