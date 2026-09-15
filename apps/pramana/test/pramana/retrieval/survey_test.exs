defmodule Pramana.Retrieval.SurveyTest do
  @moduledoc """
  Survey answers "how often and where", which top-k retrieval structurally cannot. A
  model handed five results generalises from five results; these counts are the
  antidote, so they must be exhaustive and correct.
  """
  use Pramana.DataCase, async: false

  alias Pramana.Corpus.Loader
  alias Pramana.Normalize.CBETA
  alias Pramana.Retrieval.Survey

  defp load!(work_id, lines, provenance) do
    body =
      lines
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {text, i} ->
        n = "0001a" <> String.pad_leading(Integer.to_string(i), 2, "0")
        ~s(<lb n="#{n}"/>#{text})
      end)

    xml = """
    <TEI xmlns="http://www.tei-c.org/ns/1.0" xmlns:cb="http://www.cbeta.org/ns/1.0">
    <teiHeader><fileDesc><titleStmt>
      <title level="m" xml:lang="zh-Hant">#{provenance[:title]}</title><author>譯者</author>
    </titleStmt></fileDesc></teiHeader>
    <text><body><milestone n="1" unit="juan"/>#{body}</body></text></TEI>
    """

    {:ok, ir} = CBETA.normalize(xml, work_id: work_id, canon: "T", volume: 9, number: "0262")
    {:ok, _} = Loader.load(ir, source: "cbeta", witness: "T", provenance: provenance)
  end

  setup do
    load!("T0001", ["佛性甲", "佛性乙", "無關"],
      title: "根本經",
      composition_origin: "indic",
      text_role: "root",
      division: "阿含部",
      division_en: "Āgama"
    )

    load!("T1720", ["佛性丙", "佛性丁", "佛性戊"],
      title: "註釋",
      composition_origin: "chinese",
      text_role: "commentary",
      division: "經疏部",
      division_en: "Sūtra exegesis"
    )

    load!("T2883", ["佛性己"],
      title: "疑經",
      composition_origin: "chinese",
      text_role: "apocryphon",
      division: "疑似部",
      division_en: "Apocrypha"
    )

    :ok
  end

  describe "survey/2" do
    test "counts EVERY occurrence, not a ranked sample" do
      assert {:ok, r} = Survey.survey("佛性")

      assert r.total_segments == 6
      assert r.distinct_works == 3
    end

    test "breaks results down by composition origin" do
      {:ok, r} = Survey.survey("佛性")
      by_origin = Map.new(r.by_origin, &{&1.key, &1.segments})

      # The finding a top-k search would hide: this phrase is mostly Chinese-composed.
      assert by_origin["chinese"] == 4
      assert by_origin["indic"] == 2
    end

    test "breaks results down by text role" do
      {:ok, r} = Survey.survey("佛性")
      by_role = Map.new(r.by_role, &{&1.key, &1.segments})

      assert by_role["commentary"] == 3
      assert by_role["root"] == 2
      assert by_role["apocryphon"] == 1
    end

    test "breaks results down by Taishō division" do
      {:ok, r} = Survey.survey("佛性")
      by_division = Map.new(r.by_division, &{&1.division, &1.segments})

      assert by_division["經疏部"] == 3
      assert by_division["阿含部"] == 2
      assert by_division["疑似部"] == 1
    end

    test "ranks works by how heavily they carry the phrase" do
      {:ok, r} = Survey.survey("佛性")
      top = hd(r.top_works)

      assert top.work_id == "T1720"
      assert top.segments == 3
      assert top.composition_origin == "chinese"
      assert top.division == "經疏部"
    end

    test "names the corpus the counts came from" do
      {:ok, _} = Pramana.Bake.record(%{"test" => true})
      {:ok, r} = Survey.survey("佛性")

      assert is_binary(r.bake_id)
    end
  end

  describe "option validation — worse to skip here than in a ranked search" do
    # A ranked search that ignores a filter returns the wrong ten passages. A SURVEY that
    # ignores one returns a whole-corpus count presented as an exhaustive answer to a
    # narrower question, and nothing in the output shows it. `Lexical` and `Semantic` have
    # raised since a typo'd `divison:` silently disabled filtering there; this module went
    # without the same guard.
    test "a misspelled filter raises rather than counting the whole corpus" do
      assert_raise ArgumentError, ~r/unknown survey option/, fn ->
        Survey.survey("如是我聞", divison: "阿含部")
      end
    end

    test "the error names the offending key" do
      error = assert_raise ArgumentError, fn -> Survey.survey("如是我聞", nonsense: 1) end
      assert Exception.message(error) =~ ":nonsense"
    end

    test "every option the module actually honours is accepted" do
      assert {:ok, _} =
               Survey.survey("如是我聞",
                 top_works: 3,
                 origin: "indic",
                 role: "root",
                 division: "阿含部",
                 redistributable_only: false,
                 license_class: "nc"
               )
    end
  end

  describe "filters" do
    test "origin narrows the count" do
      assert {:ok, %{total_segments: 2}} = Survey.survey("佛性", origin: "indic")
      assert {:ok, %{total_segments: 4}} = Survey.survey("佛性", origin: "chinese")
    end

    test "role narrows the count" do
      assert {:ok, %{total_segments: 1}} = Survey.survey("佛性", role: "apocryphon")
    end

    test "division narrows the count" do
      assert {:ok, %{total_segments: 3}} = Survey.survey("佛性", division: "經疏部")
    end

    test "a filter matching nothing yields zero rather than an error" do
      assert {:ok, %{total_segments: 0, distinct_works: 0}} =
               Survey.survey("佛性", origin: "tibetan")
    end
  end

  describe "input handling" do
    test "a phrase absent from the corpus counts zero" do
      assert {:ok, %{total_segments: 0}} = Survey.survey("絕對不存在的字串")
    end

    test "rejects an empty query" do
      assert {:error, :empty_query} = Survey.survey("   ")
    end

    test "treats LIKE metacharacters literally" do
      # Unescaped, "%" would match every segment and report a wildly inflated count.
      assert {:ok, %{total_segments: 0}} = Survey.survey("%")
    end
  end
end
