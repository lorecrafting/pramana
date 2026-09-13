import Config

config :pramana_foundry,
  runtime_root: "/Users/raymondluong/dev/pramana/foundry/local/",
  max_assignments: 3,
  max_tasks: 8

config :pramana_foundry,
  herdr_command: "/opt/homebrew/bin/herdr",
  herdr_timeout_ms: 30_000,
  poll_seconds: 15
