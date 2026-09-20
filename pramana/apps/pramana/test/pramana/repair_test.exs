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
  alias Pramana.Guard
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
  test "a mismatching quotation with no searched replacement loses only its unsupported citation" do
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

  test "an ambiguous quotation is flagged without changing the document" do
    text = ~s(The text says 「佛說妙法蓮華經。」 #{@urn}.)

    assert %{
             text: repaired,
             actions: [%{state: :flagged, reason: :ambiguous}],
             repaired?: false
           } = Repair.repair(text)

    assert repaired == text
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

  test "deleting an unsupported occurrence preserves a correct use of the same URN and all other bytes" do
    first = "前文🙂 e\u0301  「如是我聞，一時佛住。」【#{@urn}】\n\n"
    second = "後文  「這是完全捏造的句子」【#{@urn}】。  保留空白\n"
    original = first <> second
    result = Repair.repair(original)

    assert result.original == original
    assert result.text == first <> "後文  「這是完全捏造的句子」。  保留空白\n"
    assert [%{state: :verified}, %{state: :no_sources}] = result.actions
    assert [edit] = result.edits
    assert edit.before == "【#{@urn}】"
    assert edit.after == ""

    assert binary_part(
             original,
             edit.range.byte_start,
             edit.range.byte_end - edit.range.byte_start
           ) == edit.before

    assert result.repaired?
  end

  test "correcting one address does not rewrite another valid occurrence" do
    good = "「如是我聞，一時佛住。」 #{@urn}. "
    wrong = "「王舍城耆闍崛山中。」 #{@urn}."
    result = Repair.repair(good <> wrong)

    assert result.text == good <> "「王舍城耆闍崛山中。」 pramana:cbeta.T:T0262_001@p0001c18."
    assert [%{state: :verified}, %{state: :citation_corrected}] = result.actions
    assert length(result.edits) == 1
  end

  test "quotation replacement changes only the quoted occurrence, not identical unrelated prose" do
    original = "如是我聞一時佛住\n「如是我聞一時佛住」 [#{@urn}].\n如是我聞一時佛住"
    result = Repair.repair(original)
    assert result.text == "如是我聞一時佛住\n「如是我聞，一時佛住。」 [#{@urn}].\n如是我聞一時佛住"
  end

  test "different-length edits use original offsets and apply without shifting the other edit" do
    original = "🙂「如是我聞一時佛住」 (#{@urn})。\n「這是完全捏造的句子」【#{@urn}】。"
    result = Repair.repair(original)
    assert result.text == "🙂「如是我聞，一時佛住。」 (#{@urn})。\n「這是完全捏造的句子」。"
    assert length(result.edits) == 2
  end

  test "a failed diagnostic search never authorizes deletion" do
    original = "「這段文字未能查明」 #{@urn}"
    result = Repair.repair(original, search: fn _, _ -> {:error, :timeout} end)
    assert result.text == original
    assert result.edits == []
    assert [%{state: :flagged, reason: :search_unavailable}] = result.actions
  end

  test "a search candidate must verify the original quotation before changing its address" do
    original = "「王舍城，耆闍崛山中」 #{@urn}"
    result = Repair.repair(original)
    assert result.text == original
    assert [%{state: :flagged, reason: :replacement_not_exact}] = result.actions
  end

  test "nested citation edits are flagged rather than applied in a destructive order" do
    inner = "pramana:cbeta:T0262"
    outer = "pramana:cbeta.T:T8888_001@p0001a01"
    Repo.insert!(%Pramana.Corpus.Work{id: "T8888"})

    Pramana.CorpusFixtures.text!(
      %{
        work_id: "T8888",
        source_id: "cbeta",
        witness_id: "T",
        urn_prefix: "pramana:cbeta.T:T8888"
      },
      [{outer, "Note #{inner}"}]
    )

    # The supported editorial mark is full-width, not ASCII comma. Establish
    # that a quote replacement really overlaps the nested citation deletion.
    original = ~s("Note， #{inner}" [#{outer}])

    assert %{verdict: :quote_mismatch, reason: :editorial_punctuation} =
             outer |> Guard.check("Note， #{inner}") |> Guard.diagnose()

    result = Repair.repair(original)
    assert result.text == original
    assert result.edits == []
    assert length(result.actions) == 2
    assert Enum.all?(result.actions, &(&1.reason == :overlapping_edits))
  end

  test "an inner deletion cannot invalidate a verified outer quotation that needs no edit" do
    inner = "pramana:cbeta:T0262"
    outer = "pramana:cbeta.T:T8888_001@p0001a01"
    quoted = "Note #{inner}"
    Repo.insert!(%Pramana.Corpus.Work{id: "T8888"})

    Pramana.CorpusFixtures.text!(
      %{
        work_id: "T8888",
        source_id: "cbeta",
        witness_id: "T",
        urn_prefix: "pramana:cbeta.T:T8888"
      },
      [{outer, quoted}]
    )

    assert Guard.verify(outer, quoted)
    assert %{verdict: :bad_urn} = Guard.check(inner)
    original = ~s("#{quoted}" [#{outer}])
    result = Repair.repair(original)

    assert result.text == original
    assert result.edits == []
    assert length(result.actions) == 2
    assert Enum.all?(result.actions, &(&1.reason == :overlapping_edits))
    assert Guard.verify(outer, quoted)
  end

  test "a bare address is existence-only, not a verified quotation" do
    original = "See #{@urn}."

    assert %{text: ^original, actions: [%{state: :existence_only}], edits: []} =
             Repair.repair(original)
  end
end
