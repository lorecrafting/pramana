defmodule PramanaWeb.ReaderPassageLiveTest do
  use PramanaWeb.ConnCase, async: false
  import Ecto.Query
  import Phoenix.LiveViewTest
  import PramanaWeb.ReaderFixtures
  alias Pramana.Corpus.Loader
  alias Pramana.Corpus.Text
  alias Pramana.Corpus.Work
  alias Pramana.Normalize.CBETA
  alias Pramana.Repo
  setup :load_reader_fixture

  describe "commentary on a line" do
    @root_urn "pramana:cbeta.T:T0262_001@p0001c17"

    # `get_glosses` had this defect on the API side and the page has it too: eight of 109
    # rendered in silence tells the reader there are eight. 27 root lines in the corpus
    # carry more than eight.
    test "says how many quotations exist when it shows only some", %{conn: conn} do
      align!(12)

      {:ok, _view, html} = live(conn, ~p"/passage?#{[urn: @root_urn]}")

      assert html =~ "Commentary on this line"
      assert html =~ "Showing the 8 longest of 12 quotations"
    end

    test "says nothing about a remainder when there is none", %{conn: conn} do
      align!(3)

      {:ok, _view, html} = live(conn, ~p"/passage?#{[urn: @root_urn]}")

      assert html =~ "Commentary on this line"
      refute html =~ "Showing the"
    end

    defp align!(count) do
      root = Repo.one!(from(s in Pramana.Corpus.Segment, where: s.urn == ^@root_urn))
      original = Repo.one!(from(t in Text, where: t.work_id == "T2187"))
      Repo.delete!(original)
      lemma = "如是我聞一時佛住"

      %{segments: [commentary]} =
        Pramana.CorpusFixtures.text!(
          %{
            work_id: "T2187",
            source_id: "cbeta",
            witness_id: "T",
            urn_prefix: "pramana:cbeta.T:T2187",
            meta: %{}
          },
          [{"pramana:cbeta.T:T2187_001@p0002a01", String.duplicate(lemma, count)}]
        )

      for n <- 0..(count - 1) do
        Pramana.CorpusFixtures.alignment!(root, commentary, lemma,
          commentary_offset: n * String.length(lemma)
        )
      end
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

    test "refuses when no URN is provided in query params", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/passage")

      assert html =~ "That is not a URN this corpus can parse."
    end

    test "displays woodblock leaf photograph for a Derge passage", %{conn: conn} do
      Repo.insert!(%Work{
        id: "toh113",
        title: "Toh 113",
        composition_origin: "indic",
        text_role: "root"
      })

      Repo.insert!(%Pramana.Corpus.Source{
        id: "derge",
        name: "Derge",
        license_spdx: "CC-PDM-1.0",
        license_class: "public-domain",
        commercial_use: true,
        redistributable: true
      })

      Repo.insert!(%Pramana.Corpus.Witness{id: "D", name: "Derge"})

      Pramana.CorpusFixtures.text!(
        %{
          work_id: "toh113",
          source_id: "derge",
          witness_id: "D",
          urn_prefix: "pramana:derge.D:toh113",
          meta: %{}
        },
        [{"pramana:derge.D:toh113@80.1a.1", "ཨོཾ་མ་ཎི་པདྨེ་ཧཱུྃ།"}]
      )

      {:ok, _view, html} = live(conn, ~p"/passage?#{[urn: "pramana:derge.D:toh113@80.1a.1"]}")
      assert html =~ "Photograph of the woodblock leaf"
      assert html =~ "Digitised by the Buddhist Digital Resource Center (BDRC)"
    end

    test "renders translation pool including LLM warning badge (invariant #8)", %{conn: conn} do
      insert_translation!(
        text: "Thus have I heard at one time the Buddha was staying.",
        translator_name: "Leon Hurvitz",
        translator_id: "hurvitz",
        method: "human",
        tier: "t0"
      )

      insert_translation!(
        text: "Thus I heard at one time.",
        translator_name: "Machine Model",
        translator_id: "model_1",
        method: "llm",
        model_id: "test-model",
        tier: "t1"
      )

      {:ok, _view, html} = live(conn, ~p"/passage?#{[urn: "pramana:cbeta.T:T0262_001@p0001c17"]}")

      assert html =~ "Translations"
      assert html =~ "2 in en"
      assert html =~ "Leon Hurvitz"
      assert html =~ "llm-generated — not citable as source"
    end

    test "renders parallels including alert for references not held in this bake", %{conn: conn} do
      insert_parallel!(
        target_work_id: "T2187",
        target_urn: "pramana:cbeta.T:T2187_001@p0002a01",
        target_uid: "t2187",
        relation: "full",
        partial: true
      )

      insert_parallel!(
        target_work_id: "T9999",
        target_urn: nil,
        target_uid: "external_sutta",
        relation: "full",
        partial: false
      )

      {:ok, _view, html} = live(conn, ~p"/passage?#{[urn: "pramana:cbeta.T:T0262_001@p0001c17"]}")

      assert html =~ "Parallels"
      assert html =~ "2 recorded · 1 resolvable here"
      assert html =~ "1 of these point at texts this bake"
      assert html =~ "does not hold, so they cannot be opened"
      assert html =~ "partial"
    end

    test "renders candidates for alternate translations (異譯本)", %{conn: conn} do
      insert_work_relation!(evidence: %{"full_parallels" => 15})

      {:ok, _view, html} = live(conn, ~p"/passage?#{[urn: "pramana:cbeta.T:T0262_001@p0001c17"]}")

      assert html =~ "Other works transmitting this material"
      assert html =~ "Candidates for 異譯本"
      assert html =~ "T2187"
      assert html =~ "probable"
    end

    test "renders sections outline when work has divisions", %{conn: conn} do
      Repo.update_all(
        from(t in Text, where: t.work_id == "T0262"),
        set: [
          outline: %{
            "entries" => [
              %{
                "type" => "juan",
                "n" => 1,
                "level" => 1,
                "title" => "序品第一",
                "juan" => 1,
                "anchor" => "p0001c17"
              }
            ]
          }
        ]
      )

      {:ok, _view, html} = live(conn, ~p"/passage?#{[urn: "pramana:cbeta.T:T0262_001@p0001c17"]}")

      assert html =~ "1 sections in this work"
      assert html =~ "序品第一"
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
end
