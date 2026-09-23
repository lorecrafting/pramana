Code.require_file("../../support/ast_modules.ex", __DIR__)

defmodule PramanaFoundry.ManualLane.NonLaunchTest do
  @moduledoc """
  The manual lane launches nothing (THIN-LANE-DESIGN-2026-09-23.md §1): the transitive
  module closure of every file under `lib/pramana_foundry/manual_lane/`, plus
  `work_packet.ex`, reaches no Herdr, AgentServer, Coordinator dispatch or launch effect.

  References are resolved with the architecture gate's resolver (`test/support/ast_modules.ex`),
  so an alias, a renamed alias, a multi-alias or a module attribute is a reference. The walk
  follows every referenced module defined under `lib/`.
  """
  use ExUnit.Case, async: true

  alias PramanaFoundry.Test.AstModules, as: Ast

  @forbidden [
    PramanaFoundry.AgentServer,
    PramanaFoundry.Coordinator,
    PramanaFoundry.Coordinator.Tick,
    PramanaFoundry.Coordinator.State,
    PramanaFoundry.Effects.Launch,
    PramanaFoundry.Effects.PromptDelivery
  ]

  test "the manual lane's module closure reaches no launch path" do
    start = Path.wildcard("lib/pramana_foundry/manual_lane/**/*.ex")
    assert start != [], "no manual_lane sources found"
    start = start ++ Enum.filter(["lib/pramana_foundry/work_packet.ex"], &File.exists?/1)

    assert forbidden(start, Path.wildcard("lib/**/*.ex")) == []
  end

  test "red control: a direct Herdr.Adapter reference is seen" do
    path = fixture("defmodule Lane.A do\n def f, do: PramanaFoundry.Herdr.Adapter.run()\nend")
    assert [{Lane.A, PramanaFoundry.Herdr.Adapter}] = forbidden([path], [path])
  end

  test "red control: Coordinator reached through one intermediate module is seen" do
    a = fixture("defmodule Lane.B do\n alias Lane.Mid\n def f, do: Mid.g()\nend")
    mid = fixture("defmodule Lane.Mid do\n @c PramanaFoundry.Coordinator\n def g, do: @c\nend")
    assert [{Lane.Mid, PramanaFoundry.Coordinator}] = forbidden([a], [a, mid])
  end

  # {referencing module, forbidden module} for everything the closure of `start` reaches,
  # where `universe` is the set of source files whose modules the walk may enter.
  defp forbidden(start, universe) do
    files = for path <- universe, mod <- defined(ast(path)), into: %{}, do: {mod, path}
    walk(Enum.flat_map(start, &defined(ast(&1))), files, MapSet.new(), [])
  end

  defp walk([], _files, _seen, found), do: Enum.uniq(found)

  defp walk([mod | rest], files, seen, found) do
    if MapSet.member?(seen, mod) or not Map.has_key?(files, mod) do
      walk(rest, files, MapSet.put(seen, mod), found)
    else
      refs = references(ast(files[mod]))
      hits = for ref <- refs, bad?(ref), do: {mod, ref}
      walk(rest ++ refs, files, MapSet.put(seen, mod), found ++ hits)
    end
  end

  defp bad?(mod),
    do: mod in @forbidden or List.starts_with?(Module.split(mod), ~w(PramanaFoundry Herdr))

  # Every resolved module reference in the file, by the gate's resolver.
  defp references(quoted) do
    bindings = Ast.bindings(quoted)

    for node <- Ast.nodes(quoted),
        mod <- resolve(node, bindings),
        String.starts_with?(Atom.to_string(mod), "Elixir."),
        uniq: true,
        do: mod
  end

  defp resolve({:__aliases__, _, _} = node, b), do: Ast.resolve(node, b)
  defp resolve({:@, _, [{_, _, nil}]} = node, b), do: Ast.resolve(node, b)
  defp resolve(atom, _) when is_atom(atom), do: [atom]
  defp resolve(_, _), do: []

  # Every module a file defines, nested names concatenated.
  defp defined(quoted), do: defined(quoted, nil)

  defp defined({:defmodule, _, [{:__aliases__, _, segs}, [do: body]]}, parent) do
    mod = Module.concat([parent || Elixir | segs])
    [mod | defined(body, mod)]
  end

  defp defined({_, _, args}, parent) when is_list(args),
    do: Enum.flat_map(args, &defined(&1, parent))

  defp defined(list, parent) when is_list(list), do: Enum.flat_map(list, &defined(&1, parent))
  defp defined({a, b}, parent), do: defined(a, parent) ++ defined(b, parent)
  defp defined(_, _), do: []

  defp ast(path), do: path |> File.read!() |> Code.string_to_quoted!(file: path)

  defp fixture(source) do
    path = Path.join(System.tmp_dir!(), "non_launch_#{:erlang.unique_integer([:positive])}.ex")
    File.write!(path, source <> "\n")
    on_exit(fn -> File.rm(path) end)
    path
  end
end
