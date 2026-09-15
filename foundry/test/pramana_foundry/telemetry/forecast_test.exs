defmodule PramanaFoundry.Telemetry.ForecastTest do
  use ExUnit.Case, async: true

  alias PramanaFoundry.Status.TelemetryStatus
  alias PramanaFoundry.Telemetry.{Forecast, Observation, Telemetry}

  test "sparse, censored, blocked, parked, correction, failure, and outlier outcomes stay visible" do
    target = target("T1")

    observations = [
      observation(100, "completed"),
      observation(200, "blocked"),
      observation(300, "parked"),
      observation(400, "failed"),
      observation(10_000, "completed"),
      observation(nil, "running"),
      observation(nil, "correcting"),
      Map.put(observation(50, "completed"), "model", "non-comparable")
    ]

    forecast =
      Forecast.estimate(observations, target,
        now: "2026-09-08T00:00:00Z",
        parallel_resource_limit: 2
      )

    assert forecast["sample_size"] == 5
    assert forecast["right_censored"] == 2
    assert forecast["p50_ms"] == 300
    assert forecast["p80_ms"] == 400
    assert forecast["band"] == "under a minute"
    assert forecast["confidence"] == "medium"
    assert forecast["parallel_resource_limit"] == 2
    assert forecast["serial_integration"]
  end

  test "insufficient comparable evidence yields unavailable rather than false precision" do
    forecast = Forecast.estimate([observation(100, "completed")], target("T1"))
    assert forecast["status"] == "unavailable"
    refute Map.has_key?(forecast, "p50_ms")
    assert forecast["confidence"] == "unavailable"
  end

  test "dependency critical path recalculates deterministically and status exposes unknown denominators" do
    first = target("A")
    second = target("B") |> Map.put("dependencies", ["A"])

    observations = %{
      "A" => [observation(100, "completed"), observation(150, "completed")],
      "B" => [observation(200, "completed"), observation(250, "completed")]
    }

    initial = Forecast.critical_path([first, second], observations)
    changed = Forecast.critical_path([first, Map.put(second, "dependencies", [])], observations)
    assert initial["critical_path"]["tasks"] == ["A", "B"]
    assert initial["critical_path"]["p80_ms"] == 400
    assert changed["critical_path"]["p80_ms"] == 250

    records = [
      telemetry_record(100, "completed", "developer", "implementation", 10),
      telemetry_record(200, "blocked", "reviewer", "review", :null)
    ]

    status = TelemetryStatus.aggregate(records, estimates: %{"T1" => initial})
    assert status["token_availability"] == %{"available" => 1, "unknown" => 9}
    assert status["outcomes"] == %{"blocked" => 1, "completed" => 1}
  end

  test "durable transitions derive censored observations and preserve prediction history" do
    population =
      target("T1")
      |> Map.take(
        ~w(task_id workload risk scope_profile check_profile provider profile model reasoning)
      )

    events = [
      Map.merge(population, %{
        "run_id" => "r1",
        "role" => "developer",
        "phase" => "implementation",
        "event" => "phase_started",
        "at" => "2026-09-08T00:00:00+01:00"
      }),
      Map.merge(population, %{
        "run_id" => "r1",
        "role" => "developer",
        "phase" => "implementation",
        "event" => "phase_blocked",
        "at" => "2026-09-08T00:00:02+01:00"
      }),
      Map.merge(population, %{
        "run_id" => "r2",
        "role" => "developer",
        "phase" => "review",
        "event" => "phase_started",
        "at" => "2026-09-08T00:01:00Z"
      })
    ]

    assert {:ok, [blocked, running]} = Observation.from_events(events)
    assert blocked["duration_ms"] == 2_000
    assert blocked["outcome"] == "blocked"
    refute blocked["right_censored"]
    assert running["outcome"] == "running"
    assert running["right_censored"]

    prior = [%{"predicted_at" => "before", "forecast" => %{"p80_ms" => 9_999}}]
    updated = Forecast.recalculate(prior, [blocked, blocked], target("T1"), now: "after")
    assert hd(updated) == hd(prior)
    assert List.last(updated)["predicted_at"] == "after"
    assert List.last(updated)["forecast"]["p80_ms"] == 2_000
  end

  defp target(task_id) do
    %{
      "task_id" => task_id,
      "dependencies" => [],
      "workload" => "standard",
      "risk" => "workflow_recovery",
      "scope_profile" => "workflow-observability",
      "check_profile" => "workflow-and-python",
      "provider" => "openai",
      "profile" => "sol",
      "model" => "gpt",
      "reasoning" => "medium"
    }
  end

  defp observation(duration, outcome) do
    target("T1")
    |> Map.merge(%{"duration_ms" => duration, "outcome" => outcome})
  end

  defp telemetry_record(duration, outcome, role, phase, output_tokens) do
    started_at = ~U[2026-09-08 00:00:00Z]
    ended_at = DateTime.add(started_at, duration, :millisecond)

    attrs =
      target("T1")
      |> Map.take(
        ~w(task_id workload risk scope_profile check_profile provider profile model reasoning)
      )
      |> Map.merge(%{
        "run_id" => "run-#{duration}",
        "role" => role,
        "phase" => phase,
        "started_at" => DateTime.to_iso8601(started_at),
        "ended_at" => DateTime.to_iso8601(ended_at),
        "duration_ms" => duration,
        "retries" => 0,
        "cooldowns" => 0,
        "outcome" => outcome,
        "provider_metrics" => %{
          "output_tokens" => %{
            "value" => output_tokens,
            "source" => if(output_tokens == :null, do: "unavailable", else: "provider"),
            "quality" => if(output_tokens == :null, do: "unavailable", else: "exact")
          }
        }
      })

    {:ok, record} = Telemetry.llm(attrs)
    record
  end
end
