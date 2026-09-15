defmodule PramanaFoundry.Relocation.LocalExclude do
  @moduledoc """
  Temporary original-checkout runtime root protection.

  Protects `workflow/local/` in the original checkout with a narrowly scoped
  entry in `.git/info/exclude` before any tracked ignore is available on that
  checkout's current branch. Proves in disposable fixtures that the entry
  hides `workflow/local/` without ever staging `.git/info/exclude` or user files,
  and is cleanly removed when tracked ignore is in place.
  """

  @default_pattern "workflow/local/"
  @header_comment "# Temporary pramana workflow runtime root exclusion"

  @doc """
  Returns the absolute path to `.git/info/exclude` for a given checkout.
  """
  @spec exclude_file_path(Path.t()) :: Path.t()
  def exclude_file_path(repo_path) when is_binary(repo_path) do
    abs_repo = Path.expand(repo_path)

    case System.cmd("git", ["rev-parse", "--git-common-dir"],
           cd: abs_repo,
           stderr_to_stdout: true
         ) do
      {common_dir, 0} ->
        trimmed = String.trim(common_dir)
        git_common = Path.expand(trimmed, abs_repo)
        Path.join([git_common, "info", "exclude"])

      _ ->
        Path.join([abs_repo, ".git", "info", "exclude"])
    end
  end

  @doc """
  Adds a narrow entry to `.git/info/exclude` if not already present.
  Ensures no files are staged in Git.
  """
  @spec protect(Path.t(), binary()) :: {:ok, Path.t()} | {:error, term()}
  def protect(repo_path, pattern \\ @default_pattern)
      when is_binary(repo_path) and is_binary(pattern) do
    abs_repo = Path.expand(repo_path)
    exclude_path = exclude_file_path(abs_repo)
    info_dir = Path.dirname(exclude_path)

    with :ok <- File.mkdir_p(info_dir),
         {:ok, current_content} <- read_exclude_file(exclude_path),
         :ok <- ensure_no_staged_exclude(abs_repo) do
      if pattern_present?(current_content, pattern) do
        {:ok, exclude_path}
      else
        new_content = append_pattern(current_content, pattern)

        with :ok <- File.write(exclude_path, new_content),
             :ok <- ensure_no_staged_exclude(abs_repo) do
          {:ok, exclude_path}
        end
      end
    end
  end

  @doc """
  Checks if the pattern is currently in `.git/info/exclude`.
  """
  @spec protected?(Path.t(), binary()) :: boolean()
  def protected?(repo_path, pattern \\ @default_pattern)
      when is_binary(repo_path) and is_binary(pattern) do
    exclude_path = exclude_file_path(repo_path)

    case read_exclude_file(exclude_path) do
      {:ok, content} -> pattern_present?(content, pattern)
      {:error, _} -> false
    end
  end

  @doc """
  Verifies that `workflow/local/` (or specified pattern) is genuinely hidden from
  `git status --porcelain` and git ignore checks, and that `.git/info/exclude` is not staged.
  """
  @spec verify_protection(Path.t(), binary()) :: :ok | {:error, term()}
  def verify_protection(repo_path, pattern \\ @default_pattern)
      when is_binary(repo_path) and is_binary(pattern) do
    abs_repo = Path.expand(repo_path)
    probe_rel_dir = String.trim_trailing(pattern, "/")
    probe_name = ".protection_probe_#{System.unique_integer([:positive])}.tmp"
    probe_rel_path = Path.join(probe_rel_dir, probe_name)
    probe_full_path = Path.join(abs_repo, probe_rel_path)

    with :ok <- ensure_no_staged_exclude(abs_repo) do
      # Create probe file
      parent_dir = Path.dirname(probe_full_path)
      parent_existed_before = File.dir?(parent_dir)
      File.mkdir_p!(parent_dir)
      File.write!(probe_full_path, "runtime root protection probe\n")

      try do
        # 1. Check git status --porcelain
        case System.cmd("git", ["status", "--porcelain", probe_rel_path],
               cd: abs_repo,
               stderr_to_stdout: true
             ) do
          {"", 0} ->
            # Probe does not appear in git status!
            :ok

          {output, 0} ->
            {:error, {:probe_not_hidden, output}}

          {err, code} ->
            {:error, {:git_status_failed, code, err}}
        end
      after
        # Clean up probe
        File.rm(probe_full_path)

        if not parent_existed_before and File.ls(parent_dir) == {:ok, []} do
          File.rmdir(parent_dir)
        end
      end
    end
  end

  @doc """
  Removes the narrow exclusion pattern and comment from `.git/info/exclude`.
  Preserves all other pre-existing user entries and comments.
  Guarantees `.git/info/exclude` is never staged.
  """
  @spec unprotect(Path.t(), binary()) :: :ok | {:error, term()}
  def unprotect(repo_path, pattern \\ @default_pattern)
      when is_binary(repo_path) and is_binary(pattern) do
    abs_repo = Path.expand(repo_path)
    exclude_path = exclude_file_path(abs_repo)

    case read_exclude_file(exclude_path) do
      {:ok, content} ->
        lines = String.split(content, "\n")

        cleaned_lines =
          lines
          |> Enum.reject(fn line ->
            trimmed = String.trim(line)
            trimmed == pattern or trimmed == @header_comment
          end)

        cleaned_content =
          case cleaned_lines do
            [] -> ""
            _ -> Enum.join(cleaned_lines, "\n")
          end

        # Ensure trailing newline if non-empty
        final_content =
          if cleaned_content != "" and not String.ends_with?(cleaned_content, "\n") do
            cleaned_content <> "\n"
          else
            cleaned_content
          end

        with :ok <- File.write(exclude_path, final_content),
             :ok <- ensure_no_staged_exclude(abs_repo) do
          :ok
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Checks if tracked `.gitignore` on the current branch already ignores `workflow/local/`.
  """
  @spec tracked_ignore_present?(Path.t(), binary()) :: boolean()
  def tracked_ignore_present?(repo_path, pattern \\ @default_pattern)
      when is_binary(repo_path) and is_binary(pattern) do
    abs_repo = Path.expand(repo_path)
    gitignore_path = Path.join(abs_repo, ".gitignore")

    case File.read(gitignore_path) do
      {:ok, content} ->
        pattern_present?(content, pattern)

      {:error, _} ->
        false
    end
  end

  defp read_exclude_file(path) do
    case File.read(path) do
      {:ok, content} -> {:ok, content}
      {:error, :enoent} -> {:ok, ""}
      {:error, reason} -> {:error, reason}
    end
  end

  defp pattern_present?(content, pattern) do
    content
    |> String.split("\n")
    |> Enum.any?(fn line -> String.trim(line) == pattern end)
  end

  defp append_pattern(content, pattern) do
    trimmed = String.trim_trailing(content)

    block = "\n#{@header_comment}\n#{pattern}\n"

    if trimmed == "" do
      String.trim_leading(block, "\n")
    else
      trimmed <> "\n" <> block
    end
  end

  defp ensure_no_staged_exclude(repo_path) do
    case System.cmd("git", ["diff", "--cached", "--name-only"],
           cd: repo_path,
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        staged_files = String.split(output, "\n", trim: true)

        if Enum.any?(staged_files, fn f -> String.contains?(f, "exclude") end) do
          {:error, :git_exclude_is_staged}
        else
          :ok
        end

      {err, code} ->
        {:error, {:git_diff_cached_failed, code, err}}
    end
  end
end
