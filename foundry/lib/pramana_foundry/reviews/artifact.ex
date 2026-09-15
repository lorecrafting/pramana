defmodule PramanaFoundry.Reviews.Artifact do
  @moduledoc """
  Schema validation and checkout consistency checks for review artifacts.
  """

  @required_fields ~w(schema_version run_id task_id commit verdict findings checks remaining_risks)
  @allowed_verdicts ~w(approved rejected changes_requested)

  alias PramanaFoundry.GitEvidence

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

      not is_binary(assignment["reviewer_run_id"]) ->
        {:error, "review requires an independently issued reviewer run_id"}

      review["run_id"] != assignment["reviewer_run_id"] ->
        {:error,
         "review run_id mismatch: expected #{assignment["reviewer_run_id"]}, got #{review["run_id"]}"}

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

    GitEvidence.validate_checkout(checkout, review["commit"], ticket["base_revision"], opts)
  end
end
