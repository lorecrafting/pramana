defmodule Pramana.Pilot.ScopeTest do
  use ExUnit.Case, async: true

  alias Pramana.Pilot.Scope
  alias Pramana.Pilot.ScopeArtifact

  test "builds ten demand seeds plus four Agamas and stops relation expansion at two hops" do
    {:ok, artifact} = Scope.build(input_fixture())

    assert :ok = ScopeArtifact.validate(artifact)
    assert artifact["denominators"]["demand_seed_count"] == 10
    assert artifact["denominators"]["combined_seed_count"] == 14
    assert artifact["denominators"]["total_work_count"] == 16
    assert artifact["denominators"]["expanded_work_count"] == 2

    seed_ids = MapSet.new(Enum.map(artifact["seeds"], & &1["work_id"]))
    assert MapSet.subset?(MapSet.new(ScopeArtifact.agama_ids()), seed_ids)

    work_ids = MapSet.new(Enum.map(artifact["works"], & &1["work_id"]))
    assert MapSet.member?(work_ids, "T1800")
    assert MapSet.member?(work_ids, "T1830")
    refute MapSet.member?(work_ids, "T1900")

    assert Enum.any?(artifact["relations"], fn edge ->
             edge["source_work_id"] == "T1800" and edge["hop"] == 1
           end)

    assert Enum.any?(artifact["relations"], fn edge ->
             edge["source_work_id"] == "T1830" and edge["hop"] == 2
           end)
  end

  test "distinct hashes, not duplicate quotation rows, carry demand weight" do
    input = input_fixture()
    [first | rest] = input.quotation_rows

    duplicated = %{input | quotation_rows: [first, first, first | rest]}
    {:ok, artifact} = Scope.build(duplicated)

    top = artifact["ranking"]["top_demand"]
    original = Enum.find(top, &(&1["work_id"] == first.b_work_id))

    assert original["weight"] == 1
  end

  test "same-family quotation reuse is excluded from the demand denominator" do
    input = input_fixture()
    family_work = work("T0220a", "root", "大般若波羅蜜多經", 100, "般若部")
    family_work_2 = work("T0220b", "root", "大般若波羅蜜多經", 100, "般若部")

    input = %{
      input
      | works: [family_work, family_work_2 | input.works],
        quotation_rows: [
          %{a_work_id: "T0220a", b_work_id: "T0220b", text_sha256: hash("family")}
          | input.quotation_rows
        ]
    }

    {:ok, artifact} = Scope.build(input)
    assert artifact["ranking"]["cross_family_pairs"] == 10
  end

  test "role/date disagreement is reported as conflict and contributes no weight" do
    input = input_fixture()
    root = work("T0300", "root", "root", 900, "經集部")
    commentary = work("T1750", "commentary", "commentary", 100, "經疏部")

    input = %{
      input
      | works: [root, commentary | input.works],
        quotation_rows: [
          %{a_work_id: "T1750", b_work_id: "T0300", text_sha256: hash("conflict")}
          | input.quotation_rows
        ]
    }

    {:ok, artifact} = Scope.build(input)

    assert artifact["ranking"]["conflicting_pairs"] == 1
    refute Enum.any?(artifact["ranking"]["top_demand"], &(&1["work_id"] == "T0300"))
  end

  test "model assertions, role-incoherent rows and third-hop relations do not enter scope" do
    {:ok, artifact} = Scope.build(input_fixture())

    assert artifact["denominators"]["excluded_model_relation_rows"] == 1
    assert artifact["denominators"]["excluded_role_incoherent_relation_rows"] == 1

    refute Enum.any?(artifact["relations"], fn edge ->
             Enum.any?(edge["assertions"], &(&1["method"] == "llm"))
           end)

    refute Enum.any?(artifact["relations"], &(&1["source_work_id"] == "T0200"))
    refute Enum.any?(artifact["relations"], &(&1["source_work_id"] == "T1900"))
  end

  test "alignment coverage is counted only for admitted scope pairs" do
    {:ok, artifact} = Scope.build(input_fixture())

    row =
      Enum.find(artifact["alignment_coverage"], fn item ->
        item["commentary_work_id"] == "T1800" and item["target_work_id"] == "T0200"
      end)

    assert row["alignment_rows"] == 2
    assert row["distinct_root_urns"] == 2
    assert row["has_passage_alignment"]
    assert artifact["denominators"]["alignment_rows"] == 2
  end

  test "artifact is byte deterministic for identical semantic inputs" do
    {:ok, a} = Scope.build(input_fixture())
    {:ok, b} = Scope.build(input_fixture())

    assert ScopeArtifact.encode(a) == ScopeArtifact.encode(b)
    assert a["scope_content_sha256"] == b["scope_content_sha256"]
  end

  defp input_fixture do
    demand_roots =
      Enum.map(0..9, fn n ->
        id = "T02" <> String.pad_leading(Integer.to_string(n), 2, "0")
        work(id, "root", "demand #{n}", 100 + n, "經集部")
      end)

    demand_citers =
      Enum.map(0..9, fn n ->
        id = "T17" <> String.pad_leading(Integer.to_string(n), 2, "0")
        work(id, "commentary", "citer #{n}", 500 + n, "經疏部")
      end)

    agamas = [
      work("T0001", "root", "長阿含經", 100, "阿含部"),
      work("T0026", "root", "中阿含經", 100, "阿含部"),
      work("T0099", "root", "雜阿含經", 100, "阿含部"),
      work("T0125", "root", "增壹阿含經", 100, "阿含部")
    ]

    expansions = [
      work("T1800", "commentary", "first commentary", 600, "經疏部"),
      work("T1830", "subcommentary", "subcommentary", 700, "論疏部"),
      work("T1900", "subcommentary", "third hop", 800, "論疏部"),
      work("T1801", "commentary", "model-only", 610, "經疏部")
    ]

    quotation_rows =
      Enum.zip(demand_citers, demand_roots)
      |> Enum.map(fn {citer, root} ->
        %{
          a_work_id: citer.work_id,
          b_work_id: root.work_id,
          text_sha256: hash(citer.work_id <> root.work_id)
        }
      end)

    relation_rows = [
      relation("T1800", "T0200", "comments_on", "title_match", "certain"),
      relation("T1830", "T1800", "subcommentary_of", "manifest", "certain"),
      relation("T1900", "T1830", "subcommentary_of", "manifest", "certain"),
      relation("T1801", "T0200", "comments_on", "llm", "uncertain"),
      relation("T0200", "T1800", "comments_on", "manifest", "certain")
    ]

    alignment_rows = [
      alignment("T1800", "T0200", "r1", "c1", "l1"),
      alignment("T1800", "T0200", "r2", "c2", "l2"),
      alignment("T1900", "T1830", "r3", "c3", "l3")
    ]

    %{
      release: %{
        release_id: "release-test",
        source_bake_id: "bake-test",
        translation_set_id: "v2:translation-test",
        vector_set_id: "v2:vector-test",
        stamped_at: "2026-09-18T00:00:00Z"
      },
      works: agamas ++ demand_roots ++ demand_citers ++ expansions,
      quotation_rows: quotation_rows,
      relation_rows: relation_rows,
      alignment_rows: alignment_rows
    }
  end

  defp work(id, role, title, date_start, division) do
    %{
      work_id: id,
      text_role: role,
      title: title,
      date_start: date_start,
      date_end: date_start + 50,
      division: division
    }
  end

  defp relation(source, target, type, method, confidence) do
    %{
      source_work_id: source,
      target_work_id: target,
      target_work_ref: nil,
      relation: type,
      scope: "whole_work",
      target_urn: nil,
      confidence: confidence,
      method: method,
      evidence: %{"fixture" => true}
    }
  end

  defp alignment(commentary, root, root_urn, commentary_urn, lemma) do
    %{
      commentary_work_id: commentary,
      root_work_id: root,
      commentary_urn: commentary_urn,
      root_urn: root_urn,
      lemma_sha256: hash(lemma),
      method: "lemma_match",
      confidence: "certain"
    }
  end

  defp hash(value),
    do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
end
