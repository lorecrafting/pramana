defmodule Mix.Tasks.Pramana.Local.Add do
  @shortdoc "Hashes, bakes and loads a local source directory into the corpus"

  @moduledoc """
  Adds `sources/local/<id>/` to the corpus.

      mix pramana.local.add sources/local/huang-nianzu-jie

  Validates first and refuses to write anything if validation fails, so this can be run
  without checking `mix pramana.local.validate` beforehand — though running validate
  first is cheaper when a manifest is still being written.

  ## What it writes

  1. Every file in `text/` is hashed into `sources.lock.json`, exactly as an upstream
     source is. Adding a text produces a **new `bake_id`**, because it is a different
     corpus.
  2. The text is normalized, segmented on its printed page anchors, and loaded.

  ## What it refuses to do

  There is no MCP tool for this and there never will be. If a model could add texts, the
  corpus would stop being reproducible from `sources.lock.json`, `bake_id` would stop
  determining contents, and prompt injection would become corpus poisoning — local text
  is already treated as untrusted input. **Tools read; the CLI writes.**
  (`CLAUDE.md` invariant #7, `docs/ADDING_TEXTS.md`.)

  ## Re-adding changed text

  Re-running after editing `text/` produces different hashes and a different `bake_id`,
  and the task says loudly which files changed. It does not quietly renumber anchors: a
  citation that resolved yesterday must not silently point somewhere else today. Treat
  `text/` as immutable once added, like `raw/`, and make corrections a layer.
  """

  use Mix.Task

  alias Pramana.Acquire.Lockfile
  alias Pramana.Bake
  alias Pramana.Corpus.Loader
  alias Pramana.Local.Manifest
  alias Pramana.Local.Normalizer
  alias Pramana.Normalize.IR
  alias Pramana.Segment.Page
  alias Pramana.Sources

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")

    dir =
      case argv do
        [dir | _] -> dir
        [] -> Mix.raise("usage: mix pramana.local.add <dir>")
      end

    case Manifest.load(dir) do
      {:ok, manifest} -> add(manifest, dir)
      {:error, errors} -> refuse(errors, dir)
    end
  end

  defp add(manifest, dir) do
    report_changes(manifest, dir)

    entry = lock_entry(manifest, dir)
    :ok = Lockfile.put_source(entry)

    {:ok, ir} = Normalizer.normalize(dir, manifest: manifest)

    {:ok, %{segments: count}} =
      Loader.load(ir,
        source: Sources.local_id(manifest.id),
        witness: ir.canon,
        source_definition: Sources.from_manifest(manifest),
        provenance: provenance(manifest),
        addressing: manifest.citation["addressing"],
        segmenter: Page
      )

    {:ok, bake} = Bake.record(%{"source" => Sources.local_id(manifest.id), "mode" => "local_add"})

    report(manifest, ir, count, bake, dir)
  end

  # Segmentation happens through the pipeline registry for upstream sources; a local
  # text names its segmenter directly because its citation grammar comes from its own
  # manifest rather than from a registered witness.
  defp provenance(manifest) do
    p = manifest.provenance

    %{
      composition_origin: p["composition_origin"],
      text_role: p["text_role"],
      attribution_confidence: p["attribution_confidence"],
      title: manifest.title,
      attributed_author: manifest.author
    }
  end

  defp lock_entry(manifest, dir) do
    text_dir = Path.join(dir, "text")

    files =
      Enum.map(manifest.files, fn rel ->
        bytes = File.read!(Path.join(text_dir, rel))
        %{path: rel, sha256: Lockfile.sha256(bytes), bytes: byte_size(bytes)}
      end)

    Lockfile.build_entry(Sources.from_manifest(manifest),
      files: files,
      # There is no upstream commit to pin, so the pin IS the content hash. That is the
      # same guarantee by a different route: the bake is reproducible for anyone holding
      # these exact bytes.
      pin: %{"type" => "content", "files_sha256" => Lockfile.manifest_hash(files)}
    )
  end

  # Re-adding edited text must be loud. Anchors are printed page numbers, so they do not
  # renumber — but the CONTENT at a page may now differ from what an earlier citation
  # quoted, and the guard would then reject a quotation that was correct when made.
  defp report_changes(manifest, dir) do
    case Lockfile.get_source(Sources.local_id(manifest.id)) do
      {:error, :not_locked} ->
        :ok

      {:ok, previous} ->
        old = Map.new(previous["files"] || [], &{&1["path"], &1["sha256"]})
        text_dir = Path.join(dir, "text")

        changed =
          Enum.filter(manifest.files, fn rel ->
            sha = Lockfile.sha256(File.read!(Path.join(text_dir, rel)))
            Map.has_key?(old, rel) and old[rel] != sha
          end)

        added = Enum.reject(manifest.files, &Map.has_key?(old, &1))
        removed = Map.keys(old) -- manifest.files

        announce_changes(changed, added, removed)
    end
  end

  defp announce_changes([], [], []), do: :ok

  defp announce_changes(changed, added, removed) do
    Mix.shell().info([
      IO.ANSI.yellow(),
      """

      This source is already locked and its text has CHANGED:
        #{length(changed)} file(s) modified, #{length(added)} added, #{length(removed)} removed

      Page anchors are printed page numbers, so they do not renumber. But a quotation
      taken from a modified page may no longer match, and the citation guard will
      reject it — correctly, and confusingly, unless you know this happened.
      """,
      IO.ANSI.reset()
    ])

    for f <- Enum.take(changed, 10), do: Mix.shell().info("    modified: #{f}")
  end

  defp report(manifest, ir, count, bake, dir) do
    blank = Enum.count(ir.lines, &(&1.text == ""))
    heads = Normalizer.stripped_running_heads(dir, manifest)

    Mix.shell().info("""

    added #{manifest.id} — #{manifest.title}
      files:      #{length(manifest.files)}
      segments:   #{count}
      characters: #{String.length(IR.body(ir))}
      urn prefix: pramana:#{Sources.local_id(manifest.id)}.#{ir.canon}:#{ir.work_id}
      addressing: #{manifest.citation["addressing"]}
      licence:    #{manifest.license["class"]} (public surfaces: #{if Manifest.public?(manifest), do: "allowed", else: "EXCLUDED"})

      running heads stripped: #{heads}
      pages with no content:  #{blank}#{blank_note(blank)}

      bake_id:    #{bake.id}
      corpus:     #{bake.stats["texts"]} text(s), #{bake.stats["segments"]} segments
    """)
  end

  defp blank_note(0), do: ""

  defp blank_note(_n),
    do:
      "  ← check these against the book: a page that yielded nothing\n" <>
        "                              may be genuinely blank, or may be an extraction failure"

  # Always raises; declared so dialyzer does not report the caller as no_return.
  @spec refuse([String.t()], Path.t()) :: no_return()
  defp refuse(errors, dir) do
    for e <- errors, do: Mix.shell().error("  • #{e}")
    Mix.raise("#{length(errors)} problem(s) in #{dir}. NOTHING was written.")
  end
end
