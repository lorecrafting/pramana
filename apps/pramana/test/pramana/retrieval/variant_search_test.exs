defmodule Pramana.Retrieval.VariantSearchTest do
  @moduledoc """
  Variant expansion as it reaches search.

  The exit criterion for this feature: searching 說 finds 説 when the option is on and
  not when it is off, and the stored content is unchanged either way.
  """
  use Pramana.DataCase, async: false

  alias Pramana.Corpus.Loader
  alias Pramana.Normalize.CBETA
  alias Pramana.Retrieval.Lexical

  setup do
    # The corpus writes the traditional forms, as CBETA does.
    xml = """
    <TEI xmlns="http://www.tei-c.org/ns/1.0" xmlns:cb="http://www.cbeta.org/ns/1.0">
    <teiHeader><fileDesc><titleStmt><title level="m">測試</title></titleStmt></fileDesc></teiHeader>
    <text><body><milestone n="1" unit="juan"/>
    <lb n="0001a01"/>一切眾生皆有佛性
    <lb n="0001a02"/>佛說如是法門
    </body></text></TEI>
    """

    {:ok, ir} = CBETA.normalize(xml, work_id: "T0001", canon: "T", volume: 1, number: "0001")

    {:ok, _} =
      Loader.load(ir,
        source: "cbeta",
        witness: "T",
        provenance: %{composition_origin: "indic", text_role: "root"}
      )

    :ok
  end

  describe "the exit criterion" do
    test "a simplified query finds the traditional text ONLY when expansion is on" do
      assert {:ok, off} = Lexical.search("众生", mode: :phrase)
      assert off.total == 0

      assert {:ok, on} = Lexical.search("众生", mode: :phrase, normalize_variants: true)
      assert on.total == 1
      assert hd(on.results).span.content =~ "眾生"
    end

    test "a Japanese-form query finds the CBETA form only when expansion is on" do
      assert {:ok, off} = Lexical.search("佛説", mode: :phrase)
      assert off.total == 0

      assert {:ok, on} = Lexical.search("佛説", mode: :phrase, normalize_variants: true)
      assert on.total == 1
    end

    test "stored content is byte-identical either way" do
      # Expansion is query-side. If it ever touched the index this would change.
      {:ok, a} = Lexical.search("眾生", mode: :phrase)
      {:ok, b} = Lexical.search("众生", mode: :phrase, normalize_variants: true)

      assert hd(a.results).span.content == hd(b.results).span.content
      assert hd(a.results).span.sha256 == hd(b.results).span.sha256
    end
  end

  describe "reporting" do
    test "the response says which characters were expanded" do
      {:ok, r} = Lexical.search("众生", mode: :phrase, normalize_variants: true)

      assert r.variants.applied
      assert r.variants.expanded["众"] == ["众", "眾", "衆"]
    end

    test "and says plainly when it was not applied" do
      {:ok, r} = Lexical.search("眾生", mode: :phrase)

      refute r.variants.applied
      assert r.variants.expanded == %{}
    end
  end

  describe "off by default" do
    test "expansion never happens unless asked for" do
      # A silent widening of every query would change what "exact phrase" means.
      assert {:ok, %{total: 0}} = Lexical.search("众生", mode: :phrase)
      assert {:ok, %{total: 0}} = Lexical.search("众生", mode: :phrase, normalize_variants: false)
    end

    test "a query already in the corpus's orthography is unaffected by the option" do
      {:ok, off} = Lexical.search("眾生", mode: :phrase)
      {:ok, on} = Lexical.search("眾生", mode: :phrase, normalize_variants: true)

      assert off.total == on.total
    end
  end
end
