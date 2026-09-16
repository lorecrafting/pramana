defmodule Pramana.Report.ForeignEvidence do
  @moduledoc false

  @type counts :: %{
          unresolved: non_neg_integer(),
          unchecked: non_neg_integer(),
          literal: non_neg_integer()
        }

  @doc """
  Classifies foreign-citation occurrences after report canonicalization.

  `Citation.rewrite/2` deliberately preserves foreign-looking bytes inside literal
  quotation bodies. A preserved occurrence is independent evidence only when no Guard
  quotation actually covers it. This distinguishes literal source text from a citation
  that was recognized and resolved but left unchecked.
  """
  @spec counts([map()], String.t(), [map()]) :: counts()
  def counts(foreign, resolved, findings) when is_list(foreign) and is_binary(resolved) do
    quote_ranges =
      findings
      |> Enum.flat_map(fn
        %{occurrence: %{quote_range: %{byte_start: first, byte_end: last}}}
        when is_integer(first) and is_integer(last) ->
          [%{byte_start: first, byte_end: last}]

        _ ->
          []
      end)
      |> Enum.sort_by(& &1.byte_start)

    {counts, _state} =
      Enum.reduce(foreign, {%{unresolved: 0, unchecked: 0, literal: 0}, {0, quote_ranges}}, fn item,
                                                                                             {counts,
                                                                                              {shift,
                                                                                               ranges}} ->
        mapped_start = item.source_offset + shift
        rewritten? = rewritten?(item, resolved, mapped_start)
        mapped_length = if rewritten?, do: byte_size(item.urn), else: item.source_length
        mapped_end = mapped_start + mapped_length
        ranges = Enum.drop_while(ranges, &(&1.byte_end <= mapped_start))
        covered? = not rewritten? and covered?(mapped_start, mapped_end, ranges)

        counts = classify(counts, item, rewritten?, covered?)
        shift = if rewritten?, do: shift + byte_size(item.urn) - item.source_length, else: shift

        {counts, {shift, ranges}}
      end)

    counts
  end

  defp rewritten?(%{urn: nil}, _resolved, _mapped_start), do: false

  defp rewritten?(%{urn: urn}, resolved, mapped_start) when is_binary(urn) do
    length = byte_size(urn)
    mapped_start >= 0 and mapped_start + length <= byte_size(resolved) and
      binary_part(resolved, mapped_start, length) == urn
  end

  defp covered?(_first, _last, []), do: false

  defp covered?(first, last, [range | _]),
    do: range.byte_start <= first and last <= range.byte_end

  defp classify(counts, _item, true, _covered?), do: counts
  defp classify(counts, _item, false, true), do: Map.update!(counts, :literal, &(&1 + 1))
  defp classify(counts, %{urn: nil}, false, false), do: Map.update!(counts, :unresolved, &(&1 + 1))

  defp classify(counts, %{urn: urn}, false, false) when is_binary(urn),
    do: Map.update!(counts, :unchecked, &(&1 + 1))
end
