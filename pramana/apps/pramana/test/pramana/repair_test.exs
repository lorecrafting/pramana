defmodule Pramana.RepairTest do
  @moduledoc """
  Repairing a document's citations without inventing any.

  A repairer is more dangerous than a checker. A checker that is wrong wastes an
  afternoon; a repairer that is wrong hands back a document whose citations all resolve
  and some of which are false, which is worse than what came in. So every test here is
  about a refusal as much as a fix.
  """
  use Pramana.DataCase, async: false

  alias Pramana.Corpus.Loader
  alias Pramana.Normalize.CBETA
  alias Pramana.Repair

  @xml """
  <TEI xmlns="http://www.tei-c.org/ns/1.0" xmlns:cb="http://www.cbeta.org/ns/1.0">
  <teiHeader><fileDesc><titleStmt>
    <title level="m" xml:lang="zh-Hant">妙法蓮華經</title><author>姚秦 鳩摩羅什譯</author>
  </titleStmt></fileDesc></teiHeader>
  <text><body>
  <milestone n="1" unit="juan"/>
  <lb n="0001c17"/>如是我聞，一時佛住。
  <lb n="0001c18"/>王舍城耆闍崛山中。
  <lb n="0001c19"/>佛說妙法蓮華經。
  <lb n="0001c20"/>佛說妙法蓮華經。
  </body></text></TEI>
  """

  @urn "pramana:cbeta.T:T0262_001@p0001c17"

  setup do
    {:ok, ir} = CBETA.normalize(@xml, work_id: "T0262", canon: "T", volume: 9, number: "0262")

    {:ok, _} =
      Loader.load(ir,
        source: "cbeta",
        witness: "T",
        provenance: %{composition_origin: "indic", text_role: "root"}
      )

    :ok
  end

  test "a citation that is already right is left exactly alone" do
    text = ~s(The sūtra opens 「如是我聞，一時佛住。」 #{@urn}.)

    assert %{text: ^text, repaired?: false, actions: [%{state: :verified}]} = Repair.repair(text)
  end

  # The words are the corpus's and the punctuation is an editor's. Replacing the quotation
  # with the line's own text makes it verbatim rather than making it plausible — the
  # replacement IS the thing being cited.
  test "a quotation differing only in editorial punctuation is relaxed to what is printed" do
    text = ~s(It opens 「如是我聞一時佛住」 #{@urn}.)

    assert %{text: repaired, actions: [%{state: :quote_relaxed}], repaired?: true} =
             Repair.repair(text)

    assert repaired =~ "如是我聞，一時佛住。"
  end

  # THE REFUSAL THAT MATTERS MOST. Nothing supports it, so the citation goes and the
  # sentence stays — the prose may still be worth saying, and the citation was the lie.
  test "a fabricated quotation loses its citation and keeps its prose" do
    text = ~s(The text says 「這是完全捏造的句子」 #{@urn}.)

    assert %{actions: [%{state: :no_sources}], text: repaired} = Repair.repair(text)

    refute repaired =~ @urn
    assert repaired =~ "The text says"
  end

  test "a URN resolving to nothing is stripped rather than left asserting a source" do
    text = ~s(As stated at pramana:cbeta.T:T0262_001@p9999z99.)

    assert %{actions: [%{state: :no_sources, reason: :not_found}]} = Repair.repair(text)
  end

  test "a quotation differing in orthographic variant is relaxed to what is printed" do
    urn = "pramana:cbeta.T:T0262_001@p0001c19"
    text = ~s(The chapter begins 「佛説妙法蓮華經」 #{urn}.)

    assert %{
             text: repaired,
             actions: [%{state: :quote_relaxed, reason: :orthographic_variant}],
             repaired?: true
           } = Repair.repair(text)

    assert repaired =~ "佛說妙法蓮華經。"
  end

  test "a quotation appearing uniquely at another line has its URN corrected" do
    text = ~s(The text says 「王舍城耆闍崛山中。」 #{@urn}.)

    assert %{
             text: repaired,
             actions: [
               %{
                 state: :citation_corrected,
                 reason: :wrong_address,
                 replaced_urn: "pramana:cbeta.T:T0262_001@p0001c18"
               }
             ],
             repaired?: true
           } = Repair.repair(text)

    assert repaired =~ "pramana:cbeta.T:T0262_001@p0001c18"
    refute repaired =~ @urn
  end

  test "an ambiguous quotation appearing in multiple places loses its citation" do
    text = ~s(The text says 「佛說妙法蓮華經。」 #{@urn}.)

    assert %{
             text: repaired,
             actions: [%{state: :no_sources, reason: :ambiguous}],
             repaired?: false
           } = Repair.repair(text)

    refute repaired =~ @urn
    assert repaired =~ "The text says"
  end

  test "a quotation spanning across a line boundary is flagged rather than corrupted" do
    text = ~s(The text says 「一時佛住王舍城」 #{@urn}.)

    assert %{
             text: ^text,
             actions: [%{state: :flagged, reason: :spans_line_boundary}],
             repaired?: false
           } = Repair.repair(text)
  end

  test "a malformed URN is marked no_sources" do
    text = ~s(The text says 「如是我聞」 [pramana:cbeta:T0262].)

    assert %{actions: [%{state: :no_sources, reason: :bad_urn}]} = Repair.repair(text)
  end

  test "invariant #8: a generated translation quoted as source is flagged" do
    alias Pramana.Translations

    {:ok, _} =
      Translations.store([
        %{
          anchor_urn: @urn,
          work_id: "T0262",
          lang: "en",
          translator_id: "model:gpt4",
          tier: "t1",
          method: "llm",
          model_id: "gpt-4",
          text: "Thus have I heard.",
          redistributable: true,
          license_class: "cc0"
        }
      ])

    text = ~s(As stated 「Thus have I heard.」 [#{@urn}#tr:en/model:gpt4].)

    assert %{
             text: ^text,
             actions: [%{state: :flagged, reason: :not_citable_as_source}],
             repaired?: false
           } = Repair.repair(text)
  end
end
