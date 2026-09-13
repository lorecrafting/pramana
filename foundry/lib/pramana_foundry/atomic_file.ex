defmodule PramanaFoundry.AtomicFile do
  @moduledoc "Atomic JSON replacement with a durable intent and deterministic recovery."

  @spec write(Path.t(), map(), keyword()) :: :ok | {:error, term()}
  def write(path, value, opts \\ []) do
    dir = Path.dirname(path)
    name = Path.basename(path)

    txid =
      Keyword.get_lazy(opts, :txid, fn ->
        Integer.to_string(System.unique_integer([:positive]))
      end)

    temp = Path.join(dir, ".#{name}.#{txid}.tmp")
    intent = Path.join(dir, ".#{name}.#{txid}.intent")
    encoded = IO.iodata_to_binary([:json.encode(value), "\n"])

    intent_record = %{
      "schema_version" => 1,
      "target" => path,
      "temp" => temp,
      "sha256" => sha(encoded)
    }

    with :ok <- File.mkdir_p(dir),
         :ok <- sync_directory(dir),
         :ok <- sync_write(temp, encoded),
         :ok <- inject(opts, :after_temp),
         :ok <- sync_write(intent, IO.iodata_to_binary([:json.encode(intent_record), "\n"])),
         :ok <- sync_directory(dir),
         :ok <- inject(opts, :after_intent),
         :ok <- File.rename(temp, path),
         :ok <- sync_directory(dir),
         :ok <- inject(opts, :after_rename),
         :ok <- File.rm(intent),
         :ok <- sync_directory(dir) do
      :ok
    end
  end

  @spec recover(Path.t()) :: :ok | {:error, term()}
  def recover(path) do
    with {:ok, intents} <- transaction_files(path, ".intent"),
         :ok <-
           Enum.reduce_while(intents, :ok, fn intent, :ok ->
             case recover_intent(path, intent) do
               :ok -> {:cont, :ok}
               {:error, _reason} = error -> {:halt, error}
             end
           end),
         :ok <- remove_orphan_temps(path),
         :ok <- sync_directory(Path.dirname(path)) do
      :ok
    end
  end

  defp transaction_files(path, suffix) do
    dir = Path.dirname(path)
    prefix = ".#{Path.basename(path)}."

    with {:ok, names} <- File.ls(dir) do
      paths =
        names
        |> Enum.filter(&(String.starts_with?(&1, prefix) and String.ends_with?(&1, suffix)))
        |> Enum.sort()
        |> Enum.map(&Path.join(dir, &1))

      {:ok, paths}
    end
  end

  defp remove_orphan_temps(path) do
    with {:ok, temps} <- transaction_files(path, ".tmp") do
      Enum.reduce_while(temps, :ok, fn temp, :ok ->
        case File.rm(temp) do
          :ok -> {:cont, :ok}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
    end
  end

  defp recover_intent(path, intent) do
    with {:ok, encoded_intent} <- File.read(intent),
         true <- String.valid?(encoded_intent),
         %{
           "schema_version" => 1,
           "target" => ^path,
           "temp" => temp,
           "sha256" => expected
         } = value <- :json.decode(encoded_intent),
         [] <- Map.keys(value) -- ~w(schema_version target temp sha256),
         true <- is_binary(temp) and is_binary(expected) do
      cond do
        valid_file?(path, expected) -> finish_recovery(intent, temp, nil)
        valid_file?(temp, expected) -> finish_recovery(intent, temp, {temp, path})
        true -> {:error, {:unrecoverable_intent, intent}}
      end
    else
      _ -> {:error, {:invalid_intent, intent}}
    end
  rescue
    _ -> {:error, {:invalid_intent, intent}}
  catch
    _, _ -> {:error, {:invalid_intent, intent}}
  end

  defp finish_recovery(intent, temp, rename) do
    dir = Path.dirname(intent)

    with :ok <- maybe_rename(rename),
         :ok <- sync_directory(dir),
         :ok <- remove_if_present(temp),
         :ok <- File.rm(intent),
         :ok <- sync_directory(dir) do
      :ok
    end
  end

  defp maybe_rename(nil), do: :ok
  defp maybe_rename({from, to}), do: File.rename(from, to)

  defp remove_if_present(path) do
    case File.rm(path) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp valid_file?(path, expected) do
    case File.read(path) do
      {:ok, bytes} -> sha(bytes) == expected
      _ -> false
    end
  end

  defp sync_write(path, bytes) do
    with {:ok, file} <-
           :file.open(String.to_charlist(path), [:write, :binary, :raw, :exclusive]),
         :ok <- :file.write(file, bytes),
         :ok <- :file.sync(file),
         :ok <- :file.close(file),
         :ok <- File.chmod(path, 0o600) do
      :ok
    end
  end

  defp sync_directory(dir) do
    with {:ok, file} <- :file.open(String.to_charlist(dir), [:read, :raw, :directory]),
         :ok <- :file.sync(file),
         :ok <- :file.close(file) do
      :ok
    end
  end

  defp inject(opts, point) do
    if Keyword.get(opts, :crash_at) == point, do: {:error, {:injected_crash, point}}, else: :ok
  end

  defp sha(bytes), do: :sha256 |> :crypto.hash(bytes) |> Base.encode16(case: :lower)
end
