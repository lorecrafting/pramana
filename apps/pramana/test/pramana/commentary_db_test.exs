defmodule Pramana.CommentaryDbTest do
  @moduledoc """
  The parts of `Pramana.Commentary` that read the corpus.

  They were tested only through `apps/pramana_web`, which is the wrong place twice over: a
  domain function belongs to the domain app, and the MCP tool's test cannot fail for a
  reason the tool does not surface.

  The property that matters here is **completeness**. Every defect these functions have had
  was a silent undercount: `root_pct` summed overlapping spans and reported 1102%,
  `glosses_on/2` truncated 109 glosses to 20 without saying so, and `outline/1`'s first
  join dropped 58% of a real commentary's lemmas because they were anchored to ranges.
  """
  use Pramana.DataCase, async: true

  alias Pramana.Commentary
  alias Pramana.Corpus.CommentaryAlignment
  alias Pramana.Corpus.Loader
  alias Pramana.Corpus.Segment
  alias Pramana.Corpus.Text
  alias Pramana.Normalize.CBETA
  alias Pramana.Repo

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

  defp align!(line_urn, opts \\ []) do
    [root, commentary] =
      Enum.map(["T0223", "T1509"], &Repo.one!(from t in Text, where: t.work_id == ^&1))

    segment = Repo.one!(from s in Segment, where: s.text_id == ^root.id and s.urn == ^line_urn)
    lemma = String.slice(segment.content, 0, 8)

    %CommentaryAlignment{}
    |> Ecto.Changeset.change(%{
      lemma: lemma,
      lemma_sha256: Base.encode16(:crypto.hash(:sha256, lemma), case: :lower),
      length: 8,
      commentary_text_id: commentary.id,
      commentary_work_id: "T1509",
      commentary_urn: "pramana:cbeta.T:T1509_001@p0057a01",
      commentary_char_start: Keyword.get(opts, :at, 2),
      commentary_char_end: Keyword.get(opts, :at, 2) + 8,
      root_text_id: root.id,
      root_work_id: "T0223",
      root_urn: if(opts[:range], do: line_urn <> "-p9999z99", else: line_urn),
      root_char_start: segment.char_start,
      root_char_end: segment.char_start + 8,
      method: "lemma_match",
      confidence: "probable"
    })
    |> Repo.insert!()
  end

  describe "outline/1" do
    test "groups a commentary's lemmas by the juan of its root" do
      align!("pramana:cbeta.T:T0223_001@p0001a01")
      align!("pramana:cbeta.T:T0223_002@p0002a01", at: 20)

      assert %{lemmas: 2, roots: [root]} = Commentary.outline("T1509")
      assert root.root_work_id == "T0223"
      assert [%{juan: 1, lemmas: 1}, %{juan: 2, lemmas: 1}] = root.juan
    end

    # `segments.urn == alignments.root_urn` looks obviously right and drops every lemma
    # that crosses a printed line break, which is most of them: 12,697 of T1509's 21,834.
    # Rule 68 — an equality test on a URN is a parser.
    test "counts a lemma anchored to a range, which is the ordinary case" do
      align!("pramana:cbeta.T:T0223_001@p0001a01", range: true)

      assert %{lemmas: 1, roots: [%{juan: [%{juan: 1}]}]} = Commentary.outline("T1509")
    end

    test "a commentary with no alignment returns zero and no roots, rather than raising" do
      assert %{lemmas: 0, roots: []} = Commentary.outline("T1509")
    end

    test "roots are ordered by how much work the commentary does in each" do
      align!("pramana:cbeta.T:T0223_001@p0001a01")
      align!("pramana:cbeta.T:T0223_001@p0001a01", at: 40)
      align!("pramana:cbeta.T:T0223_002@p0002a01", at: 60)

      assert %{roots: [%{juan: juan}]} = Commentary.outline("T1509")
      assert [%{juan: 1, lemmas: 2}, %{juan: 2, lemmas: 1}] = juan
    end
  end

  describe "gloss_count/1 and glosses_on/2" do
    @line "pramana:cbeta.T:T0223_001@p0001a01"

    test "the count is the whole number, and the list is what fits" do
      for n <- 1..3//1, do: align!(@line, at: n * 10)

      assert Commentary.gloss_count(@line) == 3
      assert length(Commentary.glosses_on(@line, limit: 2)) == 2
    end

    test "a line nothing explains counts zero rather than erroring" do
      assert Commentary.gloss_count(@line) == 0
      assert Commentary.glosses_on(@line) == []
    end
  end
end
