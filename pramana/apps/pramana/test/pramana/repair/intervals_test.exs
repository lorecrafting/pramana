defmodule Pramana.Repair.IntervalsTest do
  @moduledoc "Indexed semantic overlap detection agrees with the simple all-pairs specification."
  use ExUnit.Case, async: true

  alias Pramana.Repair.Intervals

  test "no writes, same-owner ranges and touching endpoints do not conflict" do
    assert Intervals.conflicts([], [{0, 10, :a}]) == %{}
    assert Intervals.conflicts([{1, 4, :a}], [{0, 5, :a}, {4, 6, :b}]) == %{}
  end

  test "an edit inside another verified quotation flags both owners" do
    assert Intervals.conflicts([{4, 6, :inner}], [{0, 10, :outer}, {4, 6, :inner}]) ==
             %{inner: true, outer: true}
  end

  test "nested ranges, repeated owners and empty intervals agree with an independent oracle" do
    universe =
      for first <- 0..4, last <- first..5, owner <- [:a, :b, :c], do: {first, last, owner}

    for offset <- 0..40 do
      writes = universe |> Enum.drop(offset) |> Enum.take(9)
      scopes = universe |> Enum.reverse() |> Enum.drop(offset) |> Enum.take(17)
      assert MapSet.new(Map.keys(Intervals.conflicts(writes, scopes))) == oracle(writes, scopes)
    end
  end

  test "thousands of nested intervals can be classified without enumerating all pairs" do
    scopes = for n <- 1..4_000, do: {0, n + 1, n}
    writes = for n <- 1..4_000, do: {1, n + 1, n}
    assert MapSet.new(Map.keys(Intervals.conflicts(writes, scopes))) == MapSet.new(1..4_000)
  end

  defp oracle(writes, scopes) do
    for {a, b, owner} <- writes,
        {c, d, other} <- scopes,
        owner != other,
        a < b,
        c < d,
        a < d,
        c < b,
        id <- [owner, other],
        into: MapSet.new(),
        do: id
  end
end
