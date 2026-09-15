defmodule PramanaFoundry.Effects.Checkpoint do
  @moduledoc """
  Checkpoint-before-effect: an event is durably appended and fsynced before any
  side-effecting call runs, and again after it completes. Recovery reads the same
  durable log instead of trusting in-memory state, so a crash on either side of the
  boundary is reconciled from evidence rather than repeated blindly.
  """

  alias PramanaFoundry.{EventLog, Import}

  @spec append(Path.t(), binary(), binary(), binary(), binary(), map()) ::
          {:ok, map()} | {:error, term()}
  def append(log_path, event, task_id, run_id, role, attributes \\ %{})
      when is_binary(event) and is_binary(task_id) and is_binary(run_id) and is_binary(role) and
             is_map(attributes) do
    record = %{
      "schema_version" => 1,
      "event" => event,
      "at" => DateTime.to_iso8601(DateTime.utc_now()),
      "task_id" => task_id,
      "run_id" => run_id,
      "role" => role,
      "attributes" => attributes,
      "evidence" => %{}
    }

    with :ok <- EventLog.append(log_path, record) do
      {:ok, record}
    end
  end

  @spec events(Path.t()) :: {:ok, [map()]} | {:error, term()}
  def events(log_path) do
    case Import.read_jsonl(log_path, :event) do
      {:ok, records} -> {:ok, records}
      {:error, %{reason: :enoent}} -> {:ok, []}
      {:error, _reason} = error -> error
    end
  end

  @spec matching(Path.t(), binary(), binary(), binary(), binary()) ::
          {:ok, map() | nil} | {:error, term()}
  def matching(log_path, event, task_id, run_id, role) do
    with {:ok, records} <- events(log_path) do
      {:ok,
       Enum.find(records, fn record ->
         record["event"] == event and record["task_id"] == task_id and
           record["run_id"] == run_id and record["role"] == role
       end)}
    end
  end
end
