# Read-only upgrade preflight. No files are copied, moved, deleted or followed for content.
defmodule Repository.LocalLayout do
  @moduledoc false

  @artifacts ["raw", "bake/out", "priv/models", "priv/embed/.venv", "priv/plts"]

  def run(root) do
    root = Path.expand(root)
    project = Path.join(root, "pramana")

    unless File.regular?(Path.join(project, "mix.exs")) do
      IO.puts(:stderr, "Not a sibling-layout checkout: #{root}")
      System.halt(64)
    end

    local_sources =
      Path.wildcard(Path.join(root, "sources/local/*/{text,raw}"))
      |> Enum.map(&Path.relative_to(&1, root))

    problems =
      for relative <- @artifacts ++ local_sources,
          old = Path.join(root, relative),
          new = Path.join(project, relative),
          present?(old),
          not direct_bridge?(new, old) do
        state =
          if present?(new),
            do: "both locations exist; reconcile explicitly",
            else: "legacy location only"

        IO.puts("REVIEW #{relative}: #{state}")
        IO.puts("  old: #{old}\n  new: #{new}")
        relative
      end

    if problems == [] do
      IO.puts("No unresolved legacy paths in the bounded layout inventory. No data was changed.")
    else
      IO.puts(
        "No data changed. Read docs/LAYOUT_MIGRATION.md before running acquisition or inference."
      )

      System.halt(2)
    end
  end

  defp present?(path), do: match?({:ok, _}, File.lstat(path))

  defp direct_bridge?(new, old) do
    case File.read_link(new) do
      {:ok, target} -> File.dir?(new) and Path.expand(target, Path.dirname(new)) == old
      _ -> false
    end
  end
end

case System.argv() do
  [] ->
    Repository.LocalLayout.run(Path.expand("..", __DIR__))

  ["--root", root] ->
    Repository.LocalLayout.run(root)

  ["--help"] ->
    IO.puts(
      "elixir bin/check_local_layout.exs [--root CHECKOUT]\nRead-only, bounded legacy-path inventory; exit 2 requires operator review."
    )

  _ ->
    IO.puts(:stderr, "usage: elixir bin/check_local_layout.exs [--root CHECKOUT]")
    System.halt(64)
end
