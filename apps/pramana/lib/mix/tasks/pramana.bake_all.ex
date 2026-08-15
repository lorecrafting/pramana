defmodule Mix.Tasks.Pramana.BakeAll do
  @shortdoc "Bakes every acquired work via Oban, resumably"

  @moduledoc """
  Bakes an entire acquired collection.

      mix pramana.bake_all --source cbeta --canon T
      mix pramana.bake_all --source cbeta --canon T --limit 30   # a slice, for iterating
      mix pramana.bake_all --resume                              # continue an interrupted run

  Enqueues one Oban job per work and waits, reporting progress. Because each work is
  its own job, a run that is killed can be resumed, and a malformed file fails one job
  rather than the bake.

  Reads only from `raw/`, never the network.
  """

  use Mix.Task

  import Ecto.Query

  alias Pramana.Acquire.Lockfile
  alias Pramana.Bake
  alias Pramana.Bake.Worker
  alias Pramana.Repo

  @switches [source: :string, canon: :string, limit: :integer, resume: :boolean, quiet: :boolean]

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _, _} = OptionParser.parse(argv, switches: @switches)

    source = Keyword.get(opts, :source, "cbeta")
    canon = Keyword.get(opts, :canon)

    unless opts[:resume], do: enqueue(source, canon, opts[:limit])

    started = System.monotonic_time(:millisecond)
    wait_for_completion(started, opts)

    report(source, canon, started)
  end

  # Entries come from the LOCKFILE, not a fresh network call: the bake must be
  # reproducible from sources.lock.json alone.
  defp enqueue(source, canon, limit) do
    {:ok, entry} = Lockfile.get_source(source)

    # Oban retains finished jobs, and the progress counters read the queue rather than
    # this run. Without this the second full bake reported "works baked: 4941" for a
    # 2,471-work corpus — both runs summed, a wrong number that looks plausible. The
    # queue is a work list; `bakes` is the audit log. `--resume` skips this, because
    # there the earlier run's jobs ARE the run being counted.
    Repo.delete_all(
      from j in "oban_jobs", where: j.queue == "bake" and j.state in ["completed", "discarded"]
    )

    jobs =
      entry["files"]
      |> Enum.flat_map(&entry_from_path/1)
      |> filter_canon(canon)
      |> maybe_limit(limit)

    Mix.shell().info("enqueueing #{length(jobs)} work(s)...")

    jobs
    |> Enum.map(&Worker.new(Worker.args(source, &1)))
    |> Enum.chunk_every(500)
    |> Enum.each(&Oban.insert_all/1)
  end

  @path_pattern ~r{^(?<canon>[A-Z]+)/\k<canon>(?<vol>\d+)/\k<canon>\k<vol>n(?<number>[A-Za-z0-9]+)\.xml$}

  defp entry_from_path(%{"path" => path}) do
    case Regex.named_captures(@path_pattern, path) do
      nil ->
        []

      %{"canon" => canon, "vol" => vol, "number" => number} ->
        [
          %{
            canon: canon,
            volume: String.to_integer(vol),
            number: number,
            work_id: "#{canon}#{number}"
          }
        ]
    end
  end

  defp filter_canon(entries, nil), do: entries
  defp filter_canon(entries, canon), do: Enum.filter(entries, &(&1.canon == canon))

  defp maybe_limit(entries, nil), do: entries
  defp maybe_limit(entries, n), do: Enum.take(entries, n)

  defp wait_for_completion(started, opts) do
    counts = job_counts()
    outstanding = counts.available + counts.executing + counts.scheduled + counts.retryable

    if outstanding == 0 do
      :ok
    else
      unless opts[:quiet] do
        elapsed = div(System.monotonic_time(:millisecond) - started, 1000)

        Mix.shell().info(
          "  [#{elapsed}s] done #{counts.completed} | running #{counts.executing} | " <>
            "queued #{counts.available + counts.scheduled} | failed #{counts.discarded}"
        )
      end

      Process.sleep(5_000)
      wait_for_completion(started, opts)
    end
  end

  defp job_counts do
    rows =
      Repo.all(
        from j in "oban_jobs",
          where: j.queue == "bake",
          group_by: j.state,
          select: {j.state, count(j.id)}
      )
      |> Map.new()

    %{
      available: Map.get(rows, "available", 0),
      executing: Map.get(rows, "executing", 0),
      scheduled: Map.get(rows, "scheduled", 0),
      retryable: Map.get(rows, "retryable", 0),
      completed: Map.get(rows, "completed", 0),
      discarded: Map.get(rows, "discarded", 0)
    }
  end

  defp report(source, canon, started) do
    counts = job_counts()
    elapsed = div(System.monotonic_time(:millisecond) - started, 1000)

    config = %{"source" => source, "canon" => canon, "mode" => "bake_all"}
    {:ok, bake} = Bake.record(config)

    failures =
      Repo.all(
        from j in "oban_jobs",
          where: j.queue == "bake" and j.state == "discarded",
          select: {fragment("?->>'work_id'", j.args), j.errors},
          limit: 10
      )

    Mix.shell().info("""

    bake complete in #{elapsed}s
      works baked:  #{counts.completed}
      failed:       #{counts.discarded}

      bake_id:      #{bake.id}
      pipeline:     v#{bake.pipeline_version}
      corpus:       #{bake.stats["texts"]} text(s), #{bake.stats["segments"]} segments, #{bake.stats["chars"]} chars
    """)

    for {work_id, errors} <- failures do
      Mix.shell().error("  FAILED #{work_id}: #{summarize_error(errors)}")
    end
  end

  defp summarize_error([%{"error" => error} | _]),
    do: error |> to_string() |> String.slice(0, 160)

  defp summarize_error(_), do: "unknown"
end
