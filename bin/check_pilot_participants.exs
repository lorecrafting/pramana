Code.require_file(Path.join(__DIR__, "pilot_participants.exs"))

defmodule Pramana.PilotParticipants.CLI do
  @moduledoc false

  def main(args) do
    root = Path.expand("..", __DIR__)
    default = Pramana.PilotParticipants.default_manifest(root)

    case parse(args, default) do
      {:ok, manifest_path} ->
        manifest = Pramana.PilotParticipants.load_manifest!(manifest_path)
        report(manifest, root)

      {:error, message} ->
        IO.puts(:stderr, message)
        2
    end
  rescue
    error ->
      IO.puts(:stderr, Exception.message(error))
      2
  end

  defp parse(["--validate"], default), do: {:ok, default}

  defp parse(["--validate", "--manifest", path], _default),
    do: {:ok, Path.expand(path)}

  defp parse(_args, _default),
    do: {:error, "usage: elixir bin/check_pilot_participants.exs --validate [--manifest PATH]"}

  defp report(manifest, root) do
    case Pramana.PilotParticipants.validate(manifest, root) do
      :ok ->
        IO.puts(
          "pilot participant protocol valid; revision=#{Pramana.PilotParticipants.revision(manifest)}; status=#{Pramana.PilotParticipants.status(manifest)}"
        )

        0

      {:error, errors} ->
        IO.puts(:stderr, "pilot participant protocol not accepted:")
        Enum.each(errors, &IO.puts(:stderr, "  - #{&1}"))
        2
    end
  end
end

System.halt(Pramana.PilotParticipants.CLI.main(System.argv()))
