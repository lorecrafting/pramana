defmodule PramanaFoundry.Projections.ProjectionTest do
  use ExUnit.Case, async: true

  alias PramanaFoundry.Projections.Projection

  test "projects only validated worker authority without broadening it" do
    canonical = fixture_assignment()
    assert {:ok, projection} = Projection.assignment(canonical)

    assert projection["scope"] == nil
    assert projection["ticket"]["scope"] == canonical["ticket"]["scope"]
    assert projection["ticket"]["required_checks"] == canonical["ticket"]["required_checks"]
    assert projection["disabled_operations"] == canonical["disabled_operations"]
    assert projection["assignment_path"] == canonical["assignment_path"]
    assert projection["proposal_path"] == :null
    assert Projection.authority_subset?(projection, canonical)

    bytes = File.read!(fixture_assignment_path())
    expected_digest = :sha256 |> :crypto.hash(bytes) |> Base.encode16(case: :lower)
    assert Projection.canonical_digest(bytes) == expected_digest

    changed = put_in(projection, ["ticket", "scope"], ["**"])
    refute changed["ticket"]["scope"] == canonical["ticket"]["scope"]
    refute Projection.authority_subset?(changed, canonical)
    assert canonical["ticket"]["scope"] == ["workflow/**"]
  end

  test "fails closed before projecting absent and unknown authority" do
    canonical = fixture_assignment()
    missing = Map.delete(canonical, "assignment_path")
    unknown = Map.put(canonical, "billing_mode", "paid")

    assert {:error, %{reason: {:missing_fields, ["assignment_path"]}, evidence: ^missing}} =
             Projection.assignment(missing)

    assert {:error, %{reason: {:unknown_fields, ["billing_mode"]}, evidence: ^unknown}} =
             Projection.assignment(unknown)
  end

  test "PM projection omits historical assignment snapshots but retains planning authority" do
    canonical = %{
      "schema_version" => 1,
      "task_id" => "PM",
      "run_id" => "pm-run",
      "role" => "pm",
      "accepted_revision" => String.duplicate("a", 40),
      "assignment_path" => "/runtime/pm-assignment.json",
      "proposal_path" => "/runtime/pm-proposal.json",
      "audit_path" => nil,
      "profile" => "pm-profile",
      "configured_model" => "model",
      "configured_model_id" => "provider/model",
      "configured_reasoning" => "medium",
      "max_proposals" => 3,
      "allowed_operations" => ["create", "park"],
      "disabled_operations" => ["remote_push"],
      "native_entrypoint" => "AGENTS.md",
      "planning_context" => %{
        "queue" => ["T1"],
        "pending_steering" => [],
        "assignments" => [
          %{
            "task_id" => "T1",
            "run_id" => "run-1",
            "status" => "blocked",
            "blocker" => "bounded evidence",
            "scheduling_decision" => %{"status" => "blocked"},
            "ticket" => fixture_assignment()["ticket"],
            "artifact_history" => List.duplicate(%{"large" => String.duplicate("x", 100)}, 20)
          }
        ]
      }
    }

    assert {:ok, projection} = Projection.assignment(canonical)
    refute Map.has_key?(projection["planning_context"], "assignments")
    assert [summary] = projection["planning_context"]["assignment_summaries"]

    assert summary["ticket"]["required_checks"] ==
             canonical["planning_context"]["assignments"]
             |> hd()
             |> get_in(["ticket", "required_checks"])

    refute Map.has_key?(summary, "artifact_history")
    assert projection["allowed_operations"] == canonical["allowed_operations"]
  end

  test "projects the closed production review record without inventing assignment fields" do
    canonical = %{
      "schema_version" => 1,
      "task_id" => "T1",
      "run_id" => "run-1",
      "commit" => String.duplicate("a", 40),
      "verdict" => "approved",
      "findings" => [],
      "checks" => [%{"command" => ["mix", "test"], "exit_code" => 0}],
      "remaining_risks" => []
    }

    assert {:ok, projection} = Projection.review(canonical)
    assert projection == Map.put(canonical, "projection_version", 1)
    assert Projection.authority_subset?(projection, canonical)
    refute Map.has_key?(projection, "role")
    refute Map.has_key?(projection, "assignment_path")

    unknown = Map.put(canonical, "candidate_commit", canonical["commit"])

    assert {:error, %{reason: {:unknown_fields, ["candidate_commit"]}, evidence: ^unknown}} =
             Projection.review(unknown)
  end

  defp fixture_assignment do
    fixture_assignment_path()
    |> File.read!()
    |> :json.decode()
  end

  defp fixture_assignment_path,
    do: Path.expand("../../fixtures/python/assignment-v1.json", __DIR__)
end
