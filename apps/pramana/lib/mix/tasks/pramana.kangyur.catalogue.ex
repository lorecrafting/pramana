defmodule Mix.Tasks.Pramana.Kangyur.Catalogue do
  @shortdoc "Titles the Kangyur from 84000's catalogue, and links it to BDRC"

  @moduledoc """
  Gives every Tōhoku number its name.

      mix pramana.kangyur.catalogue
      mix pramana.kangyur.catalogue --dry-run

  Expects 84000's RDF export at `raw/84000-rdf`, which is one file per Tōhoku number:

      curl -sL https://codeload.github.com/84000/data-rdf/tar.gz/refs/heads/master \\
        | tar -xz --strip-components=1 -C raw/84000-rdf

  The Derge etext titles **volumes**, not works, so the Kangyur was loaded titleless and
  `mix pramana.kangyur.translations` could only name the 385 texts 84000 has translated.
  This covers the catalogue: 1,160 Tōhoku numbers, translated or not, in English,
  Sanskrit and Tibetan.

  ## A published title is not overwritten

  Where a translation exists, its own title page is the better authority on what that
  translation is called, and it is already stored. The catalogue fills what is empty and
  records which source each title came from, so the two never silently disagree.

  ## Wylie is computed here, not copied

  The RDF carries no transliteration, so the Wylie is produced by
  `Pramana.Readings.Wylie` from the Tibetan and stored under a separate key —
  `title_bo_ltn_computed` — never mixed with the transliteration 84000 publishes in its
  TEI. One is a claim by the editors and the other is a claim by this code, and a reader
  comparing them must be able to tell which is which.

  ## What this makes possible next

  Each record carries the BDRC id of the Degé printing (`MW22084_0113`). That is the
  handle an IIIF manifest is addressed by, so a work in this corpus can be put beside a
  photograph of the woodblock page it was read from — the catalogue half of the Phase 5
  BDRC item, with no OCR involved.
  """

  use Mix.Task

  import Ecto.Query

  alias Pramana.Acquire.Lockfile
  alias Pramana.Bake
  alias Pramana.Corpus.Text
  alias Pramana.Corpus.Work
  alias Pramana.Normalize.Catalogue84000
  alias Pramana.Readings.Wylie
  alias Pramana.Repo
  alias Pramana.Sources

  @switches [dry_run: :boolean, root: :string]

  @default_root "raw/84000-rdf"
  @source_id "84000-rdf"

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _} = OptionParser.parse!(argv, strict: @switches)

    root = Keyword.get(opts, :root, @default_root)
    files = root |> Path.join("*.rdf") |> Path.wildcard() |> Enum.sort()

    if files == [], do: Mix.raise("no RDF under #{root} — see the moduledoc")

    Mix.shell().info("#{if opts[:dry_run], do: "DRY RUN — ", else: ""}#{length(files)} record(s)")

    # Both halves of the edition: 84000's catalogue covers Tengyur numbers too, and 61 of
    # its records had no work to attach to until the Tengyur was ingested.
    works =
      MapSet.new(
        Repo.all(
          from t in Text,
            where: t.source_id in ["derge", "derge-tengyur"],
            select: t.work_id
        )
      )

    tally = Enum.reduce(files, empty(), &apply_record(&1, &2, works, opts[:dry_run]))

    unless opts[:dry_run] do
      write_lockfile(files)
      # THE LOCKFILE AND THE BAKE ID MOVE TOGETHER. `bake_id` is a hash of
      # `sources.lock.json`, so writing it changes the id by definition, and a bake row that
      # no longer describes its inputs stamps every API response with an id for a corpus
      # that does not exist. `Bake.record/1` is cheap — a row, not a re-bake.
      {:ok, _} = Bake.record(%{"source" => "84000-rdf", "mode" => "kangyur_catalogue"})
    end

    report(tally, length(files))
  end

  defp empty do
    %{titled: 0, already: 0, bdrc: 0, wylie: 0, absent: 0, no_title: 0}
  end

  defp apply_record(path, tally, works, dry_run?) do
    {:ok, record} = path |> File.read!() |> Catalogue84000.parse()

    cond do
      # 84000 publishes a placeholder for a Tōhoku number it has not catalogued: the file
      # exists and holds nothing but the licence boilerplate. That is a record with no
      # content, not a work this corpus is missing, and reporting it as the latter sent me
      # looking for texts that were already here.
      is_nil(record.toh) or record.titles == %{} ->
        %{tally | no_title: tally.no_title + 1}

      not MapSet.member?(works, record.toh) ->
        %{tally | absent: tally.absent + 1}

      true ->
        apply_titles(record, tally, dry_run?)
    end
  end

  # Named `apply_titles` rather than `update` because `Ecto.Query.update/3` is imported.
  defp apply_titles(record, tally, dry_run?) do
    work = Repo.get(Work, record.toh)

    if is_nil(work) do
      %{tally | absent: tally.absent + 1}
    else
      wylie = record.titles["bo"] && Wylie.transliterate(record.titles["bo"])
      new? = is_nil(work.title) and not is_nil(record.titles["en"])

      unless dry_run?, do: write(work, record, wylie)

      %{
        tally
        | titled: tally.titled + if(new?, do: 1, else: 0),
          already: tally.already + if(work.title, do: 1, else: 0),
          bdrc: tally.bdrc + if(record.bdrc["derge"], do: 1, else: 0),
          wylie: tally.wylie + if(wylie, do: 1, else: 0)
      }
    end
  end

  defp write(work, record, wylie) do
    meta =
      (work.meta || %{})
      |> Map.merge(
        reject_nil(%{
          "title_sa_catalogue" => record.titles["sa"],
          "title_bo_ltn_computed" => wylie,
          "bdrc_derge" => record.bdrc["derge"],
          "bdrc_work" => record.bdrc["tibetan"],
          "bdrc_indic" => record.bdrc["indic"],
          "catalogue_translators" => present(record.translators),
          # Which claim came from where. Without it a later reader cannot tell a title the
          # translators printed from one the catalogue supplied.
          "title_catalogue_source" => @source_id
        })
      )

    work
    |> Ecto.Changeset.change(%{
      title: work.title || record.titles["en"],
      title_original: work.title_original || record.titles["bo"],
      meta: meta
    })
    |> Repo.update!()
  end

  defp reject_nil(map), do: map |> Enum.reject(fn {_k, v} -> is_nil(v) end) |> Map.new()

  defp present([]), do: nil
  defp present(list), do: list

  # Named `write_lockfile` because `Ecto.Query.lock/2` is imported here.
  defp write_lockfile(files) do
    source_root = Path.expand(Path.join(Lockfile.raw_dir(), @source_id))

    entries =
      Enum.map(files, fn path ->
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
        files: entries,
        pin: %{"type" => "content", "files_sha256" => Lockfile.manifest_hash(entries)}
      )

    :ok = Lockfile.put_source(entry)
  end

  defp report(tally, files) do
    total =
      Repo.aggregate(from(t in Text, where: t.source_id in ["derge", "derge-tengyur"]), :count)

    titled =
      Repo.aggregate(
        from(t in Text,
          join: w in Work,
          on: w.id == t.work_id,
          where: t.source_id in ["derge", "derge-tengyur"] and not is_nil(w.title)
        ),
        :count
      )

    Mix.shell().info("""

    titled the Kangyur from 84000's catalogue
      records:        #{files}
      newly titled:   #{tally.titled}
      already titled: #{tally.already}   (from the translations' own title pages, left alone)
      wylie computed: #{tally.wylie}
      bdrc linked:    #{tally.bdrc}
      no work here:   #{tally.absent}
      empty record:   #{tally.no_title}   (a placeholder for a number 84000 has not catalogued)

      Tibetan works with a title: #{titled}/#{total}
      licence:        CC0 — the metadata is redistributable even though the translations are not
    """)
  end
end
