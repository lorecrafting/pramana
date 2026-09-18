defmodule Pramana.Pilot.Scope do
  @moduledoc """
  Materializes the Chinese-first pilot's exact work/relation scope from one selected release.

  The command is read-only. It recomputes the demand proxy from the current quotation
  graph, verifies the four named Agamas, walks only typed non-model explanatory relations,
  inventories passage alignments and emits a content-hashed artifact.

  A generated artifact is evidence for review, not self-authorization. The strategy
  preflight stays blocked until an operator reviews a live artifact and records that
  decision separately.

  The historical tranche came from a one-off directed shared-text analysis whose rules,
  but not production query, were retained. This module therefore makes the rule explicit:

    * exclude same-family reuse (for example the T0220 lettered family);
    * count distinct passage hashes, never quotation rows;
    * use an asymmetric explanatory-role direction when exactly one side may explain
      the other;
    * otherwise direct later date_start to earlier date_start;
    * when role and date both resolve but disagree, count a conflict and use neither;
    * unresolved/conflicting pairs contribute no demand weight;
    * rank target families by distinct {citer_family, passage_hash} evidence.

  This remains a demand proxy. The artifact reports the direction denominator so the
  result cannot be read as an exhaustive citation census.
  """

  import Ecto.Query

  alias Pramana.Corpus.CommentaryAlignment
  alias Pramana.Corpus.Quotation
  alias Pramana.Corpus.Text
  alias Pramana.Corpus.Work
  alias Pramana.Corpus.WorkRelation
  alias Pramana.Pilot.ScopeArtifact
  alias Pramana.Relations
  alias Pramana.Release
  alias Pramana.Repo

  @agama_expectations %{
    "T0001" => "長阿含",
    "T0026" => "中阿含",
    "T0099" => "雜阿含",
    "T0125" => "增壹阿含"
  }

  @doc """
  Reads the live database and materializes one artifact.

  expected_release_id is mandatory on purpose. "Whatever is selected when this happens
  to run" is not a pilot identity.
  """
  @spec materialize(String.t()) :: {:ok, map()} | {:error, term()}
  def materialize(expected_release_id) when is_binary(expected_release_id) do
    transaction_result =
      Repo.transaction(fn ->
        # One repeatable snapshot prevents release/work/graph reads from describing
        # different moments when a corpus maintenance process commits concurrently.
        Repo.query!("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ")

        with {:ok, release} <- current_release(expected_release_id),
             input <- load_input(release),
             {:ok, artifact} <- build(input) do
          artifact
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)

    case transaction_result do
      {:ok, artifact} -> recheck_release_after_snapshot(expected_release_id, artifact)
      {:error, reason} -> {:error, reason}
    end
  end

  def materialize(_), do: {:error, :release_id_required}

  @doc """
  Pure materialization over explicit input maps.

  Kept public so fixtures can exercise ranking/traversal/artifact arithmetic without
  claiming a synthetic database is a live corpus acceptance run.
  """
  @spec build(map()) :: {:ok, map()} | {:error, term()}
  def build(%{
        release: release,
        works: works,
        quotation_rows: quotation_rows,
        relation_rows: raw_relation_rows,
        alignment_rows: alignment_rows
      }) do
    work_map = Map.new(works, &{&1.work_id, &1})

    with {:ok, ranking, ranking_detail} <- demand_ranking(quotation_rows, work_map),
         :ok <- verify_agamas(work_map) do
      seeds = seeds(ranking["top_demand"], work_map)

      {scope, admitted_relations} = expand(seeds, raw_relation_rows, work_map)
      considered_relations = considered_relation_rows(raw_relation_rows, scope)
      traversal_stats = relation_exclusion_stats(considered_relations, work_map)
      scope_works = present_works(scope, work_map)
      relations = present_relations(admitted_relations)

      with :ok <- ensure_unambiguous_relation_pairs(relations) do
        {alignments, relevant_alignment_rows} =
          alignment_coverage(relations, alignment_rows)

        payload =
          payload(
            release,
            ranking,
            seeds,
            scope_works,
            relations,
            alignments,
            traversal_stats,
            %{
              works: works,
              ranking: ranking_detail,
              relations: considered_relations,
              alignments: relevant_alignment_rows
            }
          )

        artifact = ScopeArtifact.finalize(payload)

        case ScopeArtifact.validate(artifact) do
          :ok -> {:ok, artifact}
          {:error, errors} -> {:error, {:invalid_artifact, errors}}
        end
      end
    end
  end

  def build(_), do: {:error, :invalid_scope_input}

  @doc """
  Recomputes the demand proxy from quotation rows and work metadata.

  Quotation rows are maps with a_work_id, b_work_id, and text_sha256.
  """
  @spec demand_ranking([map()], map()) :: {:ok, map(), map()} | {:error, term()}
  def demand_ranking(rows, work_map) do
    pairs = quotation_pairs(rows, work_map)

    classified =
      Enum.map(pairs, fn pair ->
        Map.put(pair, :direction, direction(pair, work_map))
      end)

    directed = Enum.filter(classified, &match?({:ok, _, _, _}, &1.direction))
    conflicts = Enum.count(classified, &match?({:conflict, _, _}, &1.direction))
    unresolved = Enum.count(classified, &(&1.direction == :unresolved))

    ranked =
      directed
      |> demand_targets()
      |> Enum.sort_by(fn row ->
        {-row.weight, -row.citing_families, row.family}
      end)

    top =
      ranked
      |> Enum.take(ScopeArtifact.demand_seed_count())
      |> Enum.with_index(1)
      |> Enum.map(fn {row, rank} ->
        %{
          "rank" => rank,
          "work_id" => row.work_id,
          "family" => row.family,
          "weight" => row.weight,
          "citing_families" => row.citing_families,
          "directed_pair_count" => row.directed_pair_count,
          "direction_methods" => row.direction_methods,
          "family_members" => row.family_members
        }
      end)

    if length(top) == ScopeArtifact.demand_seed_count() do
      method_counts =
        directed
        |> Enum.map(fn %{direction: {:ok, _citer, _target, method}} -> method end)
        |> Enum.frequencies()
        |> Map.new(fn {method, count} -> {Atom.to_string(method), count} end)

      cutoff_weight = top |> List.last() |> Map.fetch!("weight")

      cutoff_tied_families =
        ranked
        |> Enum.filter(&(&1.weight == cutoff_weight))
        |> Enum.map(& &1.family)
        |> Enum.sort()

      ranking = %{
        "rule" => ScopeArtifact.demand_ranking_rule(),
        "cross_family_pairs" => length(classified),
        "directed_pairs" => length(directed),
        "unresolved_pairs" => unresolved,
        "conflicting_pairs" => conflicts,
        "direction_method_counts" => method_counts,
        "cutoff_weight" => cutoff_weight,
        "cutoff_tied_families" => cutoff_tied_families,
        "top_demand" => top
      }

      detail = %{
        pairs: Enum.map(classified, &ranking_input_row/1),
        ranked_families: ranked
      }

      {:ok, ranking, detail}
    else
      {:error, {:insufficient_demand_ranking, length(top)}}
    end
  end

  defp current_release(expected_release_id) do
    case Release.current() do
      nil ->
        {:error, :unstamped_release}

      release ->
        cond do
          release.release_id != expected_release_id ->
            {:error, {:release_mismatch, expected_release_id, release.release_id}}

          not v2_release?(release) ->
            {:error, {:legacy_release_identity, release.release_id}}

          true ->
            case Release.drift() do
              :current -> {:ok, release}
              :unstamped -> {:error, :unstamped_release}
              drift -> {:error, {:release_drift, drift}}
            end
        end
    end
  end

  defp recheck_release_after_snapshot(expected_release_id, artifact) do
    case current_release(expected_release_id) do
      {:ok, release} ->
        if release.release_id == artifact["release"]["release_id"] do
          {:ok, artifact}
        else
          {:error, :release_changed_after_snapshot}
        end

      {:error, reason} ->
        {:error, {:release_changed_after_snapshot, reason}}
    end
  end

  defp v2_release?(release) do
    String.starts_with?(release.translation_set_id || "", "v2:") and
      String.starts_with?(release.vector_set_id || "", "v2:")
  end

  defp load_input(release) do
    %{
      release: %{
        release_id: release.release_id,
        source_bake_id: release.source_bake_id,
        translation_set_id: release.translation_set_id,
        vector_set_id: release.vector_set_id,
        stamped_at: DateTime.to_iso8601(release.stamped_at)
      },
      works: load_works(),
      quotation_rows: load_quotation_rows(release.source_bake_id),
      relation_rows: load_relation_rows(),
      alignment_rows: load_alignment_rows(release.source_bake_id)
    }
  end

  defp load_works do
    Repo.all(
      from w in Work,
        join: t in Text,
        on: t.work_id == w.id,
        where: t.source_id == "cbeta" and t.witness_id == "T",
        distinct: w.id,
        order_by: w.id,
        select: %{
          work_id: w.id,
          title: w.title,
          text_role: w.text_role,
          division: w.division,
          date_start: w.date_start,
          date_end: w.date_end
        }
    )
  end

  defp load_quotation_rows(source_bake_id) do
    Repo.all(
      from q in Quotation,
        join: a in Text,
        on: a.id == q.a_text_id,
        join: b in Text,
        on: b.id == q.b_text_id,
        where:
          q.bake_id == ^source_bake_id and
            a.source_id == "cbeta" and a.witness_id == "T" and
            b.source_id == "cbeta" and b.witness_id == "T",
        select: %{
          a_work_id: q.a_work_id,
          b_work_id: q.b_work_id,
          text_sha256: q.text_sha256
        }
    )
  end

  defp load_relation_rows do
    allowed_relations = ScopeArtifact.allowed_relations()

    Repo.all(
      from r in WorkRelation,
        where: r.relation in ^allowed_relations,
        order_by: [asc: r.target_work_id, asc: r.source_work_id, asc: r.relation, asc: r.method],
        select: %{
          source_work_id: r.source_work_id,
          target_work_id: r.target_work_id,
          target_work_ref: r.target_work_ref,
          relation: r.relation,
          scope: r.scope,
          target_urn: r.target_urn,
          confidence: r.confidence,
          method: r.method,
          evidence: r.evidence
        }
    )
  end

  defp load_alignment_rows(source_bake_id) do
    Repo.all(
      from a in CommentaryAlignment,
        where: a.bake_id == ^source_bake_id,
        order_by: [asc: a.root_work_id, asc: a.commentary_work_id, asc: a.root_urn],
        select: %{
          commentary_work_id: a.commentary_work_id,
          root_work_id: a.root_work_id,
          commentary_urn: a.commentary_urn,
          root_urn: a.root_urn,
          lemma_sha256: a.lemma_sha256,
          method: a.method,
          confidence: a.confidence
        }
    )
  end

  defp quotation_pairs(rows, work_map) do
    rows
    |> Enum.filter(fn row ->
      Map.has_key?(work_map, row.a_work_id) and
        Map.has_key?(work_map, row.b_work_id) and
        family(row.a_work_id) != family(row.b_work_id) and
        is_binary(row.text_sha256)
    end)
    |> Enum.group_by(fn row ->
      [a, b] = Enum.sort([row.a_work_id, row.b_work_id])
      {a, b}
    end)
    |> Enum.map(fn {{a, b}, grouped} ->
      %{
        a: a,
        b: b,
        hashes: grouped |> Enum.map(& &1.text_sha256) |> MapSet.new() |> Enum.sort()
      }
    end)
    |> Enum.sort_by(&{&1.a, &1.b})
  end

  defp direction(%{a: a, b: b}, work_map) do
    aw = Map.fetch!(work_map, a)
    bw = Map.fetch!(work_map, b)
    role = role_direction(aw, bw)
    date = date_direction(aw, bw)

    case {role, date} do
      {{role_citer, role_target}, {date_citer, date_target}}
      when role_citer == date_citer and role_target == date_target ->
        {:ok, role_citer, role_target, :role_and_date}

      {{citer, target}, nil} ->
        {:ok, citer, target, :role}

      {nil, {citer, target}} ->
        {:ok, citer, target, :date}

      {nil, nil} ->
        :unresolved

      {{role_citer, role_target}, {date_citer, date_target}} ->
        {:conflict, {role_citer, role_target}, {date_citer, date_target}}
    end
  end

  defp role_direction(a, b) do
    a_to_b = b.text_role in Relations.may_explain(a.text_role)
    b_to_a = a.text_role in Relations.may_explain(b.text_role)

    cond do
      a_to_b and not b_to_a -> {a.work_id, b.work_id}
      b_to_a and not a_to_b -> {b.work_id, a.work_id}
      true -> nil
    end
  end

  defp date_direction(a, b) do
    cond do
      is_integer(a.date_start) and is_integer(b.date_start) and a.date_start > b.date_start ->
        {a.work_id, b.work_id}

      is_integer(a.date_start) and is_integer(b.date_start) and b.date_start > a.date_start ->
        {b.work_id, a.work_id}

      true ->
        nil
    end
  end

  defp demand_targets(directed_pairs) do
    directed_pairs
    |> Enum.group_by(fn %{direction: {:ok, _citer, target, _method}} -> family(target) end)
    |> Enum.map(fn {target_family, pairs} ->
      evidence =
        for %{hashes: hashes, direction: {:ok, citer, _target, _method}} <- pairs,
            hash <- hashes,
            into: MapSet.new() do
          {family(citer), hash}
        end

      member_evidence =
        pairs
        |> Enum.group_by(fn %{direction: {:ok, _citer, target, _method}} -> target end)
        |> Enum.map(fn {member, member_pairs} ->
          weight =
            for %{hashes: hashes, direction: {:ok, citer, _target, _method}} <- member_pairs,
                hash <- hashes,
                into: MapSet.new() do
              {family(citer), hash}
            end
            |> MapSet.size()

          {member, weight}
        end)
        |> Enum.sort_by(fn {member, weight} -> {-weight, member} end)

      {work_id, _member_weight} = hd(member_evidence)

      %{
        family: target_family,
        work_id: work_id,
        weight: MapSet.size(evidence),
        citing_families: evidence |> Enum.map(&elem(&1, 0)) |> MapSet.new() |> MapSet.size(),
        directed_pair_count: length(pairs),
        direction_methods:
          pairs
          |> Enum.map(fn %{direction: {:ok, _citer, _target, method}} -> Atom.to_string(method) end)
          |> Enum.frequencies(),
        family_members: Enum.map(member_evidence, &elem(&1, 0))
      }
    end)
  end

  defp ranking_input_row(pair) do
    %{
      a_work_id: pair.a,
      b_work_id: pair.b,
      passage_hashes: pair.hashes,
      direction: direction_for_digest(pair.direction)
    }
  end

  defp direction_for_digest({:ok, citer, target, method}),
    do: %{status: "directed", citer: citer, target: target, method: Atom.to_string(method)}

  defp direction_for_digest({:conflict, role, date}),
    do: %{status: "conflict", role: Tuple.to_list(role), date: Tuple.to_list(date)}

  defp direction_for_digest(:unresolved), do: %{status: "unresolved"}

  defp verify_agamas(work_map) do
    Enum.reduce_while(@agama_expectations, :ok, fn {work_id, title_fragment}, :ok ->
      case Map.get(work_map, work_id) do
        nil ->
          {:halt, {:error, {:missing_agama, work_id}}}

        %{title: title, division: "阿含部", text_role: "root"} when is_binary(title) ->
          if String.contains?(title, title_fragment) do
            {:cont, :ok}
          else
            {:halt, {:error, {:agama_identity_mismatch, work_id, title}}}
          end

        work ->
          {:halt, {:error, {:agama_provenance_mismatch, work_id, work}}}
      end
    end)
  end

  defp seeds(top_demand, work_map) do
    demand =
      Map.new(top_demand, fn row ->
        {row["work_id"], %{rank: row["rank"], weight: row["weight"]}}
      end)

    ids =
      (Map.keys(demand) ++ ScopeArtifact.agama_ids())
      |> Enum.uniq()
      |> Enum.sort()

    Enum.map(ids, fn work_id ->
      work = Map.fetch!(work_map, work_id)
      demand_info = Map.get(demand, work_id)

      sources =
        []
        |> maybe_seed_source(not is_nil(demand_info), "demand_rank")
        |> maybe_seed_source(work_id in ScopeArtifact.agama_ids(), "agama")
        |> Enum.sort()

      %{
        "work_id" => work_id,
        "title" => work.title,
        "text_role" => work.text_role,
        "division" => work.division,
        "seed_sources" => sources,
        "demand_rank" => if(demand_info, do: demand_info.rank),
        "demand_weight" => if(demand_info, do: demand_info.weight)
      }
    end)
  end

  defp maybe_seed_source(list, true, source), do: [source | list]
  defp maybe_seed_source(list, false, _source), do: list

  defp expand(seeds, relation_rows, work_map) do
    allowed_methods = MapSet.new(ScopeArtifact.allowed_relation_methods())
    allowed_relations = MapSet.new(ScopeArtifact.allowed_relations())

    eligible =
      relation_rows
      |> Enum.filter(fn row ->
        MapSet.member?(allowed_relations, row.relation) and
          MapSet.member?(allowed_methods, row.method) and
          not is_nil(row.target_work_id) and
          relation_role_compatible?(row, work_map)
      end)
      |> Enum.group_by(&{&1.source_work_id, &1.target_work_id, &1.relation})
      |> Map.new(fn {key, rows} -> {key, Enum.sort_by(rows, &assertion_key/1)} end)

    seed_ids = Enum.map(seeds, & &1["work_id"])

    initial_scope =
      Map.new(seed_ids, fn work_id ->
        {work_id, %{min_hop: 0, seed_ids: [work_id]}}
      end)

    initial_frontier = MapSet.new(seed_ids)

    {scope, admitted, _frontier} =
      Enum.reduce(
        1..ScopeArtifact.max_relation_depth(),
        {initial_scope, %{}, initial_frontier},
        fn hop, {scope, admitted, frontier} ->
          expand_hop(hop, scope, admitted, frontier, eligible, work_map)
        end
      )

    {scope, Map.values(admitted)}
  end

  defp relation_role_compatible?(row, work_map) do
    with %{text_role: source_role} <- Map.get(work_map, row.source_work_id),
         %{text_role: target_role} <- Map.get(work_map, row.target_work_id) do
      target_role in Relations.may_explain(source_role)
    else
      _ -> false
    end
  end

  defp expand_hop(hop, scope, admitted, frontier, eligible, work_map) do
    edges =
      eligible
      |> Enum.filter(fn {{source, target, _relation}, _rows} ->
        MapSet.member?(frontier, target) and Map.has_key?(work_map, source)
      end)
      |> Enum.sort_by(fn {{source, target, relation}, _rows} -> {target, source, relation} end)

    Enum.reduce(edges, {scope, admitted, MapSet.new()}, fn
      {{source, target, relation}, assertions}, {scope_acc, admitted_acc, frontier_acc} ->
        target_seeds = scope_acc |> Map.fetch!(target) |> Map.fetch!(:seed_ids)
        existing = Map.get(scope_acc, source)

        scope_acc =
          cond do
            is_nil(existing) ->
              Map.put(scope_acc, source, %{min_hop: hop, seed_ids: target_seeds})

            existing.min_hop == 0 ->
              scope_acc

            true ->
              Map.update!(scope_acc, source, fn item ->
                %{item | seed_ids: Enum.sort(Enum.uniq(item.seed_ids ++ target_seeds))}
              end)
          end

        relation_key = {source, target, relation}

        admitted_acc =
          Map.update(
            admitted_acc,
            relation_key,
            %{
              source_work_id: source,
              target_work_id: target,
              relation: relation,
              hop: hop,
              seed_ids: target_seeds,
              assertions: assertions
            },
            fn item ->
              %{item | seed_ids: Enum.sort(Enum.uniq(item.seed_ids ++ target_seeds))}
            end
          )

        frontier_acc =
          if is_nil(existing), do: MapSet.put(frontier_acc, source), else: frontier_acc

        {scope_acc, admitted_acc, frontier_acc}
    end)
  end

  defp assertion_key(row) do
    {
      row.method || "",
      row.confidence || "",
      row.scope || "",
      row.target_urn || "",
      ScopeArtifact.digest(row.evidence || %{})
    }
  end

  defp present_works(scope, work_map) do
    scope
    |> Enum.map(fn {work_id, reach} ->
      work = Map.fetch!(work_map, work_id)

      %{
        "work_id" => work_id,
        "title" => work.title,
        "text_role" => work.text_role,
        "division" => work.division,
        "date_start" => work.date_start,
        "date_end" => work.date_end,
        "source" => "cbeta",
        "witness" => "T",
        "min_hop" => reach.min_hop,
        "seed_ids" => Enum.sort(reach.seed_ids)
      }
    end)
    |> Enum.sort_by(& &1["work_id"])
  end

  defp present_relations(relations) do
    relations
    |> Enum.map(fn row ->
      %{
        "source_work_id" => row.source_work_id,
        "target_work_id" => row.target_work_id,
        "relation" => row.relation,
        "hop" => row.hop,
        "seed_ids" => Enum.sort(row.seed_ids),
        "assertions" =>
          Enum.map(row.assertions, fn assertion ->
            %{
              "method" => assertion.method,
              "confidence" => assertion.confidence,
              "scope" => assertion.scope,
              "target_urn" => assertion.target_urn,
              "evidence" => assertion.evidence || %{},
              "evidence_sha256" => ScopeArtifact.digest(assertion.evidence || %{})
            }
          end)
      }
    end)
    |> Enum.sort_by(fn row ->
      {row["hop"], row["target_work_id"], row["source_work_id"], row["relation"]}
    end)
  end

  defp alignment_coverage(relations, alignment_rows) do
    admitted_pairs =
      relations
      |> Enum.map(&{&1["source_work_id"], &1["target_work_id"]})
      |> MapSet.new()

    relevant_rows =
      alignment_rows
      |> Enum.filter(fn row ->
        MapSet.member?(admitted_pairs, {row.commentary_work_id, row.root_work_id})
      end)

    grouped =
      Enum.group_by(relevant_rows, &{&1.commentary_work_id, &1.root_work_id})

    coverage =
      Enum.map(relations, fn relation ->
        rows =
          Map.get(
            grouped,
            {relation["source_work_id"], relation["target_work_id"]},
            []
          )

        %{
          "commentary_work_id" => relation["source_work_id"],
          "target_work_id" => relation["target_work_id"],
          "relation" => relation["relation"],
          "alignment_rows" => length(rows),
          "distinct_root_urns" => rows |> Enum.map(& &1.root_urn) |> Enum.uniq() |> length(),
          "distinct_commentary_urns" =>
            rows |> Enum.map(& &1.commentary_urn) |> Enum.uniq() |> length(),
          "has_passage_alignment" => rows != []
        }
      end)
      |> Enum.sort_by(fn row ->
        {row["target_work_id"], row["commentary_work_id"], row["relation"]}
      end)

    {coverage, relevant_rows}
  end

  defp ensure_unambiguous_relation_pairs(relations) do
    ambiguous =
      relations
      |> Enum.group_by(&{&1["source_work_id"], &1["target_work_id"]})
      |> Enum.find(fn {_pair, rows} ->
        rows |> Enum.map(& &1["relation"]) |> Enum.uniq() |> length() > 1
      end)

    case ambiguous do
      nil ->
        :ok

      {{source, target}, rows} ->
        types = rows |> Enum.map(& &1["relation"]) |> Enum.uniq() |> Enum.sort()
        {:error, {:ambiguous_relation_types, source, target, types}}
    end
  end

  defp considered_relation_rows(relation_rows, scope) do
    max_depth = ScopeArtifact.max_relation_depth()

    relation_rows
    |> Enum.filter(fn row ->
      case Map.get(scope, row.target_work_id) do
        %{min_hop: hop} when hop < max_depth -> true
        _ -> false
      end
    end)
    |> Enum.sort_by(fn row ->
      {row.target_work_id || "", row.source_work_id || "", row.relation || "", row.method || ""}
    end)
  end

  defp relation_exclusion_stats(rows, work_map) do
    allowed_methods = ScopeArtifact.allowed_relation_methods()

    %{
      outside_cbeta_relation_rows:
        Enum.count(rows, fn row ->
          row.method in allowed_methods and not Map.has_key?(work_map, row.source_work_id)
        end),
      excluded_model_relation_rows:
        Enum.count(rows, &(&1.method == "llm")),
      excluded_role_incoherent_relation_rows:
        Enum.count(rows, fn row ->
          row.method in allowed_methods and
            Map.has_key?(work_map, row.source_work_id) and
            Map.has_key?(work_map, row.target_work_id) and
            not relation_role_compatible?(row, work_map)
        end)
    }
  end

  defp payload(
         release,
         ranking,
         seeds,
         works,
         relations,
         alignments,
         traversal_stats,
         inputs
       ) do
    %{
      "release" => stringify_release(release),
      "selection" => %{
        "demand_seed_count" => ScopeArtifact.demand_seed_count(),
        "demand_ranking_rule" => ScopeArtifact.demand_ranking_rule(),
        "agama_work_ids" => ScopeArtifact.agama_ids(),
        "scope_source" => "cbeta.T",
        "relation_types" => ScopeArtifact.allowed_relations(),
        "relation_methods" => ScopeArtifact.allowed_relation_methods(),
        "max_relation_depth" => ScopeArtifact.max_relation_depth()
      },
      "ranking" => ranking,
      "seeds" => seeds,
      "works" => works,
      "relations" => relations,
      "alignment_coverage" => alignments,
      "denominators" => denominators(seeds, works, relations, alignments, traversal_stats),
      "derivation_status" => %{
        "quotation_graph_completeness" => "not_recorded_by_database",
        "relation_graph_completeness" => "not_recorded_by_database",
        "alignment_graph_completeness" => "not_recorded_by_database",
        "structural_validation_establishes_live_currentness" => false,
        "live_acceptance_requires_external_completion_evidence" => true,
        "live_acceptance_requires_quiesced_repeat_match" => true
      },
      "input_digests" => %{
        "work_metadata" => ScopeArtifact.digest(stable_works(inputs.works)),
        "quotation_graph" => ScopeArtifact.digest(inputs.ranking),
        "relation_graph" => ScopeArtifact.digest(stable_relations(inputs.relations)),
        "alignment_graph" => ScopeArtifact.digest(stable_alignments(inputs.alignments))
      }
    }
  end

  defp stringify_release(release) do
    %{
      "release_id" => fetch(release, :release_id),
      "source_bake_id" => fetch(release, :source_bake_id),
      "translation_set_id" => fetch(release, :translation_set_id),
      "vector_set_id" => fetch(release, :vector_set_id),
      "stamped_at" => fetch(release, :stamped_at)
    }
  end

  defp fetch(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp denominators(seeds, works, relations, alignments, traversal_stats) do
    %{
      "combined_seed_count" => length(seeds),
      "demand_seed_count" => ScopeArtifact.demand_seed_count(),
      "agama_required_count" => length(ScopeArtifact.agama_ids()),
      "total_work_count" => length(works),
      "expanded_work_count" => length(works) - length(seeds),
      "relation_edge_count" => length(relations),
      "relation_assertion_count" =>
        relations |> Enum.map(&(length(&1["assertions"]))) |> Enum.sum(),
      "relation_edges_with_alignment" =>
        Enum.count(alignments, & &1["has_passage_alignment"]),
      "alignment_rows" => alignments |> Enum.map(& &1["alignment_rows"]) |> Enum.sum(),
      "works_by_text_role" =>
        works
        |> Enum.frequencies_by(&(&1["text_role"] || "unknown"))
        |> Map.new(fn {key, value} -> {to_string(key), value} end),
      "excluded_relation_rows_outside_cbeta" => traversal_stats.outside_cbeta_relation_rows,
      "excluded_model_relation_rows" => traversal_stats.excluded_model_relation_rows,
      "excluded_role_incoherent_relation_rows" =>
        traversal_stats.excluded_role_incoherent_relation_rows
    }
  end

  defp stable_works(works) do
    works
    |> Enum.map(fn work ->
      %{
        work_id: work.work_id,
        title: work.title,
        text_role: work.text_role,
        division: work.division,
        date_start: work.date_start,
        date_end: work.date_end
      }
    end)
    |> Enum.sort_by(& &1.work_id)
  end

  defp stable_relations(rows) do
    rows
    |> Enum.map(fn row ->
      %{
        source_work_id: row.source_work_id,
        target_work_id: row.target_work_id,
        target_work_ref: row.target_work_ref,
        relation: row.relation,
        scope: row.scope,
        target_urn: row.target_urn,
        confidence: row.confidence,
        method: row.method,
        evidence: row.evidence
      }
    end)
    |> Enum.sort_by(fn row ->
      {row.target_work_id || "", row.source_work_id || "", row.relation || "", row.method || ""}
    end)
  end

  defp stable_alignments(rows) do
    rows
    |> Enum.map(fn row ->
      %{
        commentary_work_id: row.commentary_work_id,
        root_work_id: row.root_work_id,
        commentary_urn: row.commentary_urn,
        root_urn: row.root_urn,
        lemma_sha256: row.lemma_sha256,
        method: row.method,
        confidence: row.confidence
      }
    end)
    |> Enum.sort_by(fn row ->
      {row.root_work_id || "", row.commentary_work_id || "", row.root_urn || "",
       row.commentary_urn || "", row.lemma_sha256 || ""}
    end)
  end

  defp family(work_id), do: Regex.replace(~r/[a-z]+$/, work_id, "")
end
