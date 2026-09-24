defmodule Pramana.EvidenceAdversarialTest do
  @moduledoc "Replay-boundary and quotation-extent regressions from the PR #8 adversarial review."
  use Pramana.DataCase, async: true

  alias Pramana.Corpus.Loader
  alias Pramana.Guard
  alias Pramana.Normalize.CBETA
  alias Pramana.Repair
  alias Pramana.Report

  @urn "pramana:cbeta.T:T0262_001@p0001a01"
  @unknown "pramana:cbeta.T:T9999_001@p0001a01"
  @xml """
  <TEI xmlns="http://www.tei-c.org/ns/1.0"><teiHeader><fileDesc><titleStmt>
  <title level="m">Fixture</title></titleStmt></fileDesc></teiHeader>
  <text><body><milestone n="1" unit="juan"/>
  <lb n="0001a01"/>如是我聞。
  <lb n="0001a02"/>前文。天上天下，唯我獨尊。後文。
  <lb n="0001a03"/>佛說，佛說。
  </body></text></TEI>
  """

  setup do
    {:ok, ir} = CBETA.normalize(@xml, work_id: "T0262", canon: "T", volume: 9, number: "0262")
    {:ok, _} = Loader.load(ir, source: "cbeta", witness: "T")
    :ok
  end

  defp block(newline \\ "\n") do
    Enum.join(
      [
        "```pramana-replay",
        Jason.encode!(%{tool: "get_passage", arguments: %{urn: @urn}, assert: %{urn: @urn}}),
        "```"
      ],
      newline
    )
  end

  defp verify(text),
    do: Report.verify(text, executor: fn "get_passage", _ -> {:ok, %{urn: @urn}} end)

  test "a quotation straddling a replay is neither paired nor repaired" do
    for newline <- ["\n", "\r\n"] do
      replay = block(newline)
      original = "「如是" <> newline <> replay <> newline <> "我聞」 [#{@urn}]"
      assert %{text: ^original, edits: []} = Repair.repair(original)
      result = verify(original)
      assert result.status == :incomplete
      assert result.counts.verified_quotes == 0
      assert result.counts.existence_only == 1
      assert result.counts.verified_replays == 1
    end
  end

  test "trailing protected JSON cannot be trimmed into a verified quotation" do
    quoted = "如是我聞。\n" <> block() <> "\n"
    original = "「" <> quoted <> "」 [#{@urn}]"
    refute Guard.verify(@urn, quoted)
    result = verify(original)
    refute result.ok?
    assert result.status == :incomplete
    assert result.citations.verified_quotes == 0
    assert result.resolved_text == original
  end

  test "an unfinished wrapper across a replay is flagged without deleting any bytes" do
    for newline <- ["\n", "\r\n"] do
      original = "[" <> newline <> block(newline) <> newline <> @unknown <> "]"

      assert %{
               text: ^original,
               edits: [],
               actions: [%{state: :flagged, reason: :unpaired_wrapper}]
             } =
               Repair.repair(original)
    end
  end

  test "malformed and unterminated fences still protect their bytes" do
    for replay <- ["```pramana-replay\nnot JSON\n```", "```pramana-replay\nnot JSON"] do
      original = "「如是\n" <> replay <> "\n我聞」 [#{@urn}]"
      assert %{text: ^original, edits: []} = Repair.repair(original)
      assert %{status: :incomplete, malformed: [_]} = verify(original)
    end
  end

  test "a quotation and its address cannot be associated across a replay" do
    original = "「如是我聞。」\n" <> block() <> "\n[#{@urn}]"

    assert %{status: :incomplete, counts: %{verified_quotes: 0, existence_only: 1}} =
             verify(original)
  end

  test "foreign rewriting is region-local and preserves the subsequent Unicode byte offsets" do
    prefix = "🙂「如是我聞。」 [T. 262, 1a1]\n"
    replay = block()
    original = prefix <> replay <> "\n漢 e\u0301 「如是我聞。」 [#{@urn}]"
    result = verify(original)
    assert result.status == :verified
    assert result.counts.verified_quotes == 2
    assert result.counts.verified_replays == 1
    assert result.resolved_text =~ replay
    assert [%{source_offset: offset}] = result.foreign
    assert offset == byte_size("🙂「如是我聞。」 [")

    for finding <- result.citations.findings do
      range = finding.occurrence.quote_range

      assert binary_part(
               result.resolved_text,
               range.byte_start,
               range.byte_end - range.byte_start
             ) ==
               finding.quoted
    end
  end

  test "punctuation-only input does not authorize an arbitrary replacement" do
    original = "「……」 [#{@urn}]"

    assert %{text: ^original, edits: [], actions: [%{state: :flagged, reason: :empty_quote}]} =
             Repair.repair(original)
  end

  test "a short quotation is aligned without importing adjacent substantive words" do
    urn = "pramana:cbeta.T:T0262_001@p0001a02"

    assert %{text: repaired, actions: [%{state: :quote_relaxed}]} =
             Repair.repair("「唯我，獨尊」 [#{urn}]")

    assert repaired == "「唯我獨尊」 [#{urn}]"
    assert Guard.verify(urn, "唯我獨尊")
  end

  test "repeated and variant-equivalent source subspans are ambiguous" do
    urn = "pramana:cbeta.T:T0262_001@p0001a03"

    for quote <- ["佛，說", "佛説"] do
      original = "「#{quote}」 [#{urn}]"

      assert %{
               text: ^original,
               edits: [],
               actions: [%{state: :flagged, reason: :ambiguous_quote}]
             } =
               Repair.repair(original)
    end
  end
end
