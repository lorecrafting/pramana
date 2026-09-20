defmodule PramanaFoundry.Repair.H0AcceptedFR07BoundaryTest do
  use ExUnit.Case, async: false

  alias PramanaFoundry.Repair.{FR08HandoffGate, H0AcceptedFR07Boundary}

  @accepted_revision "af0c51b4682c50080e67194dd853fbaa1eebace7"

  test "public probes produce the honest revision-bound blocked inventory" do
    report = H0AcceptedFR07Boundary.report()

    assert report.schema == "pramana-foundry-h0-accepted-fr07-boundary/v1"
    assert report.identity.accepted_revision == @accepted_revision
    assert report.identity.accepted_tree == "e4aed492d5973d185a7e772d1b764e1117df11c1"
    assert length(report.identity.public_api) == 4

    assert report.gate.status == "blocked"
    refute FR08HandoffGate.ready?(report.gate)
    assert report.gate.subject_revision == @accepted_revision
    assert report.gate.passed_count == 4
    assert report.gate.failed_count == 0
    assert report.gate.unavailable_count == 3

    statuses = Map.new(report.gate.capabilities, &{&1.id, &1.status})

    assert statuses == %{
             "atomic_authority_commit" => "unavailable",
             "complete_read_set_cas" => "unavailable",
             "fail_closed_recovery" => "passed",
             "immutable_legacy_import" => "passed",
             "protected_field_boundary" => "passed",
             "revision_and_inbox_facts" => "unavailable",
             "same_command_lookup_before_revision" => "passed"
           }

    assert Enum.all?(report.gate.capabilities, fn capability ->
             detail = capability.evidence || capability.reason
             is_binary(detail) and byte_size(detail) <= 512
           end)
  end

  test "positive probe receipts are reproducible and content addressed" do
    first = H0AcceptedFR07Boundary.report()
    second = H0AcceptedFR07Boundary.report()

    assert first == second

    assert Enum.all?(first.gate.capabilities, fn
             %{status: "passed", evidence: evidence} ->
               Regex.match?(~r/^h0:[a-z-]+:sha256:[0-9a-f]{64}$/, evidence)

             %{status: "unavailable", evidence: nil, reason: "h0:" <> _reason} ->
               true
           end)
  end

  test "a different revision cannot reuse accepted-v9 evidence" do
    report =
      FR08HandoffGate.run(H0AcceptedFR07Boundary,
        subject_revision: String.duplicate("0", 40)
      )

    assert report.status == "blocked"
    assert report.passed_count == 0
    assert report.failed_count == 0
    assert report.unavailable_count == 7
    refute FR08HandoffGate.ready?(report)
    assert Enum.all?(report.capabilities, &(&1.reason == "h0:accepted_revision_mismatch"))
  end

  test "accepted API identity matches the exact accepted revision" do
    foundry_root = Path.expand("../../..", __DIR__)
    repository_root = Path.expand("..", foundry_root)

    Enum.each(H0AcceptedFR07Boundary.identity().public_api, fn entry ->
      repository_path = "foundry/" <> entry.path

      {bytes, 0} =
        System.cmd("git", ["show", "#{@accepted_revision}:#{repository_path}"],
          cd: repository_root,
          stderr_to_stdout: true
        )

      digest = :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
      assert digest == entry.sha256
      assert File.read!(Path.join(foundry_root, entry.path)) == bytes
    end)
  end
end
