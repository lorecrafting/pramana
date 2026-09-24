defmodule Repository.WrappersTest do
  @moduledoc "Exercise forwarding without a database, model or provider."
  use ExUnit.Case, async: true

  @root Path.expand("..", __DIR__)

  setup do
    root = Path.join(System.tmp_dir!(), "layout space #{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(root, "bin"))
    File.mkdir_p!(Path.join(root, "pramana/bin"))
    File.mkdir_p!(Path.join(root, "fake-bin"))
    File.mkdir_p!(Path.join(root, "elsewhere"))

    for file <- ~w(pramana-mix pramana-mcp) do
      copy_executable(Path.join(@root, "bin/#{file}"), Path.join(root, "bin/#{file}"))
    end

    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, root: root}
  end

  test "Mix wrapper changes only the intended working directory and preserves arguments and exit",
       %{root: root} do
    fake = Path.join(root, "fake-bin/mix")
    write_executable(fake, "#!/bin/sh\nprintf '%s\\n' \"$PWD\" \"$@\"\nexit 37\n")
    env = [{"PATH", Path.join(root, "fake-bin") <> ":" <> System.get_env("PATH")}]
    args = ["test", "a file.exs", "$(never-execute)", ";literal", ""]

    {out, 37} =
      System.cmd(Path.join(root, "bin/pramana-mix"), args,
        cd: Path.join(root, "elsewhere"),
        env: env
      )

    assert out == Enum.join([Path.join(root, "pramana") | args], "\n") <> "\n"
    refute File.exists?(Path.join(root, "never-execute"))
  end

  test "the root MCP launcher forwards inert arguments without producing extra stdout", %{
    root: root
  } do
    write_executable(
      Path.join(root, "pramana/bin/pramana-mcp"),
      "#!/bin/sh\nprintf '%s\\n' \"$@\"\nexit 23\n"
    )

    args = ["space here", "$(not-a-command)", "--flag", ""]

    {out, 23} =
      System.cmd(Path.join(root, "bin/pramana-mcp"), args, cd: Path.join(root, "elsewhere"))

    assert out == Enum.join(args, "\n") <> "\n"
  end

  test "MCP implementation compiles to stderr then preserves the protocol stream", %{root: root} do
    copy_executable(
      Path.join(@root, "pramana/bin/pramana-mcp"),
      Path.join(root, "pramana/bin/pramana-mcp")
    )

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
    copy_executable(
      Path.join(@root, "pramana/bin/pramana-mcp"),
      Path.join(root, "pramana/bin/pramana-mcp")
    )

    write_executable(Path.join(root, "fake-bin/mise"), "#!/bin/sh\nexit 0\n")

    write_executable(
      Path.join(root, "fake-bin/mix"),
      "#!/bin/sh\ntest \"$1\" = compile && exit 19\nprintf 'unexpected-server-start'\n"
    )

    env = [{"PATH", Path.join(root, "fake-bin") <> ":" <> System.get_env("PATH")}]
    assert {"", 19} = System.cmd(Path.join(root, "bin/pramana-mcp"), [], env: env)
  end

  test "Modal uses the project venv and cwd without interpreting arguments", %{root: root} do
    copy_executable(
      Path.join(@root, "pramana/bin/pramana-modal"),
      Path.join(root, "pramana/bin/pramana-modal")
    )

    venv = Path.join(root, "pramana/priv/embed/.venv/bin")
    File.mkdir_p!(venv)

    write_executable(
      Path.join(venv, "modal"),
      "#!/bin/sh\nprintf '%s\\n' \"$PWD\" \"$@\"\nexit 29\n"
    )

    args = ["run", "priv/embed/a file.py", "--input-name", "$(literal)"]

    {out, 29} =
      System.cmd(Path.join(root, "pramana/bin/pramana-modal"), args,
        cd: Path.join(root, "elsewhere")
      )

    assert out == Enum.join([Path.join(root, "pramana") | args], "\n") <> "\n"
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
