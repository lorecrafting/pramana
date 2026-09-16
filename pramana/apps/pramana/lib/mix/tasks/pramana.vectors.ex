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

  @switches [
    source: :string,
    translations: :boolean,
    lang: :string,
    work: :string,
    refresh: :boolean
  ]

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _} = OptionParser.parse!(argv, strict: @switches)
    lang = Keyword.get(opts, :lang, "en")

    texts = texts(opts)
    if texts == [], do: Mix.raise("no texts matched — chunk them first with mix pramana.chunk")

    Mix.shell().info("#{length(texts)} text(s)")
    started = System.monotonic_time(:millisecond)

    refresh = opts[:refresh] || false

    {sources, translations, stale} =
      texts
      |> Enum.with_index(1)
      |> Enum.reduce({0, 0, 0}, fn {id, i}, {src, tr, st} ->
        {:ok, s} = Vectors.build_source(id)

        {t, n} = translations_for(id, lang, refresh, opts[:translations])

        if rem(i, 1_000) == 0, do: Mix.shell().info("  #{i}/#{length(texts)}")
        {src + s, tr + t, st + n}
      end)

    elapsed = div(System.monotonic_time(:millisecond) - started, 1000)
    report(sources, translations, stale, elapsed)
  end

  defp translations_for(_id, _lang, _refresh, nil), do: {0, 0}

  defp translations_for(id, lang, refresh, _yes) do
    case Vectors.build_translations(id, lang: lang, refresh: refresh) do
      {:ok, t} -> {t, 0}
      {:ok, t, stale} -> {t, stale}
    end
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

  defp report(sources, translations, stale, elapsed) do
    rows =
      Enum.map_join(Vectors.stats(), "\n", fn s ->
        "      #{String.pad_trailing("#{s.kind}/#{s.lang}", 18)} #{s.vectors} row(s), " <>
          "#{s.embedded} embedded"
      end)

    Mix.shell().info("""

    built vector rows in #{elapsed}s
      new source rows:      #{sources}
      new translation rows: #{translations}
    #{stale_line(stale)}
    #{rows}
    """)
  end

  # A row that exists and no longer matches the text it was built from. It is never
  # rewritten in place — `Pramana.Chunk.Vectors.insert/1` says why — so the choice is to
  # count it or to rebuild it, and counting it silently is how a corrected translation
  # stays uncorrected in the index it feeds.
  defp stale_line(0), do: ""

  defp stale_line(n) do
    """
      STALE:                #{n} row(s) whose text has changed since they were built.
                            They still hold the old words and the old vector. Rebuild
                            them with --refresh, then re-embed.
    """
    |> String.trim_trailing()
  end
end
