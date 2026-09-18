defmodule PramanaFoundry.Repair.FR08HandoffGate do
  @moduledoc """
  Executable readiness boundary between FR-07's accepted public store API and FR-08.

  The gate owns no storage and performs no repair. A provider executes one bounded probe
  for each mandatory FR-07 handoff capability. Missing integration is reported as blocked;
  a malformed or broken provider is reported as failed. Only a complete set of passing
  probes can produce a ready result.

  A ready report is handoff evidence, not authority to mark FR-07 complete or to bypass
  its reviewed acceptance requirements. The eventual FR-07 adapter must itself be reviewed
  protected code that executes the documented probes against the accepted public boundary.

  Provider details are deliberately short evidence references rather than raw storage
  contents or exception text. The returned map has bounded values and stable capability
  ordering for machine consumption.
  """

  @schema "pramana-foundry-fr07-fr08-handoff/v1"
  @max_detail_bytes 512
  @default_probe_timeout_ms 5_000
  @max_probe_timeout_ms 60_000

  @capabilities [
    {:same_command_lookup_before_revision,
     "same actor/command identity lookup occurs before current-revision rejection"},
    {:complete_read_set_cas,
     "complete entity, policy, control and allocation read-set CAS includes absent values"},
    {:atomic_authority_commit,
     "command result, events, projections, effects, claims, receipts, leases and ledgers commit atomically"},
    {:revision_and_inbox_facts,
     "indexed revisions and authenticated inbox sequence/seal facts are available"},
    {:protected_field_boundary,
     "kernel-originated domain changes cannot forge protected claims, balances, refs or receipts"},
    {:fail_closed_recovery,
     "storage/recovery errors are explicit and no external effect is issued before checked commit"},
    {:immutable_legacy_import,
     "legacy import preserves originals and reports unsupported or invalid records explicitly"}
  ]

  @type capability_id ::
          :same_command_lookup_before_revision
          | :complete_read_set_cas
          | :atomic_authority_commit
          | :revision_and_inbox_facts
          | :protected_field_boundary
          | :fail_closed_recovery
          | :immutable_legacy_import

  @type probe_result ::
          {:pass, String.t()} | {:fail, String.t()} | {:unavailable, String.t()}

  @callback probe(capability_id()) :: probe_result()

  @doc "The ordered mandatory capabilities FR-07 must expose before FR-08 implementation."
  @spec capabilities() :: [%{id: capability_id(), description: String.t()}]
  def capabilities do
    Enum.map(@capabilities, fn {id, description} -> %{id: id, description: description} end)
  end

  @doc "Runs every mandatory probe and returns a deterministic bounded report."
  @spec run(module() | nil | term(), keyword()) :: map()
  def run(provider \\ nil, opts \\ [])

  def run(nil, opts) do
    _timeout = probe_timeout_ms(opts)
    report(nil, unavailable_results("provider_unavailable"))
  end

  def run(provider, opts) when is_atom(provider) do
    timeout = probe_timeout_ms(opts)

    case Code.ensure_loaded(provider) do
      {:module, ^provider} ->
        if function_exported?(provider, :probe, 1) do
          report(provider, Enum.map(@capabilities, &run_probe(provider, &1, timeout)))
        else
          report(provider, unavailable_results("provider_missing_probe_callback"))
        end

      {:error, _reason} ->
        report(provider, unavailable_results("provider_not_loadable"))
    end
  end

  def run(_provider, opts) do
    _timeout = probe_timeout_ms(opts)
    report(nil, failed_results("invalid_provider"))
  end

  @doc "True only for a report in which every mandatory capability passed."
  @spec ready?(map()) :: boolean()
  def ready?(%{schema: @schema, status: "ready"}), do: true
  def ready?(_report), do: false

  defp probe_timeout_ms(opts) do
    opts = Keyword.validate!(opts, [:probe_timeout_ms])
    timeout = Keyword.get(opts, :probe_timeout_ms, @default_probe_timeout_ms)

    unless is_integer(timeout) and timeout > 0 and timeout <= @max_probe_timeout_ms do
      raise ArgumentError,
            "probe_timeout_ms must be between 1 and #{@max_probe_timeout_ms}"
    end

    timeout
  end

  defp run_probe(provider, {id, description}, timeout) do
    base = %{id: Atom.to_string(id), description: description}
    normalize_probe(base, execute_probe(provider, id, timeout))
  end

  defp execute_probe(provider, id, timeout) do
    parent = self()
    token = make_ref()

    {pid, monitor_ref} =
      spawn_monitor(fn ->
        result = safe_probe(provider, id)
        send(parent, {token, result})
      end)

    receive do
      {^token, result} ->
        await_probe_exit(pid, monitor_ref, timeout)
        result

      {:DOWN, ^monitor_ref, :process, ^pid, _reason} ->
        {:internal_failure, "probe_process_exit"}
    after
      timeout ->
        stop_probe(pid, monitor_ref, token)
        {:internal_failure, "probe_timeout"}
    end
  end

  defp safe_probe(provider, id) do
    provider.probe(id)
  rescue
    _error -> {:internal_failure, "probe_exception"}
  catch
    :throw, _reason -> {:internal_failure, "probe_throw"}
    :exit, _reason -> {:internal_failure, "probe_exit"}
  end

  defp await_probe_exit(pid, monitor_ref, timeout) do
    receive do
      {:DOWN, ^monitor_ref, :process, ^pid, _reason} ->
        :ok
    after
      timeout ->
        Process.exit(pid, :kill)
        await_killed_probe(pid, monitor_ref)
    end
  end

  defp stop_probe(pid, monitor_ref, token) do
    Process.exit(pid, :kill)
    await_killed_probe(pid, monitor_ref)

    receive do
      {^token, _late_result} -> :ok
    after
      0 -> :ok
    end
  end

  defp await_killed_probe(pid, monitor_ref) do
    receive do
      {:DOWN, ^monitor_ref, :process, ^pid, _reason} -> :ok
    after
      1_000 -> Process.demonitor(monitor_ref, [:flush])
    end
  end

  defp normalize_probe(base, {:pass, detail}) do
    case bounded_detail(detail) do
      {:ok, evidence} -> Map.merge(base, %{status: "passed", evidence: evidence, reason: nil})
      :error -> invalid_probe(base)
    end
  end

  defp normalize_probe(base, {:fail, detail}) do
    case bounded_detail(detail) do
      {:ok, reason} -> Map.merge(base, %{status: "failed", evidence: nil, reason: reason})
      :error -> invalid_probe(base)
    end
  end

  defp normalize_probe(base, {:unavailable, detail}) do
    case bounded_detail(detail) do
      {:ok, reason} -> Map.merge(base, %{status: "unavailable", evidence: nil, reason: reason})
      :error -> invalid_probe(base)
    end
  end

  defp normalize_probe(base, {:internal_failure, reason}),
    do: Map.merge(base, %{status: "failed", evidence: nil, reason: reason})

  defp normalize_probe(base, _result), do: invalid_probe(base)

  defp invalid_probe(base),
    do: Map.merge(base, %{status: "failed", evidence: nil, reason: "invalid_probe_result"})

  defp bounded_detail(detail)
       when is_binary(detail) and byte_size(detail) > 0 and byte_size(detail) <= @max_detail_bytes,
       do: {:ok, detail}

  defp bounded_detail(_detail), do: :error

  defp unavailable_results(reason) do
    Enum.map(@capabilities, fn {id, description} ->
      %{
        id: Atom.to_string(id),
        description: description,
        status: "unavailable",
        evidence: nil,
        reason: reason
      }
    end)
  end

  defp failed_results(reason) do
    Enum.map(@capabilities, fn {id, description} ->
      %{
        id: Atom.to_string(id),
        description: description,
        status: "failed",
        evidence: nil,
        reason: reason
      }
    end)
  end

  defp report(provider, results) do
    failed = Enum.count(results, &(&1.status == "failed"))
    unavailable = Enum.count(results, &(&1.status == "unavailable"))
    passed = Enum.count(results, &(&1.status == "passed"))

    status =
      cond do
        failed > 0 -> "failed"
        unavailable > 0 -> "blocked"
        passed == length(@capabilities) -> "ready"
        true -> "failed"
      end

    %{
      schema: @schema,
      status: status,
      provider: provider_name(provider),
      mandatory_count: length(@capabilities),
      passed_count: passed,
      failed_count: failed,
      unavailable_count: unavailable,
      capabilities: results
    }
  end

  defp provider_name(nil), do: nil
  defp provider_name(provider) when is_atom(provider), do: Atom.to_string(provider)
end
