defmodule Pramana.TelemetryTest do
  @moduledoc """
  A failing job must say so.

  41 of 53 bake jobs once failed deterministically and the diagnosis was a print statement
  inside `perform`, because nothing could see inside a job. These tests pin the three things
  that made that expensive: that a failure is reported at all, that the report names the
  args and the node, and that the handler does not touch what happens next.
  """
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Pramana.Telemetry

  setup do
    Telemetry.attach()
    on_exit(fn -> :telemetry.detach(Pramana.Telemetry) end)
    :ok
  end

  defp emit(job, reason) do
    :telemetry.execute(
      [:oban, :job, :exception],
      %{duration: 1_500_000_000},
      %{job: job, reason: reason, worker: job.worker}
    )
  end

  test "a failed job is logged with everything needed to find it again" do
    job = %{
      worker: "Pramana.Bake.Worker",
      args: %{"work_id" => "T0262", "source" => "cbeta"},
      attempt: 3,
      max_attempts: 3,
      queue: :bake
    }

    log = capture_log(fn -> emit(job, %RuntimeError{message: "boom"}) end)

    assert log =~ "oban job failed"
    assert log =~ "Pramana.Bake.Worker"
    # The ARGS, because "a job failed" without them is a fact nobody can act on.
    assert log =~ "T0262"
    assert log =~ "3 of 3"
    assert log =~ "1500ms"
    # The NODE. The stall that motivated this was a second VM draining the same queue with
    # yesterday's build; nothing else in the record would have distinguished them.
    assert log =~ to_string(node())
    assert log =~ "boom"
  end

  test "attaching twice does not raise" do
    # A release that restarts the application must not crash on the second boot.
    assert :ok = Telemetry.attach()
    assert :ok = Telemetry.attach()
  end

  test "an unknown event is ignored rather than raising" do
    # `@events` and the handler are allowed to drift for one commit while a handler is being
    # added; a crash in a telemetry handler detaches it silently and takes the rest with it.
    assert :ok = Telemetry.handle([:something, :else], %{}, %{}, %{})
  end

  test "successes are not logged" do
    # A bake is tens of thousands of jobs. A line each buries the one line that matters.
    log = capture_log(fn -> :telemetry.execute([:oban, :job, :stop], %{duration: 1}, %{}) end)

    refute log =~ "oban job"
  end
end
