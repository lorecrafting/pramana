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

  test "rebuild rejects prompt intents whose durable run or role was not admitted" do
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

    assert {:error, %{reason: %{reason: :run_identity_mismatch}}} =
             Transition.rebuild([admitted, wrong_run])

    wrong_role = %{prompt | "role" => "reviewer"}

    assert {:error, %{reason: %{reason: :role_identity_mismatch}}} =
             Transition.rebuild([admitted, wrong_role])
  end

  test "rebuild rejects known authority events with missing identity" do
    for event <- ~w(assignment_admitted prompt_intent) do
      incomplete = %{
        "schema_version" => 1,
        "event" => event,
        "at" => "2026-09-08T00:00:00Z",
        "attributes" => %{},
        "evidence" => %{}
      }

      assert {:error, _reason} = Transition.rebuild([incomplete])
    end
  end
end
