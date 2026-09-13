defmodule PramanaFoundry.Assignments.Handoff do
  @moduledoc """
  Validation of completed and blocked worker handoff artifacts, including scope, exclusions,
  and clean checkout verification.
  """

  @completed_fields ~w(schema_version task_id run_id assigned_base commit changed_files reproduction_evidence checks remaining_risks status outcome)
  @blocked_fields ~w(schema_version task_id run_id status reason diagnostic_evidence)
  @max_blocked_handoff_bytes 64 * 1024

  @spec validate(map(), map(), map(), keyword()) :: {:ok, map()} | {:error, String.t()}
  def validate(handoff, ticket, assignment, opts \\ [])

  def validate(%{"status" => "blocked"} = handoff, ticket, assignment, _opts) do
    keys = Map.keys(handoff)
    missing = @blocked_fields -- keys
    allowed = @blocked_fields ++ ["requested_follow_up_scope"]
    unexpected = keys -- allowed

    cond do
      missing != [] ->
        {:error, "blocked handoff missing fields: #{Enum.join(missing, ", ")}"}

      unexpected != [] ->
        {:error, "blocked handoff unexpected fields: #{Enum.join(unexpected, ", ")}"}

      handoff["schema_version"] != 1 ->
        {:error, "blocked handoff schema_version must be 1"}

      handoff["task_id"] != ticket["task_id"] ->
        {:error, "blocked handoff task_id mismatch"}

      handoff["run_id"] != assignment["run_id"] ->
        {:error, "blocked handoff run_id mismatch"}

      not is_binary(handoff["reason"]) or String.trim(handoff["reason"]) == "" ->
        {:error, "blocked handoff requires a reason"}

      not is_list(handoff["diagnostic_evidence"]) or handoff["diagnostic_evidence"] == [] ->
        {:error, "blocked handoff requires non-empty diagnostic_evidence list"}

      not Enum.all?(handoff["diagnostic_evidence"], &is_binary/1) ->
        {:error, "blocked handoff diagnostic_evidence entries must be strings"}

      true ->
        {:ok, handoff}
    end
  end

  def validate(%{"status" => "completed"} = handoff, ticket, assignment, opts) do
    keys = Map.keys(handoff) |> Enum.sort()
    expected = Enum.sort(@completed_fields)

    cond do
      keys != expected ->
        {:error, "completed handoff fields must be exactly #{Enum.join(expected, ", ")}"}

      handoff["schema_version"] != 1 ->
        {:error, "completed handoff schema_version must be 1"}

      handoff["task_id"] != ticket["task_id"] ->
        {:error, "completed handoff task_id mismatch"}

      handoff["run_id"] != assignment["run_id"] ->
        {:error, "completed handoff run_id mismatch"}

      handoff["assigned_base"] != ticket["base_revision"] ->
        {:error, "completed handoff assigned_base must match ticket base_revision"}

      not is_binary(handoff["commit"]) or not sha1?(handoff["commit"]) ->
        {:error, "completed handoff commit must be a 40-character hex SHA"}

      not is_list(handoff["changed_files"]) or handoff["changed_files"] == [] ->
        {:error, "completed handoff changed_files must be a non-empty list"}

      not is_map(handoff["reproduction_evidence"]) ->
        {:error, "completed handoff reproduction_evidence must be an object"}

      true ->
        with :ok <- validate_changed_files(handoff["changed_files"], ticket),
             :ok <- validate_checks(handoff["checks"], ticket["required_checks"]),
             :ok <- validate_clean_checkout(handoff, ticket, opts) do
          {:ok, handoff}
        end
    end
  end

  def validate(%{"status" => other}, _ticket, _assignment, _opts) do
    {:error, "unsupported handoff status: #{inspect(other)}"}
  end

  def validate(_handoff, _ticket, _assignment, _opts), do: {:error, "invalid handoff data"}

  def max_blocked_bytes, do: @max_blocked_handoff_bytes

  defp sha1?(value) do
    byte_size(value) == 40 and Regex.match?(~r/^[0-9a-f]{40}$/i, value)
  end

  defp validate_changed_files(changed_files, ticket) do
    scope = Map.get(ticket, "scope", [])
    exclusions = Map.get(ticket, "exclusions", [])

    Enum.reduce_while(changed_files, :ok, fn path, :ok ->
      in_scope? = Enum.any?(scope, &path_matches_pattern?(path, &1))
      excluded? = Enum.any?(exclusions, &path_matches_pattern?(path, &1))

      cond do
        excluded? ->
          {:halt, {:error, "changed path matches ticket exclusion: #{path}"}}

        not in_scope? ->
          {:halt, {:error, "changed path is outside ticket scope: #{path}"}}

        true ->
          {:cont, :ok}
      end
    end)
  end

  defp path_matches_pattern?(path, pattern) do
    norm_path = Path.relative_to(path, ".")
    norm_pattern = Path.relative_to(pattern, ".")

    cond do
      norm_path == norm_pattern ->
        true

      String.ends_with?(norm_pattern, "/**") ->
        prefix = String.slice(norm_pattern, 0, byte_size(norm_pattern) - 3)
        norm_path == prefix or String.starts_with?(norm_path, prefix <> "/")

      String.ends_with?(norm_pattern, "/*") ->
        prefix = String.slice(norm_pattern, 0, byte_size(norm_pattern) - 2)

        norm_path == prefix or
          (String.starts_with?(norm_path, prefix <> "/") and
             not String.contains?(Path.relative_to(norm_path, prefix), "/"))

      true ->
        regex_str = "^" <> String.replace(Regex.escape(norm_pattern), "\\*", ".*") <> "$"

        case Regex.compile(regex_str) do
          {:ok, regex} -> Regex.match?(regex, norm_path)
          _ -> false
        end
    end
  end

  defp validate_checks(checks, required_checks) do
    if not is_list(checks) do
      {:error, "completed handoff checks must be a list"}
    else
      valid_entries? =
        Enum.all?(checks, fn check ->
          is_map(check) and
            Map.keys(check) |> Enum.sort() == ["command", "exit_code"] and
            is_list(check["command"]) and
            check["command"] != [] and
            check["exit_code"] == 0
        end)

      if not valid_entries? do
        {:error, "completed handoff checks contain malformed or failed entries"}
      else
        recorded = Enum.map(checks, & &1["command"])
        expected = required_checks || []

        if recorded != expected do
          {:error, "completed handoff checks must exactly match ticket required_checks"}
        else
          :ok
        end
      end
    end
  end

  defp validate_clean_checkout(handoff, ticket, opts) do
    checkout = Keyword.get(opts, :checkout, ticket["checkout"])

    cond do
      is_nil(checkout) ->
        :ok

      Keyword.get(opts, :skip_git_checks, false) ->
        :ok

      File.dir?(checkout) ->
        # 1. Verify git status --porcelain has ZERO uncommitted or untracked changes
        case System.cmd("git", ["status", "--porcelain"], cd: checkout, stderr_to_stdout: true) do
          {"", 0} ->
            # 2. Verify HEAD == commit
            case System.cmd("git", ["rev-parse", "HEAD"], cd: checkout, stderr_to_stdout: true) do
              {head, 0} ->
                actual_head = String.trim(head)

                if actual_head != handoff["commit"] do
                  {:error,
                   "task checkout HEAD does not equal handoff commit: #{actual_head} != #{handoff["commit"]}"}
                else
                  # 3. Verify recorded commit is the sole difference from accepted base
                  base = handoff["assigned_base"]

                  case System.cmd("git", ["rev-list", "--count", "#{base}..HEAD"],
                         cd: checkout,
                         stderr_to_stdout: true
                       ) do
                    {count_str, 0} ->
                      case Integer.parse(String.trim(count_str)) do
                        {1, ""} ->
                          :ok

                        {n, ""} ->
                          {:error,
                           "task checkout has #{n} commits beyond base (expected exactly 1)"}

                        _ ->
                          {:error, "unexpected rev-list output: #{count_str}"}
                      end

                    {err, _} ->
                      {:error, "git rev-list failed: #{err}"}
                  end
                end

              {err, _} ->
                {:error, "git rev-parse HEAD failed: #{err}"}
            end

          {dirty, 0} ->
            {:error,
             "task checkout has uncommitted or untracked changes: #{String.slice(dirty, 0, 200)}"}

          {err, _} ->
            {:error, "git status check failed: #{err}"}
        end

      true ->
        :ok
    end
  end
end
