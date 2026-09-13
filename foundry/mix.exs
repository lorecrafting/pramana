defmodule PramanaFoundry.MixProject do
  use Mix.Project

  def project do
    [
      app: :pramana_foundry,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      escript: [main_module: PramanaFoundry.CLI],
      releases: [pramana_foundry: [include_executables_for: [:unix], vm_args: "rel/vm.args"]],
      deps: [
        {:owl, "~> 0.12"}
      ]
    ]
  end

  def application do
    [extra_applications: [:logger, :crypto, :public_key], mod: {PramanaFoundry.Application, []}]
  end
end
