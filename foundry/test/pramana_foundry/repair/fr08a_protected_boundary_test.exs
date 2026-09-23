defmodule PramanaFoundry.Repair.FR08AProtectedBoundaryTest do
  use ExUnit.Case, async: false

  alias PramanaFoundry.Repair.{FR08AProtectedBoundary, FR08HandoffGate}

  test "all seven revision-bound protected capabilities pass substantive public probes" do
    report = FR08AProtectedBoundary.report()

    assert report.identity.implementation_binding == "verified:source-sha256+beam-md5/v1"
    assert report.identity.subject_revision == "3db4ac1de002b9871cbc2e714d2edb510bd189e5"
    assert report.identity.subject_tree == "52dd5593a94c6a41c7f84363c8bbfee1bd154e74"
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
             "protected_primitives.ex|sha256:a426ce27b677ee0014f3ecb224293758f9f512db4805b06fca92764347b82302|beam_md5:599f1f24af0ea51489ce068ff3ace9dd"

    assert first =~
             "gateway.ex|sha256:dc8721beebc1ec8d239ec0e1ac861cdb192927640e9123c935b036afeef771d8|beam_md5:412b4970e02b24503cbc91f44449d67c"
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
