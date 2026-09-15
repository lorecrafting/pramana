defmodule PramanaFoundry.Board.View do
  @moduledoc """
  Pure functional terminal frame rendering for the PramanaFoundry board.
  Uses OWL (Owl.Data, Owl.Box, Owl.Data.zip) for colorized, box-drawn output.
  Produces Owl.Data.t() suitable for Owl.LiveScreen blocks.
  """

  alias Owl.Data

  @columns [
    "Backlog/Planned",
    "Queued",
    "Working",
    "Review",
    "Integration",
    "Accepted",
    "Parked",
    "Cooldown"
  ]

  @doc """
  Returns the canonical list of board columns.
  """
  def columns, do: @columns

  @doc """
  Renders the full board frame (kanban + status bar) as Owl.Data.t().
  """
  @spec render_frame(map(), map(), pos_integer()) :: Data.t()
  def render_frame(view_state, data, terminal_width \\ nil) do
    width = terminal_width || Owl.IO.columns() || 120

    if view_state.detail_task_id do
      render_detail_view(view_state, data, width)
    else
      render_board_view(view_state, data, width)
    end
  end

  @doc """
  Renders only the kanban columns (for intermediate composition, e.g., zipping).
  """
  @spec render_kanban(map(), map(), pos_integer()) :: Data.t()
  def render_kanban(view_state, data, terminal_width \\ nil) do
    width = terminal_width || Owl.IO.columns() || 120

    if view_state.detail_task_id do
      render_detail_view(view_state, data, width)
    else
      render_columns_only(view_state, data, width)
    end
  end

  # ===================================================================
  # Board View — Full Frame
  # ===================================================================

  defp render_board_view(view_state, data, width) do
    active_col_idx = clamp_index(view_state.active_column, length(@columns))
    grouped = group_tickets_by_column(data[:tickets] || [])

    title_bar   = build_title_bar(data, width)
    rev_bar     = build_revision_bar(data, width)
    tab_bar     = build_tab_bar(active_col_idx, grouped, width)
    headers     = [title_bar, "\n", rev_bar, "\n", tab_bar]

    columns_rendered = render_columns(view_state, grouped, width)
    footer = build_footer(width)

    Data.unlines([
      headers,
      "\n",
      columns_rendered,
      "\n",
      footer
    ])
  end

  defp render_columns_only(view_state, data, width) do
    grouped = group_tickets_by_column(data[:tickets] || [])
    render_columns(view_state, grouped, width)
  end

  # ===================================================================
  # Title / Revision / Tab Bars
  # ===================================================================

  defp build_title_bar(data, width) do
    node_str = data[:node] || to_string(Node.self())
    workers_cnt = data[:active_workers_count] || 0
    pm_status = data[:pm_status] || "idle"

    paused_str = if data[:paused], do: Data.tag(" [PAUSED]", :red), else: ""
    stop_str = if data[:stop_requested], do: Data.tag(" [STOP_REQUESTED]", :yellow), else: ""

    title = [
      Data.tag("PRAMĀNA WORKFLOW BOARD", [:bright, :cyan]),
      paused_str,
      stop_str
    ]

    info = "Node: #{node_str} │ Workers: #{workers_cnt} │ PM: #{pm_status}"

    # Right-align info
    gap = max(1, width - Data.length(title) - String.length(info))
    [title, String.duplicate(" ", gap), Data.tag(info, :light_black)]
  end

  defp build_revision_bar(data, _width) do
    accepted = data[:accepted_revision] || "-"
    runtime = data[:runtime_implementation_revision] || "-"
    match? = data[:revisions_match?] != false and accepted == runtime

    if match? do
      Data.tag("  Revisions in sync [Source: #{short_rev(accepted)} │ Loaded: #{short_rev(runtime)}]", :light_black)
    else
      Data.tag(
        "  ⚠ REVISION MISMATCH: loaded #{short_rev(runtime)} != source #{short_rev(accepted)} — restart required",
        [:red, :bright]
      )
    end
  end

  defp build_tab_bar(active_col_idx, grouped, width) do
    tab_parts =
      @columns
      |> Enum.with_index()
      |> Enum.map(fn {col, idx} ->
        count = length(Map.get(grouped, col, []))
        selected = idx == active_col_idx

        if selected do
          Data.tag(" ▶ #{col} (#{count}) ", [:bright, :cyan])
        else
          Data.tag(" #{col} (#{count}) ", :light_black)
        end
      end)

    joined = Enum.reduce(tab_parts, &Data.zip/2)

    if Data.length(joined) <= width do
      joined
    else
      active_col = Enum.at(@columns, active_col_idx)
      count = length(Map.get(grouped, active_col, []))
      Data.tag(" ▶ #{active_col} (#{count}) ◀", [:bright, :cyan])
    end
  end

  # ===================================================================
  # Column Rendering
  # ===================================================================

  defp render_columns(view_state, grouped, width) do
    active_col_idx = clamp_index(view_state.active_column, length(@columns))
    visible_indices = calculate_visible_columns(active_col_idx, width)
    num_visible = length(visible_indices)

    col_width = div(width, num_visible) - 1  # 1 for the separator gap

    rendered =
      Enum.map(visible_indices, fn col_idx ->
        col_name = Enum.at(@columns, col_idx)
        tickets = Map.get(grouped, col_name, [])
        focused? = col_idx == active_col_idx
        selected_row = Map.get(view_state.selected_rows || %{}, col_idx, 0)

        render_column_box(col_name, tickets, focused?, selected_row, col_width)
      end)

    # Zip columns side-by-side with Data.zip
    Enum.reduce(rendered, fn col, acc ->
      Data.zip(acc, col)
    end)
  end

  defp render_column_box(col_name, tickets, focused?, selected_row, width) do
    card_width = max(10, width - 2)
    count = length(tickets)

    title_content = Data.tag("#{col_name} (#{count})", if(focused?, do: [:bright, :cyan], else: :light_black))

    # Render cards inside the column
    card_lines =
      if count == 0 do
        Data.tag(" (no tickets)", :light_black)
      else
        render_cards(tickets, selected_row, focused?, card_width)
      end

    box_opts = [
      title: title_content,
      border_style: :solid_rounded,
      padding_x: 1,
      min_height: 6,
      max_width: width
    ]

    # If focused, make border standout
    box_opts =
      if focused? do
        Keyword.put(box_opts, :border_tag, :cyan)
      else
        box_opts
      end

    Owl.Box.new(card_lines, box_opts)
  end

  defp render_cards(tickets, selected_row, focused?, width) do
    tickets
    |> Enum.with_index()
    |> Enum.map(fn {ticket, idx} ->
      selected? = focused? and idx == selected_row
      marker = if selected?, do: Data.tag("▶ ", [:bright, :cyan]), else: "  "
      prio = priority_tag(ticket[:priority])
      severity = risk_tag(ticket[:risk])

      header = [
        marker,
        prio,
        severity,
        Data.tag(ticket[:task_id], if(selected?, do: [:bright], else: []))
      ]

      title_str = ticket[:title] || ""
      title_trimmed = String.slice(title_str, 0, width - 2)
      title_line = ["  ", title_trimmed]

      summary_str = ticket[:summary] || ""
      summary_trimmed = String.slice(summary_str, 0, width - 2)
      summary_line =
        if summary_trimmed != "" do
          ["  ", Data.tag(summary_trimmed, :light_black)]
        else
          []
        end

      [header, "\n", title_line, "\n", summary_line]
    end)
    |> Enum.intersperse(["\n", "\n"])
    |> List.flatten()
  end

  defp priority_tag(nil), do: ""
  defp priority_tag(:none), do: ""
  defp priority_tag(""), do: ""

  defp priority_tag(prio) do
    color =
      case to_string(prio) do
        "critical" -> :red
        "high" -> :yellow
        "medium" -> :blue
        _ -> :default_color
      end

    [Data.tag("[#{prio}] ", color), ""]
  end

  defp risk_tag(nil), do: ""
  defp risk_tag(""), do: ""

  defp risk_tag(risk) do
    color =
      case to_string(risk) do
        "high" -> :red_background
        "medium" -> :yellow_background
        _ -> :default_background
      end

    [Data.tag("{#{risk}} ", color), ""]
  end

  # ===================================================================
  # Visible Column Calculation
  # ===================================================================

  defp calculate_visible_columns(active_col_idx, width) do
    total = length(@columns)

    cond do
      width >= 160 ->
        0..(total - 1) |> Enum.to_list()

      width >= 100 ->
        num_cols = min(total, max(2, div(width, 30)))
        start = max(0, min(active_col_idx - div(num_cols, 2), total - num_cols))
        start..(start + num_cols - 1) |> Enum.to_list()

      true ->
        [active_col_idx]
    end
  end

  # ===================================================================
  # Detail View
  # ===================================================================

  defp render_detail_view(view_state, data, width) do
    task_id = view_state.detail_task_id
    ticket = find_ticket(data[:tickets] || [], task_id)

    if ticket do
      render_ticket_detail(ticket, view_state, width)
    else
      Owl.Box.new(
        Data.tag("Ticket #{task_id} not found in current board state.", :red),
        title: Data.tag("ERROR", :red),
        border_style: :solid_rounded,
        border_tag: :red
      )
    end
  end

  defp render_ticket_detail(ticket, view_state, width) do
    card_width = max(20, width - 4)

    fields =
      [
        {"Task ID", ticket[:task_id]},
        {"Title", ticket[:title] || "-"},
        {"Status", "#{ticket[:status]} (raw: #{ticket[:raw_status] || "-"})"},
        {"Priority", ticket[:priority] || "none"},
        {"Workload", ticket[:workload] || "standard"},
        {"Risk", ticket[:risk] || "none"},
        {"Model / Profile", "#{ticket[:model] || "-"} / #{ticket[:profile] || "-"}"},
        {"Base Revision", ticket[:base_revision] || "-"},
        {"Dependencies", format_deps_inline(ticket[:dependencies])},
        {"Run ID", ticket[:run_id] || "-"},
        {"Role", ticket[:role] || "-"},
        {"Candidate Commit", ticket[:candidate_commit] || "-"}
      ]

    content =
      [
        render_field_table(fields, card_width),
        render_checks_block(ticket[:required_checks], card_width),
        render_outcome_block(ticket[:outcome], card_width),
        render_blocker_block(ticket[:blocker], card_width),
        render_diagnostics_block(ticket[:diagnostics], card_width),
        render_handoff_block(ticket[:handoff], card_width),
        render_review_block(ticket[:review], card_width)
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.intersperse("\n")

    title = Data.tag("TICKET: #{ticket[:task_id]} [#{ticket[:status]}]", [:bright])
    scroll_hint = if view_state.detail_scroll_offset > 0, do: "\n  (↑ scrolled)", else: ""

    Owl.Box.new(
      [content, scroll_hint],
      title: title,
      border_style: :solid_rounded,
      border_tag: :cyan,
      padding_x: 1,
      max_width: width
    )
  end

  defp render_field_table(fields, _width) do
    Enum.map(fields, fn {label, value} ->
      [
        Data.tag("  #{label}: ", [:bright]),
        Data.tag(to_string(value), :default_color),
        "\n"
      ]
    end)
  end

  defp render_checks_block(nil, _width), do: nil
  defp render_checks_block([], _width), do: nil

  defp render_checks_block(checks, _width) do
    items =
      Enum.map(checks, fn
        cmd when is_list(cmd) -> "  • #{Enum.join(cmd, " ")}"
        other -> "  • #{to_string(other)}"
      end)

    [Data.tag("\n  REQUIRED CHECKS", [:bright, :underline]), "\n", Enum.join(items, "\n")]
  end

  defp render_outcome_block(nil, _width), do: nil
  defp render_outcome_block("", _width), do: nil

  defp render_outcome_block(outcome, width) do
    trimmed =
      outcome
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(&("  " <> String.slice(&1, 0, width - 4)))
      |> Enum.join("\n")

    [Data.tag("\n  OUTCOME", [:bright, :underline]), "\n", trimmed]
  end

  defp render_blocker_block(nil, _width), do: nil
  defp render_blocker_block("", _width), do: nil

  defp render_blocker_block(blocker, width) do
    text = String.slice(to_string(blocker), 0, width - 4)
    [Data.tag("\n  BLOCKER / ERROR", [:bright, :red, :underline]), "\n  ", Data.tag(text, :red)]
  end

  defp render_diagnostics_block(nil, _width), do: nil
  defp render_diagnostics_block([], _width), do: nil

  defp render_diagnostics_block(diags, width) do
    items =
      Enum.map(diags, fn d ->
        "  - " <> String.slice(to_string(d), 0, width - 6)
      end)

    [Data.tag("\n  DIAGNOSTICS", [:bright, :underline]), "\n", Enum.join(items, "\n")]
  end

  defp render_handoff_block(nil, _width), do: nil

  defp render_handoff_block(handoff, _width) do
    commit = Map.get(handoff, "commit", "-")
    status = Map.get(handoff, "status", "-")
    [Data.tag("\n  HANDOFF", [:bright, :underline]), "\n  Commit: #{commit} │ Status: #{status}"]
  end

  defp render_review_block(nil, _width), do: nil

  defp render_review_block(review, _width) do
    verdict = Map.get(review, "verdict", "-")
    findings = Map.get(review, "findings", [])
    [Data.tag("\n  REVIEW", [:bright, :underline]), "\n  Verdict: #{verdict} │ Findings: #{length(findings)}"]
  end

  # ===================================================================
  # Footer
  # ===================================================================

  defp build_footer(_width) do
    text = "←/→, h/l: Column │ ↑/↓, j/k: Card │ Enter: Details │ r: Refresh │ q: Quit"
    Data.tag("  #{text}", :light_black)
  end

  # ===================================================================
  # Helpers
  # ===================================================================

  defp group_tickets_by_column(tickets) do
    base = Map.new(@columns, fn col -> {col, []} end)

    Enum.reduce(tickets, base, fn ticket, acc ->
      col = Map.get(ticket, :status, "Parked")

      if Map.has_key?(acc, col) do
        Map.update!(acc, col, fn list -> list ++ [ticket] end)
      else
        Map.update!(acc, "Parked", fn list -> list ++ [ticket] end)
      end
    end)
  end

  defp find_ticket(tickets, task_id) do
    Enum.find(tickets, fn t -> t[:task_id] == task_id end)
  end

  defp clamp_index(idx, total) do
    max(0, min(idx || 0, total - 1))
  end

  defp short_rev(rev) when is_binary(rev) do
    if String.length(rev) >= 12, do: String.slice(rev, 0, 10), else: rev
  end

  defp short_rev(_), do: "-"

  defp format_deps_inline(nil), do: "none"
  defp format_deps_inline([]), do: "none"
  defp format_deps_inline(deps) when is_list(deps), do: Enum.join(deps, ", ")
  defp format_deps_inline(other), do: to_string(other)
end