defmodule PramanaFoundry.Repair.FR08HandoffGate do
  @moduledoc """
  Executable readiness boundary between FR-07's accepted public store API and FR-08.

  The gate owns no storage and performs no repair. A provider executes one bounded probe
  for each mandatory FR-07 handoff capability against one exact subject revision. Missing
  integration or subject identity is reported as blocked; a malformed or broken provider
  is reported as failed. Only a complete set of passing, revision-bound probes can produce
  a ready result.

  A ready report is handoff evidence, not authority to mark FR-07 complete or to bypass
  its reviewed acceptance requirements. The eventual FR-07 adapter must itself be reviewed
  protected code that executes the documented probes against the accepted public boundary.

  Provider details are deliberately short evidence references rather than raw storage
  contents or exception text. The returned map has bounded values and stable capability
  ordering for machine consumption.
  """

  @schema "pramana-foundry-fr07-fr08-handoff/v1"
  @max_detail_bytes 512
  @max_subject_revision_bytes 128
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

  @callback probe(capability_id(), String.t()) :: probe_result()

  @doc "The ordered mandatory capabilities FR-07 must expose before FR-08 implementation."
  @spec capabilities() :: [%{id: capability_id(), description: String.t()}]
  def capabilities do
    Enum.map(@capabilities, fn {id, description} -> %{id: id, description: description} end)
  end

  @doc "Runs every mandatory probe and returns a deterministic bounded report."
  @spec run(term(), keyword()) :: map()
  def run(provider \\ nil, opts \\ []) do
    {timeout, subject_revision} = options(opts)

    cond do
      is_nil(provider) ->
        report(nil, subject_revision, unavailable_results("provider_unavailable"))

      not is_atom(provider) ->
        report(nil, subject_revision, failed_results("invalid_provider"))

      is_nil(subject_revision) ->
        report(provider, nil, unavailable_results("subject_revision_missing"))

      true ->
        run_provider(provider, subject_revision, timeout)
    end
  end

  @doc "True only for a complete revision-bound report in which every capability passed."
  @spec ready?(map()) :: boolean()
  def ready?(%{
        schema: @schema,
        status: "ready",
        provider: provider,
        subject_revision: subject_revision,
        mandatory_count: mandatory_count,
        passed_count: passed_count,
        failed_count: 0,
        unavailable_count: 0,
        capabilities: capabilities
      })
      when is_binary(provider) and is_list(capabilities) do
    mandatory_count == length(@capabilities) and
      passed_count == mandatory_count and
      valid_subject_revision?(subject_revision) and
      valid_passed_capabilities?(capabilities)
  end

  def ready?(_report), do: false

  defp valid_passed_capabilities?(capabilities) do
    length(capabilities) == length(@capabilities) and
      Enum.zip(capabilities, @capabilities)
      |> Enum.all?(fn
        {%{
           id: actual_id,
           description: actual_description,
           status: "passed",
           evidence: evidence,
           reason: nil
         }, {expected_id, expected_description}} ->
          actual_id == Atom.to_string(expected_id) and
            actual_description == expected_description and
            match?({:ok, _evidence}, bounded_detail(evidence))

        _other ->
          false
      end)
  end

  defp valid_subject_revision?(subject_revision) do
    is_binary(subject_revision) and byte_size(subject_revision) > 0 and
      byte_size(subject_revision) <= @max_subject_revision_bytes
  end

  defp options(opts) do
    opts = Keyword.validate!(opts, [:probe_timeout_ms, :subject_revision])
    timeout = Keyword.get(opts, :probe_timeout_ms, @default_probe_timeout_ms)
    subject_revision = Keyword.get(opts, :subject_revision)

    unless is_integer(timeout) and timeout > 0 and timeout <= @max_probe_timeout_ms do
      raise ArgumentError,
            "probe_timeout_ms must be between 1 and #{@max_probe_timeout_ms}"
    end

    unless is_nil(subject_revision) or valid_subject_revision?(subject_revision) do
      raise ArgumentError,
            "subject_revision must be a non-empty binary up to #{@max_subject_revision_bytes} bytes"
    end

    {timeout, subject_revision}
  end

  defp run_provider(provider, subject_revision, timeout) do
    case Code.ensure_loaded(provider) do
      {:module, ^provider} ->
        if function_exported?(provider, :probe, 2) do
          results =
            Enum.map(
              @capabilities,
              &run_probe(provider, &1, subject_revision, timeout)
            )

          report(provider, subject_revision, results)
        else
          report(
            provider,
            subject_revision,
            unavailable_results("provider_missing_probe_callback")
          )
        end

      {:error, _reason} ->
        report(provider, subject_revision, unavailable_results("provider_not_loadable"))
    end
  end

  defp run_probe(provider, {id, description}, subject_revision, timeout) do
    base = %{id: Atom.to_string(id), description: description}
    normalize_probe(base, execute_probe(provider, id, subject_revision, timeout))
  end

  defp execute_probe(provider, id, subject_revision, timeout) do
    parent = self()
    token = make_ref()

    {pid, monitor_ref} =
      spawn_monitor(fn ->
        result = safe_probe(provider, id, subject_revision)
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

  defp safe_probe(provider, id, subject_revision) do
    provider.probe(id, subject_revision)
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

  defp report(provider, subject_revision, results) do
    failed = Enum.count(results, &(&1.status == "failed"))
    unavailable = Enum.count(results, &(&1.status == "unavailable"))
    passed = Enum.count(results, &(&1.status == "passed"))

    status =
      cond do
        failed > 0 -> "failed"
        unavailable > 0 -> "blocked"
        is_nil(subject_revision) -> "blocked"
        passed == length(@capabilities) -> "ready"
        true -> "failed"
      end

    %{
      schema: @schema,
      status: status,
      provider: provider_name(provider),
      subject_revision: subject_revision,
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
