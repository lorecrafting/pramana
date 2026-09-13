# Live test script — run via: mix run foundry/bin/live_test.exs
CHECKOUT = "/tmp/pramana-live-test"
BASE_REV = "42475ec5f6a62040413afb4bdff97e6ba1e39752"
TASK_COMMIT = "38715b80156be063beb8eed38e3953e7817922e9"

IO.puts("=== 1. Enqueueing LIVE-1 ===")
:ok = PramanaFoundry.Coordinator.enqueue_ticket(%{
  "task_id" => "LIVE-1",
  "base_revision" => BASE_REV,
  "scope" => ["*"],
  "exclusions" => [],
  "checkout" => CHECKOUT,
  "required_checks" => [["echo", "ok"]],
  "review_required_checks" => [["echo", "ok"]]
})

IO.puts("=== 2. Admitting LIVE-1 ===")
{:ok, _} = PramanaFoundry.Coordinator.admit_assignment("LIVE-1", "live-run-1", "developer")

IO.puts("=== 3. Submitting handoff ===")
handoff = %{
  "schema_version" => 1,
  "task_id" => "LIVE-1",
  "run_id" => "live-run-1",
  "assigned_base" => BASE_REV,
  "commit" => TASK_COMMIT,
  "changed_files" => ["task.txt"],
  "reproduction_evidence" => %{},
  "checks" => [%{"command" => ["echo", "ok"], "exit_code" => 0}],
  "remaining_risks" => [],
  "status" => "completed",
  "outcome" => "Test task completed"
}
{:ok, _} = PramanaFoundry.Coordinator.receive_handoff("LIVE-1", handoff, skip_git_checks: true)

IO.puts("=== 4. After handoff ===")
a = get_in(PramanaFoundry.Coordinator.state(), ["assignments", "LIVE-1"])
IO.puts("  status: #{a["status"]}")
IO.puts("  reviewer_run_id: #{a["reviewer_run_id"] || "(not set)"}")

IO.puts("=== 5. Submitting review (as reviewer) ===")
review = %{
  "schema_version" => 1,
  "run_id" => a["reviewer_run_id"] || "live-run-1",
  "task_id" => "LIVE-1",
  "commit" => TASK_COMMIT,
  "verdict" => "approved",
  "findings" => [],
  "remaining_risks" => [],
  "checks" => [%{"command" => ["echo", "ok"], "exit_code" => 0}]
}

case PramanaFoundry.Coordinator.receive_review("LIVE-1", review, skip_git_checks: true) do
  {:ok, assignment} ->
    IO.puts("  ✓ Review accepted! Status: #{assignment["status"]}")
  {:error, reason} ->
    IO.puts("  ✗ Review rejected: #{reason}")
end

IO.puts("=== 6. Integrating ===")
mock_runner = fn _cmd, _path -> {"ok", 0} end
case PramanaFoundry.Coordinator.integrate("LIVE-1", runner_fn: mock_runner, skip_git_checks: true) do
  {:ok, promoted} ->
    IO.puts("  ✓ Integrated! Status: #{promoted["status"]}")
  {:error, reason} ->
    IO.puts("  ✗ Integration failed: #{reason}")
end

IO.puts("=== 7. Final state ===")
a = get_in(PramanaFoundry.Coordinator.state(), ["assignments", "LIVE-1"])
IO.puts("  status: #{a["status"]}")
IO.puts("  accepted_revision: #{PramanaFoundry.Coordinator.state()["accepted_revision"]}")

IO.puts("")
IO.puts("=== LIVE-1 pipeline complete ===")