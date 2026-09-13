defmodule PramanaFoundry.Reviews.Artifact do
  @moduledoc """
  Schema validation and checkout consistency checks for review artifacts.
  """

  @required_fields ~w(schema_version run_id task_id commit verdict findings checks remaining_risks)
  @allowed_verdicts ~w(approved rejected changes_requested)

  @spec validate(map(), map(), map(), keyword()) :: {:ok, map()} | {:error, String.t()}
  def validate(review, ticket, assignment, opts \\ [])

  def validate(review, ticket, assignment, opts)
      when is_map(review) and is_map(ticket) and is_map(assignment) do
    keys = Map.keys(review) |> Enum.sort()
    expected_keys = Enum.sort(@required_fields)

    cond do
      keys != expected_keys ->
        {:error, "review artifact fields must be exactly #{Enum.join(expected_keys, ", ")}"}

      review["schema_version"] != 1 ->
        {:error,
         "unsupported review artifact schema_version: #{inspect(review["schema_version"])}"}

      review["task_id"] != ticket["task_id"] ->
        {:error,
         "review task_id mismatch: expected #{ticket["task_id"]}, got #{review["task_id"]}"}

      review["run_id"] != assignment["run_id"] and
          review["run_id"] != get_in(assignment, ["handoff", "run_id"]) and
          review["run_id"] != Map.get(assignment, "reviewer_run_id") ->
        {:error,
         "review run_id mismatch: expected #{assignment["run_id"] || "?"}, got #{review["run_id"]}"}

      review["commit"] != get_in(assignment, ["handoff", "commit"]) and
          review["commit"] != Map.get(assignment, "candidate_commit") ->
        {:error, "review commit mismatch"}

      review["verdict"] not in @allowed_verdicts ->
        {:error, "invalid review verdict: #{inspect(review["verdict"])}"}

      not is_list(review["findings"]) ->
        {:error, "review findings must be a list"}

      not is_list(review["remaining_risks"]) ->
        {:error, "review remaining_risks must be a list"}

      not is_list(review["checks"]) ->
        {:error, "review checks must be a list"}

      true ->
        with :ok <-
               validate_checks(
                 review["checks"],
                 ticket["review_required_checks"],
                 review["verdict"]
               ),
             :ok <- validate_checkout_consistency(review, ticket, opts) do
          {:ok, review}
        end
    end
  end

  def validate(_review, _ticket, _assignment, _opts),
    do: {:error, "invalid review or ticket data"}

  defp validate_checks(checks, required_checks, verdict) do
    # Check each individual check entry
    all_valid_entries? =
      Enum.all?(checks, fn check ->
        is_map(check) and
          Map.keys(check) |> Enum.sort() == ["command", "exit_code"] and
          is_list(check["command"]) and
          check["command"] != [] and
          Enum.all?(check["command"], &is_binary/1) and
          is_integer(check["exit_code"])
      end)

    if not all_valid_entries? do
      {:error, "review contains malformed check entries"}
    else
      if verdict == "approved" do
        all_passed? = Enum.all?(checks, fn check -> check["exit_code"] == 0 end)

        if not all_passed? do
          {:error, "approved review cannot contain non-zero exit_code checks"}
        else
          recorded_commands = Enum.map(checks, & &1["command"])
          expected_commands = required_checks || []

          if recorded_commands != expected_commands do
            {:error, "review checks must exactly match review_required_checks"}
          else
            :ok
          end
        end
      else
        :ok
      end
    end
  end

  defp validate_checkout_consistency(review, ticket, opts) do
    checkout = Keyword.get(opts, :checkout, ticket["checkout"])

    cond do
      is_nil(checkout) ->
        :ok

      Keyword.get(opts, :skip_git_checks, false) ->
        :ok

      File.dir?(checkout) ->
        case System.cmd("git", ["rev-parse", "HEAD"], cd: checkout, stderr_to_stdout: true) do
          {head, 0} ->
            actual_head = String.trim(head)

            if actual_head != review["commit"] do
              {:error, "review invalidated because checkout changed after reviewed commit"}
            else
              case System.cmd("git", ["status", "--porcelain"],
                     cd: checkout,
                     stderr_to_stdout: true
                   ) do
                {"", 0} ->
                  :ok

                {_dirty, 0} ->
                  {:error, "review invalidated because checkout has uncommitted changes"}

                {err, _} ->
                  {:error, "git status check failed: #{err}"}
              end
            end

          {err, _} ->
            {:error, "git rev-parse HEAD failed: #{err}"}
        end

      true ->
        :ok
    end
  end
end
