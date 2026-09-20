defmodule PramanaFoundry.CI.FR19ASyncFaultParse do
  @moduledoc false

  def main([trace_prefix, destination, fixture_log, phase_log, mapper_log, output]) do
    destination = Path.expand(destination)
    traces = trace_prefix |> Path.wildcard() |> Enum.sort()
    events = trace_events(traces)
    fixture = File.read!(fixture_log)
    phase = File.read!(phase_log)
    mapper = File.read!(mapper_log)

    with {:ok, typed_errno} <- typed_errno(fixture),
         {:ok, sync} <- exact_sync_failure(events, destination, typed_errno),
         {:ok, open} <- matching_open(events, destination, sync),
         {:ok, load_time} <- phase_time(phase, "load"),
         {:ok, resume_time} <- phase_time(phase, "resume"),
         {:ok, assert_time} <- phase_time(phase, "semantic-assert"),
         true <- open.time < load_time,
         true <- resume_time <= assert_time and assert_time < sync.time,
         true <- controlled_mapping?(phase, mapper, typed_errno),
         true <- fixture_complete?(fixture) do
      body = [
        "schema=pramana-foundry-fr19a-kernel-sync-fault-proof/v2",
        "destination=#{destination}",
        "errno=#{typed_errno}",
        "descriptor=#{sync.fd}",
        "open_timestamp=#{open.timestamp}",
        "load_timestamp=#{format_time(load_time)}",
        "resume_timestamp=#{format_time(resume_time)}",
        "assert_timestamp=#{format_time(assert_time)}",
        "sync_timestamp=#{sync.timestamp}",
        "controlled_error_table=true",
        "ext4_emergency_ro=#{typed_errno == "erofs"}",
        "filesystem_recovery_claimed=false",
        "gateway_storage_failure=#{typed_errno}",
        "result=pass",
        "",
        "#{sync.trace}: #{sync.line}"
      ]

      File.write!(output, Enum.join(body, "\n") <> "\n")
      0
    else
      reason ->
        File.write!(
          output,
          "schema=pramana-foundry-fr19a-kernel-sync-fault-proof/v2\nresult=fail\n" <>
            "destination=#{destination}\nreason=#{inspect(reason)}\n"
        )

        2
    end
  end

  def main(_args), do: 64

  defp trace_events(traces) do
    for trace <- traces,
        line <- File.stream!(trace, :line, []),
        event = parse_trace_line(trace, line),
        event != nil do
      event
    end
  end

  defp parse_trace_line(trace, line) do
    case Regex.run(~r/^(\d+\.\d+)\s+(.*)$/, line) do
      [_, timestamp, syscall] ->
        %{
          trace: trace,
          timestamp: timestamp,
          time: String.to_float(timestamp),
          line: String.trim(line),
          syscall: syscall
        }

      _other ->
        nil
    end
  end

  defp typed_errno(fixture) do
    case Regex.run(~r/^GATEWAY_STORAGE_FAILURE=(eio|erofs)$/m, fixture) do
      [_, errno] -> {:ok, errno}
      _other -> {:error, :missing_typed_gateway_failure}
    end
  end

  defp exact_sync_failure(events, destination, errno) do
    escaped = Regex.escape(destination)
    expected = String.upcase(errno)
    pattern = ~r/^(?:fsync|fdatasync)\((\d+)<#{escaped}>\)\s+=\s+-1 #{expected}\b/

    matches =
      for event <- events,
          [_, fd] <- [Regex.run(pattern, event.syscall)] do
        Map.put(event, :fd, fd)
      end

    case matches do
      [match] -> {:ok, match}
      [] -> {:error, :missing_exact_path_sync_failure}
      _many -> {:error, :multiple_exact_path_sync_failures}
    end
  end

  defp matching_open(events, destination, sync) do
    quoted_destination = inspect(destination)
    result = "= #{sync.fd}<#{destination}>"

    matches =
      Enum.filter(events, fn event ->
        event.time < sync.time and String.starts_with?(event.syscall, "openat(") and
          String.contains?(event.syscall, quoted_destination) and
          String.contains?(event.syscall, result)
      end)

    case List.last(matches) do
      nil -> {:error, :missing_matching_pre_fault_open}
      match -> {:ok, match}
    end
  end

  defp phase_time(phase, name) do
    pattern = ~r/^epoch_ns=(\d+) phase=#{Regex.escape(name)} status=0$/m

    case Regex.run(pattern, phase) do
      [_, epoch_ns] -> {:ok, String.to_integer(epoch_ns) / 1_000_000_000}
      _other -> {:error, {:missing_successful_phase, name}}
    end
  end

  defp controlled_mapping?(phase, mapper, errno) do
    semantic_table =
      phase =~ "phase=semantic-assert status=0" and
        Regex.match?(~r/observed_table_begin\n0\s+\d+\s+error\s*\nobserved_table_end/, phase)

    live_error = Regex.match?(~r/phase=error\n0\s+\d+\s+error\s*\n/, mapper)

    restored_linear =
      Regex.match?(~r/phase=restored\n0\s+\d+\s+linear\s+/, mapper)

    erofs_provenance = errno != "erofs" or mapper =~ "emergency_ro"

    semantic_table and live_error and restored_linear and erofs_provenance
  end

  defp fixture_complete?(fixture) do
    Regex.match?(~r/^DIRTY_PWRITE=(?:ok|error:eio|error:erofs)$/m, fixture) and
      fixture =~ "GATEWAY_RECOVERY_MODE=pass" and
      fixture =~ "LATER_PROTECTED_REFUSAL=pass" and
      fixture =~ "DESTINATION_VERIFICATION=pass" and
      fixture =~ "SOURCE_AUTHORITY=pass" and
      fixture =~ "FILESYSTEM_RECOVERY=not_claimed" and
      fixture =~ "FIXTURE_RESULT=pass"
  end

  defp format_time(time), do: :erlang.float_to_binary(time, decimals: 9)
end

System.halt(PramanaFoundry.CI.FR19ASyncFaultParse.main(System.argv()))
