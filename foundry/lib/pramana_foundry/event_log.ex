defmodule PramanaFoundry.EventLog do
  @moduledoc "Append-only event publication with per-record flush and fsync."

  alias PramanaFoundry.Schema

  def append(path, event) do
    with {:ok, validated} <- Schema.validate(:event, event),
         :ok <- File.mkdir_p(Path.dirname(path)),
         {:ok, file} <- :file.open(String.to_charlist(path), [:read, :append, :binary, :raw]),
         result <- write_and_sync(file, validated),
         :ok <- :file.close(file) do
      result
    end
  end

  defp write_and_sync(file, value) do
    with :ok <- append_boundary(file),
         :ok <- :file.write(file, [:json.encode(value), "\n"]),
         do: :file.sync(file)
  end

  defp append_boundary(file) do
    with {:ok, size} <- :file.position(file, :eof) do
      case size do
        0 ->
          :ok

        _ ->
          case :file.pread(file, size - 1, 1) do
            {:ok, "\n"} -> :ok
            {:ok, _byte} -> {:error, :unterminated_jsonl}
            :eof -> {:error, :unexpected_eof}
            {:error, _reason} = error -> error
          end
      end
    end
  end
end
