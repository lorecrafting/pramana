defmodule PramanaFoundry.TransitionTest do
  use ExUnit.Case, async: true

  alias PramanaFoundry.Transition

  test "returns checkpoint-first intents and rebuilds projections from durable records" do
    assert {:ok, %{projection: empty_proj}} = Transition.rebuild([])

    assert {:ok, %{checkpoint: admitted, effects: []}} =
             Transition.plan(empty_proj, %{
               action: :admit,
               task_id: "T1",
               run_id: "run-1",
               role: "developer",
               at: "2026-09-08T00:00:00Z"
             })

    assert {:ok, %{projection: proj}} = Transition.rebuild([admitted])

    assert {:ok, %{checkpoint: prompted, effects: [%{type: :deliver_prompt, run_id: "run-1"}]}} =
             Transition.plan(proj, %{
               action: :prompt,
               task_id: "T1",
               run_id: "run-1",
               role: "developer",
               at: "2026-09-08T00:00:01Z"
             })

    assert {:ok, %{projection: prompted_proj}} = Transition.rebuild([admitted, prompted])

    assert {:ok, %{effects: [%{type: :reconcile_prompt, run_id: "run-1"}]}} =
             Transition.plan(prompted_proj, %{
               action: :prompt,
               task_id: "T1",
               run_id: "run-1",
               role: "developer",
               at: "2026-09-08T00:00:02Z"
             })
  end

  test "duplicate and mismatched assignment identities fail closed" do
    assert {:ok, %{projection: empty_proj}} = Transition.rebuild([])

    assert {:ok, %{checkpoint: admitted}} =
             Transition.plan(empty_proj, %{
               action: :admit,
               task_id: "T1",
               run_id: "run-1",
               role: "developer",
               at: "2026-09-08T00:00:00Z"
             })

    assert {:ok, %{projection: proj}} = Transition.rebuild([admitted])

    assert {:error, :duplicate_assignment} =
             Transition.plan(proj, %{
               action: :admit,
               task_id: "T1",
               run_id: "run-1",
               role: "developer",
               at: "2026-09-08T00:00:01Z"
             })

    assert {:error, :task_identity_mismatch} =
             Transition.plan(proj, %{
               action: :admit,
               task_id: "T1",
               run_id: "run-2",
               role: "developer",
               at: "2026-09-08T00:00:02Z"
             })
  end

  test "prompt identity must match the role admitted in durable state" do
    assert {:ok, %{projection: empty_proj}} = Transition.rebuild([])

    assert {:ok, %{checkpoint: admitted}} =
             Transition.plan(empty_proj, %{
               action: :admit,
               task_id: "T1",
               run_id: "run-1",
               role: "developer",
               at: "2026-09-08T00:00:00Z"
             })

    assert {:ok, %{projection: proj}} = Transition.rebuild([admitted])
    assert proj.assignments["T1"] == {"run-1", "developer"}

    assert {:error, :role_identity_mismatch} =
             Transition.plan(proj, %{
               action: :prompt,
               task_id: "T1",
               run_id: "run-1",
               role: "reviewer",
               at: "2026-09-08T00:00:01Z"
             })
  end

  test "rebuild skips prompt intents whose durable run or role was not admitted" do
    admitted = %{
      "schema_version" => 1,
      "event" => "assignment_admitted",
      "at" => "2026-09-08T00:00:00Z",
      "task_id" => "T1",
      "run_id" => "run-1",
      "role" => "developer",
      "attributes" => %{},
      "evidence" => %{}
    }

    prompt = %{admitted | "event" => "prompt_intent", "at" => "2026-09-08T00:00:01Z"}
    wrong_run = %{prompt | "run_id" => "run-2"}

    # Mismatched prompt events are skipped rather than halting rebuild
    assert {:ok, %{projection: proj}} = Transition.rebuild([admitted, wrong_run])
    assert proj.assignments["T1"] == {"run-1", "developer"}
    # The mismatched prompt_intent was skipped; only the admission event is in the list
    assert length(proj.events) == 1

    wrong_role = %{prompt | "role" => "reviewer"}

    assert {:ok, %{projection: proj2}} = Transition.rebuild([admitted, wrong_role])
    assert proj2.assignments["T1"] == {"run-1", "developer"}
    assert length(proj2.events) == 1
  end

test "rebuild skips known authority events with missing identity" do
    for event <- ~w(assignment_admitted prompt_intent) do
      incomplete = %{
        "schema_version" => 1,
        "event" => event,
        "at" => "2026-09-08T00:00:00Z",
        "attributes" => %{},
        "evidence" => %{}
      }

      # Authority events without identity are silently skipped; rebuild continues
      assert {:ok, %{projection: proj}} = Transition.rebuild([incomplete])
      assert proj.events == []
    end
  end
end
