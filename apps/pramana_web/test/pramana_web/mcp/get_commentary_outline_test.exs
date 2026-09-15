defmodule PramanaWeb.MCP.GetCommentaryOutlineTest do
  @moduledoc """
  Where a commentary does its work in its root — `get_glosses` from the other side.

  Two things carry the weight. **The counts are complete**, because the reason this tool
  exists is that `Commentary.lemmas_of/2` truncated at 100 and hid 67,055 of 72,120
  alignments. And **a juan that does not appear is a fact about the commentary**, never
  about the corpus — a gap in a list of divisions is exactly the shape a reader mistakes
  for an absence in the canon, so the reply says which it is.
  """
  use PramanaWeb.ConnCase, async: true

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
  <lb n="0001a01"/>如是我聞一時佛住王舍城
  <milestone n="2" unit="juan"/>
  <lb n="0002a01"/>復次舍利弗菩薩摩訶薩
  </body></text></TEI>
  """

  @commentary """
  <TEI xmlns="http://www.tei-c.org/ns/1.0" xmlns:cb="http://www.cbeta.org/ns/1.0">
  <teiHeader><fileDesc><titleStmt><title level="m" xml:lang="zh-Hant">大智度論</title>
  </titleStmt></fileDesc></teiHeader>
  <text><body>
  <milestone n="1" unit="juan"/>
  <lb n="0057a01"/>釋曰如是我聞一時佛住王舍城者
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
    [root, commentary] =
      Enum.map(["T0223", "T1509"], fn work ->
        Repo.one!(from(t in Text, where: t.work_id == ^work))
      end)

    segment =
      Repo.one!(
        from(s in Pramana.Corpus.Segment,
          where: s.text_id == ^root.id and s.urn == ^juan_line
        )
      )

    lemma = String.slice(segment.content, 0, 8)

    %CommentaryAlignment{}
    |> Ecto.Changeset.change(%{
      lemma: lemma,
      lemma_sha256: Base.encode16(:crypto.hash(:sha256, lemma), case: :lower),
      length: String.length(lemma),
      commentary_text_id: commentary.id,
      commentary_work_id: "T1509",
      commentary_urn: "pramana:cbeta.T:T1509_001@p0057a01",
      commentary_char_start: 2,
      commentary_char_end: 10,
      root_text_id: root.id,
      root_work_id: "T0223",
      # A RANGE, which is the ordinary case: most lemmas cross a printed line break, and
      # joining segments on URN equality dropped 58% of a real commentary's alignments.
      root_urn: juan_line <> "-p9999z99",
      root_char_start: segment.char_start,
      root_char_end: segment.char_start + 8,
      method: "lemma_match",
      confidence: "probable"
    })
    |> Repo.insert!()
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
