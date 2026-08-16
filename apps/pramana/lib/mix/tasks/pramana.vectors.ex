defmodule Mix.Tasks.Pramana.Vectors do
  @shortdoc "Creates the chunk vector rows that a run of pramana.embed will fill"

  @moduledoc """
  Builds `chunk_vectors` rows — the units that get embedded.

      mix pramana.vectors                    # source vectors for everything
      mix pramana.vectors --translations     # also English translation vectors
      mix pramana.vectors --source sc        # one source at a time
      mix pramana.vectors --lang en

  A row is created before it has a vector, holding the exact text to embed and its
  hash. `mix pramana.embed.export` then writes that text out and
  `mix pramana.embed.import` writes vectors back, re-checking the hash — which is only
  possible because the row existed first.

  Two kinds are built here. `source` is the passage as printed. `translation` is the
  same span in a translator's words, and exists because an English question reaching
  Literary Chinese or Pāli otherwise depends entirely on the embedding model's
  cross-language space, which `Pramana.Retrieval.Semantic` is explicit about not
  trusting. A translation vector changes what can be FOUND, never what can be cited.
  """

  use Mix.Task

  import Ecto.Query

  alias Pramana.Chunk.Vectors
  alias Pramana.Corpus.Text
  alias Pramana.Repo

  @switches [source: :string, translations: :boolean, lang: :string, work: :string]

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _, _} = OptionParser.parse(argv, switches: @switches)
    lang = Keyword.get(opts, :lang, "en")

    texts = texts(opts)
    if texts == [], do: Mix.raise("no texts matched — chunk them first with mix pramana.chunk")

    Mix.shell().info("#{length(texts)} text(s)")
    started = System.monotonic_time(:millisecond)

    {sources, translations} =
      texts
      |> Enum.with_index(1)
      |> Enum.reduce({0, 0}, fn {id, i}, {src, tr} ->
        {:ok, s} = Vectors.build_source(id)

        {:ok, t} =
          if opts[:translations], do: Vectors.build_translations(id, lang: lang), else: {:ok, 0}

        if rem(i, 1_000) == 0, do: Mix.shell().info("  #{i}/#{length(texts)}")
        {src + s, tr + t}
      end)

    elapsed = div(System.monotonic_time(:millisecond) - started, 1000)
    report(sources, translations, elapsed)
  end

  defp texts(opts) do
    query = from t in Text, select: t.id, order_by: t.id

    query
    |> then(fn q ->
      if opts[:source], do: where(q, [t], t.source_id == ^opts[:source]), else: q
    end)
    |> then(fn q -> if opts[:work], do: where(q, [t], t.work_id == ^opts[:work]), else: q end)
    |> Repo.all()
  end

  defp report(sources, translations, elapsed) do
    rows =
      Enum.map_join(Vectors.stats(), "\n", fn s ->
        "      #{String.pad_trailing("#{s.kind}/#{s.lang}", 18)} #{s.vectors} row(s), " <>
          "#{s.embedded} embedded"
      end)

    Mix.shell().info("""

    built vector rows in #{elapsed}s
      new source rows:      #{sources}
      new translation rows: #{translations}

    #{rows}
    """)
  end
end
