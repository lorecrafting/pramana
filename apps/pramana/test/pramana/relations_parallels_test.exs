defmodule Pramana.RelationsParallelsTest do
  @moduledoc """
  Work-level `parallel_of`, and the claim it deliberately does not make.

  These relations are derived from SuttaCentral's curated passage parallels, aggregated to
  the work. The tests that matter are the ones pinning the LIMITS of the claim: a parallel
  is a sibling, never a translation, and the relation must be findable from either end.
  """
  use Pramana.DataCase, async: true

  alias Pramana.Relations

  defp work!(id, attrs \\ %{}) do
    Pramana.Repo.insert_all("works", [
      Map.merge(
        %{
          id: id,
          title: "title-#{id}",
          composition_origin: "indic",
          text_role: "root",
          inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
          updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
        },
        attrs
      )
    ])

    id
  end

  defp parallel!(a, b, full, confidence) do
    evidence = %{"full_parallels" => full, "derived_from" => "text_parallels"}

    for {s, t} <- [{a, b}, {b, a}] do
      {:ok, _} =
        Relations.assert(%{
          source_work_id: s,
          target_work_id: t,
          relation: "parallel_of",
          method: "catalogue",
          confidence: confidence,
          scope: "whole_work",
          evidence: evidence
        })
    end

    :ok
  end

  describe "parallels_of/1" do
    test "finds the parallel from either end" do
      # A parallel has no direction. Storing one way and hoping every caller checks both
      # is the kind of thing that is silently wrong exactly half the time.
      work!("W0099", %{title: "雜阿含經", attributed_author: "求那跋陀羅"})
      work!("W0100", %{title: "別譯雜阿含經", attributed_author: "失譯"})
      parallel!("W0099", "W0100", 706, "probable")

      assert [%{work_id: "W0100"}] = Relations.parallels_of("W0099")
      assert [%{work_id: "W0099"}] = Relations.parallels_of("W0100")
    end

    test "carries the evidence a reader needs to judge the claim" do
      work!("W0099")
      work!("W0100")
      parallel!("W0099", "W0100", 706, "probable")

      [rel] = Relations.parallels_of("W0099")

      assert rel.relation == "parallel_of"
      assert rel.confidence == "probable"
      assert rel.method == "catalogue"
      assert rel.evidence["full_parallels"] == 706
    end

    test "carries the translator, which is what makes #23 possible" do
      # Translator fingerprinting compares how two translators rendered the same material.
      # That needs the attribution beside the relation, not a second lookup.
      work!("W0099", %{attributed_author: "劉宋 求那跋陀羅譯"})
      work!("W0212", %{attributed_author: "姚秦 竺佛念譯"})
      parallel!("W0099", "W0212", 14, "probable")

      assert [%{attributed_author: "姚秦 竺佛念譯"}] = Relations.parallels_of("W0099")
    end

    test "the strongest pair comes first" do
      work!("W0099")
      work!("W0100")
      work!("W0765")
      parallel!("W0099", "W0765", 14, "probable")
      parallel!("W0099", "W0100", 706, "probable")

      assert ["W0100", "W0765"] = Relations.parallels_of("W0099") |> Enum.map(& &1.work_id)
    end

    test "a confident pair outranks a stronger but less confident one" do
      # Confidence is a claim about the assertion; evidence count only breaks ties within
      # it. A pair someone is unsure about does not lead because it happens to share more
      # passages.
      work!("W0099")
      work!("W0100")
      work!("W0765")
      parallel!("W0099", "W0100", 12, "probable")
      parallel!("W0099", "W0765", 900, "uncertain")

      assert ["W0100", "W0765"] = Relations.parallels_of("W0099") |> Enum.map(& &1.work_id)
    end

    test "returns nothing for a work with no parallels" do
      work!("W9999")

      assert Relations.parallels_of("W9999") == []
    end

    test "does not return commentary relations" do
      # `parallel_of` is a sibling; `comments_on` is a parent. Conflating them would let a
      # commentary be presented as a version of the text it explains.
      work!("W0262")
      work!("W1718")

      {:ok, _} =
        Relations.assert(%{
          source_work_id: "W1718",
          target_work_id: "W0262",
          relation: "comments_on",
          method: "title_match",
          confidence: "probable"
        })

      assert Relations.parallels_of("W1718") == []
    end
  end
end
