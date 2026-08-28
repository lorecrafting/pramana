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

  @switches [in: :string, model: :string, rebuild_index: :boolean]

  defp maybe_without_index(opts, fun) do
    if opts[:rebuild_index], do: without_index(fun), else: fun.()
  end

  # Delegated to `mix pramana.embed.index` rather than repeating its DDL here.
  #
  # This task had its own copy, and #40 moved vectors out of `chunks` into
  # `chunk_vectors` without updating it — so `--rebuild-index` dropped an index that no
  # longer existed (a silent no-op, leaving the real one live and the import slow) and
  # then rebuilt against `chunks.embedding`, a column that had been gone for two phases.
  # The flag documented as buying 2.3× had been doing the opposite, and nothing said so.
  #
  # One place knows the index name, the table, and that the build has to hold
  # `maintenance_work_mem` on its own connection.
  defp without_index(fun) do
    Mix.shell().info("dropping the vector index — semantic search is unindexed until rebuilt")
    Mix.Task.rerun("pramana.embed.index", ["--drop"])

    result = fun.()

    Mix.shell().info("rebuilding the vector index (this takes minutes)...")
    Mix.Task.rerun("pramana.embed.index", [])

    result
  end

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _} = OptionParser.parse!(argv, strict: @switches)
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
