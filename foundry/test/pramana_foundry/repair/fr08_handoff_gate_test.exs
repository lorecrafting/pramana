defmodule PramanaFoundry.Repair.FR08HandoffGateTest do
  use ExUnit.Case, async: true

  alias PramanaFoundry.Repair.FR08HandoffGate

  @subject_revision "fr07-fixture-revision-1"

  defmodule PassingProvider do
    @behaviour FR08HandoffGate

    @impl true
    def probe(id, revision), do: {:pass, "fixture:#{revision}:#{id}"}
  end

  defmodule MixedProvider do
    @behaviour FR08HandoffGate

    @impl true
    def probe(:complete_read_set_cas, _revision), do: {:unavailable, "fixture:fr07_not_ready"}

    def probe(:protected_field_boundary, _revision),
      do: {:fail, "fixture:forgery_not_rejected"}

    def probe(id, revision), do: {:pass, "fixture:#{revision}:#{id}"}
  end

  defmodule MalformedProvider do
    @behaviour FR08HandoffGate

    @impl true
    def probe(_id, _revision), do: :ok
  end

  defmodule RaisingProvider do
    @behaviour FR08HandoffGate

    @impl true
    def probe(_id, _revision), do: raise("private storage detail")
  end

  defmodule ThrowingProvider do
    @behaviour FR08HandoffGate

    @impl true
    def probe(_id, _revision), do: throw(:private_storage_detail)
  end

  defmodule ExitingProvider do
    @behaviour FR08HandoffGate

    @impl true
    def probe(_id, _revision), do: exit(:private_storage_detail)
  end

  defmodule OversizedProvider do
    @behaviour FR08HandoffGate

    @impl true
    def probe(_id, _revision), do: {:pass, String.duplicate("x", 513)}
  end

  defmodule HangingProvider do
    @behaviour FR08HandoffGate

    @impl true
    def probe(_id, _revision) do
      receive do
        :never -> {:pass, "unexpected"}
      end
    end
  end

  defmodule KilledProvider do
    @behaviour FR08HandoffGate

    @impl true
    def probe(_id, _revision), do: Process.exit(self(), :kill)
  end

  defmodule MustNotRunWithoutRevisionProvider do
    @behaviour FR08HandoffGate

    @impl true
    def probe(_id, _revision), do: raise("probe must not run without subject revision")
  end

  defmodule MissingCallbackProvider do
  end

  test "all mandatory passing probes are revision-bound before readiness" do
    report =
      FR08HandoffGate.run(PassingProvider,
        subject_revision: @subject_revision
      )

    assert report.status == "ready"
    assert FR08HandoffGate.ready?(report)
    assert report.subject_revision == @subject_revision
    assert report.mandatory_count == 7
    assert report.passed_count == 7
    assert report.failed_count == 0
    assert report.unavailable_count == 0

    assert Enum.map(report.capabilities, & &1.id) ==
             Enum.map(FR08HandoffGate.capabilities(), &Atom.to_string(&1.id))

    assert Enum.all?(report.capabilities, &(&1.status == "passed"))
    assert Enum.all?(report.capabilities, &String.contains?(&1.evidence, @subject_revision))
  end

  test "the current missing integration is blocked rather than silently ready" do
    report = FR08HandoffGate.run()

    assert report.status == "blocked"
    refute FR08HandoffGate.ready?(report)
    assert report.subject_revision == nil
    assert report.passed_count == 0
    assert report.failed_count == 0
    assert report.unavailable_count == report.mandatory_count
    assert Enum.all?(report.capabilities, &(&1.reason == "provider_unavailable"))
  end

  test "a provider cannot run or become ready without an exact subject revision" do
    report = FR08HandoffGate.run(MustNotRunWithoutRevisionProvider)

    assert report.status == "blocked"
    refute FR08HandoffGate.ready?(report)
    assert report.subject_revision == nil
    assert report.failed_count == 0
    assert report.unavailable_count == report.mandatory_count
    assert Enum.all?(report.capabilities, &(&1.reason == "subject_revision_missing"))
  end

  test "a missing provider callback is unavailable, not a false pass" do
    report =
      FR08HandoffGate.run(MissingCallbackProvider,
        subject_revision: @subject_revision
      )

    assert report.status == "blocked"
    assert report.subject_revision == @subject_revision
    assert report.failed_count == 0
    assert report.unavailable_count == report.mandatory_count

    assert Enum.all?(
             report.capabilities,
             &(&1.reason == "provider_missing_probe_callback")
           )
  end

  test "a concrete failure outranks unavailable capabilities" do
    report =
      FR08HandoffGate.run(MixedProvider,
        subject_revision: @subject_revision
      )

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
      report =
        FR08HandoffGate.run(provider,
          subject_revision: @subject_revision
        )

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
      report =
        FR08HandoffGate.run(provider,
          subject_revision: @subject_revision
        )

      assert report.status == "failed"
      assert report.failed_count == report.mandatory_count
      assert Enum.all?(report.capabilities, &(&1.reason == reason))
      refute inspect(report) =~ "private storage detail"
      refute inspect(report) =~ "private_storage_detail"
    end
  end

  test "hung probes are killed and reported as failures" do
    report =
      FR08HandoffGate.run(HangingProvider,
        subject_revision: @subject_revision,
        probe_timeout_ms: 20
      )

    assert report.status == "failed"
    assert report.failed_count == report.mandatory_count
    assert Enum.all?(report.capabilities, &(&1.reason == "probe_timeout"))
  end

  test "untrappable provider death fails without leaking its exit reason" do
    report =
      FR08HandoffGate.run(KilledProvider,
        subject_revision: @subject_revision,
        probe_timeout_ms: 100
      )

    assert report.status == "failed"
    assert report.failed_count == report.mandatory_count
    assert Enum.all?(report.capabilities, &(&1.reason == "probe_process_exit"))
  end

  test "probe timeout and subject identity configuration are validated" do
    for invalid <- [0, -1, 60_001, :infinity, "100"] do
      assert_raise ArgumentError, fn ->
        FR08HandoffGate.run(PassingProvider,
          subject_revision: @subject_revision,
          probe_timeout_ms: invalid
        )
      end
    end

    for invalid <- ["", String.duplicate("x", 129), 123, :revision] do
      assert_raise ArgumentError, fn ->
        FR08HandoffGate.run(PassingProvider,
          subject_revision: invalid
        )
      end
    end

    assert_raise ArgumentError, fn ->
      FR08HandoffGate.run(PassingProvider,
        subject_revision: @subject_revision,
        timeout_ms: 100
      )
    end
  end

  test "invalid explicit provider input fails closed" do
    report =
      FR08HandoffGate.run("not-a-module",
        subject_revision: @subject_revision
      )

    assert report.status == "failed"
    assert report.provider == nil
    assert report.subject_revision == @subject_revision
    assert report.failed_count == report.mandatory_count
    assert Enum.all?(report.capabilities, &(&1.reason == "invalid_provider"))
  end

  test "ready predicate rejects incomplete or tampered reports" do
    report =
      FR08HandoffGate.run(PassingProvider,
        subject_revision: @subject_revision
      )

    refute FR08HandoffGate.ready?(%{
             schema: report.schema,
             status: "ready",
             subject_revision: @subject_revision
           })

    refute FR08HandoffGate.ready?(%{report | passed_count: report.passed_count - 1})

    [first | rest] = report.capabilities
    tampered = [%{first | status: "failed", reason: "tampered", evidence: nil} | rest]
    refute FR08HandoffGate.ready?(%{report | capabilities: tampered})
  end

  test "reports are deterministic for the same pure provider and revision" do
    first =
      FR08HandoffGate.run(PassingProvider,
        subject_revision: @subject_revision
      )

    second =
      FR08HandoffGate.run(PassingProvider,
        subject_revision: @subject_revision
      )

    assert first == second
  end
end
