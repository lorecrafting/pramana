defmodule Pramana.DefinitionsTest do
  @moduledoc """
  Finding where the canon defines its own terms.

  The point is invariant #5 — deterministic before probabilistic. A model asked to define
  a Buddhist technical term produces fluent prose attributable to nothing. This produces a
  passage with a citation, or nothing at all, and the second outcome is a real answer
  rather than a failure to be papered over.
  """
  use Pramana.DataCase, async: false

  import Ecto.Query

  alias Pramana.Corpus.Loader
  alias Pramana.Corpus.Text
  alias Pramana.Definitions
  alias Pramana.Normalize.CBETA
  alias Pramana.Repo

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
    <teiHeader><fileDesc><titleStmt><title level="m">#{provenance[:title]}</title>
    <author>x</author></titleStmt></fileDesc></teiHeader>
    <text><body><milestone n="1" unit="juan"/>#{body}</body></text></TEI>
    """

    {:ok, ir} = CBETA.normalize(xml, work_id: work_id, canon: "T", volume: 1, number: "0001")
    {:ok, _} = Loader.load(ir, source: "cbeta", witness: "T", provenance: provenance)
    Repo.one!(from t in Text, where: t.work_id == ^work_id, select: t.id)
  end

  setup do
    load!(
      "T0001",
      [
        "爾時世尊告諸比丘",
        "云何為正見謂正見有二",
        "有正見世俗有漏有取",
        "復次比丘修習正見",
        "如是正見廣說如上"
      ],
      title: "阿含經",
      division: "阿含部",
      composition_origin: "indic",
      text_role: "root"
    )

    :ok
  end

  describe "Chinese definitional formulae" do
    test "finds the passage where the term is defined, not every mention of it" do
      {:ok, result} = Definitions.find("正見")

      assert result.total >= 1
      assert Enum.all?(result.results, &String.contains?(&1.span.content, "正見"))
      # 正見 appears on four lines here; only one of them defines it.
      assert Enum.any?(result.results, &String.contains?(&1.span.content, "云何為正見"))
    end

    test "records which formula matched, so the reader can judge the match" do
      {:ok, result} = Definitions.find("正見")

      assert Enum.any?(result.results, &(&1.formula in Definitions.formulae()["lzh"]))
      assert Enum.any?(result.results, &(&1.matched_phrase == "云何為正見"))
    end

    test "returns nothing rather than near-misses for a term the canon does not define" do
      {:ok, result} = Definitions.find("量子力學")

      assert result.results == []
      assert result.total == 0
      # The formulae tried are still reported: "we looked, in these ways, and found
      # nothing" is a different claim from "we did not look".
      assert result.formulae_tried == Definitions.formulae()["lzh"]
    end
  end

  describe "language detection" do
    test "Han script selects the Chinese formulae" do
      assert Definitions.detect_language("正見") == "lzh"
      assert Definitions.find("正見") |> elem(1) |> Map.get(:language) == "lzh"
    end

    test "anything else selects the Pāli formulae" do
      assert Definitions.detect_language("sammādiṭṭhi") == "pli"
    end

    test "an explicit language overrides the script guess" do
      {:ok, result} = Definitions.find("正見", language: "pli")

      assert result.language == "pli"
      assert result.formulae_tried == Definitions.formulae()["pli"]
    end
  end

  describe "filters" do
    test "provenance filters pass through to the search" do
      {:ok, indic} = Definitions.find("正見", origin: "indic")
      {:ok, japanese} = Definitions.find("正見", origin: "japanese")

      assert indic.total >= 1
      # The only text here is Indic-origin, so a Japanese filter must empty the result
      # rather than being quietly ignored.
      assert japanese.total == 0
    end

    test "limit is respected" do
      {:ok, result} = Definitions.find("正見", limit: 1)
      assert length(result.results) <= 1
    end
  end

  describe "the formula list itself" do
    test "covers both traditions" do
      assert Map.keys(Definitions.formulae()) |> Enum.sort() == ["lzh", "pli"]
    end

    test "puts the least ambiguous Chinese formula first" do
      # 云何為 is unambiguous; 何謂 also introduces ordinary rhetorical questions. Order
      # is the ranking when several match.
      assert Definitions.formulae()["lzh"] |> hd() == "云何為"
    end
  end
end
