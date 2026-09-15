defmodule PramanaNative.MixProject do
  use Mix.Project

  def project do
    [
      app: :pramana_native,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      test_coverage: [
        # Every function here is a NIF stub: the Elixir body is `:erlang.nif_error/1`
        # and is REPLACED by the Rust implementation when the module loads, so it never
        # executes and coverage reports it as dead no matter how well tested it is. All
        # three functions are exercised by the suite. The number would be noise, so the
        # module is excluded rather than the threshold fudged.
        # (Excluding the module outright instead makes Mix's summary list empty and
        # `mix test --cover` crashes in Enum.max/1, so the threshold is 0 rather than
        # an ignore_modules entry.)
        summary: [threshold: 0]
      ],
      deps: deps()
    ]
  end

  def application, do: [extra_applications: [:logger]]

  defp deps do
    [
      {:rustler, "~> 0.38"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end
end
