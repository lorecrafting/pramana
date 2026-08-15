defmodule PramanaWeb.MCP.SurveyAndOutlineTest do
  @moduledoc """
  `survey_corpus` and `get_outline` are the two tools that let a model reason about the
  canon *without* reading it, and both were nearly untested.

  They matter for opposite reasons. `survey_corpus` is what turns "here are five
  passages" into a defensible claim about how often and where something occurs — a model
  handed five results will generalise from five results. `get_outline` is what makes a
  4.7-million-segment corpus navigable at all.
  """
  use Pramana.DataCase, async: true

  alias Pramana.Corpus.Loader
  alias Pramana.Normalize.CBETA
  alias PramanaWeb.MCP.Tools.GetOutline
  alias PramanaWeb.MCP.Tools.SurveyCorpus

  # Two works so the breakdowns have something to break down: an Indic root text and a
  # Chinese commentary that quotes it. Both contain 佛性.
  @root """
  <TEI xmlns="http://www.tei-c.org/ns/1.0" xmlns:cb="http://www.cbeta.org/ns/1.0">
  <teiHeader><fileDesc><titleStmt>
    <title level="m" xml:lang="zh-Hant">大般涅槃經</title>
  </titleStmt></fileDesc></teiHeader>
  <text><body>
  <milestone n="1" unit="juan"/>
  <cb:mulu level="1" type="品">壽命品</cb:mulu>
  <lb n="0001a01"/>一切眾生皆有佛性
  <lb n="0001a02"/>如來常住無有變易
  <milestone n="2" unit="juan"/>
  <cb:mulu level="1" type="品">金剛身品</cb:mulu>
  <lb n="0010b01"/>佛性者名第一義空
  </body></text></TEI>
  """

  @commentary """
  <TEI xmlns="http://www.tei-c.org/ns/1.0" xmlns:cb="http://www.cbeta.org/ns/1.0">
  <teiHeader><fileDesc><titleStmt>
    <title level="m" xml:lang="zh-Hant">涅槃經疏</title>
  </titleStmt></fileDesc></teiHeader>
  <text><body>
  <milestone n="1" unit="juan"/>
  <lb n="0100a01"/>釋曰佛性者眾生本具
  </body></text></TEI>
  """

  setup do
    load!(@root, "T0374", 12, "0374", %{
      composition_origin: "indic",
      text_role: "root",
      division: "涅槃部",
      division_en: "Nirvāṇa"
    })

    load!(@commentary, "T1767", 38, "1767", %{
      composition_origin: "chinese",
      text_role: "commentary",
      division: "經疏部",
      division_en: "Sūtra commentary"
    })

    :ok
  end

  defp load!(xml, work_id, volume, number, provenance) do
    {:ok, ir} = CBETA.normalize(xml, work_id: work_id, canon: "T", volume: volume, number: number)
    {:ok, _} = Loader.load(ir, source: "cbeta", witness: "T", provenance: provenance)
  end

  defp payload(response),
    do: response |> Map.fetch!(:content) |> hd() |> Map.fetch!("text") |> Jason.decode!()

  describe "survey_corpus" do
    test "counts every occurrence, not a ranked sample" do
      {:reply, response, _} = SurveyCorpus.execute(%{query: "佛性"}, %{})
      data = payload(response)

      # 佛性 appears on three lines across two works. A tool that reported the two or
      # three it happened to rank first would support a different, weaker claim.
      assert data["total_segments"] == 3
      assert data["distinct_works"] == 2
    end

    test "breaks results down by the provenance axes" do
      {:reply, response, _} = SurveyCorpus.execute(%{query: "佛性"}, %{})
      data = payload(response)

      # Note the shape is not uniform: the origin and role breakdowns key on "key"
      # while the division breakdown keys on "division". Worth knowing before writing
      # a client against it.
      origins = Map.new(data["by_origin"], &{&1["key"], &1["segments"]})
      assert origins == %{"indic" => 2, "chinese" => 1}

      roles = Map.new(data["by_role"], &{&1["key"], &1["segments"]})
      assert roles == %{"root" => 2, "commentary" => 1}

      divisions = Map.new(data["by_division"], &{&1["division"], &1["segments"]})
      assert divisions == %{"涅槃部" => 2, "經疏部" => 1}
    end

    test "each declared filter actually filters" do
      # An accepted-but-ignored filter is the defect class that already bit this project
      # once: results looked filtered and were not.
      for {params, expected} <- [
            {%{query: "佛性", origin: "indic"}, 2},
            {%{query: "佛性", origin: "chinese"}, 1},
            {%{query: "佛性", role: "commentary"}, 1},
            {%{query: "佛性", division: "涅槃部"}, 2}
          ] do
        {:reply, response, _} = SurveyCorpus.execute(params, %{})

        assert payload(response)["total_segments"] == expected,
               "filter #{inspect(params)} did not restrict the count"
      end
    end

    test "names the corpus it counted" do
      # The key must always be present. Its VALUE is nil here only because the test
      # database holds no bake record — the tool reports that honestly rather than
      # inventing an id.
      {:reply, response, _} = SurveyCorpus.execute(%{query: "佛性"}, %{})
      assert Map.has_key?(payload(response), "bake_id")
    end

    test "reports zero honestly rather than erroring" do
      # "The canon does not contain this" is a real, useful answer.
      {:reply, response, _} = SurveyCorpus.execute(%{query: "絕無此語"}, %{})
      data = payload(response)

      assert data["total_segments"] == 0
      assert data["distinct_works"] == 0
    end

    test "ranks the works carrying the phrase" do
      {:reply, response, _} = SurveyCorpus.execute(%{query: "佛性", top_works: 1}, %{})
      top = payload(response)["top_works"]

      assert length(top) == 1
      assert hd(top)["work_id"] == "T0374"
    end
  end

  describe "get_outline" do
    test "returns CBETA's own structure, anchored to URNs" do
      {:reply, response, _} = GetOutline.execute(%{work_id: "T0374"}, %{})
      data = payload(response)

      assert data["work_id"] == "T0374"
      assert data["juan_count"] == 2
      assert data["urn_prefix"] == "pramana:cbeta.T:T0374"

      titles = Enum.map(data["entries"], & &1["title"])
      assert "壽命品" in titles
      assert "金剛身品" in titles
    end

    test "entries carry the juan they open, so a caller can fetch just that part" do
      {:reply, response, _} = GetOutline.execute(%{work_id: "T0374"}, %{})
      entries = payload(response)["entries"]

      assert Enum.map(entries, & &1["juan"]) == [1, 2]
    end

    test "carries no passage text — surveying structure must not pull the corpus" do
      {:reply, response, _} = GetOutline.execute(%{work_id: "T0374"}, %{})
      data = payload(response)

      refute Enum.any?(data["entries"], &Map.has_key?(&1, "text"))
      refute data["entries"] |> Jason.encode!() |> String.contains?("一切眾生皆有佛性")
    end

    test "names the corpus it answered from" do
      {:reply, response, _} = GetOutline.execute(%{work_id: "T0374"}, %{})
      assert Map.has_key?(payload(response), "bake_id")
    end

    test "an unknown work is an error that says what to do next" do
      {:reply, response, _} = GetOutline.execute(%{work_id: "T9999"}, %{})

      assert response.isError
      text = response |> Map.fetch!(:content) |> hd() |> Map.fetch!("text")
      assert text =~ "T9999"
      assert text =~ "search"
    end
  end
end
