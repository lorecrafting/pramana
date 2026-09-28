defmodule Repository.WrappersTest do
  @moduledoc "Exercise forwarding without a database, model or provider."
  use ExUnit.Case, async: true

  @root Path.expand("..", __DIR__)

  setup do
    root = Path.join(System.tmp_dir!(), "layout space #{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(root, "bin"))
    File.mkdir_p!(Path.join(root, "fake-bin"))
    File.mkdir_p!(Path.join(root, "elsewhere"))

    for file <- ~w(pramana-mcp pramana-modal pramana-tranche) do
      copy_executable(Path.join(@root, "bin/#{file}"), Path.join(root, "bin/#{file}"))
    end

    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, root: root}
  end

  test "MCP implementation compiles to stderr then preserves the protocol stream", %{root: root} do
    write_executable(Path.join(root, "fake-bin/mise"), "#!/bin/sh\nexit 0\n")

    write_executable(Path.join(root, "fake-bin/mix"), """
    #!/bin/sh
    if [ "$1" = compile ]; then
      printf 'compiler-output\n'
      exit 0
    fi
    test "$1" = pramana.mcp.stdio || exit 91
    printf '{"protocol":"only"}\n'
    """)

    env = [{"PATH", Path.join(root, "fake-bin") <> ":" <> System.get_env("PATH")}]

    {out, 0} =
      System.cmd(Path.join(root, "bin/pramana-mcp"), [],
        cd: Path.join(root, "elsewhere"),
        env: env
      )

    assert out == "{\"protocol\":\"only\"}\n"
  end

  test "MCP compile failure stops before protocol startup", %{root: root} do
    write_executable(Path.join(root, "fake-bin/mise"), "#!/bin/sh\nexit 0\n")

    write_executable(
      Path.join(root, "fake-bin/mix"),
      "#!/bin/sh\ntest \"$1\" = compile && exit 19\nprintf 'unexpected-server-start'\n"
    )

    env = [{"PATH", Path.join(root, "fake-bin") <> ":" <> System.get_env("PATH")}]
    assert {"", 19} = System.cmd(Path.join(root, "bin/pramana-mcp"), [], env: env)
  end

  test "Modal uses the project venv and cwd without interpreting arguments", %{root: root} do
    venv = Path.join(root, "priv/embed/.venv/bin")
    File.mkdir_p!(venv)

    write_executable(
      Path.join(venv, "modal"),
      "#!/bin/sh\nprintf '%s\\n' \"$PWD\" \"$@\"\nexit 29\n"
    )

    args = ["run", "priv/embed/a file.py", "--input-name", "$(literal)"]

    {out, 29} =
      System.cmd(Path.join(root, "bin/pramana-modal"), args, cd: Path.join(root, "elsewhere"))

    assert out == Enum.join([root | args], "\n") <> "\n"
  end

  test "tranche refuses to launch when Modal app state is unavailable", %{root: root} do
    venv = Path.join(root, "priv/embed/.venv/bin")
    File.mkdir_p!(venv)
    marker = Path.join(root, "launched")

    for response <- ["exit 7", "printf 'not json'"] do
      write_executable(
        Path.join(venv, "modal"),
        "#!/bin/sh\nif [ \"$1\" = app ]; then #{response}; exit 0; fi\ntouch '#{marker}'\n"
      )

      {_, status} =
        System.cmd(Path.join(root, "bin/pramana-tranche"), ["arm", "input.jsonl", "output.jsonl"],
          env: [{"PRAMANA_TRANCHE_LOGS", Path.join(root, "logs")}],
          stderr_to_stdout: true
        )

      assert status == 2
      refute File.exists?(marker)
    end
  end

  test "tranche ignores completion text from another invocation", %{root: root} do
    venv = Path.join(root, "priv/embed/.venv/bin")
    File.mkdir_p!(venv)
    write_executable(Path.join(venv, "modal"), "#!/bin/sh\nprintf '[]'")
    logs = Path.join(root, "logs")
    File.mkdir_p!(logs)
    File.write!(Path.join(logs, "old.log"), "nothing outstanding\n")

    {_, status} =
      System.cmd(Path.join(root, "bin/pramana-tranche"), ["arm", "input.jsonl", "output.jsonl"],
        env: [
          {"PRAMANA_TRANCHE_LOGS", logs},
          {"PRAMANA_TRANCHE_MAX_RESTARTS", "0"}
        ],
        stderr_to_stdout: true
      )

    assert status == 1
  end

  defp copy_executable(from, to) do
    File.cp!(from, to)
    File.chmod!(to, 0o755)
  end

  defp write_executable(path, content) do
    File.write!(path, content)
    File.chmod!(path, 0o755)
  end
end
