defmodule Pramana.Repair.Quote do
  @moduledoc """
  Aligns a nonempty quotation to one exact source subspan without adding words.

  Editorial marks are removed only from comparison copies. Variant mode folds
  the existing curated glyph classes. Original source byte boundaries survive;
  overlapping and repeated matches are ambiguous, never resolved by first match.
  """

  alias Pramana.Punctuation
  alias Pramana.Retrieval.Variants

  @spec align(String.t(), String.t(), atom()) :: {:ok, String.t()} | {:error, atom()}
  def align(actual, quoted, mode) do
    needle = normalize(quoted, mode)

    if needle == "" do
      {:error, :empty_quote}
    else
      {normalized, starts, ends} = indexed(actual, mode)
      locate(actual, needle, normalized, starts, ends)
    end
  end

  defp locate(actual, needle, normalized, starts, ends) do
    case :binary.match(normalized, needle) do
      :nomatch ->
        {:error, :unaligned_quote}

      {first, length} ->
        finish = first + length
        remaining = byte_size(normalized) - first - 1

        if :binary.match(normalized, needle, scope: {first + 1, remaining}) != :nomatch do
          {:error, :ambiguous_quote}
        else
          source_slice(actual, normalized == needle, starts[first], ends[finish])
        end
    end
  end

  defp source_slice(_actual, _whole, nil, _last), do: {:error, :unaligned_quote}
  defp source_slice(_actual, _whole, _first, nil), do: {:error, :unaligned_quote}
  # Preserve surrounding editorial marks only when the ENTIRE substantive span
  # matches. A partial quote gets its minimal aligned span, never adjacent words.
  defp source_slice(actual, true, _first, _last), do: {:ok, String.trim(actual)}

  defp source_slice(actual, false, first, last),
    do: {:ok, binary_part(actual, first, last - first)}

  defp indexed(actual, mode) do
    {parts, starts, ends, _, _} =
      actual
      |> String.graphemes()
      |> Enum.reduce({[], %{}, %{}, 0, 0}, fn grapheme, {parts, starts, ends, src, dst} ->
        normalized = normalize(grapheme, mode)
        next_src = src + byte_size(grapheme)
        next_dst = dst + byte_size(normalized)

        if normalized == "" do
          {parts, starts, ends, next_src, dst}
        else
          {[normalized | parts], Map.put(starts, dst, src), Map.put(ends, next_dst, next_src),
           next_src, next_dst}
        end
      end)

    {parts |> Enum.reverse() |> IO.iodata_to_binary(), starts, ends}
  end

  defp normalize(text, :orthographic_variant), do: text |> Punctuation.strip() |> Variants.fold()
  defp normalize(text, _mode), do: Punctuation.strip(text)
end
