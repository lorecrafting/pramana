defmodule Pramana.Chunk.BuilderTest do
  @moduledoc """
  Chunks are the unit that gets embedded, so two things must hold: they must be
  semantically coherent (unlike an 18-character printed line), and they must stay
  citable — a semantic hit is worthless if it cannot be verified.
  """
  use Pramana.DataCase, async: false

  import Ecto.Query

  alias Pramana.Chunk.Builder
  alias Pramana.Corpus
  alias Pramana.Corpus.Chunk
  alias Pramana.Corpus.Loader
  alias Pramana.Corpus.Text
  alias Pramana.Guard
  alias Pramana.Normalize.CBETA
  alias Pramana.Repo

  # Twelve 10-character lines across two juan.
  defp load! do
    lines =
      for i <- 1..12 do
        juan = if i <= 6, do: 1, else: 2
        {juan, String.duplicate(<<0x4E00 + i::utf8>>, 10)}
      end

    body =
      lines
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {{juan, text}, i} ->
        n = "0001a" <> String.pad_leading(Integer.to_string(i), 2, "0")

        milestone =
          if i == 1 or (juan == 2 and i == 7), do: ~s(<milestone n="#{juan}" unit="juan"/>)

        "#{milestone}<lb n=\"#{n}\"/>#{text}"
      end)

    xml = """
    <TEI xmlns="http://www.tei-c.org/ns/1.0" xmlns:cb="http://www.cbeta.org/ns/1.0">
    <teiHeader><fileDesc><titleStmt><title level="m">測試</title><author>x</author>
    </titleStmt></fileDesc></teiHeader>
    <text><body>#{body}</body></text></TEI>
    """

    {:ok, ir} = CBETA.normalize(xml, work_id: "T0262", canon: "T", volume: 9, number: "0262")
    {:ok, _} = Loader.load(ir, source: "cbeta", witness: "T", provenance: %{})
    Repo.one!(from t in Text, where: t.work_id == "T0262", select: t.id)
  end

  setup do
    %{text_id: load!()}
  end

  defp chunks(text_id) do
    Repo.all(from c in Chunk, where: c.text_id == ^text_id, order_by: c.first_ordinal)
  end

  describe "grouping" do
    test "packs segments up to max_chars", %{text_id: text_id} do
      {:ok, n} = Builder.build_for_text(text_id, max_chars: 30)

      # 10 chars per line, 30-char budget -> 3 lines per chunk, but juan boundaries
      # split 6+6 into two groups of three.
      assert n == 4
      assert Enum.map(chunks(text_id), & &1.segment_count) == [3, 3, 3, 3]
    end

    test "never crosses a juan boundary", %{text_id: text_id} do
      # A window spanning two fascicles would describe a passage no edition contains.
      {:ok, _} = Builder.build_for_text(text_id, max_chars: 10_000)

      juans = Enum.map(chunks(text_id), & &1.juan)
      assert juans == [1, 2]
      assert Enum.map(chunks(text_id), & &1.segment_count) == [6, 6]
    end

    test "a larger budget yields fewer, longer chunks", %{text_id: text_id} do
      {:ok, small} = Builder.build_for_text(text_id, max_chars: 20)
      {:ok, large} = Builder.build_for_text(text_id, max_chars: 60)

      assert large < small
    end

    test "is idempotent — rebuilding converges", %{text_id: text_id} do
      {:ok, first} = Builder.build_for_text(text_id, max_chars: 30)
      {:ok, second} = Builder.build_for_text(text_id, max_chars: 30)

      assert first == second
      assert length(chunks(text_id)) == second
    end

    test "an oversized single segment still becomes its own chunk", %{text_id: text_id} do
      # Never silently drop content just because one line exceeds the budget.
      {:ok, n} = Builder.build_for_text(text_id, max_chars: 3)
      assert n == 12
    end
  end

  describe "chunks stay citable" do
    test "every chunk URN resolves", %{text_id: text_id} do
      {:ok, _} = Builder.build_for_text(text_id, max_chars: 30)

      for chunk <- chunks(text_id) do
        assert {:ok, _span} = Corpus.resolve(chunk.urn), "#{chunk.urn} does not resolve"
      end
    end

    test "resolved content matches stored content exactly", %{text_id: text_id} do
      {:ok, _} = Builder.build_for_text(text_id, max_chars: 30)

      for chunk <- chunks(text_id) do
        {:ok, span} = Corpus.resolve(chunk.urn)
        assert span.content == chunk.content
      end
    end

    test "the guard verifies a chunk and quotes inside it", %{text_id: text_id} do
      {:ok, _} = Builder.build_for_text(text_id, max_chars: 30)
      chunk = hd(chunks(text_id))

      assert Guard.verify(chunk.urn, chunk.content)
      assert Guard.verify(chunk.urn, String.slice(chunk.content, 5, 10))
      refute Guard.verify(chunk.urn, chunk.content <> "偽")
    end

    test "a multi-segment chunk gets a RANGE urn, a single-segment one stays a point", %{
      text_id: text_id
    } do
      {:ok, _} = Builder.build_for_text(text_id, max_chars: 30)
      assert hd(chunks(text_id)).urn =~ "-"

      {:ok, _} = Builder.build_for_text(text_id, max_chars: 3)
      refute hd(chunks(text_id)).urn =~ "-"
    end

    test "byte offsets slice the chunk out of the stored body", %{text_id: text_id} do
      {:ok, _} = Builder.build_for_text(text_id, max_chars: 30)
      {:ok, body} = Corpus.body("pramana:cbeta.T:T0262")

      for chunk <- chunks(text_id) do
        slice = binary_part(body, chunk.byte_start, chunk.byte_end - chunk.byte_start)
        # The body joins lines with "\n"; chunk content concatenates them.
        assert String.replace(slice, "\n", "") == chunk.content
      end
    end
  end

  describe "group/2 without a database" do
    test "returns an empty list for no segments" do
      assert Builder.group([], 100) == []
    end

    test "keeps every segment — nothing is dropped", %{text_id: text_id} do
      segments =
        Repo.all(
          from s in Pramana.Corpus.Segment, where: s.text_id == ^text_id, order_by: s.ordinal
        )

      grouped = Builder.group(segments, 25)
      assert grouped |> List.flatten() |> length() == length(segments)
    end
  end
end
