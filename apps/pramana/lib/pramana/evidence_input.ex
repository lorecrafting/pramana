defmodule Pramana.EvidenceInput do
  @moduledoc """
  Shared report input boundary and original-byte prose regions.

  The 200 KB limit is the reader's existing resource policy, now also applied to
  domain verification and repair. It is not a retrieval-quality threshold.
  Regions are ordered, non-overlapping half-open UTF-8 byte ranges. Passing a
  region never substitutes bytes or permits a match to cross its boundary.
  """

  @max_bytes 200_000

  @spec max_bytes() :: pos_integer()
  def max_bytes, do: @max_bytes

  @spec check(String.t()) :: :ok | {:error, map()}
  def check(text) when is_binary(text) do
    cond do
      byte_size(text) > @max_bytes ->
        {:error, %{code: :input_too_large, max_bytes: @max_bytes, actual_bytes: byte_size(text)}}

      not String.valid?(text) ->
        {:error, %{code: :invalid_utf8}}

      true ->
        :ok
    end
  end

  @doc "Validates byte regions and returns their untouched slices with original offsets."
  @spec regions(String.t(), keyword()) :: [{non_neg_integer(), String.t()}]
  def regions(text, opts \\ []) do
    ranges = Keyword.get(opts, :regions, [%{byte_start: 0, byte_end: byte_size(text)}])

    {slices, _last} =
      Enum.map_reduce(ranges, 0, fn range, previous ->
        %{byte_start: first, byte_end: last} = range
        validate_range!(first, last, previous, byte_size(text))
        slice = binary_part(text, first, last - first)
        if not String.valid?(slice), do: raise(ArgumentError, "region splits a UTF-8 character")
        {{first, slice}, last}
      end)

    slices
  end

  @doc "Applies non-overlapping original-byte edits in one output pass; never rescans rewritten text."
  @spec apply_edits(String.t(), [map()]) :: String.t()
  def apply_edits(original, []), do: original

  def apply_edits(original, edits) do
    {parts, cursor} =
      edits
      |> Enum.sort_by(& &1.range.byte_start)
      |> Enum.map_reduce(0, fn edit, cursor ->
        %{byte_start: first, byte_end: last} = edit.range
        validate_range!(first, last, cursor, byte_size(original))

        if binary_part(original, first, last - first) != edit.before,
          do: raise(ArgumentError, "citation edit bytes changed")

        {[binary_part(original, cursor, first - cursor), edit.after], last}
      end)

    IO.iodata_to_binary([parts, binary_part(original, cursor, byte_size(original) - cursor)])
  end

  defp validate_range!(first, last, previous, size)
       when is_integer(first) and is_integer(last) and first >= previous and last >= first and
              last <= size,
       do: :ok

  defp validate_range!(_first, _last, _previous, _size),
    do: raise(ArgumentError, "evidence regions must be ordered, non-overlapping byte ranges")
end
