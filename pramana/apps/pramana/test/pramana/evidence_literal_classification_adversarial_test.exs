defmodule Pramana.EvidenceLiteralClassificationAdversarialTest do
  @moduledoc """
  Adversarial regressions for foreign-looking text inside literal quotations.

  Quotation marks alone do not prove that a foreign-looking token is source evidence. The
  token is literal content only when a Guard citation actually consumes that exact quote.
  """
  use Pramana.DataCase, async: false

  alias Pramana.Corpus.Loader
  alias Pramana.Normalize.CBETA
  alias Pramana.Report

  @cbeta_urn "pramana:cbeta.T:T0262_001@p0006a23"
  @literal_urn "pramana:cbeta.T:T8889_001@p0001a01"

  @cbeta_xml """
  <TEI xmlns="http://www.tei-c.org/ns/1.0" xmlns:cb="http://www.cbeta.org/ns/1.0">
  <teiHeader><fileDesc><titleStmt>
    <title level="m" xml:lang="zh-Hant">妙法蓮華經</title><author>姚秦 鳩摩羅什譯</author>
  </titleStmt></fileDesc></teiHeader>
  <text><body>
  <milestone n="1" unit="juan"/>
  <lb n="0006a23"/>如是我聞一時佛住
  </body></text></TEI>
  """

  @literal_xml """
  <TEI xmlns="http://www.tei-c.org/ns/1.0" xmlns:cb="http://www.cbeta.org/ns/1.0">
  <teiHeader><fileDesc><titleStmt>
    <title level="m" xml:lang="zh-Hant">Literal address witness</title>
  </titleStmt></fileDesc></teiHeader>
  <text><body>
  <milestone n="1" unit="juan"/>
  <lb n="0001a01"/>T. 262, 99a1
  </body></text></TEI>
  """

  setup do
    load!(@cbeta_xml, "T0262", 9, "0262")
    load!(@literal_xml, "T8889", 85, "8889")
    :ok
  end

  test "a resolved foreign token in an unpaired literal quote keeps a mixed report incomplete" do
    original =
      ~s("T. 262, 6a23" is a citation label. 「如是我聞一時佛住」 [#{@cbeta_urn}])

    result = verify(original)

    assert result.citations.verified_quotes == 1
    assert [%{quoted: "如是我聞一時佛住", verdict: :ok}] = result.citations.findings
    assert result.counts.unresolved_foreign == 0
    assert result.counts.unchecked_foreign == 1
    assert result.counts.literal_foreign == 0
    assert [%{matched: "T. 262, 6a23", evidence_role: :unchecked}] = result.foreign
    assert result.status == :incomplete
    refute result.ok?
  end

  test "an unresolved foreign-looking token inside a checked canonical quote is literal content" do
    original = "「T. 262, 99a1」 [#{@literal_urn}]"
    result = verify(original)

    assert result.citations.verified_quotes == 1
    assert result.counts.unresolved_foreign == 0
    assert result.counts.unchecked_foreign == 0
    assert result.counts.literal_foreign == 1
    assert result.status == :verified
    assert result.ok?

    assert [%{matched: "T. 262, 99a1", urn: nil, evidence_role: :literal}] = result.foreign
  end

  test "literal classification survives when the outer citation is foreign and rewritten" do
    original = "「T. 262, 99a1」 T. 8889, 1a1"
    result = verify(original)

    assert result.resolved_text == "「T. 262, 99a1」 #{@literal_urn}"
    assert result.citations.verified_quotes == 1
    assert result.counts.unresolved_foreign == 0
    assert result.counts.unchecked_foreign == 0
    assert result.counts.literal_foreign == 1

    assert [
             %{matched: "T. 262, 99a1", evidence_role: :literal},
             %{matched: "T. 8889, 1a1", evidence_role: :checked}
           ] = result.foreign

    assert result.status == :verified
    assert result.ok?
  end

  test "an earlier length-changing rewrite does not corrupt later literal classification" do
    original = "See T. 262, 6a23. Then 「T. 262, 99a1」 [#{@literal_urn}]"
    result = verify(original)

    assert result.resolved_text ==
             "See #{@cbeta_urn}. Then 「T. 262, 99a1」 [#{@literal_urn}]"

    assert result.citations.verified_quotes == 1
    assert result.citations.existence_only == 1
    assert result.counts.unresolved_foreign == 0
    assert result.counts.unchecked_foreign == 0
    assert result.counts.literal_foreign == 1
    assert result.status == :incomplete
  end

  defp verify(markdown) do
    Report.verify(markdown,
      executor: fn _, _ -> flunk("no replay expected") end,
      bake_id: "b"
    )
  end

  defp load!(xml, work_id, volume, number) do
    {:ok, ir} = CBETA.normalize(xml, work_id: work_id, canon: "T", volume: volume, number: number)

    {:ok, _} =
      Loader.load(ir,
        source: "cbeta",
        witness: "T",
        provenance: %{composition_origin: "indic", text_role: "root"}
      )
  end
end
