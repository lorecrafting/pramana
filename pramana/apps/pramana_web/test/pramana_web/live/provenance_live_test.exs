defmodule PramanaWeb.ReaderProvenanceLiveTest do
  use PramanaWeb.ConnCase, async: false
  import Ecto.Query
  import Phoenix.LiveViewTest
  import PramanaWeb.ReaderFixtures
  alias Pramana.Corpus.Loader
  alias Pramana.Corpus.Text
  alias Pramana.Embed.Serving
  alias Pramana.Normalize.CBETA
  alias Pramana.Repo
  setup :load_reader_fixture
  @indic PramanaWeb.ReaderFixtures.indic()

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

    test "a derived anchor warning belongs to that hit, not a neighboring canonical one", %{
      conn: conn
    } do
      Repo.update_all(from(t in Text, where: t.work_id == "T0262"),
        set: [meta: %{"addressing" => "derived"}]
      )

      {:ok, view, _} = live(conn, ~p"/?#{[q: "如是我聞", mode: "phrase"]}")

      assert has_element?(
               view,
               ~s(article[data-source-urn="pramana:cbeta.T:T0262_001@p0001c17"]),
               "derived anchor — no printed page"
             )

      refute has_element?(
               view,
               ~s(article[data-source-urn="pramana:cbeta.T:T2187_001@p0002a01"]),
               "derived anchor"
             )
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
