defmodule Pramana.Report.ForeignEvidence do
  @moduledoc false

  @type role :: :checked | :literal | :unresolved | :unchecked

  @type counts :: %{
          unresolved: non_neg_integer(),
          unchecked: non_neg_integer(),
          literal: non_neg_integer()
        }

  @type result :: %{counts: counts(), foreign: [map()]}

  @doc """
  Classifies foreign-citation occurrences after report canonicalization.

  `Citation.rewrite/2` deliberately preserves foreign-looking bytes inside literal
  quotation bodies. A preserved occurrence is independent evidence only when no Guard
  quotation actually covers it. This distinguishes literal source text from a citation
  that was recognized and resolved but left unchecked.

  Mapping is fail-closed: if neither the expected canonical replacement nor the original
  matched bytes occur at the reconstructed output offset, that occurrence is `unchecked`
  rather than being allowed to disappear into a verified report.
  """
  @spec classify([map()], String.t(), [map()]) :: result()
  def classify(foreign, resolved, findings) when is_list(foreign) and is_binary(resolved) do
    initial = %{
      counts: %{unresolved: 0, unchecked: 0, literal: 0},
      foreign: [],
      shift: 0,
      ranges: quote_ranges(findings)
    }

    classified = Enum.reduce(foreign, initial, &classify_occurrence(&1, &2, resolved))

    %{
      counts: classified.counts,
      foreign: Enum.reverse(classified.foreign)
    }
  end

  @spec counts([map()], String.t(), [map()]) :: counts()
  def counts(foreign, resolved, findings),
    do: classify(foreign, resolved, findings).counts

  defp quote_ranges(findings) do
    findings
    |> Enum.flat_map(fn
      %{occurrence: %{quote_range: %{byte_start: first, byte_end: last}}}
      when is_integer(first) and is_integer(last) ->
        [%{byte_start: first, byte_end: last}]

      _ ->
        []
    end)
    |> Enum.sort_by(& &1.byte_start)
  end

  defp classify_occurrence(item, state, resolved) do
    mapped_start = item.source_offset + state.shift
    rewrite_state = rewrite_state(item, resolved, mapped_start)
    mapped_end = mapped_start + mapped_length(item, rewrite_state)
    ranges = Enum.drop_while(state.ranges, &(&1.byte_end <= mapped_start))
    covered? = rewrite_state == :preserved and covered?(mapped_start, mapped_end, ranges)
    role = role(item, rewrite_state, covered?)

    %{
      state
      | counts: bump(state.counts, role),
        foreign: [Map.put(item, :evidence_role, role) | state.foreign],
        shift: shifted(state.shift, item, rewrite_state),
        ranges: ranges
    }
  end

  defp rewrite_state(item, resolved, mapped_start) do
    cond do
      is_binary(item.urn) and exact_at?(resolved, mapped_start, item.urn) -> :rewritten
      exact_at?(resolved, mapped_start, item.matched) -> :preserved
      true -> :unknown
    end
  end

  defp exact_at?(text, start, expected) when is_binary(expected) do
    length = byte_size(expected)

    start >= 0 and start + length <= byte_size(text) and
      binary_part(text, start, length) == expected
  end

  defp mapped_length(item, :rewritten), do: byte_size(item.urn)
  defp mapped_length(item, _state), do: item.source_length

  defp shifted(shift, item, :rewritten),
    do: shift + byte_size(item.urn) - item.source_length

  defp shifted(shift, _item, _state), do: shift

  defp covered?(_first, _last, []), do: false

  defp covered?(first, last, [range | _]),
    do: range.byte_start <= first and last <= range.byte_end

  defp role(_item, :rewritten, _covered?), do: :checked
  defp role(_item, :preserved, true), do: :literal
  defp role(%{urn: nil}, :preserved, false), do: :unresolved
  defp role(_item, _rewrite_state, _covered?), do: :unchecked

  defp bump(counts, :literal), do: Map.update!(counts, :literal, &(&1 + 1))
  defp bump(counts, :unresolved), do: Map.update!(counts, :unresolved, &(&1 + 1))
  defp bump(counts, :unchecked), do: Map.update!(counts, :unchecked, &(&1 + 1))
  defp bump(counts, :checked), do: counts
end
