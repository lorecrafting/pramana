defmodule Pramana.Release do
  @moduledoc """
  What answered, as distinct from what was baked.

  `Pramana.Bake` identifies acquired source inputs. A release identifies the selected
  retrieval state layered over those sources.

  ## Content identity, not row counts

  Version-2 component ids are content digests:

    * `source_bake_id` — `Pramana.Bake`'s source-input identity.
    * `translation_set_id` — a deterministic digest of every rendering's stable content,
      selection fields and provenance.
    * `vector_set_id` — a deterministic digest of every logical vector row, including a
      SHA-256 of the actual stored pgvector binary value.
    * `release_id` — a digest of those three components.

  Component ids carry a `v2:` prefix. Older unprefixed release rows remain valid history,
  but `drift/0` reports them as legacy until an operator explicitly stamps the current
  state. No migration rewrites historical identities.

  The content scan happens only when a release is explicitly stamped or `ids/0` is called.
  Tool responses keep reading the selected `release_id` with one indexed lookup.

  ## Drift is cheap first, exact only when needed

  `drift/0` first compares the recorded source id, counts and translator/model names. For
  a v2 release whose aggregates are unchanged, it checks whether rows were touched after
  the current selection time. Only then does it recompute that layer's content digest.
  This catches same-count translation edits and vector recomputations without hashing the
  million-row index on every `mix pramana.doctor` run.

  Normal write paths must therefore advance `updated_at`; vector embedding writers do so.
  Direct SQL that mutates answer-producing rows while deliberately preserving timestamps
  can evade the cheap trigger and is outside this contract.

  ## What this still does not promise

  A matching release id identifies the recorded source, translation and vector rows. It
  does not freeze historical rows, retrieval code, defaults, database planner behaviour or
  a transactional snapshot of a tool execution. Re-running a call under the same id is
  better grounded, but is not an immutable replay guarantee.
  """

  import Ecto.Query

  alias Pramana.Bake
  alias Pramana.Corpus.Chunk
  alias Pramana.Corpus.ChunkVector
  alias Pramana.Corpus.Release, as: Schema
  alias Pramana.Corpus.Translation
  alias Pramana.Release.Selection
  alias Pramana.Repo

  @stamp_lock [0x5052414D, 1]
  @set_version "v2"

  @doc """
  Records and selects the current retrieval state.

  Stamping is intentionally explicit. It streams compact row fingerprints instead of
  materialising translation text or vector values in the BEAM, and may scan the whole
  vector table. Run data writers to completion before stamping; the advisory lock below
  serializes release stampers, not arbitrary corpus mutations.
  """
  @spec stamp() :: {:ok, Schema.t()}
  def stamp do
    Repo.transaction(
      fn ->
        Repo.query!("SELECT pg_advisory_xact_lock($1, $2)", @stamp_lock)
        facts = facts()
        ids = ids_for(facts)
        stamped = Map.put(facts, :stamped_at, DateTime.utc_now())

        Repo.insert!(struct(Schema, Map.merge(stamped, ids)),
          on_conflict: :nothing,
          conflict_target: [:release_id]
        )

        release = Repo.get_by!(Schema, release_id: ids.release_id)

        Repo.insert!(
          %Selection{id: 1, release_id: release.id, selected_at: DateTime.utc_now()},
          on_conflict: {:replace, [:release_id, :selected_at]},
          conflict_target: [:id]
        )

        release
      end,
      timeout: :infinity
    )
  end

  @doc "The explicitly selected release, or nil before the first stamp."
  @spec current() :: Schema.t() | nil
  def current do
    case selected_release() do
      nil -> nil
      {release, _selected_at} -> release
    end
  end

  @doc "The selected release id to put on an answer, or nil before the first stamp."
  @spec current_id() :: String.t() | nil
  def current_id do
    case current() do
      nil -> nil
      release -> release.release_id
    end
  end

  @doc """
  Reports whether the selected release still describes the live retrieval state.

  Aggregate changes are reported directly. Same-count content changes are rehashed only
  when a layer has been touched since `release_selection.selected_at`. Legacy coarse
  component ids are reported as an identity-version drift and are never silently upgraded.
  """
  @spec drift() :: :unstamped | :current | map()
  def drift do
    case selected_release() do
      nil ->
        :unstamped

      {release, selected_at} ->
        moved =
          release
          |> aggregate_drift()
          |> maybe_identity_version_drift(release)
          |> maybe_translation_content_drift(release, selected_at)
          |> maybe_vector_content_drift(release, selected_at)

        if moved == %{}, do: :current, else: moved
    end
  end

  @doc """
  Computes the v2 ids the current corpus would stamp without selecting them.

  This is a full content scan, including hashing stored vector bytes. It is for audits and
  explicit release work, not request-time metadata.
  """
  @spec ids() :: map()
  def ids do
    with_transaction(fn ->
      facts = facts()

      facts
      |> ids_for()
      |> Map.put(:source_bake_id, facts.source_bake_id)
    end)
  end

  defp selected_release do
    Repo.one(
      from(selection in Selection,
        join: release in Schema,
        on: release.id == selection.release_id,
        where: selection.id == 1,
        select: {release, selection.selected_at}
      )
    )
  end

  defp aggregate_drift(release) do
    for {key, live} <- facts(),
        live != Map.fetch!(release, key),
        into: %{},
        do: {key, %{stamped: Map.fetch!(release, key), live: live}}
  end

  defp maybe_identity_version_drift(moved, release) do
    if v2_release?(release) do
      moved
    else
      Map.put(moved, :identity_version, %{stamped: "v1/coarse", live: @set_version})
    end
  end

  defp maybe_translation_content_drift(moved, release, selected_at) do
    stable_aggregates? =
      not Map.has_key?(moved, :translations_count) and not Map.has_key?(moved, :translators)

    maybe_content_drift(
      moved,
      stable_aggregates? and v2_release?(release),
      Translation,
      selected_at,
      :translation_set_id,
      release.translation_set_id,
      &translation_set_id/0
    )
  end

  defp maybe_vector_content_drift(moved, release, selected_at) do
    stable_aggregates? =
      not Map.has_key?(moved, :vectors_count) and not Map.has_key?(moved, :embedding_models)

    maybe_content_drift(
      moved,
      stable_aggregates? and v2_release?(release),
      ChunkVector,
      selected_at,
      :vector_set_id,
      release.vector_set_id,
      &vector_set_id/0
    )
  end

  defp maybe_content_drift(moved, false, _schema, _selected_at, _key, _stamped, _compute),
    do: moved

  defp maybe_content_drift(moved, true, schema, selected_at, key, stamped, compute) do
    if changed_after?(schema, selected_at) do
      live = with_transaction(compute)

      if live == stamped do
        moved
      else
        Map.put(moved, key, %{stamped: stamped, live: live})
      end
    else
      moved
    end
  end

  defp changed_after?(schema, selected_at) do
    case Repo.aggregate(schema, :max, :updated_at) do
      nil -> false
      changed_at -> DateTime.compare(changed_at, selected_at) == :gt
    end
  end

  defp v2_release?(release) do
    String.starts_with?(release.translation_set_id, @set_version <> ":") and
      String.starts_with?(release.vector_set_id, @set_version <> ":")
  end

  # Cheap facts retained on the release row so drift can explain ordinary changes without
  # recomputing the content sets.
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
        |> Enum.sort()
    }
  end

  defp ids_for(facts) do
    translation_set = translation_set_id()
    vector_set = vector_set_id()

    %{
      translation_set_id: translation_set,
      vector_set_id: vector_set,
      release_id: sha(["release-v2", facts.source_bake_id, translation_set, vector_set])
    }
  end

  # Stable row fields only. Surrogate ids and timestamps are deliberately excluded: two
  # databases containing the same logical renderings should mint the same set id.
  defp translation_set_id do
    query =
      from(t in Translation,
        order_by: [asc: t.anchor_urn, asc: t.lang, asc: t.translator_id],
        select:
          fragment(
            """
            encode(
              sha256(
                convert_to(
                  jsonb_build_array(
                    ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
                  )::text,
                  'UTF8'
                )
              ),
              'hex'
            )
            """,
            t.anchor_urn,
            t.work_id,
            t.lang,
            t.translator_id,
            t.translator_name,
            t.tier,
            t.method,
            t.text_sha256,
            t.model_id,
            t.prompt_version,
            t.glossary_id,
            t.bake_id,
            t.review_state,
            t.glossary_compliance,
            t.consensus_score,
            t.confidence,
            t.license_spdx,
            t.license_class,
            t.redistributable,
            t.attribution,
            t.source_file,
            t.meta
          )
      )

    digest_query("translation-set", query)
  end

  # `vector_send/1` is pgvector's immutable binary serializer. Hashing it covers the
  # actual stored float32 vector, not just the text/model metadata around it.
  defp vector_set_id do
    query =
      from(v in ChunkVector,
        join: c in Chunk,
        on: c.id == v.chunk_id,
        order_by: [asc: c.urn, asc: v.kind, asc: v.lang, asc: v.translator_id],
        select:
          fragment(
            """
            encode(
              sha256(
                convert_to(
                  jsonb_build_array(
                    ?, ?, ?, ?, ?, ?, ?,
                    CASE
                      WHEN ? IS NULL THEN NULL
                      ELSE encode(sha256(vector_send(?)), 'hex')
                    END,
                    ?
                  )::text,
                  'UTF8'
                )
              ),
              'hex'
            )
            """,
            c.urn,
            v.kind,
            v.lang,
            v.translator_id,
            v.content_sha256,
            v.embedding_model,
            v.embedding_max_length,
            v.embedding,
            v.embedding,
            v.meta
          )
      )

    digest_query("vector-set", query)
  end

  defp digest_query(label, query) do
    context =
      :crypto.hash_init(:sha256)
      |> :crypto.hash_update("pramana:#{label}:#{@set_version}\n")

    context =
      query
      |> Repo.stream(max_rows: 2_000)
      |> Enum.reduce(context, fn fingerprint, acc ->
        :crypto.hash_update(acc, fingerprint <> "\n")
      end)

    @set_version <> ":" <> Base.encode16(:crypto.hash_final(context), case: :lower)
  end

  defp with_transaction(fun) do
    if Repo.in_transaction?() do
      fun.()
    else
      case Repo.transaction(fun, timeout: :infinity) do
        {:ok, value} -> value
        {:error, reason} -> raise "release identity transaction rolled back: #{inspect(reason)}"
      end
    end
  end

  defp sha(parts) do
    parts
    |> Enum.map_join("|", &inspect/1)
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
end
