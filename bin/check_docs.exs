# Repository checks: no Mix deps, database, models or live Foundry state.
root = Path.expand("..", __DIR__)
ExUnit.start()
Code.require_file(Path.join(root, "pramana/apps/pramana/lib/pramana/docs/sync.ex"))
Code.require_file(Path.join(root, "bin/pilot_preflight.exs"))
Code.require_file(Path.join(root, "bin/pilot_acceptance.exs"))
Code.require_file(Path.join(root, "bin/pilot_participants.exs"))
Code.require_file(Path.join(root, "pramana/apps/pramana/lib/pramana/pilot/scope_artifact.ex"))

for relative <- [
      "test/docs/routing_test.exs",
      "test/docs/tasks_test.exs",
      "test/docs/hygiene_test.exs",
      "test/layout_test.exs",
      "test/pilot_preflight_test.exs",
      "test/pilot_acceptance_test.exs",
      "test/pilot_participants_test.exs",
      "test/pilot_scope_artifact_test.exs",
      "test/local_layout_test.exs",
      "test/wrappers_test.exs",
      "pramana/apps/pramana/test/docs/sync_test.exs",
      "pramana/apps/pramana_web/test/pramana_web/mcp/documented_test.exs"
    ] do
  Code.require_file(Path.join(root, relative))
end
