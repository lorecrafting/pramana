defmodule PramanaWeb.ReaderWorkLiveTest do
  use PramanaWeb.ConnCase, async: false
  import Ecto.Query
  import Phoenix.LiveViewTest
  import PramanaWeb.ReaderFixtures
  alias Pramana.Corpus.AuthorityPerson
  alias Pramana.Corpus.AuthorityPlace
  alias Pramana.Corpus.AuthorityRelation
  alias Pramana.Corpus.Text
  alias Pramana.Corpus.Work
  alias Pramana.Normalize.CBETA
  alias Pramana.Repo
  setup :load_reader_fixture

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

    test "renders outline entries with and without anchors", %{conn: conn} do
      Repo.update_all(
        from(t in Text, where: t.work_id == "T2187"),
        set: [
          outline: %{
            "entries" => [
              %{
                "type" => "juan",
                "n" => 1,
                "level" => 1,
                "title" => "序品第一",
                "juan" => 1,
                "anchor" => "p0002a01"
              },
              %{
                "type" => "pin",
                "n" => 2,
                "level" => 2,
                "title" => "無錨段落",
                "juan" => 1,
                "anchor" => nil
              }
            ]
          }
        ]
      )

      {:ok, _view, html} = live(conn, ~p"/works/T2187")

      assert html =~ "序品第一"
      assert html =~ "無錨段落"
      assert html =~ "recorded with no anchor, so it cannot be opened"
    end

    test "renders shared passages count in alternate works transmitting this material", %{
      conn: conn
    } do
      insert_work_relation!(evidence: %{"full_parallels" => 15})

      {:ok, _view, html} = live(conn, ~p"/works/T0262")

      assert html =~ "Other works transmitting this material"
      assert html =~ "15 shared passages"
    end
  end

  describe "the hand behind the byline" do
    setup do
      %AuthorityPlace{}
      |> Ecto.Changeset.change(%{
        id: "PL_KUCHA",
        name: "龜茲",
        district: "中國-新疆維吾爾自治區",
        country: "西域",
        source: "dila-authority"
      })
      |> Repo.insert!()

      %AuthorityPerson{}
      |> Ecto.Changeset.change(%{
        id: "A000001",
        name: "鳩摩羅什",
        names: ["鳩摩羅什", "羅什"],
        dynasty: "後秦",
        birth_earliest: ~D[0344-01-01],
        death_latest: ~D[0413-12-31],
        sect: "三論宗",
        place_id: "PL_KUCHA",
        source: "dila-authority"
      })
      |> Repo.insert!()

      %AuthorityRelation{}
      |> Ecto.Changeset.change(%{
        person_id: "A000001",
        related_id: "A000002",
        related_name: "佛陀耶舍",
        type: "student",
        source: "dila-authority"
      })
      |> Repo.insert!()

      import Ecto.Query, only: [from: 2]

      Repo.update_all(from(w in Work, where: w.id == "T0262"),
        set: [authority_id: "A000001"]
      )

      :ok
    end

    test "names the person, their dates, sect and place", %{conn: conn} do
      %AuthorityRelation{}
      |> Ecto.Changeset.change(%{
        person_id: "A000001",
        related_id: "A000003",
        related_name: "卑摩羅叉",
        type: "teacher",
        source: "dila-authority"
      })
      |> Repo.insert!()

      {:ok, _view, html} = live(conn, ~p"/works/T0262")

      assert html =~ "鳩摩羅什"
      assert html =~ "also 羅什"
      assert html =~ "344–413"
      assert html =~ "三論宗"
      assert html =~ "龜茲"
      # The historical region, not only the modern province — 西域 is what a scholar means.
      assert html =~ "西域"
      assert html =~ "taught by 卑摩羅叉"
      assert html =~ "taught 佛陀耶舍"
    end

    test "a person recorded only by birth prints b. year", %{conn: conn} do
      %AuthorityPerson{}
      |> Ecto.Changeset.change(%{
        id: "A000011",
        name: "玄奘",
        birth_earliest: ~D[0602-01-01],
        death_latest: nil,
        source: "dila-authority"
      })
      |> Repo.insert!()

      Repo.update_all(from(w in Work, where: w.id == "T2187"),
        set: [authority_id: "A000011"]
      )

      {:ok, _view, html} = live(conn, ~p"/works/T2187")

      assert html =~ "玄奘"
      assert html =~ "b. 602"
      refute html =~ "602–"
    end

    test "says the identification is an inference, on the page", %{conn: conn} do
      # A reader who takes the panel as settled fact has been misled by a surface that looked
      # more certain than the data. The caveat is not a footnote elsewhere.
      {:ok, _view, html} = live(conn, ~p"/works/T0262")

      assert html =~ "probable, never certain"
      assert html =~ "unrecorded namesake"
      assert html =~ "span of a life, not of the work"
    end

    test "an open bound is printed as an open bound", %{conn: conn} do
      # 施護 is recorded only by his death. Printing "1018" alone would assert a birth year
      # nobody recorded; "d. 1018" says what is actually known.
      %AuthorityPerson{}
      |> Ecto.Changeset.change(%{
        id: "A000009",
        name: "施護",
        death_latest: ~D[1018-01-25],
        source: "dila-authority"
      })
      |> Repo.insert!()

      import Ecto.Query, only: [from: 2]

      Repo.update_all(from(w in Work, where: w.id == "T2187"),
        set: [authority_id: "A000009"]
      )

      {:ok, _view, html} = live(conn, ~p"/works/T2187")

      assert html =~ "施護"
      assert html =~ "d. 1018"
      refute html =~ "1018–1018"
    end

    test "a person with no recorded dates shows none, and no empty span", %{conn: conn} do
      %AuthorityPerson{}
      |> Ecto.Changeset.change(%{id: "A000010", name: "無名", source: "dila-authority"})
      |> Repo.insert!()

      import Ecto.Query, only: [from: 2]

      Repo.update_all(from(w in Work, where: w.id == "T2187"),
        set: [authority_id: "A000010"]
      )

      {:ok, _view, html} = live(conn, ~p"/works/T2187")

      assert html =~ "無名"
      # The dates caveat is conditional: printing "dates are the span of a life" beside no
      # dates would be noise.
      refute html =~ "span of a life, not of the work"
    end

    test "a work whose byline resolved to nobody renders no panel at all", %{conn: conn} do
      # Roughly 40% of bylines resolve to nobody, and that is a refusal rather than a gap.
      # An empty "Attributed to" heading would assert that a person was identified and
      # nothing is known about them.
      {:ok, _view, html} = live(conn, ~p"/works/T2187")

      refute html =~ "probable, never certain"
    end
  end
end
