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

  describe "a locator grammar that already uses the range separator" do
    setup do
      # SuttaCentral numbers a merged section `53-55.1`, so the hyphen is inside the
      # locator as well as being the character that joins two of them. 749 Pāli segments
      # are addressed this way.
      Repo.insert!(%Pramana.Corpus.Source{
        id: "sc",
        name: "SuttaCentral",
        license_spdx: "CC-PDM-1.0",
        license_class: "public-domain",
        commercial_use: true,
        redistributable: true
      })

      Repo.insert!(%Pramana.Corpus.Witness{id: "ms", name: "Mahāsaṅgīti"})
      work = Repo.insert!(%Pramana.Corpus.Work{id: "mn12"})

      text =
        Repo.insert!(%Text{
          work_id: work.id,
          source_id: "sc",
          witness_id: "ms",
          urn_prefix: "pramana:sc.ms:mn12",
          body: "",
          body_sha256: "x",
          meta: %{}
        })

      for i <- 1..8 do
        content = String.duplicate("sa", 10)

        Repo.insert!(%Pramana.Corpus.Segment{
          text_id: text.id,
          urn: "pramana:sc.ms:mn12@53-55.#{i}",
          ordinal: i - 1,
          content: content,
          content_sha256: :crypto.hash(:sha256, content) |> Base.encode16(case: :lower),
          char_start: 0,
          char_end: 20,
          byte_start: 0,
          byte_end: 20,
          meta: %{}
        })
      end

      %{sc_text_id: text.id}
    end

    test "two chunks of one section do not collide on the same URN", %{sc_text_id: id} do
      # Building the range from PARSED locators produced `mn12@53-53` for every chunk in
      # the section: `53-55.1` parses as a range from `53` to `55.1`, so both endpoints
      # collapsed to `53`. Two such chunks in one insert violate the unique index, and
      # before that they were simply the same wrong address.
      {:ok, _} = Builder.build_for_text(id, max_chars: 40)

      urns = Enum.map(chunks(id), & &1.urn)

      assert length(urns) > 1
      assert length(Enum.uniq(urns)) == length(urns)
      refute "pramana:sc.ms:mn12@53-53" in urns
    end

    test "the URN names its real endpoints", %{sc_text_id: id} do
      {:ok, _} = Builder.build_for_text(id, max_chars: 40)

      assert hd(chunks(id)).urn == "pramana:sc.ms:mn12@53-55.1-53-55.2"
    end

    test "and still resolves, by identity rather than by splitting", %{sc_text_id: id} do
      # `53-55.1-53-55.2` cannot be divided back into two locators by any rule. The chunk
      # records the ordinals it spans, so the URN resolves as the stored address it is.
      {:ok, _} = Builder.build_for_text(id, max_chars: 40)

      for chunk <- chunks(id) do
        assert {:ok, span} = Corpus.resolve(chunk.urn), "#{chunk.urn} does not resolve"
        assert span.content == chunk.content
      end
    end

    test "the guard verifies a quote from one", %{sc_text_id: id} do
      {:ok, _} = Builder.build_for_text(id, max_chars: 40)
      chunk = hd(chunks(id))

      assert Guard.verify(chunk.urn, chunk.content)
      refute Guard.verify(chunk.urn, chunk.content <> "xyz")
    end
  end

  describe "the chunk size for a script" do
    test "each script has its own, and an unknown source takes the Chinese default" do
      # Not a preference. The embedder truncates at 320 BGE-M3 tokens, and these are the
      # largest sizes whose 95th percentile fits: Pāli tokenizes at 0.425 tokens per
      # character and Tibetan at 0.151, so the same window holds very different amounts
      # of each. See the table in `Pramana.Chunk.Builder`.
      assert Builder.max_chars_for_source("sc") == 700
      assert Builder.max_chars_for_source("derge") == 1_200
      # Both halves of the Degé are the same script; a source missing here silently takes
      # the Chinese 300, which for Tibetan is a fifth of the window.
      assert Builder.max_chars_for_source("derge-tengyur") == 1_200
      assert Builder.max_chars_for_source("cbeta") == 300
    end

    test "Pāli is no longer 1,200, which embedded two thirds of each chunk" do
      # 76.2% of Pāli chunks at 1,200 characters exceeded the window, so their vectors
      # described a prefix while the text they claimed to describe stayed whole in the
      # database — invisible in every count.
      refute Builder.max_chars_for_source("sc") == 1_200
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
