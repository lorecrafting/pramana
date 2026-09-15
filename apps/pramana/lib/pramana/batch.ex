defmodule Pramana.Batch do
  @moduledoc """
  How many rows fit in one `insert_all`.

  Postgres binds at most 65,535 parameters per statement and `insert_all` sends one per
  column per row, so the safe batch size is a function of how **wide** the row is, not a
  constant.

  This exists because the constant was wrong twice. A fixed 5,000 worked for a 13-column
  table and exceeded the limit at 18 (`Pramana.Translations`); the lesson was written
  down, and then a fresh 5,000 was written into `Pramana.Quotations` for a 17-column
  table and failed the same way. A rule in a document does not survive being reimplemented
  — a shared function does.

  Then it failed a **fourth** time, in `Pramana.Readings.store/1`, which had no batching
  at all and had simply never been handed enough rows to notice. That is the more useful
  diagnosis: offering `chunk/1` still leaves every call site free to forget, and a write
  path only reveals the omission once the data grows. `insert_all/4` is the fix — it
  takes the same arguments as `Repo.insert_all/3` and cannot be called without batching,
  so the decision is made once rather than remembered at each site.
  """

  alias Pramana.Repo

  @max_bind_params 65_535

  @doc """
  Rows per statement for a list of row maps, from the width of the first.

  Returns 1 for an empty list, so a caller can chunk unconditionally.
  """
  @spec size([map()]) :: pos_integer()
  def size([]), do: 1
  def size([row | _]) when is_map(row), do: max(div(@max_bind_params, map_size(row)), 1)

  @doc "Chunks rows into statements that Postgres will accept."
  @spec chunk([map()]) :: [[map()]]
  def chunk([]), do: []
  def chunk(rows), do: Enum.chunk_every(rows, size(rows))

  @doc """
  `Repo.insert_all/3` that cannot exceed the parameter limit.

  Same arguments, same return shape — the count summed across statements. Use this rather
  than `Repo.insert_all/3` anywhere the row count is not bounded by construction, which
  in this project means anywhere data comes from a file, a scan or a corpus.

  Not a transaction. Each statement commits on its own, which is what the callers want:
  every one of them is idempotent by conflict target, so a partial run is resumable
  rather than lost.
  """
  @spec insert_all(module(), [map()], keyword()) :: {non_neg_integer(), nil}
  def insert_all(schema, rows, opts \\ []) do
    written =
      rows
      |> chunk()
      |> Enum.reduce(0, fn statement, acc ->
        {n, _} = Repo.insert_all(schema, statement, opts)
        acc + n
      end)

    {written, nil}
  end
end
