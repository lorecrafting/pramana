Code.require_file(
  Path.expand(
    "../apps/pramana/lib/pramana/pilot/scope_artifact.ex",
    __DIR__
  )
)

defmodule Pramana.PilotScopeCheck.CLI do
  @moduledoc false

  def main(args) do
    case args do
      ["--validate", path] ->
        artifact =
          path
          |> Path.expand()
          |> File.read!()
          |> Pramana.Pilot.ScopeArtifact.decode!()

        report(Pramana.Pilot.ScopeArtifact.validate(artifact), artifact)

      _ ->
        IO.puts(:stderr, "usage: elixir bin/check_pilot_scope.exs --validate PATH")
        2
    end
  rescue
    error ->
      IO.puts(:stderr, Exception.message(error))
      2
  end

  defp report(:ok, artifact) do
    IO.puts(
      "pilot scope artifact structurally valid; live_currentness=not_established; " <>
        "scope=#{artifact["scope_content_sha256"]}; " <>
        "release=#{artifact["release"]["release_id"]}"
    )

    0
  end

  defp report({:error, errors}, _artifact) do
    IO.puts(:stderr, "pilot scope artifact not accepted:")
    Enum.each(errors, &IO.puts(:stderr, "  - #{&1}"))
    2
  end
end

System.halt(Pramana.PilotScopeCheck.CLI.main(System.argv()))
