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

  **The unit is the work, not the file.** Those coincide across the whole Taishō, which
  is why the difference went unnoticed for two collections: CBETA gives a Taishō work
  split across volumes a distinct id (`T0220a`, `T0220b`), so 2,471 works arrived as
  2,471 files. The X collection reuses one number across both of its volume files, and
  because the loader *replaces* a work's segments, a job per file meant the second
  volume to finish silently erased the first — six works, each keeping about half of
  itself, with which half decided by job scheduling. See `IR.concat/1`.
  """

  use Oban.Worker, queue: :bake, max_attempts: 3

  alias Pramana.Acquire.Lockfile
  alias Pramana.Corpus.Loader
  alias Pramana.Normalize.IR
  alias Pramana.Pipeline

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    %{
      "source" => source,
      "canon" => canon,
      "number" => number,
      "work_id" => work_id
    } = args

    volumes = volumes(args)

    with {:ok, pipeline} <- Pipeline.for_source(source),
         {:ok, parts} <- normalize_volumes(source, pipeline, canon, volumes, number, work_id) do
      ir = IR.concat(parts)

      provenance =
        provenance_for(pipeline, %{
          canon: canon,
          # The FIRST volume, which is where the work begins. Provenance rules that key
          # on a volume range (the Taishō 部 table) must be asked about the volume the
          # work starts in; asking about the last one would put a work that opens in an
          # Indic division and runs on into the next one on the wrong side of the line.
          volume: hd(volumes),
          number: number,
          # The work's own byline. Only a non-Taishō collection uses it — X has no 部
          # table — but it is passed always, because a rule that receives different
          # inputs depending on the canon is a rule nobody can reason about.
          author: ir.author
        })

      {:ok, %{segments: count}} =
        Loader.load(ir,
          source: source,
          witness: canon,
          provenance: provenance,
          source_file: Enum.map_join(volumes, " ", &raw_path(source, pipeline, canon, &1, number))
        )

      {:ok, %{work_id: work_id, segments: count}}
    else
      {:error, reason} ->
        # Return the reason so Oban records it against the job; the run continues.
        Logger.error("bake failed for #{work_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # `volumes` is the general form: a work is one or more printed volumes, in printed
  # order. `volume` is still accepted because jobs enqueued by an earlier run may be
  # sitting in the queue, and a deploy that made those unrunnable would strand them.
  defp volumes(%{"volumes" => volumes}) when is_list(volumes) and volumes != [], do: volumes
  defp volumes(%{"volume" => volume}), do: [volume]

  # Each volume is normalized on its own and the parts are assembled afterwards. Doing
  # it the other way — concatenating the XML — would produce a document with two TEI
  # headers and two licence notices, and the parser would be reading something no
  # edition ever published.
  defp normalize_volumes(source, pipeline, canon, volumes, number, work_id) do
    Enum.reduce_while(volumes, {:ok, []}, fn volume, {:ok, acc} ->
      with {:ok, xml} <- read_raw(source, pipeline, canon, volume, number),
           {:ok, ir} <- normalize(pipeline, xml, work_id, canon, volume, number) do
        {:cont, {:ok, [ir | acc]}}
      else
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, parts} -> {:ok, Enum.reverse(parts)}
      error -> error
    end
  end

  defp read_raw(source, pipeline, canon, volume, number) do
    path = raw_path(source, pipeline, canon, volume, number)

    case File.read(path) do
      {:ok, xml} -> {:ok, xml}
      {:error, reason} -> {:error, {:raw_unreadable, path, reason}}
    end
  end

  defp raw_path(source, pipeline, canon, volume, number) do
    Path.join([
      Lockfile.raw_dir(),
      source,
      pipeline.acquirer.raw_path(%{canon: canon, volume: volume, number: number})
    ])
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

  `entry.volumes` is a list in printed order, so the unit of a job is the **work** and
  not the file. Those are the same thing for 5,015 of the 5,021 CBETA works and
  different for six.
  """
  @spec args(String.t(), map()) :: map()
  def args(source, entry) do
    %{
      "source" => source,
      "canon" => entry.canon,
      "volumes" => entry.volumes,
      "number" => entry.number,
      "work_id" => entry.work_id
    }
  end
end
