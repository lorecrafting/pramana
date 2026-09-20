defmodule PramanaFoundry.Repair.FR08AProtectedBoundaryTest do
  use ExUnit.Case, async: false

  alias PramanaFoundry.Repair.{FR08AProtectedBoundary, FR08HandoffGate}

  test "all seven revision-bound protected capabilities pass substantive public probes" do
    report = FR08AProtectedBoundary.report()

    assert report.identity.implementation_binding == "verified:source-sha256+beam-md5/v1"
    assert report.identity.subject_revision == "35ebb1d6d2d9a1661686f9f14e17c0dbeb0d2de0"
    assert report.identity.subject_tree == "2ed0b1ebf0e3aaa34ad404c62cb805b696679930"
    assert length(report.identity.exercised_api) == 9
    assert FR08HandoffGate.ready?(report.gate)
    assert report.gate.passed_count == 7
    assert report.gate.failed_count == 0
    assert report.gate.unavailable_count == 0

    assert Enum.all?(report.gate.capabilities, fn capability ->
             capability.status == "passed" and
               String.starts_with?(capability.evidence, "fr08a:") and
               String.contains?(capability.evidence, ":sha256:")
           end)
  end

  test "revision mismatch cannot claim readiness" do
    report =
      FR08HandoffGate.run(FR08AProtectedBoundary,
        subject_revision: "0000000000000000000000000000000000000000"
      )

    refute FR08HandoffGate.ready?(report)
    assert report.unavailable_count == 7
  end

  test "frozen artifact is deterministic and bound to the protected sources" do
    first = FR08AProtectedBoundary.report_artifact()
    second = FR08AProtectedBoundary.report_artifact()
    foundry_root = Path.expand("../../..", __DIR__)

    assert first == second
    assert first == File.read!(Path.join(foundry_root, "docs/fr-08/fr08a-protected-report.txt"))
    assert first =~ "ready=true\n"
    assert first =~ "implementation_binding=verified:source-sha256+beam-md5/v1\n"

    assert first =~
             "protected_primitives.ex|sha256:909cae2e73e8e5c7153567ed6d09f55d9254aa1db2ff074316a73082d4122264|beam_md5:ddecbc7ded57c8ab76f6f72fcaa4f4c6"
  end

  test "changed loaded Gateway implementation refuses all positive evidence" do
    foundry_root = Path.expand("../../..", __DIR__)
    fixture = Path.join(foundry_root, "test/support/fr08a_identity_negative_fixture.exs")

    {output, 0} =
      System.cmd(System.find_executable("mix"), ["run", "--no-start", "--no-compile", fixture],
        cd: foundry_root,
        env: [{"COORDINATOR_TICK", "0"}, {"HERDR_ENV", nil}]
      )

    assert output == "identity_mismatch_refused\n"
  end
end
