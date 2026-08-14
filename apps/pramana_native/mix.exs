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
