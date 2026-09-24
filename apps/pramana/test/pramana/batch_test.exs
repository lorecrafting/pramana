defmodule Pramana.BatchTest do
  @moduledoc """
  Batch sizing, and why the write itself lives here.

  The Postgres 65,535-parameter limit was hit four times in this project. The first
  three were fixed by writing the lesson down; the fourth happened anyway, in a module
  that had no batching at all and had simply never been handed enough rows to notice.
  `insert_all/3` exists so that using the safe path is easier than not.
  """
  use Pramana.DataCase, async: true

  alias Pramana.Batch
  alias Pramana.Corpus.CharacterReading
  alias Pramana.Repo

  describe "size" do
    test "is a function of row WIDTH, not a constant" do
      # The whole bug in one assertion: the same 5,000 that is safe at 13 columns
      # exceeds the limit at 18.
      narrow = Batch.size([Map.new(1..13, &{&1, &1})])
      wide = Batch.size([Map.new(1..18, &{&1, &1})])

      assert narrow > wide
      assert narrow * 13 <= 65_535
      assert wide * 18 <= 65_535
    end

    test "never returns zero, however wide the row" do
      # A row wider than the limit would otherwise chunk into empty statements and
      # loop forever.
      assert Batch.size([Map.new(1..70_000, &{&1, &1})]) == 1
    end

    test "an empty list still gives a usable size, so callers can chunk unconditionally" do
      assert Batch.size([]) == 1
    end
  end

  describe "chunk" do
    test "splits into statements Postgres will accept" do
      rows = List.duplicate(Map.new(1..18, &{&1, &1}), 10_000)

      for statement <- Batch.chunk(rows) do
        assert length(statement) * 18 <= 65_535
      end
    end

    test "an empty list produces no statements at all" do
      assert Batch.chunk([]) == []
    end
  end

  describe "insert_all" do
    defp rows(n) do
      now = DateTime.utc_now()

      for i <- 1..n do
        %{
          character: <<0x4E00 + i::utf8>>,
          reading: "x",
          attested: ["x"],
          authority: "test",
          inserted_at: now,
          updated_at: now
        }
      end
    end

    test "writes more rows than one statement can hold" do
      # 6 columns × 12,000 rows is 72,000 parameters — over the limit in one statement,
      # fine across several.
      {written, _} = Batch.insert_all(CharacterReading, rows(12_000))

      assert written == 12_000
      assert Repo.aggregate(CharacterReading, :count) == 12_000
    end

    test "returns the count summed across statements, like Repo.insert_all" do
      assert {3, nil} = Batch.insert_all(CharacterReading, rows(3))
    end

    test "an empty list writes nothing rather than erroring" do
      assert {0, nil} = Batch.insert_all(CharacterReading, [])
    end

    test "passes options through" do
      {2, _} = Batch.insert_all(CharacterReading, rows(2))

      {written, _} =
        Batch.insert_all(CharacterReading, rows(2),
          on_conflict: :nothing,
          conflict_target: [:character]
        )

      assert written == 0
      assert Repo.aggregate(CharacterReading, :count) == 2
    end
  end
end
