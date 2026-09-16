defmodule Pramana.EvidenceAssociationFollowupTest do
  @moduledoc """
  Regression coverage for the post-merge evidence-integrity review.

  A repair may not change which quotation belongs to a surviving citation, and report
  canonicalization may not rewrite literal quotation bytes before the guard checks them.
  """
  use Pramana.DataCase, async: false

  alias Pramana.Citation
  alias Pramana.Corpus.Loader
  alias Pramana.Corpus.Source
  alias Pramana.Corpus.Witness
  alias Pramana.Corpus.Work
  alias Pramana.CorpusFixtures
  alias Pramana.Normalize.CBETA
  alias Pramana.Repair
  alias Pramana.Report
  alias Pramana.Repo

  @cbeta_urn "pramana:cbeta.T:T0262_001@p0006a23"
  @sc_urn "pramana:sc.ms:mn1@1.1"
  @literal_urn "pramana:cbeta.T:T8888_001@p0001a01"

  @xml """
  <TEI xmlns="http://www.tei-c.org/ns/1.0" xmlns:cb="http://www.cbeta.org/ns/1.0">
  <teiHeader><fileDesc><titleStmt>
    <title level="m" xml:lang="zh-Hant">妙法蓮華經</title><author>姚秦 鳩摩羅什譯</author>
  </titleStmt></fileDesc></teiHeader>
  <text><body>
  <milestone n="1" unit="juan"/>
  <lb n="0006a23"/>如是我聞一時佛住
  </body></text></TEI>
  """

  setup do
    {:ok, ir} = CBETA.normalize(@xml, work_id: "T0262", canon: "T", volume: 9, number: "0262")

    {:ok, _} =
      Loader.load(ir,
        source: "cbeta",
        witness: "T",
        provenance: %{composition_origin: "indic", text_role: "root"}
      )

    Repo.insert!(%Source{
      id: "sc",
      name: "SuttaCentral",
      license_spdx: "CC0-1.0",
      license_class: "cc0",
      commercial_use: true,
      redistributable: true
    })

    Repo.insert!(%Witness{id: "ms", name: "Mahāsaṅgīti"})
    Repo.insert!(%Work{id: "mn1", title: "Mūlapariyāya"})

    CorpusFixtures.text!(
      %{
        work_id: "mn1",
        source_id: "sc",
        witness_id: "ms",
        urn_prefix: "pramana:sc.ms:mn1",
        meta: %{}
      },
      [{@sc_urn, "mn1:1.1"}]
    )

    Repo.insert!(%Work{id: "T8888", title: "Literal-address witness"})

    CorpusFixtures.text!(
      %{
        work_id: "T8888",
        source_id: "cbeta",
        witness_id: "T",
        urn_prefix: "pramana:cbeta.T:T8888",
        meta: %{}
      },
      [{@literal_urn, "T. 262, 6a23"}]
    )

    :ok
  end

  test "deleting one citation cannot rebind its quotation to a surviving citation" do
    unsupported = "pramana:cbeta.T:T9999_001@p0001a01"

    original =
      "🙂 e\u0301 「這句並不存在」 [#{unsupported}] [#{@cbeta_urn}]；另見 [#{@cbeta_urn}]."

    result = Repair.repair(original)

    assert result.original == original
    assert result.text == original
    assert result.edits == []
    refute result.repaired?

    assert [
             %{state: :flagged, reason: :citation_rebinding},
             %{state: :existence_only},
             %{state: :existence_only}
           ] = result.actions
  end

  test "foreign addresses inside literal quotations stay byte-identical while outside addresses rewrite" do
    original = "Literal 「T. 262, 6a23」; compare T. 262, 6a23."
    {rewritten, found} = Citation.rewrite(original)

    assert rewritten == "Literal 「T. 262, 6a23」; compare #{@cbeta_urn}."
    assert length(found) == 2
    assert Enum.all?(found, &(&1.urn == @cbeta_urn))
  end

  test "report verifies a SuttaCentral-looking literal without rewriting its evidence bytes" do
    original = "「mn1:1.1」 [#{@sc_urn}]"

    result =
      Report.verify(original,
        executor: fn _, _ -> flunk("no replay expected") end,
        bake_id: "b"
      )

    assert result.status == :verified
    assert result.ok?
    assert result.resolved_text == original
    assert result.citations.checked == 1
    assert result.citations.verified_quotes == 1
    assert [%{matched: "mn1:1.1", urn: @sc_urn}] = result.foreign
  end

  test "report preserves a Taisho-looking literal cited by a different canonical witness" do
    original = "「T. 262, 6a23」 [#{@literal_urn}]"

    result =
      Report.verify(original,
        executor: fn _, _ -> flunk("no replay expected") end,
        bake_id: "b"
      )

    assert result.status == :verified
    assert result.ok?
    assert result.resolved_text == original
    assert result.citations.checked == 1
    assert result.citations.verified_quotes == 1
    assert [%{matched: "T. 262, 6a23", urn: @cbeta_urn}] = result.foreign
  end

  test "an outer foreign citation still canonicalizes and verifies its quotation" do
    original = "「如是我聞一時佛住」 T. 262, 6a23"

    result =
      Report.verify(original,
        executor: fn _, _ -> flunk("no replay expected") end,
        bake_id: "b"
      )

    assert result.status == :verified
    assert result.ok?
    assert result.resolved_text == "「如是我聞一時佛住」 #{@cbeta_urn}"
    assert result.citations.checked == 1
    assert result.citations.verified_quotes == 1
  end
end
