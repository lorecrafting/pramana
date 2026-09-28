defmodule Mix.Tasks.Pramana.Texts.CountChars do
  @shortdoc "Backfills texts.char_count for rows baked before the column existed"

  @moduledoc """
  Fills in `texts.char_count` where it is null.

      mix pramana.texts.count_chars

  New rows get it at load time, in the same transaction as the body. This is only for a bake
  that predates the column — see the migration for why the column exists at all: computing
  the total on demand detoasts every text in the corpus and cost the reader's `/inventory`
  page ten seconds on every load.

  Idempotent, and it does not rewrite rows that already have a count. Safe to re-run and safe
  to interrupt: it works in bounded transactions. Counts are Unicode grapheme clusters,
  exactly as in the loader, not UTF-8 bytes or PostgreSQL code points. Text bytes are
  never normalized or rewritten. Existing non-null counts are preserved; this command
  is not a repair of counts written by an older implementation.
  """

  use Mix.Task

  import Ecto.Query

  alias Pramana.Corpus.Text
  alias Pramana.Elapsed
  alias Pramana.Repo

  @batch 500

  @impl Mix.Task
  def run(_argv) do
    Mix.Task.run("app.start")
    started = System.monotonic_time(:millisecond)

    pending = Repo.aggregate(from(t in Text, where: is_nil(t.char_count)), :count)
    Mix.shell().info("#{pending} text(s) without a character count")

    filled = fill(0)

    Mix.shell().info(
      "filled #{filled} in #{Elapsed.human(System.monotonic_time(:millisecond) - started)}"
    )
  end

  # PostgreSQL char_length counts code points, whereas the loader counts grapheme
  # clusters. Read only a bounded batch and use the SAME unit. Row locks ensure that
  # a concurrent reload cannot leave a count calculated from an older body.
  defp fill(done) do
    {:ok, count} = Repo.transaction(&fill_batch/0)

    if count == 0 do
      done
    else
      Mix.shell().info("  #{done + count}…")
      fill(done + count)
    end
  end

  defp fill_batch do
    rows =
      Repo.all(
        from(t in Text,
          where: is_nil(t.char_count),
          order_by: t.id,
          limit: @batch,
          lock: "FOR UPDATE",
          select: {t.id, t.body}
        )
      )

    Enum.each(rows, fn {id, body} ->
      {1, nil} =
        Repo.update_all(from(t in Text, where: t.id == ^id),
          set: [char_count: String.length(body)]
        )
    end)

    length(rows)
  end
end
