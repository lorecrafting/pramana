defmodule PramanaFoundry.Repair.FR08AProtectedBoundaryTest do
  use ExUnit.Case, async: false

  alias PramanaFoundry.Repair.{FR08AProtectedBoundary, FR08HandoffGate}

  test "all seven revision-bound protected capabilities pass substantive public probes" do
    report = FR08AProtectedBoundary.report()

    assert report.identity.implementation_binding == "verified:source-sha256+beam-md5/v1"
    assert report.identity.subject_revision == "d199d24e230fe3c22bb4f8de95dd3db71aeac58a"
    assert report.identity.subject_tree == "805b1cf20e20c9b7091e6bfe237d1be5342fba75"
    assert length(report.identity.exercised_api) == 11
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
             "protected_primitives.ex|sha256:7b1653e4613ffa2fbbff77cab97311172ff188d00c8aa3e48a3bc4b9503bf630|beam_md5:ab95d17ba2b276f1935e8f7d66bfc24b"

    assert first =~
             "gateway.ex|sha256:e2ed0e49c71c46449f8c3da16a630aa3f7e5dd3b3be0742313624846c765f524|beam_md5:3482b1e7bef6a04794e2a17a0c91355f"
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
