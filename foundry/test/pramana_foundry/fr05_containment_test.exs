defmodule PramanaFoundry.FR05ContainmentTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias PramanaFoundry.CLI
  alias PramanaFoundry.Coordinator
  alias PramanaFoundry.Coordinator.State
  alias PramanaFoundry.Integration
  alias PramanaFoundry.PM
  alias PramanaFoundry.Transition

  setup do
    suffix = 16 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
    root = Path.join(System.tmp_dir!(), "fr05-containment-#{suffix}")
    File.mkdir!(root)
    repo = Path.join(root, "repo")
    {base, candidate} = create_repo(repo)
    original = :sys.get_state(Coordinator)

    on_exit(fn ->
      :sys.replace_state(Coordinator, fn _data -> original end)
      File.rm_rf!(root)
    end)

    %{base: base, candidate: candidate, repo: repo, root: root}
  end

  test "public admission rejects auto_approve without changing state or log", ctx do
    log = install_state(State.new(accepted_revision: ctx.base), ctx.root)
    before = Coordinator.state()
    ticket = Map.put(ticket(ctx), "auto_approve", true)

    assert {:error, reason} = Coordinator.enqueue_ticket(ticket)
    assert reason =~ "auto_approve is forbidden"
    assert Coordinator.state() == before
    refute File.exists?(log)
  end

  test "direct ticket CLI rejects forbidden, unknown and malformed options without effects",
       ctx do
    log = install_state(State.new(accepted_revision: ctx.base), ctx.root)
    before = Coordinator.state()
    required = ["--title", "probe", "--priority", "P2"]

    rejected_suffixes = [
      ["--auto_approve", "true"],
      ["--auto_approve", "false"],
      ["--auto-approve", "true"],
      ["--AUTO_APPROVE", "TRUE"],
      ["--auto_approve=true"],
      ["--auto_approve"],
      ["--auto_approve", "true", "--auto_approve", "false"],
      ["--unknown-acceptance-control", "true"],
      ["--title", "duplicate"]
    ]

    Enum.each(rejected_suffixes, fn suffix ->
      assert_raise RuntimeError, fn ->
        capture_io(fn -> CLI.main(["ticket", "create" | required ++ suffix]) end)
      end

      assert Coordinator.state() == before
      refute File.exists?(log)
    end)
  end

  test "replay rejects auto approval at ticket and handoff boundaries", ctx do
    ticket_event =
      event("ticket_enqueued", %{"ticket" => Map.put(ticket(ctx), "auto_approve", false)})

    assert {:error, %{reason: %{reason: :forbidden_auto_approve}}} =
             Transition.rebuild([ticket_event])

    events = [
      event("ticket_enqueued", %{"ticket" => ticket(ctx)}),
      event("assignment_admitted", %{"checkout" => ctx.repo}),
      event("handoff_received", %{"handoff" => handoff(ctx), "auto_approved" => true})
    ]

    assert {:error, %{reason: %{reason: :forbidden_auto_approve}}} =
             Transition.rebuild(events)
  end

  test "runtime and PM boundaries reject injected auto approval", ctx do
    assignment = %{
      "task_id" => "FR05",
      "status" => "queued",
      "ticket" => Map.put(ticket(ctx), "auto_approve", true)
    }

    state =
      State.new(accepted_revision: ctx.base)
      |> put_in(["assignments", "FR05"], assignment)
      |> Map.put("queue", ["FR05"])

    assert {:error, reason} = State.admit_assignment(state, "FR05", "run", "developer")
    assert reason =~ "auto_approve is forbidden"
    assert {:error, reason, ^state} = State.receive_handoff(state, "FR05", handoff(ctx))
    assert reason =~ "auto_approve is forbidden"
    assert {:error, reason, ^state} = State.receive_review(state, "FR05", review(ctx, "run"))
    assert reason =~ "auto_approve is forbidden"

    proposal = %{
      "operation" => "create",
      "ticket" => Map.put(ticket(ctx), "auto_approve", true),
      "reason" => "fixture"
    }

    assert {:error, pm_reason} =
             PM.apply_proposals(State.new(accepted_revision: ctx.base), [proposal])

    assert pm_reason =~ "auto_approve is forbidden"
  end

  test "CLI preserves submitted handoff identity instead of synthesizing it", ctx do
    {:ok, queued} = State.enqueue_ticket(State.new(accepted_revision: ctx.base), ticket(ctx))

    {:ok, _assignment, dispatched} =
      State.admit_assignment(queued, "FR05", "issued-run", "developer")

    install_state(dispatched, ctx.root)
    path = Path.join(ctx.root, "handoff.json")
    File.write!(path, :json.encode(Map.put(handoff(ctx), "run_id", "stale-run")))

    error =
      assert_raise RuntimeError, fn ->
        capture_io(fn -> CLI.main(["handoff", "submit", "FR05", "--handoff-path", path]) end)
      end

    assert Exception.message(error) =~ "run_id mismatch"
    refute get_in(Coordinator.state(), ["assignments", "FR05", "candidate_commit"])
  end

  test "a stale real Git candidate cannot be substituted for checkout HEAD", ctx do
    assignment = reviewed_candidate_state(ctx)["assignments"]["FR05"]
    stale = %{handoff(ctx) | "commit" => ctx.base}

    assert {:error, reason} =
             PramanaFoundry.Assignments.validate_handoff(stale, ticket(ctx), assignment)

    assert reason =~ "Git evidence mismatch"
  end

  test "CLI does not invent a missing candidate or check identity", ctx do
    {:ok, queued} = State.enqueue_ticket(State.new(accepted_revision: ctx.base), ticket(ctx))

    {:ok, _assignment, dispatched} =
      State.admit_assignment(queued, "FR05", "developer-run", "developer")

    install_state(dispatched, ctx.root)
    path = Path.join(ctx.root, "incomplete-handoff.json")

    incomplete =
      handoff(ctx)
      |> Map.delete("commit")
      |> Map.delete("checks")

    File.write!(path, :json.encode(incomplete))

    error =
      assert_raise RuntimeError, fn ->
        capture_io(fn -> CLI.main(["handoff", "submit", "FR05", "--handoff-path", path]) end)
      end

    assert Exception.message(error) =~ "completed handoff fields must be exactly"
    refute get_in(Coordinator.state(), ["assignments", "FR05", "candidate_commit"])
  end

  test "review requires the independently issued reviewer identity", ctx do
    state = reviewed_candidate_state(ctx)
    install_state(state, ctx.root)
    path = Path.join(ctx.root, "review.json")
    File.write!(path, :json.encode(review(ctx, "developer-run")))

    error =
      assert_raise RuntimeError, fn ->
        capture_io(fn -> CLI.main(["review", "submit", "FR05", "--review-path", path]) end)
      end

    assert Exception.message(error) =~ "review run_id mismatch"
    refute get_in(Coordinator.state(), ["assignments", "FR05", "review"])
  end

  test "missing and nonexistent checkout evidence cannot validate submissions", ctx do
    assignment = reviewed_candidate_state(ctx)["assignments"]["FR05"]
    missing_ticket = Map.delete(ticket(ctx), "checkout")

    assert {:error, missing_reason} =
             PramanaFoundry.Assignments.validate_handoff(
               handoff(ctx),
               missing_ticket,
               assignment
             )

    assert missing_reason =~ "requires an explicit checkout"

    nonexistent_ticket = Map.put(ticket(ctx), "checkout", Path.join(ctx.root, "absent"))

    assert {:error, nonexistent_reason} =
             PramanaFoundry.Reviews.validate_artifact(
               review(ctx, "reviewer-run"),
               nonexistent_ticket,
               assignment
             )

    assert nonexistent_reason =~ "checkout does not exist"
  end

  test "integration command changes neither event log, state, nor Git ref", ctx do
    state = reviewed_candidate_state(ctx)
    log = install_state(state, ctx.root)
    File.write!(log, "sentinel\n")
    before_log = File.read!(log)
    before_state = Coordinator.state()
    before_ref = git!(ctx.repo, ["rev-parse", "refs/heads/main"])

    error =
      assert_raise RuntimeError, fn ->
        capture_io(fn -> CLI.main(["ticket", "integrate", "FR05"]) end)
      end

    assert Exception.message(error) =~ "FR-05 containment"
    assert File.read!(log) == before_log
    assert Coordinator.state() == before_state
    assert git!(ctx.repo, ["rev-parse", "refs/heads/main"]) == before_ref
  end

  test "every direct integration boundary refuses before state or runner effects", ctx do
    state = reviewed_candidate_state(ctx)
    log = install_state(state, ctx.root)
    before = :erlang.term_to_binary(state)
    assignment = state["assignments"]["FR05"]
    invented = put_in(assignment, ["ticket", "auto_approve"], true)
    absent = Path.join(ctx.root, "absent-integration-checkout")

    assert {:error, reason} = Integration.acquire_owner(state, "FR05", "invented")
    assert reason =~ "integration is suspended before effects"
    assert {:error, ^reason} = Integration.release_owner(state, "FR05")

    assert {:error, ^reason} =
             Integration.validate_readiness(state, invented, integration_path: absent)

    runner = fn command, path ->
      send(self(), {:integration_runner_invoked, command, path})
      {"unexpected", 0}
    end

    assert {:error, ^reason} =
             Integration.run_gate_checks(absent, [["forged-check"]], runner)

    refute_received {:integration_runner_invoked, _, _}
    assert {:error, ^reason} = Integration.promote_candidate(state, invented)
    assert {:error, ^reason} = Integration.fail_integration(state, invented, "forged failure")
    assert :erlang.term_to_binary(state) == before
    assert :erlang.term_to_binary(Coordinator.state()) == before
    refute File.exists?(log)
    refute File.exists?(absent)
  end

  test "legacy integration success remains explicitly unverified and cannot advance accepted revision",
       ctx do
    events = [
      event("ticket_enqueued", %{"ticket" => ticket(ctx)}),
      event("assignment_admitted", %{"checkout" => ctx.repo}),
      event("integration_started", %{"commit" => ctx.candidate}),
      event("integration_completed", %{"outcome" => "succeeded", "commit" => ctx.candidate})
    ]

    assert {:ok, %{state: state}} = Transition.rebuild(events, accepted_revision: ctx.base)
    assert state["accepted_revision"] == ctx.base
    assert state["assignments"]["FR05"]["status"] == "integration_unverified"

    assert get_in(state, ["assignments", "FR05", "legacy_unverified_integration_claim", "commit"]) ==
             ctx.candidate

    assert get_in(state, ["integration", "legacy_unverified_claims"]) != []
  end

  test "disabled mutable-source watcher invokes no build, watcher, or release child", ctx do
    fake_bin = Path.join(ctx.root, "fake-bin")
    marker = Path.join(ctx.root, "child-invoked")
    File.mkdir!(fake_bin)

    Enum.each(~w(mix fswatch pramana_foundry sleep tail basename dirname), fn name ->
      path = Path.join(fake_bin, name)
      File.write!(path, "#!/bin/sh\nprintf '%s\\n' invoked >> '#{marker}'\nexit 99\n")
      File.chmod!(path, 0o700)
    end)

    script = Path.expand("../../bin/pramana-live.sh", __DIR__)

    {output, status} =
      System.cmd("/bin/bash", [script],
        env: [{"PATH", fake_bin}],
        stderr_to_stdout: true
      )

    assert status == 78
    assert output =~ "mutable source cannot select or activate"
    refute File.exists?(marker)
  end

  defp reviewed_candidate_state(ctx) do
    {:ok, queued} = State.enqueue_ticket(State.new(accepted_revision: ctx.base), ticket(ctx))

    {:ok, _assignment, dispatched} =
      State.admit_assignment(queued, "FR05", "developer-run", "developer")

    updated =
      Map.merge(dispatched["assignments"]["FR05"], %{
        "status" => "review_approved",
        "candidate_commit" => ctx.candidate,
        "handoff" => handoff(ctx),
        "reviewer_run_id" => "reviewer-run"
      })

    put_in(dispatched, ["assignments", "FR05"], updated)
  end

  defp install_state(state, root) do
    log = Path.join(root, "events.jsonl")

    :sys.replace_state(Coordinator, fn data ->
      %{
        data
        | state: state,
          event_log_path: log,
          recovery_error: nil,
          tick_ref: nil,
          require_runtime_owner: false
      }
    end)

    log
  end

  defp ticket(ctx) do
    %{
      "task_id" => "FR05",
      "base_revision" => ctx.base,
      "scope" => ["change.txt"],
      "exclusions" => [],
      "checkout" => ctx.repo,
      "required_checks" => [],
      "review_required_checks" => []
    }
  end

  defp handoff(ctx) do
    %{
      "schema_version" => 1,
      "task_id" => "FR05",
      "run_id" => "developer-run",
      "assigned_base" => ctx.base,
      "commit" => ctx.candidate,
      "changed_files" => ["change.txt"],
      "reproduction_evidence" => %{"source" => "isolated Git fixture"},
      "checks" => [],
      "remaining_risks" => [],
      "status" => "completed",
      "outcome" => "completed"
    }
  end

  defp review(ctx, run_id) do
    %{
      "schema_version" => 1,
      "task_id" => "FR05",
      "run_id" => run_id,
      "commit" => ctx.candidate,
      "verdict" => "approved",
      "findings" => [],
      "checks" => [],
      "remaining_risks" => []
    }
  end

  defp event(name, attributes) do
    %{
      "schema_version" => 1,
      "event" => name,
      "at" => "2026-09-13T00:00:00Z",
      "task_id" => "FR05",
      "run_id" => "developer-run",
      "role" => "developer",
      "attributes" => attributes,
      "evidence" => %{}
    }
  end

  defp create_repo(repo) do
    File.mkdir!(repo)
    git!(repo, ["init", "--initial-branch=main"])
    git!(repo, ["config", "user.name", "FR05 Test"])
    git!(repo, ["config", "user.email", "fr05@example.invalid"])
    File.write!(Path.join(repo, "base.txt"), "base\n")
    git!(repo, ["add", "base.txt"])
    git!(repo, ["commit", "-m", "base"])
    base = git!(repo, ["rev-parse", "HEAD"])
    File.write!(Path.join(repo, "change.txt"), "candidate\n")
    git!(repo, ["add", "change.txt"])
    git!(repo, ["commit", "-m", "candidate"])
    {base, git!(repo, ["rev-parse", "HEAD"])}
  end

  defp git!(repo, argv) do
    case System.cmd("git", argv, cd: repo, stderr_to_stdout: true) do
      {output, 0} -> String.trim(output)
      {output, status} -> flunk("git #{Enum.join(argv, " ")} failed (#{status}): #{output}")
    end
  end
end
