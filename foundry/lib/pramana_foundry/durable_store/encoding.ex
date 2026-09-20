defmodule PramanaFoundry.DurableStore.Encoding do
  @moduledoc false

  def canonical(value) do
    with {:ok, encoded} <- encode(value) do
      {:ok, IO.iodata_to_binary(encoded)}
    end
  end

  def json(value) do
    with {:ok, normalized} <- normalize(value) do
      {:ok, IO.iodata_to_binary(:json.encode(normalized))}
    end
  rescue
    _ -> {:error, :invalid_json_value}
  end

  def digest(bytes) when is_binary(bytes) do
    :sha256 |> :crypto.hash(bytes) |> Base.encode16(case: :lower)
  end

  def semantic_digest(domain, value) when is_binary(domain) do
    with {:ok, bytes} <-
           canonical(%{"domain" => domain, "schema_version" => 1, "value" => value}) do
      {:ok, digest(bytes)}
    end
  end

  defp encode(nil), do: {:ok, "null"}
  defp encode(true), do: {:ok, "true"}
  defp encode(false), do: {:ok, "false"}

  defp encode(value)
       when is_integer(value) and value >= -9_223_372_036_854_775_808 and
              value <= 9_223_372_036_854_775_807,
       do: {:ok, Integer.to_string(value)}

  defp encode(value) when is_integer(value), do: {:error, :integer_out_of_range}

  defp encode(value) when is_binary(value) do
    if String.valid?(value) do
      {:ok, ["\"", encode_string(value), "\""]}
    else
      {:error, :invalid_utf8}
    end
  end

  defp encode(value) when is_list(value) do
    with {:ok, items} <- map_ok(value, &encode/1) do
      {:ok, ["[", Enum.intersperse(items, ","), "]"]}
    end
  end

  defp encode(value) when is_map(value) do
    with {:ok, pairs} <- normalize_pairs(value),
         {:ok, encoded} <- map_ok(pairs, &encode_pair/1) do
      {:ok, ["{", Enum.intersperse(encoded, ","), "}"]}
    end
  end

  defp encode(_value), do: {:error, :unsupported_semantic_value}

  defp encode_string(value) do
    for <<codepoint::utf8 <- value>> do
      case codepoint do
        ?" -> "\\\""
        ?\\ -> "\\\\"
        control when control in 0..0x1F -> "\\u" <> control_hex(control)
        scalar -> <<scalar::utf8>>
      end
    end
  end

  defp control_hex(control) do
    control
    |> Integer.to_string(16)
    |> String.downcase(:ascii)
    |> String.pad_leading(4, "0")
  end

  defp encode_pair({key, value}) do
    with {:ok, encoded_key} <- encode(key), {:ok, encoded_value} <- encode(value) do
      {:ok, [encoded_key, ":", encoded_value]}
    end
  end

  defp normalize(value) when is_map(value) do
    with {:ok, pairs} <- normalize_pairs(value),
         {:ok, normalized} <-
           map_ok(pairs, fn {key, item} ->
             with {:ok, nested} <- normalize(item), do: {:ok, {key, nested}}
           end) do
      {:ok, Map.new(normalized)}
    end
  end

  defp normalize(value) when is_list(value), do: map_ok(value, &normalize/1)

  defp normalize(nil), do: {:ok, :null}

  defp normalize(value)
       when is_boolean(value) or is_integer(value) or is_binary(value),
       do: {:ok, value}

  defp normalize(_value), do: {:error, :unsupported_semantic_value}

  defp normalize_pairs(map) do
    pairs =
      Enum.map(map, fn
        {key, value} when is_binary(key) ->
          if(ascii_key?(key), do: {key, value}, else: :invalid)

        {key, value} when is_atom(key) ->
          normalized = Atom.to_string(key)
          if ascii_key?(normalized), do: {normalized, value}, else: :invalid

        {_key, _value} ->
          :invalid
      end)

    cond do
      :invalid in pairs ->
        {:error, :invalid_schema_key}

      pairs |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> length() != map_size(map) ->
        {:error, :duplicate_schema_key}

      true ->
        {:ok, Enum.sort_by(pairs, &elem(&1, 0))}
    end
  end

  defp ascii_key?(key) do
    key != "" and String.valid?(key) and Enum.all?(:binary.bin_to_list(key), &(&1 <= 0x7F))
  end

  defp map_ok(enumerable, fun) do
    enumerable
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      case fun.(item) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end
end
