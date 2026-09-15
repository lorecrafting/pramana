defmodule PramanaWeb.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      # Telemetry poller will execute the given period measurements
      # every 10_000ms. Learn more here: https://hexdocs.pm/telemetry_metrics
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
      # Add reporters as children of your supervision tree.
      # {Telemetry.Metrics.ConsoleReporter, metrics: metrics()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # Phoenix Metrics
      summary("phoenix.endpoint.start.system_time",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.start.system_time",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.exception.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.socket_connected.duration",
        unit: {:native, :millisecond}
      ),
      sum("phoenix.socket_drain.count"),
      summary("phoenix.channel_joined.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.channel_handled_in.duration",
        tags: [:event],
        unit: {:native, :millisecond}
      ),

      # Database Metrics
      summary("pramana.repo.query.total_time",
        unit: {:native, :millisecond},
        description: "The sum of the other measurements"
      ),
      summary("pramana.repo.query.decode_time",
        unit: {:native, :millisecond},
        description: "The time spent decoding the data received from the database"
      ),
      summary("pramana.repo.query.query_time",
        unit: {:native, :millisecond},
        description: "The time spent executing the query"
      ),
      summary("pramana.repo.query.queue_time",
        unit: {:native, :millisecond},
        description: "The time spent waiting for a database connection"
      ),
      summary("pramana.repo.query.idle_time",
        unit: {:native, :millisecond},
        description:
          "The time the connection spent waiting before being checked out for the query"
      ),

      # VM Metrics
      # THIS PROJECT'S OWN EVENTS. Everything above is generated Phoenix scaffolding, which
      # is why `docs/OBSERVABILITY.md` could say the running system was unobserved while a
      # metrics module existed. See `Pramana.Telemetry` for what each event answers.
      summary("pramana.retrieval.search.duration",
        event_name: "pramana.retrieval.search",
        unit: {:native, :millisecond},
        tags: [:mode, :outcome],
        description: "Retrieval, by mode — and `retrievers` says which arms actually ran"
      ),
      summary("pramana.retrieval.search.results",
        event_name: "pramana.retrieval.search",
        measurement: :results,
        description: "Results returned, zero included"
      ),
      summary("pramana.guard.check.duration",
        event_name: "pramana.guard.check",
        unit: {:native, :millisecond},
        tags: [:verdict],
        description: "Citation checks by verdict — refusals are the signal"
      ),
      # THE TWO SIGNALS THAT WERE COMPUTED AND DISCARDED — docs/PLAN.md § A6, items 1 and 3.
      #
      # Counters rather than a stored log, deliberately. Persisting refusals or queries is a
      # decision about privacy and retention before it is a feature: a scholar's queries
      # reveal unpublished research direction. § A6 says the retention policy comes before
      # the first row, and these answer most of the question without one.
      counter("pramana.guard.check.duration",
        event_name: "pramana.guard.check",
        measurement: :duration,
        tags: [:verdict],
        description: "Citation refusals by verdict — a rising rate is a corpus problem"
      ),
      counter("pramana.coverage.caveat.fired",
        event_name: "pramana.coverage.caveat",
        measurement: :fired,
        tags: [:kinds],
        description: "Which gap callers keep hitting — a prioritised acquisition list"
      ),
      counter("pramana.mcp.tool.calls",
        event_name: "pramana.mcp.tool",
        measurement: :calls,
        tags: [:tool],
        description: "Which tools a model actually reaches for"
      ),
      summary("pramana.bake.work.duration",
        event_name: "pramana.bake.work",
        unit: {:native, :millisecond},
        tags: [:outcome],
        description: "Per work, so a slow bake can be attributed"
      ),
      summary("pramana.acquire.fetch.bytes",
        event_name: "pramana.acquire.fetch",
        tags: [:source, :outcome],
        description: "Bytes fetched — what distinguishes a slow link from a truncated one"
      ),
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io")
    ]
  end

  defp periodic_measurements do
    [
      # A module, function and arguments to be invoked periodically.
      # This function must call :telemetry.execute/3 and a metric must be added above.
      # {PramanaWeb, :count_users, []}
    ]
  end
end
