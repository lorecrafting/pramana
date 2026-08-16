defmodule PramanaWeb.MCP.ComparisonToolsTest do
  @moduledoc """
  The two tools a reader actually reaches for: "show me this passage's other versions"
  and "where does the canon say what this word means".

  Both exist to keep a model from composing what it could quote. `define_from_canon`
  returns the tradition's own definitional sentence with a citation, rather than a gloss
  synthesised from training data; `compare_versions` returns the renderings and parallels
  that scholarship already recorded, rather than a similarity guess.
  """
  use Pramana.DataCase, async: false

  import Ecto.Query

  alias Pramana.Corpus.Loader
  alias Pramana.Corpus.Text
  alias Pramana.Normalize.CBETA
  alias Pramana.Repo
  alias Pramana.Translations
  alias PramanaWeb.MCP.Tools.CompareVersions
  alias PramanaWeb.MCP.Tools.DefineFromCanon

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
    Repo.one!(from(t in Text, where: t.work_id == ^work_id, select: t.id))
  end

  defp call!(tool, params),
    do:
      tool.execute(params, %{})
      |> elem(1)
      |> Map.fetch!(:content)
      |> hd()
      |> Map.fetch!("text")
      |> Jason.decode!()

  setup do
    load!(
      "T0001",
      ["爾時世尊告諸比丘", "云何為正見謂正見有二", "如是正見廣說如上"],
      title: "阿含經",
      division: "阿含部",
      composition_origin: "indic",
      text_role: "root"
    )

    :ok
  end

  describe "define_from_canon" do
    test "returns the passage where the canon defines the term" do
      data = call!(DefineFromCanon, %{term: "正見"})

      assert data["total"] >= 1
      assert Enum.any?(data["results"], &(&1["span"]["content"] =~ "云何為正見"))
    end

    test "names the formula that matched, so the reader can judge it" do
      data = call!(DefineFromCanon, %{term: "正見"})

      assert Enum.any?(data["results"], &(&1["formula"] == "云何為"))
    end

    test "every response says these are quotations, not a synthesised gloss" do
      data = call!(DefineFromCanon, %{term: "正見"})

      assert data["note"] =~ "not a synthesised gloss" or
               data["note"] =~ "Nothing here is a synthesised gloss"
    end

    test "a term the canon does not define returns nothing, and says what it tried" do
      data = call!(DefineFromCanon, %{term: "量子力學"})

      assert data["results"] == []
      assert data["formulae_tried"] != []
    end

    test "provenance filters reach the search rather than being decorative" do
      assert call!(DefineFromCanon, %{term: "正見", origin: ["japanese"]})["total"] == 0
      assert call!(DefineFromCanon, %{term: "正見", origin: ["indic"]})["total"] >= 1
    end
  end

  describe "compare_versions" do
    setup do
      urn = "pramana:cbeta.T:T0001_001@p0001a02"

      {:ok, _} =
        Translations.store([
          %{
            anchor_urn: urn,
            work_id: "T0001",
            lang: "en",
            translator_id: "test-hand",
            tier: "t0",
            method: "human",
            text: "And what is right view?",
            redistributable: true,
            license_class: "cc0"
          }
        ])

      {:ok, urn: urn}
    end

    test "returns the passage with its renderings", %{urn: urn} do
      data = call!(CompareVersions, %{urn: urn})

      assert data["passage"]["content"] =~ "云何為正見"
      assert data["renderings"]["count"] == 1
      assert hd(data["renderings"]["pool"])["text"] == "And what is right view?"
    end

    test "states that parallels are different texts, not editions of one another", %{urn: urn} do
      assert call!(CompareVersions, %{urn: urn})["note"] =~ "DIFFERENT texts"
    end

    test "pinning a translator narrows the pool", %{urn: urn} do
      data = call!(CompareVersions, %{urn: urn, translator: "nobody"})
      assert data["renderings"] == nil
    end

    test "a URN addressing nothing is refused rather than compared" do
      {:reply, response, _} =
        CompareVersions.execute(%{urn: "pramana:cbeta.T:T9999_001@p0001a01"}, %{})

      assert response.isError
    end

    test "a malformed URN is refused with a message naming the expected shape" do
      {:reply, response, _} = CompareVersions.execute(%{urn: "nonsense"}, %{})

      assert response.isError
      assert hd(response.content)["text"] =~ "Expected pramana:"
    end
  end
end
