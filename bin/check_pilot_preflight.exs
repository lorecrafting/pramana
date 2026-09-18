Code.require_file(Path.join(__DIR__, "pilot_preflight.exs"))

defmodule Pramana.PilotPreflight.CLI do
  @moduledoc false

  def main(args) do
    root = Path.expand("..", __DIR__)

    case parse(args, Pramana.PilotPreflight.default_manifest(root)) do
      {:ok, mode, manifest_path} ->
        manifest = Pramana.PilotPreflight.load_manifest!(manifest_path)

        case mode do
          :validate ->
            report_validation(manifest, root)

          :ready ->
            report_ready(manifest, root)
        end

      {:error, message} ->
        IO.puts(:stderr, message)
        2
    end
  rescue
    error ->
      IO.puts(:stderr, Exception.message(error))
      2
  end

  defp report_validation(manifest, root) do
    case Pramana.PilotPreflight.validate(manifest, root) do
      :ok ->
        IO.puts(
          "pilot preflight manifest valid; status=#{Pramana.PilotPreflight.status(manifest)}"
        )

        0

      {:error, errors} ->
        print_errors(errors)
        2
    end
  end

  defp report_ready(manifest, root) do
    current_revision = Pramana.PilotPreflight.git_revision!(root)

    case Pramana.PilotPreflight.ready(manifest, root, current_revision) do
      :ok ->
        IO.puts("pilot preflight ready for #{current_revision}")
        0

      {:error, errors} ->
        print_errors(errors)
        2
    end
  end

  defp parse(["--validate"], default), do: {:ok, :validate, default}
  defp parse(["--ready"], default), do: {:ok, :ready, default}
  defp parse(["--validate", "--manifest", path], _default),
    do: {:ok, :validate, Path.expand(path)}

  defp parse(["--ready", "--manifest", path], _default),
    do: {:ok, :ready, Path.expand(path)}

  defp parse(_args, _default), do: {:error, usage()}

  defp usage do
    """
    usage:
      elixir bin/check_pilot_preflight.exs --validate [--manifest PATH]
      elixir bin/check_pilot_preflight.exs --ready [--manifest PATH]
    """
    |> String.trim()
  end

  defp print_errors(errors) do
    IO.puts(:stderr, "pilot preflight not accepted:")

    Enum.each(errors, fn error ->
      IO.puts(:stderr, "  - #{error}")
    end)
  end
end

System.halt(Pramana.PilotPreflight.CLI.main(System.argv()))
