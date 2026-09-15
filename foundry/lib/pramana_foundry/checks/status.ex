defmodule PramanaFoundry.Checks.Status do
  @moduledoc """
  Pure classification of a check's durable evidence. Nothing here touches the OS; it
  only interprets already-gathered identity, completion, deadline, and stop-intent
  records so the same decision can be tested without spawning a process and re-derived
  identically after a restart.
  """

  alias PramanaFoundry.Effects.ProcessGroup

  @type state :: %{
          recorded_identity: ProcessGroup.identity() | nil,
          live_identity: ProcessGroup.identity() | nil,
          completion: %{binary() => term()} | nil,
          deadline_epoch: number() | nil,
          cancellation_requested?: boolean(),
          stop_intent_checkpointed?: boolean()
        }

  @type outcome ::
          {:completed, integer(), boolean()}
          | :timeout
          | :running
          | :cancelled
          | :uncertain

  @doc """
  `{:completed, exit_code, promotable?}` when the check finished inside its deadline;
  `promotable?` is false when a stop intent was checkpointed before completion arrived,
  so a late clean exit is preserved as diagnostic evidence but never treated as a
  passing gate. `:timeout` beats any exit code, including a late zero, once the
  deadline has passed. Absent a completion record, `:running` requires the live
  process to be the exact one recorded (pid, process group, start time, command);
  anything else -- gone, or a different process now holding that pid -- is
  `:uncertain` rather than assumed success or failure, and is never silently rerun.
  """
  @spec classify(state()) :: outcome()
  def classify(%{completion: nil} = state) do
    cond do
      state.cancellation_requested? and not running?(state) -> :cancelled
      running?(state) -> :running
      true -> :uncertain
    end
  end

  def classify(%{completion: completion} = state) do
    if deadline_exceeded?(state, completion) do
      :timeout
    else
      {:completed, Map.fetch!(completion, "returncode"), not state.stop_intent_checkpointed?}
    end
  end

  defp running?(%{recorded_identity: nil}), do: false
  defp running?(%{recorded_identity: _recorded, live_identity: nil}), do: false

  defp running?(%{recorded_identity: recorded, live_identity: live}),
    do: ProcessGroup.same_process?(recorded, live)

  defp deadline_exceeded?(%{deadline_epoch: nil}, _completion), do: false

  defp deadline_exceeded?(%{deadline_epoch: deadline_epoch}, %{"completed_at" => completed_at}),
    do: completed_at > deadline_epoch
end
