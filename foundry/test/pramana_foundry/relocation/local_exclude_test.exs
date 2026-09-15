defmodule PramanaFoundry.Relocation.LocalExcludeTest do
  use ExUnit.Case, async: true

  alias PramanaFoundry.Relocation.LocalExclude

  @moduletag :local_exclude

  setup do
    tmp = Path.join(System.tmp_dir!(), "local-exclude-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)

    # Initialize disposable Git repository fixture
    {_, 0} = System.cmd("git", ["init"], cd: tmp)
    {_, 0} = System.cmd("git", ["config", "user.email", "test@pramana.local"], cd: tmp)
    {_, 0} = System.cmd("git", ["config", "user.name", "Pramana Test"], cd: tmp)

    # Commit initial tracked files (including one in workflow/)
    tracked_file = Path.join(tmp, "tracked_user_file.txt")
    File.write!(tracked_file, "tracked content\n")
    workflow_tracked = Path.join(tmp, "workflow/tracked_mod.txt")
    File.mkdir_p!(Path.dirname(workflow_tracked))
    File.write!(workflow_tracked, "workflow tracked\n")
    {_, 0} = System.cmd("git", ["add", "."], cd: tmp)
    {_, 0} = System.cmd("git", ["commit", "-m", "initial tracked files"], cd: tmp)

    # Create an untracked user file
    untracked_file = Path.join(tmp, "user_scratchpad.txt")
    File.write!(untracked_file, "untracked scratchpad content\n")

    on_exit(fn -> File.rm_rf(tmp) end)

    {:ok, repo: tmp, tracked_file: tracked_file, untracked_file: untracked_file}
  end

  test "protect hides workflow/local/ from git status without staging user files or exclude", %{
    repo: repo,
    untracked_file: untracked_file
  } do
    runtime_dir = Path.join(repo, "workflow/local")
    File.mkdir_p!(runtime_dir)
    runtime_file = Path.join(runtime_dir, "coordinator_state.json")
    File.write!(runtime_file, "{\"active\": true}\n")

    # Before protection: workflow/local/ is visible in git status
    {status_before, 0} = System.cmd("git", ["status", "--porcelain"], cd: repo)
    assert String.contains?(status_before, "workflow/local")
    assert String.contains?(status_before, "user_scratchpad.txt")

    refute LocalExclude.protected?(repo)

    # Apply protection
    assert {:ok, exclude_path} = LocalExclude.protect(repo)
    assert File.exists?(exclude_path)
    assert LocalExclude.protected?(repo)

    # Verify protection using probe
    assert :ok = LocalExclude.verify_protection(repo)

    # After protection: workflow/local/ is completely hidden, untracked user file remains
    {status_after, 0} = System.cmd("git", ["status", "--porcelain"], cd: repo)
    refute String.contains?(status_after, "workflow/local")
    assert String.contains?(status_after, "?? user_scratchpad.txt")

    # Guarantee: git exclude is NEVER staged
    {staged, 0} = System.cmd("git", ["diff", "--cached", "--name-only"], cd: repo)
    assert staged == ""

    # Untracked user file is untouched
    assert File.read!(untracked_file) == "untracked scratchpad content\n"

    # Protect is idempotent
    assert {:ok, _} = LocalExclude.protect(repo)
    exclude_content = File.read!(exclude_path)
    # Pattern appears exactly once
    assert length(String.split(exclude_content, "workflow/local/")) == 2

    # Clean unprotect
    assert :ok = LocalExclude.unprotect(repo)
    refute LocalExclude.protected?(repo)

    # After unprotect: workflow/local is visible again, and no user files were staged
    {status_restored, 0} = System.cmd("git", ["status", "--porcelain"], cd: repo)
    assert String.contains?(status_restored, "workflow/local")
    {staged_restored, 0} = System.cmd("git", ["diff", "--cached", "--name-only"], cd: repo)
    assert staged_restored == ""
  end

  test "unprotect preserves pre-existing user exclusions", %{repo: repo} do
    exclude_path = LocalExclude.exclude_file_path(repo)
    File.mkdir_p!(Path.dirname(exclude_path))

    # Pre-existing user exclude
    File.write!(exclude_path, "# User custom exclude\n*.user_tmp\nmy_private_notes.md\n")

    assert {:ok, _} = LocalExclude.protect(repo)
    assert LocalExclude.protected?(repo)

    # Both user excludes and pramana exclusion exist
    content = File.read!(exclude_path)
    assert String.contains?(content, "*.user_tmp")
    assert String.contains?(content, "my_private_notes.md")
    assert String.contains?(content, "workflow/local/")

    # Unprotect
    assert :ok = LocalExclude.unprotect(repo)
    refute LocalExclude.protected?(repo)

    cleaned = File.read!(exclude_path)
    assert String.contains?(cleaned, "*.user_tmp")
    assert String.contains?(cleaned, "my_private_notes.md")
    refute String.contains?(cleaned, "workflow/local/")
  end
end
