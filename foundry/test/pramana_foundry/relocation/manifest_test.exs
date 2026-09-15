defmodule PramanaFoundry.Relocation.ManifestTest do
  use ExUnit.Case, async: true

  alias PramanaFoundry.Relocation.Manifest

  @moduletag :manifest

  setup do
    root = Path.join(System.tmp_dir!(), "manifest-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)

    # 1. Main repo
    main_repo = Path.join(root, "pramana-main")
    File.mkdir_p!(main_repo)
    {_, 0} = System.cmd("git", ["init"], cd: main_repo)
    {_, 0} = System.cmd("git", ["config", "user.email", "test@pramana.local"], cd: main_repo)
    {_, 0} = System.cmd("git", ["config", "user.name", "Pramana Test"], cd: main_repo)

    # Base commit with .gitignore
    File.write!(Path.join(main_repo, ".gitignore"), "*.ignored\n")
    File.write!(Path.join(main_repo, "base.txt"), "base file\n")
    {_, 0} = System.cmd("git", ["add", "."], cd: main_repo)
    {_, 0} = System.cmd("git", ["commit", "-m", "init"], cd: main_repo)

    # Make main repo have dirty tracked, untracked, and ignored files
    File.write!(Path.join(main_repo, "base.txt"), "modified base file content\n")
    File.write!(Path.join(main_repo, "untracked.txt"), "untracked content\n")
    File.write!(Path.join(main_repo, "sample.ignored"), "ignored content\n")

    # Symlink
    File.ln_s(Path.join(main_repo, "base.txt"), Path.join(main_repo, "base_symlink.txt"))
    # Broken symlink
    File.ln_s(Path.join(main_repo, "nonexistent.txt"), Path.join(main_repo, "broken_symlink.txt"))

    # 2. Linked worktree
    worktree = Path.join(root, "pramana-task-01")

    {_, 0} =
      System.cmd("git", ["worktree", "add", "-b", "task-branch-01", worktree], cd: main_repo)

    File.write!(Path.join(worktree, "task_work.txt"), "some work\n")
    {_, 0} = System.cmd("git", ["add", "task_work.txt"], cd: worktree)
    {_, 0} = System.cmd("git", ["commit", "-m", "task commit"], cd: worktree)
    File.write!(Path.join(worktree, "task_work.txt"), "dirty worktree bytes\n")
    File.write!(Path.join(worktree, "untracked_worktree.txt"), "untracked worktree\n")

    # 3. Legacy supervisor state directory
    legacy_state = Path.join(root, ".pramana-supervisor")
    File.mkdir_p!(legacy_state)
    File.write!(Path.join(legacy_state, "state.json"), "{\"status\": \"running\"}\n")

    # 4. Colliding destination for task-01
    dest_root = Path.join(root, "destinations")
    File.mkdir_p!(Path.join(dest_root, "pramana-task-01"))
    File.write!(Path.join(dest_root, "pramana-task-01/existing.txt"), "collision file")

    on_exit(fn -> File.rm_rf(root) end)

    {:ok,
     root: root,
     main_repo: main_repo,
     worktree: worktree,
     legacy_state: legacy_state,
     dest_root: dest_root}
  end

  test "analyzes full inventory including git metadata, dirty bytes, symlinks, live handles, and collisions",
       %{
         root: _root,
         main_repo: main_repo,
         worktree: worktree,
         legacy_state: legacy_state,
         dest_root: dest_root
       } do
    mock_handles = %{
      worktree => [%{pid: 1234, path: worktree}]
    }

    {:ok, manifest} =
      Manifest.build(
        paths: [main_repo, worktree, legacy_state],
        destination_root: dest_root,
        original_checkout: main_repo,
        mock_live_handles: mock_handles,
        destination_headroom_bytes: 50_000_000
      )

    assert length(manifest.directories) == 3

    # Main repo analysis
    main_item = Enum.find(manifest.directories, &(&1.path == main_repo))
    assert main_item.kind == :original_checkout
    assert main_item.git.is_git == true
    assert main_item.git.branch == "main" or main_item.git.branch == "master"
    assert main_item.git.dirty_tracked.count >= 1
    assert main_item.git.dirty_tracked.bytes > 0
    assert main_item.git.untracked.count >= 1
    assert main_item.git.ignored.count >= 1
    assert main_item.safety.is_original_checkout == true
    assert main_item.safety.movable == false
    assert :original_checkout in main_item.safety.reasons

    # Symlink verification in main repo
    assert Enum.any?(main_item.symlinks, &(&1.path == "base_symlink.txt" and not &1.broken))
    assert Enum.any?(main_item.symlinks, &(&1.path == "broken_symlink.txt" and &1.broken))

    # Worktree analysis
    wt_item = Enum.find(manifest.directories, &(&1.path == worktree))
    assert wt_item.kind == :worktree
    assert wt_item.git.is_git == true
    assert wt_item.git.branch == "task-branch-01"
    assert wt_item.git.dirty_tracked.count >= 1
    assert wt_item.git.dirty_tracked.bytes > 0
    assert wt_item.git.untracked.count >= 1
    # Live handles detected
    assert length(wt_item.live_handles) == 1
    assert hd(wt_item.live_handles).pid == 1234
    # Destination collision detected because dest_root/pramana-task-01 exists with files
    assert wt_item.destination.collision == true
    assert wt_item.safety.movable == false
    assert :destination_collision in wt_item.safety.reasons

    # Legacy state analysis
    legacy_item = Enum.find(manifest.directories, &(&1.path == legacy_state))
    assert legacy_item.kind == :legacy_state
    assert legacy_item.git.is_git == false
    assert legacy_item.safety.movable == true

    # Output formatting and serialization
    map = Manifest.to_map(manifest)
    assert is_map(map)
    assert map["can_relocate"] == false
    assert map["sufficient_headroom"] == true

    formatted = Manifest.format(manifest)
    assert is_binary(formatted)
    assert String.contains?(formatted, "Pramana Workspace Relocation Inventory Manifest")
    assert String.contains?(formatted, "pramana-task-01")
    assert String.contains?(formatted, "pramana-main")
  end

  test "detects insufficient destination headroom", %{
    main_repo: main_repo,
    worktree: worktree,
    dest_root: dest_root
  } do
    # Dest that doesn't collide
    clean_dest_root = Path.join(dest_root, "clean_dest")

    {:ok, manifest} =
      Manifest.build(
        paths: [worktree],
        destinations: %{worktree => Path.join(clean_dest_root, "wt")},
        original_checkout: main_repo,
        destination_headroom_bytes: 5
      )

    refute manifest.sufficient_headroom
    refute manifest.can_relocate

    assert Enum.any?(
             manifest.warnings,
             &String.contains?(&1, "Insufficient destination headroom")
           )
  end
end
