defmodule Pramana.Pipeline do
  @moduledoc """
  Contracts for the bake pipeline, and the registry that binds a source to them.

  ## Why contracts exist

  So that a better ingest method later is cheap, and a new source does not mean
  copy-paste. Three properties already make the *data* safe to reprocess:

  - `raw/` is immutable and pinned, so a better method is a **re-run against the same
    bytes**, never a re-fetch.
  - The IR is a seam: normalizers produce it, segmenters consume it, either replaceable.
  - URNs derive from each source's **own** anchors (`<lb n="0001c17"/>`), not from our
    chunking, so a better normalizer does not renumber citations.

  What was missing was a contract on the *code*. Without one, `mix pramana.bake` named
  `Normalize.CBETA` directly, and every additional source would have grown its own
  hardcoded path.

  ## Adding a source

  Implement the three behaviours, add one `@sources` entry, touch nothing else.
  """

  defmodule Acquirer do
    @moduledoc """
    Fetches upstream bytes into `raw/` and records them in `sources.lock.json`.

    A `target` is a source-specific map describing what to fetch, because sources
    genuinely differ: CBETA needs `canon`/`volume`/`number`, SuttaCentral has native
    segment ids, 84000 has Toh numbers and folio references. Forcing them into one
    shape would only push the difference somewhere less visible.
    """

    @type target :: map()
    @type pin :: map()

    @doc "Resolves the current upstream version to an immutable pin."
    @callback pin(keyword()) :: {:ok, pin()} | {:error, term()}

    @doc "Fetches the given targets at `pin` into `raw/`, updating the lockfile."
    @callback fetch(pin(), [target()], keyword()) :: {:ok, map()} | {:error, term()}

    @doc "Where a target's bytes live under `raw/<source>/`, relative to that directory."
    @callback raw_path(target()) :: String.t()
  end

  defmodule Normalizer do
    @moduledoc """
    Converts raw source bytes into `Pramana.Normalize.IR`.

    The IR is the seam. Everything downstream — segmentation, offsets, retrieval —
    depends only on this shape, so a normalizer can be rewritten without touching them.
    """

    alias Pramana.Normalize.IR

    @callback normalize(binary() | Enumerable.t(), keyword()) :: {:ok, IR.t()} | {:error, term()}
  end

  defmodule Segmenter do
    @moduledoc """
    Converts an IR into citable, URN-anchored segment rows.

    Per-witness rather than per-source, because the citation grammar belongs to the
    edition: CBETA and SAT both cite the Taishō by page/register/line, so they share a
    segmenter even though their normalizers differ.
    """

    alias Pramana.Normalize.IR

    @callback segments(IR.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  end

  @sources %{
    "cbeta" => %{
      acquirer: Pramana.Acquire.CBETA,
      normalizer: Pramana.Normalize.CBETA,
      segmenter: Pramana.Segment.Taisho,
      witness: "T",
      provenance_rule: Pramana.URN.Taisho
    }
  }

  @doc """
  The pipeline modules bound to a source id.
  """
  @spec for_source(String.t()) :: {:ok, map()} | {:error, :unsupported_source}
  def for_source(source_id) when is_binary(source_id) do
    case Map.fetch(@sources, source_id) do
      {:ok, config} -> {:ok, config}
      :error -> {:error, :unsupported_source}
    end
  end

  @doc "Source ids with a registered pipeline."
  @spec sources() :: [String.t()]
  def sources, do: Map.keys(@sources)
end
