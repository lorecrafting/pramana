defmodule PramanaFoundry.Board.FindingsPanel do
  @moduledoc """
  Renders the findings/status panel for the TUI board using OWL.
  Shows recent findings from the improver (findings.jsonl) color-coded by severity.
  """

  alias Owl.Data

  @doc """
  Fetches recent findings from findings.jsonl.
  Returns the last N records, filtered to finding events only.
  Uses the same runtime_root logic as ConsolidatedLog.
  """
  @spec fetch_findings(pos_integer()) :: [map()]
  def fetch_findings(count \\ 15) do
    root = PramanaFoundry.RuntimeRoot.fetch!()

    path = Path.join(root, "state/current/findings.jsonl")

    case File.read(path) do
      {:ok, bytes} ->
        bytes
        |> String.split("\n", trim: true)
        |> Enum.map(&safe_decode/1)
        |> Enum.reject(&is_nil/1)
        |> Enum.reverse()
        |> Enum.take(count)

      _ ->
        []
    end
  end

  @doc """
  Renders the findings panel as Owl.Data.t().

  Shows the most severe findings first. Each line shows:
  severity icon, category, and summary.
  Falls back to a brief description if no findings.
  """
  @spec render_findings([map()], pos_integer()) :: Data.t()
  def render_findings(findings, terminal_width \\ nil) do
    width = terminal_width || Owl.IO.columns() || 80

    # Filter to only finding events, sorted by severity
    finding_events =
      Enum.filter(findings, fn f -> Map.get(f, "event") == "finding" end)

    # Count severity
    critical_count = Enum.count(finding_events, fn f -> Map.get(f, "severity") == "critical" end)
    high_count = Enum.count(finding_events, fn f -> Map.get(f, "severity") == "high" end)
    medium_count = Enum.count(finding_events, fn f -> Map.get(f, "severity") == "medium" end)

    # Get latest metrics_snapshot for memory/depth info
    latest_metrics =
      Enum.find(findings, fn f -> Map.get(f, "event") == "metrics_snapshot" end)

    _latest_proposal =
      Enum.find(findings, fn f -> Map.get(f, "event") == "proposal" end)

    # Render findings entries (max ~5 visible)
    visible = Enum.take(finding_events, 5)

    findings_lines =
      if visible == [] do
        [Data.tag("  No active findings.", :light_black)]
      else
        Enum.map(visible, fn f ->
          severity = Map.get(f, "severity", "info")
          category = Map.get(f, "category", "unknown")
          summary = Map.get(f, "summary", "")

          severity_icon =
            case severity do
              "critical" -> Data.tag("● ", :red)
              "high" -> Data.tag("● ", :yellow)
              "medium" -> Data.tag("● ", :blue)
              _ -> Data.tag("○ ", :light_black)
            end

          category_tag = Data.tag("[#{category}]", :light_black)
          summary_trimmed = String.slice(summary, 0, width - 25)

          [severity_icon, category_tag, " ", Data.tag(summary_trimmed, :default_color)]
        end)
      end

    # Summary line
    summary_parts = [
      Data.tag("Findings: ", [:bright]),
      Data.tag("#{critical_count} critical", :red),
      " / ",
      Data.tag("#{high_count} high", :yellow),
      " / ",
      Data.tag("#{medium_count} medium", :blue)
    ]

    metrics_part =
      if latest_metrics do
        mem_kb = div(Map.get(latest_metrics, "memory_bytes", 0), 1024)
        findings_count = Map.get(latest_metrics, "findings_count", 0)
        cycle = Map.get(latest_metrics, "cycle", 0)
        " │ Mem: #{mem_kb}KB │ Cycle: #{cycle} │ Active: #{findings_count}"
      else
        ""
      end

    summary_info = [summary_parts, Data.tag(metrics_part, :light_black)]

    Owl.Box.new(
      [
        summary_info,
        "\n",
        Enum.intersperse(findings_lines, "\n")
      ],
      title: Data.tag("FINDINGS", [:bright, :yellow]),
      border_style: :solid_rounded,
      border_tag: :yellow,
      padding_x: 1,
      max_width: width
    )
  end

  defp safe_decode(line) do
    :json.decode(line)
  rescue
    _ -> nil
  end
end
