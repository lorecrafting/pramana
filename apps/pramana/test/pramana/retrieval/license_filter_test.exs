defmodule Pramana.Retrieval.LicenseFilterTest do
  @moduledoc """
  The filter that makes "we publish the pipeline, not the corpus" enforceable.

  `license_class` was recorded on every source and displayed in every result from early
  on, which made it *look* enforced. Nothing could actually filter on it, so the licence
  posture was a promise kept by hand — and the Phase 2 gate found that task #16 had been
  marked complete against an exit criterion ("excluded under a CC0-only licence filter")
  that no code satisfied.

  A public surface sets `redistributable_only: true` once. If that option is ever
  accepted and ignored, this is where it shows up.
  """
  use Pramana.DataCase, async: false

  import Ecto.Query

  alias Pramana.Chunk.Builder
  alias Pramana.Corpus.Loader
  alias Pramana.Corpus.Text
  alias Pramana.Normalize.CBETA
  alias Pramana.Repo
  alias Pramana.Retrieval.Lexical
  alias Pramana.Retrieval.Survey

  defp load!(work_id, source, line) do
    xml = """
    <TEI xmlns="http://www.tei-c.org/ns/1.0" xmlns:cb="http://www.cbeta.org/ns/1.0">
    <teiHeader><fileDesc><titleStmt><title level="m">測試</title></titleStmt></fileDesc></teiHeader>
    <text><body><milestone n="1" unit="juan"/><lb n="0001a01"/>#{line}</body></text></TEI>
    """

    {:ok, ir} = CBETA.normalize(xml, work_id: work_id, canon: "T", volume: 1, number: "0001")

    {:ok, _} =
      Loader.load(ir,
        source: source,
        witness: "T",
        provenance: %{composition_origin: "indic", text_role: "root"}
      )

    text_id = Repo.one!(from t in Text, where: t.work_id == ^work_id, select: t.id)
    {:ok, _} = Builder.build_for_text(text_id, max_chars: 300)
  end

  setup do
    # `cbeta` is nc / not redistributable; `sc` (SuttaCentral) is CC0 / redistributable.
    # Both contain the same phrase, so only the licence separates them.
    load!("T0001", "cbeta", "一切眾生皆有佛性")
    load!("SC001", "sc", "一切眾生皆有佛性")
    :ok
  end

  describe "redistributable_only" do
    test "keeps only sources that may be republished" do
      {:ok, all} = Lexical.search("一切眾生皆有佛性", limit: 20)
      {:ok, public} = Lexical.search("一切眾生皆有佛性", limit: 20, redistributable_only: true)

      assert all.total == 2
      assert public.total == 1
      assert hd(public.results).span.provenance.license_class == "cc0"
    end

    test "excludes a restricted local text even though it matches" do
      {:ok, public} = Lexical.search("一切眾生皆有佛性", limit: 20, redistributable_only: true)

      refute Enum.any?(public.results, &(&1.span.provenance.license_class == "nc"))
      refute Enum.any?(public.results, &(&1.span.provenance.license_class == "restricted"))
    end

    test "false or absent leaves the corpus unfiltered, rather than silently narrowing it" do
      {:ok, a} = Lexical.search("一切眾生皆有佛性", limit: 20)
      {:ok, b} = Lexical.search("一切眾生皆有佛性", limit: 20, redistributable_only: false)

      assert a.total == b.total
    end
  end

  describe "license_class" do
    test "restricts to the named classes" do
      {:ok, cc0} = Lexical.search("一切眾生皆有佛性", limit: 20, license_class: "cc0")
      {:ok, nc} = Lexical.search("一切眾生皆有佛性", limit: 20, license_class: "nc")

      assert cc0.total == 1
      assert nc.total == 1
      refute hd(cc0.results).span.urn == hd(nc.results).span.urn
    end

    test "accepts a list" do
      {:ok, both} = Lexical.search("一切眾生皆有佛性", limit: 20, license_class: ["cc0", "nc"])
      assert both.total == 2
    end

    test "a class nothing carries returns nothing rather than everything" do
      # The dangerous failure is a filter that matches nothing and is therefore ignored.
      {:ok, none} = Lexical.search("一切眾生皆有佛性", limit: 20, license_class: "cc-by-sa")
      assert none.total == 0
    end
  end

  describe "survey" do
    test "counts a public-only corpus, not just the full one" do
      # A survey is a claim about how much the corpus contains. A public surface needs
      # that claim to be true of what it can actually serve.
      {:ok, all} = Survey.survey("一切眾生皆有佛性")
      {:ok, public} = Survey.survey("一切眾生皆有佛性", redistributable_only: true)

      assert all.total_segments == 2
      assert public.total_segments == 1
    end
  end

  describe "option validation" do
    test "a misspelled licence option raises rather than being ignored" do
      # `licence` vs `license` is the exact typo this codebase will make.
      assert_raise ArgumentError, ~r/unknown search option/, fn ->
        Lexical.search("一切眾生皆有佛性", licence_class: "cc0")
      end

      assert_raise ArgumentError, ~r/unknown search option/, fn ->
        Lexical.search("一切眾生皆有佛性", redistributable: true)
      end
    end
  end
end
