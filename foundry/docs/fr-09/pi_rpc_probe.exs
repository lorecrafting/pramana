#!/usr/bin/env elixir

# Provider-free checkpoint-F probe for the exact locally installed Pi executable.
# Uses disposable state, synthetic secrets, and a loopback-only HTTP fixture.

defmodule CheckpointF.FakeProvider do
  def start(parent) do
    {:ok, requests} = Agent.start_link(fn -> [] end)

    {:ok, listen} =
      :gen_tcp.listen(0, [
        :binary,
        packet: :raw,
        active: false,
        reuseaddr: true,
        ip: {127, 0, 0, 1}
      ])

    {:ok, {_address, port}} = :inet.sockname(listen)
    pid = spawn_link(fn -> accept_loop(listen, parent, requests) end)
    %{listen: listen, pid: pid, port: port, requests: requests}
  end

  def stop(server) do
    :gen_tcp.close(server.listen)
    Agent.stop(server.requests)
  end

  def requests(server), do: Agent.get(server.requests, &Enum.reverse/1)

  defp accept_loop(listen, parent, requests) do
    case :gen_tcp.accept(listen) do
      {:ok, socket} ->
        # Pi/Undici may open and close a speculative connection without a request.
        # Keep each connection failure isolated from the listener and probe process.
        spawn(fn -> serve(socket, parent, requests) end)
        accept_loop(listen, parent, requests)

      {:error, :closed} ->
        :ok
    end
  end

  defp serve(socket, parent, requests) do
    {headers, body} = receive_request(socket)
    parsed = :json.decode(body)
    slow? = String.contains?(body, "SLOW_ABORT")

    request = %{
      path: request_path(headers),
      authorization_ok: header(headers, "authorization") == "Bearer checkpoint-f-synthetic-key",
      model: parsed["model"],
      slow: slow?
    }

    Agent.update(requests, &[request | &1])
    if slow?, do: send(parent, :slow_request_seen)

    :ok =
      :gen_tcp.send(socket, [
        "HTTP/1.1 200 OK\r\n",
        "content-type: text/event-stream\r\n",
        "cache-control: no-cache\r\n",
        "connection: close\r\n\r\n"
      ])

    alive? =
      if slow? do
        Enum.reduce_while(1..100, true, fn _, _ ->
          Process.sleep(50)

          case :gen_tcp.send(socket, ": waiting\n\n") do
            :ok -> {:cont, true}
            {:error, _} -> {:halt, false}
          end
        end)
      else
        true
      end

    if alive? do
      initial = %{
        id: "checkpoint-f",
        object: "chat.completion.chunk",
        created: 0,
        model: "fixture-model",
        choices: [%{index: 0, delta: %{role: "assistant"}, finish_reason: nil}]
      }

      content = %{
        id: "checkpoint-f",
        object: "chat.completion.chunk",
        created: 0,
        model: "fixture-model",
        choices: [%{index: 0, delta: %{content: "fixture response"}, finish_reason: nil}]
      }

      final = %{
        id: "checkpoint-f",
        object: "chat.completion.chunk",
        created: 0,
        model: "fixture-model",
        choices: [%{index: 0, delta: %{}, finish_reason: "stop"}],
        usage: %{prompt_tokens: 7, completion_tokens: 2, total_tokens: 9}
      }

      chunks = if slow?, do: [initial, final], else: [initial, content, final]

      Enum.each(chunks, fn chunk ->
        :gen_tcp.send(socket, ["data: ", :json.encode(chunk), "\n\n"])
      end)

      :gen_tcp.send(socket, "data: [DONE]\n\n")
    end

    :gen_tcp.close(socket)
  end

  defp receive_request(socket, buffer \\ "") do
    case :binary.match(buffer, "\r\n\r\n") do
      {index, 4} ->
        header_size = index + 4
        <<headers::binary-size(^header_size), rest::binary>> = buffer
        content_length = headers |> header("content-length") |> String.to_integer()
        {headers, rest <> receive_exact(socket, content_length - byte_size(rest))}

      :nomatch ->
        case :gen_tcp.recv(socket, 0, 5_000) do
          {:ok, data} -> receive_request(socket, buffer <> data)
          {:error, :closed} -> exit(:normal)
        end
    end
  end

  defp receive_exact(_socket, remaining) when remaining <= 0, do: ""

  defp receive_exact(socket, remaining) do
    {:ok, data} = :gen_tcp.recv(socket, remaining, 5_000)
    data <> receive_exact(socket, remaining - byte_size(data))
  end

  defp request_path(headers) do
    headers
    |> String.split("\r\n", parts: 2)
    |> hd()
    |> String.split(" ")
    |> Enum.at(1)
  end

  defp header(headers, wanted) do
    headers
    |> String.split("\r\n")
    |> Enum.find_value(fn line ->
      case String.split(line, ":", parts: 2) do
        [name, value] ->
          if String.downcase(name) == wanted, do: String.trim(value)

        _ ->
          nil
      end
    end)
  end
