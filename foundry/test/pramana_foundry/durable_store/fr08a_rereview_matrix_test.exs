defmodule PramanaFoundry.DurableStore.FR08ARereviewMatrixTest do
  use ExUnit.Case, async: false

  @tag timeout: 120_000
  test "the maintained hostile final-review matrix passes all twenty-two public cases" do
    foundry_root = Path.expand("../../..", __DIR__)
    probe = Path.join(foundry_root, "docs/fr-08/fr08a-final-review-probes.exs")

    {output, status} =
      System.cmd(
        System.find_executable("mix"),
        ["run", "--no-start", "--no-compile", probe],
        cd: foundry_root,
        env: [
          {"COORDINATOR_TICK", "0"},
          {"HERDR_ENV", nil},
          {"TMPDIR", canonical_tmp()}
        ],
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert output =~ "Result: 22 passed", output
  end

  defp canonical_tmp do
    if File.dir?("/private/tmp"), do: "/private/tmp", else: System.tmp_dir!()
  end
end
