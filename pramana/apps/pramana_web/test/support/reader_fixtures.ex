defmodule PramanaWeb.ReaderFixtures do
  @moduledoc "Two contrasting source works and opt-in reader relationships."
  alias Pramana.Corpus.Loader
  alias Pramana.Corpus.TextParallel
  alias Pramana.Corpus.Translation
  alias Pramana.Corpus.WorkRelation
  alias Pramana.Normalize.CBETA
  alias Pramana.Repo

  @indic """
  <TEI xmlns="http://www.tei-c.org/ns/1.0" xmlns:cb="http://www.cbeta.org/ns/1.0">
  <teiHeader><fileDesc><titleStmt>
    <title level="m" xml:lang="zh-Hant">妙法蓮華經</title>
    <author>姚秦 鳩摩羅什譯</author>
  </titleStmt></fileDesc></teiHeader>
  <text><body>
  <milestone n="1" unit="juan"/>
  <lb n="0001c17"/>如是我聞一時佛住
  <lb n="0001c18"/>王舍城耆闍崛山中
  </body></text></TEI>
  """

  # A Japanese-composed commentary quoting the same words. The pair is the whole point:
  # a flat result list would put these next to each other with nothing between them.
  @japanese """
  <TEI xmlns="http://www.tei-c.org/ns/1.0" xmlns:cb="http://www.cbeta.org/ns/1.0">
  <teiHeader><fileDesc><titleStmt>
    <title level="m" xml:lang="zh-Hant">法華義疏</title><author>聖德太子</author>
  </titleStmt></fileDesc></teiHeader>
  <text><body>
  <milestone n="1" unit="juan"/>
  <lb n="0002a01"/>如是我聞者釋曰
  </body></text></TEI>
  """

  def indic, do: @indic

  def load_reader_fixture(_) do
    load = fn xml, work_id, volume, number, provenance ->
      {:ok, ir} =
        CBETA.normalize(xml, work_id: work_id, canon: "T", volume: volume, number: number)

      {:ok, _} = Loader.load(ir, source: "cbeta", witness: "T", provenance: provenance)
    end

    load.(@indic, "T0262", 9, "0262", %{composition_origin: "indic", text_role: "root"})

    load.(@japanese, "T2187", 56, "2187", %{
      composition_origin: "japanese",
      text_role: "commentary"
    })

    :ok
  end

  @default_translation %{
    anchor_urn: "pramana:cbeta.T:T0262_001@p0001c17",
    work_id: "T0262",
    lang: "en",
    translator_id: "trans_test",
    translator_name: "Test Translator",
    tier: "t0",
    method: "human",
    text: "Default translation text",
    license_class: "public-domain",
    attribution: "Test Attribution"
  }

  def insert_translation!(attrs) do
    params =
      @default_translation
      |> Map.merge(Map.new(attrs))
      |> with_text_sha256()
      |> with_model_id()

    %Translation{}
    |> Ecto.Changeset.change(params)
    |> Repo.insert!()
  end

  defp with_text_sha256(%{text: text} = params) do
    sha = Base.encode16(:crypto.hash(:sha256, text), case: :lower)
    Map.put(params, :text_sha256, sha)
  end

  defp with_model_id(%{method: "llm"} = params) do
    Map.put_new(params, :model_id, "test-model")
  end

  defp with_model_id(params), do: params

  @default_parallel %{
    source_work_id: "T0262",
    source_urn: "pramana:cbeta.T:T0262_001@p0001c17",
    source_uid: "t0262",
    target_uid: "target_uid",
    relation: "full",
    partial: false
  }

  def insert_parallel!(attrs) do
    params = Map.merge(@default_parallel, Map.new(attrs))

    %TextParallel{}
    |> Ecto.Changeset.change(params)
    |> Repo.insert!()
  end

  @default_work_relation %{
    source_work_id: "T0262",
    target_work_id: "T2187",
    relation: "parallel_of",
    method: "shared_text",
    confidence: "probable",
    evidence: %{}
  }

  def insert_work_relation!(attrs) do
    params = Map.merge(@default_work_relation, Map.new(attrs))

    %WorkRelation{}
    |> WorkRelation.changeset(params)
    |> Repo.insert!()
  end
end
