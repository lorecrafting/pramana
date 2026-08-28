defmodule Mix.Tasks.Pramana.Derge.Ingest do
  @shortdoc "Ingests the Digital Derge Kangyur, volume by volume"

  @moduledoc """
  Bakes the Derge (sde dge) Kangyur from the Esukhia–Barom etext.

      mix pramana.derge.ingest                     # the Kangyur, all 103 volumes
      mix pramana.derge.ingest --collection tengyur  # the other half, 213 volumes
      mix pramana.derge.ingest --limit 5           # a prefix, for iterating
      mix pramana.derge.ingest --dry-run

  Expects the unpacked edition at `raw/derge/UT4CZ5369-200106`, one directory per volume,
  one TEI file inside each.

  ## Volumes are fed in printed order, and the order comes from the volumes

  A work runs across volumes and only the volume where it begins carries its `toh`
  marker, so this is a single ordered walk, not a per-file job that could be run
  concurrently (`Pramana.Normalize.Derge.Edition`). The order is taken from the `[N]` each
  volume prints on its own title page rather than from the directory listing, because the
  directory names are BDRC image-group ids. They happen to sort correctly. Out-of-order
  volumes would not error — they would mislabel every anchor in the edition — so the run
  refuses to start unless the numbers it read are exactly 1..N with nothing missing.

  ## Two collections, one edition, two provenances

  The Degé print is a Kangyur and a Tengyur, and they are not the same kind of text. The
  Kangyur is what the tradition holds to be the Buddha's word; the Tengyur is the Indian
  commentarial literature on it — Nāgārjuna, Vasubandhu, Candrakīrti. Loading the second
  as `root` would present a treatise as scripture, which is invariant #4 failing at the
  point of ingest, so the collection decides `text_role` and nothing else does.

  They also arrive in different formats. Esukhia publishes the Kangyur as TEI with work
  markers and the Tengyur as TEI **without** them — 212 files, not one `unit="text"`
  milestone between them — so the Tengyur is read from its annotated plain text instead,
  through `Pramana.Normalize.DergeTengyur`. The walk over volumes is the same for both.

  ## Provenance is `probable`, not `certain`

  Every text in the Kangyur is presented by the tradition as a translation of an Indic
  original, and for the overwhelming majority that is right. It is not right for all of
  them — the *mdzangs blun* was assembled in Central Asia from Chinese, and a handful of
  others are disputed — and this etext carries no catalogue data to tell them apart. So
  the whole collection is loaded `indic` / `root` with `attribution_confidence:
  "probable"`, which is the claim actually being made: *this is where the Kangyur places
  it*. The 84000 catalogue (#21, the Toh join) has per-work origin data and can correct
  individual works to `certain` or `disputed` afterwards. Recording `certain` now would
  be faster and would make the correction indistinguishable from a bug.

  The *dkar chag* is the exception and is loaded as what it is: a Tibetan-composed
  catalogue, `tibetan` / `catalogue` / `certain`.

  ## Titles are absent on purpose

  The etext gives a Tibetan title for each *volume*, not for each work. A work's title
  sits inside its own opening lines (`rgya gar skad du…`), and lifting it out means
  parsing prose. Rule 5 says deterministic before probabilistic, and the deterministic
  source exists: 84000's catalogue publishes the title of every Toh number in four
  languages. Works land here titleless and are titled by that join, never by guesswork.
  """

  use Mix.Task

  alias Pramana.Acquire.Lockfile
  alias Pramana.Bake
  alias Pramana.Corpus.Loader
  alias Pramana.Normalize.Derge.Edition
  alias Pramana.Segment
  alias Pramana.Sources

  @switches [limit: :integer, dry_run: :boolean, root: :string, collection: :string]

  @witness "D"

  # What differs between the two halves of the edition, in one place: where the files are,
  # what reads them, which volume is a catalogue rather than a text, and what kind of text
  # the collection holds.
  @collections %{
    "kangyur" => %{
      source_id: "derge",
      root: "raw/derge/UT4CZ5369-200106",
      normalizer: Pramana.Normalize.Derge,
      discovery: Pramana.Normalize.Derge.Edition,
      catalogue_volumes: [103],
      text_role: "root"
    },
    "tengyur" => %{
      source_id: "derge-tengyur",
      # Under `raw/<source_id>/` because `Pramana.Acquire.Lockfile.verify/1` resolves every
      # recorded path against exactly that. Held at `raw/tengyur/` the lock recorded
      # absolute paths — `Path.relative_to/2` returns the path unchanged when the prefix
      # does not match — and all 213 entries failed to verify on this machine and could
      # never have verified on another.
      root: "raw/derge-tengyur/text",
      normalizer: Pramana.Normalize.DergeTengyur,
      discovery: Pramana.Normalize.DergeTengyur,
      # Empty not because the Tengyur has no dkar chag — volume 213 is exactly that — but
      # because this release ships it with no bytes, so it needs no exclusion. The
      # empty-volume path in `Derge.Edition` counts and skips it.
      catalogue_volumes: [],
      text_role: "treatise"
    }
  }

  # Volume 103 of the Kangyur is the dkar chag, the edition's own index. Which volume that
  # is, is a fact about the edition and not about the markup: eight `toh` markers sit in
  # its running list of titles, and splitting on them yields works a few words long that
  # collide on the URN with the real text. Median characters between markers there: 24,
  # against 7,804 in every other volume. The Tengyur has no such volume.

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _} = OptionParser.parse!(argv, strict: @switches)

    collection = collection(opts[:collection])
    root = Keyword.get(opts, :root, collection.root)
    volumes = root |> discover(collection) |> limit(opts[:limit])

    Mix.shell().info(
      "#{if opts[:dry_run], do: "DRY RUN — ", else: ""}#{collection.source_id}: " <>
        "#{length(volumes)} volume(s)"
    )

    paths = Map.new(volumes)

    case Edition.reduce(
           read_lazily(volumes),
           {0, []},
           &store(&1, &2, paths, collection, opts[:dry_run]),
           catalogue_volumes: collection.catalogue_volumes,
           normalizer: collection.normalizer
         ) do
      {:ok, {segments, failed}, stats} ->
        if opts[:dry_run] do
          report(stats, segments, failed, nil, collection)
        else
          maybe_lock(root, volumes, opts[:limit], collection)

          {:ok, bake} =
            Bake.record(%{"source" => collection.source_id, "mode" => "derge_ingest"})

          report(stats, segments, failed, bake, collection)
        end

      {:error, {:empty_volume, volume}} ->
        Mix.raise("volume #{volume} produced no lines — see Pramana.Normalize.Derge.Edition")

      {:error, reason} ->
        Mix.raise("derge ingest failed: #{inspect(reason)}")
    end
  end

  # One volume's XML in memory at a time. The whole edition is 336 MB and a single work
  # can span thirteen volumes, so the accumulated work is unavoidable; 103 files of it is
  # not.
  defp read_lazily(volumes) do
    Stream.map(volumes, fn {volume, path} -> {volume, File.read!(path)} end)
  end

  defp collection(nil), do: @collections["kangyur"]

  # `case` over `Map.get_lazy/3`: the fallback only raises, so as an anonymous function it
  # has no local return and dialyzer flags it. Same behaviour, and the raise is now in a
  # branch rather than in a function claiming to produce a collection.
  defp collection(name) do
    case Map.fetch(@collections, name) do
      {:ok, collection} -> collection
      :error -> Mix.raise("unknown collection #{inspect(name)}; expected kangyur or tengyur")
    end
  end

  defp discover(root, collection) do
    case collection.discovery.volumes_at(root) do
      {:ok, volumes} ->
        volumes

      {:error, {:no_volumes_at, root}} ->
        Mix.raise("no TEI under #{root} — see the moduledoc for the expected layout")

      {:error, {:volume_unnamed, path}} ->
        Mix.raise("#{path} does not name its volume in its title")

      {:error, {:volumes_not_contiguous, missing, duplicated}} ->
        Mix.raise(
          "volumes are not contiguous: #{inspect(missing)} missing, " <>
            "#{inspect(duplicated)} duplicated"
        )
    end
  end

  # A slice for iterating. It must be a PREFIX of the edition, never an arbitrary subset,
  # because a work that begins before the slice cannot be assembled inside it — and the
  # work still open when the slice ends is stored truncated, which is why `--limit` never
  # writes a lockfile and is not a way to ingest part of the canon.
  defp limit(volumes, nil), do: volumes
  defp limit(volumes, n), do: Enum.take(volumes, n)

  defp store(ir, {segments, failed}, _paths, _collection, true),
    do: {segments + length(ir.lines), failed}

  defp store(ir, {segments, failed}, paths, collection, _dry_run) do
    # One malformed work fails its own row, not the run — the same isolation as
    # `pramana.bake_all`. `Loader.load/2` signals failure by raising.
    {:ok, %{segments: count}} = load(ir, paths, collection)
    {segments + count, failed}
  rescue
    error -> {segments, [{ir.work_id, Exception.message(error)} | failed]}
  end

  defp load(ir, paths, collection) do
    Loader.load(ir,
      source: collection.source_id,
      witness: @witness,
      segmenter: Segment.Derge,
      provenance: provenance(ir, collection),
      # The anchor is a position on a printed leaf of one edition — folio, side, line —
      # not a scheme that survives being lifted out of it. That is `edition_page`, the
      # same claim the Taishō makes with page/register/line.
      addressing: "edition_page",
      # A spanning work cannot be re-derived from any one file, so every file it drew
      # from is recorded. `mix pramana.verify` re-walks exactly these.
      source_file: ir |> Edition.volumes() |> Enum.map_join(" ", &relative(paths[&1]))
    )
  end

  defp relative(path), do: Path.relative_to(path, File.cwd!())

  defp provenance(%{work_id: "dkar-chag-" <> _}, _collection) do
    %{
      composition_origin: "tibetan",
      text_role: "catalogue",
      attribution_confidence: "certain"
    }
  end

  # The collection decides what kind of text this is. A Tengyur treatise loaded as `root`
  # would present Nagarjuna as the Buddha, which is the mislabelling this project exists
  # to prevent, arriving at the moment of ingest.
  defp provenance(_ir, collection) do
    %{
      composition_origin: "indic",
      text_role: collection.text_role,
      attribution_confidence: "probable"
    }
  end

  # A `--limit` run must not write a lockfile: the lock is a claim about what the whole
  # source IS, and one describing less than what was ingested is worse than none, because
  # it would verify.
  defp maybe_lock(root, volumes, nil, collection), do: :ok = lock(root, volumes, collection)

  defp maybe_lock(_root, _volumes, _limit, _collection) do
    Mix.shell().info("  (--limit run: sources.lock.json left alone)")
  end

  defp lock(root, volumes, collection) do
    # `Lockfile.verify/1` resolves each entry against `raw/<source_id>/`, so the path must
    # be relative to that and to nothing else. Both sides are expanded because the
    # discovered paths are relative to the cwd while `raw_dir/0` is absolute, and
    # `Path.relative_to/2` silently returns the path unchanged when the prefix does not
    # match — which produces a lockfile that looks right and verifies nothing.
    source_root = Path.expand(Path.join(Lockfile.raw_dir(), collection.source_id))

    files =
      Enum.map(volumes, fn {_volume, path} ->
        bytes = File.read!(path)

        %{
          path: Path.relative_to(Path.expand(path), source_root),
          sha256: Lockfile.sha256(bytes),
          bytes: byte_size(bytes)
        }
      end)

    {:ok, definition} = Sources.fetch(collection.source_id)

    entry =
      Lockfile.build_entry(definition,
        files: files,
        # Distributed as a dated archive rather than a repository, so there is no commit
        # to pin. The hash over the file manifest is the pin.
        pin: %{
          "type" => "content",
          "files_sha256" => Lockfile.manifest_hash(files),
          "edition" => Path.basename(root)
        }
      )

    Lockfile.put_source(entry)
  end

  defp report(stats, segments, failed, bake, collection) do
    Mix.shell().info("""

    ingested #{collection.source_id}
      volumes:    #{stats.volumes}
      works:      #{stats.works}#{spanning(stats)}
      lines:      #{stats.lines}
      segments:   #{segments}
      failed:     #{length(failed)}
      urn shape:  pramana:derge.D:toh1@1.1b.1   (volume, folio and side, line)
      licence:    public-domain, REDISTRIBUTABLE
      titles:     none — they come from the 84000 catalogue join
    #{baked(bake)}
    """)

    for {work, reason} <- Enum.take(failed, 10) do
      Mix.shell().error("  FAILED #{work}: #{inspect(reason)}")
    end
  end

  defp spanning(%{spanning: 0}), do: ""
  defp spanning(stats), do: " (#{stats.spanning} spanning more than one volume)"

  defp baked(nil), do: "  nothing written"

  defp baked(bake) do
    """
      bake_id:    #{bake.id}
      corpus:     #{bake.stats["texts"]} text(s), #{bake.stats["segments"]} segments\
    """
  end
end
