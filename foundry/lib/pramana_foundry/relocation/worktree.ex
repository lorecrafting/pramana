defmodule PramanaFoundry.Relocation.Worktree do
  @moduledoc """
  Safe worktree relocation adaptation for registered checkouts.

  Uses `git worktree move` for registered worktrees while guaranteeing that
  the original checkout's tracked/untracked edits and root chat working
  directories are never moved or rewritten.
  """

  @doc """
  Checks whether a given path is a Git worktree (has a `.git` file pointing to gitdir).
  """
  @spec worktree?(Path.t()) :: boolean()
  def worktree?(path) when is_binary(path) do
    git_path = Path.join(path, ".git")

    case File.lstat(git_path) do
      {:ok, %File.Stat{type: :regular}} ->
        case File.read(git_path) do
          {:ok, content} -> String.starts_with?(String.trim(content), "gitdir:")
          _ -> false
        end

      _ ->
        false
    end
  end

  @doc """
  Checks whether a given path is the original/main Git checkout (has a `.git` directory,
  or matches explicit original_checkout_path, or git-dir == git-common-dir).
  """
  @spec original_checkout?(Path.t(), keyword()) :: boolean()
  def original_checkout?(path, opts \\ []) when is_binary(path) do
    abs_path = Path.expand(path)

    # 1. Check explicit option
    case Keyword.get(opts, :original_checkout) do
      explicit when is_binary(explicit) ->
        if abs_path == Path.expand(explicit), do: true, else: check_git_original(abs_path)

      _ ->
        check_git_original(abs_path)
    end
  end

  @doc """
  Checks whether a given path is the root chat working directory.
  """
  @spec root_chat_directory?(Path.t(), keyword()) :: boolean()
  def root_chat_directory?(path, opts \\ []) when is_binary(path) do
    abs_path = Path.expand(path)

    case Keyword.get(opts, :root_chat_dir) do
      explicit when is_binary(explicit) ->
        abs_path == Path.expand(explicit)

      _ ->
        abs_path == Path.expand(File.cwd!())
    end
  end

  @doc """
  Validates that a planned move does not violate safety invariants:
  - Source must exist.
  - Source must not be the original checkout.
  - Source must not be the root chat working directory.
  - Destination must not already exist (collision).
  """
  @spec validate_move(Path.t(), Path.t(), keyword()) :: :ok | {:error, term()}
  def validate_move(source, destination, opts \\ [])
      when is_binary(source) and is_binary(destination) do
    abs_src = Path.expand(source)
    abs_dst = Path.expand(destination)

    cond do
      not File.exists?(abs_src) ->
        {:error, {:source_not_found, abs_src}}

      original_checkout?(abs_src, opts) ->
        {:error, :cannot_move_original_checkout}

      root_chat_directory?(abs_src, opts) ->
        {:error, :cannot_move_root_chat_directory}

      abs_src == abs_dst ->
        {:error, :source_and_destination_identical}

      destination_collides?(abs_dst) ->
        {:error, {:destination_collision, abs_dst}}

      true ->
        :ok
    end
  end

  @doc """
  Safely moves a worktree or directory to a new destination.
  """
  @spec move(Path.t(), Path.t(), keyword()) :: {:ok, Path.t()} | {:error, term()}
  def move(source, destination, opts \\ []) when is_binary(source) and is_binary(destination) do
    abs_src = Path.expand(source)
    abs_dst = Path.expand(destination)

    with :ok <- validate_move(abs_src, abs_dst, opts) do
      dst_parent = Path.dirname(abs_dst)
      File.mkdir_p!(dst_parent)

      if worktree?(abs_src) do
        move_worktree(abs_src, abs_dst)
      else
        move_directory(abs_src, abs_dst)
      end
    end
  end

  @doc """
  Rolls back a previously moved worktree or directory from destination back to source.
  """
  @spec rollback_move(Path.t(), Path.t(), keyword()) :: {:ok, Path.t()} | {:error, term()}
  def rollback_move(destination, source, _opts \\ [])
      when is_binary(destination) and is_binary(source) do
    abs_dst = Path.expand(destination)
    abs_src = Path.expand(source)

    if File.exists?(abs_dst) do
      src_parent = Path.dirname(abs_src)
      File.mkdir_p!(src_parent)

      if worktree?(abs_dst) do
        move_worktree(abs_dst, abs_src)
      else
        move_directory(abs_dst, abs_src)
      end
    else
      {:error, {:destination_not_found, abs_dst}}
    end
  end

  defp check_git_original(abs_path) do
    git_path = Path.join(abs_path, ".git")

    case File.lstat(git_path) do
      {:ok, %File.Stat{type: :directory}} ->
        true

      {:ok, %File.Stat{type: :regular}} ->
        false

      _ ->
        case System.cmd("git", ["rev-parse", "--git-dir"], cd: abs_path, stderr_to_stdout: true) do
          {dir, 0} ->
            case System.cmd("git", ["rev-parse", "--git-common-dir"],
                   cd: abs_path,
                   stderr_to_stdout: true
                 ) do
              {common, 0} ->
                Path.expand(String.trim(dir), abs_path) ==
                  Path.expand(String.trim(common), abs_path)

              _ ->
                false
            end

          _ ->
            false
        end
    end
  end

  defp destination_collides?(abs_dst) do
    if File.exists?(abs_dst) do
      case File.ls(abs_dst) do
        {:ok, []} -> false
        {:ok, _entries} -> true
        _ -> true
      end
    else
      false
    end
  end

  defp move_worktree(abs_src, abs_dst) do
    case System.cmd("git", ["worktree", "move", abs_src, abs_dst],
           cd: abs_src,
           stderr_to_stdout: true
         ) do
      {_output, 0} ->
        # Verify the worktree moved cleanly and destination is valid
        if worktree?(abs_dst) do
          {:ok, abs_dst}
        else
          {:error, {:worktree_verification_failed, abs_dst}}
        end

      {output, code} ->
        {:error, {:git_worktree_move_failed, code, String.trim(output)}}
    end
  end

  defp move_directory(abs_src, abs_dst) do
    case File.rename(abs_src, abs_dst) do
      :ok ->
        {:ok, abs_dst}

      {:error, :exdev} ->
        # Across filesystem boundaries: copy recursively and remove
        case File.cp_r(abs_src, abs_dst) do
          {:ok, _} ->
            File.rm_rf!(abs_src)
            {:ok, abs_dst}

          {:error, reason, file} ->
            File.rm_rf(abs_dst)
            {:error, {:cross_device_copy_failed, reason, file}}
        end

      {:error, reason} ->
        {:error, {:file_rename_failed, reason}}
    end
  end
end
