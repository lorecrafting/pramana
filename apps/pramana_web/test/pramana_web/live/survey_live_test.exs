defmodule PramanaWeb.ReaderSurveyLiveTest do
  use PramanaWeb.ConnCase, async: false
  import Ecto.Query
  import Phoenix.LiveViewTest
  import PramanaWeb.ReaderFixtures
  alias Pramana.Corpus.Work
  alias Pramana.Repo
  setup :load_reader_fixture

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

    test "submitting survey form pushes query to URL", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/survey")

      view
      |> form("form", %{"q" => "如是我聞"})
      |> render_submit()

      assert_patched(view, ~p"/survey?#{[q: "如是我聞"]}")
    end

    test "submitting empty or whitespace query resets results", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/survey?#{[q: "如是我聞"]}")

      html =
        view
        |> form("form", %{"q" => "   "})
        |> render_submit()

      refute html =~ "printed lines containing it"
    end

    test "shows Taishō division breakdown and top works when works have divisions",
         %{conn: conn} do
      Repo.update_all(from(w in Work, where: w.id == "T0262"),
        set: [division: "法華部", division_en: "Lotus Sutra"]
      )

      Repo.update_all(from(w in Work, where: w.id == "T2187"),
        set: [division: "續經疏部", division_en: nil]
      )

      {:ok, _view, html} = live(conn, ~p"/survey?#{[q: "如是我聞"]}")

      assert html =~ "By Taishō division (部)"
      assert html =~ "法華部"
      assert html =~ "Lotus Sutra"
      assert html =~ "續經疏部"
      assert html =~ "Where it is used most"
      assert html =~ "T0262"
    end
  end
end
