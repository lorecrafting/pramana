defmodule Mix.Tasks.Pramana.Embed.Index do
  @shortdoc "Builds (or rebuilds) the HNSW index over chunk vectors"

  @moduledoc """
  Creates the approximate-nearest-neighbour index that makes semantic search fast.

      mix pramana.embed.index                  # build if absent
      mix pramana.embed.index --rebuild        # drop and rebuild
      mix pramana.embed.index --drop           # drop only, before a large import
      mix pramana.embed.index --memory 4GB

  ## Why this is a task and not a migration

  Incremental HNSW maintenance is expensive: importing 299,317 vectors into a live index
  took 88 minutes against 34 minutes to compute them on a GPU (#37). The workflow is
  therefore **drop, import, rebuild**, which is an operational sequence, not a schema
  change — and a migration that built the index would build it again on every restore for
  no benefit.

  ## Memory is not a tuning knob here

  An HNSW build that does not fit in `maintenance_work_mem` falls back to building on
  disk, and it does not merely run slower — it *degrades* as the graph grows. At
  PostgreSQL's 64 MB default this index reached 187k of 299,317 tuples in 17 minutes and
  was still slowing. Size the memory to the graph: roughly `rows × dimensions × 4 bytes`,
  plus the links, so ~1.5 GB per 300k vectors at 1024 dimensions.
  """

  use Mix.Task

  alias Pramana.Repo

  @switches [rebuild: :boolean, drop: :boolean, memory: :string]

  @index "chunk_vectors_embedding_hnsw_index"
  @default_memory "4GB"

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _, _} = OptionParser.parse(argv, switches: @switches)

    # `opts[:x] or opts[:y]` raises when both are nil — Elixir's `or` demands booleans.
    if opts[:drop] == true or opts[:rebuild] == true, do: drop()

    unless opts[:drop] == true do
      build(Keyword.get(opts, :memory, @default_memory))
    end

    report()
  end

  defp drop do
    Mix.shell().info("dropping #{@index}…")
    Repo.query!("DROP INDEX IF EXISTS #{@index}")
  end

  defp build(memory) do
    if exists?() do
      Mix.shell().info("#{@index} already exists — use --rebuild to replace it")
    else
      vectors = count_embedded()

      Mix.shell().info(
        "building #{@index} over #{vectors} embedded vector(s) with " <>
          "maintenance_work_mem = #{memory}…"
      )

      started = System.monotonic_time(:second)

      # BOTH statements must run on the SAME connection, so they go inside one
      # transaction. `Repo.query!` checks a connection out of the pool per call, so a
      # bare `SET maintenance_work_mem` followed by a bare `CREATE INDEX` can land on
      # different backends — the setting applies to a connection that then goes idle,
      # and the build runs at the 64 MB default anyway. It fails silently: the index is
      # built correctly, just an order of magnitude slower, which looks like "HNSW is
      # slow" rather than like a bug. Measured: ~22k tuples/min with the memory, ~1.6k
      # without.
      Repo.transaction(
        fn ->
          Repo.query!("SET LOCAL maintenance_work_mem = '#{memory}'")

          Repo.query!(
            "CREATE INDEX #{@index} ON chunk_vectors USING hnsw (embedding vector_ip_ops)",
            [],
            timeout: :infinity
          )
        end,
        timeout: :infinity
      )

      Mix.shell().info("  built in #{System.monotonic_time(:second) - started}s")
    end
  end

  defp exists? do
    %{rows: [[count]]} =
      Repo.query!("SELECT count(*) FROM pg_indexes WHERE indexname = $1", [@index])

    count > 0
  end

  defp count_embedded do
    %{rows: [[count]]} =
      Repo.query!("SELECT count(*) FROM chunk_vectors WHERE embedding IS NOT NULL")

    count
  end

  defp report do
    %{rows: rows} =
      Repo.query!("""
      SELECT kind, lang, count(*), count(embedding)
      FROM chunk_vectors GROUP BY kind, lang ORDER BY count(*) DESC
      """)

    Mix.shell().info("""

    chunk vectors
    #{Enum.map_join(rows, "\n", fn [kind, lang, total, embedded] -> "      #{String.pad_trailing("#{kind}/#{lang}", 18)} #{total} row(s), #{embedded} embedded" end)}

      index present: #{exists?()}
    """)
  end
end
