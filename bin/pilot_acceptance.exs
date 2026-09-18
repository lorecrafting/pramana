defmodule Pramana.PilotAcceptance do
  @moduledoc false

  @schema "pramana-pilot-acceptance/v1"
  @pilot_id "chinese-commentary-v1"
  @revision 1
  @status "frozen_pre_execution"

  @expected_bounds %{
    "concepts_max" => 3,
    "deterministic_candidates_planned_max" => 12,
    "deterministic_candidates_retrieval_active_max" => 8,
    "related_candidates_retrieval_active_max" => 3,
    "model_proposed_candidates_max" => 4,
    "model_query_proposal_calls_max" => 1,
    "lexical_results_per_query_max" => 20,
    "semantic_results_per_query_max" => 20,
    "lexical_candidate_depth_max" => 60,
    "semantic_candidate_depth_max" => 120,
    "original_english_multilingual_queries_max" => 1,
    "existing_english_index_queries_max" => 1,
    "fused_results_max" => 20,
    "relation_hops_max" => 2,
    "related_works_per_task_max" => 8,
    "synthesis_source_passages_max" => 8,
    "translated_unique_passages_max" => 6,
    "source_characters_per_translation_max" => 1200,
    "source_characters_translated_per_task_max" => 6000,
    "source_utf8_bytes_per_translation_max" => 4800,
    "source_utf8_bytes_translated_per_task_max" => 24000,
    "glossary_pins_per_translation_max" => 12,
    "model_calls_total_max" => 8,
    "model_calls_translation_max" => 6,
    "model_calls_synthesis_max" => 1,
    "automatic_retries_max" => 0,
    "model_call_timeout_seconds" => 60,
    "automated_task_timeout_seconds" => 300,
    "cash_spend_usd_max" => 0
  }

  @expected_rules %{
    "duplicate_source_hash_translation" =>
      "reuse_existing_result_or_refuse; never issue another translation call inside the same task attempt",
    "candidate_deduplication" => "normalized identical retrieval queries execute once",
    "overflow" =>
      "stop the affected stage and report bound_exceeded; never truncate silently into a success claim",
    "retry" =>
      "no automatic retry; an explicit later retry is a new attempt with its own receipt and bounds",
    "provider_tokens" =>
      "record tokenizer-specific input/output token counts when a provider/model is eventually authorized; the UTF-8 source-byte caps remain authoritative",
    "provider_authority" => "this contract authorizes no provider/model/spend route"
  }

  @expected_query_classes ~w(
    explicit_equivalent
    attested_gloss
    historical_rendering
    orthographic_variant
    transliteration
    broader_narrower
    related
    model_proposed
  )

  @expected_translation_dimensions ~w(
    propositional_fidelity
    omission_addition
    negation_modality
    technical_terms
    names_referents
    readability
  )

  @expected_support_classes ~w(
    direct_source_support
    independent_treatise_support
    commentarial_interpretation
    synthesis_across_sources
    unresolved_or_insufficient
  )

  @expected_roles ~w(root treatise commentary subcommentary)

  @expected_evaluation %{
    "retrieval_ranks" => [1, 5, 10],
    "retrieval_primary_metric" => "evaluator-approved evidence recall_at_10",
    "retrieval_required_breakdowns" => [
      "arm",
      "fused",
      "task_class",
      "text_role",
      "supported_vs_out_of_scope"
    ],
    "query_expansion_classes" => @expected_query_classes,
    "translation_scale" => %{
      "min" => 0,
      "max" => 2,
      "dimensions" => @expected_translation_dimensions,
      "passing_total_min" => 9,
      "zero_dimension_allowed" => false
    },
    "answer_support_classes" => @expected_support_classes,
    "role_separated_translation_reporting" => @expected_roles,
    "critical_failure_override" => true,
    "query_expansion_verified_surface_accuracy_required" => 1.0,
    "query_expansion_verified_surface_allowed_outcomes" => [
      "correct_as_declared",
      "correct_only_with_narrower_scope_preserved"
    ]
  }

  @critical_ids ~w(
    CF01_false_verification
    CF02_wrong_source_identity
    CF03_rendering_source_conflation
    CF04_wrong_text_role
    CF05_fabricated_exegetical_relation
    CF06_query_equivalence_overclaim
    CF07_material_translation_distortion
    CF08_unsupported_claim_as_supported
    CF09_rights_or_data_boundary_violation
    CF10_evidence_export_violation
    CF11_privacy_or_retention_violation
    CF12_execution_or_spend_bound_violation
    CF13_false_absence_or_exhaustiveness_claim
    CF14_provenance_or_traceability_loss
  )

  @rehearsal_ids ~w(
    R01_exact_attested_term
    R02_historical_rendering_scope
    R03_related_not_equivalent_trap
    R04_root_with_aligned_commentary
    R05_treatise_commentary_subcommentary
    R06_no_human_english
    R07_unsupported_or_out_of_scope
    R08_multiple_legitimate_passages
    R09_false_verification_injection
    R10_generated_human_source_conflation_injection
    R11_fabricated_relation_injection
    R12_rights_export_boundary
    R13_duplicate_hash_and_retry
    R14_candidate_explosion_bound
    R15_timeout_or_unavailable_inference
  )

  @expected_rehearsal %{
    "case_ids" => @rehearsal_ids,
    "all_mechanical_cases_must_pass" => true,
    "all_injected_critical_failures_must_be_detected" => true,
    "live_provider_calls_allowed" => false,
    "counts_toward_participant_pilot" => false,
    "trust_gate_requires_actual_execution" => true
  }

  @spec load_manifest!(String.t()) :: map()
  def load_manifest!(path) do
    path
    |> File.read!()
    |> :json.decode()
    |> normalize_json()
  end

  @spec default_manifest(String.t()) :: String.t()
  def default_manifest(root), do: Path.join(root, "docs/strategy/pilot_acceptance.json")

  @spec validate(map(), String.t()) :: :ok | {:error, [String.t()]}
  def validate(manifest, root) when is_map(manifest) do
    errors =
      []
      |> check_top_level(manifest)
      |> check_exact("execution_bounds", manifest["execution_bounds"], @expected_bounds)
      |> check_exact("execution_rules", manifest["execution_rules"], @expected_rules)
      |> check_exact("evaluation", manifest["evaluation"], @expected_evaluation)
      |> check_exact("critical_failure_ids", manifest["critical_failure_ids"], @critical_ids)
      |> check_exact("rehearsal", manifest["rehearsal"], @expected_rehearsal)
      |> check_document_ids(root)
      |> check_preflight_alignment(root)

    case Enum.reverse(errors) do
      [] -> :ok
      found -> {:error, found}
    end
  end

  def validate(_manifest, _root), do: {:error, ["acceptance manifest must be an object"]}

  @spec revision(map()) :: integer() | nil
  def revision(manifest), do: manifest["contract_revision"]

  @spec status(map()) :: String.t() | nil
  def status(manifest), do: manifest["status"]

  defp check_top_level(errors, manifest) do
    expected =
      MapSet.new(~w(
        schema
        pilot_id
        contract_revision
        status
        execution_bounds
        execution_rules
        evaluation
        critical_failure_ids
        rehearsal
      ))

    actual = manifest |> Map.keys() |> MapSet.new()

    errors
    |> add_if(manifest["schema"] != @schema, "schema must be #{@schema}")
    |> add_if(manifest["pilot_id"] != @pilot_id, "pilot_id must be #{@pilot_id}")
    |> add_if(
      manifest["contract_revision"] != @revision,
      "contract_revision must be #{@revision}"
    )
    |> add_if(manifest["status"] != @status, "status must be #{@status}")
    |> add_if(
      MapSet.difference(actual, expected) != MapSet.new(),
      "acceptance manifest contains unknown top-level fields"
    )
    |> add_if(
      MapSet.difference(expected, actual) != MapSet.new(),
      "acceptance manifest is missing required top-level fields"
    )
  end

  defp check_exact(errors, name, actual, expected) do
    add_if(errors, actual != expected, "#{name} does not match the frozen v1 contract")
  end

  defp check_document_ids(errors, root) do
    path = Path.join(root, "docs/strategy/PILOT_ACCEPTANCE.md")

    case File.read(path) do
      {:ok, document} ->
        errors
        |> require_ids_once(document, @critical_ids, "critical")
        |> require_ids_once(document, @rehearsal_ids, "rehearsal")

      {:error, reason} ->
        ["cannot read PILOT_ACCEPTANCE.md: #{inspect(reason)}" | errors]
    end
  end

  defp require_ids_once(errors, document, ids, kind) do
    Enum.reduce(ids, errors, fn id, acc ->
      short = id |> String.split("_", parts: 2) |> hd()
      marker = "| #{short} |"
      count = length(:binary.matches(document, marker))

      add_if(
        acc,
        count != 1,
        "#{kind} id #{short} must appear exactly once in PILOT_ACCEPTANCE.md (found #{count})"
      )
    end)
  end

  defp check_preflight_alignment(errors, root) do
    path = Path.join(root, "docs/strategy/pilot_preflight.json")

    case File.read(path) do
      {:ok, bytes} ->
        preflight = bytes |> :json.decode() |> normalize_json()
        gates = Map.new(preflight["gates"] || [], &{&1["id"], &1})

        errors
        |> require_gate(gates, "execution_bounds", "ready")
        |> require_gate(gates, "evaluation_rubric", "ready")
        |> require_gate(gates, "critical_taxonomy", "ready")
        |> require_gate(gates, "rehearsal_trust", "blocked")
        |> require_acceptance_evidence(gates, "execution_bounds")
        |> require_acceptance_evidence(gates, "evaluation_rubric")
        |> require_acceptance_evidence(gates, "critical_taxonomy")
        |> require_acceptance_evidence(gates, "rehearsal_trust")

      {:error, reason} ->
        ["cannot read pilot_preflight.json: #{inspect(reason)}" | errors]
    end
  end

  defp require_gate(errors, gates, id, state) do
    actual = get_in(gates, [id, "state"])
    add_if(
      errors,
      actual != state,
      "preflight gate #{id} must be #{state}, got #{inspect(actual)}"
    )
  end

  defp require_acceptance_evidence(errors, gates, id) do
    evidence = get_in(gates, [id, "evidence"]) || []

    required = [
      "docs/strategy/PILOT_ACCEPTANCE.md",
      "docs/strategy/pilot_acceptance.json"
    ]

    missing = required -- evidence

    add_if(
      errors,
      missing != [],
      "preflight gate #{id} is missing acceptance evidence #{inspect(missing)}"
    )
  end

  defp normalize_json(:null), do: nil

  defp normalize_json(value) when is_map(value) do
    Map.new(value, fn {key, item} -> {key, normalize_json(item)} end)
  end

  defp normalize_json(value) when is_list(value), do: Enum.map(value, &normalize_json/1)
  defp normalize_json(value), do: value

  defp add_if(errors, true, message), do: [message | errors]
  defp add_if(errors, false, _message), do: errors
end
