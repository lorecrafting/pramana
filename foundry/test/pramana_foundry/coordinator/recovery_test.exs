defmodule PramanaFoundry.RecoveryTest do
  use ExUnit.Case, async: true

  alias PramanaFoundry.Assignments
  alias PramanaFoundry.Integration
  alias PramanaFoundry.Transition

  @commit "1111222233334444555566667777888899990000"

  test "deterministic restart recovery prevents duplicate prompt and duplicate dispatch" do
    # 1. Admit assignment event
    admit_event = %{
      "schema_version" => 1,
      "event" => "assignment_admitted",
      "task_id" => "T-REC-1",
      "run_id" => "run-rec-1",
      "role" => "developer",
      "at" => "2026-09-10T10:00:00Z",
      "attributes" => %{},
      "evidence" => %{}
    }

    # 2. Prompt intent event
    prompt_event = %{
      "schema_version" => 1,
      "event" => "prompt_intent",
      "task_id" => "T-REC-1",
      "run_id" => "run-rec-1",
      "role" => "developer",
      "at" => "2026-09-10T10:00:01Z",
      "attributes" => %{},
      "evidence" => %{}
    }

    # Rebuilding Transition projection from records
    assert {:ok, %{projection: proj, state: recovered_state}} = Transition.rebuild([admit_event, prompt_event])

    # Planning prompt again after restart returns reconcile_prompt effect, NOT deliver_prompt!
    assert {:ok, %{effects: [%{type: :reconcile_prompt, run_id: "run-rec-1"}]}} =
             Transition.plan(proj, %{
               action: :prompt,
               task_id: "T-REC-1",
               run_id: "run-rec-1",
               role: "developer",
               at: "2026-09-10T10:00:02Z"
             })

    # Planning admit again fails as duplicate assignment
    assert {:error, :duplicate_assignment} =
             Transition.plan(proj, %{
               action: :admit,
               task_id: "T-REC-1",
               run_id: "run-rec-1",
               role: "developer",
               at: "2026-09-10T10:00:03Z"
             })

    # Full state reconstruction from records recovers assignment without re-dispatching
    assignment = recovered_state["assignments"]["T-REC-1"]
    assert assignment["status"] == "prompting"
    assert assignment["run_id"] == "run-rec-1"
  end

  test "dirty task checkout is refused on handoff and prevents promotion" do
    # Create a temporary git directory with an uncommitted change to simulate dirty checkout
    tmp_dir =
      Path.join(System.tmp_dir!(), "pramana-dirty-checkout-#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    System.cmd("git", ["init"], cd: tmp_dir)
    System.cmd("git", ["config", "user.email", "test@pramana.local"], cd: tmp_dir)
    System.cmd("git", ["config", "user.name", "Pramana Test"], cd: tmp_dir)

    # Initial commit as base
    File.write!(Path.join(tmp_dir, "file.txt"), "base")
    System.cmd("git", ["add", "file.txt"], cd: tmp_dir)
    System.cmd("git", ["commit", "-m", "base"], cd: tmp_dir)
    {base_head, 0} = System.cmd("git", ["rev-parse", "HEAD"], cd: tmp_dir)
    base = String.trim(base_head)

    # Second commit as task work
    File.write!(Path.join(tmp_dir, "file.txt"), "modified")
    System.cmd("git", ["commit", "-am", "task work"], cd: tmp_dir)
    {task_head, 0} = System.cmd("git", ["rev-parse", "HEAD"], cd: tmp_dir)
    task_commit = String.trim(task_head)

    # Make the working tree dirty (uncommitted change)
    File.write!(Path.join(tmp_dir, "file.txt"), "uncommitted dirty content")

    ticket = %{
      "task_id" => "T-DIRTY",
      "base_revision" => base,
      "checkout" => tmp_dir,
      "scope" => ["file.txt"],
      "exclusions" => [],
      "required_checks" => []
    }

    assignment = %{
      "run_id" => "run-dirty-1",
      "ticket" => ticket
    }

    handoff = %{
      "schema_version" => 1,
      "task_id" => "T-DIRTY",
      "run_id" => "run-dirty-1",
      "assigned_base" => base,
      "commit" => task_commit,
      "changed_files" => ["file.txt"],
      "reproduction_evidence" => %{"before" => "fail", "after" => "pass"},
      "checks" => [],
      "remaining_risks" => [],
      "status" => "completed",
      "outcome" => "done"
    }

    # Handoff validation directly detects dirty checkout and refuses
    assert {:error, msg} =
             Assignments.validate_handoff(handoff, ticket, assignment, skip_git_checks: false)

    assert msg =~ "task checkout has uncommitted or untracked changes"
  end

  test "integration singleton ownership is recovered and prevents double-promotion" do
    integration_event = %{
      "schema_version" => 1,
      "event" => "integration_started",
      "task_id" => "T-INT-1",
      "at" => "2026-09-10T11:00:00Z",
      "attributes" => %{"commit" => @commit},
      "evidence" => %{}
    }

    assert {:ok, %{state: state}} = Transition.rebuild([integration_event])
    assert state["integration"]["owner"] == "T-INT-1"
    assert state["integration"]["candidate"] == @commit

    # Another candidate cannot integrate
    assert {:error, :integration_busy} =
             Integration.acquire_owner(state, "T-INT-2", "other-commit")
  end
end
