defmodule Strategy.PilotParticipantsTest do
  use ExUnit.Case, async: true

  @root Path.expand("..", __DIR__)
  @manifest Path.join(@root, "docs/strategy/pilot_participants.json")

  test "current participant protocol is structurally valid and frozen" do
    manifest = Pramana.PilotParticipants.load_manifest!(@manifest)

    assert :ok = Pramana.PilotParticipants.validate(manifest, @root)
    assert Pramana.PilotParticipants.revision(manifest) == 1
    assert Pramana.PilotParticipants.status(manifest) == "frozen_pre_recruitment"
  end

  test "retention and withdrawal limits cannot silently loosen" do
    manifest = Pramana.PilotParticipants.load_manifest!(@manifest)

    changed =
      put_in(
        manifest,
        ["retention", "full_task_record_delete_days_after_collection_max"],
        365
      )

    assert {:error, errors} = Pramana.PilotParticipants.validate(changed, @root)
    assert "post-collection full-task deletion cap must be 90 days" in errors

    changed = put_in(manifest, ["withdrawal", "individual_records_delete_days_max"], 30)

    assert {:error, errors} = Pramana.PilotParticipants.validate(changed, @root)
    assert "withdrawal individual-record deletion cap must be 7 days" in errors
  end

  test "public example sharing and provider-independent study boundaries default closed" do
    manifest = Pramana.PilotParticipants.load_manifest!(@manifest)

    assert manifest["optional_consents"]["public_anonymized_example_sharing"] == false
    assert manifest["optional_consents"]["quote_participant_feedback_publicly"] == false
    assert manifest["purpose_boundaries"]["study_record_not_model_training_data"]
    assert manifest["purpose_boundaries"]["study_record_not_foundry_memory"]
    assert manifest["public_sharing"]["default"] == false
  end

  test "outcome denominator keeps failures visible and cannot prune after system failure" do
    manifest = Pramana.PilotParticipants.load_manifest!(@manifest)
    denominator = manifest["task_denominator"]

    assert denominator["eligibility_decided_without_using_system_success"]
    assert denominator["supported_retrieval_miss_counts_as_failure"]
    assert denominator["timeout_or_technical_failure_counts_as_failure"]
    assert denominator["abandonment_after_start_counts_as_failure"]
    assert denominator["minimum_eligible_tasks_after_exclusions"] == 24
    assert denominator["minimum_eligible_tasks_per_stratum_after_exclusions"] == 6
    assert denominator["minimum_commentary_eligible_tasks_after_exclusions"] == 6

    for outcome <- ["failure_retrieval_miss", "failure_timeout", "failure_technical"] do
      assert outcome in denominator["included_outcomes"]
    end
  end

  test "participant identity and independent evaluator judgment stay separated" do
    manifest = Pramana.PilotParticipants.load_manifest!(@manifest)

    assert manifest["identifiers"]["direct_identity_in_study_dataset"] == false
    assert manifest["identifiers"]["cross_dataset_reidentification_key_in_study_dataset"] == false

    evaluator = manifest["evaluator_separation"]
    assert evaluator["qualified_source_judgment_requires_independent_evaluator"]
    assert evaluator["participant_cannot_supply_independent_source_judgment_for_own_task"]
    assert evaluator["disagreements_preserved"]
  end

  test "repeat-use signal stays voluntary and consent receipt stays pseudonymous" do
    manifest = Pramana.PilotParticipants.load_manifest!(@manifest)

    refute "fourteen_day_followup_contact" in manifest["required_consents"]
    assert "repeat_use_signal_is_unprompted" in manifest["required_disclosures"]
    assert manifest["optional_consents"]["followup_logistics_contact"] == false

    receipt = manifest["consent_receipt"]
    assert receipt["direct_identity_fields_allowed"] == false
    assert receipt["contact_or_identity_roster_separate"]
    assert manifest["identifiers"]["consent_receipt_contains_direct_identity"] == false
  end

  test "adult-only v1 and operator anti-denominator-gaming rules stay pinned" do
    manifest = Pramana.PilotParticipants.load_manifest!(@manifest)

    assert manifest["eligibility"]["minimum_age"] == 18
    assert manifest["eligibility"]["age_attestation_only"]
    assert manifest["eligibility"]["date_of_birth_collected"] == false
    assert manifest["eligibility"]["minors_in_pilot_v1"] == false

    denominator = manifest["task_denominator"]
    assert denominator["participant_exclusion_may_be_initiated_by_participant"]
    assert denominator["operator_or_evaluator_may_not_prompt_exclusion_based_on_outcome"]
    assert denominator["all_exclusions_counted_and_reported"]

    regulatory = manifest["regulatory_boundary"]
    assert regulatory["protocol_is_not_irb_or_regulatory_determination"]
    assert regulatory["institution_must_obtain_applicable_review_or_approval"]
  end

  test "external participant transfer, logging and public-cell boundaries stay closed" do
    manifest = Pramana.PilotParticipants.load_manifest!(@manifest)

    transfer = manifest["conditional_consents"]["external_provider_question_transfer"]
    assert transfer["default"] == false
    assert transfer["must_name_provider_or_product_route"]
    assert transfer["must_disclose_retention_training_human_review_and_deletion_terms"]

    purpose = manifest["purpose_boundaries"]
    assert purpose["full_question_not_in_operational_logs"]
    assert purpose["generated_answer_not_in_operational_logs"]
    assert purpose["prompt_payload_not_in_operational_logs"]

    sharing = manifest["public_sharing"]
    assert sharing["public_aggregate_min_distinct_participants_per_cell"] == 3
    assert sharing["cells_below_minimum_suppressed_or_merged"]
    assert sharing["exact_question_or_date_never_treated_as_aggregate"]
  end

  test "post-decision deletion and material protocol changes do not escape consent" do
    manifest = Pramana.PilotParticipants.load_manifest!(@manifest)

    withdrawal = manifest["withdrawal"]
    assert withdrawal["post_decision_individual_deletion_request_allowed_while_records_exist"]
    assert withdrawal["post_decision_deletion_recomputes_recorded_aggregate_decision"] == false

    protocol_change = manifest["protocol_change"]
    assert protocol_change["reconsent_required_before_next_measured_task"]
    assert "external_transfer" in protocol_change["material_changes_requiring_reconsent"]
    assert "retention_or_deletion" in protocol_change["material_changes_requiring_reconsent"]

    denominator = manifest["task_denominator"]
    assert denominator["scope_support_adjudication_blinded_to_system_output_where_feasible"]
    assert denominator["scope_support_adjudication_records_blinding_status"]
  end

  test "participant protocol preflight gate is ready while unrelated execution gates remain blocked" do
    manifest = Pramana.PilotParticipants.load_manifest!(@manifest)
    assert :ok = Pramana.PilotParticipants.validate(manifest, @root)

    preflight =
      @root
      |> Path.join("docs/strategy/pilot_preflight.json")
      |> File.read!()
      |> :json.decode()

    gates = Map.new(preflight["gates"], &{&1["id"], &1})

    assert gates["participant_protocol"]["state"] == "ready"
    assert gates["bilingual_evaluators"]["state"] == "blocked"
    assert gates["pilot_scope"]["state"] == "blocked"
    assert gates["foundry_g0"]["state"] == "blocked"
  end

  test "CLI validates the frozen protocol and rejects incomplete invocation" do
    {validated, 0} =
      System.cmd("elixir", ["bin/check_pilot_participants.exs", "--validate"],
        cd: @root,
        stderr_to_stdout: true
      )

    assert validated =~
             "pilot participant protocol valid; revision=1; status=frozen_pre_recruitment"

    {usage, 2} =
      System.cmd("elixir", ["bin/check_pilot_participants.exs"],
        cd: @root,
        stderr_to_stdout: true
      )

    assert usage =~ "--validate"
  end
end
