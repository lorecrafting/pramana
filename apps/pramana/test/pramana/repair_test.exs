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

  # NOT TESTED HERE: `flagged` for a translation quoted as source (invariant #8) and for a
  # quotation spanning a printed line boundary. Both need corpus state this fixture does
  # not have — a stored generated rendering, and a quotation genuinely continuous across
  # two lines — and a test that reached the planner directly would assert the mapping
  # while proving nothing about what ships. `Pramana.Guard`'s own tests cover the verdicts
  # those two states are derived from.
end
