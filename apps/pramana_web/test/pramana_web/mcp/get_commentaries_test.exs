defmodule PramanaWeb.MCP.GetCommentariesTest do
  @moduledoc """
  The tool that answers "commentary **on the Lotus Sūtra**" rather than "Chinese
  commentary".

  The property that matters most is not that it finds the links — it is that pulling a
  commentary into an answer never lets it be quoted *as* the text it explains. Same rule
  as invariant #7 for generated translations: helpful, attributable, never citable as
  the root.
  """
  use Pramana.DataCase, async: false

  alias Pramana.Corpus.Work
  alias Pramana.Relations
  alias Pramana.Repo
  alias PramanaWeb.MCP.Tools.GetCommentaries

  defp work!(id, attrs) do
    Repo.insert!(
      struct(
        %Work{id: id, title: id, composition_origin: "chinese", text_role: "commentary"},
        attrs
      )
    )
  end

  setup do
    work!("T0262", %{title: "妙法蓮華經", text_role: "root", composition_origin: "indic"})
    work!("T1718", %{title: "法華文句", date_start: 587, date_end: 597, date_basis: "catalogue"})

    work!("T1719", %{
      title: "法華文句記",
      text_role: "subcommentary",
      date_start: 765,
      date_basis: "catalogue"
    })

    work!("JP001", %{
      title: "法華義疏",
      composition_origin: "japanese",
      date_start: 615,
      date_basis: "catalogue"
    })

    for {source, target, relation} <- [
          {"T1718", "T0262", "comments_on"},
          {"JP001", "T0262", "comments_on"},
          {"T1719", "T1718", "subcommentary_of"}
        ] do
      {:ok, _} =
        Relations.assert(%{
          source_work_id: source,
          target_work_id: target,
          relation: relation,
          method: "catalogue",
          confidence: "certain"
        })
    end

    :ok
  end

  defp call!(params),
    do:
      GetCommentaries.execute(params, %{})
      |> elem(1)
      |> Map.fetch!(:content)
      |> hd()
      |> Map.fetch!("text")
      |> Jason.decode!()

  describe "what explains a work" do
    test "returns the commentaries pointing at it" do
      data = call!(%{work_id: "T0262"})

      assert data["total"] == 2
      ids = data["groups"] |> Enum.flat_map(& &1["works"]) |> Enum.map(& &1["work_id"])
      assert Enum.sort(ids) == ["JP001", "T1718"]
    end

    test "separates a Japanese commentary from a Chinese one" do
      # A 7th-century Chinese gloss and a Japanese one are different evidence about the
      # same sūtra, and must not arrive in one undifferentiated pile.
      labels = call!(%{work_id: "T0262"})["groups"] |> Enum.map(& &1["label"])

      assert "Chinese-composed commentary" in labels
      assert "Japanese-composed commentary" in labels
    end

    test "carries the period, so a 7th-century gloss is not mistaken for a modern one" do
      work = call!(%{work_id: "T0262"})["groups"] |> Enum.flat_map(& &1["works"]) |> hd()
      assert work["period"]
    end

    test "every result states how the link was established" do
      for group <- call!(%{work_id: "T0262"})["groups"], w <- group["works"] do
        assert w["method"] == "catalogue"
        assert w["confidence"] == "certain"
      end
    end

    test "says plainly that these works are NOT the text they explain" do
      # The whole reason relations exist is that this distinction survives into the
      # answer rather than being flattened.
      note = call!(%{work_id: "T0262"})["note"]

      assert note =~ "EXPLAIN T0262"
      assert note =~ "never to the text it comments on"
    end

    test "returns no quotable text at all" do
      # To quote a commentary you fetch its passages by URN, where the guard applies.
      json = call!(%{work_id: "T0262"}) |> Jason.encode!()
      refute json =~ "content"
      refute json =~ "sha256"
    end

    test "a work nothing explains returns an empty list rather than erroring" do
      assert call!(%{work_id: "JP001"})["total"] == 0
    end
  end

  describe "what a work explains" do
    test "walks the chain and returns every intermediate layer" do
      data = call!(%{work_id: "T1719", direction: "this_explains"})

      assert data["depth"] == 2
      assert Enum.map(data["chain"], & &1["work_id"]) == ["T1718", "T0262"]
    end

    test "a root text is reported as explaining nothing" do
      data = call!(%{work_id: "T0262", direction: "this_explains"})

      assert data["depth"] == 0
      assert data["note"] =~ "may be a root text"
    end

    test "a declared target outside the corpus is reported as asserted, not unknown" do
      # Regression: the Huang Nianzu commentary declares `comments_on:
      # xia-lianju-conflation`, which is not ingested. Reporting only the walkable chain
      # said "not recorded as explaining anything — it may be a root text", which is
      # false and is the absence-mistaken-for-silence error in miniature.
      work!("LOCAL1", %{title: "現代註解"})

      {:ok, _} =
        Relations.assert(%{
          source_work_id: "LOCAL1",
          target_work_ref: "xia-lianju-conflation",
          relation: "comments_on",
          method: "manifest"
        })

      data = call!(%{work_id: "LOCAL1", direction: "this_explains"})

      assert data["depth"] == 0
      assert data["note"] =~ "xia-lianju-conflation"
      assert data["note"] =~ "asserted, not unknown"
      refute data["note"] =~ "may be a root text"
      assert [%{"work_ref" => "xia-lianju-conflation"}] = data["unresolved_targets"]
    end
  end

  test "names the corpus it answered from" do
    assert Map.has_key?(call!(%{work_id: "T0262"}), "bake_id")
  end
end
