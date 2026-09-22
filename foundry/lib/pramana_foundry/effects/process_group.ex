defmodule PramanaFoundry.Effects.ProcessGroup do
  @moduledoc """
  OS process-group identity and signalling. A BEAM monitor only ever observes a Port's
  immediate OS pid, never the descendants a check spawns underneath it, and a bare pid
  can be silently reused by an unrelated process after exit. `identity/1` captures
  pid, parent pid, process-group id, start time, process state, and command the same way
  the Python supervisor does (`ps -o pid=,ppid=,pgid=,lstart=,state=,command=`);
  `signal/2` re-verifies that exact identity immediately before sending, and a stale, reused, or
  replacement-owner pid is refused rather than signalled.
  """

  @type identity :: %{
          pid: pos_integer(),
          parent_pid: non_neg_integer(),
          process_group_id: pos_integer(),
          started_at: binary(),
          state: binary(),
          command: binary()
        }
  @type presence :: :gone | :present | :unknown

  @identity_fields [:pid, :process_group_id, :started_at, :command]
  @incarnation_fields [:pid, :process_group_id, :started_at]

  @spec identity(pos_integer()) :: {:ok, identity()} | {:error, term()}
  def identity(pid) when is_integer(pid) and pid > 0 do
    case System.cmd(
           "ps",
           [
             "-ww",
             "-o",
             "pid=,ppid=,pgid=,lstart=,state=,command=",
             "-p",
             Integer.to_string(pid)
           ],
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        parse(output)

      {output, 1} ->
        if String.trim(output) == "", do: {:error, :not_found}, else: {:error, {:ps_failed, 1}}

      {_output, status} ->
        {:error, {:ps_failed, status}}
    end
  rescue
    ErlangError -> {:error, :ps_unavailable}
  end

  def identity(_pid), do: {:error, :invalid_pid}

  @doc "True only when pid, process group, start time, and command all agree exactly."
  @spec same_process?(identity(), identity()) :: boolean()
  def same_process?(expected, actual) when is_map(expected) and is_map(actual) do
    Map.take(expected, @identity_fields) == Map.take(actual, @identity_fields)
  end

  def same_process?(_expected, _actual), do: false

  @doc """
  Sends `signal` to the whole process group, but only after re-reading the pid's live
  identity and confirming it still matches `expected`. A stale pid (exited and reused),
  a replacement owner, or a pid whose group changed is refused rather than signalled.
  """
  @spec signal(identity(), :sigterm | :sigkill) :: :ok | {:error, term()}
  def signal(expected, signal), do: signal(expected, signal, &identity/1, &System.cmd/3)

  @doc false
  @spec signal(
          identity(),
          :sigterm | :sigkill,
          (pos_integer() -> {:ok, identity()} | {:error, term()}),
          (binary(), [binary()], keyword() -> {binary(), non_neg_integer()})
        ) ::
          :ok | {:error, term()}
  def signal(
        %{pid: pid, process_group_id: pgid} = expected,
        signal,
        identity_reader,
        command_runner
      )
      when signal in [:sigterm, :sigkill] do
    case identity_reader.(pid) do
      {:ok, actual} ->
        if same_process?(expected, actual) do
          send_group_signal(expected, pgid, signal, identity_reader, command_runner)
        else
          {:error, :stale_identity}
        end

      {:error, :not_found} ->
        {:error, :stale_identity}

      {:error, _reason} = error ->
        error
    end
  end

  @doc false
  # A cooperating check process (the checks trampoline) may itself notice a
  # cancellation request and exit its own group at essentially the same moment this
  # signal is sent. When that race wins, `kill` reports "no such process" for a group
  # that no longer exists -- the same outcome this call exists to produce, not a
  # failure to report. Only a `kill` failure over a group whose leader is still alive
  # afterward is a genuine signalling failure (e.g. permission denied).
  defp send_group_signal(expected, pgid, signal, identity_reader, command_runner) do
    flag = if signal == :sigterm, do: "-TERM", else: "-KILL"

    case command_runner.("kill", [flag, "-#{pgid}"], stderr_to_stdout: true) do
      {_output, 0} ->
        :ok

      {_output, status} ->
        if gone?(expected, identity_reader), do: :ok, else: {:error, {:kill_failed, status}}
    end
  end

  @doc false
  # A process that has exited but not yet been reaped by its parent stays visible with
  # process state `Z`. Treat that state like an absent pid only when the immutable parts
  # of the observed identity still match the caller-bound incarnation. Command text is
  # deliberately not process-state evidence: a live argv may contain "defunct", while
  # a real zombie's displayed command may change after the expected identity was bound.
  @spec gone?(identity()) :: boolean()
  def gone?(expected), do: presence(expected) == :gone

  @doc false
  @spec gone?(identity(), (pos_integer() -> {:ok, identity()} | {:error, term()})) :: boolean()
  def gone?(expected, identity_reader) when is_function(identity_reader, 1) do
    presence(expected, identity_reader) == :gone
  end

  @doc "Observes only the bound leader identity; failures and mismatches remain unknown."
  @spec presence(identity()) :: presence()
  def presence(expected), do: presence(expected, &identity/1)

  @doc false
  @spec presence(identity(), (pos_integer() -> {:ok, identity()} | {:error, term()})) ::
          presence()
  def presence(%{pid: pid} = expected, identity_reader) when is_function(identity_reader, 1) do
    case identity_reader.(pid) do
      {:error, :not_found} ->
        :gone

      {:ok, %{state: state} = actual} when is_binary(state) ->
        cond do
          not same_incarnation?(expected, actual) -> :unknown
          String.starts_with?(state, "Z") -> :gone
          true -> :present
        end

      _ ->
        :unknown
    end
  end

  defp parse(output) do
    case output |> String.trim() |> String.split(~r/\s+/, parts: 10) do
      [pid, ppid, pgid, w1, w2, w3, w4, w5, state, command] ->
        with {pid, ""} <- Integer.parse(pid),
             {ppid, ""} <- Integer.parse(ppid),
             {pgid, ""} <- Integer.parse(pgid) do
          {:ok,
           %{
             pid: pid,
             parent_pid: ppid,
             process_group_id: pgid,
             started_at: Enum.join([w1, w2, w3, w4, w5], " "),
             state: state,
             command: command
           }}
        else
          _ -> {:error, :unparsable_process_identity}
        end

      _ ->
        {:error, :unparsable_process_identity}
    end
  end

  @doc """
  True when `actual` is the same process *incarnation* as `expected` — pid, process group
  and start time — regardless of what it is currently executing.

  Distinct from `same_process?/2`, which also compares `command`. A live process may change
  its `command` without becoming a different process: `/usr/bin/python3` re-execs into the
  framework Python, and `sh -c "<one command>"` tail-call-execs into that command. Measured
  through `Checks.Runner`, 5 of 12 launches read back a different `command` for the same pid,
  process group and start time — see `docs/fr-04/identity-drift-probe.exs`.

  So ask this when the question is "is the process I recorded still running", and
  `same_process?/2` when the question is "may I signal this", where the strictest available
  check is wanted and a false refusal is backstopped by the cancellation file.
  """
  @spec same_incarnation?(identity(), identity()) :: boolean()
  def same_incarnation?(expected, actual) when is_map(expected) and is_map(actual) do
    Map.take(expected, @incarnation_fields) == Map.take(actual, @incarnation_fields)
  end

  def same_incarnation?(_expected, _actual), do: false
end
