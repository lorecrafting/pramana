defmodule PramanaFoundry.Assessor.UniqueJSON do
  @moduledoc """
  Strict JSON decoder that rejects duplicate object keys and trailing non-whitespace.

  The normal JSON map decoder keeps only one value for duplicate keys. Provider evidence
  must not silently choose between contradictory fields, so this decoder uses OTP's
  object callbacks to reject duplicates before a map is constructed.
  """

  @spec decode(binary()) :: {:ok, term()} | {:error, atom()}
  def decode(bytes) when is_binary(bytes) do
    decoders = %{
      object_start: fn _old_acc -> {[], MapSet.new()} end,
      object_push: &object_push/3,
      object_finish: fn {pairs, _keys}, old_acc -> {Map.new(pairs), old_acc} end
    }

    try do
      case :json.decode(bytes, nil, decoders) do
        {value, _acc, rest} ->
          if json_whitespace?(rest), do: {:ok, value}, else: {:error, :trailing_json_data}
      end
    rescue
      _ -> {:error, :malformed_json}
    catch
      :duplicate_json_key -> {:error, :duplicate_json_key}
      _, _ -> {:error, :malformed_json}
    end
  end

  def decode(_bytes), do: {:error, :malformed_json}

  defp object_push(key, value, {pairs, keys}) do
    if MapSet.member?(keys, key) do
      throw(:duplicate_json_key)
    else
      {[{key, value} | pairs], MapSet.put(keys, key)}
    end
  end

  defp json_whitespace?(<<>>), do: true

  defp json_whitespace?(<<char, rest::binary>>) when char in [9, 10, 13, 32],
    do: json_whitespace?(rest)

  defp json_whitespace?(_bytes), do: false
end
