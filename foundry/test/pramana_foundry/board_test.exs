defmodule PramanaFoundry.BoardTest do
  use ExUnit.Case, async: false

  alias PramanaFoundry.Board
  alias PramanaFoundry.Coordinator
  alias PramanaFoundry.Status.Report

  @base_rev "d83f8f0cedc34780d25cba452545ce9883d416a5"
  @commit "2222333344445555666677778888999900001111"
  @check ["sh", "-c", "cd workflow && exec mise exec -- mix test"]

  setup do
    Report.set_runtime_implementation_revision(@base_rev)
    :ok = Coordinator.reset(accepted_revision: @base_rev)
    :ok
  end

  describe "columns, titles, and summaries" do
    test "canonical columns contains all 8 required columns" do
      expected = [
        "Backlog/Planned",
        "Queued",
        "Working",
        "Review",
        "Integration",
        "Accepted",
        "Parked",
        "Cooldown"
      ]

      assert Board.columns() == expected
    end

    test "card_title deterministically extracts concise human labels" do
      assert Board.card_title("WF-ELIXIR-BOARD-01") == "WF ELIXIR BOARD"
      assert Board.card_title("T-COORD-1") == "T COORD"
      assert Board.card_title("AUTO-FIXTURE-CLEANUP-02") == "AUTO FIXTURE CLEANUP"
      assert Board.card_title("simple") == "simple"
    end

    test "card_summary deterministically extracts first meaningful line of outcome" do
      outcome = """
      - Implement the Elixir terminal board and sanitized BEAM inspection.
      Full details follow on subsequent lines.
      """

      assert Board.card_summary(outcome, "WF-01") ==
               "Implement the Elixir terminal board and sanitized BEAM inspection."

      markdown_outcome = """
      # Summary
      ```elixir
      code
      ```
      Outcome: The main outcome description here.
      Actual outcome line to display.
      """

      assert Board.card_summary(markdown_outcome, "WF-02") ==
               "Actual outcome line to display."

      assert Board.card_summary("", "FALLBACK") == "FALLBACK"
      assert Board.card_summary(nil, "FALLBACK") == "FALLBACK"
    end

    test "status_column maps raw statuses to canonical columns" do
      assert Board.status_column("backlog") == "Backlog/Planned"
      assert Board.status_column("planned") == "Backlog/Planned"
      assert Board.status_column("queued") == "Queued"
      assert Board.status_column("dispatched") == "Working"
      assert Board.status_column("working") == "Working"
      assert Board.status_column("prompting") == "Working"
      assert Board.status_column("handoff_received") == "Review"
      assert Board.status_column("reviewing") == "Review"
      assert Board.status_column("approved") == "Integration"
      assert Board.status_column("review_approved") == "Integration"
      assert Board.status_column("accepted") == "Accepted"
      assert Board.status_column("integrated") == "Accepted"
      assert Board.status_column("parked") == "Parked"
      assert Board.status_column("blocked") == "Parked"
      assert Board.status_column("cooldown") == "Cooldown"
    end
  end

  describe "board rendering and state" do
    test "renders all 8 columns in frame" do
      board =
        start_supervised!({Board, [coordinator: Coordinator, name: nil, width: 160, height: 30]})

      frame = Board.render_frame(board)

      assert String.contains?(frame, "PRAMĀNA WORKFLOW BOARD")
      assert String.contains?(frame, "Backlog/Planned")
      assert String.contains?(frame, "Queued")
      assert String.contains?(frame, "Working")
      assert String.contains?(frame, "Review")
      assert String.contains?(frame, "Integration")
      assert String.contains?(frame, "Accepted")
      assert String.contains?(frame, "Parked")
      assert String.contains?(frame, "Cooldown")
    end

    test "renders card titles and one-line summaries for tickets" do
      ticket = %{
        "task_id" => "WF-ELIXIR-BOARD-01",
        "base_revision" => @base_rev,
        "priority" => "P0",
        "workload" => "standard",
        "risk" => "workflow_recovery",
        "model" => "gemini",
        "profile" => "omp_gemini_developer",
        "dependencies" => ["WF-ELIXIR-ENGINE-04"],
        "required_checks" => [@check],
        "outcome" => "Implement the Elixir terminal board and sanitized BEAM inspection."
      }

      assert :ok = Coordinator.enqueue_ticket(ticket)

      board =
        start_supervised!({Board, [coordinator: Coordinator, name: nil, width: 120, height: 30]})

      Board.refresh(board)

      frame = Board.render_frame(board)

      assert String.contains?(frame, "WF-ELIXIR-BOARD-01")
      assert String.contains?(frame, "WF ELIXIR BOARD")
      assert String.contains?(frame, "Implement the Elixir")
    end
  end

  describe "keyboard navigation and card selection" do
    test "left and right keys navigate between columns with visual indication" do
      board =
        start_supervised!({Board, [coordinator: Coordinator, name: nil, width: 120, height: 30]})

      vs0 = Board.view_state(board)
      assert vs0.active_column == 0

      # Move right with "l" (vim key)
      assert {:ok, vs1} = Board.handle_key(board, "l")
      assert vs1.active_column == 1

      # Move right with :right arrow
      assert {:ok, vs2} = Board.handle_key(board, :right)
      assert vs2.active_column == 2

      # Move right with ANSI escape "\e[C"
      assert {:ok, vs3} = Board.handle_key(board, "\e[C")
      assert vs3.active_column == 3

      # Move left with "h" (vim key)
      assert {:ok, vs4} = Board.handle_key(board, "h")
      assert vs4.active_column == 2

      # Move left with :left arrow
      assert {:ok, vs5} = Board.handle_key(board, :left)
      assert vs5.active_column == 1

      # Move left past column 0 clamps to 0
      assert {:ok, _} = Board.handle_key(board, :left)
      assert {:ok, vs_clamped} = Board.handle_key(board, :left)
      assert vs_clamped.active_column == 0

      # Frame displays active column marker
      frame = Board.render_frame(board)
      assert String.contains?(frame, "▶ Backlog/Planned")
    end

    test "up and down keys select cards within active column" do
      # Enqueue two tickets
      ticket1 = %{
        "task_id" => "T-TEST-1",
        "base_revision" => @base_rev,
        "required_checks" => [@check],
        "outcome" => "First ticket outcome"
      }

      ticket2 = %{
        "task_id" => "T-TEST-2",
        "base_revision" => @base_rev,
        "required_checks" => [@check],
        "outcome" => "Second ticket outcome"
      }

      :ok = Coordinator.enqueue_ticket(ticket1)
      :ok = Coordinator.enqueue_ticket(ticket2)

      board =
        start_supervised!({Board, [coordinator: Coordinator, name: nil, width: 120, height: 30]})

      Board.refresh(board)

      # Switch to Queued column (index 1)
      assert {:ok, _} = Board.handle_key(board, :right)
      vs = Board.view_state(board)
      assert vs.active_column == 1
      assert Map.get(vs.selected_rows, 1, 0) == 0

      # Down arrow selects second card
      assert {:ok, vs_down} = Board.handle_key(board, :down)
      assert Map.get(vs_down.selected_rows, 1) == 1

      # Down arrow clamps at last card
      assert {:ok, vs_down_clamp} = Board.handle_key(board, :down)
      assert Map.get(vs_down_clamp.selected_rows, 1) == 1

      # Up arrow selects first card
      assert {:ok, vs_up} = Board.handle_key(board, "k")
      assert Map.get(vs_up.selected_rows, 1) == 0

      # Up arrow clamps at 0
      assert {:ok, vs_up_clamp} = Board.handle_key(board, "k")
      assert Map.get(vs_up_clamp.selected_rows, 1) == 0

      # Frame shows selection marker "▶ "
      frame = Board.render_frame(board)
      assert String.contains?(frame, "▶ ")
    end
  end

  describe "detail view expansion and dismissal" do
    test "enter opens detail view with all ticket metadata, esc/q dismisses" do
      ticket = %{
        "task_id" => "WF-ELIXIR-BOARD-01",
        "base_revision" => @base_rev,
        "priority" => "P0",
        "workload" => "standard",
        "risk" => "workflow_recovery",
        "model" => "gemini-3.8-flash",
        "profile" => "omp_gemini_developer",
        "dependencies" => ["WF-ELIXIR-ENGINE-04"],
        "required_checks" => [@check],
        "outcome" => "Implement the Elixir terminal board and sanitized BEAM inspection."
      }

      :ok = Coordinator.enqueue_ticket(ticket)

      board =
        start_supervised!({Board, [coordinator: Coordinator, name: nil, width: 120, height: 30]})

      Board.refresh(board)

      # Navigate to Queued column (index 1)
      {:ok, _} = Board.handle_key(board, :right)

      # Press Enter to open detail view
      {:ok, vs_detail} = Board.handle_key(board, :enter)
      assert vs_detail.detail_task_id == "WF-ELIXIR-BOARD-01"

      frame = Board.render_frame(board)
      assert String.contains?(frame, "TICKET: WF-ELIXIR-BOARD-01")
      assert String.contains?(frame, "Priority: P0")
      assert String.contains?(frame, "Workload: standard")
      assert String.contains?(frame, "Risk: workflow_recovery")
      assert String.contains?(frame, "Model / Profile: gemini-3.8-flash / omp_gemini_developer")
      assert String.contains?(frame, "Base Revision: #{@base_rev}")
      assert String.contains?(frame, "Dependencies: WF-ELIXIR-ENGINE-04")
      assert String.contains?(frame, "REQUIRED CHECKS")
      assert String.contains?(frame, "OUTCOME")
      assert String.contains?(frame, "Implement the Elixir terminal board")

      # Scroll in detail view
      {:ok, vs_scroll} = Board.handle_key(board, :down)
      assert vs_scroll.detail_scroll_offset == 1

      # Press 'q' dismisses detail view without quitting board
      {:ok, vs_dismiss} = Board.handle_key(board, "q")
      assert vs_dismiss.detail_task_id == nil

      # Now back to board view
      board_frame = Board.render_frame(board)
      assert String.contains?(board_frame, "PRAMĀNA WORKFLOW BOARD")

      # Re-open and dismiss with :esc
      {:ok, _} = Board.handle_key(board, :enter)
      assert Board.view_state(board).detail_task_id == "WF-ELIXIR-BOARD-01"

      {:ok, vs_esc} = Board.handle_key(board, :esc)
      assert vs_esc.detail_task_id == nil
    end

    test "q in board view signals quit" do
      board =
        start_supervised!({Board, [coordinator: Coordinator, name: nil, width: 120, height: 30]})

      assert {:quit, vs_quit} = Board.handle_key(board, "q")
      assert vs_quit.quit? == true
    end
  end

  describe "terminal resize handling" do
    test "resize handles dimension changes smoothly" do
      board =
        start_supervised!({Board, [coordinator: Coordinator, name: nil, width: 120, height: 30]})

      # Standard size
      lines120 = Board.render_lines(board)
      assert length(lines120) == 30

      # Wide size
      :ok = Board.resize(board, 160, 40)
      lines160 = Board.render_lines(board)
      assert length(lines160) == 40
      vs160 = Board.view_state(board)
      assert vs160.width == 160
      assert vs160.height == 40

      # Narrow size
      :ok = Board.resize(board, 60, 15)
      lines60 = Board.render_lines(board)
      assert length(lines60) == 15
      vs60 = Board.view_state(board)
      assert vs60.width == 60
      assert vs60.height == 15

      # Minimum bounds respected
      :ok = Board.resize(board, 10, 2)
      vs_min = Board.view_state(board)
      assert vs_min.width >= 30
      assert vs_min.height >= 8
    end
  end

  describe "revision visibility and mismatch highlighting" do
    test "visibly highlights revision mismatch until reconciled" do
      board =
        start_supervised!({Board, [coordinator: Coordinator, name: nil, width: 120, height: 30]})

      # Initial state: in sync
      frame_sync = Board.render_frame(board)
      assert String.contains?(frame_sync, "Revisions in sync")
      refute String.contains?(frame_sync, "REVISION MISMATCH")

      # Introduce mismatch
      mismatched_rev = "1111222233334444555566667777888899990000"
      Report.set_runtime_implementation_revision(mismatched_rev)
      Board.refresh(board)

      frame_mismatch = Board.render_frame(board)
      assert String.contains?(frame_mismatch, "REVISION MISMATCH")
      assert String.contains?(frame_mismatch, "restart required")

      # Reconcile revision
      Report.reconcile_runtime_implementation_revision(@base_rev)
      Board.refresh(board)

      frame_reconciled = Board.render_frame(board)
      assert String.contains?(frame_reconciled, "Revisions in sync")
      refute String.contains?(frame_reconciled, "REVISION MISMATCH")
    end
  end

  describe "automatic refresh on state change" do
    test "automatic refresh timer reloads coordinator data without keystrokes" do
      # Start board with fast refresh interval (50ms)
      board =
        start_supervised!(
          {Board,
           [coordinator: Coordinator, name: nil, refresh_interval_ms: 50, width: 120, height: 30]}
        )

      data0 = Board.get_data(board)
      assert length(data0.tickets) == 0

      # Enqueue ticket in coordinator
      ticket = %{
        "task_id" => "T-AUTO-REFRESH",
        "base_revision" => @base_rev,
        "required_checks" => [@check],
        "outcome" => "Auto refreshed ticket"
      }

      :ok = Coordinator.enqueue_ticket(ticket)

      # Wait for auto-refresh tick (150ms > 50ms)
      Process.sleep(150)

      data1 = Board.get_data(board)
      assert length(data1.tickets) == 1
      assert hd(data1.tickets).task_id == "T-AUTO-REFRESH"

      frame = Board.render_frame(board)
      assert String.contains?(frame, "T-AUTO-REFRESH")
    end
  end

  describe "complete fault isolation" do
    test "board crash, exit, or kill cannot stop, delay, or disrupt coordinator" do
      ticket = %{
        "task_id" => "T-ISOLATION-1",
        "base_revision" => @base_rev,
        "scope" => ["workflow/lib/pramana_foundry/**"],
        "required_checks" => [@check],
        "outcome" => "Fault isolation verification"
      }

      :ok = Coordinator.enqueue_ticket(ticket)
      assert "T-ISOLATION-1" in Coordinator.state()["queue"]

      # Start unlinked board process
      {:ok, board_pid} = Board.start(coordinator: Coordinator, name: nil)
      assert Process.alive?(board_pid)

      # Board reads data successfully
      data = Board.get_data(board_pid)
      assert length(data.tickets) == 1

      # Kill the board process violently with :kill
      Process.exit(board_pid, :kill)
      refute Process.alive?(board_pid)

      # Coordinator is completely unharmed and operational
      coord_pid = Process.whereis(Coordinator)
      assert coord_pid != nil
      assert Process.alive?(coord_pid)

      # Coordinator can admit assignment and execute workflow dispatch without delay
      assert {:ok, _} = Coordinator.admit_assignment("T-ISOLATION-1", "run-iso-1", "developer")
      assert Coordinator.state()["assignments"]["T-ISOLATION-1"]["status"] == "dispatched"

      # Handoff can be received normally
      handoff = %{
        "schema_version" => 1,
        "task_id" => "T-ISOLATION-1",
        "run_id" => "run-iso-1",
        "assigned_base" => @base_rev,
        "commit" => @commit,
        "changed_files" => ["workflow/lib/pramana_foundry/board.ex"],
        "reproduction_evidence" => %{"before" => "fail", "after" => "pass"},
        "checks" => [%{"command" => @check, "exit_code" => 0}],
        "remaining_risks" => [],
        "status" => "completed",
        "outcome" => "Implemented fault isolation"
      }

      assert {:ok, _} =
               Coordinator.receive_handoff("T-ISOLATION-1", handoff, skip_git_checks: true)

      assert Coordinator.state()["assignments"]["T-ISOLATION-1"]["status"] == "handoff_received"
    end

    test "coordinator continues unaffected when board encounters unexpected exceptions" do
      {:ok, board_pid} = Board.start(coordinator: Coordinator, name: nil)

      # Send unexpected garbage message to board
      send(board_pid, {:some_unexpected_event, 12345})
      # Board ignores or survives
      assert Process.alive?(board_pid)

      # Coordinator remains completely healthy
      assert Coordinator.status()["paused"] == false
      assert :ok = Coordinator.pause()
      assert Coordinator.status()["paused"] == true
      assert :ok = Coordinator.resume()

      Board.close(board_pid)
    end
  end
end
