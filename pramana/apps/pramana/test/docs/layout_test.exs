defmodule Docs.LayoutTest do
  @moduledoc "Structural and executable wrapper checks; no corpus, daemon or provider."
  use ExUnit.Case, async: true

  @root Path.expand("../../../../..", __DIR__)

  defp scratch do
    path = Path.join(System.tmp_dir!(), "pramana layout #{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf!(path) end)
    path
  end

  defp executable(path, content) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)
    File.chmod!(path, 0o755)
    path
  end

  defp copy(root, relative) do
    source = Path.join(@root, relative)
    target = Path.join(root, relative)
    File.mkdir_p!(Path.dirname(target))
    File.cp!(source, target)
    File.chmod!(target, 0o755)
    target
  end

  test "the repository has two independent Mix roots, not a root umbrella" do
    refute File.exists?(Path.join(@root, "mix.exs"))
    assert File.read!(Path.join(@root, "pramana/mix.exs")) =~ ~s(apps_path: "apps")
    refute File.read!(Path.join(@root, "foundry/mix.exs")) =~ "in_umbrella"

    for project <- ["pramana", "foundry"] do
      for path <- ["mix.exs", "mix.lock", "config/config.exs"] do
        assert File.regular?(Path.join([@root, project, path]))
      end
    end

    refute File.exists?(Path.join(@root, "pramana/apps/foundry"))
    assert File.read!(Path.join(@root, ".mcp.json")) =~ "./pramana/bin/pramana-mcp"
  end

  test "the explicit product wrapper preserves working directory, argv and failure" do
    root = scratch()
    wrapper = copy(root, "bin/pramana")
    File.mkdir_p!(Path.join(root, "pramana"))

    command =
      executable(Path.join(root, "fake executable"), """
      #!/usr/bin/env bash
      printf '%s\\0' "$PWD" "$@"
      exit 23
      """)

    arguments = ["two words", "", "; not a command", "line\nbreak", "བོད་"]
    {output, status} = System.cmd(wrapper, [command | arguments], cd: System.tmp_dir!())
    assert status == 23
    assert String.split(output, <<0>>) == [Path.join(root, "pramana") | arguments] ++ [""]
  end

  test "the MCP compatibility route keeps compilation off protocol stdout" do
    root = scratch()
    wrapper = copy(root, "bin/pramana-mcp")
    copy(root, "pramana/bin/pramana-mcp")
    fake_bin = Path.join(root, "fake-bin")
    # Prevent an installed mise from changing the isolated fake PATH.
    executable(Path.join(fake_bin, "mise"), "#!/usr/bin/env bash\nexit 0\n")

    executable(Path.join(fake_bin, "mix"), """
    #!/usr/bin/env bash
    case "$1" in
      compile) echo 'compiler chatter'; exit 0 ;;
      pramana.mcp.stdio) printf '{"cwd":"%s"}\n' "$PWD"; exit 0 ;;
      *) exit 99 ;;
    esac
    """)

    env = [{"PATH", fake_bin <> ":" <> System.fetch_env!("PATH")}]
    {output, status} = System.cmd(wrapper, [], env: env, cd: System.tmp_dir!())
    assert status == 0
    assert output == ~s({"cwd":"#{Path.join(root, "pramana")}"}\n)
    refute output =~ "compiler chatter"
  end

  test "Modal compatibility uses an explicit existing venv without changing caller cwd" do
    root = scratch()
    wrapper = copy(root, "bin/pramana-modal")
    copy(root, "pramana/bin/pramana-modal")
    source = Path.join(root, "pramana/priv/embed/probe.py")
    File.mkdir_p!(Path.dirname(source))
    File.write!(source, "# No model is run.\n")
    data_root = Path.join(root, "old data")

    executable(Path.join(data_root, "priv/embed/.venv/bin/modal"), """
    #!/usr/bin/env bash
    printf '%s\\0' "$PWD" "$@"
    exit 17
    """)

    {output, status} =
      System.cmd(wrapper, ["run", "priv/embed/probe.py", "two words", ""],
        cd: root,
        env: [{"PRAMANA_DATA_ROOT", data_root}, {"PRAMANA_MODAL_VENV", nil}]
      )

    assert status == 17
    assert String.split(output, <<0>>) == [root, "run", source, "two words", "", ""]

    {_message, status} =
      System.cmd(wrapper, [],
        cd: root,
        stderr_to_stdout: true,
        env: [{"PRAMANA_DATA_ROOT", "relative/data"}, {"PRAMANA_MODAL_VENV", nil}]
      )

    assert status == 2
  end

  test "project routers are small and point at shared policy rather than duplicating it" do
    for project <- ["pramana", "foundry"] do
      text = File.read!(Path.join([@root, project, "AGENTS.md"]))
      assert byte_size(text) < 3000
      assert text =~ "../docs/agents/WORKFLOW.md"
    end
  end
end
