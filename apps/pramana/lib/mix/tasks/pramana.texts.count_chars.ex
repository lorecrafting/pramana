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
  to interrupt: it works in batches, and each batch is its own statement.
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

  # BATCHED, and in SQL. `char_length` is Postgres counting characters rather than bytes —
  # the same thing `String.length/1` gives the loader — so a backfilled row and a freshly
  # loaded one agree. Pulling bodies into the VM to count them would move 548 million
  # characters across the wire to produce one integer per row.
  defp fill(done) do
    {count, _} =
      Repo.update_all(
        from(t in Text,
          where:
            t.id in subquery(
              from(x in Text, where: is_nil(x.char_count), select: x.id, limit: @batch)
            ),
          update: [set: [char_count: fragment("char_length(body)")]]
        ),
        []
      )

    if count == 0 do
      done
    else
      Mix.shell().info("  #{done + count}…")
      fill(done + count)
    end
  end
end
