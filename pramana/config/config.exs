# This file is responsible for configuring your umbrella
# and **all applications** and their dependencies with the
# help of the Config module.
#
# Note that all applications in your umbrella share the
# same configuration and dependencies, which is why they
# all use the same configuration file. If you want different
# configurations or dependencies per app, it is best to
# move said applications out of the umbrella.
import Config

# Configure Mix tasks and generators
config :pramana,
  ecto_repos: [Pramana.Repo],
  # The umbrella root, resolved at compile time. `File.cwd!()` is unreliable here:
  # in an umbrella, mix runs each child app from its own directory, so raw/ and
  # sources.lock.json would resolve differently depending on how tests were invoked.
  project_root: Path.expand("..", __DIR__),
  # Figure blocks live in project STATUS and the still-shared active PLAN. Keep the
  # roots explicit: ordinary source/data paths remain relative to the project only.
  documentation_roots: [Path.expand("..", __DIR__), Path.expand("../..", __DIR__)]

# pgvector requires a custom Postgrex types module so `vector` columns
# encode/decode natively. See docs/ARCHITECTURE.md stage 4.
config :pramana, Pramana.Repo, types: Pramana.PostgrexTypes

# The bake runs as Oban jobs: durable, resumable, and fault-isolated per file.
# Concurrency is bounded because normalization is CPU-bound and the DB is the real
# constraint -- more workers past core count just lengthens transactions.
config :pramana, Oban,
  repo: Pramana.Repo,
  engine: Oban.Engines.Basic,
  queues: [bake: 8],
  # SEVEN DAYS, not one. The pruner discards completed, cancelled and discarded jobs alike,
  # and a job that exhausted its attempts is `discarded` — so at 24 h a bake run overnight
  # loses its own failures before anyone reads them. That is precisely what made the stall of
  # 41-of-53 jobs expensive to diagnose. Oban's pruner takes a single `max_age`, so keeping
  # failures longer means keeping successes longer; `oban_jobs` rows are small and a full
  # bake is a few thousand of them, which is a trade worth making in one direction only.
  plugins: [{Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7}]

config :pramana_web,
  ecto_repos: [Pramana.Repo],
  generators: [context_app: :pramana]

# Configures the endpoint
config :pramana_web, PramanaWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: PramanaWeb.ErrorHTML, json: PramanaWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Pramana.PubSub,
  live_view: [signing_salt: "oh6/CmTf"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  pramana_web: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../apps/pramana_web/assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  pramana_web: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("../apps/pramana_web", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# EXLA compiles Nx to native code; without it embedding runs on the pure-Elixir
# backend and is orders of magnitude slower.
config :nx, :default_backend, EXLA.Backend

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
