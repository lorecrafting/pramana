defmodule PramanaFoundry.RelocationTest do
  use ExUnit.Case, async: false

  alias PramanaFoundry.Relocation
  alias PramanaFoundry.Relocation.{Digest, LocalExclude, PathMap}

  @moduletag :relocation

  setup do
    root = Path.join(System.tmp_dir!(), "reloc-test-#{System.unique_integer([:positive])}")
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

    # Historical artifacts
    artifact_dir = Path.join(worktree, "artifacts")
    File.mkdir_p!(artifact_dir)
    File.write!(Path.join(artifact_dir, "prompt.json"), "{\"prompt\": \"evidence\"}\n")

    # Legacy state directory
    legacy_dir = Path.join(root, ".pramana-supervisor")
    File.mkdir_p!(legacy_dir)
    File.write!(Path.join(legacy_dir, "supervisor.json"), "{\"status\": \"idle\"}\n")

    dest_root = Path.join(root, "relocated")

    on_exit(fn -> File.rm_rf(root) end)

    {:ok,
     root: root,
     main_repo: main_repo,
     worktree: worktree,
     legacy_dir: legacy_dir,
     dest_root: dest_root}
  end

  test "plan creates structured plan from inventory", %{
    main_repo: main_repo,
    worktree: worktree,
    legacy_dir: legacy_dir,
    dest_root: dest_root
  } do
    {:ok, plan} =
      Relocation.plan(
        paths: [main_repo, worktree, legacy_dir],
        destination_root: dest_root,
        original_checkout: main_repo
      )

    assert length(plan.steps) == 2
    step_sources = Enum.map(plan.steps, & &1.source)
    assert worktree in step_sources
    assert legacy_dir in step_sources
    refute main_repo in step_sources
  end

  @tag skip: "mutating relocation is disabled until FR-19B"
  test "execute performs full end-to-end relocation with byte invariance, runtime protection, and path mapping",
       %{
         main_repo: main_repo,
         worktree: worktree,
         legacy_dir: legacy_dir,
         dest_root: dest_root
       } do
    # Pre-move snapshots
    {:ok, wt_snap} = Digest.snapshot(worktree)
    {:ok, leg_snap} = Digest.snapshot(legacy_dir)

    dest_wt = Path.join(dest_root, "pramana-task-wt")
    dest_leg = Path.join(dest_root, ".pramana-supervisor")
    journal_path = Path.join(dest_root, "journal.jsonl")
    path_map_file = Path.join(dest_root, "path_map.json")

    opts = [
      paths: [main_repo, worktree, legacy_dir],
      destinations: %{worktree => dest_wt, legacy_dir => dest_leg},
      original_checkout: main_repo,
      journal_path: journal_path,
      path_map_file: path_map_file,
      unprotect_on_complete: true
    ]

    assert {:ok, result} = Relocation.execute(opts)
    assert result.status == :completed
    assert length(result.completed_steps) == 2

    # Verify destination files and SHA-256 byte-for-byte invariance
    assert {:ok, _} = Digest.verify(wt_snap, dest_wt)
    assert {:ok, _} = Digest.verify(leg_snap, dest_leg)

    # PathMap resolution
    assert PathMap.resolve(result.path_map, Path.join(worktree, "artifacts/prompt.json")) ==
             Path.join(dest_wt, "artifacts/prompt.json")

    assert PathMap.resolve(result.path_map, Path.join(legacy_dir, "supervisor.json")) ==
             Path.join(dest_leg, "supervisor.json")

    # Original checkout runtime root protection was verified and unprotect was called
    refute LocalExclude.protected?(main_repo)

    # Original checkout files are completely untouched
    assert File.read!(Path.join(main_repo, "base.txt")) == "main base\n"
  end
end
