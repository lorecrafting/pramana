defmodule Mix.Tasks.Pramana.Derge.Titles do
  @shortdoc "Promotes the Degé title already held in works.meta into works.title"

  @moduledoc """
      mix pramana.derge.titles           # report only, writes nothing
      mix pramana.derge.titles --write

  **2,675 Tengyur works have a title and cannot be found by it**, because the Degé ingest
  writes the incipit into `works.meta` — `title_sa_ltn_computed`, `title_bo_ltn_computed`,
  `title_sa_bo_script` — while `works.title` stays null. `get_outline` and `search` read
  `title`, so half a canon is segmented, embedded and nameless to a reader, including the
  whole *pramāṇa* literature this system is named after: `toh4210` holds
  `pra mA Na bAr ti kA kA ri kA` and shows nothing.

  Nothing here parses anything. The extraction already happened at ingest; this promotes
  it into the column that is read.

  ## Sanskrit first, then Tibetan

  `title` prefers the romanised **Sanskrit** where the work has one, because an
  English-speaking reader looking for the *Pramāṇavārttika* will not type
  `tshad ma rnam 'grel`. Where there is no Sanskrit — Tibetan-composed treatises in the
  Tengyur never had one — the romanised Tibetan is the handle.

  ## It only ever fills a blank

  The Kangyur already carries curated English titles from 84000 ("The Chapter on Going
  Forth"), and overwriting those with Wylie would be a straight regression. This writes
  **only where `title` is null**, so running it against the whole Tibetan canon is safe
  and re-running it is a no-op.
  """

  use Mix.Task

  alias Pramana.Repo

  @switches [write: :boolean]

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _} = OptionParser.parse!(argv, strict: @switches)

    before = census()
    if opts[:write], do: promote()
    now = census()

    Mix.shell().info("""

    #{if opts[:write], do: "promoted meta titles into works.title", else: "DRY RUN — nothing written; add --write"}

    #{Enum.map_join(now, "\n", &row(&1, before))}

    A work with no romanised title in meta has no title block in the edition — a
    continuation of a work spanning volumes, mostly. Those stay nameless and are counted
    here rather than hidden.
    """)
  end

  # Sanskrit before Tibetan, and only into a null. `updated_at` moves so the change is
  # visible to anything watching the row.
  defp promote do
    Repo.query!("""
    UPDATE works w
       SET title = COALESCE(w.meta ->> 'title_sa_ltn_computed',
                            w.meta ->> 'title_bo_ltn_computed'),
           updated_at = now()
     WHERE w.title IS NULL
       AND (w.meta ? 'title_sa_ltn_computed' OR w.meta ? 'title_bo_ltn_computed')
       AND EXISTS (SELECT 1 FROM texts t
                    WHERE t.work_id = w.id AND t.source_id IN ('derge', 'derge-tengyur'))
    """)
  end

  defp census do
    %{rows: rows} =
      Repo.query!("""
      SELECT t.source_id,
             count(DISTINCT w.id),
             count(DISTINCT w.id) FILTER (WHERE w.title IS NOT NULL),
             count(DISTINCT w.id) FILTER (WHERE w.title IS NULL
               AND (w.meta ? 'title_sa_ltn_computed' OR w.meta ? 'title_bo_ltn_computed'))
        FROM works w JOIN texts t ON t.work_id = w.id
       WHERE t.source_id IN ('derge', 'derge-tengyur')
       GROUP BY 1 ORDER BY 1
      """)

    Enum.map(rows, fn [s, works, titled, promotable] ->
      %{source: s, works: works, titled: titled, promotable: promotable}
    end)
  end

  defp row(now, before) do
    was = Enum.find(before, &(&1.source == now.source)) || now
    pct = if now.works > 0, do: Float.round(now.titled / now.works * 100, 1), else: 0.0

    "  #{String.pad_trailing(now.source, 16)} #{now.titled}/#{now.works} titled (#{pct}%)" <>
      "   gained #{now.titled - was.titled}   still promotable #{now.promotable}" <>
      "   no title block #{now.works - now.titled - now.promotable}"
  end
end
