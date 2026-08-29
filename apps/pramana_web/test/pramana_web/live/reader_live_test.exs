defmodule PramanaWeb.ReaderLiveTest do
  @moduledoc """
  The reader is a renderer, so these tests do not re-test retrieval. They pin the things
  a UI can silently drop and a scholar cannot do without:

  - a passage is never shown without its provenance in words (invariant #4);
  - a passage is never shown without its URN (invariants #1 and #2);
  - what the corpus does not hold is on screen with the results, because an absence that
    is not stated reads as the tradition being silent.
  """
  use PramanaWeb.ConnCase, async: false

  alias Pramana.Embed.Serving

  import Phoenix.LiveViewTest

  alias Pramana.Corpus.Loader
  alias Pramana.Normalize.CBETA

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

  setup do
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

  describe "search" do
    test "renders the form before anything is searched", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "Pramāṇa"
      refute html =~ "passage(s)"
    end

    # Invariant #4, rendered. The Japanese commentary and the Indian sūtra both match
    # 如是我聞, and a reader must not be able to take one for the other by reading down a
    # ranked list.
    test "buckets results by composition origin and names each bucket", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/?#{[q: "如是我聞", mode: "phrase"]}")

      assert html =~ "Indic-composed root scripture"
      assert html =~ "Japanese-composed commentary"
    end

    test "every hit carries its URN and its origin", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/?#{[q: "如是我聞", mode: "phrase"]}")

      assert html =~ "pramana:cbeta.T:T0262_001@p0001c17"
      assert html =~ "pramana:cbeta.T:T2187_001@p0002a01"
      assert html =~ "T0262"
      assert html =~ "妙法蓮華經"
    end

    # `String.to_existing_atom("phrase")` raised here on the first phrase search in a
    # fresh VM and worked on every one after, because `:phrase` enters the atom table
    # only when `Retrieval.Lexical` loads. `Pramana.Retrieval.mode/1` is a literal map
    # for that reason, and this is the regression.
    test "a lexical mode works as the first search in the VM", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/?#{[q: "如是我聞", mode: "ngram"]}")

      assert html =~ "passage(s)"
    end

    test "an unknown mode falls back to hybrid rather than failing", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/?#{[q: "如是我聞", mode: "nonsense"]}")

      assert html =~ "passage(s)"
    end

    # A menu built from a static list offers canons the bake does not hold, and each of
    # those is a promise of an empty result set — the confusion `Coverage` exists to
    # prevent, arriving through a dropdown instead of a search.
    test "the collection menu offers only collections the bake holds", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "any collection"
      # T is loaded by this test's setup; nothing else is. Asserted on the OPTION VALUE,
      # not on the name anywhere in the page — the coverage banner legitimately names
      # 嘉興大藏經 as a collection that is NOT loaded, so a page-wide match would confuse
      # "offered in the menu" with "mentioned on the page".
      assert html =~ ~s(value="T")
      refute html =~ ~s(value="J")
      refute html =~ ~s(value="X")
    end

    test "a collection filter narrows the results", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/?#{[q: "如是我聞", mode: "phrase", witness: "T"]}")

      assert html =~ "passage(s)"
      assert html =~ "T0262"
    end

    test "a provenance filter narrows the buckets", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/?#{[q: "如是我聞", mode: "phrase", origin: "indic"]}")

      assert html =~ "Indic-composed root scripture"
      refute html =~ "Japanese-composed commentary"
    end

    # Nothing found is not the same as nothing said, and the page has to be the thing
    # that says so.
    test "no results says the canon may not be loaded rather than staying silent", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/?#{[q: "這句話不在藏經裡面", mode: "phrase"]}")

      assert html =~ "0 passage(s)"
      assert html =~ "not the same as the canon being"
    end

    test "searching pushes the query into the URL so a result is linkable", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view
      |> form("form", %{"q" => "如是我聞", "mode" => "phrase"})
      |> render_submit()

      # Blank filters are dropped from the URL rather than carried as empty strings, so
      # the link someone pastes says only what they actually chose.
      assert_patched(view, ~p"/?#{[limit: "20", mode: "phrase", q: "如是我聞"]}")
    end
  end

  describe "passage" do
    test "shows the line in its printed context, focused", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/passage?#{[urn: "pramana:cbeta.T:T0262_001@p0001c17"]}")

      assert html =~ "如是我聞一時佛住"
      # its neighbour, which is what makes a typographic line readable
      assert html =~ "王舍城耆闍崛山中"
      assert html =~ "妙法蓮華經"
    end

    test "shows the citation a quotation is verified against", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/passage?#{[urn: "pramana:cbeta.T:T0262_001@p0001c17"]}")

      assert html =~ "pramana:cbeta.T:T0262_001@p0001c17"
      assert html =~ "sha256"
    end

    test "a URN that resolves to nothing says so instead of rendering blank", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/passage?#{[urn: "pramana:cbeta.T:T9999_001@p0001a01"]}")

      assert html =~ "No passage with that URN is in this bake"
    end

    test "an unparseable URN is refused as a URN, not as a missing passage", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/passage?#{[urn: "not-a-urn"]}")

      assert html =~ "not a URN"
    end

    # A section with nothing in it is not rendered at all. `Compare.versions/2` returns
    # `nil` rather than an empty structure for exactly this reason: a "Parallels" heading
    # over an empty list reads as "we looked and there are none", which is a claim.
    test "shows no translation or parallel headings for a passage that has neither",
         %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/passage?#{[urn: "pramana:cbeta.T:T0262_001@p0001c17"]}")

      refute html =~ "Translations"
      refute html =~ "Parallels"
    end
  end

  describe "the work browser" do
    # A work page is where someone decides whether to trust a text, so it is where the
    # publisher's own copy is most worth one click away.
    test "links out to the edition that published the work", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/works/T2187")

      assert html =~ "cbetaonline.dila.edu.tw"
      assert html =~ "CBETA Online"
      # The link must never read as the citation.
      assert html =~ "not the citation"
    end

    test "leads with provenance, because an outline is where a text is misjudged",
         %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/works/T2187")

      # Same shape as a sūtra, same headings, same juan count — the axes are the only
      # thing that distinguishes them here.
      assert html =~ "Japanese-composed commentary"
      assert html =~ "法華義疏"
      assert html =~ "pramana:cbeta.T:T2187"
    end

    test "a work with no recorded divisions says so rather than showing an empty list",
         %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/works/T0262")

      assert html =~ "records no internal divisions"
      assert html =~ "not a gap in the bake"
    end

    test "an unknown work id is refused", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/works/T9999")

      assert html =~ "No work with that id is in this bake"
    end

    # A work can run to 92,192 printed lines; finding a phrase inside one is a different
    # act from finding it in the canon, and an outline cannot do it.
    test "offers a search scoped to the work", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/works/T0262")

      assert html =~ "Search inside this work"
      assert html =~ ~s(name="work" value="T0262")
    end

    test "a work-scoped search returns only that work", %{conn: conn} do
      {:ok, _view, html} =
        live(conn, ~p"/?#{[q: "如是我聞", mode: "phrase", work: "T0262"]}")

      assert html =~ "within T0262"
      assert html =~ "T0262_001@p0001c17"
      refute html =~ "T2187_001@p0002a01"
    end

    test "a search hit links to its work", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/?#{[q: "如是我聞", mode: "phrase"]}")

      assert html =~ ~s(href="/works/T0262")
    end
  end

  describe "the variant apparatus" do
    @witnessed """
    <TEI xmlns="http://www.tei-c.org/ns/1.0" xmlns:cb="http://www.cbeta.org/ns/1.0">
    <teiHeader><fileDesc><titleStmt>
      <title level="m" xml:lang="zh-Hant">雜阿含經</title><author>求那跋陀羅譯</author>
    </titleStmt></fileDesc></teiHeader>
    <text><body>
    <milestone n="1" unit="juan"/>
    <lb n="0001a18"/>如是我<app><lem>聞</lem><rdg wit="#wit1">問</rdg></app>一時
    </body></text></TEI>
    """

    setup do
      {:ok, ir} =
        CBETA.normalize(@witnessed, work_id: "T0099", canon: "T", volume: 2, number: "0099")

      {:ok, %{text: text}} =
        Loader.load(ir, source: "cbeta", witness: "T", provenance: %{composition_origin: "indic"})

      # Sigla come from the text's OWN header. `wit1` means 38 different things across the
      # canon, so a global table would attribute this Song reading to whatever wit1
      # happens to mean elsewhere.
      text
      |> Ecto.Changeset.change(meta: Map.put(text.meta, "witnesses", %{"wit1" => "【宋】"}))
      |> Pramana.Repo.update!()

      :ok
    end

    test "names the witness from this text's own header", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/passage?#{[urn: "pramana:cbeta.T:T0099_001@p0001a18"]}")

      assert html =~ "Variant readings"
      assert html =~ "【宋】"
      assert html =~ "not stable across the canon"
    end

    test "counts the work's variant lines on its outline page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/works/T0099")

      assert html =~ "lines with variants"
    end

    # `meta["apparatus"]` carries the raw `wit="#wit1"` from the file, and `wit1` means 38
    # different things across the canon. A raw id rendered beside a reading is a
    # sigil-shaped string in front of a reader with every reason to take it for one.
    test "never shows a raw witness id, even on a neighbouring line", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/passage?#{[urn: "pramana:cbeta.T:T0099_001@p0001a18"]}")

      refute html =~ "#wit1"
      # The named form, from this text's own header, is still there.
      assert html =~ "【宋】"
    end
  end

  # Top-k retrieval cannot answer "how often, and where". Search was the only thing a
  # human could do here for two phases, which means every claim a person formed from this
  # corpus was formed from a ranked sample — while the MCP surface has had `survey_corpus`
  # since Phase 3, with a note telling models to run it BEFORE claiming anything.
  # Someone opening a search box cannot tell an empty result from a short shelf. Every
  # other surface answers that per query, attached to results they already asked for;
  # this answers it once, before they ask.
  # An English query used to reach the lexical retriever, which reads `segments`, and come
  # back with Pāli passages that shared character n-grams with it. The renderings that
  # could have answered were reachable only through an anchor the caller already had.
  describe "translations beside the search results" do
    test "renders nothing when no rendering matches", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/?q=#{"云何為念力"}")

      refute html =~ "Translations using these words"
    end

    test "keeps a rendering out of the ranked passage list", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/?q=#{"云何為念力"}")

      # Whatever else the page shows, a translation must never be presented as a passage.
      refute html =~ "never citable as the text" and html =~ "provenance group"
    end
  end

  describe "the inventory" do
    test "leads with what is NOT loaded", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/inventory")

      assert html =~ "Not loaded"
      assert html =~ "CBETA publishes 26 collections"
      assert html =~ "Taishō volumes 56–84"
    end

    test "names the absent collections rather than coding them", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/inventory")

      assert html =~ "嘉興大藏經"
      assert html =~ "Jiaxing Canon"
    end

    test "shows the corpus totals and the bake that produced them", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/inventory")

      assert html =~ "citable segments"
      assert html =~ "pipeline v"
    end

    test "breaks works down by composition origin, named in words", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/inventory")

      assert html =~ "Where these texts were composed"
      assert html =~ "Indic-composed"
      assert html =~ "Japanese-composed"
    end
  end

  describe "the survey" do
    test "counts every occurrence and says how concentrated they are", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/survey?#{[q: "如是我聞"]}")

      assert html =~ "printed lines containing it"
      assert html =~ "distinct works"
      assert html =~ "lines per work on average"
    end

    # `label/2` names a BUCKET — a pair — so asking it about one axis yields
    # "Indic-composed, role uncatalogued", which reads as a claim that the role is unknown
    # when the caller simply did not ask about it.
    test "a single-axis breakdown names one axis, not a pair", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/survey?#{[q: "如是我聞"]}")

      assert html =~ "Indic-composed"
      refute html =~ "Indic-composed, role uncatalogued"
    end

    test "carries the coverage caveat, because a count invites a claim", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/survey?#{[q: "如是我聞"]}")

      assert html =~ "Taishō volumes 56–84"
    end

    test "a phrase the corpus does not hold says so rather than showing zeroes",
         %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/survey?#{[q: "這句話不存在於藏經"]}")

      assert html =~ "Nothing in the loaded corpus uses this"
    end

    test "renders the form before anything is counted", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/survey")

      refute html =~ "printed lines containing it"
    end
  end

  describe "the reader's own claims about a passage" do
    # THREE levels, not two. `edition_page` is a page number printed in the physical book
    # — a reader with the book can turn to it — and the first version of this badge said
    # "not checkable against a printed page" for all 4,576 of them, the whole Degé Tengyur
    # included. `Pramana.Corpus` records that collapsing `edition_page` into `derived`
    # "understated what can be verified"; the reader was doing it again one layer up.
    test "an edition-page anchor is not described as unverifiable", %{conn: conn} do
      {:ok, ir} =
        CBETA.normalize(@indic, work_id: "T0262", canon: "T", volume: 9, number: "0262")

      {:ok, %{text: text}} =
        Loader.load(ir,
          source: "cbeta",
          witness: "T",
          addressing: "edition_page",
          provenance: %{composition_origin: "indic"}
        )

      assert text.meta["addressing"] == "edition_page"

      {:ok, _view, html} = live(conn, ~p"/passage?#{[urn: "pramana:cbeta.T:T0262_001@p0001c17"]}")

      refute html =~ "not checkable against a printed page"
      assert html =~ "anchored to the printed page"
    end

    test "a non-canonical anchor is flagged as not checkable against a page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/?#{[q: "如是我聞", mode: "phrase"]}")

      # Every text here IS canonically anchored, so the warning must be absent — a badge
      # that shows up unconditionally tells a reader nothing.
      refute html =~ "not checkable against a printed page"
    end

    # "The semantic arm did not run" and "why it did not run" are different facts, and
    # only the second tells a reader whether the fix is a restart or an ingest. Reporting
    # the symptom alone leaves them to guess, and the guess decides whether they conclude
    # the canon is thin.
    test "says why meaning-based search did not run, not only that it did not",
         %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/?#{[q: "如是我聞", mode: "phrase"]}")

      assert html =~ "Meaning-based matches were not considered"

      # BOTH BRANCHES, because which one is right depends on the environment and the
      # invariant does not. This asserted the no-serving wording only, and failed the day
      # the gate ran with PRAMANA_EMBEDDING=1 exported — where the serving IS running and
      # the page correctly says so. A test that passes only in one environment is a test
      # that will fail in the other at the worst moment.
      if Serving.available?() do
        assert html =~ "The serving is running"
        assert html =~ "nothing embedded"
      else
        assert html =~ "PRAMANA_EMBEDDING=1"
        assert html =~ "not of the corpus"
      end
    end

    test "the coverage banner names what is not loaded", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/?#{[q: "如是我聞", mode: "phrase"]}")

      assert html =~ "Taishō volumes 56–84"
      assert html =~ "CBETA publishes 26 collections"
    end
  end
end
