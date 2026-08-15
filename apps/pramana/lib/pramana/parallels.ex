defmodule Pramana.Parallels do
  @moduledoc """
  Cross-tradition parallels, from curated scholarship rather than similarity.

  SuttaCentral's `sc-data` carries **388,074 hand-curated relations** between texts in
  Chinese, Pāli, Sanskrit and Tibetan, typed by how strong the relation is. That is
  decades of comparative work, freely given. `CLAUDE.md` invariant #5 — deterministic
  before probabilistic — makes ingesting it the obvious move: an embedding could
  *approximate* this and would be worse, unexplainable, and unattributable.

  ## Their ids, verbatim

  `sa1`, `mn10`, `t792` are the field's identifiers. Inventing our own mapping would be
  the same mistake as inventing citation ids, so the uids are stored as printed and the
  resolution to our URNs is kept alongside rather than instead.

  ## Relation type is a claim about strength

  | relation | count | meaning |
  |---|---|---|
  | `full` | 353,874 | a full parallel |
  | `resembling` | 22,512 | resembles, without being a parallel |
  | `sections` | 10,834 | a section corresponds |
  | `mentions` | 730 | mentions in passing |
  | `retells` | 124 | retells the story |

  Flattening these into "related" would let a passing mention be presented as a
  parallel. They stay distinct all the way into the answer.
  """

  import Ecto.Query

  alias Pramana.Corpus.Segment
  alias Pramana.Corpus.Text
  alias Pramana.Corpus.TextAnchor
  alias Pramana.Corpus.TextParallel
  alias Pramana.Parallels.Anchor
  alias Pramana.Repo

  @relations ~w(full resembling sections mentions retells)

  @doc "SuttaCentral's relation types, strongest first."
  @spec relations() :: [String.t()]
  def relations, do: @relations

  @doc """
  Resolves a SuttaCentral text entry to a URN in this corpus, or `nil`.

  Looks the segment **up** rather than constructing a URN: the juan is in our data and
  not in SuttaCentral's reference, so building `T0099_001@…` by hand would be guessing
  at a component we already know.
  """
  @spec resolve_anchor(map()) :: map() | nil
  def resolve_anchor(entry) do
    with anchor when not is_nil(anchor) <- Anchor.from_entry(entry),
         urn when not is_nil(urn) <- lookup_urn(anchor) do
      %{
        uid: entry["uid"],
        work_id: anchor.work_id,
        urn: with_range(urn, anchor),
        acronym: entry["acronym"],
        volpage: entry["volpage"]
      }
    else
      _ -> nil
    end
  end

  defp lookup_urn(anchor) do
    Repo.one(
      from s in Segment,
        join: t in Text,
        on: t.id == s.text_id,
        where:
          t.work_id == ^anchor.work_id and
            s.page == ^String.pad_leading(anchor.page, 4, "0") and
            s.register == ^anchor.register and s.line == ^anchor.line,
        select: s.urn,
        limit: 1
    )
  end

  # A volpage stating a span becomes a range URN, because narrowing it to its first line
  # would quietly claim less than the source does.
  defp with_range(urn, %{page_end: nil}), do: urn
  defp with_range(urn, anchor), do: urn <> "-" <> Anchor.locator_end(anchor)

  @doc "Stores resolved anchors."
  @spec store_anchors([map()]) :: {:ok, non_neg_integer()}
  def store_anchors(anchors) do
    now = DateTime.utc_now()
    rows = Enum.map(anchors, &Map.merge(&1, %{inserted_at: now, updated_at: now}))

    {count, _} =
      Repo.insert_all(TextAnchor, rows,
        on_conflict: {:replace, [:work_id, :urn, :acronym, :volpage, :updated_at]},
        conflict_target: [:uid]
      )

    {:ok, count}
  end

  @doc """
  Flattens SuttaCentral's `new_parallels.json` into directed pairs.

  Their format is `%{"an1.1-5" => %{"full" => ["t792", "ea9.7"]}}`. A leading `~` marks
  an indirect reference and a `#` suffix names a sub-passage; both are preserved rather
  than stripped, because they are the source's own hedging.
  """
  @spec flatten(map()) :: [map()]
  def flatten(parallels) do
    Enum.flat_map(parallels, fn {source, groups} ->
      Enum.flat_map(groups, fn {relation, targets} -> pairs(source, relation, targets) end)
    end)
  end

  # The flat case: a relation naming a list of texts.
  defp pairs(source, relation, targets) when is_list(targets) and relation in @relations do
    Enum.map(targets, fn target ->
      %{
        source_uid: strip(source),
        target_uid: strip(target),
        relation: relation,
        partial: partial?(source) or partial?(target)
      }
    end)
  end

  # `sections` nests: `%{"an1.17#1.1" => %{"mentions" => ["pe3#27.1"]}}`. The key is a
  # SUB-PASSAGE of the source and the inner map carries its own relation types — so this
  # is passage-level scholarship, finer than the flat form, and flattening it to
  # "an1.17 sections pe3" would throw away both the precision and the real relation.
  defp pairs(_source, "sections", targets) when is_map(targets) do
    Enum.flat_map(targets, fn {sub_source, inner} ->
      Enum.flat_map(inner, fn {relation, list} -> pairs(sub_source, relation, list) end)
    end)
  end

  defp pairs(_source, _relation, _targets), do: []

  # A leading `~` is the source's own hedge that the reference is indirect.
  defp partial?(uid), do: String.starts_with?(uid, "~")

  defp strip(uid), do: uid |> String.trim_leading("~") |> String.split("#") |> hd()

  @doc "Stores parallel pairs, resolving each side against the anchor table."
  @spec store([map()]) :: {:ok, map()}
  def store(pairs) do
    anchors =
      Repo.all(from a in TextAnchor, select: {a.uid, {a.urn, a.work_id}})
      |> Map.new()

    now = DateTime.utc_now()

    rows =
      pairs
      |> Enum.uniq_by(&{&1.source_uid, &1.target_uid, &1.relation})
      |> Enum.map(fn pair ->
        {source_urn, source_work} = Map.get(anchors, pair.source_uid, {nil, nil})
        {target_urn, target_work} = Map.get(anchors, pair.target_uid, {nil, nil})

        pair
        |> Map.merge(%{
          source_urn: source_urn,
          source_work_id: source_work,
          target_urn: target_urn,
          target_work_id: target_work,
          inserted_at: now,
          updated_at: now
        })
      end)

    written =
      rows
      |> Enum.chunk_every(5_000)
      |> Enum.reduce(0, fn batch, acc ->
        {n, _} =
          Repo.insert_all(TextParallel, batch,
            on_conflict:
              {:replace,
               [:partial, :source_urn, :target_urn, :source_work_id, :target_work_id, :updated_at]},
            conflict_target: [:source_uid, :target_uid, :relation]
          )

        acc + n
      end)

    {:ok, %{written: written, total: length(rows)}}
  end

  @doc """
  Parallels for a work or a SuttaCentral uid.

  Directed both ways: a parallel is symmetric in fact, but the source data records it
  once, so querying only one direction would hide half of what is known.
  """
  @spec for_work(String.t(), keyword()) :: [map()]
  def for_work(work_id, opts \\ []) do
    relations = Keyword.get(opts, :relations, @relations)

    forward =
      from p in TextParallel,
        where: p.source_work_id == ^work_id and p.relation in ^relations,
        select: %{
          uid: p.target_uid,
          urn: p.target_urn,
          work_id: p.target_work_id,
          relation: p.relation,
          partial: p.partial,
          from_uid: p.source_uid,
          from_urn: p.source_urn
        }

    backward =
      from p in TextParallel,
        where: p.target_work_id == ^work_id and p.relation in ^relations,
        select: %{
          uid: p.source_uid,
          urn: p.source_urn,
          work_id: p.source_work_id,
          relation: p.relation,
          partial: p.partial,
          from_uid: p.target_uid,
          from_urn: p.target_urn
        }

    Repo.all(forward) ++ Repo.all(backward)
  end

  @doc "Parallels for one SuttaCentral uid, both directions."
  @spec for_uid(String.t()) :: [map()]
  def for_uid(uid) do
    forward =
      from p in TextParallel,
        where: p.source_uid == ^uid,
        select: %{
          uid: p.target_uid,
          urn: p.target_urn,
          work_id: p.target_work_id,
          relation: p.relation,
          partial: p.partial
        }

    backward =
      from p in TextParallel,
        where: p.target_uid == ^uid,
        select: %{
          uid: p.source_uid,
          urn: p.source_urn,
          work_id: p.source_work_id,
          relation: p.relation,
          partial: p.partial
        }

    Repo.all(forward) ++ Repo.all(backward)
  end

  @doc "The anchor for a uid, if we resolved one."
  @spec anchor(String.t()) :: TextAnchor.t() | nil
  def anchor(uid), do: Repo.get(TextAnchor, uid)

  @doc "Counts, for the inventory and the gate."
  @spec stats() :: map()
  def stats do
    %{
      parallels: Repo.aggregate(TextParallel, :count),
      anchors: Repo.aggregate(TextAnchor, :count),
      by_relation:
        Repo.all(
          from p in TextParallel,
            group_by: p.relation,
            select: {p.relation, count(p.id)},
            order_by: [desc: count(p.id)]
        )
        |> Map.new(),
      resolvable_both_ends:
        Repo.aggregate(
          from(p in TextParallel, where: not is_nil(p.source_urn) and not is_nil(p.target_urn)),
          :count
        ),
      resolvable_one_end:
        Repo.aggregate(
          from(p in TextParallel,
            where:
              (is_nil(p.source_urn) and not is_nil(p.target_urn)) or
                (not is_nil(p.source_urn) and is_nil(p.target_urn))
          ),
          :count
        )
    }
  end
end
