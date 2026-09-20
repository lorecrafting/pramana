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

  describe "domain events" do
    setup do
      ref = make_ref()
      parent = self()

      events = [
        [:pramana, :retrieval, :search],
        [:pramana, :guard, :check],
        [:pramana, :mcp, :tool],
        [:pramana, :bake, :work],
        [:pramana, :acquire, :fetch]
      ]

      :telemetry.attach_many(
        ref,
        events,
        fn event, measurements, metadata, _ ->
          send(parent, {:event, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(ref) end)
      :ok
    end

    test "emit/3 attaches the bake_id, because a measurement must name its corpus" do
      Telemetry.emit([:pramana, :mcp, :tool], %{calls: 1}, %{tool: "search"})

      assert_receive {:event, [:pramana, :mcp, :tool], %{calls: 1}, metadata}
      assert Map.has_key?(metadata, :bake_id)
      assert metadata.tool == "search"
    end

    test "an explicit bake_id is not overwritten" do
      # A caller replaying an older corpus is reporting about THAT bake, not this one.
      Telemetry.emit([:pramana, :guard, :check], %{}, %{bake_id: "older"})

      assert_receive {:event, _, _, %{bake_id: "older"}}
    end

    test "span/3 times the work, returns the result untouched, and describes it" do
      result =
        Telemetry.span(
          [:pramana, :retrieval, :search],
          fn -> {:ok, %{results: [1, 2, 3], mode: "hybrid", retrievers: ["lexical"]}} end,
          fn {:ok, found} -> {%{results: length(found.results)}, %{mode: found.mode}} end
        )

      assert {:ok, %{results: [1, 2, 3]}} = result

      assert_receive {:event, [:pramana, :retrieval, :search], measurements, metadata}
      assert measurements.results == 3
      assert measurements.duration > 0
      assert metadata.mode == "hybrid"
    end

    test "instrumentation never breaks the thing it instruments" do
      # This case is an EXIT, not an exception. Reading the bake row without a database
      # checkout dies in `DBConnection.Holder.checkout` with `:no_process`, and an exit walks
      # straight past `rescue` into the caller — so a `rescue`-only version killed the
      # retrieval it was measuring. It flaked one run in three before it was caught.
      #
      # This test module is deliberately `ExUnit.Case` rather than `DataCase`: with no
      # ownership there is no connection, which is the condition being tested.
      assert :ok = Telemetry.emit([:pramana, :acquire, :fetch], %{bytes: 0})
      assert_receive {:event, [:pramana, :acquire, :fetch], _, metadata}
      # It goes out WITHOUT the id rather than not going out.
      assert metadata.bake_id == nil
    end
  end

  test "successes are not logged" do
    # A bake is tens of thousands of jobs. A line each buries the one line that matters.
    log = capture_log(fn -> :telemetry.execute([:oban, :job, :stop], %{duration: 1}, %{}) end)

    refute log =~ "oban job"
  end
end
