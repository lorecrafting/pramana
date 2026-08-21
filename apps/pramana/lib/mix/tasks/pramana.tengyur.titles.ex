defmodule Mix.Tasks.Pramana.Tengyur.Titles do
  @shortdoc "Reads Tengyur work titles out of the works themselves"

  @moduledoc """
  Gives the Tengyur its names, from the edition rather than from a catalogue.

      mix pramana.tengyur.titles            # write them
      mix pramana.tengyur.titles --dry-run  # report only

  84000 has catalogued the Kangyur and not the commentaries, so all 3,380 Tengyur works
  loaded addressable only by Tōhoku number. Acquiring a catalogue (rKTs, BDRC, Adarsha)
  would mean a new source, a new licence axis and a new lockfile entry.

  None of that is needed: a translated Indian treatise opens by naming itself in both
  languages, and `Pramana.Tengyur.Titles` reads that. The title is then **`source`
  attested** — the words the edition prints — rather than a modern editor's identification.

  ## What is written

  - `title_original` — the Tibetan title
  - `meta.title_sa_bo_script` — the Sanskrit title **as transliterated into Tibetan
    letters**, which is what the page shows; not Devanāgarī, not romanised Sanskrit
  - `meta.title_bo_ltn_computed` / `meta.title_sa_ltn_computed` — Wylie, computed by
    `Pramana.Readings.Wylie`, so the titles are searchable and readable without Tibetan script
  - `meta.title_source` — `derge-tengyur:incipit`, so a later reader can tell a title the
    translators printed from one a catalogue supplied

  **No English title is written**, because none is known. A work whose English name is
  unknown stays unknown; inventing one is the same failure as inventing a citation id.

  Existing titles are never overwritten — if a catalogue lands later it can fill the ~23%
  that do not name themselves, and this task will not fight it.
  """

  use Mix.Task

  import Ecto.Query

  alias Pramana.Corpus.Segment
  alias Pramana.Corpus.Text
  alias Pramana.Corpus.Work
  alias Pramana.Readings.Wylie
  alias Pramana.Repo
  alias Pramana.Tengyur.Titles

  @switches [dry_run: :boolean, limit: :integer]

  @source_id "derge-tengyur"

  # The title formula sits in the first line or two. Reading four is slack for a work whose
  # head ornament or homage is split across lines; reading the whole work would be 891,169
  # segments for a string that is always at the top.
  @head_lines 4

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _, _} = OptionParser.parse(argv, switches: @switches)

    works = works(opts[:limit])

    tally =
      works
      |> Enum.reduce(empty_tally(), fn text, tally ->
        text |> head_text() |> Titles.extract() |> apply_titles(text, tally, opts[:dry_run])
      end)

    report(tally, length(works), opts[:dry_run])
  end

  defp works(limit) do
    query =
      from t in Text,
        where: t.source_id == ^@source_id,
        select: %{id: t.id, work_id: t.work_id},
        order_by: t.work_id

    query |> take(limit) |> Repo.all()
  end

  # Named `take` because `Ecto.Query.limit/2` is imported.
  defp take(query, nil), do: query
  defp take(query, n), do: limit(query, ^n)

  defp head_text(text) do
    Repo.all(
      from s in Segment,
        where: s.text_id == ^text.id,
        order_by: s.ordinal,
        limit: @head_lines,
        select: s.content
    )
    |> Enum.join("")
  end

  defp apply_titles(titles, _text, tally, _dry_run) when map_size(titles) == 0,
    do: %{tally | unnamed: tally.unnamed + 1}

  defp apply_titles(titles, text, tally, dry_run) do
    work = Repo.get(Work, text.work_id)

    cond do
      is_nil(work) -> %{tally | absent: tally.absent + 1}
      work.title_original -> %{tally | already: tally.already + 1}
      true -> write_titles(work, titles, tally, dry_run)
    end
  end

  defp write_titles(work, titles, tally, dry_run) do
    unless dry_run, do: write(work, titles)

    %{
      tally
      | titled: tally.titled + 1,
        sanskrit: tally.sanskrit + if(titles[:sa_bo], do: 1, else: 0)
    }
  end

  defp write(work, titles) do
    meta =
      (work.meta || %{})
      |> Map.merge(
        reject_nil(%{
          "title_sa_bo_script" => titles[:sa_bo],
          "title_sa_ltn_computed" => titles[:sa_bo] && Wylie.transliterate(titles[:sa_bo]),
          "title_bo_ltn_computed" => titles[:bo] && Wylie.transliterate(titles[:bo]),
          "title_source" => "#{@source_id}:incipit"
        })
      )

    work
    |> Ecto.Changeset.change(%{title_original: titles[:bo], meta: meta})
    |> Repo.update!()
  end

  defp reject_nil(map), do: map |> Enum.reject(fn {_k, v} -> is_nil(v) end) |> Map.new()

  defp empty_tally,
    do: %{titled: 0, sanskrit: 0, unnamed: 0, already: 0, absent: 0}

  defp report(tally, total, dry_run) do
    Mix.shell().info("""

    #{if dry_run, do: "would title", else: "titled"} the Tengyur from its own incipits
      works examined:   #{total}
      titled:           #{tally.titled} (#{percent(tally.titled, total)}%)
      with Sanskrit:    #{tally.sanskrit}
      name themselves not: #{tally.unnamed} — no title written, and none invented
      already titled:   #{tally.already}
      work row absent:  #{tally.absent}
      attestation:      source — the words the edition prints, not a catalogue's reading
      English titles:   none. 84000 has not translated the Tengyur, so none is known.
    """)
  end

  defp percent(_n, 0), do: 0
  defp percent(n, total), do: Float.round(n * 100 / total, 1)
end
