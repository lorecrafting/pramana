# Standalone documentation checks: no Mix deps, application startup or database.
root = Path.expand("..", __DIR__)
ExUnit.start()
Code.require_file(Path.join(root, "pramana/apps/pramana/lib/pramana/paths.ex"))
Code.require_file(Path.join(root, "pramana/apps/pramana/lib/pramana/docs/sync.ex"))

for relative <- [
      "pramana/apps/pramana/test/docs/routing_test.exs",
      "pramana/apps/pramana/test/docs/tasks_test.exs",
      "pramana/apps/pramana/test/docs/hygiene_test.exs",
      "pramana/apps/pramana/test/docs/layout_test.exs",
      "pramana/apps/pramana/test/docs/sync_test.exs",
      "pramana/apps/pramana/test/pramana/paths_test.exs",
      "pramana/apps/pramana_web/test/pramana_web/mcp/documented_test.exs"
    ] do
  Code.require_file(Path.join(root, relative))
end
