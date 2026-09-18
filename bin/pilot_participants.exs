defmodule Pramana.PilotParticipants do
  @moduledoc false

  @schema "pramana-pilot-participants/v1"
  @pilot_id "chinese-commentary-v1"
  @revision 1
  @status "frozen_pre_recruitment"

  @required_disclosures ~w(
    research_feasibility_pilot_not_spiritual_direction
    bounded_chinese_corpus_scope_and_known_coverage_limits
    chinese_source_is_authoritative_and_generated_english_is_not_source_evidence
    model_or_provider_identity_and_data_boundary_when_applicable
    what_full_task_data_will_be_retained_for_study
    retention_and_deletion_deadline
    withdrawal_and_task_exclusion_process
    evidence_export_is_user_controlled
    public_example_sharing_requires_separate_optional_consent
    no_penalty_for_skipping_or_withdrawing
    repeat_use_signal_is_unprompted
  )

  @required_consents ~w(
    participate_in_feasibility_study
    retain_full_task_record_for_evaluation
    qualified_evaluator_review_of_task_record
    current_alternative_intake
  )

  @prohibited_collection ~w(
    passwords_or_api_keys
    payment_information
    government_identifiers
    audio_recording
    video_recording
    screen_recording
    precise_location
    unrelated_contact_lists
    private_notes_outside_the_declared_task_record
  )

  @required_task_fields ~w(
    protocol_revision
    participant_id
    task_id
    audience_stratum
    task_class
    question_text
    submitted_at
    declared_scope_identity
    system_release_identity
    query_plan_receipt
    retrieval_receipt
    selected_evidence_ids
    generated_answer
    rendering_metadata
    outcome_state
    failure_category
    time_to_useful_evidence_ms
    commentary_eligible
    commentary_opened
    evidence_packet_trace_result
    comprehension_check
    consent_receipt_id
  )

  @included_outcomes ~w(
    success_supported
    success_scoped_unsupported
    failure_retrieval_miss
    failure_wrong_evidence
    failure_comprehension
    failure_timeout
    failure_technical
    abandoned_after_start
  )

  @excluded_outcomes ~w(
    withdrawn_from_study
    private_excluded_by_participant
    protocol_invalid_before_start
    rehearsal_or_training_case
    duplicate_task_not_independently_attempted
  )

  @alternative_categories ~w(
    web_search
    canon_or_archive_search
    general_chat_model
    specialist_buddhist_tool
    books_or_manual_research
    teacher_or_study_community
    other
    none
  )

  @expected_top_level ~w(
    schema
    pilot_id
    protocol_revision
    status
    collection_mode
    identifiers
    eligibility
    required_disclosures
    required_consents
    optional_consents
    consent_receipt
    prohibited_collection
    study_record
    current_alternative
    sensitive_content
    retention
    purpose_boundaries
    evidence_export
    evaluator_separation
    task_denominator
    withdrawal
    public_sharing
    incident_response
    regulatory_boundary
  )

  @spec load_manifest!(String.t()) :: map()
  def load_manifest!(path) do
    path
    |> File.read!()
    |> :json.decode()
    |> normalize_json()
  end

  @spec default_manifest(String.t()) :: String.t()
  def default_manifest(root), do: Path.join(root, "docs/strategy/pilot_participants.json")

  @spec validate(map(), String.t()) :: :ok | {:error, [String.t()]}
  def validate(manifest, root) when is_map(manifest) do
    errors =
      []
      |> check_top_level(manifest)
      |> check_identifiers(manifest["identifiers"])
      |> check_eligibility(manifest["eligibility"])
      |> check_exact("required_disclosures", manifest["required_disclosures"], @required_disclosures)
      |> check_exact("required_consents", manifest["required_consents"], @required_consents)
      |> check_optional_consents(manifest["optional_consents"])
      |> check_consent_receipt(manifest["consent_receipt"])
      |> check_exact("prohibited_collection", manifest["prohibited_collection"], @prohibited_collection)
      |> check_study_record(manifest["study_record"])
      |> check_current_alternative(manifest["current_alternative"])
      |> check_sensitive_content(manifest["sensitive_content"])
      |> check_retention(manifest["retention"])
      |> check_purpose_boundaries(manifest["purpose_boundaries"])
      |> check_evidence_export(manifest["evidence_export"])
      |> check_evaluator_separation(manifest["evaluator_separation"])
      |> check_task_denominator(manifest["task_denominator"])
      |> check_withdrawal(manifest["withdrawal"])
      |> check_public_sharing(manifest["public_sharing"])
      |> check_incident_response(manifest["incident_response"])
      |> check_regulatory_boundary(manifest["regulatory_boundary"])
      |> check_document(root)
      |> check_preflight_alignment(root)

    case Enum.reverse(errors) do
      [] -> :ok
      found -> {:error, found}
    end
  end

  def validate(_manifest, _root), do: {:error, ["participant manifest must be an object"]}

  @spec revision(map()) :: integer() | nil
  def revision(manifest), do: manifest["protocol_revision"]

  @spec status(map()) :: String.t() | nil
  def status(manifest), do: manifest["status"]

  defp check_top_level(errors, manifest) do
    actual = manifest |> Map.keys() |> MapSet.new()
    expected = MapSet.new(@expected_top_level)

    errors
    |> add_if(manifest["schema"] != @schema, "schema must be #{@schema}")
    |> add_if(manifest["pilot_id"] != @pilot_id, "pilot_id must be #{@pilot_id}")
    |> add_if(manifest["protocol_revision"] != @revision, "protocol_revision must be #{@revision}")
    |> add_if(manifest["status"] != @status, "status must be #{@status}")
    |> add_if(
      manifest["collection_mode"] != "consent_required_for_measured_participant_record",
      "collection_mode must require consent for a measured participant record"
    )
    |> add_if(
      MapSet.difference(actual, expected) != MapSet.new(),
      "participant manifest contains unknown top-level fields"
    )
    |> add_if(
      MapSet.difference(expected, actual) != MapSet.new(),
      "participant manifest is missing required top-level fields"
    )
  end

  defp check_identifiers(errors, ids) when is_map(ids) do
    errors
    |> add_if(ids["participant_id"] != "random_pseudonymous_id", "participant_id policy changed")
    |> add_if(ids["task_id"] != "random_id", "task_id policy changed")
    |> add_if(ids["evaluator_id"] != "random_pseudonymous_id", "evaluator_id policy changed")
    |> add_if(
      ids["consent_receipt_id"] != "random_pseudonymous_id",
      "consent_receipt_id policy changed"
    )
    |> require_false(ids, "consent_receipt_contains_direct_identity")
    |> require_false(ids, "direct_identity_in_study_dataset")
    |> require_false(ids, "account_credentials_collected")
    |> require_false(ids, "cross_dataset_reidentification_key_in_study_dataset")
  end

  defp check_identifiers(errors, _), do: ["identifiers must be an object" | errors]

  defp check_eligibility(errors, value) when is_map(value) do
    errors
    |> add_if(value["minimum_age"] != 18, "pilot v1 minimum age must remain 18")
    |> require_true(value, "age_attestation_only")
    |> require_false(value, "date_of_birth_collected")
    |> require_false(value, "minors_in_pilot_v1")
  end

  defp check_eligibility(errors, _), do: ["eligibility must be an object" | errors]

  defp check_optional_consents(errors, consents) when is_map(consents) do
    errors
    |> require_false(consents, "public_anonymized_example_sharing")
    |> require_false(consents, "quote_participant_feedback_publicly")
    |> require_false(consents, "followup_logistics_contact")
  end

  defp check_optional_consents(errors, _), do: ["optional_consents must be an object" | errors]

  defp check_consent_receipt(errors, value) when is_map(value) do
    errors
    |> check_exact(
      "consent_receipt.required_fields",
      value["required_fields"],
      [
        "consent_receipt_id",
        "participant_id",
        "protocol_revision",
        "consented_at",
        "required_consent_values",
        "optional_consent_values",
        "age_18_or_older_attestation"
      ]
    )
    |> require_false(value, "direct_identity_fields_allowed")
    |> require_true(value, "contact_or_identity_roster_separate")
  end

  defp check_consent_receipt(errors, _), do: ["consent_receipt must be an object" | errors]

  defp check_study_record(errors, record) when is_map(record) do
    errors
    |> check_exact("study_record.required_fields", record["required_fields"], @required_task_fields)
    |> check_exact(
      "study_record.optional_fields",
      record["optional_fields"],
      [
        "participant_feedback",
        "current_alternative_optional_note",
        "study_evidence_packet_copy_if_rights_permit"
      ]
    )
    |> check_exact(
      "study_record.excluded_fields",
      record["excluded_fields"],
      [
        "participant_name",
        "participant_email",
        "participant_phone",
        "account_credentials",
        "freeform_private_notes_not_part_of_task"
      ]
    )
  end

  defp check_study_record(errors, _), do: ["study_record must be an object" | errors]

  defp check_current_alternative(errors, value) when is_map(value) do
    errors
    |> require_true(value, "required")
    |> check_exact(
      "current_alternative.multi_select_categories",
      value["multi_select_categories"],
      @alternative_categories
    )
    |> check_exact(
      "current_alternative.required_fields",
      value["required_fields"],
      ["categories", "frequency_bucket", "usual_time_bucket", "main_friction_category"]
    )
    |> add_if(
      value["optional_free_text_max_chars"] != 500,
      "current alternative free-text cap must be 500 characters"
    )
    |> require_true(value, "credentials_or_account_details_forbidden")
  end

  defp check_current_alternative(errors, _),
    do: ["current_alternative must be an object" | errors]

  defp check_sensitive_content(errors, value) when is_map(value) do
    errors
    |> require_true(value, "pre_task_warning")
    |> add_if(
      value["instruction"] !=
        "do_not_submit_secrets_credentials_or_unnecessary_highly_personal_information",
      "sensitive-content instruction changed"
    )
    |> require_true(value, "participant_can_mark_task_private_exclude")
    |> add_if(
      value["accidental_sensitive_content_action"] !=
        "stop_research_use_and_delete_full_content_promptly",
      "accidental-sensitive-content action changed"
    )
    |> require_true(value, "minimal_incident_metadata_may_remain_without_content")
    |> require_true(value, "spiritual_or_personal_question_alone_is_not_permission_for_secondary_use")
  end

  defp check_sensitive_content(errors, _),
    do: ["sensitive_content must be an object" | errors]

  defp check_retention(errors, value) when is_map(value) do
    errors
    |> add_if(
      value["full_task_record_delete_days_after_pilot_decision_max"] != 30,
      "post-decision full-task deletion cap must be 30 days"
    )
    |> add_if(
      value["full_task_record_delete_days_after_collection_max"] != 90,
      "post-collection full-task deletion cap must be 90 days"
    )
    |> add_if(
      value["effective_full_task_deadline"] != "earlier_of_the_two_limits",
      "full-task deadline must use the earlier deletion cap"
    )
    |> add_if(
      value["followup_contact_delete_days_after_observation_window_max"] != 7,
      "follow-up contact deletion cap must be 7 days"
    )
    |> add_if(
      value["followup_contact_purpose"] != "logistics_only_not_repeat_use_prompting",
      "follow-up contact purpose must remain logistics-only and unprompted"
    )
    |> add_if(value["withdrawal_delete_days_max"] != 7, "withdrawal deletion cap must be 7 days")
    |> require_false(value, "per_task_content_after_deadline")
    |> require_false(value, "pseudonymous_individual_metadata_after_deadline")
    |> require_true(value, "aggregate_non_reconstructive_metrics_may_remain")
    |> require_true(value, "public_example_content_requires_optional_consent")
  end

  defp check_retention(errors, _), do: ["retention must be an object" | errors]

  defp check_purpose_boundaries(errors, value) when is_map(value) do
    errors
    |> require_true(value, "operational_noncontent_telemetry_not_study_consent")
    |> require_true(value, "study_record_not_model_training_data")
    |> require_true(value, "study_record_not_canonical_corpus_data")
    |> require_true(value, "study_record_not_foundry_memory")
    |> require_true(value, "evaluator_record_not_participant_identity_record")
    |> require_true(value, "no_secondary_use_without_new_consent")
  end

  defp check_purpose_boundaries(errors, _),
    do: ["purpose_boundaries must be an object" | errors]

  defp check_evidence_export(errors, value) when is_map(value) do
    errors
    |> require_true(value, "participant_controls_export")
    |> require_false(value, "server_copy_required")
    |> require_false(value, "study_copy_default")
    |> add_if(
      value["study_copy_requires"] != "study_consent_and_source_rights",
      "study evidence-packet copy must require consent and source rights"
    )
    |> check_exact(
      "evidence_export.retained_trace_fields",
      value["retained_trace_fields"],
      ["packet_hash", "source_ids", "traceability_result", "rights_disposition"]
    )
  end

  defp check_evidence_export(errors, _), do: ["evidence_export must be an object" | errors]

  defp check_evaluator_separation(errors, value) when is_map(value) do
    errors
    |> require_true(value, "evaluator_id_separate_from_participant_id")
    |> require_true(value, "qualified_source_judgment_requires_independent_evaluator")
    |> require_true(value, "participant_may_also_be_evaluator_pool_member")
    |> require_true(value, "participant_cannot_supply_independent_source_judgment_for_own_task")
    |> require_true(value, "disagreements_preserved")
    |> require_true(value, "adjudication_recorded")
  end

  defp check_evaluator_separation(errors, _),
    do: ["evaluator_separation must be an object" | errors]

  defp check_task_denominator(errors, value) when is_map(value) do
    errors
    |> require_true(value, "eligibility_decided_without_using_system_success")
    |> add_if(
      value["start_boundary"] != "participant_submits_consented_natural_task",
      "task denominator start boundary changed"
    )
    |> check_exact("task_denominator.included_outcomes", value["included_outcomes"], @included_outcomes)
    |> check_exact("task_denominator.excluded_outcomes", value["excluded_outcomes"], @excluded_outcomes)
    |> require_true(value, "supported_retrieval_miss_counts_as_failure")
    |> require_true(value, "correctly_scoped_unsupported_can_count_as_success")
    |> require_true(value, "timeout_or_technical_failure_counts_as_failure")
    |> require_true(value, "abandonment_after_start_counts_as_failure")
    |> require_true(value, "exclusions_reported_separately")
    |> require_true(value, "participant_exclusion_may_be_initiated_by_participant")
    |> require_true(value, "operator_or_evaluator_may_not_prompt_exclusion_based_on_outcome")
    |> require_true(value, "all_exclusions_counted_and_reported")
    |> add_if(value["minimum_eligible_tasks_after_exclusions"] != 24, "eligible-task floor must be 24")
    |> add_if(
      value["minimum_eligible_tasks_per_stratum_after_exclusions"] != 6,
      "per-stratum eligible-task floor must be 6"
    )
    |> add_if(
      value["minimum_commentary_eligible_tasks_after_exclusions"] != 6,
      "commentary-eligible task floor must be 6"
    )
    |> require_true(value, "replenish_after_withdrawal_or_exclusion")
  end

  defp check_task_denominator(errors, _), do: ["task_denominator must be an object" | errors]

  defp check_withdrawal(errors, value) when is_map(value) do
    errors
    |> add_if(
      value["allowed_until"] != "pilot_decision_recorded",
      "withdrawal window must remain open until the pilot decision"
    )
    |> require_true(value, "no_penalty")
    |> require_true(value, "stop_new_research_use_immediately")
    |> add_if(
      value["individual_records_delete_days_max"] != 7,
      "withdrawal individual-record deletion cap must be 7 days"
    )
    |> require_true(value, "remove_from_participant_denominators")
    |> require_true(value, "recompute_predecision_aggregates")
    |> require_true(value, "previously_published_or_merged_non_reconstructive_aggregate_record_may_remain")
    |> require_true(value, "no_new_public_example_use_after_withdrawal")
  end

  defp check_withdrawal(errors, _), do: ["withdrawal must be an object" | errors]

  defp check_public_sharing(errors, value) when is_map(value) do
    errors
    |> require_false(value, "default")
    |> require_true(value, "aggregate_results_allowed_without_task_content")
    |> require_true(value, "small_cohort_reidentification_review_required")
    |> require_true(value, "individual_question_answer_or_feedback_requires_optional_consent")
    |> require_true(value, "source_text_still_subject_to_source_rights")
  end

  defp check_public_sharing(errors, _), do: ["public_sharing must be an object" | errors]

  defp check_incident_response(errors, value) when is_map(value) do
    errors
    |> check_exact(
      "incident_response.triggers",
      value["triggers"],
      [
        "unauthorized_retention",
        "unauthorized_disclosure",
        "secondary_use_without_consent",
        "sensitive_content_retained_against_protocol",
        "identity_linkage_leak",
        "rights_restricted_packet_retained_or_shared"
      ]
    )
    |> check_exact(
      "incident_response.actions",
      value["actions"],
      [
        "stop_affected_processing",
        "contain_access",
        "delete_or_quarantine_as_required",
        "record_noncontent_incident_receipt",
        "notify_operator_and_affected_participant_when_appropriate",
        "resolve_before_resuming_affected_study_path"
      ]
    )
    |> add_if(
      value["critical_failure_mapping"] != "CF11_privacy_or_retention_violation",
      "privacy incident must map to CF11"
    )
  end

  defp check_incident_response(errors, _),
    do: ["incident_response must be an object" | errors]

  defp check_regulatory_boundary(errors, value) when is_map(value) do
    errors
    |> require_true(value, "protocol_is_not_irb_or_regulatory_determination")
    |> require_true(value, "institution_must_obtain_applicable_review_or_approval")
    |> require_true(value, "this_protocol_authorizes_no_compensation_or_recruitment_spend")
  end

  defp check_regulatory_boundary(errors, _),
    do: ["regulatory_boundary must be an object" | errors]

  defp check_document(errors, root) do
    path = Path.join(root, "docs/strategy/PILOT_PARTICIPANTS.md")

    case File.read(path) do
      {:ok, document} ->
        required = [
          "# 1. Consent before collection",
          "# 6. Retention and deletion",
          "# 9. Evaluator separation",
          "# 10. Task outcomes and denominator rules",
          "# 11. Withdrawal",
          "# 13. Incident handling",
          "# 14. Preflight disposition"
        ]

        Enum.reduce(required, errors, fn heading, acc ->
          add_if(acc, not String.contains?(document, heading), "participant protocol missing #{heading}")
        end)

      {:error, reason} ->
        ["cannot read PILOT_PARTICIPANTS.md: #{inspect(reason)}" | errors]
    end
  end

  defp check_preflight_alignment(errors, root) do
    path = Path.join(root, "docs/strategy/pilot_preflight.json")

    case File.read(path) do
      {:ok, bytes} ->
        preflight = bytes |> :json.decode() |> normalize_json()
        gates = Map.new(preflight["gates"] || [], &{&1["id"], &1})
        gate = gates["participant_protocol"] || %{}
        evidence = gate["evidence"] || []

        errors
        |> add_if(gate["state"] != "ready", "participant_protocol preflight gate must be ready")
        |> add_if(
          gate["reason"] not in [nil, ""],
          "ready participant_protocol gate must not carry a blocking reason"
        )
        |> add_if(
          "docs/strategy/PILOT_PARTICIPANTS.md" not in evidence,
          "participant_protocol gate must cite PILOT_PARTICIPANTS.md"
        )
        |> add_if(
          "docs/strategy/pilot_participants.json" not in evidence,
          "participant_protocol gate must cite pilot_participants.json"
        )

      {:error, reason} ->
        ["cannot read pilot_preflight.json: #{inspect(reason)}" | errors]
    end
  end

  defp check_exact(errors, name, actual, expected) do
    add_if(errors, actual != expected, "#{name} does not match the frozen v1 protocol")
  end

  defp require_true(errors, map, key),
    do: add_if(errors, map[key] != true, "#{key} must remain true")

  defp require_false(errors, map, key),
    do: add_if(errors, map[key] != false, "#{key} must remain false")

  defp normalize_json(:null), do: nil

  defp normalize_json(value) when is_map(value) do
    Map.new(value, fn {key, item} -> {key, normalize_json(item)} end)
  end

  defp normalize_json(value) when is_list(value), do: Enum.map(value, &normalize_json/1)
  defp normalize_json(value), do: value

  defp add_if(errors, true, message), do: [message | errors]
  defp add_if(errors, false, _message), do: errors
end
