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

  describe "the reader's own claims about a passage" do
    test "a non-canonical anchor is flagged as not checkable against a page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/?#{[q: "如是我聞", mode: "phrase"]}")

      # Every text here IS canonically anchored, so the warning must be absent — a badge
      # that shows up unconditionally tells a reader nothing.
      refute html =~ "not checkable against a printed page"
    end

    test "the coverage banner names what is not loaded", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/?#{[q: "如是我聞", mode: "phrase"]}")

      assert html =~ "Taishō volumes 56–84"
      assert html =~ "CBETA publishes 26 collections"
    end
  end
end
