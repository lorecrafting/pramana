defmodule Mix.Tasks.Pramana.Acquire do
  @shortdoc "Fetches pinned upstream corpus sources into raw/"

  @moduledoc """
  Fetches upstream corpus sources into `raw/`, recording an immutable pin and
  per-file hashes in `sources.lock.json`.

      mix pramana.acquire --source cbeta --work T0262 --volume 9
      mix pramana.acquire --source cbeta --verify

  `raw/` is append-only and gitignored. Re-running verifies hashes rather than
  refetching. See `docs/ARCHITECTURE.md`, "Stage 0 — Acquire".
  """

  use Mix.Task

  alias Pramana.Acquire.CBETA
  alias Pramana.Acquire.Lockfile

  @switches [source: :string, work: :string, volume: :integer, canon: :string, verify: :boolean]

  @impl Mix.Task
  def run(argv) do
    {:ok, _} = Application.ensure_all_started(:req)
    {opts, _, _} = OptionParser.parse(argv, switches: @switches)

    source = Keyword.get(opts, :source, "cbeta")

    cond do
      opts[:verify] -> verify(source)
      source == "cbeta" -> acquire_cbeta(opts)
      true -> Mix.raise("acquire for source #{inspect(source)} is not implemented yet")
    end
  end

  defp verify(source) do
    case Lockfile.verify(source) do
      {:ok, count} ->
        Mix.shell().info("verified #{count} file(s) for #{source} against sources.lock.json")

      {:error, :not_locked} ->
        Mix.raise("#{source} is not in sources.lock.json — run acquire first")

      {:error, {:mismatches, mismatches}} ->
        for m <- mismatches, do: Mix.shell().error("  #{m.path}: #{inspect(m.reason)}")

        Mix.raise("""
        raw/ does not match sources.lock.json (#{length(mismatches)} file(s)).

        raw/ is append-only and must never be edited by hand (CLAUDE.md invariant #3).
        Delete the affected files and re-run acquire to restore them.
        """)
    end
  end

  defp acquire_cbeta(opts) do
    work = Keyword.get(opts, :work, "T0262")
    volume = Keyword.get(opts, :volume, 9)
    canon = Keyword.get(opts, :canon, "T")
    number = String.replace_prefix(work, canon, "")

    path = CBETA.work_path(canon, volume, number)

    Mix.shell().info("resolving upstream pin...")
    {:ok, sha} = CBETA.resolve_pin()
    Mix.shell().info("pinned to #{sha}")

    case CBETA.fetch_paths(sha, [path]) do
      {:ok, %{refetched: false, files: files}} ->
        Mix.shell().info("already up to date (#{length(files)} file(s) verified)")

      {:ok, %{files: files}} ->
        for f <- files, do: Mix.shell().info("  fetched #{f.path} (#{f.bytes} bytes)")
        Mix.shell().info("wrote #{Lockfile.path()}")

      {:error, reason} ->
        Mix.raise("acquire failed: #{inspect(reason)}")
    end
  end
end
