defmodule PramanaFoundry.GitEvidence do
  @moduledoc """
  Fail-closed containment checks for legacy handoff and review submissions.

  These checks establish only that the named checkout and commits exist and agree at
  submission time. FR-13 replaces this mutable-checkout boundary with frozen,
  controller-custodied evidence and full scope verification.
  """

  @spec validate_checkout(term(), term(), term(), keyword()) :: :ok | {:error, String.t()}
  if Mix.env() == :test do
    def validate_checkout(checkout, commit, base, opts \\ []) do
      if Keyword.get(opts, :skip_git_checks, false) or
           Keyword.get(opts, :test_only_skip_git_checks, false),
         do: :ok,
         else: validate_evidence(checkout, commit, base)
    end
  else
    def validate_checkout(checkout, commit, base, opts \\ []) do
      cond do
        Keyword.get(opts, :skip_git_checks, false) ->
          {:error, "skip_git_checks is unavailable; FR-13 restores verified submissions"}

        Keyword.get(opts, :test_only_skip_git_checks, false) ->
          {:error, "test-only Git bypass is unavailable in this build"}

        true ->
          validate_evidence(checkout, commit, base)
      end
    end
  end

  defp validate_evidence(checkout, commit, base) do
    cond do
      not is_binary(checkout) or String.trim(checkout) == "" ->
        {:error, "submission requires an explicit checkout for Git evidence"}

      not File.dir?(checkout) ->
        {:error, "submission checkout does not exist: #{inspect(checkout)}"}

      not sha1?(commit) ->
        {:error, "submission requires an exact 40-character candidate commit"}

      not sha1?(base) ->
        {:error, "submission requires an exact 40-character base commit"}

      true ->
        validate_repository(checkout, commit, base)
    end
  end

  defp validate_repository(checkout, commit, base) do
    with {:ok, "true"} <- git(checkout, ["rev-parse", "--is-inside-work-tree"]),
         :ok <- clean_worktree?(checkout),
         {:ok, ^commit} <- git(checkout, ["rev-parse", "HEAD"]),
         :ok <- commit_exists(checkout, base, "base"),
         :ok <- commit_exists(checkout, commit, "candidate"),
         :ok <- ancestor?(checkout, base, commit) do
      :ok
    else
      {:ok, actual} -> {:error, "Git evidence mismatch: #{inspect(actual)}"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp clean_worktree?(checkout) do
    case git(checkout, ["status", "--porcelain"]) do
      {:ok, ""} ->
        :ok

      {:ok, dirty} ->
        {:error,
         "task checkout has uncommitted or untracked changes: #{String.slice(dirty, 0, 200)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp commit_exists(checkout, commit, label) do
    case git(checkout, ["cat-file", "-e", "#{commit}^{commit}"]) do
      {:ok, ""} -> :ok
      {:error, _reason} -> {:error, "#{label} commit does not exist in submission checkout"}
      {:ok, _output} -> {:error, "unexpected Git evidence for #{label} commit"}
    end
  end

  defp ancestor?(checkout, base, commit) do
    case System.cmd("git", ["merge-base", "--is-ancestor", base, commit],
           cd: checkout,
           stderr_to_stdout: true
         ) do
      {"", 0} -> :ok
      {_output, 1} -> {:error, "submission base is not an ancestor of candidate commit"}
      {output, _status} -> {:error, "git merge-base failed: #{String.trim(output)}"}
    end
  end

  defp git(checkout, argv) do
    case System.cmd("git", argv, cd: checkout, stderr_to_stdout: true) do
      {output, 0} -> {:ok, String.trim(output)}
      {output, _status} -> {:error, "git #{Enum.join(argv, " ")} failed: #{String.trim(output)}"}
    end
  end

  defp sha1?(value) when is_binary(value),
    do: byte_size(value) == 40 and Regex.match?(~r/\A[0-9a-f]{40}\z/, value)

  defp sha1?(_value), do: false
end
