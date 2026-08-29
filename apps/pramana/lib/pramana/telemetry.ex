defmodule Pramana.Telemetry do
  @moduledoc """
  What happened, when nobody was watching.

  Attached once at boot. Today it does one thing — **it makes a failing Oban job say so** —
  and it is the place the rest of `docs/OBSERVABILITY.md` will hang from.

  ## Why this exists, concretely

  41 of 53 bake jobs failed deterministically, and the diagnosis was **adding a print
  statement inside `perform`**, because nothing else could see inside a job. The cause was a
  stale `mix phx.server` from the previous day draining the same queue with yesterday's
  build. No log would have had to be clever to catch that; any record of a job failing, with
  its args, would have done it.

  What made it expensive was not the bug. It was that a job could fail 41 times in silence:
  Oban records the error on the row, `Oban.Plugins.Pruner` discards the row after 24 hours,
  and an overnight bake therefore loses its own failures before anyone reads them.

  ## What it deliberately does not do

  **It does not retry, discard, or otherwise change what happens.** Oban owns that policy
  and a telemetry handler that alters behaviour is a control path hiding in an observation
  path. This reports and returns.

  And it does not log successes. A bake is tens of thousands of jobs; a line each would bury
  the one line that matters, which is the failure mode `integrity` had while it reported
  1,228 X texts as broken.
  """

  require Logger

  @events [
    [:oban, :job, :exception]
  ]

  @doc """
  Attaches every handler. Idempotent: re-attaching is a no-op rather than an error, because
  a release that restarts the application must not crash on the second boot.
  """
  @spec attach() :: :ok
  def attach do
    :telemetry.detach(__MODULE__)
    :telemetry.attach_many(__MODULE__, @events, &__MODULE__.handle/4, %{})
  end

  @doc false
  def handle([:oban, :job, :exception], measurements, metadata, _config) do
    job = metadata[:job] || %{}

    Logger.error("""
    oban job failed: #{inspect(metadata[:worker] || job.worker)}
      args:     #{inspect(Map.get(job, :args), limit: 10)}
      attempt:  #{Map.get(job, :attempt)} of #{Map.get(job, :max_attempts)}
      queue:    #{Map.get(job, :queue)}
      after:    #{div(measurements[:duration] || 0, 1_000_000)}ms
      reason:   #{inspect(metadata[:reason], limit: 5)}
      node:     #{node()}
    """)
  end

  # An unmatched event is not an error: `@events` and this function must be allowed to drift
  # for one commit while a handler is being added.
  def handle(_event, _measurements, _metadata, _config), do: :ok
end
