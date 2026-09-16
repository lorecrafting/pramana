defmodule Repository.LocalLayoutTest do
  @moduledoc "The upgrade preflight must observe legacy data without modifying it."
  use ExUnit.Case, async: true
  @script Path.expand("../bin/check_local_layout.exs", __DIR__)

  setup do
    root = Path.join(System.tmp_dir!(), "layout preflight #{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(root, "pramana"))
    File.write!(Path.join(root, "pramana/mix.exs"), "# fixture")
    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, root: root}
  end

  test "fresh source-only checkout is accepted without creating data", %{root: root} do
    assert {_, 0} = run(root)
    refute File.exists?(Path.join(root, "raw"))
    refute File.exists?(Path.join(root, "pramana/raw"))
  end

  test "legacy data is reported but never copied or removed", %{root: root} do
    old = Path.join(root, "raw")
    File.mkdir_p!(old)
    File.write!(Path.join(old, "sentinel"), "unchanged")
    assert {text, 2} = run(root)
    assert text =~ "legacy location only"
    assert File.read!(Path.join(old, "sentinel")) == "unchanged"
    refute File.exists?(Path.join(root, "pramana/raw"))
  end

  test "explicit direct compatibility link is recognized", %{root: root} do
    File.mkdir_p!(Path.join(root, "raw"))
    File.ln_s!("../raw", Path.join(root, "pramana/raw"))
    assert {_, 0} = run(root)
    assert File.read_link!(Path.join(root, "pramana/raw")) == "../raw"
  end

  test "two independent locations are a conflict, not an automatic merge", %{root: root} do
    File.mkdir_p!(Path.join(root, "raw"))
    File.mkdir_p!(Path.join(root, "pramana/raw"))
    assert {text, 2} = run(root)
    assert text =~ "both locations exist"
    assert File.dir?(Path.join(root, "raw"))
    assert File.dir?(Path.join(root, "pramana/raw"))
  end

  test "an invalid legacy parent is not silently treated as absent", %{root: root} do
    parent = Path.join(root, "priv")
    File.write!(parent, "preserved")
    assert {text, 2} = run(root)
    assert text =~ "cannot inspect"
    assert text =~ ":enotdir"
    assert File.read!(parent) == "preserved"
  end

  test "a dangling bridge still requires review", %{root: root} do
    File.mkdir_p!(Path.join(root, "raw"))
    bridge = Path.join(root, "pramana/raw")
    File.ln_s!("../missing-raw", bridge)
    assert {text, 2} = run(root)
    assert text =~ "both locations exist"
    assert File.read_link!(bridge) == "../missing-raw"
  end

  defp run(root),
    do:
      System.cmd(System.find_executable("elixir"), [@script, "--root", root],
        stderr_to_stdout: true
      )
end
