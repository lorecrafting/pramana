defmodule PramanaWeb.ReaderSearchLiveTest do
  use PramanaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import PramanaWeb.ReaderFixtures
  alias Pramana.Corpus.Work
  alias Pramana.Repo
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

    # Exercises UI dispatch. The fresh-VM mapping guarantee belongs to ColdStartTest.
    test "an explicit lexical mode reaches the reader search boundary", %{conn: conn} do
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

    test "a collection filter excludes a matching passage from another collection", %{conn: conn} do
      Repo.insert!(%Pramana.Corpus.Witness{id: "X", name: "X collection"})

      Repo.insert!(%Work{
        id: "X0001",
        title: "competing collection",
        composition_origin: "chinese",
        text_role: "commentary"
      })

      Pramana.CorpusFixtures.text!(
        %{
          work_id: "X0001",
          source_id: "cbeta",
          witness_id: "X",
          urn_prefix: "pramana:cbeta.X:X0001",
          meta: %{}
        },
        [{"pramana:cbeta.X:X0001_001@p0001a01", "如是我聞競爭候選"}]
      )

      {:ok, all, _} = live(conn, ~p"/?#{[q: "如是我聞", mode: "phrase"]}")
      assert has_element?(all, ~s(article[data-source-urn="pramana:cbeta.X:X0001_001@p0001a01"]))
      {:ok, filtered, _} = live(conn, ~p"/?#{[q: "如是我聞", mode: "phrase", witness: "T"]}")

      assert has_element?(
               filtered,
               ~s(article[data-source-urn="pramana:cbeta.T:T0262_001@p0001c17"])
             )

      refute has_element?(
               filtered,
               ~s(article[data-source-urn="pramana:cbeta.X:X0001_001@p0001a01"])
             )
    end

    test "a provenance filter excludes the Japanese hit from the ranked results", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/?#{[q: "如是我聞", mode: "phrase", origin: "indic"]}")

      assert has_element?(
               view,
               ~s([data-result-group="Indic-composed root scripture"] article[data-source-urn="pramana:cbeta.T:T0262_001@p0001c17"])
             )

      refute has_element?(view, ~s(article[data-source-urn="pramana:cbeta.T:T2187_001@p0002a01"]))
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

  describe "translations beside the search results" do
    test "renders nothing when no rendering matches", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/?q=#{"云何為念力"}")

      refute html =~ "Translations using these words"
    end

    test "a matching translation remains separate from ranked source passages", %{conn: conn} do
      rendering = "如是我聞 — deliberately different translated words"
      insert_translation!(text: rendering, translator_id: "matching-rendering", method: "human")
      {:ok, view, _} = live(conn, ~p"/?#{[q: "如是我聞", mode: "phrase"]}")

      assert has_element?(view, "#translation-results article", rendering)
      assert has_element?(view, "#translation-results", "never citable as the text")

      assert has_element?(
               view,
               ~s(article[data-source-urn="pramana:cbeta.T:T0262_001@p0001c17"]),
               "如是我聞一時佛住"
             )

      refute has_element?(view, "article[data-source-urn]", rendering)
      refute has_element?(view, ~s(article[data-source-urn*="#tr:"]))
    end
  end
end
