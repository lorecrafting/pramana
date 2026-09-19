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
  alias Pramana.Corpus.Work
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

  describe "min_density/1" do
    # 30 was calibrated against sūtra exegesis and applied to everything, which rejected 24
    # of 29 asserted śāstra pairs. 論疏部 quotes its śāstra less verbatim than 經疏部 quotes
    # its sūtra, and its own null set of 264 pairs tops out at 13.5 against 28.4.
    test "śāstra exegesis has a lower floor than sūtra exegesis" do
      assert Commentary.min_density("subcommentary") < Commentary.min_density("commentary")
    end

    test "an unknown or absent role gets the conservative floor, not the lower one" do
      assert Commentary.min_density(nil) == Commentary.min_density("commentary")
      assert Commentary.min_density("treatise") == Commentary.min_density("commentary")
    end

    # The floor follows the SOURCE's role, so the same evidence decides differently for a
    # 經疏 and a 論疏. Without that, this whole calibration would be decoration.
    # Density is spans per 10k characters of the COMMENTARY, so landing between the two
    # floors needs a body long enough that one quotation is worth about twenty: one span
    # in ~500 characters. The filler is deliberately nothing the root contains.
    test "the same density aligns a subcommentary and does not align a commentary" do
      load_long_commentary!()

      density = Commentary.measure("T9999", "T0223").density
      assert density > 14.0 and density < 30.0, "fixture must sit between the floors: #{density}"

      set_role!("T9999", "subcommentary")

      assert Commentary.measure("T9999", "T0223").aligned,
             "a subcommentary clears the śāstra floor at this density"

      set_role!("T9999", "commentary")

      refute Commentary.measure("T9999", "T0223").aligned,
             "the same evidence does not clear the sūtra floor"
    end

    defp set_role!(id, role) do
      Repo.update_all(from(w in Work, where: w.id == ^id), set: [text_role: role])
    end

    defp load_long_commentary! do
      filler = String.duplicate("此中應廣分別其義理趣", 48)

      xml = """
      <TEI xmlns="http://www.tei-c.org/ns/1.0" xmlns:cb="http://www.cbeta.org/ns/1.0">
      <teiHeader><fileDesc><titleStmt><title level="m" xml:lang="zh-Hant">長論疏</title>
      </titleStmt></fileDesc></teiHeader>
      <text><body>
      <milestone n="1" unit="juan"/>
      <lb n="0001a01"/>釋曰如是我聞一時佛住王舍城者#{filler}
      </body></text></TEI>
      """

      {:ok, ir} = CBETA.normalize(xml, work_id: "T9999", canon: "T", volume: 25, number: "9999")
      {:ok, _} = Loader.load(ir, source: "cbeta", witness: "T")
    end
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

  describe "alignment_counts/1" do
    test "groups alignments by commentary work with lemma and line counts" do
      align!("pramana:cbeta.T:T0223_001@p0001a01", at: 10)
      align!("pramana:cbeta.T:T0223_001@p0001a01", at: 30)

      counts = Commentary.alignment_counts("T0223")
      assert %{"T1509" => %{lemmas: 2, lines: 1}} = counts

      assert Commentary.alignment_counts("T_UNEXPLAINED") == %{}
    end
  end

  describe "lemmas_of/2" do
    test "returns presented lemmas with offsets and metadata ordered by char start" do
      align!("pramana:cbeta.T:T0223_001@p0001a01", at: 10)
      align!("pramana:cbeta.T:T0223_001@p0001a01", at: 30)

      lemmas = Commentary.lemmas_of("T1509")
      assert length(lemmas) == 2
      [first, second] = lemmas
      assert first.commentary_offsets.char_start == 10
      assert second.commentary_offsets.char_start == 30
      assert first.commentary_work_id == "T1509"
      assert first.root_work_id == "T0223"
      assert is_binary(first.lemma_sha256)

      limited = Commentary.lemmas_of("T1509", limit: 1)
      assert length(limited) == 1
    end
  end

  describe "align/3" do
    test "refuses to align a work with itself" do
      assert {:error, :same_text} = Commentary.align("T0223", "T0223")
    end

    test "returns error when either text is not found" do
      assert {:error, {:not_found, "MISSING"}} = Commentary.align("MISSING", "T0223")
      assert {:error, {:not_found, "MISSING"}} = Commentary.align("T1509", "MISSING")
    end

    test "aligns matching commentary and root texts and persists rows" do
      assert {:ok, report} = Commentary.align("T1509", "T0223")
      assert report.aligned == true
      assert report.written >= 1
      assert report.unresolved == 0

      # Re-aligning replaces rows idempotently
      assert {:ok, report2} = Commentary.align("T1509", "T0223")
      assert report2.written == report.written
      assert report2.unresolved == 0
    end

    test "reports matched spans that cannot be resolved to citation segments" do
      commentary =
        Repo.one!(from t in Text, where: t.work_id == "T1509")

      Repo.delete_all(from s in Segment, where: s.text_id == ^commentary.id)

      assert {:ok, report} = Commentary.align("T1509", "T0223")
      assert report.aligned == true
      assert report.spans > 0
      assert report.written == 0
      assert report.unresolved == report.spans
    end

    test "skips persisting when texts do not clear the alignment density gate" do
      load_long_commentary!()
      set_role!("T9999", "commentary")

      assert {:skip, report} = Commentary.align("T9999", "T0223")
      assert report.aligned == false
    end
  end
end