end

defmodule CheckpointF.RPC do
  @fixed_path "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

  def start(root, endpoint, extra_args \\ []) do
    config = Path.join(root, "controlled-config")
    sessions = Path.join(root, "controlled-sessions")
    workspace = Path.join(root, "workspace")
    File.mkdir_p!(config)
    File.mkdir_p!(sessions)
    File.mkdir_p!(workspace)

    models = %{
      providers: %{
        "checkpoint-f" => %{
          baseUrl: endpoint,
          api: "openai-completions",
          apiKey: "checkpoint-f-synthetic-key",
          authHeader: true,
          models: [
            %{
              id: "fixture-model",
              reasoning: false,
              contextWindow: 8192,
              maxTokens: 128,
              cost: %{input: 0, output: 0, cacheRead: 0, cacheWrite: 0}
            }
          ]
        }
      }
    }

    File.write!(Path.join(config, "models.json"), :json.encode(models))
    synthetic_home = Path.join(root, "ambient-home")
    File.mkdir_p!(synthetic_home)

    owned_paths = owned_paths(root)
    Enum.each(owned_paths, fn {_name, path} -> File.mkdir_p!(path) end)

    fd_source = Path.join(root, "synthetic-fd-secret")
    File.write!(fd_source, "synthetic-explicit-extension-fd")

    env = [
      {"HOME", synthetic_home},
      {"PATH", @fixed_path},
      {"TMPDIR", owned_paths.tmp},
      {"TMP", owned_paths.tmp},
      {"TEMP", owned_paths.tmp},
      {"XDG_CACHE_HOME", owned_paths.xdg_cache},
      {"XDG_CONFIG_HOME", owned_paths.xdg_config},
      {"XDG_DATA_HOME", owned_paths.xdg_data},
      {"XDG_STATE_HOME", owned_paths.xdg_state},
      {"NPM_CONFIG_CACHE", owned_paths.npm_cache},
      {"PI_CODING_AGENT_DIR", config},
      {"PI_CODING_AGENT_SESSION_DIR", sessions},
      {"PI_OFFLINE", "1"},
      {"PI_TELEMETRY", "0"},
      {"CHECKPOINT_F_INHERITED_SECRET", "synthetic-env-secret"},
      {"CHECKPOINT_F_FD_PATH", fd_source},
      {"LANG", "C.UTF-8"}
    ]

    args = [
      "--mode",
      "rpc",
      "--provider",
      "checkpoint-f",
      "--model",
      "fixture-model",
      "--session-dir",
      sessions,
      "--session-id",
      "11111111-1111-4111-8111-111111111111",
      "--name",
      "checkpoint-f-fixture",
      "--no-tools",
      "--no-extensions",
      "--no-skills",
      "--no-prompt-templates",
      "--no-themes",
      "--no-context-files",
      "--no-approve",
      "--offline"
      | extra_args
    ]

    # The fixed wrapper opens one synthetic FD before replacing itself with exact Pi.
    # All variable values remain argv or quoted environment data, never shell fragments.
    wrapper = "exec 9<\"$CHECKPOINT_F_FD_PATH\"; exec /opt/homebrew/bin/pi \"$@\""

    clean_env_args = ["-i"] ++ Enum.map(env, fn {name, value} -> "#{name}=#{value}" end)

    port =
      Port.open({:spawn_executable, "/usr/bin/env"}, [
        :binary,
        :exit_status,
        {:line, 1_048_576},
        {:args, clean_env_args ++ ["/bin/sh", "-c", wrapper, "checkpoint-f" | args]},
        {:cd, workspace}
      ])

    %{port: port, workspace: workspace, config: config, sessions: sessions}
  end

  def owned_paths(root) do
    %{
      tmp: Path.join(root, "tmp"),
      xdg_cache: Path.join(root, "xdg/cache"),
      xdg_config: Path.join(root, "xdg/config"),
      xdg_data: Path.join(root, "xdg/data"),
      xdg_state: Path.join(root, "xdg/state"),
      npm_cache: Path.join(root, "npm-cache")
    }
  end

  def send_command(rpc, type, fields \\ %{}) do
    id = Map.get(fields, "id", random_id())
    payload = fields |> Map.put("id", id) |> Map.put("type", type)
    true = Port.command(rpc.port, [:json.encode(payload), "\n"])
    id
  end

  def wait_response(rpc, id, timeout \\ 30_000) do
    wait_for(rpc, fn item -> item["type"] == "response" and item["id"] == id end, timeout)
  end

  def wait_event(rpc, type, timeout \\ 30_000) do
    wait_for(rpc, fn item -> item["type"] == type end, timeout)
  end

  def close(rpc) do
    {:os_pid, pid} = Port.info(rpc.port, :os_pid)

    {_output, 0} =
      System.cmd("kill", ["-TERM", Integer.to_string(pid)], stderr_to_stdout: true)

    status = wait_exit(rpc.port, 5_000)
    if status not in [0, 143], do: raise("unexpected Pi close status: #{status}")
    wait_gone(pid, 50)
  end

  defp wait_exit(port, timeout) do
    receive do
      {^port, {:exit_status, status}} -> status
      {^port, {:data, _data}} -> wait_exit(port, timeout)
    after
      timeout -> raise "Pi did not exit after controller termination"
    end
  end

  defp wait_for(rpc, predicate, timeout, partial \\ "") do
    receive do
      {port, {:data, {:noeol, data}}} when port == rpc.port ->
        wait_for(rpc, predicate, timeout, partial <> data)

      {port, {:data, {:eol, data}}} when port == rpc.port ->
        item = :json.decode(partial <> data)
        if predicate.(item), do: item, else: wait_for(rpc, predicate, timeout)

      {port, {:exit_status, status}} when port == rpc.port ->
        raise "Pi exited before expected RPC item: #{status}"
    after
      timeout -> raise "timed out waiting for Pi RPC item"
    end
  end

  defp wait_gone(_pid, 0), do: raise("Pi process did not close")

  defp wait_gone(pid, attempts) do
    case System.cmd("kill", ["-0", Integer.to_string(pid)], stderr_to_stdout: true) do
      {_output, 0} ->
        Process.sleep(20)
        wait_gone(pid, attempts - 1)

      {_output, _status} ->
        :ok
    end
  end

  defp random_id do
    16 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)
  end
