defmodule PramanaFoundry.DurableStore.LegacyLine do
  @moduledoc false

  alias PramanaFoundry.Schema

  def classify(bytes) when is_binary(bytes) do
    cond do
      not String.valid?(bytes) -> {false, "invalid_utf8"}
      not String.ends_with?(bytes, "\n") -> {false, "unterminated_jsonl"}
      true -> decode(String.trim_trailing(bytes, "\n"))
    end
  end

  defp decode(""), do: {false, "empty_record"}

  defp decode(line) do
    decoded = :json.decode(line)

    case Schema.validate(:event, decoded) do
      {:ok, _record} -> {true, nil}
      {:error, error} -> {false, "schema:" <> inspect(error.reason)}
    end
  rescue
    _ -> {false, "malformed_json"}
  catch
    _, _ -> {false, "malformed_json"}
  end
end
