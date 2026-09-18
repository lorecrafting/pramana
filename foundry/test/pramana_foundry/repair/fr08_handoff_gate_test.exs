defmodule PramanaFoundry.Repair.FR08HandoffGateTest do
  use ExUnit.Case, async: true

  alias PramanaFoundry.Repair.FR08HandoffGate

  defmodule PassingProvider do
    @behaviour FR08HandoffGate

    @impl true
    def probe(id), do: {:pass, "fixture:" <> Atom.to_string(id)}
  end

  defmodule MixedProvider do
    @behaviour FR08HandoffGate

    @impl true
    def probe(:complete_read_set_cas), do: {:unavailable, "fixture:fr07_not_ready"}
    def probe(:protected_field_boundary), do: {:fail, "fixture:forgery_not_rejected"}
    def probe(id), do: {:pass, "fixture:" <> Atom.to_string(id)}
  end

  defmodule MalformedProvider do
    @behaviour FR08HandoffGate

    @impl true
    def probe(_id), do: :ok
  end

  defmodule RaisingProvider do
    @behaviour FR08HandoffGate

    @impl true
    def probe(_id), do: raise("private storage detail")
  end

  defmodule ThrowingProvider do
    @behaviour FR08HandoffGate

    @impl true
    def probe(_id), do: throw(:private_storage_detail)
  end

  defmodule ExitingProvider do
    @behaviour FR08HandoffGate

    @impl true
    def probe(_id), do: exit(:private_storage_detail)
  end

  defmodule OversizedProvider do
    @behaviour FR08HandoffGate

    @impl true
    def probe(_id), do: {:pass, String.duplicate("x", 513)}
  end

  defmodule HangingProvider do
    @behaviour FR08HandoffGate

    @impl true
    def probe(_id) do
      receive do
        :never -> {:pass, "unexpected"}
      end
    end
  end

  defmodule KilledProvider do
    @behaviour FR08HandoffGate

    @impl true
    def probe(_id), do: Process.exit(self(), :kill)
  end

  defmodule MissingCallbackProvider do
  end

  test "all mandatory passing probes are required for readiness" do
    report = FR08HandoffGate.run(PassingProvider)

    assert report.status == "ready"
    assert FR08HandoffGate.ready?(report)
    assert report.mandatory_count == 7
    assert report.passed_count == 7
    assert report.failed_count == 0
    assert report.unavailable_count == 0

    assert Enum.map(report.capabilities, & &1.id) ==
             Enum.map(FR08HandoffGate.capabilities(), &Atom.to_string(&1.id))

    assert Enum.all?(report.capabilities, &(&1.status == "passed"))
  end

  test "the current missing integration is blocked rather than silently ready" do
    report = FR08HandoffGate.run()

    assert report.status == "blocked"
    refute FR08HandoffGate.ready?(report)
    assert report.passed_count == 0
    assert report.failed_count == 0
    assert report.unavailable_count == report.mandatory_count
    assert Enum.all?(report.capabilities, &(&1.reason == "provider_unavailable"))
  end

  test "a missing provider callback is unavailable, not a false pass" do
    report = FR08HandoffGate.run(MissingCallbackProvider)

    assert report.status == "blocked"
    assert report.failed_count == 0
    assert report.unavailable_count == report.mandatory_count

    assert Enum.all?(
             report.capabilities,
             &(&1.reason == "provider_missing_probe_callback")
           )
  end

  test "a concrete failure outranks unavailable capabilities" do
    report = FR08HandoffGate.run(MixedProvider)

    assert report.status == "failed"
    assert report.failed_count == 1
    assert report.unavailable_count == 1
    assert report.passed_count == 5

    assert Enum.find(report.capabilities, &(&1.id == "protected_field_boundary")).status ==
             "failed"

    assert Enum.find(report.capabilities, &(&1.id == "complete_read_set_cas")).status ==
             "unavailable"
  end

  test "malformed or oversized probe results fail closed" do
    for provider <- [MalformedProvider, OversizedProvider] do
      report = FR08HandoffGate.run(provider)
      assert report.status == "failed"
      assert report.failed_count == report.mandatory_count
      assert Enum.all?(report.capabilities, &(&1.reason == "invalid_probe_result"))
    end
  end

  test "probe exceptions, throws and exits fail without leaking provider detail" do
    for {provider, reason} <- [
          {RaisingProvider, "probe_exception"},
          {ThrowingProvider, "probe_throw"},
          {ExitingProvider, "probe_exit"}
        ] do
      report = FR08HandoffGate.run(provider)

      assert report.status == "failed"
      assert report.failed_count == report.mandatory_count
      assert Enum.all?(report.capabilities, &(&1.reason == reason))
      refute inspect(report) =~ "private storage detail"
      refute inspect(report) =~ "private_storage_detail"
    end
  end


  test "hung probes are killed and reported as failures" do
    report = FR08HandoffGate.run(HangingProvider, probe_timeout_ms: 20)

    assert report.status == "failed"
    assert report.failed_count == report.mandatory_count
    assert Enum.all?(report.capabilities, &(&1.reason == "probe_timeout"))
  end

  test "untrappable provider death fails without leaking its exit reason" do
    report = FR08HandoffGate.run(KilledProvider, probe_timeout_ms: 100)

    assert report.status == "failed"
    assert report.failed_count == report.mandatory_count
    assert Enum.all?(report.capabilities, &(&1.reason == "probe_process_exit"))
  end

  test "probe timeout configuration is finite and validated" do
    for invalid <- [0, -1, 60_001, :infinity, "100"] do
      assert_raise ArgumentError, fn ->
        FR08HandoffGate.run(PassingProvider, probe_timeout_ms: invalid)
      end
    end

    assert_raise ArgumentError, fn ->
      FR08HandoffGate.run(PassingProvider, timeout_ms: 100)
    end
  end

  test "invalid explicit provider input fails closed" do
    report = FR08HandoffGate.run("not-a-module")

    assert report.status == "failed"
    assert report.provider == nil
    assert report.failed_count == report.mandatory_count
    assert Enum.all?(report.capabilities, &(&1.reason == "invalid_provider"))
  end

  test "reports are deterministic for the same pure provider" do
    assert FR08HandoffGate.run(PassingProvider) == FR08HandoffGate.run(PassingProvider)
  end
end
