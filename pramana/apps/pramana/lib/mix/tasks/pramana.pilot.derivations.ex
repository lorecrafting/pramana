defmodule Mix.Tasks.Pramana.Pilot.Derivations do
  @shortdoc "Checks Chinese-pilot derivation completion receipts"

  @moduledoc """
  Verifies that the four deterministic derived-data producers required by the Chinese
  pilot have clean, current receipts for one source bake.

      mix pramana.pilot.derivations
      mix pramana.pilot.derivations --bake-id <source-bake-id>
      mix pramana.pilot.derivations --bake-id <source-bake-id> --json

  A passing result is derivation-completion evidence only. It does not make the pilot scope
  ready, establish source rights, or prove scholarly correctness of inferred relations.
  """

  use Mix.Task

  alias Pramana.Bake
  alias Pramana.Pilot.DerivationReadiness

  @switches [bake_id: :string, json: :boolean]

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, rest} = OptionParser.parse!(argv, strict: @switches)

    if rest != [], do: Mix.raise("unexpected argument(s): #{Enum.join(rest, " ")}")

    bake_id =
      opts[:bake_id] || Bake.current_id() ||
        Mix.raise("no source bake is available; pass --bake-id explicitly")

    result = DerivationReadiness.check(bake_id)

    if opts[:json], do: Mix.shell().info(Jason.encode!(result)), else: report(result)

    unless result.ready do
      Mix.raise("pilot derivation receipts are incomplete or stale")
    end
  end

  defp report(result) do
    Mix.shell().info("pilot derivation receipts for #{result.source_bake_id}")

    Enum.each(result.derivations, fn {kind, status} ->
      Mix.shell().info("  #{String.pad_trailing(kind, 22)} #{status.state}")
    end)

    Mix.shell().info(if(result.ready, do: "  READY", else: "  NOT READY"))
  end
end
