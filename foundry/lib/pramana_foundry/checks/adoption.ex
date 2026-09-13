defmodule PramanaFoundry.Checks.Adoption do
  @moduledoc """
  Restart-time reconciliation for a check that may have kept running while no
  coordinator was watching it. It re-derives live process identity itself (never
  trusts stale in-memory state) and adopts a surviving check exactly once: a live
  process that matches the durably recorded pid/process-group/start-time/command
  is adopted; anything else is resolved the same way `Checks.Status` would from a
  live coordinator, so restart and steady-state share one policy.
  """

  alias PramanaFoundry.Checks.Status
  alias PramanaFoundry.Effects.ProcessGroup

  @type reconciled :: {:adopted, ProcessGroup.identity()} | Status.outcome()

  @spec reconcile(Status.state()) :: reconciled()
  def reconcile(%{recorded_identity: recorded} = state) do
    live_identity = current_identity(recorded)
    state = Map.put(state, :live_identity, live_identity)

    case Status.classify(state) do
      :running -> {:adopted, recorded}
      other -> other
    end
  end

  defp current_identity(%{pid: pid}) do
    case ProcessGroup.identity(pid) do
      {:ok, identity} -> identity
      {:error, _reason} -> nil
    end
  end

  defp current_identity(_recorded), do: nil
end