end

defmodule CheckpointF.Probe do
  alias CheckpointF.{FakeProvider, RPC}

  @repo Path.expand("../../..", __DIR__)
  @installed_pi_cache "/opt/homebrew/lib/node_modules/@earendil-works/pi-coding-agent/node_modules/.cache/jiti"
  @hostile_parent_environment %{
    "CHECKPOINT_F_PARENT_ONLY" => "must-not-reach-pi",
    "OPENAI_API_KEY" => "synthetic-hostile-openai",
    "ANTHROPIC_API_KEY" => "synthetic-hostile-anthropic",
    "HTTPS_PROXY" => "http://synthetic-hostile.invalid:9",
    "ALL_PROXY" => "socks5://synthetic-hostile.invalid:9",
    "http_proxy" => "http://synthetic-hostile.invalid:9",
    "SSH_AUTH_SOCK" => "/synthetic/hostile/ssh-agent.sock",
    "AWS_PROFILE" => "synthetic-hostile-profile",
    "GIT_ASKPASS" => "/synthetic/hostile/askpass",
    "HERDR_CONFIG_PATH" => "/synthetic/hostile/herdr.toml",
    "PRAMANA_OPERATOR_RUNTIME_ROOT" => "/synthetic/hostile/operator-root",
    "PI_PACKAGE_DIR" => "/synthetic/hostile/pi-packages",
    "NODE_OPTIONS" => "--no-warnings",
    "NPM_CONFIG_USERCONFIG" => "/synthetic/hostile/npmrc"
  }

  def run do
    # Replace any same-named parent values with synthetic sentinels without reading them.
    # The trusted /usr/bin/env -i boundary below must remove every one before Pi starts.
    Enum.each(@hostile_parent_environment, fn {name, value} -> System.put_env(name, value) end)

    server = FakeProvider.start(self())
    endpoint = "http://127.0.0.1:#{server.port}/v1"
    root = Path.join(System.tmp_dir!(), "checkpoint-f-pi-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    outside_before = outside_cache_snapshot()

    try do
      prepare_discovery_fixtures(root)
      rpc = RPC.start(root, endpoint)

      state = response!(rpc, "get_state")
      commands = response!(rpc, "get_commands")
      loaded_commands = get_in(commands, ["data", "commands"])
      assert(Enum.map(loaded_commands, & &1["name"]) == ["llama"], "unexpected commands")

      assert(
        get_in(hd(loaded_commands), ["sourceInfo", "path"]) == "<inline:llama.cpp>",
        "unexpected bundled command source"
      )

      refute_exists(Path.join(root, "ambient-extension-loaded"))
      refute_exists(Path.join(root, "project-extension-loaded"))

      prompt_id = RPC.send_command(rpc, "prompt", %{"message" => "LOCAL_FIXTURE_ONLY"})
      assert(RPC.wait_response(rpc, prompt_id)["success"] == true, "prompt rejected")
      RPC.wait_event(rpc, "agent_settled")
      stats = response!(rpc, "get_session_stats")
      assert(stats["success"] == true, "stats unavailable")

      slow_id = RPC.send_command(rpc, "prompt", %{"message" => "SLOW_ABORT"})
      assert(RPC.wait_response(rpc, slow_id)["success"] == true, "slow prompt rejected")

      receive do
        :slow_request_seen -> :ok
      after
        5_000 -> raise "loopback provider did not receive slow request"
      end

      assert(response!(rpc, "abort", 15_000)["success"] == true, "abort failed")
      assert(get_in(response!(rpc, "get_state"), ["data", "isStreaming"]) == false, "not idle")

      assert_bash(rpc, ~s(test "$CHECKPOINT_F_INHERITED_SECRET" = synthetic-env-secret))
      assert_bash(rpc, environment_assertion_command(root))
      assert_bash_fails(rpc, ~s|test "$(cat /dev/fd/9)" = synthetic-explicit-extension-fd|)
      assert_bash(rpc, "kill -0 #{System.pid()}")

      assert_bash(
        rpc,
        "cd #{shell_quote(@repo)} && " <>
          ~s|common=$(git rev-parse --path-format=absolute --git-common-dir) && test -r "$common/HEAD"|
      )

      docs = assert_bash(rpc, "cd #{shell_quote(@repo)} && elixir bin/check_docs.exs", 30_000)
      docs_result = docs |> get_in(["data", "output"]) |> result_line()

      session_id = get_in(state, ["data", "sessionId"])
      session_file = get_in(state, ["data", "sessionFile"])
      RPC.close(rpc)

      resumed = RPC.start(root, endpoint)
      resumed_state = response!(resumed, "get_state")
      assert(get_in(resumed_state, ["data", "sessionId"]) == session_id, "session ID changed")

      assert(
        get_in(resumed_state, ["data", "sessionFile"]) == session_file,
        "session file changed"
      )

      RPC.close(resumed)
      explicit_extension_probe(root, endpoint)
      assert_owned_jiti_cache(root)

      requests = FakeProvider.requests(server)
      assert(length(requests) == 2, "unexpected provider request count")
      assert(Enum.all?(requests, &(&1.path == "/v1/chat/completions")), "unexpected endpoint")
      assert(Enum.all?(requests, & &1.authorization_ok), "synthetic bearer not forwarded")
      assert(Enum.all?(requests, &(&1.model == "fixture-model")), "unexpected model")

      version = isolated_version(root)

      outside_after = outside_cache_snapshot()

      assert(
        outside_after == outside_before,
        "candidate-created Jiti/cache path escaped owned root"
      )

      IO.puts(
        :json.encode(%{
          schema: "checkpoint-f-pi-rpc-probe-v2",
          pi_version: version,
          provider: "loopback-only synthetic OpenAI-compatible fixture",
          provider_requests: length(requests),
          rpc: %{
            start_get_state: "supported",
            observe_events_and_stats: "supported",
            prompt_ack_and_settlement: "supported",
            abort_to_idle: "supported",
            same_session_restart: "supported",
            controller_terminate_process_gone: "supported"
          },
          discovery_denials: %{
            ambient_extension: "denied by isolated config and flags",
            project_extension: "denied by flags",
            hostile_parent_environment: "denied by trusted env -i launcher",
            jiti_cache_escape: "denied; compiled extension cache stayed under owned TMPDIR"
          },
          environment_boundary: %{
            hostile_parent_sentinels: "absent in Pi extension and RPC Bash",
            allowlisted_synthetic_environment: "present in Pi extension and RPC Bash"
          },
          isolation_denials: %{
            explicit_extension_with_no_extensions: "FAILED: executed",
            inherited_file_descriptor:
              "FAILED: explicit startup extension read it; RPC bash child closed it",
            same_user_process_visibility: "FAILED: visible/signalable",
            shared_git_metadata: "FAILED: readable",
            direct_synthetic_credential_to_endpoint: "FAILED: Pi sent bearer directly"
          },
          model_free_repo_check_via_rpc_bash: docs_result
        })
      )
    after
      FakeProvider.stop(server)
      File.rm_rf!(root)
      assert(not File.exists?(root), "owned probe root cleanup failed")
    end
  end

  defp prepare_discovery_fixtures(root) do
    ambient_marker = Path.join(root, "ambient-extension-loaded")
    project_marker = Path.join(root, "project-extension-loaded")

    write!(
      Path.join(root, "ambient-home/.pi/agent/extensions/ambient.ts"),
      extension_source(ambient_marker, "loaded")
    )

    write!(
      Path.join(root, "workspace/.pi/extensions/project.ts"),
      extension_source(project_marker, "loaded")
    )
  end

  defp explicit_extension_probe(root, endpoint) do
    marker = Path.join(root, "explicit-extension-loaded")
    extension = Path.join(root, "explicit.ts")

    write!(
      extension,
      "import fs from 'node:fs';\n" <>
        "const inherited = fs.readFileSync('/dev/fd/9', 'utf8');\n" <>
        "const forbidden = #{:json.encode(Map.keys(@hostile_parent_environment))};\n" <>
        "const leaked = forbidden.filter((name) => process.env[name] !== undefined);\n" <>
        "const result = { inherited, leaked, allowlisted: {\n" <>
        "  secret: process.env.CHECKPOINT_F_INHERITED_SECRET,\n" <>
        "  home: process.env.HOME, tmpdir: process.env.TMPDIR,\n" <>
        "  cache: process.env.XDG_CACHE_HOME, config: process.env.PI_CODING_AGENT_DIR,\n" <>
        "  sessions: process.env.PI_CODING_AGENT_SESSION_DIR\n" <>
        "}};\n" <>
        "fs.writeFileSync(#{:json.encode(marker)}, JSON.stringify(result));\n" <>
        "export default function () {}\n"
    )

    rpc = RPC.start(root, endpoint, ["--extension", extension])
    response!(rpc, "get_state")
    RPC.close(rpc)

    observed = marker |> File.read!() |> :json.decode()
    assert(observed["inherited"] == "synthetic-explicit-extension-fd", "FD not inherited")
    assert(observed["leaked"] == [], "hostile parent environment reached extension/Pi")

    assert(
      get_in(observed, ["allowlisted", "secret"]) == "synthetic-env-secret",
      "allowlist lost"
    )

    assert_owned_environment(observed["allowlisted"], root)
  end

  defp isolated_version(root) do
    paths = RPC.owned_paths(root)

    args = [
      "-i",
      "HOME=#{Path.join(root, "ambient-home")}",
      "PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin",
      "TMPDIR=#{paths.tmp}",
      "XDG_CACHE_HOME=#{paths.xdg_cache}",
      "PI_CODING_AGENT_DIR=#{Path.join(root, "controlled-config")}",
      "PI_OFFLINE=1",
      "PI_TELEMETRY=0",
      "/opt/homebrew/bin/pi",
      "--version"
    ]

    {version, 0} = System.cmd("/usr/bin/env", args)
    String.trim(version)
  end

  defp environment_assertion_command(root) do
    paths = RPC.owned_paths(root)

    forbidden =
      Enum.map(Map.keys(@hostile_parent_environment), fn name ->
        ~s|test -z "${#{name}+x}"|
      end)

    allowlisted = [
      ~s|test "$CHECKPOINT_F_INHERITED_SECRET" = synthetic-env-secret|,
      ~s|test "$HOME" = #{shell_quote(Path.join(root, "ambient-home"))}|,
      ~s|test "$TMPDIR" = #{shell_quote(paths.tmp)}|,
      ~s|test "$XDG_CACHE_HOME" = #{shell_quote(paths.xdg_cache)}|,
      ~s|test "$XDG_CONFIG_HOME" = #{shell_quote(paths.xdg_config)}|,
      ~s|test "$XDG_DATA_HOME" = #{shell_quote(paths.xdg_data)}|,
      ~s|test "$XDG_STATE_HOME" = #{shell_quote(paths.xdg_state)}|,
      ~s|test "$NPM_CONFIG_CACHE" = #{shell_quote(paths.npm_cache)}|,
      ~s|test "$PI_CODING_AGENT_DIR" = #{shell_quote(Path.join(root, "controlled-config"))}|,
      ~s|test "$PI_CODING_AGENT_SESSION_DIR" = #{shell_quote(Path.join(root, "controlled-sessions"))}|
    ]

    Enum.join(forbidden ++ allowlisted, " && ")
  end

  defp assert_owned_environment(observed, root) do
    expected = %{
      "secret" => "synthetic-env-secret",
      "home" => Path.join(root, "ambient-home"),
      "tmpdir" => RPC.owned_paths(root).tmp,
      "cache" => RPC.owned_paths(root).xdg_cache,
      "config" => Path.join(root, "controlled-config"),
      "sessions" => Path.join(root, "controlled-sessions")
    }

    assert(observed == expected, "extension did not receive exact allowlisted environment")
  end

  defp assert_owned_jiti_cache(root) do
    jiti_root = Path.join(RPC.owned_paths(root).tmp, "jiti")

    files =
      Path.wildcard(Path.join(jiti_root, "**/*"), match_dot: true)
      |> Enum.filter(&File.regular?/1)

    assert(files != [], "explicit extension did not create the expected owned Jiti cache")
    assert(Enum.all?(files, &inside?(&1, root)), "Jiti cache escaped owned root")
  end

  defp outside_cache_snapshot do
    known_dirs = [
      Path.join(System.tmp_dir!(), "jiti"),
      Path.join(System.user_home!(), ".cache/jiti"),
      @installed_pi_cache
    ]

    Map.new(known_dirs, fn directory ->
      matching =
        case File.ls(directory) do
          {:ok, names} ->
            Enum.sort(names)

          {:error, :enoent} ->
            []
        end

      {directory, matching}
    end)
  end

  defp inside?(path, root) do
    relative = Path.relative_to(Path.expand(path), Path.expand(root))
    relative != ".." and not String.starts_with?(relative, "../")
  end

  defp response!(rpc, type, timeout \\ 30_000) do
    id = RPC.send_command(rpc, type)
    RPC.wait_response(rpc, id, timeout)
  end

  defp assert_bash(rpc, command, timeout \\ 30_000) do
    id = RPC.send_command(rpc, "bash", %{"command" => command})
    result = RPC.wait_response(rpc, id, timeout)
    assert(result["success"] == true, "RPC bash rejected")
    assert(get_in(result, ["data", "exitCode"]) == 0, inspect(result))
    result
  end

  defp assert_bash_fails(rpc, command) do
    id = RPC.send_command(rpc, "bash", %{"command" => command})
    result = RPC.wait_response(rpc, id)
    assert(result["success"] == true, "RPC bash rejected")
    assert(get_in(result, ["data", "exitCode"]) != 0, "RPC bash unexpectedly inherited FD")
  end

  defp result_line(output) do
    line = output |> String.split("\n") |> Enum.find(&String.starts_with?(&1, "Result:"))
    assert(is_binary(line) and String.contains?(line, "passed"), "docs result absent")
    String.replace_prefix(line, "Result: ", "")
  end

  defp extension_source(marker, value) do
    "import fs from 'node:fs';\n" <>
      "fs.writeFileSync(#{:json.encode(marker)}, #{:json.encode(value)});\n" <>
      "export default function () {}\n"
  end

  defp write!(path, contents) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, contents)
  end

  defp refute_exists(path), do: assert(not File.exists?(path), "unexpected startup code: #{path}")

  defp shell_quote(value), do: "'" <> String.replace(value, "'", "'\\''") <> "'"

  defp assert(true, _message), do: :ok
  defp assert(false, message), do: raise(message)
end

CheckpointF.Probe.run()
