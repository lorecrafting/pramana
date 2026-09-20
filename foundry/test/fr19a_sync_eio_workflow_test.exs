defmodule PramanaFoundry.CI.FR19ASyncEIOWorkflowTest do
  use ExUnit.Case, async: true

  test "Gateway fixture receives its seven arguments without a literal separator" do
    workflow =
      __DIR__
      |> Path.join("../../.github/workflows/fr19a-sync-eio.yml")
      |> Path.expand()
      |> File.read!()

    refute Regex.match?(~r/fr19a_linux_sync_eio_fixture\.exs\s+--(?:\s|\\)/, workflow)

    assert workflow =~
             "test/support/fr19a_linux_sync_eio_fixture.exs \\\n" <>
               "              \"$source_root/authority.sqlite3\""
  end

  test "privileged tracer drops the tracee to the validated runner identity" do
    workflow =
      __DIR__
      |> Path.join("../../.github/workflows/fr19a-sync-eio.yml")
      |> Path.expand()
      |> File.read!()

    assert workflow =~ "if sudo -n /usr/bin/env \\\n"
    assert workflow =~ ~s("$strace_path" -u "$runner_user" -ff -yy -ttt)
    assert workflow =~ ~s(FR19A_EXPECTED_RUNNER_UID="$runner_uid")
    assert workflow =~ "if [[ $runner_uid -eq 0"
  end
end
