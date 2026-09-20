defmodule PramanaFoundry.Repair.H0AcceptedFR07BoundaryTest do
  use ExUnit.Case, async: false

  alias PramanaFoundry.Repair.{FR08HandoffGate, H0AcceptedFR07Boundary}

  @accepted_revision "af0c51b4682c50080e67194dd853fbaa1eebace7"
  @test_adapter_revision String.duplicate("a", 40)

  test "historical provider refuses to credit the evolved FR-08A implementation" do
    report = H0AcceptedFR07Boundary.report(@test_adapter_revision)

    assert report.schema == "pramana-foundry-h0-accepted-fr07-boundary/v1"
    assert report.identity.accepted_revision == @accepted_revision
    assert report.identity.accepted_tree == "e4aed492d5973d185a7e772d1b764e1117df11c1"
    assert report.identity.adapter_probe_revision == @test_adapter_revision

    assert report.identity.implementation_binding == %{
             status: "mismatch",
             method: "source-sha256+beam-md5/v1"
           }

    assert length(report.identity.public_api) == 4

    assert report.gate.status == "blocked"
    refute FR08HandoffGate.ready?(report.gate)
    assert report.gate.subject_revision == @accepted_revision
    assert report.gate.passed_count == 0
    assert report.gate.failed_count == 0
    assert report.gate.unavailable_count == 7

    assert Enum.all?(
             report.gate.capabilities,
             &(&1.status == "unavailable" and
                 &1.reason == "h0:loaded_accepted_api_identity_mismatch")
           )

    assert Enum.all?(report.gate.capabilities, fn capability ->
             detail = capability.evidence || capability.reason
             is_binary(detail) and byte_size(detail) <= 512
           end)
  end

  test "evolved implementation refusal remains bounded" do
    report = H0AcceptedFR07Boundary.report(@test_adapter_revision)

    assert Enum.all?(report.gate.capabilities, fn capability ->
             capability.status == "unavailable" and capability.evidence == nil and
               capability.reason == "h0:loaded_accepted_api_identity_mismatch"
           end)
  end

  test "frozen accepted-v9 artifact and adapter sources remain historically bound" do
    foundry_root = Path.expand("../../..", __DIR__)
    artifact_path = Path.join(foundry_root, "docs/fr-08/h0-accepted-fr07-report.txt")
    expected = File.read!(artifact_path)

    [_line, adapter_revision] =
      Regex.run(~r/^adapter_probe_revision=([0-9a-f]{40})$/m, expected)

    repository_root = Path.expand("..", foundry_root)

    for path <- [
          "foundry/lib/pramana_foundry/repair/h0_accepted_fr07_boundary.ex",
          "foundry/test/support/h0_report_fixture.exs",
          "foundry/test/support/h0_identity_negative_fixture.exs"
        ] do
      {bytes, 0} =
        System.cmd("git", ["show", "#{adapter_revision}:#{path}"],
          cd: repository_root,
          stderr_to_stdout: true
        )

      assert bytes == File.read!(Path.join(repository_root, path))
    end

    assert expected =~ "implementation_binding=verified|source-sha256+beam-md5/v1\n"
    assert expected =~ "passed_count=4\n"
    assert expected =~ "unavailable_count=3\n"
  end

  test "changed loaded Gateway implementation refuses accepted-v9 positive evidence" do
    foundry_root = Path.expand("../../..", __DIR__)

    assert run_fixture(
             foundry_root,
             "h0_identity_negative_fixture.exs",
             @test_adapter_revision,
             "normal"
           ) == "identity_mismatch_refused\n"
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

  test "accepted API identity matches its exact historical revision" do
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

      if entry.path == "lib/pramana_foundry/durable_store/gateway.ex" do
        refute File.read!(Path.join(foundry_root, entry.path)) == bytes
      end
    end)
  end

  defp run_fixture(foundry_root, fixture, adapter_revision, load_order) do
    fixture_path = Path.join([foundry_root, "test", "support", fixture])

    {output, 0} =
      System.cmd(
        System.find_executable("mix"),
        ["run", "--no-start", "--no-compile", fixture_path],
        cd: foundry_root,
        env: [
          {"H0_ADAPTER_REVISION", adapter_revision},
          {"H0_LOAD_ORDER", load_order},
          {"COORDINATOR_TICK", "0"},
          {"HERDR_ENV", nil}
        ]
      )

    output
  end
end
