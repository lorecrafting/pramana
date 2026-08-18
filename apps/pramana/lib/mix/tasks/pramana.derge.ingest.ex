defmodule Mix.Tasks.Pramana.Derge.Ingest do
  @shortdoc "Ingests the Digital Derge Kangyur, volume by volume"

  @moduledoc """
  Bakes the Derge (sde dge) Kangyur from the Esukhia–Barom etext.

      mix pramana.derge.ingest                  # all 103 volumes
      mix pramana.derge.ingest --limit 5        # the first five, for iterating
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

  @switches [limit: :integer, dry_run: :boolean, root: :string]

  @default_root "raw/derge/UT4CZ5369-200106"
  @source_id "derge"
  @witness "D"

  # Volume 103 is the dkar chag, the edition's own index. Which volume that is, is a fact
  # about the edition and not about the markup: eight `toh` markers sit in its running
  # list of titles, and splitting on them yields works a few words long that collide on
  # the URN with the real text. Median characters between markers there: 24, against
  # 7,804 in every other volume.
  @catalogue_volume 103

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _, _} = OptionParser.parse(argv, switches: @switches)

    root = Keyword.get(opts, :root, @default_root)
    volumes = root |> discover() |> limit(opts[:limit])

    Mix.shell().info(
      "#{if opts[:dry_run], do: "DRY RUN — ", else: ""}#{length(volumes)} volume(s), " <>
        "#{@catalogue_volume} as catalogue"
    )

    paths = Map.new(volumes)

    case Edition.reduce(read_lazily(volumes), {0, []}, &store(&1, &2, paths, opts[:dry_run]),
           catalogue_volumes: [@catalogue_volume]
         ) do
      {:ok, {segments, failed}, stats} ->
        if opts[:dry_run] do
          report(stats, segments, failed, nil)
        else
          maybe_lock(root, volumes, opts[:limit])
          {:ok, bake} = Bake.record(%{"source" => @source_id, "mode" => "derge_ingest"})
          report(stats, segments, failed, bake)
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

  defp discover(root) do
    case Edition.volumes_at(root) do
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

  defp store(ir, {segments, failed}, _paths, true), do: {segments + length(ir.lines), failed}

  defp store(ir, {segments, failed}, paths, _dry_run) do
    # One malformed work fails its own row, not the run — the same isolation as
    # `pramana.bake_all`. `Loader.load/2` signals failure by raising.
    {:ok, %{segments: count}} = load(ir, paths)
    {segments + count, failed}
  rescue
    error -> {segments, [{ir.work_id, Exception.message(error)} | failed]}
  end

  defp load(ir, paths) do
    Loader.load(ir,
      source: @source_id,
      witness: @witness,
      segmenter: Segment.Derge,
      provenance: provenance(ir),
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

  defp provenance(%{work_id: "dkar-chag-" <> _}) do
    %{
      composition_origin: "tibetan",
      text_role: "catalogue",
      attribution_confidence: "certain"
    }
  end

  defp provenance(_ir) do
    %{
      composition_origin: "indic",
      text_role: "root",
      attribution_confidence: "probable"
    }
  end

  # A `--limit` run must not write a lockfile: the lock is a claim about what the whole
  # source IS, and one describing less than what was ingested is worse than none, because
  # it would verify.
  defp maybe_lock(root, volumes, nil), do: :ok = lock(root, volumes)

  defp maybe_lock(_root, _volumes, _limit) do
    Mix.shell().info("  (--limit run: sources.lock.json left alone)")
  end

  defp lock(root, volumes) do
    # `Lockfile.verify/1` resolves each entry against `raw/<source_id>/`, so the path must
    # be relative to that and to nothing else. Both sides are expanded because the
    # discovered paths are relative to the cwd while `raw_dir/0` is absolute, and
    # `Path.relative_to/2` silently returns the path unchanged when the prefix does not
    # match — which produces a lockfile that looks right and verifies nothing.
    source_root = Path.expand(Path.join(Lockfile.raw_dir(), @source_id))

    files =
      Enum.map(volumes, fn {_volume, path} ->
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

  defp report(stats, segments, failed, bake) do
    Mix.shell().info("""

    ingested the Derge Kangyur
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
