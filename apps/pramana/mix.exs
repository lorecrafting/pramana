defmodule Pramana.MixProject do
  use Mix.Project

  def project do
    [
      app: :pramana,
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
        # ▸ RESET 2026-08-28, and this is the one time it is allowed to go DOWN.
        # The ratchet was raised at real gates — 82 -> 91 -> 92 -> 93 for pramana_web — by
        # someone running `mix test --cover` by hand. Then `mix pramana.gate` became how the
        # suite is run, and its test step was plain `mix test`. Coverage drifted to 77.5%
        # with nothing watching, and the recorded number went on describing a codebase that
        # no longer existed.
        #
        # A threshold nothing enforces is not a standard, it is a comment. So the gate now
        # runs `--cover`, and the number is reset to what is actually true so that it can
        # fail. The restoration targets — 85 here, 93 for pramana_web — are tracked in
        # docs/PLAN.md, not quietly forgotten.
        #
        # THE RULE IS UNCHANGED: never lower this to make a run pass. Lowering from a
        # number you are meeting is gaming the ratchet; recording a number you are not
        # meeting, so it can be defended, is the opposite.
        # THE THRESHOLD TRAILS ACHIEVED COVERAGE BY ABOUT A POINT, DELIBERATELY.
        #
        # "Raise it when coverage rises" was applied literally on 2026-09-03 — 83 to 84
        # against an achieved 84.26 — and that is the wrong reading. A ratchet set at the
        # waterline makes every later commit a coverage negotiation, and the cheapest way
        # to win one is a test that asserts nothing. The number would keep going up and
        # mean less each time.
        #
        # A ratchet exists to catch a REGRESSION — a module that quietly lost its tests, a
        # suite that stopped running — not to force maximisation. A point of margin catches
        # that and still lets an honest commit land without buying its way past the gate.
        #
        # So: raise this when achieved coverage rises by more than the margin, and keep
        # roughly a point of room. Achieved 84.26 on 2026-09-03, after
        # `Pramana.Provenance` went 9% -> 86% and `Pramana.Publishing.Guard` 36% -> 73% —
        # both chosen for what they carry rather than for their size, invariant #4's
        # structural enforcement and the licence refusal at boot. Restoration target 85.
        #
        # NEVER lower it to make a failing run pass. Restoring margin after over-tightening
        # is a different act, and this comment is what makes it one.
        summary: [threshold: 83],
        ignore_modules: [
          ~r/^Mix\.Tasks\./,
          ~r/^Pramana\.Corpus\.[A-Z]/,
          Pramana.Application,
          Pramana.Repo
        ]
      ],
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Pramana.Application, []},
      extra_applications: [:logger]
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
      {:dns_cluster, "~> 0.2.0"},
      {:phoenix_pubsub, "~> 2.1"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:jason, "~> 1.2"},

      # CJK segmentation NIF — see docs/ELIXIR.md exception #1
      {:pramana_native, in_umbrella: true},

      # Embeddings. The Phase 0 spike established that BGE-M3's XLM-RoBERTa backbone
      # loads in Bumblebee for DENSE vectors; its sparse/ColBERT heads do not.
      {:bumblebee, "~> 0.6"},
      {:nx, "~> 0.9"},
      {:exla, "~> 0.9"},

      # Corpus pipeline
      {:pgvector, "~> 0.3"},
      {:saxy, "~> 1.6"},
      {:req, "~> 0.5"},
      {:oban, "~> 2.19"},
      {:yaml_elixir, "~> 2.11"},

      # Quality gates — see docs/CHECKS.md
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run #{__DIR__}/priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
    ]
  end
end
