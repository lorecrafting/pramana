# Standalone documentation checks: no Mix deps, application startup or database.
root = Path.expand("..", __DIR__)
ExUnit.start()

for relative <- [
      "apps/pramana/test/docs/routing_test.exs",
      "apps/pramana/test/docs/tasks_test.exs",
      "apps/pramana/test/docs/hygiene_test.exs",
      "apps/pramana_web/test/pramana_web/mcp/documented_test.exs"
    ] do
  Code.require_file(Path.join(root, relative))
end
