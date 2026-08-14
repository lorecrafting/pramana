defmodule Pramana.Bake.Worker do
  @moduledoc """
  Bakes one work: normalize → segment → load.

  One job per work, which is what buys the three properties the bake needs at 5,000
  files:

  - **Fault isolation.** A malformed TEI file fails its own job and the run continues.
    In a single sequential script this is a `try/rescue` you have to remember; here it
    is the default.
  - **Resumability.** A bake killed at file 4,000 resumes at 4,000. Completed jobs stay
    completed.
  - **Bounded concurrency** across cores without a GIL.

  Idempotent: `Loader.load/2` replaces a work's segments rather than appending, so a
  retried or re-run job converges on the same state.
  """

  use Oban.Worker, queue: :bake, max_attempts: 3

  alias Pramana.Acquire.Lockfile
  alias Pramana.Corpus.Loader
  alias Pramana.Pipeline

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    %{
      "source" => source,
      "canon" => canon,
      "volume" => volume,
      "number" => number,
      "work_id" => work_id
    } = args

    with {:ok, pipeline} <- Pipeline.for_source(source),
         {:ok, xml} <- read_raw(source, pipeline, canon, volume, number),
         {:ok, ir} <- normalize(pipeline, xml, work_id, canon, volume, number) do
      provenance =
        provenance_for(pipeline, %{canon: canon, volume: volume, number: number})

      {:ok, %{segments: count}} =
        Loader.load(ir, source: source, witness: canon, provenance: provenance)

      {:ok, %{work_id: work_id, segments: count}}
    else
      {:error, reason} ->
        # Return the reason so Oban records it against the job; the run continues.
        Logger.error("bake failed for #{work_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp read_raw(source, pipeline, canon, volume, number) do
    path =
      Path.join([
        Lockfile.raw_dir(),
        source,
        pipeline.acquirer.raw_path(%{canon: canon, volume: volume, number: number})
      ])

    case File.read(path) do
      {:ok, xml} -> {:ok, xml}
      {:error, reason} -> {:error, {:raw_unreadable, path, reason}}
    end
  end

  defp normalize(pipeline, xml, work_id, canon, volume, number) do
    pipeline.normalizer.normalize(xml,
      work_id: work_id,
      canon: canon,
      volume: volume,
      number: number
    )
  rescue
    error -> {:error, {:normalize_crashed, Exception.message(error)}}
  end

  # provenance_rule is OPTIONAL: it encodes a witness-specific rule that Pali and
  # Tibetan sources will not have. Assigning provenance HERE, during the bake, rather
  # than in a later pass is what makes a re-bake converge instead of undoing it.
  defp provenance_for(pipeline, target) do
    case Map.get(pipeline, :provenance_rule) do
      nil -> %{}
      rule -> rule.provenance_for_target(target)
    end
  end

  @doc """
  Builds job args for a catalog entry.
  """
  @spec args(String.t(), map()) :: map()
  def args(source, entry) do
    %{
      "source" => source,
      "canon" => entry.canon,
      "volume" => entry.volume,
      "number" => entry.number,
      "work_id" => entry.work_id
    }
  end
end
