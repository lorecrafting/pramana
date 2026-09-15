defmodule PramanaFoundry.Assignments.Correction do
  @moduledoc """
  Correction tracking, evidence retention, and attempt-limit gating (maximum configurable via ticket).
  """

  @default_max_corrections 2

  @doc """
  Processes a review rejection or changes_requested verdict.
  Increments correction count, retains rejected review findings, and either prepares
  a correction assignment or parks the ticket if the limit is exceeded.

  The maximum correction attempts is read from the ticket's `corrections.max` field.
  If absent, defaults to #{@default_max_corrections}.
  """
  def handle_review(assignment, review) do
    verdict = review["verdict"]

    if verdict == "approved" do
      {:ok, :approved, assignment}
    else
      current_count = Map.get(assignment, "correction_count", 0)
      new_count = current_count + 1

      # Read max_corrections from ticket, e.g. ticket.corrections.max
      ticket = Map.get(assignment, "ticket", %{})
      max_corrections =
        get_in(ticket, ["corrections", "max"]) || @default_max_corrections

      history = Map.get(assignment, "correction_history", [])

      record = %{
        "round" => new_count,
        "rejected_commit" => review["commit"],
        "verdict" => verdict,
        "findings" => review["findings"],
        "checks" => review["checks"],
        "at" => DateTime.utc_now() |> DateTime.to_iso8601()
      }

      updated_history = history ++ [record]

      if new_count > max_corrections do
        parked_assignment =
          assignment
          |> Map.put("correction_count", new_count)
          |> Map.put("correction_history", updated_history)
          |> Map.put("status", "parked")
          |> Map.put("blocker", "maximum corrections exceeded (#{max_corrections})")

        {:error, :max_corrections_exceeded, parked_assignment}
      else
        correction_assignment =
          assignment
          |> Map.put("correction_count", new_count)
          |> Map.put("correction_history", updated_history)
          |> Map.put("status", "queued")
          |> Map.put("correction_context", record)

        {:ok, :correction_needed, correction_assignment}
      end
    end
  end
end
