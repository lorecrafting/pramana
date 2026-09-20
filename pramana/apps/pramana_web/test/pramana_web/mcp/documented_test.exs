defmodule PramanaWeb.MCP.DocumentedTest do
  @moduledoc """
  Every source-declared tool appears in `docs/MCP.md`'s table, and every row of that table
  is declared. This file also runs in the dependency-free repository check. The application
  suite separately compares the runtime tools/list result with the documented names.

  `docs/MCP.md` says it of itself — *"a tool that is not in its table is a tool a model will
  not find"* — and nothing enforced it. This is the same failure `Docs.RoutingTest` exists
  to prevent one level up: a rule nobody is routed to fires after the defect rather than
  before it. A tool is only shipped when a model can discover it, which is rule 60, and the
  table is where discovery happens for a reader deciding what this surface can do.

  Both directions matter. An undocumented tool is invisible; a documented tool that no
  longer exists is worse, because a caller plans around it and gets an error from a surface
  that claimed to offer it.
  """
  use ExUnit.Case, async: true

  # Deliberately the source project root, not the mutable `:project_root`: that setting is rebound by
  # acquisition tests to a temporary directory, and a docs assertion that silently reads an
  # empty tmpdir passes for the wrong reason.
  @root Path.expand("../../../../..", __DIR__)

  defp declared do
    ast =
      @root
      |> Path.join("apps/pramana_web/lib/pramana_web/mcp/server.ex")
      |> File.read!()
      |> Code.string_to_quoted!()

    {_ast, names} =
      Macro.prewalk(ast, [], fn
        {:component, _, [{:__aliases__, _, [:PramanaWeb, :MCP, :Tools, name]}]} = node, acc ->
          {node, [name |> Atom.to_string() |> Macro.underscore() | acc]}

        node, acc ->
          {node, acc}
      end)

    MapSet.new(names)
  end

  # Scoped to the table under `| tool | for |`, not to every backticked table cell in the
  # file. The first version matched any row starting with one backticked word and pulled in
  # `cbeta` from the edition-links table further down — a docs check that fails on unrelated
  # prose is a check people learn to edit around.
  defp documented do
    @root
    |> Path.join("docs/MCP.md")
    |> File.read!()
    |> String.split("| tool | for |", parts: 2)
    |> List.last()
    |> String.split("\n\n", parts: 2)
    |> List.first()
    |> then(&Regex.scan(~r/^\| `(\w+)` \|/m, &1))
    |> Enum.map(fn [_, name] -> name end)
    |> MapSet.new()
  end

  test "every source-declared tool is in the table" do
    assert MapSet.size(declared()) > 0
    assert MapSet.size(documented()) > 0
    missing = MapSet.difference(declared(), documented())

    assert MapSet.size(missing) == 0,
           "not in docs/MCP.md's table: #{Enum.join(missing, ", ")}. A tool a model cannot " <>
             "find is a tool that has not shipped (rule 60)."
  end

  test "every tool named in the table is source-declared" do
    stale = MapSet.difference(documented(), declared())

    assert MapSet.size(stale) == 0,
           "documented in docs/MCP.md but not declared in server.ex: " <>
             "#{Enum.join(stale, ", ")}. A promised tool that errors is worse than a " <>
             "missing one."
  end
end
