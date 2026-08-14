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

    :ok = Lockfile.put_source(entry)

    Mix.shell().info("""

    acquired #{length(files)} file(s) into raw/#{source}/
      pin:          #{sha}
      manifest:     #{entry["files_sha256"]}
      lockfile:     #{Lockfile.path()}

    Next: mix pramana.bake_all --source #{source}#{if canon, do: " --canon #{canon}", else: ""}
    """)
  end

  defp maybe_limit(entries, nil), do: entries
  defp maybe_limit(entries, n), do: Enum.take(entries, n)
end
