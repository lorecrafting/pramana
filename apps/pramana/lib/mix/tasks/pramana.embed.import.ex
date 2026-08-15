defmodule Mix.Tasks.Pramana.Embed.Import do
  @shortdoc "Imports vectors produced on a GPU elsewhere"

  @moduledoc """
      mix pramana.embed.import --in /tmp/vectors.jsonl

      mix pramana.embed.import --in /tmp/vectors.jsonl --rebuild-index

  Verifies each row's `content_sha256` against the stored chunk before writing. A
  vector computed from text that has since changed is REJECTED rather than written,
  because it would attach a plausible-looking vector to the wrong passage and nothing
  would look wrong — it is still 1024 valid floats.

  ## `--rebuild-index`, for a full-corpus import

  Every write to `embedding` maintains the HNSW index incrementally, and at corpus scale
  that is the dominant cost: measured 2026-08-14, importing 299,317 vectors took 88
  minutes against 34 minutes to compute them on a GPU. Dropping the index, loading, and
  building it once is far cheaper.

  Use it for a bulk load, not for a small top-up — rebuilding takes minutes regardless of
  how many rows were imported.

  **If this crashes between the drop and the rebuild, the index is gone.** That failure
  is safe rather than silent: semantic search still returns correct results, by
  sequential scan, and the latency makes it obvious. Recreate with `mix ecto.migrate`.
  """

  use Mix.Task

  alias Pramana.Embed.Transfer
  alias Pramana.Repo

  @switches [in: :string, model: :string, rebuild_index: :boolean]

  @index "chunks_embedding_hnsw_index"

  defp maybe_without_index(opts, fun) do
    if opts[:rebuild_index], do: without_index(fun), else: fun.()
  end

  defp without_index(fun) do
    Mix.shell().info("dropping #{@index} — semantic search is unindexed until it is rebuilt")
    Repo.query!("DROP INDEX IF EXISTS #{@index}")

    result = fun.()

    Mix.shell().info("rebuilding #{@index} (this takes a few minutes)...")
    started = System.monotonic_time(:millisecond)

    Repo.query!("CREATE INDEX #{@index} ON chunks USING hnsw (embedding vector_ip_ops)", [],
      timeout: :infinity
    )

    Mix.shell().info("  rebuilt in #{div(System.monotonic_time(:millisecond) - started, 1000)}s")
    result
  end

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _, _} = OptionParser.parse(argv, switches: @switches)
    path = Keyword.fetch!(opts, :in)

    {:ok, r} = maybe_without_index(opts, fn -> Transfer.import(path, opts) end)

    Mix.shell().info("""

    imported #{r.written} vector(s)
      hash mismatches (rejected): #{length(r.hash_mismatch)}
      wrong dimensions (rejected): #{length(r.bad_dims)}
      unknown chunk ids (rejected): #{length(r.unknown)}
    """)

    if r.hash_mismatch != [] do
      Mix.shell().error("""
      Rejected #{length(r.hash_mismatch)} vector(s) whose source text no longer matches.
      The corpus was re-baked after the export. Re-export and re-embed those chunks.
      Sample ids: #{inspect(Enum.take(r.hash_mismatch, 10))}
      """)
    end
  end
end
