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
  """

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
end
