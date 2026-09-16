defmodule Docs.TasksTest do
  @moduledoc """
  Task discovery belongs in the CLI index, not in every agent's initial context.
  Historical/design examples are not assumed to be implemented commands.
  """
  use ExUnit.Case, async: true
  @root Path.expand("../..", __DIR__)

  defp tasks do
    @root
    |> Path.join("pramana/apps/*/lib/mix/tasks/*.ex")
    |> Path.wildcard()
    |> Enum.map(&Path.basename(&1, ".ex"))
    |> MapSet.new()
  end

  test "the CLI index matches actual task modules in both directions" do
    documented =
      @root
      |> Path.join("pramana/docs/CLI.md")
      |> File.read!()
      |> then(&Regex.scan(~r/^\| \[`mix (pramana\.[a-z0-9_.]+)`\]/m, &1))
      |> Enum.map(fn [_, task] -> task end)
      |> MapSet.new()

    assert MapSet.size(documented) > 0
    assert documented == tasks()
  end

  test "ordinary current guides do not recommend nonexistent project tasks" do
    proposed = ~w(PLAN.md PRODUCT_STRATEGY.md)

    unknown =
      ["docs/*.md", "pramana/docs/*.md"]
      |> Enum.flat_map(&Path.wildcard(Path.join(@root, &1)))
      |> Enum.reject(&(Path.basename(&1) in proposed))
      |> Enum.flat_map(fn path ->
        ~r/\bmix (pramana\.[a-z][a-z0-9_.]*)/
        |> Regex.scan(File.read!(path))
        |> Enum.map(fn [_, name] -> String.trim_trailing(name, ".") end)
        |> Enum.reject(&MapSet.member?(tasks(), &1))
        |> Enum.map(&{Path.relative_to(path, @root), &1})
      end)

    assert unknown == []
  end

  test "session diagnostics are discoverable without bloating the router" do
    testing = File.read!(Path.join(@root, "docs/TESTING.md"))
    cli = File.read!(Path.join(@root, "pramana/docs/CLI.md"))

    for task <- ~w(pramana.doctor pramana.gate pramana.coherence pramana.recall) do
      assert String.contains?(testing <> cli, task)
    end
  end
end
