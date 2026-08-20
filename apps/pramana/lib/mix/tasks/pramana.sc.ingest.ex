defmodule Mix.Tasks.Pramana.Sc.Ingest do
  @shortdoc "Ingests SuttaCentral bilara-data Pāli root text"

  @moduledoc """
  Bakes the Mahāsaṅgīti Pāli Tipiṭaka from a sparse checkout of `bilara-data`.

      mix pramana.sc.ingest                     # everything under root/pli/ms
      mix pramana.sc.ingest --limit 50          # a slice, for iterating
      mix pramana.sc.ingest --dry-run

  Expects the checkout at `raw/sc/bilara-data`, made with:

      git clone --depth 1 --branch published --filter=blob:none --sparse \\
        https://github.com/suttacentral/bilara-data.git
      cd bilara-data && git sparse-checkout set root/pli/ms

  The full repository is 910 MB; `root/pli/ms` is 57 MB across 7,288 files, so a sparse
  checkout is the difference between a minute and a coffee break.

  ## Licence, checked rather than assumed

  `bilara-data`'s LICENSE.md says everything is CC0, and `_publication.json` disagrees in
  two places: the Pāli root text is **Public Domain Mark** and the Patna Dhammapada is
  **CC BY-SA 3.0**, which carries attribution and share-alike obligations CC0 does not.
  Licence is therefore recorded per publication, never per repository.

  This ingest covers the root text only — Public Domain, and the **first redistributable
  content in this corpus**. Until it landed, `redistributable_only: true` returned
  nothing at all.
  """

  use Mix.Task

  alias Pramana.Acquire.Lockfile
  alias Pramana.Bake
  alias Pramana.Corpus.Loader
  alias Pramana.Normalize.Bilara
  alias Pramana.Segment.SegmentId

  @switches [limit: :integer, dry_run: :boolean, root: :string]

  @default_root "raw/sc/bilara-data"
  @subpath "root/pli/ms"
  @source_id "sc"
  @witness "ms"

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _, _} = OptionParser.parse(argv, switches: @switches)

    root = Keyword.get(opts, :root, @default_root)
    files = files(root, opts[:limit])

    if files == [],
      do: Mix.raise("no files under #{Path.join(root, @subpath)} — see the moduledoc")

    Mix.shell().info("#{if opts[:dry_run], do: "DRY RUN — ", else: ""}#{length(files)} file(s)")

    {ok, failed, segments} = Enum.reduce(files, {0, [], 0}, &ingest(&1, &2, opts[:dry_run]))

    unless opts[:dry_run] do
      maybe_lock(root, files, opts[:limit])
      {:ok, bake} = Bake.record(%{"source" => @source_id, "mode" => "sc_ingest"})
      report(ok, failed, segments, bake)
    end
  end

  # The lockfile is a claim about what the whole source IS, so a `--limit` run must not
  # write one: a `--limit 1` rewrote the `sc` entry to a single file, leaving the lock
  # asserting a one-file corpus while 8,442 works sat in the database. A pin that
  # describes less than what was ingested is worse than no pin — it would verify.
  defp maybe_lock(root, files, nil), do: :ok = lock(root, files)

  defp maybe_lock(_root, _files, _limit) do
    Mix.shell().info("  (--limit run: sources.lock.json left alone)")
  end

  defp files(root, limit) do
    root
    |> Path.join(@subpath)
    |> Path.join("**/*.json")
    |> Path.wildcard()
    |> Enum.sort()
    |> then(fn all -> if limit, do: Enum.take(all, limit), else: all end)
  end

  # One file can hold several works — `an1.1-10_root-pli-ms.json` is ten suttas — so the
  # unit of ingest is the WORK, taken from the segment ids, not the filename.
  defp ingest(file, acc, dry_run?) do
    case Bilara.normalize_file(File.read!(file), witness: @witness) do
      {:ok, irs} ->
        relative = Path.relative_to(file, File.cwd!())
        Enum.reduce(irs, acc, &tally(&1, &2, dry_run?, relative))

      {:error, reason} ->
        {ok, failed, segments} = acc
        {ok, [{Path.basename(file), reason} | failed], segments}
    end
  end

  defp tally(ir, {ok, failed, segments}, dry_run?, file) do
    case store(ir, dry_run?, file) do
      {:ok, count} -> {ok + 1, failed, segments + count}
      {:error, reason} -> {ok, [{ir.work_id, reason} | failed], segments}
    end
  end

  defp store(_ir, true, _file), do: {:ok, 0}

  defp store(ir, _, file) do
    # One malformed work must fail its own row, not the run. Same isolation as
    # `pramana.bake_all`, which learned this over 2,471 works. `Loader.load/2` signals
    # failure by raising — including the check-constraint violation that caught the
    # unregistered `public-domain` licence class — so the rescue is the whole mechanism.
    {:ok, %{segments: count}} = load(ir, file)
    {:ok, count}
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp load(ir, file) do
    Loader.load(ir,
      source: @source_id,
      witness: @witness,
      segmenter: SegmentId,
      # The Pāli canon is Indic-composed root scripture. Unlike the Taishō there is no
      # division table to consult — this is the whole collection, and it is what it is.
      provenance: %{
        composition_origin: "indic",
        text_role: "root",
        attribution_confidence: "certain",
        title: ir.title
      },
      # A published critical edition with its own citation scheme, which a reader can
      # check at suttacentral.net. Not `edition_page`: there is no printed page here,
      # the segment id IS the address.
      addressing: "canonical",
      source_file: file
    )
  end

  defp lock(root, files) do
    # Relative to `raw/<source_id>/`, which is what `Lockfile.verify/1` resolves against —
    # NOT to the checkout root. Recorded against `raw/sc/bilara-data` instead, every one of
    # the 7,288 paths was missing its `bilara-data/` prefix and the entire Pāli provenance
    # record resolved to nothing, while `verify` and `integrity` stayed green because both
    # work from paths recorded on the texts rather than from this file. Both sides are
    # expanded because `Path.relative_to/2` returns the path unchanged when the prefix does
    # not match, which is a lockfile that looks right and checks nothing.
    source_root = Path.expand(Path.join(Lockfile.raw_dir(), @source_id))

    entries =
      Enum.map(files, fn file ->
        bytes = File.read!(file)

        %{
          path: Path.relative_to(Path.expand(file), source_root),
          sha256: Lockfile.sha256(bytes),
          bytes: byte_size(bytes)
        }
      end)

    entry =
      Lockfile.build_entry(
        %{
          id: @source_id,
          name: "SuttaCentral bilara-data — Mahāsaṅgīti Pāli Tipiṭaka (root)",
          upstream_url: "https://github.com/suttacentral/bilara-data",
          repo: "suttacentral/bilara-data",
          license: %{
            # Per `_publication.json` scpub64, NOT the repository-level CC0 claim. The
            # root text is Public Domain Mark: free of known restrictions, redistributable.
            spdx: "CC-PDM-1.0",
            class: "public-domain",
            commercial_use: true,
            redistributable: true,
            notice:
              "Mahāsaṅgīti Tipiṭaka Buddhavasse 2500. Public Domain Mark per " <>
                "bilara-data _publication.json (scpub64). SuttaCentral asks that use " <>
                "accord with the values of the Buddhist tradition."
          }
        },
        files: entries,
        pin: %{"type" => "git", "commit" => commit(root), "sparse" => @subpath}
      )

    Lockfile.put_source(entry)
  end

  defp commit(root) do
    case System.cmd("git", ["-C", root, "rev-parse", "HEAD"], stderr_to_stdout: true) do
      {sha, 0} -> String.trim(sha)
      _ -> nil
    end
  end

  defp report(ok, failed, segments, bake) do
    Mix.shell().info("""

    ingested SuttaCentral Pāli
      works:      #{ok}
      failed:     #{length(failed)}
      segments:   #{segments}
      urn shape:  pramana:sc.ms:mn1@1.1   (SuttaCentral's own segment ids, verbatim)
      licence:    public-domain, REDISTRIBUTABLE

      bake_id:    #{bake.id}
      corpus:     #{bake.stats["texts"]} text(s), #{bake.stats["segments"]} segments
    """)

    for {work, reason} <- Enum.take(failed, 10) do
      Mix.shell().error("  FAILED #{work}: #{inspect(reason)}")
    end
  end
end
