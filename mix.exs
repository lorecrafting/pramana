defmodule Pramana.MixProject do
  use Mix.Project

  def project do
    [
      app: :pramana,
      version: "0.1.0",
      elixir: "~> 1.20",
      elixirc_paths: elixirc_paths(Mix.env()),
      test_paths: ["test/app"],
      test_coverage: [
        # Combined baseline was 90.16% at conversion; keep about one point of room.
        summary: [threshold: 89],
        ignore_modules: [
          ~r/^Mix\.Tasks\./,
          ~r/^Pramana\.Corpus\.[A-Z]/,
          Pramana.Application,
          Pramana.Repo,
          PramanaNative,
          PramanaWeb.Endpoint,
          PramanaWeb.Telemetry,
          PramanaWeb.CoreComponents,
          PramanaWeb.Layouts,
          PramanaWeb.ErrorHTML,
          PramanaWeb.ErrorJSON,
          PramanaWeb.Router,
          PramanaWeb
        ]
      ],
      start_permanent: Mix.env() == :prod,
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader],
      dialyzer: [
        plt_local_path: "priv/plts",
        plt_core_path: "priv/plts",
        plt_add_apps: [:mix, :ex_unit]
      ],
      aliases: aliases(),
      deps: deps()
    ]
  end

  def application do
    [mod: {Pramana.Application, []}, extra_applications: [:logger, :runtime_tools]]
  end

  def cli do
    [preferred_envs: [test: :test, precommit: :test]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/app/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:dns_cluster, "~> 0.2.0"},
      {:phoenix_pubsub, "~> 2.1"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:jason, "~> 1.2"},
      {:rustler, "~> 0.38"},
      {:bumblebee, "~> 0.6"},
      {:nx, "~> 0.9"},
      {:exla, "~> 0.9"},
      {:pgvector, "~> 0.3"},
      {:saxy, "~> 1.6"},
      {:req, "~> 0.5"},
      {:oban, "~> 2.19"},
      {:yaml_elixir, "~> 2.11"},
      {:phoenix, "~> 1.8.11"},
      {:phoenix_ecto, "~> 4.5"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.1.0"},
      {:lazy_html, ">= 0.1.13", only: :test},
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
      {:anubis_mcp, "~> 2.0"},
      {:bandit, "~> 1.5"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind pramana_web", "esbuild pramana_web"],
      "assets.deploy": [
        "compile",
        "tailwind pramana_web --minify",
        "esbuild pramana_web --minify",
        "phx.digest"
      ],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"]
    ]
  end
end
