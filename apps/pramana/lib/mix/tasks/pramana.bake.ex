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
  alias Pramana.Corpus.Loader
  alias Pramana.Pipeline

  @switches [source: :string, work: :string, volume: :integer, canon: :string]

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _, _} = OptionParser.parse(argv, switches: @switches)

    source = Keyword.get(opts, :source, "cbeta")

    config = %{
      "source" => source,
      "work" => Keyword.get(opts, :work, "T0262"),
      "volume" => Keyword.get(opts, :volume, 9),
      "canon" => Keyword.get(opts, :canon, "T")
    }

    pipeline = fetch_pipeline!(source)
    verify_raw!(source)

    ir = normalize!(pipeline, source, config)
    number = String.replace_prefix(config["work"], config["canon"], "")

    provenance =
      provenance_for(pipeline, %{
        canon: config["canon"],
        volume: config["volume"],
        number: number,
        # The work's own byline, for collections with no 部 table. See
        # `Pramana.Cbeta.Byline`. Passed on both bake paths so a single-work bake and a
        # bulk bake cannot assign different provenance to the same text.
        author: ir.author
      })

    {:ok, %{text: text, segments: count}} =
      Loader.load(ir,
        source: source,
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

  defp normalize!(pipeline, source, config) do
    canon = config["canon"]
    work = config["work"]
    number = String.replace_prefix(work, canon, "")

    target = %{canon: canon, volume: config["volume"], number: number}
    path = Path.join([Lockfile.raw_dir(), source, pipeline.acquirer.raw_path(target)])

    {:ok, ir} =
      pipeline.normalizer.normalize(File.read!(path),
        work_id: work,
        canon: canon,
        volume: config["volume"],
        number: number
      )

    ir
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
