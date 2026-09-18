defmodule Pramana.Pilot.ScopeArtifact do
  @moduledoc """
  Pure contract for one materialized Chinese pilot scope.

  This module has no Repo, Ecto or application-start dependency so a saved artifact can be
  checked independently of the live corpus that produced it. Validation establishes
  structure, internal denominators, frozen scope parameters and the content hash. It does
  not establish that the artifact still matches a live database; the materializer owns
  that boundary.
  """

  @schema "pramana-pilot-scope/v1"
  @pilot_id "chinese-commentary-v1"
  @agama_ids ~w(T0001 T0026 T0099 T0125)
  @relations ~w(comments_on subcommentary_of)
  @relation_methods ~w(catalogue manifest title_match lemma_match shared_text)
  @max_relation_depth 2
  @demand_seed_count 10
  @demand_ranking_rule "directed_shared_text_v1"

  @top_level ~w(
    schema
    pilot_id
    scope_content_sha256
    release
    selection
    ranking
    seeds
    works
    relations
    alignment_coverage
    denominators
    derivation_status
    input_digests
  )

  @doc "The four named Āgama works required by the charter."
  @spec agama_ids() :: [String.t()]
  def agama_ids, do: @agama_ids

  @doc "The only relation types that may expand the v1 pilot scope."
  @spec allowed_relations() :: [String.t()]
  def allowed_relations, do: @relations

  @doc "Non-model assertion methods admitted by the v1 scope materializer."
  @spec allowed_relation_methods() :: [String.t()]
  def allowed_relation_methods, do: @relation_methods

  @doc "The frozen scope-traversal ceiling."
  @spec max_relation_depth() :: pos_integer()
  def max_relation_depth, do: @max_relation_depth

  @doc "The number of demand-ranked seed families admitted before the Āgamas are added."
  @spec demand_seed_count() :: pos_integer()
  def demand_seed_count, do: @demand_seed_count

  @doc "The frozen rule identifier for the v1 demand-ranking algorithm."
  @spec demand_ranking_rule() :: String.t()
  def demand_ranking_rule, do: @demand_ranking_rule

  @doc """
  Adds the contract identifiers and a SHA-256 over the complete semantic artifact.

  The hash excludes only itself. No wall-clock generation timestamp belongs in the
  semantic payload, so re-materializing unchanged inputs produces the same bytes and hash.
  """
  @spec finalize(map()) :: map()
  def finalize(payload) when is_map(payload) do
    artifact =
      payload
      |> Map.put("schema", @schema)
      |> Map.put("pilot_id", @pilot_id)
      |> Map.delete("scope_content_sha256")

    Map.put(artifact, "scope_content_sha256", digest(artifact))
  end

  @doc "Canonical compact JSON: map keys are sorted recursively."
  @spec encode(map()) :: binary()
  def encode(artifact), do: canonical_json(artifact) <> "\n"

  @doc "Loads JSON written by this contract without requiring Jason."
  @spec decode!(binary()) :: term()
  def decode!(bytes), do: bytes |> :json.decode() |> normalize_json()

  @doc "SHA-256 of a term's canonical JSON representation."
  @spec digest(term()) :: String.t()
  def digest(term) do
    term
    |> canonical_json()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  @doc """
  Validates the saved artifact's closed v1 shape and arithmetic.

  Live release/current-corpus verification is deliberately absent here. A structurally
  valid historical artifact is still historical evidence rather than proof of current
  readiness.
  """
  @spec validate(map()) :: :ok | {:error, [String.t()]}
  def validate(artifact) when is_map(artifact) do
    errors =
      []
      |> check_top_level(artifact)
      |> check_hash(artifact)
      |> check_release(artifact["release"])
      |> check_selection(artifact["selection"])
      |> check_ranking(artifact["ranking"])
      |> check_seeds(artifact["seeds"], artifact["ranking"])
      |> check_works(artifact["works"], artifact["seeds"])
      |> check_relations(artifact["relations"], artifact["works"], artifact["seeds"])
      |> check_alignments(artifact["alignment_coverage"], artifact["relations"])
      |> check_denominators(artifact)
      |> check_derivation_status(artifact["derivation_status"])
      |> check_input_digests(artifact["input_digests"])

    case Enum.reverse(errors) do
      [] -> :ok
      found -> {:error, found}
    end
  end

  def validate(_artifact), do: {:error, ["scope artifact must be an object"]}

  defp check_top_level(errors, artifact) do
    actual = Map.keys(artifact)
    unknown = actual -- @top_level
    missing = @top_level -- actual

    errors
    |> add_if(artifact["schema"] != @schema, "schema must be #{@schema}")
    |> add_if(artifact["pilot_id"] != @pilot_id, "pilot_id must be #{@pilot_id}")
    |> add_if(unknown != [], "scope artifact contains unknown top-level fields")
    |> add_if(missing != [], "scope artifact is missing required top-level fields")
  end

  defp check_hash(errors, artifact) do
    expected = artifact |> Map.delete("scope_content_sha256") |> digest()

    errors
    |> add_if(not sha256?(artifact["scope_content_sha256"]), "scope_content_sha256 is invalid")
    |> add_if(
      artifact["scope_content_sha256"] != expected,
      "scope_content_sha256 does not match canonical artifact content"
    )
  end

  defp check_release(errors, release) when is_map(release) do
    errors
    |> add_if(not nonempty?(release["release_id"]), "release.release_id is required")
    |> add_if(not nonempty?(release["source_bake_id"]), "release.source_bake_id is required")
    |> add_if(
      not v2_component?(release["translation_set_id"]),
      "release.translation_set_id must be a v2 content identity"
    )
    |> add_if(
      not v2_component?(release["vector_set_id"]),
      "release.vector_set_id must be a v2 content identity"
    )
    |> add_if(not nonempty?(release["stamped_at"]), "release.stamped_at is required")
  end

  defp check_release(errors, _), do: ["release must be an object" | errors]

  defp check_selection(errors, selection) when is_map(selection) do
    errors
    |> add_if(
      selection["demand_seed_count"] != @demand_seed_count,
      "selection.demand_seed_count must be #{@demand_seed_count}"
    )
    |> add_if(
      selection["demand_ranking_rule"] != @demand_ranking_rule,
      "selection.demand_ranking_rule must be #{@demand_ranking_rule}"
    )
    |> add_if(
      selection["agama_work_ids"] != @agama_ids,
      "selection.agama_work_ids must match the four charter Āgamas"
    )
    |> add_if(
      selection["relation_types"] != @relations,
      "selection.relation_types must match the frozen v1 relation set"
    )
    |> add_if(
      selection["relation_methods"] != @relation_methods,
      "selection.relation_methods must match the frozen non-model assertion set"
    )
    |> add_if(
      selection["max_relation_depth"] != @max_relation_depth,
      "selection.max_relation_depth must be #{@max_relation_depth}"
    )
    |> add_if(
      selection["scope_source"] != "cbeta.T",
      "selection.scope_source must remain cbeta.T"
    )
  end

  defp check_selection(errors, _), do: ["selection must be an object" | errors]

  defp check_ranking(errors, ranking) when is_map(ranking) do
    top = ranking["top_demand"] || []
    work_ids = Enum.map(top, & &1["work_id"])
    families = Enum.map(top, & &1["family"])
    same_weight_families = ranking["cutoff_same_weight_families"] || []
    equivalent_families = ranking["cutoff_equivalent_families"] || []
    tenth = Enum.at(top, @demand_seed_count - 1)

    errors
    |> add_if(
      ranking["rule"] != @demand_ranking_rule,
      "ranking.rule must be #{@demand_ranking_rule}"
    )
    |> add_if(length(top) != @demand_seed_count, "ranking.top_demand must contain ten rows")
    |> add_if(not sorted_unique_rank?(top), "ranking.top_demand ranks must be unique 1..10")
    |> add_if(
      length(work_ids) != length(Enum.uniq(work_ids)),
      "ranking demand work ids must be unique"
    )
    |> add_if(
      length(families) != length(Enum.uniq(families)),
      "ranking demand families must be unique"
    )
    |> add_if(
      Enum.any?(top, &(not positive_integer?(&1["weight"]))),
      "ranking demand weights must be positive integers"
    )
    |> add_if(
      not positive_integer?(ranking["cutoff_weight"]),
      "ranking.cutoff_weight must be a positive integer"
    )
    |> add_if(
      is_map(tenth) and ranking["cutoff_weight"] != tenth["weight"],
      "ranking.cutoff_weight must equal rank ten weight"
    )
    |> add_if(
      not positive_integer?(ranking["cutoff_citing_families"]),
      "ranking.cutoff_citing_families must be a positive integer"
    )
    |> add_if(
      is_map(tenth) and ranking["cutoff_citing_families"] != tenth["citing_families"],
      "ranking.cutoff_citing_families must equal rank ten citing_families"
    )
    |> add_if(
      same_weight_families != Enum.sort(Enum.uniq(same_weight_families)),
      "ranking.cutoff_same_weight_families must be sorted and unique"
    )
    |> add_if(
      equivalent_families != Enum.sort(Enum.uniq(equivalent_families)),
      "ranking.cutoff_equivalent_families must be sorted and unique"
    )
    |> add_if(
      is_map(tenth) and tenth["family"] not in same_weight_families,
      "ranking.cutoff_same_weight_families must include the rank ten family"
    )
    |> add_if(
      is_map(tenth) and tenth["family"] not in equivalent_families,
      "ranking.cutoff_equivalent_families must include the rank ten family"
    )
    |> add_if(
      not Enum.all?(equivalent_families, &(&1 in same_weight_families)),
      "ranking cutoff-equivalent families must be a subset of same-weight families"
    )
    |> add_if(
      not valid_direction_method_counts?(ranking["direction_method_counts"], ranking["directed_pairs"]),
      "ranking.direction_method_counts must exactly account for directed_pairs"
    )
    |> add_if(
      Enum.any?(top, &(not valid_top_demand_row?(&1))),
      "ranking.top_demand row metadata is internally inconsistent"
    )
    |> add_if(
      not nonnegative_integer?(ranking["cross_family_pairs"]),
      "ranking.cross_family_pairs must be a non-negative integer"
    )
    |> add_if(
      not nonnegative_integer?(ranking["directed_pairs"]),
      "ranking.directed_pairs must be a non-negative integer"
    )
    |> add_if(
      not nonnegative_integer?(ranking["unresolved_pairs"]),
      "ranking.unresolved_pairs must be a non-negative integer"
    )
    |> add_if(
      not nonnegative_integer?(ranking["conflicting_pairs"]),
      "ranking.conflicting_pairs must be a non-negative integer"
    )
    |> add_if(
      ranking_pair_total(ranking) != ranking["cross_family_pairs"],
      "ranking direction denominators do not sum to cross_family_pairs"
    )
  end

  defp check_ranking(errors, _), do: ["ranking must be an object" | errors]

  defp check_seeds(errors, seeds, ranking) when is_list(seeds) and is_map(ranking) do
    ids = Enum.map(seeds, & &1["work_id"])
    ranked = Map.new(ranking["top_demand"] || [], &{&1["work_id"], &1})
    demand_ids = ranked |> Map.keys() |> MapSet.new()

    errors =
      errors
      |> add_if(ids != Enum.sort(ids), "seeds must be sorted by work_id")
      |> add_if(length(ids) != length(Enum.uniq(ids)), "seed work ids must be unique")
      |> add_if(
        not Enum.all?(@agama_ids, &(&1 in ids)),
        "all four charter Āgamas must be present in seeds"
      )
      |> add_if(
        not MapSet.subset?(demand_ids, MapSet.new(ids)),
        "every demand-ranked work must be present in seeds"
      )

    Enum.reduce(seeds, errors, &check_seed(&1, &2, ranked))
  end

  defp check_seed(seed, errors, ranked) do
    work_id = seed["work_id"]
    expected_sources = expected_seed_sources(work_id, ranked)
    rank_row = Map.get(ranked, work_id)

    errors
    |> add_if(not nonempty?(work_id), "seed work_id is required")
    |> add_if(
      seed["seed_sources"] != expected_sources,
      "seed_sources must exactly match ranking/Āgama membership"
    )
    |> add_if(
      seed["demand_rank"] != demand_value(rank_row, "rank"),
      "seed demand_rank must match ranking.top_demand"
    )
    |> add_if(
      seed["demand_weight"] != demand_value(rank_row, "weight"),
      "seed demand_weight must match ranking.top_demand"
    )
  end

  defp expected_seed_sources(work_id, ranked) do
    []
    |> maybe_source(Map.has_key?(ranked, work_id), "demand_rank")
    |> maybe_source(work_id in @agama_ids, "agama")
    |> Enum.sort()
  end

  defp maybe_source(sources, true, source), do: [source | sources]
  defp maybe_source(sources, false, _source), do: sources

  defp demand_value(nil, _key), do: nil
  defp demand_value(row, key), do: row[key]

  defp check_seeds(errors, _seeds, _ranking), do: ["seeds must be an array" | errors]

  defp check_works(errors, works, seeds) when is_list(works) and is_list(seeds) do
    ids = Enum.map(works, & &1["work_id"])
    declared_seed_ids = MapSet.new(Enum.map(seeds, & &1["work_id"]))

    errors =
      errors
      |> add_if(ids != Enum.sort(ids), "works must be sorted by work_id")
      |> add_if(length(ids) != length(Enum.uniq(ids)), "scope work ids must be unique")
      |> add_if(
        not MapSet.subset?(seed_ids, MapSet.new(ids)),
        "every seed must be present in works"
      )

    Enum.reduce(works, errors, &check_work(&1, &2, seed_ids))
  end

  defp check_work(work, errors, seed_ids) do
    work_id = work["work_id"]
    ancestry = work["seed_ids"] || []
    seed? = MapSet.member?(seed_ids, work_id)

    errors
    |> add_if(not nonempty?(work_id), "work_id is required")
    |> add_if(work["source"] != "cbeta", "scope works must come from CBETA")
    |> add_if(work["witness"] != "T", "scope works must use the Taishō witness")
    |> add_if(
      ancestry != Enum.sort(Enum.uniq(ancestry)),
      "work seed_ids must be sorted and unique"
    )
    |> add_if(
      not Enum.all?(ancestry, &MapSet.member?(seed_ids, &1)),
      "work seed_ids must name declared seeds"
    )
    |> add_if(
      not valid_work_hop_and_ancestry?(work, seed?),
      "work min_hop/seed ancestry is inconsistent with seed membership"
    )
  end

  defp valid_work_hop_and_ancestry?(work, true),
    do: work["min_hop"] == 0 and work["seed_ids"] == [work["work_id"]]

  defp valid_work_hop_and_ancestry?(work, false),
    do:
      is_integer(work["min_hop"]) and
        work["min_hop"] in 1..@max_relation_depth and
        (work["seed_ids"] || []) != []

  defp check_works(errors, _works, _seeds), do: ["works must be an array" | errors]

  defp check_relations(errors, relations, works, seeds)
       when is_list(relations) and is_list(works) and is_list(seeds) do
    work_ids = MapSet.new(Enum.map(works, & &1["work_id"]))
    works_by_id = Map.new(works, &{&1["work_id"], &1})
    seed_ids = MapSet.new(Enum.map(seeds, & &1["work_id"]))
    keys = Enum.map(relations, &relation_key/1)
    pair_keys = Enum.map(relations, &{&1["source_work_id"], &1["target_work_id"]})

    errors =
      errors
      |> add_if(keys != Enum.sort(keys), "relations must use canonical sort order")
      |> add_if(length(keys) != length(Enum.uniq(keys)), "relation edges must be unique")
      |> add_if(
        length(pair_keys) != length(Enum.uniq(pair_keys)),
        "one source/target pair may not carry multiple admitted relation types"
      )

    Enum.reduce(relations, errors, fn relation, acc ->
      assertions = relation["assertions"] || []
      seed_ids = relation["seed_ids"] || []
      assertion_keys = Enum.map(assertions, &assertion_artifact_key/1)

      acc
      |> add_if(
        seed_ids != Enum.sort(Enum.uniq(seed_ids)),
        "relation seed_ids must be sorted and unique"
      )
      |> add_if(seed_ids == [], "relation seed_ids must not be empty")
      |> add_if(
        not Enum.all?(seed_ids, &MapSet.member?(declared_seed_ids, &1)),
        "relation seed_ids must name declared seeds"
      )
      |> add_if(
        not relation_ancestry_matches_target?(relation, works_by_id),
        "relation seed_ids must match target-work ancestry"
      )
      |> add_if(
        assertion_keys != Enum.sort(assertion_keys),
        "relation assertions must use canonical sort order"
      )
      |> add_if(
        length(assertion_keys) != length(Enum.uniq(assertion_keys)),
        "relation assertions must be unique"
      )
      |> add_if(
        relation["relation"] not in @relations,
        "scope relation type is outside the frozen relation set"
      )
      |> add_if(
        not MapSet.member?(work_ids, relation["source_work_id"]) or
          not MapSet.member?(work_ids, relation["target_work_id"]),
        "scope relation endpoint is outside works"
      )
      |> add_if(
        not (is_integer(relation["hop"]) and relation["hop"] in 1..@max_relation_depth),
        "scope relation hop is outside the frozen depth"
      )
      |> add_if(assertions == [], "scope relation must retain at least one assertion")
      |> add_if(
        Enum.any?(assertions, &(&1["method"] not in @relation_methods)),
        "scope relation contains a disallowed assertion method"
      )
      |> add_if(
        Enum.any?(assertions, &(not is_map(&1["evidence"]))),
        "scope relation assertion evidence must be an object"
      )
      |> add_if(
        Enum.any?(assertions, &(not sha256?(&1["evidence_sha256"]))),
        "scope relation assertion evidence digest must be a SHA-256"
      )
      |> add_if(
        Enum.any?(assertions, fn assertion ->
          is_map(assertion["evidence"]) and
            assertion["evidence_sha256"] != digest(assertion["evidence"])
        end),
        "scope relation assertion evidence digest does not match evidence"
      )
    end)
  end

  defp check_relations(errors, _relations, _works, _seeds),
    do: ["relations must be an array" | errors]

  defp relation_ancestry_matches_target?(relation, works_by_id) do
    case Map.get(works_by_id, relation["target_work_id"]) do
      nil -> false
      target -> relation["seed_ids"] == target["seed_ids"]
    end
  end

  defp check_alignments(errors, rows, relations) when is_list(rows) and is_list(relations) do
    relation_keys = MapSet.new(Enum.map(relations, &relation_identity/1))
    keys = Enum.map(rows, &alignment_key/1)

    errors =
      errors
      |> add_if(keys != Enum.sort(keys), "alignment_coverage must use canonical sort order")
      |> add_if(length(keys) != length(Enum.uniq(keys)), "alignment coverage rows must be unique")

    Enum.reduce(rows, errors, fn row, acc ->
      acc
      |> add_if(
        not MapSet.member?(relation_keys, alignment_identity(row)),
        "alignment coverage row has no admitted scope relation"
      )
      |> add_if(
        not Enum.all?(
          ~w(alignment_rows distinct_root_urns distinct_commentary_urns),
          &nonnegative_integer?(row[&1])
        ),
        "alignment counts must be non-negative integers"
      )
      |> add_if(
        row["has_passage_alignment"] != row["alignment_rows"] > 0,
        "has_passage_alignment must match alignment_rows"
      )
      |> add_if(
        row["distinct_root_urns"] > row["alignment_rows"] or
          row["distinct_commentary_urns"] > row["alignment_rows"],
        "alignment distinct counts cannot exceed alignment_rows"
      )
    end)
  end

  defp check_alignments(errors, _rows, _relations),
    do: ["alignment_coverage must be an array" | errors]

  defp check_denominators(errors, artifact) do
    d = artifact["denominators"]

    if is_map(d) do
      seeds = artifact["seeds"] || []
      works = artifact["works"] || []
      relations = artifact["relations"] || []
      alignments = artifact["alignment_coverage"] || []

      role_counts =
        works
        |> Enum.frequencies_by(&(&1["text_role"] || "unknown"))
        |> Map.new(fn {key, value} -> {to_string(key), value} end)

      assertion_count =
        relations
        |> Enum.map(&length(&1["assertions"] || []))
        |> Enum.sum()

      errors
      |> add_if(d["combined_seed_count"] != length(seeds), "combined_seed_count is wrong")
      |> add_if(
        d["demand_seed_count"] != @demand_seed_count,
        "denominators.demand_seed_count is wrong"
      )
      |> add_if(d["agama_required_count"] != length(@agama_ids), "agama_required_count is wrong")
      |> add_if(d["total_work_count"] != length(works), "total_work_count is wrong")
      |> add_if(
        d["expanded_work_count"] != length(works) - length(seeds),
        "expanded_work_count is wrong"
      )
      |> add_if(d["relation_edge_count"] != length(relations), "relation_edge_count is wrong")
      |> add_if(
        d["relation_assertion_count"] != assertion_count,
        "relation_assertion_count is wrong"
      )
      |> add_if(
        d["relation_edges_with_alignment"] !=
          Enum.count(alignments, & &1["has_passage_alignment"]),
        "relation_edges_with_alignment is wrong"
      )
      |> add_if(
        d["alignment_rows"] != Enum.sum(Enum.map(alignments, & &1["alignment_rows"])),
        "alignment_rows denominator is wrong"
      )
      |> add_if(d["works_by_text_role"] != role_counts, "works_by_text_role is wrong")
    else
      ["denominators must be an object" | errors]
    end
  end

  defp check_derivation_status(errors, status) when is_map(status) do
    errors
    |> add_if(
      status["quotation_graph_completeness"] != "not_recorded_by_database",
      "quotation graph completeness must remain explicitly external"
    )
    |> add_if(
      status["relation_graph_completeness"] != "not_recorded_by_database",
      "relation graph completeness must remain explicitly external"
    )
    |> add_if(
      status["alignment_graph_completeness"] != "not_recorded_by_database",
      "alignment graph completeness must remain explicitly external"
    )
    |> add_if(
      status["structural_validation_establishes_live_currentness"] != false,
      "structural validation must not claim live currentness"
    )
    |> add_if(
      status["live_acceptance_requires_external_completion_evidence"] != true,
      "live acceptance must require external derivation completion evidence"
    )
    |> add_if(
      status["live_acceptance_requires_quiesced_repeat_match"] != true,
      "live acceptance must require a quiesced repeated materialization match"
    )
  end

  defp check_derivation_status(errors, _),
    do: ["derivation_status must be an object" | errors]

  defp check_input_digests(errors, digests) when is_map(digests) do
    required = ~w(work_metadata quotation_graph relation_graph alignment_graph)

    Enum.reduce(required, errors, fn key, acc ->
      add_if(acc, not sha256?(digests[key]), "input_digests.#{key} must be a SHA-256")
    end)
  end

  defp check_input_digests(errors, _), do: ["input_digests must be an object" | errors]

  defp sorted_unique_rank?(rows) do
    ranks = Enum.map(rows, & &1["rank"])
    ranks == Enum.to_list(1..@demand_seed_count)
  end

  defp ranking_pair_total(ranking) do
    (ranking["directed_pairs"] || 0) +
      (ranking["unresolved_pairs"] || 0) +
      (ranking["conflicting_pairs"] || 0)
  end

  defp valid_direction_method_counts?(counts, directed_pairs) when is_map(counts) do
    allowed = ~w(role date role_and_date)
    keys = Map.keys(counts)

    Enum.all?(keys, &(&1 in allowed)) and
      Enum.all?(Map.values(counts), &nonnegative_integer?/1) and
      Enum.sum(Map.values(counts)) == directed_pairs
  end

  defp valid_direction_method_counts?(_counts, _directed_pairs), do: false

  defp valid_top_demand_row?(row) do
    methods = row["direction_methods"]
    members = row["family_members"] || []

    nonempty?(row["work_id"]) and
      nonempty?(row["family"]) and
      positive_integer?(row["citing_families"]) and
      positive_integer?(row["directed_pair_count"]) and
      row["citing_families"] <= row["directed_pair_count"] and
      row["weight"] >= row["citing_families"] and
      members == Enum.sort(Enum.uniq(members)) and
      row["work_id"] in members and
      valid_direction_method_counts?(methods, row["directed_pair_count"])
  end

  defp assertion_artifact_key(assertion) do
    {
      assertion["method"] || "",
      assertion["confidence"] || "",
      assertion["scope"] || "",
      assertion["target_urn"] || "",
      assertion["evidence_sha256"] || ""
    }
  end

  defp relation_key(row),
    do: {row["hop"], row["target_work_id"], row["source_work_id"], row["relation"]}

  defp relation_identity(row),
    do: {row["source_work_id"], row["target_work_id"], row["relation"]}

  defp alignment_key(row),
    do: {row["target_work_id"], row["commentary_work_id"], row["relation"]}

  defp alignment_identity(row),
    do: {row["commentary_work_id"], row["target_work_id"], row["relation"]}

  defp v2_component?(value), do: is_binary(value) and String.starts_with?(value, "v2:")

  defp sha256?(value),
    do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{64}\z/, value)

  defp nonempty?(value), do: is_binary(value) and String.trim(value) != ""
  defp nonnegative_integer?(value), do: is_integer(value) and value >= 0
  defp positive_integer?(value), do: is_integer(value) and value > 0

  defp canonical_json(map) when is_map(map) and not is_struct(map) do
    body =
      map
      |> Enum.map(fn {key, value} -> {to_string(key), value} end)
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map_join(",", fn {key, value} ->
        json_scalar(key) <> ":" <> canonical_json(value)
      end)

    "{" <> body <> "}"
  end

  defp canonical_json(list) when is_list(list) do
    "[" <> Enum.map_join(list, ",", &canonical_json/1) <> "]"
  end

  defp canonical_json(nil), do: "null"
  defp canonical_json(value), do: json_scalar(value)

  defp json_scalar(nil), do: "null"
  defp json_scalar(value), do: value |> encode_json_scalar() |> IO.iodata_to_binary()

  defp encode_json_scalar(value) when is_atom(value) and value not in [true, false],
    do: :json.encode(Atom.to_string(value))

  defp encode_json_scalar(value), do: :json.encode(value)

  defp normalize_json(:null), do: nil

  defp normalize_json(value) when is_map(value) do
    Map.new(value, fn {key, item} -> {key, normalize_json(item)} end)
  end

  defp normalize_json(value) when is_list(value), do: Enum.map(value, &normalize_json/1)
  defp normalize_json(value), do: value

  defp add_if(errors, true, message), do: [message | errors]
  defp add_if(errors, false, _message), do: errors
end
