defmodule Mix.Tasks.Pramana.Bake do
  @shortdoc "Normalizes, segments, and loads acquired sources into the corpus"

  @moduledoc """
  Runs the bake pipeline over acquired sources.

      mix pramana.bake --source cbeta --work T0262 --volume 9

  Reads only from `raw/`, never the network, so a bake is reproducible from
  `sources.lock.json` alone. Requires `mix pramana.acquire` first.

  Dispatches through `Pramana.Pipeline.for_source/1` rather than naming a source's
  modules, so adding a source means implementing three behaviours and one registry
  entry — not editing this task.

  On completion it records the bake and prints its `bake_id`. An answer that cannot
  name the corpus it came from is not reproducible.
  """

  use Mix.Task

  alias Pramana.Acquire.Lockfile
  alias Pramana.Bake
  alias Pramana.Bake.WorkList
  alias Pramana.Corpus.Loader
  alias Pramana.Normalize.IR
  alias Pramana.Pipeline

  @switches [source: :string, work: :string, volume: :integer, canon: :string]

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _} = OptionParser.parse!(argv, strict: @switches)

    source = Keyword.get(opts, :source, "cbeta")

    config = %{
      "source" => source,
      "work" => Keyword.get(opts, :work, "T0262"),
      "volume" => Keyword.get(opts, :volume, 9),
      "canon" => Keyword.get(opts, :canon, "T")
    }

    pipeline = fetch_pipeline!(source)
    verify_raw!(source)

    # The volumes come from the LOCKFILE, not from `--volume`, whenever the lockfile
    # knows this work. A work that runs across two volumes baked from one of them is
    # half a text that verifies clean, and requiring the operator to know which works
    # those are is how the bulk path lost six of them. `--volume` still answers for a
    # work the lockfile has never heard of.
    config = with_work_list(source, config)
    volumes = config["volumes"]

    ir = normalize!(pipeline, source, config, volumes)
    number = String.replace_prefix(config["work"], config["canon"], "")

    provenance =
      provenance_for(pipeline, %{
        canon: config["canon"],
        volume: hd(volumes),
        number: number,
        # The work's own byline, for collections with no 部 table. See
        # `Pramana.Cbeta.Byline`. Passed on both bake paths so a single-work bake and a
        # bulk bake cannot assign different provenance to the same text.
        author: ir.author
      })

    {:ok, %{text: text, segments: count}} =
      Loader.load(ir,
        source: source,
        # RELATIVE TO THE REPOSITORY, never absolute. An absolute path records the
        # developer's home directory into the corpus — 648 of 648 CBETA texts named
        # `/Users/…/pramana/raw/cbeta/…` until 2026-09-03 — and a provenance record that
        # only resolves on one machine is not provenance. `mix pramana.derge.ingest`
        # already had a `relative/1` for exactly this and the lesson never reached here,
        # which is rule 41.
        source_file:
          pipeline
          |> raw_paths(source, config, volumes, number)
          |> Enum.map_join(" ", &Pramana.Paths.record_source(&1)),
        # THE CANON, not `pipeline.witness`. That registry field is a static "T", which was
        # indistinguishable from correct while the Taishō was the only CBETA collection
        # held. Baking a single X work through this path produced
        # `pramana:cbeta.T:X1508` — an X work addressed as if it sat in the Taishō, with a
        # URN that resolves and is wrong. `Bake.Worker` has always used the canon, so the
        # two bake paths silently disagreed; a second collection is what made that visible.
        witness: config["canon"],
        provenance: provenance
      )

    {:ok, bake} = Bake.record(config)

    report(ir, text, count, provenance, bake)
  end

  defp fetch_pipeline!(source) do
    case Pipeline.for_source(source) do
      {:ok, pipeline} ->
        pipeline

      {:error, :unsupported_source} ->
        Mix.raise("""
        No pipeline registered for source #{inspect(source)}.

        Known sources: #{Enum.join(Pipeline.sources(), ", ")}.
        To add one, implement the three Pramana.Pipeline behaviours and register it.
        """)
    end
  end

  # Never trust raw/ without checking it against the lockfile first.
  defp verify_raw!(source) do
    case Lockfile.verify(source) do
      {:ok, n} -> Mix.shell().info("verified #{n} raw file(s) against sources.lock.json")
      {:error, reason} -> Mix.raise("raw/ does not match the lockfile: #{inspect(reason)}")
    end
  end

  # Which printed volumes this work occupies, in printed order — and which collection
  # it belongs to. `--canon` defaults to "T", so `--work X0240` alone would have baked
  # an X work into the Taishō namespace: the same class of mistake as the static
  # witness this task's `Loader.load/2` call already warns about. The lockfile knows,
  # so it answers.
  defp with_work_list(source, config) do
    case WorkList.find(source, config["work"]) do
      %{volumes: volumes, canon: canon} = entry ->
        Map.merge(config, %{
          "volumes" => volumes,
          "canon" => canon,
          "volume" => hd(volumes),
          # The paths as acquired. Reconstructing them pads the volume to two digits and
          # the width belongs to the edition — A091, P154, L115 use three — so a rebuilt
          # path for canon A points at a file that does not exist. Both bake paths read
          # `WorkList`, and this is the second time they would otherwise have disagreed.
          "paths" => Map.get(entry, :paths)
        })

      nil ->
        Map.put(config, "volumes", [config["volume"]])
    end
  end

  defp normalize!(pipeline, source, config, volumes) do
    canon = config["canon"]
    work = config["work"]
    number = String.replace_prefix(work, canon, "")

    volumes
    |> Enum.zip(raw_paths(pipeline, source, config, volumes, number))
    |> Enum.map(fn {volume, path} ->
      {:ok, ir} =
        pipeline.normalizer.normalize(File.read!(path),
          work_id: work,
          canon: canon,
          volume: volume,
          number: number
        )

      ir
    end)
    |> IR.concat()
  end

  defp raw_paths(pipeline, source, config, volumes, number) do
    case config["paths"] do
      paths when is_list(paths) and paths != [] ->
        Enum.map(paths, &Path.join([Lockfile.raw_dir(), source, &1]))

      _ ->
        Enum.map(volumes, fn volume ->
          target = %{canon: config["canon"], volume: volume, number: number}
          Path.join([Lockfile.raw_dir(), source, pipeline.acquirer.raw_path(target)])
        end)
    end
  end

  defp provenance_for(pipeline, target) do
    case Map.get(pipeline, :provenance_rule) do
      nil -> %{}
      rule -> rule.provenance_for_target(target)
    end
  end

  defp report(ir, text, count, provenance, bake) do
    Mix.shell().info("""

    baked #{ir.work_id} — #{ir.title}
      author:     #{ir.author}
      juan:       #{ir.juan_count}
      segments:   #{count}
      outline:    #{length(ir.outline)} entries
      urn prefix: #{text.urn_prefix}
      origin:     #{provenance[:composition_origin] || "(catalogue data needed)"}
      role:       #{provenance[:text_role] || "(catalogue data needed)"}

      bake_id:    #{bake.id}
      pipeline:   v#{bake.pipeline_version}
      corpus:     #{bake.stats["texts"]} text(s), #{bake.stats["segments"]} segments, #{bake.stats["chars"]} chars
    """)
  end
end
