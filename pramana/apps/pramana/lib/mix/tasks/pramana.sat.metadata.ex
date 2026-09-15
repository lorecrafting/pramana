defmodule Mix.Tasks.Pramana.Sat.Metadata do
  @shortdoc "Fetches IIIF metadata for the Taishō 56–84 works this corpus cannot show"

  @moduledoc """
  Phase 1 of acquiring Taishō volumes 56–84: the metadata, and only the metadata.

      mix pramana.sat.metadata --limit 5      # try it on five works first
      mix pramana.sat.metadata                # all 541, ~30 min at the default interval
      mix pramana.sat.metadata --interval 5000

  ## Why this runs before any text is fetched

  The reader answers `useid={work}_{volume}_{page}` with the whole **fascicle** containing
  that page, and nothing in the catalogue says how many fascicles a work has — so the text
  walk has to be adaptive and needs each work's extent first. See `Pramana.Acquire.SAT`.

  **It is also worth having on its own.** Every manifest carries the work's title, byline
  and 部 division, so this alone lets `Pramana.Coverage` name all 541 missing works instead
  of reporting a number. Publishing the gap is the doctrine; this makes the gap legible.

  ## Resumable, because a polite fetch is a long one

  Each manifest is written to `raw/sat-iiif/manifests/` as it arrives and skipped if already
  present, so an interrupted run continues rather than restarting. `raw/` is append-only
  (invariant #3).

  ## It stops on the first error

  Not `max_retries: 3`. A non-200 from a service being fetched on sufferance is a signal to
  stop, and hammering it is how a courteous fetch becomes the thing the 2026-08-15 letter
  promised not to do.
  """

  use Mix.Task

  alias Pramana.Acquire.SAT

  @index "raw/sat-iiif/manifests_index_20260830.html"
  @out "raw/sat-iiif/manifests"

  @switches [limit: :integer, interval: :integer]

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _} = OptionParser.parse!(argv, strict: @switches)

    {:ok, catalogue} = SAT.catalogue(Pramana.Paths.data(@index))
    File.mkdir_p!(Pramana.Paths.data(@out))

    outstanding = Enum.reject(catalogue, fn {w, v} -> File.exists?(path(w, v)) end)
    targets = if opts[:limit], do: Enum.take(outstanding, opts[:limit]), else: outstanding

    # COUNTED BEFORE THE LIMIT IS APPLIED. Deriving this from `targets` conflated "already
    # fetched" with "not selected because of --limit", so a first run of `--limit 3` over an
    # empty directory reported `already had 538`. A progress line that overstates progress is
    # the same defect as a coverage figure without its denominator.
    held = length(catalogue) - length(outstanding)

    Mix.shell().info("""

      catalogue   #{length(catalogue)} work(s) in T#{SAT.gap_range().first}–T#{SAT.gap_range().last}
      already had #{held}
      outstanding #{length(outstanding)}
      fetching    #{length(targets)} at one request per #{Keyword.get(opts, :interval, 3000)} ms
      identifying as #{SAT.user_agent()}
    """)

    results = Enum.reduce_while(targets, [], &fetch_one(&1, &2, opts))
    report(results, length(catalogue))
  end

  defp fetch_one({work, volume}, acc, opts) do
    url = SAT.manifest_url(work, volume)

    case SAT.get(url, interval_ms: Keyword.get(opts, :interval, 3000)) do
      {:ok, json} ->
        # No `is_binary/1` guard here: `SAT.get/1` is specced to return a binary, and
        # dialyzer rightly called the defensive `else` branch unreachable. A guard that
        # contradicts its own contract is not robustness, it is two claims about one thing.
        File.write!(path(work, volume), json)
        summary = json |> Jason.decode!() |> SAT.summarize_manifest()

        Mix.shell().info(
          "  T#{work} v#{volume}  #{summary.title}  #{summary.pages}p  #{summary.author}"
        )

        {:cont, [{work, volume, summary} | acc]}

      {:error, reason} ->
        Mix.shell().error("""
          STOPPED at T#{work} v#{volume}: #{inspect(reason)}

          Not retried, deliberately. #{length(acc)} manifest(s) fetched and kept; re-running
          resumes from here. If this is a 403 or a 429, stop and read docs/sat-request-email.md
          before trying again.
        """)

        {:halt, acc}
    end
  end

  defp path(work, volume),
    do: Path.join(Pramana.Paths.data(@out), "#{work}_#{volume}_manifest.json")

  defp report([], _total), do: Mix.shell().info("\n  nothing fetched\n")

  defp report(results, total) do
    pages = results |> Enum.map(fn {_, _, s} -> s.pages end) |> Enum.sum()
    with_author = Enum.count(results, fn {_, _, s} -> s.author != "" end)

    Mix.shell().info("""

      fetched     #{length(results)} manifest(s) of #{total}
      pages       #{pages} Taishō page(s) described
      bylines     #{with_author} of #{length(results)} carry an author
      written to  #{@out}

      These describe works the corpus does NOT hold. Nothing here is citable text.
    """)
  end
end
