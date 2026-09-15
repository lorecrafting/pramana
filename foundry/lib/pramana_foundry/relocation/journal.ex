defmodule PramanaFoundry.Relocation.Journal do
  @moduledoc """
  Append-only transaction journal for workspace relocation with per-entry fsync.

  Records each atomic move step before execution, enabling deterministic
  crash recovery to resume or reverse in-flight relocations.
  """

  @doc """
  Initializes a new journal file with a transaction init record.
  """
  @spec init(Path.t(), binary(), keyword()) :: {:ok, Path.t()} | {:error, term()}
  def init(journal_path, txid, opts \\ []) when is_binary(journal_path) and is_binary(txid) do
    abs_path = Path.expand(journal_path)
    dir = Path.dirname(abs_path)

    with :ok <- File.mkdir_p(dir) do
      entry = %{
        "txid" => txid,
        "seq" => 0,
        "timestamp" => now_iso8601(),
        "step_id" => "init",
        "action" => "init",
        "status" => "completed",
        "source" => nil,
        "destination" => nil,
        "metadata" => Keyword.get(opts, :metadata, %{})
      }

      case append_entry(abs_path, entry) do
        :ok -> {:ok, abs_path}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Records a state change for a step in the journal with fsync.
  """
  @spec record(
          Path.t(),
          binary(),
          non_neg_integer(),
          binary(),
          atom() | binary(),
          atom() | binary(),
          binary() | nil,
          binary() | nil,
          map()
        ) :: :ok | {:error, term()}
  def record(
        journal_path,
        txid,
        seq,
        step_id,
        action,
        status,
        source,
        destination,
        metadata \\ %{}
      ) do
    entry = %{
      "txid" => txid,
      "seq" => seq,
      "timestamp" => now_iso8601(),
      "step_id" => to_string(step_id),
      "action" => to_string(action),
      "status" => to_string(status),
      "source" => source,
      "destination" => destination,
      "metadata" => metadata
    }

    append_entry(journal_path, entry)
  end

  @doc """
  Appends an entry to the journal file and fsyncs the write.
  """
  @spec append_entry(Path.t(), map()) :: :ok | {:error, term()}
  def append_entry(journal_path, entry) when is_binary(journal_path) and is_map(entry) do
    abs_path = Path.expand(journal_path)
    dir = Path.dirname(abs_path)

    with :ok <- File.mkdir_p(dir),
         encoded <- IO.iodata_to_binary([:json.encode(entry), "\n"]),
         {:ok, file} <- :file.open(String.to_charlist(abs_path), [:append, :binary, :raw]),
         :ok <- :file.write(file, encoded),
         :ok <- :file.sync(file),
         :ok <- :file.close(file) do
      :ok
    end
  end

  @doc """
  Reads all entries from the journal file in sequential order.
  """
  @spec read_entries(Path.t()) :: {:ok, [map()]} | {:error, term()}
  def read_entries(journal_path) when is_binary(journal_path) do
    abs_path = Path.expand(journal_path)

    case File.read(abs_path) do
      {:ok, content} ->
        entries =
          content
          |> String.split("\n", trim: true)
          |> Enum.reduce_while({:ok, []}, fn line, {:ok, acc} ->
            case decode_line(line) do
              {:ok, entry} -> {:cont, {:ok, [entry | acc]}}
              {:error, reason} -> {:halt, {:error, reason}}
            end
          end)

        case entries do
          {:ok, list} -> {:ok, Enum.reverse(list)}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Reconstructs the execution state from the journal.
  Categorizes steps into completed, in-flight (prepared but not completed/rolled back),
  and rolled back.
  """
  @spec reconstruct_state(Path.t()) :: {:ok, map()} | {:error, term()}
  def reconstruct_state(journal_path) when is_binary(journal_path) do
    case read_entries(journal_path) do
      {:ok, entries} ->
        init_entry = Enum.find(entries, fn e -> e["step_id"] == "init" end)
        txid = if init_entry, do: init_entry["txid"], else: "unknown"

        # Group entries by step_id in chronological order of first appearance
        {steps_by_id, step_order} =
          Enum.reduce(entries, {%{}, []}, fn entry, {map, order} ->
            step_id = entry["step_id"]

            if step_id == "init" do
              {map, order}
            else
              order_updated = if Map.has_key?(map, step_id), do: order, else: [step_id | order]
              current_entries = Map.get(map, step_id, [])
              {Map.put(map, step_id, [entry | current_entries]), order_updated}
            end
          end)

        reversed_order = Enum.reverse(step_order)

        # For each step_id, examine latest entry
        {completed, in_flight, rolled_back, failed} =
          Enum.reduce(reversed_order, {[], [], [], []}, fn step_id, {comp, infl, roll, fail} ->
            # entries are stored in reverse order in steps_by_id
            step_entries = Map.fetch!(steps_by_id, step_id)
            latest = hd(step_entries)
            prepared = Enum.find(step_entries, fn e -> e["status"] == "prepared" end) || latest

            case latest["status"] do
              "completed" ->
                {[latest | comp], infl, roll, fail}

              "prepared" ->
                {comp, [prepared | infl], roll, fail}

              "rolled_back" ->
                {comp, infl, [latest | roll], fail}

              "failed" ->
                {comp, [prepared | infl], roll, [latest | fail]}

              _ ->
                {comp, [latest | infl], roll, fail}
            end
          end)

        {:ok,
         %{
           txid: txid,
           entries: entries,
           completed: Enum.reverse(completed),
           in_flight: Enum.reverse(in_flight),
           rolled_back: Enum.reverse(rolled_back),
           failed: Enum.reverse(failed),
           step_order: reversed_order,
           max_seq: Enum.reduce(entries, 0, fn e, max -> max(max, e["seq"] || 0) end)
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp decode_line(line) do
    try do
      {:ok, :json.decode(line)}
    rescue
      _ -> {:error, :malformed_json_line}
    catch
      _, _ -> {:error, :malformed_json_line}
    end
  end

  defp now_iso8601 do
    DateTime.utc_now() |> DateTime.to_iso8601()
  end
end
