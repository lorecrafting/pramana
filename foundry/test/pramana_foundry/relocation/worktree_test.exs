defmodule PramanaFoundry.Relocation.WorktreeTest do
  use ExUnit.Case, async: true

  alias PramanaFoundry.Relocation.Worktree

  @moduletag :worktree

  setup do
    base_tmp = Path.join(System.tmp_dir!(), "worktree-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(base_tmp)

    main_repo = Path.join(base_tmp, "main_repo")
    File.mkdir_p!(main_repo)

    # Initialize main repo
    {_, 0} = System.cmd("git", ["init"], cd: main_repo)
    {_, 0} = System.cmd("git", ["config", "user.email", "test@pramana.local"], cd: main_repo)
    {_, 0} = System.cmd("git", ["config", "user.name", "Pramana Test"], cd: main_repo)

    File.write!(Path.join(main_repo, "base.txt"), "base content\n")
    {_, 0} = System.cmd("git", ["add", "base.txt"], cd: main_repo)
    {_, 0} = System.cmd("git", ["commit", "-m", "initial commit"], cd: main_repo)

    # Add dirty tracked and untracked files to original checkout to guarantee they are never touched
    File.write!(Path.join(main_repo, "base.txt"), "modified base content\n")
    File.write!(Path.join(main_repo, "untracked_main.txt"), "untracked in main\n")

    # Create a git worktree
    worktree_path = Path.join(base_tmp, "task_worktree")

    {_, 0} =
      System.cmd("git", ["worktree", "add", "-b", "task-branch", worktree_path], cd: main_repo)

    File.write!(Path.join(worktree_path, "task_file.txt"), "task content\n")

    on_exit(fn -> File.rm_rf(base_tmp) end)

    {:ok, base_tmp: base_tmp, main_repo: main_repo, worktree_path: worktree_path}
  end

  test "correctly identifies worktree vs original checkout", %{
    main_repo: main_repo,
    worktree_path: worktree_path
  } do
    assert Worktree.original_checkout?(main_repo)
    refute Worktree.worktree?(main_repo)

    assert Worktree.worktree?(worktree_path)
    refute Worktree.original_checkout?(worktree_path)
  end

  test "refuses to move original checkout", %{
    base_tmp: base_tmp,
    main_repo: main_repo
  } do
    dest = Path.join(base_tmp, "moved_main")
    assert {:error, :cannot_move_original_checkout} = Worktree.move(main_repo, dest)
  end

  test "refuses to move root chat working directory", %{
    base_tmp: base_tmp,
    worktree_path: worktree_path
  } do
    dest = Path.join(base_tmp, "moved_worktree")

    assert {:error, :cannot_move_root_chat_directory} =
             Worktree.move(worktree_path, dest, root_chat_dir: worktree_path)
  end

  test "refuses to move when destination collides with existing files", %{
    base_tmp: base_tmp,
    worktree_path: worktree_path
  } do
    dest = Path.join(base_tmp, "colliding_dest")
    File.mkdir_p!(dest)
    File.write!(Path.join(dest, "existing.txt"), "already here")

    expanded_dest = Path.expand(dest)
    assert {:error, {:destination_collision, ^expanded_dest}} = Worktree.move(worktree_path, dest)
  end

  test "moves worktree via git worktree move while preserving original checkout intact", %{
    base_tmp: base_tmp,
    main_repo: main_repo,
    worktree_path: worktree_path
  } do
    dest = Path.join(base_tmp, "relocated_worktree")

    assert {:ok, ^dest} = Worktree.move(worktree_path, dest, original_checkout: main_repo)
    assert Worktree.worktree?(dest)
    refute File.exists?(worktree_path)
    assert File.exists?(Path.join(dest, "task_file.txt"))

    # Verify original checkout was completely untouched
    assert File.read!(Path.join(main_repo, "base.txt")) == "modified base content\n"
    assert File.read!(Path.join(main_repo, "untracked_main.txt")) == "untracked in main\n"

    # Verify git worktree list lists the new destination
    {list_out, 0} = System.cmd("git", ["worktree", "list"], cd: main_repo)
    assert String.contains?(list_out, dest)
    refute String.contains?(list_out, worktree_path)

    # Rollback worktree move
    assert {:ok, ^worktree_path} = Worktree.rollback_move(dest, worktree_path)
    assert Worktree.worktree?(worktree_path)
    refute File.exists?(dest)

    # Original checkout still intact
    assert File.read!(Path.join(main_repo, "base.txt")) == "modified base content\n"
    assert File.read!(Path.join(main_repo, "untracked_main.txt")) == "untracked in main\n"
  end

  test "moves and rolls back regular directory", %{base_tmp: base_tmp} do
    src = Path.join(base_tmp, "legacy_state")
    dst = Path.join(base_tmp, "archived_state")
    File.mkdir_p!(src)
    File.write!(Path.join(src, "record.json"), "{\"status\": \"ok\"}")

    assert {:ok, ^dst} = Worktree.move(src, dst)
    assert File.exists?(Path.join(dst, "record.json"))
    refute File.exists?(src)

    assert {:ok, ^src} = Worktree.rollback_move(dst, src)
    assert File.exists?(Path.join(src, "record.json"))
    refute File.exists?(dst)
  end
end
