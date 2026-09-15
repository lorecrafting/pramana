defmodule PramanaFoundry.Effects.PromptDelivery do
  @moduledoc """
  Checkpointed prompt-delivery lifecycle. `prompt_intent` is durably appended before
  Herdr's `agent prompt` runs; `prompt_delivered` only after it returns. A crash
  between those two checkpoints leaves delivery ambiguous, and restart never calls
  `agent prompt` again for that task/run/role: it looks for positive transcript
  evidence that the exact text already reached the agent, and parks with that
  evidence when none is found rather than guessing either way.
  """

  alias PramanaFoundry.Effects.Checkpoint
  alias PramanaFoundry.Herdr.Adapter

  @spec deliver(
          Path.t(),
          binary(),
          binary(),
          binary(),
          Adapter.t(),
          Adapter.expected_identity(),
          binary(),
          keyword()
        ) ::
          {:ok, :delivered | :already_delivered} | {:error, term()}
  def deliver(log_path, task_id, run_id, role, adapter, expected, text, opts \\ []) do
    with {:ok, state} <- status(log_path, task_id, run_id, role) do
      case state do
        :not_sent -> send_prompt(log_path, task_id, run_id, role, adapter, expected, text, opts)
        :intent_only -> reconcile(log_path, task_id, run_id, role, adapter, expected, text, opts)
        :delivered -> {:ok, :already_delivered}
      end
    end
  end

  @spec status(Path.t(), binary(), binary(), binary()) ::
          {:ok, :not_sent | :intent_only | :delivered} | {:error, term()}
  def status(log_path, task_id, run_id, role) do
    with {:ok, delivered} <-
           Checkpoint.matching(log_path, "prompt_delivered", task_id, run_id, role) do
      if delivered do
        {:ok, :delivered}
      else
        with {:ok, intent} <-
               Checkpoint.matching(log_path, "prompt_intent", task_id, run_id, role) do
          {:ok, if(intent, do: :intent_only, else: :not_sent)}
        end
      end
    end
  end

  defp send_prompt(log_path, task_id, run_id, role, adapter, expected, text, opts) do
    with {:ok, _intent} <-
           Checkpoint.append(log_path, "prompt_intent", task_id, run_id, role, %{
             "text_sha256" => sha(text)
           }),
         {:ok, _prompted} <- Adapter.prompt(adapter, expected, text, opts) do
      persist_delivered(log_path, task_id, run_id, role, text, "delivered_now")
    end
  end

  defp reconcile(log_path, task_id, run_id, role, adapter, expected, text, opts) do
    case Adapter.read(adapter, expected, 160, opts) do
      {:ok, transcript} ->
        if String.contains?(transcript, text) do
          persist_delivered(log_path, task_id, run_id, role, text, "confirmed_via_transcript")
        else
          {:error, {:ambiguous_prompt_delivery, :not_found_in_recent_output}}
        end

      {:error, reason} ->
        {:error, {:ambiguous_prompt_delivery, reason}}
    end
  end

  defp persist_delivered(log_path, task_id, run_id, role, text, evidence) do
    with {:ok, _event} <-
           Checkpoint.append(log_path, "prompt_delivered", task_id, run_id, role, %{
             "text_sha256" => sha(text),
             "evidence" => evidence
           }) do
      {:ok, :delivered}
    end
  end

  defp sha(text), do: :sha256 |> :crypto.hash(text) |> Base.encode16(case: :lower)
end
