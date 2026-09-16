defmodule Pramana.GuardOccurrencesTest do
  @moduledoc "Exact edit ranges are derived by the same parser that identifies citations."
  use ExUnit.Case, async: true

  alias Pramana.Guard

  @urn "pramana:cbeta.T:T0262_001@p0001a01"

  test "repeated URNs and combining characters retain byte rather than character offsets" do
    prefix = "🙂 e\u0301："
    text = prefix <> "「如是我聞」【#{@urn}】.  See #{@urn}."
    assert [quoted, bare] = Guard.occurrences(text)
    assert quoted.quoted == "如是我聞"
    assert bare.quoted == nil
    assert slice(text, quoted.quote_range) == "如是我聞"
    assert slice(text, quoted.urn_range) == @urn
    assert slice(text, quoted.citation_range) == "【#{@urn}】"
    assert slice(text, bare.citation_range) == @urn
    assert quoted.urn_range.byte_start == byte_size(prefix <> "「如是我聞」【")
    assert bare.urn_range.byte_start > quoted.urn_range.byte_end
  end

  test "a paired citation wrapper includes only that wrapper and its internal whitespace" do
    for {open, close} <- [{"[", "]"}, {"(", ")"}, {"（", "）"}, {"【", "】"}] do
      wrapped = open <> "  " <> @urn <> " " <> close
      assert [occurrence] = Guard.occurrences("before  " <> wrapped <> "  after")
      assert slice("before  " <> wrapped <> "  after", occurrence.citation_range) == wrapped
    end
  end

  test "unpaired punctuation is not included in a citation edit" do
    text = "before [" <> @urn <> "). after"
    assert [occurrence] = Guard.occurrences(text)
    assert slice(text, occurrence.citation_range) == @urn
  end

  defp slice(text, %{byte_start: first, byte_end: last}),
    do: binary_part(text, first, last - first)
end
