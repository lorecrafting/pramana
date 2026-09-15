defmodule PramanaFoundry.Effects.ProcessGroup do
  @moduledoc """
  OS process-group identity and signalling. A BEAM monitor only ever observes a Port's
  immediate OS pid, never the descendants a check spawns underneath it, and a bare pid
  can be silently reused by an unrelated process after exit. `identity/1` captures
  pid, parent pid, process-group id, start time, and command the same way the Python
  supervisor does (`ps -o pid=,ppid=,pgid=,lstart=,command=`); `signal/2` re-verifies
  that exact identity immediately before sending, and a stale, reused, or
  replacement-owner pid is refused rather than signalled.
  """

  @type identity :: %{
          pid: pos_integer(),
          parent_pid: non_neg_integer(),
          process_group_id: pos_integer(),
          started_at: binary(),
          command: binary()
        }

  @identity_fields [:pid, :process_group_id, :started_at, :command]

  @spec identity(pos_integer()) :: {:ok, identity()} | {:error, term()}
  def identity(pid) when is_integer(pid) and pid > 0 do
    case System.cmd(
           "ps",
           ["-ww", "-o", "pid=,ppid=,pgid=,lstart=,command=", "-p", Integer.to_string(pid)],
           stderr_to_stdout: true
         ) do
      {output, 0} -> parse(output)
      {_output, _status} -> {:error, :not_found}
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
  def signal(%{pid: pid, process_group_id: pgid} = expected, signal)
      when signal in [:sigterm, :sigkill] do
    case identity(pid) do
      {:ok, actual} ->
        if same_process?(expected, actual) do
          send_group_signal(pid, pgid, signal)
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
  defp send_group_signal(pid, pgid, signal) do
    flag = if signal == :sigterm, do: "-TERM", else: "-KILL"

    case System.cmd("kill", [flag, "-#{pgid}"], stderr_to_stdout: true) do
      {_output, 0} ->
        :ok

      {_output, status} ->
        if gone?(pid), do: :ok, else: {:error, {:kill_failed, status}}
    end
  end

  @doc false
  # A process that has exited but not yet been reaped by its parent stays visible to
  # `ps -p` as `<defunct>` for a brief window -- long enough for a racing caller to
  # observe it. Treat a zombie the same as an absent pid: gone, for signalling purposes.
  @spec gone?(pos_integer()) :: boolean()
  def gone?(pid) do
    case identity(pid) do
      {:error, :not_found} ->
        true

      {:ok, %{command: command}} when is_binary(command) ->
        String.contains?(command, "defunct")

      _ ->
        false
    end
  end

  defp parse(output) do
    case output |> String.trim() |> String.split(~r/\s+/, parts: 9) do
      [pid, ppid, pgid, w1, w2, w3, w4, w5, command] ->
        with {pid, ""} <- Integer.parse(pid),
             {ppid, ""} <- Integer.parse(ppid),
             {pgid, ""} <- Integer.parse(pgid) do
          {:ok,
           %{
             pid: pid,
             parent_pid: ppid,
             process_group_id: pgid,
             started_at: Enum.join([w1, w2, w3, w4, w5], " "),
             command: command
           }}
        else
          _ -> {:error, :unparsable_process_identity}
        end

      _ ->
        {:error, :unparsable_process_identity}
    end
  end
end
