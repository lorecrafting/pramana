defmodule Pramana.Release do
  @moduledoc """
  What answered, as distinct from what was baked.

  ## The problem this exists for

  `Pramana.Bake` hashes `[lock_digest, pipeline_version, config]` — acquired bytes,
  normalisation, bake settings. That identifies source inputs, not a frozen database.
  Reproducing passage bytes requires those inputs and the matching pipeline; loaded
  rows can change and historical snapshots are not retained by these identities.

  **It is the wrong identity for a retrieval, and on 2026-09-03 that stopped being
  theoretical.** 27,751 renderings and 27,751 vectors were imported under an unchanged
  `bake_id`. Two people holding that id can answer the same query differently.

  It mattered because the id was asserted everywhere: `PramanaWeb.MCP.Reply` stamps it on
  every response of all nineteen tools, the MCP guide told a model to cite it for
  reproducibility, and `verify_report` keys replays on it — so a replay recorded before an
  import runs against the same id and a different index, and can fail while blaming the
  report rather than the corpus.

  ## Three components and one combined stamp

    * `source_bake_id` — `Pramana.Bake`'s source-input identity.
    * `translation_set_id` — the English layer: how many renderings, by whom.
    * `vector_set_id` — the index: how many vectors, of what kinds, from which model.
    * `release_id` — a digest of those three recorded components.

  The translation and vector identities summarize counts and translator/model names,
  not content. Same-count edits and changes to retrieval code or defaults may be invisible.
  Matching `release_id` values do not establish identical answers or historical replay.

  ## Stamped, not computed

  These ride on every tool response, so they must cost one indexed read. Counting 1,066,026
  vectors per request is not that, so a release is **recorded** when something changes it —
  exactly as a bake is.

  A recorded fact can go stale where a computed one cannot. `drift/0` compares the
  recorded source identity, counts and translator/model names with their live values;
  `mix pramana.doctor` reports differences. This detects drift in those facts, not all
  possible content changes. Reading a stamp or checking drift never refreshes it.
  """

  import Ecto.Query

  alias Pramana.Bake
  alias Pramana.Corpus.ChunkVector
  alias Pramana.Corpus.Release, as: Schema
  alias Pramana.Corpus.Translation
  alias Pramana.Release.Selection
  alias Pramana.Repo

  @doc """
  Records the current retrieval state and returns it.

  Idempotent by digest: immutable release rows are reused. The selected release is
  recorded separately and atomically, so returning from state A to B to A selects
  A again without rewriting its original stamp timestamp. This is selection, not
  deployment or a content-complete fingerprint.
  """
  # Database-local advisory namespace "PRAM", key 1 = release-stamp writer.
  # Held to the outer transaction boundary; old writers must be drained at cutover.
  @stamp_lock [0x5052414D, 1]

  @spec stamp() :: {:ok, Schema.t()}
  def stamp do
    Repo.transaction(fn ->
      Repo.query!("SELECT pg_advisory_xact_lock($1, $2)", @stamp_lock)
      facts = facts()
      ids = ids_for(facts)

      # ON CONFLICT makes concurrent creation of one digest safe; read it back
      # because an ignored insert does not return the existing row's identity.
      Repo.insert!(struct(Schema, Map.merge(facts, ids)),
        on_conflict: :nothing,
        conflict_target: [:release_id]
      )

      release = Repo.get_by!(Schema, release_id: ids.release_id)

      Repo.insert!(%Selection{id: 1, release_id: release.id, selected_at: DateTime.utc_now()},
        on_conflict: {:replace, [:release_id, :selected_at]},
        conflict_target: [:id]
      )

      release
    end)
  end

  @doc "The explicitly selected release, or nil before the first stamp. Reading never selects or refreshes it."
  @spec current() :: Schema.t() | nil
  def current do
    Repo.one(
      from(selection in Selection,
        join: release in Schema,
        on: release.id == selection.release_id,
        where: selection.id == 1,
        select: release
      )
    )
  end

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
  Whether the recorded source identity and derived facts still match their live values.

  Returns `:unstamped`, `:current`, or a map naming each fact that moved, including
  `:source_bake_id`. Only the observation timestamp is excluded from comparison.
  `:current` does not establish byte-complete content identity or identical retrieval.
  This check does not write or refresh a release stamp.
  """
  @spec drift() :: :unstamped | :current | map()
  def drift do
    case current() do
      nil ->
        :unstamped

      release ->
        live = Map.delete(facts(), :stamped_at)

        moved =
          for {key, value} <- live,
              value != Map.fetch!(release, key),
              into: %{},
              do: {key, %{stamped: Map.fetch!(release, key), live: value}}

        if moved == %{}, do: :current, else: moved
    end
  end

  # Counts and identities rather than content hashes. This keeps stamping bounded by
  # aggregate queries, but same-count content changes can retain the same digest.
  defp facts do
    %{
      source_bake_id: Bake.current_id(),
      translations_count: Repo.aggregate(Translation, :count),
      vectors_count: Repo.aggregate(ChunkVector, :count),
      embedding_models:
        Repo.all(from(v in ChunkVector, distinct: true, select: v.embedding_model))
        |> Enum.reject(&is_nil/1)
        |> Enum.sort(),
      translators:
        Repo.all(from(t in Translation, distinct: true, select: t.translator_id))
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
