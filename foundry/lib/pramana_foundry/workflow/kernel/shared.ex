defmodule PramanaFoundry.Workflow.Kernel.Shared do
  @moduledoc """
  Attempt accessors and the phase guards every family shares. Nothing here moves a
  phase; it reads or updates an attempt, or refuses on a ticket or attempt phase.
  """

  @terminal_ticket_phases ~w(integrated rejected cancelled)

  def terminal_ticket_phases, do: @terminal_ticket_phases

  def active_attempt(ticket), do: ticket["attempts"][ticket["active_attempt_id"]] || %{}

  # R4 orders closure *after* settlement in four rows - "close developer, then queue
  # fresh", "queue fresh developer after all check workers close", "close/seal reviewer,
  # then queued fresh developer", "bounded new check-run reservation after cleanup" - and
  # R4a's restart sentence requires reconstructing "no live execution". Addressing an
  # execution through the active-attempt pointer made every one of them unreachable the
  # instant attempt_settled cleared it, so every integrated ticket reported a live
  # execution forever. An execution belongs to the attempt that created it, whether or not
  # that attempt is still active.
  def attempt(ticket, attempt_id), do: ticket["attempts"][attempt_id] || %{}

  def update_attempt(ticket, attempt_id, fun),
    do: update_in(ticket, ["attempts", attempt_id], fun)

  def require_attempt(ticket, attempt_id),
    do:
      if(is_binary(attempt_id) and is_map(ticket["attempts"][attempt_id]),
        do: :ok,
        else: {:error, :unknown_attempt}
      )

  def update_active_attempt(ticket, fun),
    do: update_in(ticket, ["attempts", ticket["active_attempt_id"]], fun)

  def require_phase(ticket, phases),
    do: if(ticket["phase"] in phases, do: :ok, else: {:error, :wrong_source_phase})

  def require_attempt_phase(ticket, phases),
    do:
      if(active_attempt(ticket)["phase"] in phases,
        do: :ok,
        else: {:error, :wrong_attempt_phase}
      )

  def require_active_attempt(ticket, attempt_id) do
    if is_binary(attempt_id) and ticket["active_attempt_id"] == attempt_id,
      do: :ok,
      else: {:error, :not_the_active_attempt}
  end

  def require_no_active_attempt(ticket),
    do: if(is_nil(ticket["active_attempt_id"]), do: :ok, else: {:error, :attempt_still_active})
end
