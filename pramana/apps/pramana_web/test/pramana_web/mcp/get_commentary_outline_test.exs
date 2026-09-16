defmodule PramanaWeb.MCP.GetCommentaryOutlineTest do
  @moduledoc """
  Where a commentary does its work in its root — `get_glosses` from the other side.

  Two things carry the weight. **The counts are complete**, because the reason this tool
  exists is that `Commentary.lemmas_of/2` truncated at 100 and hid 67,055 of 72,120
  alignments. And **a juan that does not appear is a fact about the commentary**, never
  about the corpus — a gap in a list of divisions is exactly the shape a reader mistakes
  for an absence in the canon, so the reply says which it is.
  """
  use Pramana.DataCase, async: true

  import Ecto.Query

  alias Pramana.Corpus.CommentaryAlignment
  alias Pramana.Corpus.Loader
  alias Pramana.Corpus.Text
  alias Pramana.Normalize.CBETA
  alias Pramana.Repo
  alias PramanaWeb.MCP.Tools.GetCommentaryOutline

  @root """
  <TEI xmlns="http://www.tei-c.org/ns/1.0" xmlns:cb="http://www.cbeta.org/ns/1.0">
  <teiHeader><fileDesc><titleStmt><title level="m" xml:lang="zh-Hant">摩訶般若波羅蜜經</title>
  </titleStmt></fileDesc></teiHeader>
  <text><body>
  <milestone n="1" unit="juan"/>
  <lb n="0001a01"/>如是我聞
  <lb n="0001a02"/>一時佛住王舍城
  <milestone n="2" unit="juan"/>
  <lb n="0002a01"/>復次舍利
  <lb n="0002a02"/>弗菩薩摩訶薩
  </body></text></TEI>
  """

  @commentary """
  <TEI xmlns="http://www.tei-c.org/ns/1.0" xmlns:cb="http://www.cbeta.org/ns/1.0">
  <teiHeader><fileDesc><titleStmt><title level="m" xml:lang="zh-Hant">大智度論</title>
  </titleStmt></fileDesc></teiHeader>
  <text><body>
  <milestone n="1" unit="juan"/>
  <lb n="0057a01"/>釋曰如是我聞一時佛住王舍城者復次舍利弗菩薩摩訶薩
  </body></text></TEI>
  """

  setup do
    for {xml, id, vol, num} <- [{@root, "T0223", 8, "0223"}, {@commentary, "T1509", 25, "1509"}] do
      {:ok, ir} = CBETA.normalize(xml, work_id: id, canon: "T", volume: vol, number: num)
      {:ok, _} = Loader.load(ir, source: "cbeta", witness: "T")
    end

    :ok
  end

  defp call!(params) do
    {:reply, response, %{}} = GetCommentaryOutline.execute(params, %{})
    response |> Map.fetch!(:content) |> hd() |> Map.fetch!("text") |> Jason.decode!()
  end

  defp align!(juan_line) do
    range =
      juan_line <>
        "-" <>
        (juan_line |> String.split("@") |> List.last() |> String.replace_suffix("01", "02"))

    {:ok, span} = Pramana.Corpus.resolve(range)
    lemma = String.slice(span.content, 0, 8)
    root = Repo.get_by!(Pramana.Corpus.Segment, urn: juan_line)
    commentary = Repo.get_by!(Pramana.Corpus.Segment, urn: "pramana:cbeta.T:T1509_001@p0057a01")
    {byte_offset, _} = :binary.match(commentary.content, lemma)

    commentary_offset =
      commentary.char_start + String.length(binary_part(commentary.content, 0, byte_offset))

    # Source body contains a newline at the printed break; the address spans that break.
    root_end = root.char_start + String.length(lemma) + 1
    root_work = Repo.get!(Text, root.text_id)
    commentary_work = Repo.get!(Text, commentary.text_id)

    Repo.insert!(
      struct!(CommentaryAlignment, %{
        lemma: lemma,
        lemma_sha256: Pramana.CorpusFixtures.sha256(lemma),
        length: String.length(lemma),
        commentary_text_id: commentary.text_id,
        commentary_work_id: commentary_work.work_id,
        commentary_urn: commentary.urn,
        commentary_char_start: commentary_offset,
        commentary_char_end: commentary_offset + String.length(lemma),
        root_text_id: root.text_id,
        root_work_id: root_work.work_id,
        root_urn: range,
        root_char_start: root.char_start,
        root_char_end: root_end,
        method: "lemma_match",
        confidence: "probable"
      })
    )
  end

  test "reports the juan a commentary works over, and the lemma counts in each" do
    align!("pramana:cbeta.T:T0223_001@p0001a01")

    payload = call!(%{work_id: "T1509"})

    assert payload["lemmas"] == 1
    assert [root] = payload["roots"]
    assert root["root_work_id"] == "T0223"
    assert [%{"juan" => 1, "lemmas" => 1}] = root["juan"]
  end

  # The defect this tool was built to avoid: a lemma anchored to a range URN equals no
  # segment's URN, so an equality join drops it and reports a smaller corpus than exists.
  test "counts a lemma anchored to a range, not only one anchored to a single line" do
    align!("pramana:cbeta.T:T0223_002@p0002a01")

    payload = call!(%{work_id: "T1509"})

    assert payload["lemmas"] == 1, "a range-anchored lemma must not vanish"
    assert [%{"juan" => 2}] = hd(payload["roots"])["juan"]
  end

  test "a juan nothing was quoted from is absent, and the reply says what that means" do
    align!("pramana:cbeta.T:T0223_001@p0001a01")

    payload = call!(%{work_id: "T1509"})

    refute Enum.any?(hd(payload["roots"])["juan"], &(&1["juan"] == 2))
    assert payload["note"] =~ "NOT about the corpus"
  end

  test "a work with no alignment says so without implying it explains nothing" do
    payload = call!(%{work_id: "T1509"})

    assert payload["lemmas"] == 0
    assert payload["roots"] == []
    assert payload["note"] =~ "NOT evidence it explains nothing"
  end
end
