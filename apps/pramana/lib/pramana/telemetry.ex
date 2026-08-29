defmodule Pramana.Telemetry do
  @moduledoc """
  What happened, when nobody was watching.

  Attached once at boot. It makes a failing Oban job say so, and it defines the events the
  rest of the system emits.

  ## The events, named for the questions they answer

  Emitting costs nothing when nothing is attached, so these are unconditional. What they are
  *called* matters more than what they measure, because a name is what someone greps for at
  two in the morning:

  | event | measurements | why |
  |---|---|---|
  | `[:pramana, :retrieval, :search]` | `duration`, `results` | **which retrievers actually ran** is metadata here. "The semantic arm silently did not run" is a failure this project has already had |
  | `[:pramana, :guard, :check]` | `duration` | the verdict and, on a mismatch, the reason. Refusals are the highest-signal thing the system produces and they were being discarded |
  | `[:pramana, :mcp, :tool]` | `duration` | the surface the whole thesis rests on, and it was entirely unobserved |
  | `[:pramana, :bake, :work]` | `duration`, `segments` | per work, so a slow bake can be attributed rather than guessed at |
  | `[:pramana, :acquire, :fetch]` | `duration`, `bytes` | the one stage that touches the network |

  **`bake_id` rides on every one of them.** A measurement that cannot say which corpus it
  describes is not comparable with the next one, which is the same reason every API response
  carries it.

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
  Emits one domain event, with `bake_id` attached.

  Deliberately a thin wrapper rather than a macro: the call site should read as an ordinary
  function call, because a measurement that is expensive to add does not get added.
  """
  @spec emit([atom()], map(), map()) :: :ok
  def emit(event, measurements, metadata \\ %{}) when is_list(event) and is_map(measurements) do
    :telemetry.execute(event, measurements, Map.put_new_lazy(metadata, :bake_id, &bake_id/0))
  end

  # Never let instrumentation break the thing it instruments. If the bake row cannot be read
  # — no database, a migration in flight — the event still goes out without it.
  defp bake_id do
    Pramana.Bake.current_id()
  rescue
    _ -> nil
  end

  @doc """
  Times `fun`, emits `event`, and returns whatever `fun` returned.

  `describe` is a function of the RESULT returning `{measurements, metadata}`, so a call site
  can report something about the answer — how many results, which retrievers ran — without
  computing it twice and without the event needing to know how to inspect a result.
  """
  @spec span([atom()], (-> result), (result -> {map(), map()})) :: result when result: var
  def span(event, fun, describe \\ fn _ -> {%{}, %{}} end) do
    started = System.monotonic_time()
    result = fun.()
    duration = System.monotonic_time() - started

    {measurements, metadata} = describe.(result)
    emit(event, Map.put(measurements, :duration, duration), metadata)

    result
  end

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
