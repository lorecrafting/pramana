defmodule PramanaFoundry.CLI.Validators do
  @moduledoc """
  Actionable field-level validation for agent CLI commands.

  Every error tells the agent exactly what to fix and how.
  Every validation returns either `:ok` or a list of actionable error messages.
  """

  @commit_sha_regex ~r/\A[a-f0-9]{40}\z/
  @valid_verdicts ~w(approved changes_requested rejected)
  @valid_priorities ~w(P0 P1 P2 P3)

  # ── Handoff validation ──

  @doc "Validate a complete handoff JSON map. Returns :ok or {:error, [messages]}."
  def validate_handoff(map) when is_map(map) do
    errors =
      []
      |> check_required(map, "outcome", "outcome of the handoff (e.g. 'completed', 'partial')")
      |> check_required(map, "summary", "summary of what was changed, tested, and any issues")
      |> check_type(map, "outcome", &is_binary/1, "must be a string")
      |> check_type(map, "summary", &is_binary/1, "must be a string")
      |> check_commit_sha(map)
      |> check_changed_files(map)
      |> check_optional_type(map, "checks_passed", &is_boolean/1, "must be true or false")
      |> check_optional_type(map, "unresolved_issues", &is_list/1, "must be a list of strings")
      |> check_optional_type(map, "evidence", &is_list/1, "must be a list of evidence entries")

    if errors == [], do: :ok, else: {:error, errors}
  end

  def validate_handoff(other) do
    {:error, ["Handoff must be a JSON object, got #{inspect(other)}"]}
  end

  # ── Review validation ──

  @doc "Validate a complete review JSON map. Returns :ok or {:error, [messages]}."
  def validate_review(map) when is_map(map) do
    errors =
      []
      |> check_required(map, "verdict", "one of: approved, changes_requested, rejected")
      |> check_required(map, "findings", "list of specific issues found during review")
      |> check_verdict(map)
      |> check_type(map, "findings", &is_list/1, "must be a list of strings")
      |> check_optional_type(
        map,
        "remaining_risks",
        &is_list/1,
        "must be a list of risk descriptions"
      )
      |> check_optional_type(map, "checks", &is_map/1, "must be a map of check names to results")

    if errors == [], do: :ok, else: {:error, errors}
  end

  def validate_review(other) do
    {:error, ["Review must be a JSON object, got #{inspect(other)}"]}
  end

  # ── Ticket validation ──

  @doc "Validate ticket creation params. Returns :ok or {:error, [messages]}."
  def validate_ticket(fields) when is_map(fields) do
    errors =
      []
      |> check_required(fields, "title", "descriptive ticket title")
      |> check_required(fields, "scope", "list of files/directories the ticket covers")
      |> check_required(fields, "acceptance_criteria", "list of criteria the handoff must meet")
      |> check_type(fields, "title", &is_binary/1, "must be a string")
      |> check_type(fields, "scope", &is_list/1, "must be a list of file paths")
      |> check_type(fields, "acceptance_criteria", &is_list/1, "must be a list of criteria")
      |> check_priority(fields)

    if errors == [], do: :ok, else: {:error, errors}
  end

  def validate_ticket(other) do
    {:error, ["Ticket must be a JSON object, got #{inspect(other)}"]}
  end

  # ── Individual field validators ──

  @doc "Validate a commit SHA. Returns :ok or {:error, message}."
  def validate_commit_sha(nil), do: :ok

  def validate_commit_sha(sha) when is_binary(sha) do
    if String.match?(sha, @commit_sha_regex) do
      :ok
    else
      {:error,
       "Field 'commit' must be a 40-character hex SHA, got '#{sha}'\n" <>
         "  Fix: Provide the full 40-character commit hash (run: git rev-parse HEAD)"}
    end
  end

  def validate_commit_sha(other) do
    {:error, "Field 'commit' must be a string, got #{inspect(other)}"}
  end

  @doc "Validate a JSON file exists and parses as a map. Returns {:ok, map} or {:error, message}."
  def validate_json_file(path) do
    case File.read(path) do
      {:ok, contents} ->
        case decode_json(contents) do
          {:ok, data} when is_map(data) ->
            {:ok, data}

          {:ok, _} ->
            {:error,
             "File '#{path}' must contain a JSON object (got array/string/number)\n" <>
               "  Fix: Write the artifact as a JSON object with named fields (e.g. {'outcome': 'completed', ...})"}

          {:error, reason} ->
            {:error,
             "File '#{path}' is not valid JSON: #{inspect(reason)}\n" <>
               "  Fix: Ensure the file contains valid JSON syntax"}
        end

      {:error, reason} ->
        {:error,
         "File '#{path}' could not be read: #{reason}\n" <>
           "  Fix: Write the handoff artifact to '#{path}' before submitting"}
    end
  end

  defp decode_json(contents) do
    {:ok, :json.decode(contents)}
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc "Validate that a directory exists. Returns :ok or {:error, message}."
  def validate_directory(path) do
    if File.dir?(path) do
      :ok
    else
      {:error,
       "Directory '#{path}' does not exist\n" <>
         "  Fix: The checkout directory should exist — check the task_id is correct"}
    end
  end

  @doc "Validate task_id format (non-empty, no spaces). Returns :ok or {:error, message}."
  def validate_task_id(id) when is_binary(id) do
    if String.trim(id) != "" and not String.contains?(id, " ") do
      :ok
    else
      {:error,
       "Task ID '#{id}' is invalid — must be non-empty with no spaces\n" <>
         "  Fix: Use the exact task_id from the ticket (e.g. 'FIX-42')"}
    end
  end

  def validate_task_id(other) do
    {:error, "Task ID must be a string, got #{inspect(other)}"}
  end

  # ── Validation helpers ──

  defp check_required(errors, map, field, hint) do
    case Map.get(map, field) do
      nil ->
        errors ++
          [
            "Missing required field '#{field}'\n" <>
              "  Fix: Add '#{field}' to the artifact — #{hint}"
          ]

      val when is_binary(val) ->
        if String.trim(val) == "" do
          errors ++
            [
              "Field '#{field}' must not be empty\n" <>
                "  Fix: Provide a non-empty value for '#{field}' — #{hint}"
            ]
        else
          errors
        end

      _val ->
        errors
    end
  end

  defp check_type(errors, map, field, type_check, message) do
    case Map.get(map, field) do
      nil ->
        errors

      val ->
        if type_check.(val) do
          errors
        else
          errors ++
            [
              "Field '#{field}' #{message}, got '#{inspect(val)}'\n" <>
                "  Fix: Correct the type of '#{field}'"
            ]
        end
    end
  end

  defp check_optional_type(errors, map, field, type_check, message) do
    case Map.get(map, field) do
      nil ->
        errors

      val ->
        if type_check.(val) do
          errors
        else
          errors ++
            [
              "Field '#{field}' #{message}, got '#{inspect(val)}'\n" <>
                "  Fix: Correct the type of '#{field}'"
            ]
        end
    end
  end

  defp check_commit_sha(errors, map) do
    case map["commit"] do
      nil ->
        errors

      sha ->
        case validate_commit_sha(sha) do
          :ok -> errors
          {:error, msg} -> errors ++ [msg]
        end
    end
  end

  defp check_changed_files(errors, map) do
    case Map.get(map, "changed_files") do
      nil ->
        errors

      files when is_list(files) ->
        errors

      other ->
        errors ++
          [
            "Field 'changed_files' must be a list of file paths, got '#{inspect(other)}'\n" <>
              "  Fix: List the files that were changed during this assignment"
          ]
    end
  end

  defp check_verdict(errors, map) do
    case Map.get(map, "verdict") do
      nil ->
        errors

      v when v in @valid_verdicts ->
        errors

      other ->
        valid = Enum.join(@valid_verdicts, ", ")

        errors ++
          [
            "Field 'verdict' must be one of: #{valid}, got '#{inspect(other)}'\n" <>
              "  Fix: Set verdict to one of: #{valid}"
          ]
    end
  end

  defp check_priority(errors, map) do
    case Map.get(map, "priority") do
      nil ->
        errors

      p when p in @valid_priorities ->
        errors

      other ->
        valid = Enum.join(@valid_priorities, ", ")

        errors ++
          [
            "Field 'priority' must be one of: #{valid}, got '#{inspect(other)}'\n" <>
              "  Fix: Set priority to one of: #{valid}"
          ]
    end
  end
end
