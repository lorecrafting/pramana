defmodule PramanaFoundry.Repair.FR08AProtectedBoundaryTest do
  use ExUnit.Case, async: false

  alias PramanaFoundry.Repair.{FR08AProtectedBoundary, FR08HandoffGate}

  test "all seven revision-bound protected capabilities pass substantive public probes" do
    report = FR08AProtectedBoundary.report()

    assert report.identity.implementation_binding == "verified:source-sha256+beam-md5/v1"
    assert report.identity.subject_revision == "b4a203e6119f08b7245b15fe3e45ab862fc4f5d2"
    assert report.identity.subject_tree == "9e52a8b4b60746c4080952cfa59946a55263ecb1"
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
             "protected_primitives.ex|sha256:72e7a8cc868ac18154f85b8df0e9f84cf00732be0fa3a3bd8e3d0383775b7b97|beam_md5:f6b9988ba8e8e16e613b3ca75dc09f89"

    assert first =~
             "gateway.ex|sha256:69b4c025befa04213c7181b0aa1ef5d44d103f9f692de14c85247d8053560ec1|beam_md5:dc9e42d03dfd8aa8cb7ddb74ea96a27a"
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
