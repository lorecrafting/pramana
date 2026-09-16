defmodule Pramana.Retrieval.DateFilterTest do
  @moduledoc """
  `composed_after` / `composed_before`, and the two ways they can quietly lie.

  A date here is a **bound derived from the attributed author's lifespan**, never a
  composition date, so every question this filter answers is "which century" and none of
  them is "which year". The tests are mostly about the edges, because the middle is
  obvious and the edges are where a plausible wrong answer comes from:

  1. **A missing end is not an infinite one.** 性起 died in 1798 with no birth recorded, and
     the first version returned his work under `composed_before: 400` — formally defensible
     from a null lower bound, and useless. The known end stands in for the missing one.
  2. **An undated work is unaddressed, not excluded.** It is invisible to the filter, and
     that is a different statement from "we determined it falls outside the window". Only
     `Coverage.dated/0` can say how much of the shelf that hides.

  Both retrievers are exercised. A filter honoured by one and dropped by the other is the
  `division:` bug, which shipped contaminated results that still looked filtered.
  """
  use Pramana.DataCase, async: false

  alias Pramana.Corpus.Loader
  alias Pramana.Corpus.Work
  alias Pramana.Coverage
  alias Pramana.Normalize.CBETA
  alias Pramana.Repo
  alias Pramana.Retrieval.Lexical
  alias Pramana.Retrieval.Semantic

  import Ecto.Query

  @phrase "一切眾生"

  defp load!(work_id, dates) do
    xml = """
    <TEI xmlns="http://www.tei-c.org/ns/1.0" xmlns:cb="http://www.cbeta.org/ns/1.0">
    <teiHeader><fileDesc><titleStmt><title level="m">測試</title>
    <author>x</author></titleStmt></fileDesc></teiHeader>
    <text><body><milestone n="1" unit="juan"/><lb n="0001a01"/>#{@phrase}皆有佛性</body></text>
    </TEI>
    """

    {:ok, ir} = CBETA.normalize(xml, work_id: work_id, canon: "T", volume: 1, number: "0001")

    {:ok, _} =
      Loader.load(ir,
        source: "cbeta",
        witness: "T",
        provenance: [title: work_id, composition_origin: "chinese", text_role: "root"]
      )

    Repo.update_all(from(w in Work, where: w.id == ^work_id), set: dates)
    work_id
  end

  setup do
    # Both ends known — a genuine window.
    load!("T0001", date_start: 638, date_end: 713, date_basis: "authority_lifespan")
    # Death only. The lower bound is null in the row, deliberately: writing 1798 into both
    # would assert a precision nobody has. The FILTER may still use 1798 at both ends.
    load!("T0002", date_start: nil, date_end: 1798, date_basis: "authority_lifespan")
    # Birth only, the mirror case.
    load!("T0003", date_start: 705, date_end: nil, date_basis: "authority_lifespan")
    # No date at all: no authority link, or a linked person DILA gives no dates for.
    load!("T0004", date_start: nil, date_end: nil, date_basis: nil)
    :ok
  end

  defp lexical(opts) do
    {:ok, found} = Lexical.search(@phrase, Keyword.merge([limit: 20], opts))

    found.results |> Enum.map(& &1.span.provenance.work_id) |> Enum.uniq() |> Enum.sort()
  end

  describe "composed_after / composed_before" do
    test "a window keeps only works whose bound overlaps it" do
      assert lexical(composed_after: 618, composed_before: 907) == ["T0001", "T0003"]
    end

    test "a death-only work is compared on its death year, not on an open past" do
      # The bug this replaced: a null `date_start` read as "could be any year", so a work by
      # someone who died in 1798 came back as possibly pre-400.
      refute "T0002" in lexical(composed_before: 400)
      assert "T0002" in lexical(composed_after: 1700)
    end

    test "a birth-only work is compared on its birth year, not on an open future" do
      refute "T0003" in lexical(composed_after: 1500)
      assert "T0003" in lexical(composed_before: 800)
    end

    test "an undated work is invisible to any date filter, in both directions" do
      refute "T0004" in lexical(composed_after: 1)
      refute "T0004" in lexical(composed_before: 3000)
      # ...and present the moment the filter is not asked for, which is what makes it
      # "unaddressed" rather than "excluded".
      assert "T0004" in lexical([])
    end

    test "either end works alone" do
      # 750, not 700: T0003's author was born in 705 and cannot have composed before 700.
      # The first version of this test asserted otherwise and the filter was right.
      assert lexical(composed_before: 750) == ["T0001", "T0003"]
      assert lexical(composed_after: 1000) == ["T0002"]
    end
  end

  describe "the other retriever honours the same options" do
    # Synthetic vectors exercise actual SQL filtering without a model or a provider.
    test "Semantic returns the exact dated subset, including one-sided and unknown bounds" do
      for text <- Repo.all(Pramana.Corpus.Text) do
        {:ok, 1} = Pramana.Chunk.Builder.build_for_text(text.id, max_chars: 100)
        {:ok, 1} = Pramana.Chunk.Vectors.build_source(text.id)
      end

      vector = [1.0 | List.duplicate(0.0, 1023)]

      Repo.update_all(Pramana.Corpus.ChunkVector,
        set: [embedding: Pgvector.new(vector), embedding_model: Pramana.Embed.model()]
      )

      for {opts, expected} <- [
            {[], ~w(T0001 T0002 T0003 T0004)},
            {[composed_after: 618, composed_before: 907], ~w(T0001 T0003)},
            {[composed_before: 400], []},
            {[composed_after: 1700], ["T0002"]},
            {[composed_after: 1500], ["T0002"]},
            {[composed_before: 800], ~w(T0001 T0003)},
            {[composed_after: 1, composed_before: 3000], ~w(T0001 T0002 T0003)}
          ] do
        %{results: results} = Semantic.search_vector(vector, [limit: 20] ++ opts)
        actual = results |> Enum.map(& &1.span.provenance.work_id) |> Enum.sort()

        assert actual == expected,
               "semantic date filter #{inspect(opts)} returned #{inspect(actual)}"
      end
    end

    test "the lexical option list carries them, since a dispatcher filters against it" do
      assert :composed_after in Lexical.known_opts()
      assert :composed_before in Lexical.known_opts()
    end
  end

  describe "Coverage.dated/0" do
    test "reports the denominator a date filter hides" do
      dated = Coverage.dated()

      assert dated.works == 4
      assert dated.dated == 3
      assert dated.undated == 1
      # The sentence is the point: a caller must be able to tell "outside the window" from
      # "never had a date".
      assert dated.note =~ "NOT excluded on evidence"
    end
  end
end
