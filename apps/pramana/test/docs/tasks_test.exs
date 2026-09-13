defmodule Docs.TasksTest do
  @moduledoc """
  Every mix task is mentioned in at least one document.

  There are tests that a **rule** is reachable from `AGENTS.md`'s trigger table
  (`Docs.RoutingTest`) and that an **MCP tool** appears in `docs/MCP.md`'s table
  (`PramanaWeb.MCP.DocumentedTest`), because a capability nobody can find has not shipped.
  The write path had no such check, and ten of forty-nine tasks were named in no document at
  all — including six added the same week.

  The bar is deliberately low: *mentioned somewhere*. Not every task belongs in the
  always-in-context file, and demanding that would push forty-nine lines into `AGENTS.md` and
  make it worse. But a task nobody has written a sentence about is one nobody will run, and
  the CLI is the only way anything is written to this corpus (invariant #7).
  """
  use ExUnit.Case, async: true

  # The repository root, not `:project_root`: that setting is rebound by acquisition tests to
  # a temporary directory, and a docs assertion reading an empty tmpdir passes for the wrong
  # reason.
  @root Path.expand("../../../..", __DIR__)

  defp tasks do
    @root
    |> Path.join("apps/*/lib/mix/tasks/*.ex")
    |> Path.wildcard()
    |> Enum.map(&(&1 |> Path.basename(".ex")))
  end

  defp prose do
    ["AGENTS.md", "CLAUDE.md", "README.md"]
    |> Enum.map(&Path.join(@root, &1))
    |> Enum.concat(Path.wildcard(Path.join(@root, "docs/*.md")))
    |> Enum.map_join("\n", &File.read!/1)
  end

  test "every mix task is named in some document" do
    text = prose()
    missing = Enum.reject(tasks(), &String.contains?(text, &1))

    assert missing == [],
           """
           These tasks are named in no document, so nobody will find them:

           #{Enum.map_join(missing, "\n", &"    mix #{&1}")}

           A sentence in the file that owns the subject is enough — `docs/SOURCES.md` for an
           ingest, `docs/EMBEDDING.md` for a model step, `docs/CHECKS.md` for a check.
           """
  end

  test "the tasks a session runs first are in AGENTS.md, not merely somewhere" do
    # These are the ones a new session needs without being told to look: what state am I in,
    # is it green, and what does a measurement command need to be a measurement.
    agents = File.read!(Path.join(@root, "AGENTS.md"))

    for task <- ~w(pramana.doctor pramana.gate pramana.coherence pramana.recall) do
      assert String.contains?(agents, task), "#{task} is not in AGENTS.md"
    end
  end
end
