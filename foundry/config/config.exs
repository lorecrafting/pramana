import Config

operator_runtime_root =
  System.get_env("PRAMANA_OPERATOR_RUNTIME_ROOT") ||
    if config_env() == :test do
      Path.join(System.tmp_dir!(), "pramana-foundry-test-operator")
    else
      "/Users/raymondluong/dev/pramana/foundry/local/"
    end

config :pramana_foundry,
  runtime_root: operator_runtime_root,
  max_assignments: 3,
  max_tasks: 8

config :pramana_foundry,
  herdr_command: "/opt/homebrew/bin/herdr",
  herdr_timeout_ms: 30_000,
  poll_seconds: 15
