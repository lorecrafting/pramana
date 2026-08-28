defmodule Mix.Tasks.Pramana.Kangyur.Translations do
  @shortdoc "Ingests 84000's English translations as renderings of the Derge Kangyur"

  @moduledoc """
  Attaches 84000's published translations to the Tibetan they translate.

      mix pramana.kangyur.translations
      mix pramana.kangyur.translations --limit 20
      mix pramana.kangyur.translations --dry-run

  Expects the checkout at `raw/84000/data-tei`. Nothing here becomes a citable text:
  84000's English is a **rendering** of a work this corpus already holds in Tibetan, so
  it is stored in the translation pool, addressed as `<derge anchor>#tr:en/84000`, and
  the guard rejects it if it is ever quoted as source (`CLAUDE.md` invariant #8).

  ## The anchor is a range, because the two editions cite at different grains

  Our Derge anchors are **lines** — `51.1b.3` — and 84000 marks **folios**. A folio's
  English therefore renders about seven of our lines, and it is stored against the range
  of exactly those lines, `51.1b.1-51.1b.7`. Anchoring it to the first line instead would
  be a smaller change and a false claim: it would say this English renders line 1.

  Every anchor is checked against the segments it names before the rendering is stored.
  A folio 84000 cites that our Derge text does not contain is **not stored**, and is
  counted in the report — the failure mode being guarded against is an anchor that
  resolves to the wrong passage, which no later check would catch.

  ## Which file wins when a text has two

  84000 renames files when a translation is revised — `the_gandhavyuha_sutra` became
  `the_stem_array` — and a mirror keeps both. 11 Tōhoku numbers arrive twice and 7 of
  those pairs differ in the text itself, being successive editions of the same
  translation. The `<edition>` version decides, compared as numbers: `v 1.0.30` is newer
  than `v 1.0.7` and older than `v 1.1.1`, all three of which a string comparison gets
  wrong.

  ## Titles

  The Derge etext titles volumes, not works, so its 1,195 works arrive titleless. 84000
  publishes each work's title in English, Sanskrit, Tibetan and Wylie, and those land on
  the works it has translated — 384 of them. The rest stay untitled rather than being
  given something invented; 84000's full catalogue covers all 1,169 Tōhoku numbers and is
  a separate acquisition.
  """

  use Mix.Task

  import Ecto.Query

  alias Pramana.Acquire.Lockfile
  alias Pramana.Corpus.Segment
  alias Pramana.Corpus.Text
  alias Pramana.Corpus.Work
  alias Pramana.Normalize.Tei84000
  alias Pramana.Normalize.Tei84000.Folios
  alias Pramana.Repo
  alias Pramana.Sources
  alias Pramana.Translations
  alias Pramana.URN

  @switches [limit: :integer, dry_run: :boolean, root: :string]

  @default_root "raw/84000/data-tei"
  @source_id "84000"
  @derge_source "derge"
  @derge_witness "D"
  @translator_id "84000"
  @lang "en"

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _} = OptionParser.parse!(argv, strict: @switches)

    root = Keyword.get(opts, :root, @default_root)
    files = root |> newest_per_work() |> take(opts[:limit])

    if files == [], do: Mix.raise("no translations under #{root} — see the moduledoc")

    Mix.shell().info("#{if opts[:dry_run], do: "DRY RUN — ", else: ""}#{length(files)} file(s)")

    tally = Enum.reduce(files, empty(), &ingest(&1, &2, opts[:dry_run]))

    unless opts[:dry_run], do: maybe_lock(root, opts[:limit])

    report(tally, length(files))
  end

  # The lockfile describes the whole source, so a `--limit` run must not write one — the
  # same rule the other ingests follow, for the same reason: a pin that describes less
  # than what was ingested would verify.
  defp maybe_lock(_root, limit) when not is_nil(limit) do
    Mix.shell().info("  (--limit run: sources.lock.json left alone)")
  end

  defp maybe_lock(root, _limit) do
    source_root = Path.expand(Path.join(Lockfile.raw_dir(), @source_id))

    files =
      root
      |> Path.join("translations/**/*.xml")
      |> Path.wildcard()
      |> Enum.map(fn path ->
        bytes = File.read!(path)

        %{
          path: Path.relative_to(Path.expand(path), source_root),
          sha256: Lockfile.sha256(bytes),
          bytes: byte_size(bytes)
        }
      end)

    {:ok, definition} = Sources.fetch(@source_id)

    entry =
      Lockfile.build_entry(definition,
        files: files,
        # A GitHub repository, but acquired file by file rather than as a checkout, so
        # there is no commit to name. The manifest hash is the pin.
        pin: %{"type" => "content", "files_sha256" => Lockfile.manifest_hash(files)}
      )

    :ok = Lockfile.put_source(entry)
  end

  defp empty do
    %{
      works: 0,
      titled: 0,
      spans: 0,
      stored: 0,
      unanchored: 0,
      unplaced: 0,
      rejected: [],
      absent: []
    }
  end

  # One file per Tōhoku number: the newest edition of it.
  defp newest_per_work(root) do
    root
    |> Path.join("translations/kangyur/translations/*.xml")
    |> Path.wildcard()
    |> Enum.map(&{&1, read(&1)})
    |> Enum.reject(&match?({_path, :error}, &1))
    |> Enum.group_by(fn {_path, parsed} -> primary(parsed) end)
    |> Enum.map(fn {_toh, candidates} -> Enum.max_by(candidates, &version/1) end)
    |> Enum.sort_by(fn {path, _parsed} -> path end)
  end

  defp read(path) do
    case path |> File.read!() |> Tei84000.parse() do
      {:ok, parsed} -> parsed
      {:error, _reason} -> :error
    end
  end

  defp primary(%{locations: [%{toh: toh} | _]}), do: toh
  defp primary(_parsed), do: nil

  # "v 1.0.30 2024" -> [1, 0, 30]. Compared as numbers because 1.0.30 is newer than
  # 1.0.7, which string ordering reverses.
  defp version({_path, %{edition: nil}}), do: []

  defp version({_path, %{edition: edition}}) do
    case Regex.run(~r/v\s*([\d.]+)/, edition) do
      [_, digits] -> digits |> String.split(".") |> Enum.map(&String.to_integer/1)
      nil -> []
    end
  end

  # Named `take` rather than `limit` because `Ecto.Query.limit/2` is imported here.
  defp take(files, nil), do: files
  defp take(files, n), do: Enum.take(files, n)

  defp ingest({path, parsed}, tally, dry_run?) do
    {:ok, split} = Folios.split(parsed)
    relative = Path.relative_to(path, File.cwd!())

    tally = %{tally | unplaced: tally.unplaced + split.unplaced}

    split.spans
    |> Enum.group_by(& &1.toh)
    |> Enum.reduce(tally, fn {toh, group}, tally ->
      store_work(work_id(toh), group, parsed, relative, tally, dry_run?)
    end)
  end

  # 84000 translates the dkar chag chapter by chapter under Toh 4568; this corpus holds
  # the catalogue as the single work it is (`Pramana.Normalize.Derge`), so its chapters
  # all render the same work. The folio anchors are unaffected — they are volume 103's.
  defp work_id("toh4568" <> _), do: "dkar-chag-103"
  defp work_id(toh), do: toh

  defp store_work(work_id, spans, parsed, file, tally, dry_run?) do
    case folios(work_id) do
      folios when map_size(folios) == 0 ->
        %{tally | absent: [work_id | tally.absent]}

      folios ->
        {rows, unanchored, rejected} = rows(spans, work_id, folios, parsed, file)

        unless dry_run? do
          {:ok, _} = Translations.store(rows)
          title(work_id, parsed)
        end

        %{
          tally
          | works: tally.works + 1,
            titled: tally.titled + if(parsed.titles["en"], do: 1, else: 0),
            spans: tally.spans + length(spans),
            stored: tally.stored + length(rows),
            unanchored: tally.unanchored + unanchored,
            rejected: tally.rejected ++ rejected
        }
    end
  end

  # A volume's worth of spans is accepted or refused together.
  #
  # 84000 numbers Toh 11's folios from the work's own beginning in its second volume —
  # `F.92.b` where the Degé prints `1a` — and 428 of those 610 numbers exist in that
  # volume of that work, so they anchor. To the wrong leaf. Every one would resolve,
  # byte-verify, and read as a translation of a passage it does not translate.
  #
  # What separates that from a real edge is how much of the volume lands: 490 of the 503
  # volume-groups anchor completely, and the ones that do not divide sharply — 99.4% and
  # 99.6%, which are texts where 84000 cites one folio past the end of ours, against 70%,
  # 67% and 0%, which are texts numbering something else. Nothing sits between except one
  # group of ten folios, and ten folios of English are cheap next to a wrong citation.
  @accept 0.95

  defp rows(spans, work_id, folios, parsed, file) do
    spans
    |> Enum.group_by(& &1.volume)
    |> Enum.reduce({[], 0, []}, fn {volume, group}, acc ->
      anchored = Enum.map(group, &{&1, Map.get(folios, {to_string(volume), &1.folio})})
      landed = Enum.count(anchored, fn {_span, lines} -> lines end)

      accept(anchored, landed, {work_id, volume}, {parsed, file}, acc)
    end)
  end

  defp accept(anchored, landed, {work_id, volume}, {parsed, file}, {rows, unanchored, rejected}) do
    if landed / length(anchored) >= @accept do
      new =
        anchored
        |> Enum.reject(fn {_span, lines} -> is_nil(lines) end)
        |> merge_by_folio()
        |> Enum.map(fn {span, lines} -> row(span, work_id, lines, parsed, file) end)

      {new ++ rows, unanchored + length(anchored) - landed, rejected}
    else
      {rows, unanchored, [{work_id, volume, landed, length(anchored)} | rejected]}
    end
  end

  # A folio can be marked twice in one file — a section break inside a leaf re-states
  # where the reader is — and both marks describe the same leaf, so they are two pieces of
  # one folio's English rather than two renderings of it. Storing them separately is not
  # an option the schema allows either: one anchor, one translator, one rendering.
  defp merge_by_folio(anchored) do
    anchored
    |> Enum.group_by(fn {span, _lines} -> span.folio end)
    |> Enum.map(fn
      {_folio, [single]} ->
        single

      {_folio, [{span, lines} | _] = pieces} ->
        {%{span | text: Enum.map_join(pieces, " ", fn {s, _} -> s.text end)}, lines}
    end)
  end

  # Every folio of a Derge work, with the first and last line printed on it. This is what
  # turns a folio-level rendering into a range of citable lines, and it comes from the
  # segments themselves so an anchor cannot name a line that does not exist.
  defp folios(work_id) do
    from(s in Segment,
      join: t in Text,
      on: t.id == s.text_id,
      where: t.work_id == ^work_id and t.source_id == ^@derge_source,
      select: {fragment("? ->> 'volume'", s.meta), s.page, s.ordinal, s.urn}
    )
    |> Repo.all()
    |> Enum.group_by(fn {volume, page, _ordinal, _urn} -> {volume, page} end)
    |> Map.new(fn {key, rows} ->
      sorted = Enum.sort_by(rows, fn {_v, _p, ordinal, _urn} -> ordinal end)
      {key, {edge(hd(sorted)), edge(List.last(sorted))}}
    end)
  end

  # The locator is what a reader cites; the ordinal is what a containment query compares.
  # `Pramana.Translations.covering/2` needs the second because a locator grammar belongs
  # to its edition — whether `51.100a.3` lies inside `51.100a.1-51.100a.7` is a fact about
  # Derge folios, while ordinals order every source the same way.
  defp edge({_volume, _page, ordinal, urn}) do
    %{locator: urn |> String.split("@", parts: 2) |> List.last(), ordinal: ordinal}
  end

  defp row(span, work_id, {first, last}, parsed, file) do
    %{
      anchor_urn: anchor(work_id, first, last),
      work_id: work_id,
      lang: @lang,
      translator_id: @translator_id,
      translator_name: Enum.join(parsed.translators, ", "),
      tier: "t0",
      method: "human",
      text: span.text,
      license_spdx: "CC-BY-NC-ND-3.0",
      license_class: "nc",
      redistributable: false,
      attribution:
        "Translated by " <>
          Enum.join(parsed.translators, ", ") <>
          " under the patronage and supervision of 84000: Translating the Words of the Buddha.",
      source_file: file,
      meta: %{
        "folio" => span.folio,
        "volume" => span.volume,
        "toh" => span.toh,
        "edition" => parsed.edition,
        "titles" => parsed.titles,
        "ordinal_start" => first.ordinal,
        "ordinal_end" => last.ordinal
      }
    }
  end

  defp anchor(work_id, %{locator: locator}, %{locator: locator}), do: urn(work_id, locator, nil)
  defp anchor(work_id, first, last), do: urn(work_id, first.locator, last.locator)

  defp urn(work_id, locator, locator_end) do
    URN.to_string(%URN{
      source: @derge_source,
      witness: @derge_witness,
      work: work_id,
      locator: locator,
      locator_end: locator_end
    })
  end

  # The Derge etext gives no work titles, so these are the first this corpus has for
  # Tibetan. English is the title, Tibetan the original; Sanskrit and Wylie go to meta
  # rather than being flattened into one of those two fields.
  defp title(work_id, %{titles: titles}) do
    case Repo.get(Work, work_id) do
      nil ->
        :ok

      work ->
        work
        |> Ecto.Changeset.change(%{
          title: titles["en"] || work.title,
          title_original: titles["bo"] || work.title_original,
          meta:
            Map.merge(work.meta || %{}, %{
              "title_sa" => titles["Sa-Ltn"],
              "title_bo_ltn" => titles["Bo-Ltn"],
              "title_source" => "84000"
            })
        })
        |> Repo.update!()
    end
  end

  defp report(tally, files) do
    {:ok, source} = Sources.fetch(@source_id)

    Mix.shell().info("""

    ingested 84000 translations
      files:        #{files}   (newest edition of each Tōhoku number)
      works:        #{tally.works} matched to a Derge text
      titled:       #{tally.titled}
      folio spans:  #{tally.spans}
      renderings:   #{tally.stored}
      not anchored: #{tally.unanchored} folios 84000 cites that the Derge text does not contain
      not placed:   #{tally.unplaced} folio references that fit no location in their file
      refused:      #{length(tally.rejected)} volume group(s) whose folio numbering is not the Degé's
      urn shape:    pramana:derge.D:toh113@51.1b.1-51.1b.7#tr:en/84000
      licence:      #{source.license.spdx} — NOT redistributable, no derivatives
    """)

    for work <- Enum.take(Enum.reverse(tally.absent), 10) do
      Mix.shell().error("  no Derge text for #{work}")
    end

    for {work, volume, landed, total} <- Enum.take(Enum.reverse(tally.rejected), 10) do
      Mix.shell().info(
        "  refused #{work} vol #{volume}: only #{landed}/#{total} folios are in the Derge text"
      )
    end
  end
end
