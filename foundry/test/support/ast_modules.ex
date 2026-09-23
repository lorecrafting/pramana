defmodule PramanaFoundry.Test.AstModules do
  @moduledoc """
  Static module resolution over unexpanded source, shared by the tests that read call
  sites and references from the AST rather than the text.

  Extracted from `r4_no_direct_apply_test.exs`, whose moduledoc and `@spellings` list say
  what it resolves and what it does not.
  """

  # Every node of `quoted`, in prewalk order.
  def nodes(quoted) do
    {_, acc} = Macro.prewalk(quoted, [], fn node, acc -> {node, [node | acc]} end)
    Enum.reverse(acc)
  end

  # Static module bindings in the file: `alias A.B`, `alias A.B, as: C`, `alias A.{B, C}`,
  # each with any further options (`warn: false`), and `@name A.B`. Collected file-wide rather
  # than per lexical scope, and each name keeps EVERY module it is ever bound to, so a later
  # alias in another module cannot hide an earlier one: a name resolves to the set, and the
  # scan reports if the target is in it. That can over-report, never under-report.
  def bindings(quoted) do
    quoted
    |> nodes()
    |> Enum.reduce(%{}, fn
      {:alias, _, [{{:., _, [prefix, :{}]}, _, targets} | _]}, acc ->
        for {:__aliases__, _, segs} <- targets,
            base <- resolve(prefix, acc),
            reduce: acc do
          acc -> bind(acc, List.last(segs), Module.concat([base | segs]))
        end

      {:alias, _, [{:__aliases__, _, segs} = target | opts]}, acc ->
        name =
          case Keyword.get(List.flatten(opts), :as) do
            {:__aliases__, _, [as]} -> as
            _ -> List.last(segs)
          end

        Enum.reduce(resolve(target, acc), acc, &bind(&2, name, &1))

      {:@, _, [{name, _, [value]}]}, acc ->
        Enum.reduce(resolve(value, acc), acc, &bind(&2, {:@, name}, &1))

      _, acc ->
        acc
    end)
  end

  defp bind(acc, name, module), do: Map.update(acc, name, [module], &[module | &1])

  # Every module the spelling can name. An aliased first segment also keeps its literal
  # meaning, which is what it names above the alias.
  def resolve({:__aliases__, _, [first | rest]}, bindings) when is_atom(first) do
    for base <- [first | Map.get(bindings, first, [])], do: Module.concat([base | rest])
  end

  def resolve({:@, _, [{name, _, nil}]}, bindings), do: Map.get(bindings, {:@, name}, [])
  def resolve(module, _) when is_atom(module), do: [module]
  def resolve(_, _), do: []
end
