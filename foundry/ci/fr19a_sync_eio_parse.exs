defmodule PramanaFoundry.CI.FR19ASyncEIOParse do
  @moduledoc false

  def main([trace_prefix, destination, fixture_log, output]) do
    destination = Path.expand(destination)

    traces =
      trace_prefix
      |> Path.wildcard()
      |> Enum.sort()

    matches =
      for trace <- traces,
          line <- File.stream!(trace, :line, []),
          sync_eio?(line),
          String.contains?(line, "<#{destination}>") do
        %{trace: trace, line: String.trim(line)}
      end

    fixture = File.read!(fixture_log)

    with true <- Regex.match?(~r/^DIRTY_PWRITE=(?:ok|error:eio)$/m, fixture),
         true <- fixture =~ "GATEWAY_STORAGE_FAILURE=eio",
         true <- fixture =~ "FIXTURE_RESULT=pass",
         [_first | _rest] <- matches do
      body = [
        "schema=pramana-foundry-fr19a-sync-eio-proof/v1",
        "destination=#{destination}",
        "sync_eio_matches=#{length(matches)}",
        "fixture_dirty_pwrite=ok",
        "gateway_storage_failure=eio",
        "result=pass",
        "",
        Enum.map_join(matches, "\n", &"#{&1.trace}: #{&1.line}")
      ]

      File.write!(output, Enum.join(body, "\n") <> "\n")
      0
    else
      _reason ->
        File.write!(
          output,
          "schema=pramana-foundry-fr19a-sync-eio-proof/v1\nresult=fail\n" <>
            "destination=#{destination}\nsync_eio_matches=#{length(matches)}\n"
        )

        2
    end
  end

  def main(_args), do: 64

  defp sync_eio?(line) do
    Regex.match?(~r/\b(?:fsync|fdatasync)\([^)]*\)\s+=\s+-1 EIO\b/, line)
  end
end

System.halt(PramanaFoundry.CI.FR19ASyncEIOParse.main(System.argv()))
