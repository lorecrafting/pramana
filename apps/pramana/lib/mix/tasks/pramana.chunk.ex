defmodule Mix.Tasks.Pramana.Chunk do
  @shortdoc "Builds retrieval chunks over the baked segments"

  @moduledoc """
  Groups segments into ~300-character windows for embedding.

      mix pramana.chunk                 # whole corpus
      mix pramana.chunk --work T0262
      mix pramana.chunk --max-chars 400

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

  @switches [work: :string, max_chars: :integer]

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _, _} = OptionParser.parse(argv, switches: @switches)
    max_chars = Keyword.get(opts, :max_chars, 300)

    texts =
      case opts[:work] do
        nil -> Repo.all(from t in Text, select: {t.id, t.work_id}, order_by: t.work_id)
        work -> Repo.all(from t in Text, where: t.work_id == ^work, select: {t.id, t.work_id})
      end

    if texts == [], do: Mix.raise("nothing to chunk — run mix pramana.bake_all first")

    started = System.monotonic_time(:millisecond)

    total =
      texts
      |> Enum.with_index(1)
      |> Enum.reduce(0, fn {{id, work_id}, i}, acc ->
        {:ok, n} = Builder.build_for_text(id, max_chars: max_chars)

        if rem(i, 250) == 0 do
          Mix.shell().info("  #{i}/#{length(texts)} works, #{acc + n} chunks (#{work_id})")
        end

        acc + n
      end)

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
      segments:         #{segments}
      reduction:        #{Float.round(segments / max(total, 1), 1)}x fewer rows to embed
      avg chunk chars:  #{avg && Float.round(Decimal.to_float(avg), 1)}
    """)
  end
end
