defmodule Mix.Tasks.Pramana.AcquireAll do
  @shortdoc "Bulk-acquires an entire source into raw/ from one pinned archive"

  @moduledoc """
  Acquires a whole collection at a pinned commit.

      mix pramana.acquire_all --source cbeta --canon T      # Taisho only, 2,471 works
      mix pramana.acquire_all --source cbeta                # everything, 5,005 works

  One recursive git-tree call builds the catalog, and one archive download fetches the
  bytes — rather than thousands of individual requests. Every extracted file is still
  hashed into `sources.lock.json`, so `mix pramana.verify` keeps its guarantee.
  """

  use Mix.Task

  alias Pramana.Acquire.Archive
  alias Pramana.Acquire.CBETA
  alias Pramana.Acquire.CBETA.Catalog
  alias Pramana.Acquire.Lockfile
  alias Pramana.Sources

  @switches [source: :string, canon: :string, limit: :integer]

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _, _} = OptionParser.parse(argv, switches: @switches)

    source = Keyword.get(opts, :source, "cbeta")
    canon = Keyword.get(opts, :canon)
    {:ok, definition} = Sources.fetch(source)

    Mix.shell().info("resolving upstream pin...")
    {:ok, sha} = CBETA.resolve_pin()
    Mix.shell().info("pinned to #{sha}")

    {:ok, entries} = Catalog.fetch(sha, canon: canon, repo: definition.repo)
    entries = maybe_limit(entries, opts[:limit])

    total_mb = Float.round(Enum.sum(Enum.map(entries, & &1.bytes)) / 1_000_000, 1)

    Mix.shell().info(
      "catalog: #{length(entries)} work(s), #{total_mb} MB" <>
        if(canon, do: " (canon #{canon})", else: " (all collections)")
    )

    {:ok, files} =
      Archive.fetch(source, sha, Enum.map(entries, & &1.path), repo: definition.repo)

    entry =
      Lockfile.build_entry(definition,
        files: files,
        pin: %{"type" => "git", "commit" => sha}
      )

    # MERGED into whatever the source already records, because a collection is not a
    # source: `--canon X` acquires 1,236 of CBETA's files and must not be read as a
    # statement that the other 3,769 are gone. Replacing the entry is how the Taishō
    # fell out of the lockfile while its 2,471 texts stayed in the corpus.
    :ok = merge!(entry)
    {:ok, locked} = Lockfile.get_source(source)

    Mix.shell().info("""

    acquired #{length(files)} file(s) into raw/#{source}/
      pin:          #{sha}
      manifest:     #{locked["files_sha256"]}
      in lockfile:  #{locked["file_count"]} file(s) for #{source}
      lockfile:     #{Lockfile.path()}

    Next: mix pramana.bake_all --source #{source}#{if canon, do: " --canon #{canon}", else: ""}
    """)
  end

  defp merge!(entry) do
    case Lockfile.merge_source(entry) do
      :ok ->
        :ok

      {:error, {:pin_conflict, locked, incoming}} ->
        Mix.raise("""
        #{entry["id"]} is already locked at a different upstream pin.

          locked:   #{inspect(locked)}
          incoming: #{inspect(incoming)}

        One entry cannot honestly carry files fetched at two commits — the pin would be
        wrong for half of them. Re-acquire the whole source at the new pin, and re-bake:
        the corpus those older files produced is not reproducible from the new commit.
        """)
    end
  end

  defp maybe_limit(entries, nil), do: entries
  defp maybe_limit(entries, n), do: Enum.take(entries, n)
end
