defmodule Mix.Tasks.Pramana.Kangyur.Glossary do
  @shortdoc "Ingests 84000's per-translation glossaries as Skt–Tib–En term anchors"

  @moduledoc """
  Loads the glossary each 84000 translator published with their translation.

      mix pramana.kangyur.glossary
      mix pramana.kangyur.glossary --dry-run

  58,820 entries across the published Kangyur: the English chosen, the Sanskrit behind it,
  the Tibetan the Degé prints, often a Chinese equivalent, and usually a note explaining
  the choice — each tied to the text it was glossed in. This is the Skt–Tib anchor set
  Phase 5 asks for, and it is made by the people who did the translating rather than
  assembled by matching strings.

  ## Evidence, not policy

  It is stored apart from `glossary_terms`, which is a different kind of thing: 376
  hand-pinned renderings for one Chinese commentary, answering *what should this be
  called*. These entries answer *what did this translator call it, in this text* — and two
  translators disagreeing is data rather than a conflict to resolve. **2,756 Sanskrit terms
  are rendered by more than one Tibetan** across the corpus, which is the divergence
  Phase 6 exists to measure, arriving early and for free.

  ## The attestation travels with the term

  84000 marks how each form is known, and most Sanskrit is `sourceUnspecified` — a
  reconstruction of what stood in a lost Indic original, not a quotation from one. Only
  575 Sanskrit terms in the whole Kangyur are attested in a source. That distinction is
  stored per language, so a caller can ask for only what a witness actually says.
  """

  use Mix.Task

  import Ecto.Query

  alias Pramana.Corpus.GlossaryEntry
  alias Pramana.Corpus.Loader
  alias Pramana.Corpus.Text
  alias Pramana.Normalize.Tei84000
  alias Pramana.Normalize.Tei84000.Glossary
  alias Pramana.Repo

  @switches [dry_run: :boolean, root: :string, limit: :integer]

  @default_root "raw/84000/data-tei"
  @source_id "84000"

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _} = OptionParser.parse!(argv, strict: @switches)

    root = Keyword.get(opts, :root, @default_root)

    files =
      root
      |> Path.join("translations/kangyur/translations/*.xml")
      |> Path.wildcard()
      |> Enum.sort()
      |> take(opts[:limit])

    if files == [], do: Mix.raise("no translations under #{root}")

    Mix.shell().info("#{if opts[:dry_run], do: "DRY RUN — ", else: ""}#{length(files)} file(s)")

    works = MapSet.new(Repo.all(from t in Text, where: t.source_id == "derge", select: t.work_id))

    # The glossary rows reference the source, and 84000's translations live in a table
    # that does not — so nothing had yet recorded its licence in `sources`.
    unless opts[:dry_run], do: Loader.ensure_source!(@source_id)

    tally = Enum.reduce(files, empty(), &ingest(&1, &2, works, opts[:dry_run]))

    report(tally)
  end

  defp take(files, nil), do: files
  defp take(files, n), do: Enum.take(files, n)

  defp empty, do: %{files: 0, entries: 0, stored: 0, unlinked: 0}

  defp ingest(path, tally, works, dry_run?) do
    xml = File.read!(path)
    {:ok, parsed} = Tei84000.parse(xml)
    {:ok, entries} = Glossary.parse(xml)

    work_id = work_id(parsed, works)
    rows = Enum.map(entries, &row(&1, work_id, Path.relative_to(path, File.cwd!())))
    rows = Enum.reject(rows, &empty_row?/1)

    unless dry_run?, do: store(rows)

    %{
      tally
      | files: tally.files + 1,
        entries: tally.entries + length(entries),
        stored: tally.stored + length(rows),
        unlinked: tally.unlinked + if(is_nil(work_id), do: length(rows), else: 0)
    }
  end

  # The glossary belongs to the translation, and the translation belongs to a Tōhoku
  # number this corpus may or may not hold. An entry whose work is absent is still stored:
  # a term is a term, and `work_id` being null says exactly what is true — that the text
  # it was glossed in is not here.
  defp work_id(%{locations: [%{toh: toh} | _]}, works) do
    id = if String.starts_with?(toh, "toh4568"), do: "dkar-chag-103", else: toh
    if MapSet.member?(works, id), do: id
  end

  defp work_id(_parsed, _works), do: nil

  defp empty_row?(row),
    do: is_nil(row.sanskrit) and is_nil(row.tibetan) and is_nil(row.english)

  defp row(entry, work_id, file) do
    now = DateTime.utc_now()

    %{
      source_id: @source_id,
      work_id: work_id,
      gloss_id: entry.gloss_id,
      english: entry.english,
      english_alternatives: entry.english_alternatives,
      sanskrit: entry.sanskrit,
      sanskrit_attestation: entry.sanskrit_attestation,
      tibetan: entry.tibetan,
      wylie: entry.wylie,
      tibetan_attestation: entry.tibetan_attestation,
      chinese: entry.chinese,
      chinese_attestation: entry.chinese_attestation,
      pali: entry.pali,
      definition: entry.definition,
      meta: %{"source_file" => file},
      inserted_at: now,
      updated_at: now
    }
  end

  defp store([]), do: :ok

  defp store(rows) do
    rows
    |> Enum.uniq_by(& &1.gloss_id)
    |> Enum.chunk_every(2_000)
    |> Enum.each(
      &Repo.insert_all(GlossaryEntry, &1,
        on_conflict:
          {:replace,
           [
             :work_id,
             :english,
             :english_alternatives,
             :sanskrit,
             :sanskrit_attestation,
             :tibetan,
             :wylie,
             :tibetan_attestation,
             :chinese,
             :chinese_attestation,
             :pali,
             :definition,
             :meta,
             :updated_at
           ]},
        conflict_target: [:source_id, :gloss_id]
      )
    )
  end

  defp report(tally) do
    stored = Repo.aggregate(GlossaryEntry, :count)

    stats =
      Repo.one(
        from g in GlossaryEntry,
          select: %{
            sanskrit: count(g.sanskrit),
            tibetan: count(g.tibetan),
            chinese: count(g.chinese),
            definitions: count(g.definition),
            attested_sanskrit:
              fragment("count(*) filter (where ? = 'source')", g.sanskrit_attestation)
          }
      )

    distinct =
      Repo.one(
        from g in GlossaryEntry,
          select: %{
            sanskrit: fragment("count(distinct ?)", g.sanskrit),
            tibetan: fragment("count(distinct ?)", g.tibetan)
          }
      )

    Mix.shell().info("""

    ingested 84000's glossaries
      files:              #{tally.files}
      entries seen:       #{tally.entries}
      stored:             #{tally.stored}#{if tally.unlinked > 0, do: " (#{tally.unlinked} in texts this corpus does not hold)"}

      in the table:       #{stored}
      with Sanskrit:      #{stats.sanskrit}   (#{stats.attested_sanskrit} attested in a source; the rest reconstructed)
      with Tibetan:       #{stats.tibetan}
      with Chinese:       #{stats.chinese}
      with a definition:  #{stats.definitions}

      distinct Sanskrit terms: #{distinct.sanskrit}
      distinct Tibetan terms:  #{distinct.tibetan}
    """)
  end
end
