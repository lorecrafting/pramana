defmodule Strategy.PilotAcceptanceTest do
  use ExUnit.Case, async: true

  @root Path.expand("..", __DIR__)
  @manifest Path.join(@root, "docs/strategy/pilot_acceptance.json")

  test "current frozen acceptance contract is structurally valid" do
    manifest = Pramana.PilotAcceptance.load_manifest!(@manifest)

    assert :ok = Pramana.PilotAcceptance.validate(manifest, @root)
    assert Pramana.PilotAcceptance.revision(manifest) == 1
    assert Pramana.PilotAcceptance.status(manifest) == "frozen_pre_execution"
  end

  test "a frozen execution value cannot drift without changing the validator" do
    manifest = Pramana.PilotAcceptance.load_manifest!(@manifest)

    changed =
      put_in(
        manifest,
        ["execution_bounds", "model_calls_total_max"],
        manifest["execution_bounds"]["model_calls_total_max"] + 1
      )

    assert {:error, errors} = Pramana.PilotAcceptance.validate(changed, @root)
    assert "execution_bounds does not match the frozen v1 contract" in errors
  end

  test "critical and rehearsal ids are closed for contract revision one" do
    manifest = Pramana.PilotAcceptance.load_manifest!(@manifest)

    changed = Map.update!(manifest, "critical_failure_ids", &tl/1)
    assert {:error, errors} = Pramana.PilotAcceptance.validate(changed, @root)
    assert "critical_failure_ids does not match the frozen v1 contract" in errors

    changed = put_in(manifest, ["rehearsal", "case_ids"], ["R01_exact_attested_term"])
    assert {:error, errors} = Pramana.PilotAcceptance.validate(changed, @root)
    assert "rehearsal does not match the frozen v1 contract" in errors
  end

  test "verified query-equivalence threshold is frozen at one hundred percent" do
    manifest = Pramana.PilotAcceptance.load_manifest!(@manifest)

    assert manifest["evaluation"]["query_expansion_verified_surface_accuracy_required"] == 1.0

    changed =
      put_in(
        manifest,
        ["evaluation", "query_expansion_verified_surface_accuracy_required"],
        0.99
      )

    assert {:error, errors} = Pramana.PilotAcceptance.validate(changed, @root)
    assert "evaluation does not match the frozen v1 contract" in errors
  end

  test "adversarial authority and fan-out ceilings stay closed" do
    manifest = Pramana.PilotAcceptance.load_manifest!(@manifest)
    bounds = manifest["execution_bounds"]
    rules = manifest["execution_rules"]
    evaluation = manifest["evaluation"]

    assert bounds["retrieval_executions_total_max"] ==
             bounds["chinese_lexical_query_executions_max"] +
               bounds["chinese_semantic_query_executions_max"] +
               bounds["original_english_multilingual_queries_max"] +
               bounds["existing_english_index_queries_max"]

    assert bounds["weak_expansion_fusion_contributions_per_passage_max"] == 1
    assert rules["external_provider_calls_authorized"] == false
    assert rules["external_provider_capacity_authorized"] == false

    assert evaluation["retrieval_supported_cases_min"] == 30
    assert evaluation["retrieval_commentary_eligible_cases_min"] == 8
    assert evaluation["retrieval_recall_at_10_min"] == 0.80
    assert evaluation["retrieval_commentary_recall_at_10_min"] == 0.75

    assert "CF15_source_data_control_injection" in manifest["critical_failure_ids"]
    assert "R16_source_data_control_injection" in manifest["rehearsal"]["case_ids"]

    assert manifest["rehearsal"][
             "actual_authorized_inference_route_quality_required_before_trust_ready"
           ]
  end

  test "current preflight alignment keeps spec gates ready and rehearsal trust blocked" do
    manifest = Pramana.PilotAcceptance.load_manifest!(@manifest)
    assert :ok = Pramana.PilotAcceptance.validate(manifest, @root)

    preflight =
      @root
      |> Path.join("docs/strategy/pilot_preflight.json")
      |> File.read!()
      |> :json.decode()

    gates = Map.new(preflight["gates"], &{&1["id"], &1})

    assert gates["execution_bounds"]["state"] == "ready"
    assert gates["evaluation_rubric"]["state"] == "ready"
    assert gates["critical_taxonomy"]["state"] == "ready"
    assert gates["rehearsal_trust"]["state"] == "blocked"
    assert gates["retrieval_baseline"]["state"] == "blocked"
  end

  test "CLI validates the frozen contract and rejects incomplete invocation" do
    {validated, 0} =
      System.cmd("elixir", ["bin/check_pilot_acceptance.exs", "--validate"],
        cd: @root,
        stderr_to_stdout: true
      )

    assert validated =~ "pilot acceptance contract valid; revision=1; status=frozen_pre_execution"

    {usage, 2} =
      System.cmd("elixir", ["bin/check_pilot_acceptance.exs"],
        cd: @root,
        stderr_to_stdout: true
      )

    assert usage =~ "--validate"
  end
end
