defmodule Pramana.Repair.Intervals do
  @moduledoc """
  Finds writes that touch another occurrence's semantic ranges, in O(n log n).

  An interval is `{first_byte, last_byte, owner}`. Two sorted prefix sweeps mark
  both owners without enumerating intersecting pairs, even for nested intervals.
  Half-open touching endpoints do not overlap. The no-write case is constant time.
  """

  @type interval :: {non_neg_integer(), non_neg_integer(), term()}

  @spec conflicts([interval()], [interval()]) :: MapSet.t()
  def conflicts([], _scopes), do: MapSet.new()

  def conflicts(writes, scopes) do
    MapSet.union(intersecting_owners(writes, scopes), intersecting_owners(scopes, writes))
  end

  defp intersecting_owners(queries, candidates) do
    candidates = Enum.sort_by(candidates, &elem(&1, 0))

    queries
    |> Enum.sort_by(&elem(&1, 1))
    |> Enum.reduce({candidates, [], MapSet.new()}, fn {first, last, owner},
                                                      {pending, best, ids} ->
      {pending, best} = advance(pending, best, last)
      overlaps = Enum.any?(best, fn {finish, other} -> other != owner and finish > first end)
      ids = if first < last and overlaps, do: MapSet.put(ids, owner), else: ids
      {pending, best, ids}
    end)
    |> elem(2)
  end

  defp advance([{first, last, owner} | rest], best, limit) when first < limit do
    best = if first < last, do: remember(best, last, owner), else: best
    advance(rest, best, limit)
  end

  defp advance(pending, best, _limit), do: {pending, best}

  defp remember(best, last, owner) do
    previous = Enum.find_value(best, last, fn {finish, id} -> if id == owner, do: finish end)

    [{max(last, previous), owner} | Enum.reject(best, fn {_, id} -> id == owner end)]
    |> Enum.sort(:desc)
    |> Enum.take(2)
  end
end
