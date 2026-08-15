defmodule Pramana.Bake do
  @moduledoc """
  Bake identity: `bake_id = sha256(sources.lock + pipeline_version + config)`.

  See `docs/ARCHITECTURE.md`, "Stage 5 — Freeze". Two people with the same `bake_id`
  hold byte-identical corpora, which is what makes a citation reproducible years later
  and what "decoupled from the LLM" actually means in practice.

  ## pipeline_version

  Bump `@pipeline_version` whenever a change alters the **output** of normalization or
  segmentation — different text, different offsets, different anchors. Do *not* bump it
  for refactors, added tests, or new query paths, which leave the corpus identical.

  Getting this wrong in the lax direction is the dangerous one: two different corpora
  sharing an id means a citation that verified yesterday can fail today with nothing to
  point at. When in doubt, bump.

  ## Honest scope, as of Phase 1

  `segments` carries no `bake_id`, and the loader replaces rows in place. So there is
  exactly **one current bake** at a time; bakes do not coexist, and re-baking does not
  leave old citations resolvable. That is acceptable while a single corpus is being
  built and is cheap to change later (a nullable column in Postgres is not a rewrite) —
  but it must not be described as more than it is.
  """

  import Ecto.Query

  alias Pramana.Acquire.Lockfile
  alias Pramana.Corpus.Bake, as: BakeSchema
  alias Pramana.Corpus.Segment
  alias Pramana.Corpus.Text
  alias Pramana.Repo

  # Bump when normalization or segmentation OUTPUT changes. History:
  #   1 — initial: CBETA TEI -> IR -> Taisho line segments
  #   2 — segment note-only lines instead of dropping them. A line whose printed
  #       content is entirely an inline note now gets a URN (empty content, note in
  #       meta); only genuinely blank lines are skipped. Recovers 5,213 printed lines
  #       and 266,547 characters that had been unreachable.
  #   3 — split a <note> that spans <lb/> across the lines it covers, instead of
  #       attributing all of it to the line where it closes. Intermediate lines were
  #       left with no text and no note, so v2 still dropped them.
  @pipeline_version "3"

  @doc "The current pipeline version."
  @spec pipeline_version() :: String.t()
  def pipeline_version, do: @pipeline_version

  @doc """
  Computes the bake id for the current lockfile and configuration.

  Deterministic: the same lockfile, pipeline version and config always give the same
  id, and any change to upstream bytes changes it through the lockfile's per-source
  `files_sha256`.
  """
  @spec bake_id(map()) :: {:ok, String.t(), String.t()} | {:error, term()}
  def bake_id(config \\ %{}) do
    with {:ok, lock} <- Lockfile.read() do
      lock_digest = canonical_digest(lock)

      id =
        [lock_digest, @pipeline_version, canonical_digest(config)]
        |> Enum.join("\n")
        |> sha256()

      {:ok, id, lock_digest}
    end
  end

  @doc """
  Records the current bake, replacing the row if this exact bake is re-run.

  Re-running an identical bake is idempotent by construction: same inputs, same id,
  same row.
  """
  @spec record(map()) :: {:ok, BakeSchema.t()} | {:error, term()}
  def record(config \\ %{}) do
    with {:ok, id, lock_digest} <- bake_id(config) do
      bake = %BakeSchema{
        id: id,
        pipeline_version: @pipeline_version,
        sources_lock_sha256: lock_digest,
        config: config,
        built_at: DateTime.utc_now(),
        stats: stats()
      }

      {:ok,
       Repo.insert!(bake,
         on_conflict: {:replace, [:built_at, :stats, :config, :updated_at]},
         conflict_target: :id
       )}
    end
  end

  @doc "The most recently built bake, or nil if nothing has been baked."
  @spec current() :: BakeSchema.t() | nil
  def current do
    Repo.one(from b in BakeSchema, order_by: [desc: b.built_at], limit: 1)
  end

  @doc """
  The current bake id, for stamping onto API and MCP responses.

  An answer that cannot name the corpus it came from is not reproducible.
  """
  @spec current_id() :: String.t() | nil
  def current_id do
    case current() do
      nil -> nil
      bake -> bake.id
    end
  end

  @doc "Counts describing what is in the corpus right now."
  @spec stats() :: map()
  def stats do
    %{
      "texts" => Repo.aggregate(Text, :count),
      "segments" => Repo.aggregate(Segment, :count),
      "chars" =>
        Repo.one(from t in Text, select: coalesce(sum(fragment("length(?)", t.body)), 0)) || 0
    }
  end

  # Sorted-key JSON so that map ordering, which is not stable in Elixir, cannot change
  # a bake id. Two identical lockfiles must always digest the same.
  defp canonical_digest(term), do: term |> canonicalize() |> Jason.encode!() |> sha256()

  defp canonicalize(map) when is_map(map) and not is_struct(map) do
    map
    |> Enum.sort_by(fn {k, _v} -> to_string(k) end)
    |> Enum.map(fn {k, v} -> [to_string(k), canonicalize(v)] end)
  end

  defp canonicalize(list) when is_list(list), do: Enum.map(list, &canonicalize/1)
  defp canonicalize(other), do: other

  defp sha256(binary), do: :crypto.hash(:sha256, binary) |> Base.encode16(case: :lower)
end
