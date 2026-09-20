defmodule PramanaFoundry.Relocation.CrashRecoveryTest do
  use ExUnit.Case, async: false

  alias PramanaFoundry.Relocation
  alias PramanaFoundry.Relocation.{Digest, Journal, PathMap}

  @moduletag :crash_recovery
  @moduletag skip: "mutating relocation recovery is disabled until FR-19B"

  setup do
    root = Path.join(System.tmp_dir!(), "crash-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)

    main_repo = Path.join(root, "pramana-main")
    File.mkdir_p!(main_repo)

    # Init git repo
    {_, 0} = System.cmd("git", ["init"], cd: main_repo)
    {_, 0} = System.cmd("git", ["config", "user.email", "test@pramana.local"], cd: main_repo)
    {_, 0} = System.cmd("git", ["config", "user.name", "Pramana Test"], cd: main_repo)

    File.write!(Path.join(main_repo, "base.txt"), "main base\n")
    {_, 0} = System.cmd("git", ["add", "."], cd: main_repo)
    {_, 0} = System.cmd("git", ["commit", "-m", "init"], cd: main_repo)

    # Create worktree
    worktree = Path.join(root, "pramana-task-wt")
    {_, 0} = System.cmd("git", ["worktree", "add", "-b", "task-branch", worktree], cd: main_repo)
    File.write!(Path.join(worktree, "task_code.txt"), "task code content\n")
    {_, 0} = System.cmd("git", ["add", "."], cd: worktree)
    {_, 0} = System.cmd("git", ["commit", "-m", "task commit"], cd: worktree)

    # Historical artifacts in worktree
    artifact_dir = Path.join(worktree, "artifacts")
    File.mkdir_p!(artifact_dir)

    File.write!(
      Path.join(artifact_dir, "prompt.json"),
      "{\"model\": \"gpt-4o\", \"prompt\": \"hello\"}\n"
    )

    File.write!(
      Path.join(artifact_dir, "handoff.json"),
      "{\"status\": \"completed\", \"run_id\": \"run-1\"}\n"
    )

    # Legacy state directory
    legacy_dir = Path.join(root, "legacy_supervisor_state")
    File.mkdir_p!(legacy_dir)
    File.write!(Path.join(legacy_dir, "supervisor.json"), "{\"supervisor\": \"running\"}\n")

    dest_root = Path.join(root, "relocated")

    on_exit(fn -> File.rm_rf(root) end)

    {:ok,
     root: root,
     main_repo: main_repo,
     worktree: worktree,
     legacy_dir: legacy_dir,
     dest_root: dest_root}
  end

  @boundaries [
    :after_prepare,
    :before_move,
    :after_move,
    :after_digest_verify,
    :after_complete,
    :after_path_map
  ]

  for boundary <- @boundaries do
    @boundary boundary

    test "crash injection at boundary #{boundary}: deterministic resumption and SHA-256 invariance",
         %{
           main_repo: main_repo,
           worktree: worktree,
           legacy_dir: legacy_dir,
           dest_root: dest_root
         } do
      boundary = @boundary

      # Take pre-move snapshots of both directories
      {:ok, wt_pre_snap} = Digest.snapshot(worktree)
      {:ok, leg_pre_snap} = Digest.snapshot(legacy_dir)

      dest_wt = Path.join(dest_root, "wt")
      dest_leg = Path.join(dest_root, "legacy")
      journal_path = Path.join(dest_root, "journal-resume-#{boundary}.jsonl")
      path_map_file = Path.join(dest_root, "path_map-resume-#{boundary}.json")

      plan_opts = [
        paths: [worktree, legacy_dir],
        destinations: %{worktree => dest_wt, legacy_dir => dest_leg},
        original_checkout: main_repo,
        journal_path: journal_path,
        path_map_file: path_map_file,
        crash_at: boundary
      ]

      # Execute with injected crash at boundary
      assert {:error, {:injected_crash, ^boundary}} = Relocation.execute(plan_opts)

      # Journal exists and recorded entries
      assert File.exists?(journal_path)

      # Resume from crash
      assert {:ok, resume_result} = Relocation.resume(journal_path, path_map_file: path_map_file)
      assert resume_result.status == :completed

      # Verify destination directories exist
      assert File.exists?(dest_wt)
      assert File.exists?(dest_leg)

      # Invariant 3: SHA-256 byte-for-byte invariance verified at destination
      assert {:ok, _} = Digest.verify(wt_pre_snap, dest_wt)
      assert {:ok, _} = Digest.verify(leg_pre_snap, dest_leg)

      # PathMap resolves old paths to new paths
      assert File.exists?(path_map_file)
      assert {:ok, pm} = PathMap.load(path_map_file)

      assert PathMap.resolve(pm, Path.join(worktree, "artifacts/prompt.json")) ==
               Path.join(dest_wt, "artifacts/prompt.json")

      assert PathMap.resolve(pm, Path.join(legacy_dir, "supervisor.json")) ==
               Path.join(dest_leg, "supervisor.json")
    end

    test "crash injection at boundary #{boundary}: clean rollback without leaving orphaned state",
         %{
           main_repo: main_repo,
           worktree: worktree,
           legacy_dir: legacy_dir,
           dest_root: dest_root
         } do
      boundary = @boundary

      # Take pre-move snapshots
      {:ok, wt_pre_snap} = Digest.snapshot(worktree)
      {:ok, leg_pre_snap} = Digest.snapshot(legacy_dir)

      dest_wt = Path.join(dest_root, "wt_rb")
      dest_leg = Path.join(dest_root, "legacy_rb")
      journal_path = Path.join(dest_root, "journal-rollback-#{boundary}.jsonl")
      path_map_file = Path.join(dest_root, "path_map-rollback-#{boundary}.json")

      plan_opts = [
        paths: [worktree, legacy_dir],
        destinations: %{worktree => dest_wt, legacy_dir => dest_leg},
        original_checkout: main_repo,
        journal_path: journal_path,
        path_map_file: path_map_file,
        crash_at: boundary
      ]

      # Execute with crash injection
      assert {:error, {:injected_crash, ^boundary}} = Relocation.execute(plan_opts)

      # Rollback from crash
      assert {:ok, rb_result} = Relocation.rollback(journal_path, path_map_file: path_map_file)
      assert rb_result.status == :rolled_back

      # Sources are restored
      assert File.exists?(worktree)
      assert File.exists?(legacy_dir)

      # Byte-for-byte SHA-256 invariance of restored sources
      assert {:ok, _} = Digest.verify(wt_pre_snap, worktree)
      assert {:ok, _} = Digest.verify(leg_pre_snap, legacy_dir)

      # Destinations do not leave orphaned files
      refute File.exists?(Path.join(dest_wt, "task_code.txt"))
      refute File.exists?(Path.join(dest_leg, "supervisor.json"))

      # Journal records rollback
      {:ok, journal_state} = Journal.reconstruct_state(journal_path)
      assert length(journal_state.in_flight) == 0
    end
  end
end
