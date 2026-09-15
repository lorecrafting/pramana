defmodule Pramana.Release do
  @moduledoc """
  What answered, as distinct from what was baked.

  ## The problem this exists for

  `Pramana.Bake` hashes `[lock_digest, pipeline_version, config]` — acquired bytes,
  normalisation, bake settings. That is the right identity for a **passage**: resolve a URN
  against the same `bake_id` and the text is byte-identical, which is what makes a citation
  checkable years later.

  **It is the wrong identity for a retrieval, and on 2026-09-03 that stopped being
  theoretical.** 27,751 renderings and 27,751 vectors were imported under an unchanged
  `bake_id`. Two people holding that id can answer the same query differently.

  It mattered because the id was asserted everywhere: `PramanaWeb.MCP.Reply` stamps it on
  every response of all nineteen tools, the MCP guide told a model to cite it for
  reproducibility, and `verify_report` keys replays on it — so a replay recorded before an
  import runs against the same id and a different index, and can fail while blaming the
  report rather than the corpus.

  ## Three things move independently, so three ids

    * `source_bake_id` — `Pramana.Bake`'s id, unchanged and still the passage's identity.
    * `translation_set_id` — the English layer: how many renderings, by whom.
    * `vector_set_id` — the index: how many vectors, of what kinds, from which model.
    * `release_id` — a digest of those three, and the only one that answers *what produced
      this answer*.

  **A citation is still reproducible from `source_bake_id` alone.** That claim never
  depended on the index, and nothing here weakens it. What `release_id` adds is the ability
  to say a *search* was or was not run against the same state.

  ## Stamped, not computed

  These ride on every tool response, so they must cost one indexed read. Counting 1,066,026
  vectors per request is not that, so a release is **recorded** when something changes it —
  exactly as a bake is.

  A recorded fact can go stale where a computed one cannot, which would reproduce the
  original defect in a new place. So `drift/0` compares the stamp against what is live and
  `mix pramana.doctor` reports it: **the failure mode is visible rather than silent**, which
  is the only difference that ever mattered here.
  """

  import Ecto.Query

  alias Pramana.Bake
  alias Pramana.Corpus.ChunkVector
  alias Pramana.Corpus.Release, as: Schema
  alias Pramana.Corpus.Translation
  alias Pramana.Repo

  @doc """
  Records the current retrieval state and returns it.

  Idempotent by digest: stamping twice with nothing changed returns the existing row rather
  than accumulating identical ones, because a release list where most entries are duplicates
  is a list nobody reads.
  """
  @spec stamp() :: {:ok, Schema.t()}
  def stamp do
    facts = facts()
    ids = ids_for(facts)

    case Repo.one(from r in Schema, where: r.release_id == ^ids.release_id) do
      nil -> Repo.insert(struct(Schema, Map.merge(facts, ids)), returning: true)
      existing -> {:ok, existing}
    end
  end

  @doc "The most recent stamp, or `nil` when nothing has been stamped yet."
  @spec current() :: Schema.t() | nil
  def current, do: Repo.one(from r in Schema, order_by: [desc: r.stamped_at], limit: 1)

  @doc """
  The id to put on an answer, or `nil` when no release has been stamped.

  `nil` rather than a computed fallback: an id invented at read time would differ between
  two processes reading the same corpus, which is worse than admitting there is none.
  """
  @spec current_id() :: String.t() | nil
  def current_id do
    case current() do
      nil -> nil
      release -> release.release_id
    end
  end

  @doc """
  Whether the stamp still describes the corpus, and in what respect it does not.

  Returns `:unstamped`, `:current`, or a map naming each fact that moved. **This is the
  check that keeps a recorded id from repeating the defect it was built to fix** — a stamp
  nobody refreshes is exactly a `bake_id` that does not move.
  """
  @spec drift() :: :unstamped | :current | map()
  def drift do
    case current() do
      nil ->
        :unstamped

      release ->
        live = facts()

        moved =
          for key <- [:translations_count, :vectors_count, :embedding_models, :translators],
              Map.get(live, key) != Map.get(release, key),
              into: %{},
              do: {key, %{stamped: Map.get(release, key), live: Map.get(live, key)}}

        if moved == %{}, do: :current, else: moved
    end
  end

  # The facts a release is a digest OF. Counts and identities rather than content hashes:
  # hashing 273,334 rendering texts per stamp would make stamping the expensive thing, and
  # what a caller needs to know is whether the state they are looking at is the one that
  # answered, not to re-derive it.
  defp facts do
    %{
      source_bake_id: Bake.current_id(),
      translations_count: Repo.aggregate(Translation, :count),
      vectors_count: Repo.aggregate(ChunkVector, :count),
      embedding_models:
        Repo.all(from v in ChunkVector, distinct: true, select: v.embedding_model)
        |> Enum.reject(&is_nil/1)
        |> Enum.sort(),
      translators:
        Repo.all(from t in Translation, distinct: true, select: t.translator_id)
        |> Enum.reject(&is_nil/1)
        |> Enum.sort(),
      stamped_at: DateTime.utc_now()
    }
  end

  @doc """
  The ids the CURRENT corpus would stamp, computed rather than read.

  For a caller that wants to know which half moved without writing a row — `mix
  pramana.doctor` and the drift check. Not for stamping a response: that reads
  `current_id/0`, which is one indexed lookup.
  """
  @spec ids() :: map()
  def ids do
    facts = facts()
    Map.put(ids_for(facts), :source_bake_id, facts.source_bake_id)
  end

  # ONE definition of what the ids are made of. It was briefly two — `digest/1` for
  # stamping and `ids/0` for reporting — which is how the two go out of step and a stamped
  # id stops matching the id a check computes. `Pramana.Retrieval.RenderingScope` learned
  # the same lesson one day earlier; rule 41.
  defp ids_for(facts) do
    translation_set = sha(["t", facts.translations_count, facts.translators])
    vector_set = sha(["v", facts.vectors_count, facts.embedding_models])

    %{
      translation_set_id: translation_set,
      vector_set_id: vector_set,
      release_id: sha([facts.source_bake_id, translation_set, vector_set])
    }
  end

  defp sha(parts) do
    parts
    |> Enum.map_join("|", &inspect/1)
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
end
