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
  # The mix TASKS do not ship, and that is the point rather than an omission: `CLAUDE.md`
  # invariant #7 says tools read and the CLI writes. A release has no Mix, so a deployed
  # node physically cannot acquire, bake, or ingest — the read-only posture is a property
  # of the artefact rather than a rule the router enforces.
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
      preferred_envs: [precommit: :test]
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
      precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"]
    ]
  end
end
