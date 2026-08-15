defmodule PramanaWeb.MixProject do
  use Mix.Project

  def project do
    [
      app: :pramana_web,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.20",
      elixirc_paths: elixirc_paths(Mix.env()),
      test_coverage: [
        # 90% is Mix's default and this project cannot honestly hold it umbrella-wide:
        # the uncovered modules are CLI shells over already-covered domain functions
        # (`pramana.embed.import` is 0%, `Pramana.Embed.Transfer` behind it is 100%),
        # OTP application callbacks, and generated Phoenix scaffolding unused until
        # Phase 8. Excluding those and holding a real number beats a threshold nobody
        # can meet, which just gets ignored.
        #
        # The threshold is a RATCHET: raise it when coverage rises, never lower it to
        # make a run pass. `docs/CHECKS.md` treats a regression as a gate failure.
        #
        # It nests under `summary:` — `test_coverage: [threshold: n]` is silently
        # ignored and Mix keeps applying its own default of 90.
        summary: [threshold: 82],
        ignore_modules: [
          ~r/^Mix\.Tasks\./,
          ~r/^Pramana\.Corpus\.[A-Z]/,
          PramanaWeb.Application,
          PramanaWeb.Endpoint,
          PramanaWeb.Telemetry,
          PramanaWeb.CoreComponents,
          PramanaWeb.Layouts,
          PramanaWeb.PageHTML,
          PramanaWeb.PageController,
          PramanaWeb.ErrorHTML,
          PramanaWeb.ErrorJSON,
          PramanaWeb.Router,
          PramanaWeb
        ]
      ],
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {PramanaWeb.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.8.11"},
      {:phoenix_ecto, "~> 4.5"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.1.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:pramana, in_umbrella: true},
      {:anubis_mcp, "~> 2.0"},
      {:jason, "~> 1.2"},
      {:bandit, "~> 1.5"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "assets.setup", "assets.build"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind pramana_web", "esbuild pramana_web"],
      "assets.deploy": [
        "tailwind pramana_web --minify",
        "esbuild pramana_web --minify",
        "phx.digest"
      ]
    ]
  end
end
