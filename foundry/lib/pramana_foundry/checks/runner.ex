defmodule PramanaFoundry.Checks.Runner do
  @moduledoc """
  Runs a check as an OS process outside any coordinator callback, the same boundary
  `PramanaFoundry.Fence` already uses for the singleton lock: a small stdlib-only
  Python trampoline is spawned as an independent OS process, so a BEAM crash orphans
  it rather than killing it. The trampoline starts the check in its own session (its
  own process group), durably publishes the child's pid the moment it is known, keeps
  watching for a cancellation file, and durably records the exit code the moment the
  check exits -- all without depending on the coordinator being alive to observe it.

  This module only spawns and observes. Deadline precedence, adoption, and stale-pid
  refusal live in `PramanaFoundry.Checks.Status`, `PramanaFoundry.Checks.Adoption`,
  and `PramanaFoundry.Effects.ProcessGroup`, which read the same durable files.
  """

  alias PramanaFoundry.AtomicFile
  alias PramanaFoundry.Effects.ProcessGroup

  @child_poll_interval_ms 20
  @default_launch_timeout_ms 5_000
  @redacted "[redacted]"

  @worker_script """
  import contextlib, json, os, signal, subprocess, sys, time


  def atomic_json(path, value):
      directory = os.path.dirname(path) or "."
      tmp = os.path.join(directory, ".{}.{}.tmp".format(os.path.basename(path), os.getpid()))
      with open(tmp, "w", encoding="utf-8") as stream:
          json.dump(value, stream)
          stream.flush()
          os.fsync(stream.fileno())
      os.replace(tmp, path)
      directory_fd = os.open(directory, os.O_RDONLY)
      try:
          os.fsync(directory_fd)
      finally:
          os.close(directory_fd)


  def read_json(path):
      try:
          with open(path, encoding="utf-8") as stream:
              return json.load(stream)
      except FileNotFoundError:
          return None


  def cancellation_matches(cancellation_path, token):
      request = read_json(cancellation_path)
      return isinstance(request, dict) and request.get("launch_token") == token


  spec = json.load(open(sys.argv[1], encoding="utf-8"))
  token = spec["launch_token"]
  command = spec["command"]
  cwd = spec["cwd"]
  environment = spec["environment"]
  identity_path = spec["identity_path"]
  completion_path = spec["completion_path"]
  cancellation_path = spec["cancellation_path"]
  output_path = spec["output_path"]

  os.makedirs(os.path.dirname(output_path) or ".", exist_ok=True)
  with open(output_path, "ab", buffering=0) as output:
      child = subprocess.Popen(
          command,
          cwd=cwd,
          env={**os.environ, **environment},
          stdin=subprocess.DEVNULL,
          stdout=output,
          stderr=subprocess.STDOUT,
          start_new_session=True,
      )
      atomic_json(identity_path, {"launch_token": token, "child_pid": child.pid})

      returncode = None
      while returncode is None:
          if cancellation_matches(cancellation_path, token):
              with contextlib.suppress(ProcessLookupError):
                  os.killpg(os.getpgid(child.pid), signal.SIGTERM)
          returncode = child.poll()
          if returncode is None:
              time.sleep(0.02)

  atomic_json(completion_path, {
      "launch_token": token,
      "returncode": returncode,
      "completed_at": time.time(),
  })
  """

  @type spec :: %{
          required(:launch_token) => binary(),
          required(:command) => [binary()],
          required(:cwd) => binary(),
          required(:env) => %{optional(binary()) => binary()},
          required(:spec_path) => Path.t(),
          required(:identity_path) => Path.t(),
          required(:completion_path) => Path.t(),
          required(:cancellation_path) => Path.t(),
          required(:output_path) => Path.t()
        }

  @spec launch(spec()) :: {:ok, port()} | {:error, term()}
  def launch(spec) do
    with :ok <- write_spec(spec),
         {:ok, python} <- python_executable() do
      port =
        Port.open(
          {:spawn_executable, python},
          [:binary, :exit_status, args: ["-c", @worker_script, spec.spec_path]]
        )

      {:ok, port}
    end
  end

  @doc "Blocks until the trampoline has published the child's pid, or `:launch_timeout`."
  @spec await_child_pid(spec(), non_neg_integer()) :: {:ok, pos_integer()} | {:error, term()}
  def await_child_pid(spec, timeout_ms \\ @default_launch_timeout_ms) do
    await_child_pid(spec, timeout_ms, System.monotonic_time(:millisecond))
  end

  defp await_child_pid(spec, timeout_ms, started_at) do
    case read_json(spec.identity_path) do
      {:ok, %{"launch_token" => token, "child_pid" => pid}} when token == spec.launch_token ->
        {:ok, pid}

      _ ->
        if System.monotonic_time(:millisecond) - started_at >= timeout_ms do
          {:error, :launch_timeout}
        else
          Process.sleep(@child_poll_interval_ms)
          await_child_pid(spec, timeout_ms, started_at)
        end
    end
  end

  @spec read_completion(spec()) :: {:ok, map()} | {:error, term()}
  def read_completion(spec), do: read_json(spec.completion_path)

  @doc """
  Best-effort cooperative cancellation (the live trampoline notices within one poll
  interval) plus a direct process-group signal re-verified against `identity`, so stop
  is effective whether or not the original trampoline is still alive to see the file.
  """
  @spec terminate(spec(), ProcessGroup.identity(), binary()) :: :ok | {:error, term()}
  def terminate(spec, identity, reason) do
    _ =
      AtomicFile.write(spec.cancellation_path, %{
        "launch_token" => spec.launch_token,
        "reason" => reason,
        "requested_at" => DateTime.to_iso8601(DateTime.utc_now())
      })

    case ProcessGroup.signal(identity, :sigterm) do
      :ok ->
        :ok

      {:error, :stale_identity} ->
        # The trampoline's own poll loop watches the same cancellation file and may
        # have already killed the group itself within the interval between the write
        # above and this signal -- the exact outcome this call exists to produce, not
        # a failure. Only when the pid is confirmed still occupied (a genuine
        # replacement owner, not a caller-verified identity that just finished
        # exiting because our own cancellation succeeded) is this still refused.
        if ProcessGroup.gone?(identity), do: :ok, else: {:error, :stale_identity}

      other ->
        other
    end
  end

  @doc "Redacts environment values for durable checkpoint evidence; keys are preserved."
  @spec sanitize_env(%{optional(binary()) => binary()}) :: %{optional(binary()) => binary()}
  def sanitize_env(env) when is_map(env),
    do: Map.new(env, fn {key, _value} -> {key, @redacted} end)

  defp write_spec(spec) do
    AtomicFile.write(spec.spec_path, %{
      "launch_token" => spec.launch_token,
      "command" => spec.command,
      "cwd" => spec.cwd,
      "environment" => spec.env,
      "identity_path" => spec.identity_path,
      "completion_path" => spec.completion_path,
      "cancellation_path" => spec.cancellation_path,
      "output_path" => spec.output_path
    })
  end

  defp python_executable do
    case System.find_executable("python3") do
      nil -> {:error, :python_not_found}
      path -> {:ok, path}
    end
  end

  defp read_json(path) do
    with {:ok, bytes} <- File.read(path),
         true <- String.valid?(bytes) do
      decode(bytes)
    else
      false -> {:error, :invalid_utf8}
      {:error, _reason} = error -> error
    end
  end

  defp decode(bytes) do
    {:ok, :json.decode(bytes)}
  rescue
    _ -> {:error, :malformed_json}
  catch
    _, _ -> {:error, :malformed_json}
  end
end
