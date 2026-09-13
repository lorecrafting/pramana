defmodule PramanaFoundry.Board do
  @moduledoc """
  Terminal board for PramanaFoundry reading the coordinator's authoritative
  projection and status report. Renders status columns:
  Backlog/Planned, Queued, Working, Review, Integration, Accepted, Parked, Cooldown.

  Supports automatic refresh, terminal resize handling, keyboard navigation,
  detail views, and visible revision mismatch highlighting. Fault-isolated:
  board crash or exit cannot disrupt coordinator execution.
  """

  use GenServer

  alias PramanaFoundry.Board.Inspection
  alias PramanaFoundry.Board.FindingsPanel
  alias PramanaFoundry.Board.View
  alias PramanaFoundry.Board.ViewState
  alias PramanaFoundry.Coordinator
  alias PramanaFoundry.Status.Report

  @columns View.columns()

  # ===================================================================
  # Public Client API
  # ===================================================================

  @doc """
  Starts the board GenServer.
  Options:
  - `:coordinator`: module or pid of coordinator (default `PramanaFoundry.Coordinator`)
  - `:refresh_interval_ms`: poll interval in ms (default 1000)
  - `:width`: initial width (default 120)
  - `:height`: initial height (default 30)
  - `:name`: registration name (default `PramanaFoundry.Board`, or nil for anonymous)
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)

    if name do
      GenServer.start_link(__MODULE__, opts, name: name)
    else
      GenServer.start_link(__MODULE__, opts)
    end
  end

  @doc """
  Starts the board GenServer unlinked.
  """
  def start(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)

    if name do
      GenServer.start(__MODULE__, opts, name: name)
    else
      GenServer.start(__MODULE__, opts)
    end
  end

  @doc """
  Handles a keyboard input event on the board.
  """
  def handle_key(board \\ __MODULE__, key) do
    GenServer.call(board, {:handle_key, key})
  end

  @doc """
  Updates the terminal dimensions on resize.
  """
  def resize(board \\ __MODULE__, width, height) do
    GenServer.call(board, {:resize, width, height})
  end

  @doc """
  Forces an immediate refresh of data from the coordinator.
  """
  def refresh(board \\ __MODULE__) do
    GenServer.call(board, :refresh)
  end

  @doc """
  Returns the current rendered terminal frame as a string.
  """
  def render_frame(board \\ __MODULE__) do
    GenServer.call(board, :render_frame)
  end

  @doc """
  Returns the current rendered terminal frame as a list of lines.
  """
  def render_lines(board \\ __MODULE__) do
    GenServer.call(board, :render_lines)
  end

  @doc """
  Returns the current ViewState struct.
  """
  def view_state(board \\ __MODULE__) do
    GenServer.call(board, :view_state)
  end

  @doc """
  Returns the current board data map.
  """
  def get_data(board \\ __MODULE__) do
    GenServer.call(board, :get_data)
  end

  @doc """
  Stops the board process.
  """
  def close(board \\ __MODULE__) do
    GenServer.stop(board, :normal)
  end

  @doc """
  Returns formatted sanitized BEAM inspection status and attach instructions.
  """
  def inspection(opts \\ []) do
    Inspection.format(opts)
  end

  @doc """
  Returns raw sanitized BEAM inspection status map.
  """
  def inspection_status(opts \\ []) do
    Inspection.status(opts)
  end

  @doc """
  Runs the interactive terminal board loop using Owl.LiveScreen.
  If running in a non-TTY environment, renders one frame and returns :ok.

  When running as an escript (separate BEAM node), this function:
  - Starts the `:owl` application for LiveScreen support
  - Connects to the running daemon node to access Coordinator state
  - Falls back to local data if the daemon cannot be reached
  """
  def run(opts \\ []) do
    # Ensure OWL application is running (critical in escript mode;
    # Mix/release auto-starts it)
    ensure_owl_started()

    # When running outside the daemon node (escript), connect to it
    # so Coordinator.state() works
    connect_to_daemon()

    case start_link(opts) do
      {:ok, pid} ->
        if tty?() do
          run_interactive(pid)
        else
          IO.puts(render_frame(pid))
          close(pid)
          :ok
        end

      {:error, {:already_started, pid}} ->
        if tty?() do
          run_interactive(pid)
        else
          IO.puts(render_frame(pid))
          :ok
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc false
  def ensure_owl_started do
    case Application.start(:owl) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
      # non-fatal
      {:error, _} -> :ok
    end
  end

  @doc false
  def connect_to_daemon do
    # Try to connect to the daemon node for live coordinator state.
    # Falls back silently if distribution isn't available (escript mode).
    try do
      daemon_node = daemon_node_name()

      if daemon_node && Node.self() != daemon_node do
        cookie = daemon_cookie()
        if cookie, do: :erlang.set_cookie(String.to_atom(cookie))
        Node.connect(daemon_node)
      end
    rescue
      _ -> :ok
    end

    :ok
  end

  defp daemon_node_name do
    # The daemon runs as pramana_foundry@hostname
    {:ok, hostname} = :inet.gethostname()
    String.to_atom("pramana_foundry@#{hostname}")
  rescue
    _ -> nil
  end

  defp daemon_cookie do
    # Read from the prod release cookie file
    # (escript runs separately; needs same cookie as daemon)
    release_root =
      Path.join([
        File.cwd!(),
        "_build",
        "prod",
        "rel",
        "pramana_foundry"
      ])

    cookie_path = Path.join([release_root, "releases", "COOKIE"])

    case File.read(cookie_path) do
      {:ok, cookie} -> String.trim(cookie)
      _ -> nil
    end
  rescue
    _ -> nil
  end

  # ===================================================================
  # GenServer Callbacks
  # ===================================================================

  @impl true
  def init(opts) do
    coordinator = Keyword.get(opts, :coordinator, Coordinator)
    refresh_ms = Keyword.get(opts, :refresh_interval_ms, 1000)
    width = Keyword.get(opts, :width, 120)
    height = Keyword.get(opts, :height, 30)

    view_state = ViewState.new(width: width, height: height)
    data = fetch_coordinator_data(coordinator, opts)
    findings = FindingsPanel.fetch_findings()

    timer_ref =
      if refresh_ms > 0 do
        schedule_refresh(refresh_ms)
      else
        nil
      end

    {:ok,
     %{
       coordinator: coordinator,
       refresh_interval_ms: refresh_ms,
       timer_ref: timer_ref,
       view_state: view_state,
       data: data,
       findings: findings,
       live_screen_initialized?: false,
       opts: opts
     }}
  end

  @impl true
  def handle_call({:handle_key, key}, _from, state) do
    case ViewState.handle_key(state.view_state, key, state.data) do
      {:ok, new_vs} ->
        # If 'r' key pressed, reload data immediately
        new_data =
          if key in ["r", "R"] do
            fetch_coordinator_data(state.coordinator, state.opts)
          else
            state.data
          end

        new_state = %{state | view_state: new_vs, data: new_data}
        width = Owl.IO.columns() || 120
        Owl.LiveScreen.update(:kanban, View.render_kanban(new_state.view_state, new_data, width))
        {:reply, {:ok, new_vs}, new_state}

      {:quit, new_vs} ->
        {:reply, {:quit, new_vs}, %{state | view_state: new_vs}}
    end
  end

  def handle_call({:resize, width, height}, _from, state) do
    new_vs = ViewState.resize(state.view_state, width, height)
    new_state = %{state | view_state: new_vs}
    width = Owl.IO.columns() || 120

    Owl.LiveScreen.update(
      :kanban,
      View.render_kanban(new_state.view_state, new_state.data, width)
    )

    {:reply, :ok, new_state}
  end

  def handle_call(:refresh, _from, state) do
    new_data = fetch_coordinator_data(state.coordinator, state.opts)
    new_findings = FindingsPanel.fetch_findings()
    new_state = %{state | data: new_data, findings: new_findings}
    push_live_screen(new_state)
    {:reply, :ok, new_state}
  end

  def handle_call(:render_frame, _from, state) do
    width = Owl.IO.columns() || 120

    frame =
      View.render_frame(state.view_state, state.data, width)
      |> Owl.Data.to_chardata()
      |> IO.chardata_to_string()

    {:reply, frame, state}
  end

  def handle_call(:render_lines, _from, state) do
    width = Owl.IO.columns() || 120
    height = state.view_state.height || 30

    raw_lines =
      View.render_frame(state.view_state, state.data, width)
      |> Owl.Data.to_chardata()
      |> IO.chardata_to_string()
      |> String.split("\n")

    # Pad or trim to expected height
    lines =
      (raw_lines ++
         List.duplicate(String.duplicate(" ", width), max(0, height - length(raw_lines))))
      |> Enum.take(height)

    {:reply, lines, state}
  end

  def handle_call(:view_state, _from, state) do
    {:reply, state.view_state, state}
  end

  def handle_call(:get_data, _from, state) do
    {:reply, state.data, state}
  end

  def handle_call(:mark_live_screen_initialized, _from, state) do
    {:reply, :ok, %{state | live_screen_initialized?: true}}
  end

  @impl true
  def handle_info(:refresh_tick, state) do
    new_data = fetch_coordinator_data(state.coordinator, state.opts)
    new_findings = FindingsPanel.fetch_findings()
    new_state = %{state | data: new_data, findings: new_findings}

    # Push to LiveScreen if initialized (not in daemon mode)
    if state.live_screen_initialized? do
      push_live_screen(new_state)
    end

    new_timer = schedule_refresh(state.refresh_interval_ms)
    {:noreply, %{new_state | timer_ref: new_timer}}
  end

  def handle_info(_other, state), do: {:noreply, state}

  @impl true
  def handle_cast({:key_input, key}, state) do
    case ViewState.handle_key(state.view_state, key, state.data) do
      {:ok, new_vs} ->
        new_data =
          if key in ["r", "R"] do
            fetch_coordinator_data(state.coordinator, state.opts)
          else
            state.data
          end

        new_state = %{
          state
          | view_state: new_vs,
            data: new_data,
            findings: FindingsPanel.fetch_findings()
        }

        push_live_screen(new_state)
        {:noreply, new_state}

      {:quit, _new_vs} ->
        # Quit handled in interactive_loop, not here
        {:noreply, state}
    end
  end

  # ===================================================================
  # Pure Functional Helpers & Domain Logic
  # ===================================================================

  @doc """
  Returns the canonical list of board columns.
  """
  def columns, do: @columns

  @doc """
  Maps a raw status to one of the 8 canonical columns.
  """
  @spec status_column(term()) :: String.t()
  def status_column(raw_status) do
    case to_string(raw_status) do
      s when s in ["backlog", "planned", "backlog_planned", "proposed", "proposal"] ->
        "Backlog/Planned"

      s when s in ["queued"] ->
        "Queued"

      s
      when s in [
             "dispatched",
             "prompting",
             "working",
             "checkout_intent",
             "starting",
             "correction_intent",
             "correction_waiting",
             "correction_prompting",
             "correcting",
             "queued_correction",
             "dispatch_intent"
           ] ->
        "Working"

      s when s in ["handoff_received", "review_intent", "review_prompting", "reviewing"] ->
        "Review"

      s when s in ["approved", "review_approved", "integrating", "checking"] ->
        "Integration"

      s when s in ["accepted", "promoted", "integrated"] ->
        "Accepted"

      s when s in ["cooldown", "provider_cooled"] ->
        "Cooldown"

      s when s in ["parked", "stale", "blocked", "cancelled"] ->
        "Parked"

      _ ->
        "Parked"
    end
  end

  @doc """
  Deterministically turns a task ID into a concise human-readable card title.
  """
  @spec card_title(String.t()) :: String.t()
  def card_title(task_id) when is_binary(task_id) do
    parts =
      task_id
      |> String.split(~r/[-_\s]+/)
      |> Enum.reject(&(&1 == ""))

    # Strip trailing digits / version numbers
    stripped = drop_trailing_digits(parts)

    title =
      if Enum.empty?(stripped) do
        task_id
      else
        Enum.join(stripped, " ")
      end

    String.slice(title, 0, 28)
  end

  def card_title(other), do: to_string(other)

  defp drop_trailing_digits([]), do: []

  defp drop_trailing_digits(parts) do
    last = List.last(parts)

    if Regex.match?(~r/^\d+$/, last) do
      drop_trailing_digits(Enum.slice(parts, 0, length(parts) - 1))
    else
      parts
    end
  end

  @doc """
  Deterministically extracts the first meaningful outcome line as a one-line summary.
  """
  @spec card_summary(String.t() | nil, String.t()) :: String.t()
  def card_summary(outcome, task_id \\ "")

  def card_summary(nil, task_id), do: task_id || ""
  def card_summary("", task_id), do: task_id || ""

  def card_summary(outcome, task_id) when is_binary(outcome) do
    lines =
      outcome
      |> String.split("\n")
      |> Enum.map(&String.trim/1)

    find_first_summary(lines, false, task_id)
  end

  defp find_first_summary([], _in_code, task_id), do: task_id || ""

  defp find_first_summary([line | rest], in_code, task_id) do
    cond do
      String.starts_with?(line, "```") ->
        find_first_summary(rest, not in_code, task_id)

      in_code ->
        find_first_summary(rest, true, task_id)

      true ->
        cleaned =
          line
          |> String.replace(~r/^[-*•\s]+/, "")
          |> String.trim()

        if cleaned == "" or String.starts_with?(cleaned, "#") or
             String.starts_with?(String.downcase(cleaned), "outcome:") do
          find_first_summary(rest, false, task_id)
        else
          String.slice(cleaned, 0, 120)
        end
    end
  end

  @doc """
  Builds a ticket record map from an assignment or raw ticket.
  """
  @spec build_ticket(map(), map()) :: map()
  def build_ticket(assignment_or_ticket, state \\ %{}) do
    ticket = Map.get(assignment_or_ticket, "ticket", assignment_or_ticket)
    task_id = Map.get(ticket, "task_id") || Map.get(assignment_or_ticket, "task_id", "UNKNOWN")
    raw_status = Map.get(assignment_or_ticket, "status") || Map.get(ticket, "status", "queued")
    sched_status = get_in(assignment_or_ticket, ["scheduling_decision", "status"])

    profile =
      Map.get(ticket, "profile") ||
        Map.get(assignment_or_ticket, "configured_profile") || ""

    cooldowns = Map.get(state, "provider_cooldowns", %{})
    cooled? = active_cooldown?(cooldowns, profile)

    col =
      cond do
        raw_status == "cooldown" -> "Cooldown"
        sched_status == "cooldown" -> "Cooldown"
        raw_status == "queued" and cooled? -> "Cooldown"
        true -> status_column(raw_status)
      end

    outcome =
      get_in(assignment_or_ticket, ["handoff", "outcome"]) ||
        Map.get(ticket, "outcome") || ""

    %{
      task_id: task_id,
      title: card_title(task_id),
      summary: card_summary(outcome, task_id),
      status: col,
      raw_status: raw_status,
      priority: Map.get(ticket, "priority"),
      workload: Map.get(ticket, "workload", "standard"),
      risk: Map.get(ticket, "risk") || Map.get(ticket, "work_class"),
      model: Map.get(ticket, "model") || Map.get(assignment_or_ticket, "configured_model"),
      profile: profile,
      base_revision: Map.get(ticket, "base_revision") || Map.get(state, "accepted_revision"),
      dependencies: Map.get(ticket, "dependencies", []),
      required_checks: Map.get(ticket, "required_checks", []),
      outcome: outcome,
      blocker:
        Map.get(assignment_or_ticket, "blocker") ||
          get_in(assignment_or_ticket, ["handoff", "reason"]),
      diagnostics: get_in(assignment_or_ticket, ["handoff", "diagnostic_evidence"]) || [],
      run_id: Map.get(assignment_or_ticket, "run_id"),
      role: Map.get(assignment_or_ticket, "role"),
      candidate_commit:
        Map.get(assignment_or_ticket, "candidate_commit") ||
          get_in(assignment_or_ticket, ["handoff", "commit"]),
      handoff: Map.get(assignment_or_ticket, "handoff"),
      review: Map.get(assignment_or_ticket, "review")
    }
  end

  @doc """
  Loads board data from a coordinator state map or coordinator process.
  """
  @spec load_data(map() | pid() | atom(), keyword()) :: map()
  def load_data(source, opts \\ [])

  def load_data(coord, opts) when is_atom(coord) or is_pid(coord) do
    fetch_coordinator_data(coord, opts)
  end

  def load_data(%{} = state, opts) do
    assignments = Map.get(state, "assignments", %{})
    queue = Map.get(state, "queue", [])

    assignment_tickets =
      Enum.map(assignments, fn {_task_id, assignment} ->
        build_ticket(assignment, state)
      end)

    assigned_task_ids = Map.keys(assignments)

    # Tickets in queue without assignments
    queue_tickets =
      queue
      |> Enum.reject(&(&1 in assigned_task_ids))
      |> Enum.map(fn task_id ->
        build_ticket(%{"task_id" => task_id, "status" => "queued"}, state)
      end)

    # Proposals or backlog if present
    backlog_raw =
      Map.get(state, "backlog", []) ++
        Map.get(state, "planned", []) ++
        Map.get(state, "proposals", [])

    backlog_tickets =
      Enum.map(backlog_raw, fn item ->
        build_ticket(Map.put(item, "status", "backlog"), state)
      end)

    all_tickets = assignment_tickets ++ queue_tickets ++ backlog_tickets

    accepted = Map.get(state, "accepted_revision")

    runtime =
      Keyword.get(opts, :runtime_implementation_revision) ||
        Report.runtime_implementation_revision()

    revisions_match? = accepted == runtime

    active_workers_cnt =
      Enum.count(all_tickets, fn t -> t[:status] == "Working" end)

    %{
      tickets: all_tickets,
      accepted_revision: accepted,
      runtime_implementation_revision: runtime,
      revisions_match?: revisions_match?,
      paused: Map.get(state, "paused", false),
      stop_requested: Map.get(state, "stop_requested", false),
      active_workers_count: active_workers_cnt,
      pm_status: get_in(state, ["pm", "status"]) || "idle",
      node: to_string(Node.self()),
      updated_at: Map.get(state, "updated_at")
    }
  end

  @doc """
  Renders a view state and data map using View.
  """
  def render(view_state, data), do: View.render_frame(view_state, data)

  # ===================================================================
  # Private Helpers
  # ===================================================================

  defp fetch_coordinator_data(coordinator, opts) do
    try do
      state =
        cond do
          coordinator == :event_log ->
            rebuild_from_event_log()

          is_pid(coordinator) ->
            try do
              GenServer.call(coordinator, :state)
            rescue
              _ -> %{}
            end

          is_atom(coordinator) and Process.whereis(coordinator) != nil ->
            coordinator.state()

          true ->
            rebuild_from_event_log()
        end

      load_data(state, opts)
    rescue
      _e ->
        # Safe fault recovery: return empty data with diagnostics
        %{
          tickets: [],
          accepted_revision: nil,
          runtime_implementation_revision: Report.runtime_implementation_revision(),
          revisions_match?: true,
          paused: false,
          stop_requested: false,
          active_workers_count: 0,
          pm_status: "idle",
          node: to_string(Node.self()),
          updated_at: nil
        }
    end
  end

  defp rebuild_from_event_log do
    root = PramanaFoundry.RuntimeRoot.fetch!()

    events_path = Path.join(root, "state/current/events.jsonl")

    case File.read(events_path) do
      {:ok, bytes} ->
        records =
          bytes
          |> String.split("\n", trim: true)
          |> Enum.map(&safe_json_decode/1)
          |> Enum.reject(&is_nil/1)

        case PramanaFoundry.Transition.rebuild(records) do
          {:ok, projection} -> projection
          _ -> %{}
        end

      _ ->
        %{}
    end
  end

  defp safe_json_decode(line) do
    :json.decode(line)
  rescue
    _ -> nil
  end

  defp active_cooldown?(cooldowns, profile) when is_map(cooldowns) and is_binary(profile) do
    now = System.system_time(:second)

    case Map.get(cooldowns, profile) do
      %{"until_epoch" => until_epoch} when until_epoch > now -> true
      _ -> false
    end
  end

  defp active_cooldown?(_cooldowns, _profile), do: false

  defp schedule_refresh(ms) when is_integer(ms) and ms > 0 do
    Process.send_after(self(), :refresh_tick, ms)
  end

  defp schedule_refresh(_), do: nil

  defp tty? do
    try do
      IO.ANSI.enabled?() and System.get_env("TERM") not in [nil, "dumb", ""]
    rescue
      _ -> false
    end
  end

  defp push_live_screen(state) do
    width = Owl.IO.columns() || 120
    kanban_view = View.render_kanban(state.view_state, state.data, width)
    findings_view = FindingsPanel.render_findings(state.findings, width)

    Owl.LiveScreen.update(:kanban, kanban_view)
    Owl.LiveScreen.update(:findings, findings_view)
  end

  defp setup_live_screen(state) do
    # Add LiveScreen blocks with identity render (we pre-render before pushing)
    Owl.LiveScreen.add_block(:kanban,
      state: "",
      render: fn data -> data end
    )

    Owl.LiveScreen.add_block(:findings,
      state: "",
      render: fn data -> data end
    )

    push_live_screen(state)
  end

  defp run_interactive(pid) do
    # Clear screen and set up Owl.LiveScreen
    IO.write(IO.ANSI.clear() <> IO.ANSI.home())

    # Get state from board and set up LiveScreen blocks
    state_data = GenServer.call(pid, :get_data)
    state_vs = GenServer.call(pid, :view_state)
    state_findings = PramanaFoundry.Board.FindingsPanel.fetch_findings()

    setup_live_screen(%{view_state: state_vs, data: state_data, findings: state_findings})

    # Mark LiveScreen as initialized in the GenServer
    GenServer.call(pid, :mark_live_screen_initialized)

    interactive_loop(pid)
  end

  defp read_key do
    case IO.getn("", 1) do
      "\e" ->
        case IO.getn("", 1) do
          "[" ->
            case IO.getn("", 1) do
              "A" -> :up
              "B" -> :down
              "C" -> :right
              "D" -> :left
              other -> {:escape, "[#{other}"}
            end

          "O" ->
            case IO.getn("", 1) do
              "A" -> :up
              "B" -> :down
              "C" -> :right
              "D" -> :left
              other -> {:escape, "O#{other}"}
            end

          other ->
            {:escape, other}
        end

      char ->
        char
    end
  end

  defp normalize_key(:up), do: "k"
  defp normalize_key(:down), do: "j"
  defp normalize_key(:left), do: "h"
  defp normalize_key(:right), do: "l"
  defp normalize_key("\r"), do: "\r"
  defp normalize_key("\n"), do: "\r"
  defp normalize_key(key) when is_binary(key), do: key

  defp interactive_loop(pid) do
    key = read_key()

    case key do
      "q" ->
        Owl.LiveScreen.flush()
        close(pid)
        :ok

      "Q" ->
        Owl.LiveScreen.flush()
        close(pid)
        :ok

      _ ->
        normalized = normalize_key(key)
        GenServer.cast(pid, {:key_input, normalized})
        interactive_loop(pid)
    end
  end
end
