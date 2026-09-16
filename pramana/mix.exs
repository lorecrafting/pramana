defmodule Pramana.Umbrella.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.1.0",
      start_permanent: Mix.env() == :prod,
      dialyzer: [
        plt_local_path: "priv/plts",
        plt_core_path: "priv/plts",
        # Mix and ExUnit are build/test tools, absent from the runtime PLT by default,
        # so mix tasks would otherwise report every Mix.* call as unknown.
        plt_add_apps: [:mix, :ex_unit]
      ],
      deps: deps(),
      aliases: aliases(),
      releases: releases(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  # ONE RELEASE, AND IT DELIBERATELY OMITS NOTHING. Both apps ship, because the web app is
  # transport over a domain that owns the data — splitting them would need the domain
  # reachable over the network, which is a distributed system nobody asked for.
  #
  # Mix tasks do not ship in this release. That removes the CLI entry points, not
  # domain write functions or database privileges: production still requires a
  # restricted database role and the checks in docs/DEPLOY.md.
  defp releases do
    [
      pramana: [
        applications: [pramana: :permanent, pramana_web: :permanent],
        include_executables_for: [:unix]
      ]
    ]
  end

  def cli do
    [
      preferred_envs: [test: :test, precommit: :test]
    ]
  end

  # Dependencies can be Hex packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
  #
  # Type "mix help deps" for more examples and options.
  #
  # Dependencies listed here are available only for this project
  # and cannot be accessed from applications inside the apps/ folder.
  defp deps do
    [
      # Required to run "mix format" on ~H/.heex files from the umbrella root
      {:phoenix_live_view, ">= 0.0.0"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  #
  # Aliases listed here are available only for this project
  # and cannot be accessed from applications inside the apps/ folder.
  defp aliases do
    [
      # run `mix setup` in all child apps
      setup: ["cmd mix setup"],
      # Prepare the test database before recursive umbrella application startup.
      # A child-only alias is too late when another child starts the domain app.
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"]
    ]
  end
end
