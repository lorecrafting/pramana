defmodule Mix.Tasks.Pramana.Chunk do
  @shortdoc "Builds retrieval chunks over the baked segments"

  @moduledoc """
  Groups segments into windows sized for their script — 300 characters of Literary
  Chinese, 700 of romanised Pāli, 1,200 of Tibetan — for embedding. Those sizes are
  measured against the embedder's tokenizer rather than chosen; see
  `Pramana.Chunk.Builder`.

      mix pramana.chunk                 # whole corpus
      mix pramana.chunk --work T0262
      mix pramana.chunk --source derge    # one source only
      mix pramana.chunk --max-chars 400
      mix pramana.chunk --source sc --force   # re-chunk, discarding THAT source's vectors

  Segments are printed lines (18 characters on average, broken typographically), which
  is the wrong unit to embed. Chunking also cuts the row count roughly 16×, which is
  the difference between embedding the corpus in an afternoon and in a week.
  """

  use Mix.Task

  import Ecto.Query

  alias Pramana.Chunk.Builder
  alias Pramana.Corpus.Chunk
  alias Pramana.Corpus.Text
  alias Pramana.Repo

  @switches [work: :string, source: :string, max_chars: :integer, force: :boolean]

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _, _} = OptionParser.parse(argv, switches: @switches)
    # No default here: the size comes from the text's script unless the caller
    # deliberately overrides it. See `Pramana.Chunk.Builder.max_chars_for/1`.
    max_chars = opts[:max_chars]

    texts = Repo.all(scope(opts))

    if texts == [], do: Mix.raise("nothing to chunk — run mix pramana.bake_all first")

    started = System.monotonic_time(:millisecond)

    chunk_opts = chunk_opts(opts, max_chars)

    {total, protected} =
      texts
      |> Enum.with_index(1)
      |> Enum.reduce({0, 0}, &chunk_one(&1, &2, chunk_opts, length(texts)))

    elapsed = div(System.monotonic_time(:millisecond) - started, 1000)

    # Count segments of the works we actually chunked, not the whole corpus — a
    # single-work run would otherwise report a nonsense reduction ratio.
    text_ids = Enum.map(texts, &elem(&1, 0))

    segments =
      Repo.aggregate(from(s in Pramana.Corpus.Segment, where: s.text_id in ^text_ids), :count)

    avg = Repo.one(from c in Chunk, select: avg(fragment("length(?)", c.content)))

    Mix.shell().info("""

    chunked in #{elapsed}s
      works:            #{length(texts)}
      chunks:           #{total}
      left alone:       #{protected} text(s) whose vectors a rebuild would have discarded#{if protected > 0, do: " (--force to override)", else: ""}
      segments:         #{segments}
      reduction:        #{Float.round(segments / max(total, 1), 1)}x fewer rows to embed
      avg chunk chars:  #{avg && Float.round(Decimal.to_float(avg), 1)}
    """)
  end

  # `--source` exists because `--force` does. Re-chunking discards the vectors of every
  # text it touches, and the corpus holds 299,317 Chinese vectors that cost a GPU hour —
  # so "re-chunk the Pāli at its corrected size" must be sayable without putting those in
  # the blast radius. Narrowing a destructive operation is not a convenience.
  defp scope(opts) do
    query = from(t in Text, select: {t.id, t.work_id}, order_by: t.work_id)

    query
    |> then(fn q -> if opts[:work], do: where(q, [t], t.work_id == ^opts[:work]), else: q end)
    |> then(fn q ->
      if opts[:source], do: where(q, [t], t.source_id == ^opts[:source]), else: q
    end)
  end

  defp chunk_opts(opts, max_chars) do
    [force: opts[:force] == true]
    |> then(fn o -> if max_chars, do: Keyword.put(o, :max_chars, max_chars), else: o end)
  end

  defp chunk_one({{id, work_id}, i}, {acc, protected}, chunk_opts, total_texts) do
    {n, protected} =
      case Builder.build_for_text(id, chunk_opts) do
        {:ok, n} ->
          {n, protected}

        # Refused rather than silently discarding vectors. Counted and reported at the
        # end, so a run over a partly-embedded corpus says exactly what it left alone
        # instead of looking like it did everything.
        {:error, {:would_discard_embeddings, _, _}} ->
          {0, protected + 1}
      end

    if rem(i, 250) == 0 do
      Mix.shell().info("  #{i}/#{total_texts} works, #{acc + n} chunks (#{work_id})")
    end

    {acc + n, protected}
  end
end
