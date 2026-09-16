defmodule PramanaWeb.ReaderSearchLiveTest do
  use PramanaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import PramanaWeb.ReaderFixtures
  alias Pramana.Normalize.CBETA
  setup :load_reader_fixture

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

    # Ordinary mounted navigation; fresh-VM mode parsing is covered in cold_start_test.exs.
    test "a lexical mode renders a search page", %{conn: conn} do
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

    test "a collection filter removes an otherwise matching competing collection", %{conn: conn} do
      xml = """
      <TEI xmlns="http://www.tei-c.org/ns/1.0"><teiHeader><fileDesc><titleStmt>
      <title level="m">卍續藏對照</title></titleStmt></fileDesc></teiHeader>
      <text><body><milestone n="1" unit="juan"/><lb n="0001a01" ed="X"/>如是我聞續藏</body></text></TEI>
      """

      {:ok, ir} = CBETA.normalize(xml, work_id: "X0240", canon: "X", volume: 8, number: "0240")
      {:ok, _} = Pramana.Corpus.Loader.load(ir, source: "cbeta", witness: "X")
      x_urn = "pramana:cbeta.X:X0240_001@p0001a01"
      {:ok, all, _} = live(conn, ~p"/?#{[q: "如是我聞", mode: "phrase"]}")
      assert has_element?(all, ~s([data-source-urn="#{x_urn}"]))

      {:ok, filtered, _} = live(conn, ~p"/?#{[q: "如是我聞", mode: "phrase", witness: "T"]}")

      assert has_element?(filtered, ~s([data-source-urn="pramana:cbeta.T:T0262_001@p0001c17"]))
      refute has_element?(filtered, ~s([data-source-urn="#{x_urn}"]))
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

    test "clicking clear button resets search to initial state", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?#{[q: "如是我聞", mode: "phrase"]}")

      view
      |> element("button", "clear")
      |> render_click()

      assert_patched(view, ~p"/")
    end

    test "renders matching English translations beside the passage search results", %{conn: conn} do
      insert_translation!(
        text: "Thus have I heard the Blessed One was staying in Rajagriha",
        translator_name: "Leon Hurvitz",
        translator_id: "hurvitz",
        method: "human"
      )

      {:ok, _view, html} = live(conn, ~p"/?#{[q: "Blessed One Rajagriha"]}")

      assert html =~ "Translations using these words"
      assert html =~ "never citable as the text"
      assert html =~ "Leon Hurvitz"
      assert html =~ "pramana:cbeta.T:T0262_001@p0001c17"
    end
  end

  describe "what the reader refuses" do
    # The architectural constraint is that this is a renderer, not a new LLM consumer.
    # We cannot grep for every possible client library, but we can assert the observable
    # boundary: nothing a page load does produces a generated rendering where there was none.
    test "viewing a passage does not produce any translation layer", %{conn: conn} do
      before_count = Pramana.Repo.aggregate(Pramana.Corpus.Translation, :count)
      {:ok, _view, _html} = live(conn, ~p"/passage?#{[urn: "pramana:cbeta.T:T0262_001@p0001c17"]}")
      assert Pramana.Repo.aggregate(Pramana.Corpus.Translation, :count) == before_count
    end

    test "a matching translation is not merged into the source result group", %{conn: conn} do
      insert_translation!(text: "如是我聞 translated decoy", translator_name: "Decoy Translator")
      {:ok, view, _} = live(conn, ~p"/?#{[q: "如是我聞", mode: "phrase"]}")

      assert has_element?(view, "#translation-results", "Decoy Translator")
      assert has_element?(view, "[data-result-group] [data-source-urn]")
      refute view |> element("[data-result-group]") |> render() =~ "Decoy Translator"
    end
  end
end
