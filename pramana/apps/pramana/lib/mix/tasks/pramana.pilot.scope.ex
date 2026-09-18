defmodule Mix.Tasks.Pramana.Pilot.Scope do
  @shortdoc "Materializes the release-bound Chinese pilot scope"

  @moduledoc """
  Produces the exact scope artifact that the Chinese pilot preflight requires.

      mix pramana.pilot.scope \
        --release-id v2-or-release-digest \
        --out /tmp/pramana-pilot-scope.json

  The release id is mandatory. The task refuses an unstamped, stale, legacy or differently
  selected release. It is read-only: it does not modify corpus relations, alignments,
  releases or the preflight manifest.

  A successful file is **not** automatic pilot approval. Review it, reconcile rights for
  the complete expanded scope, and only then update the separate readiness evidence.

  A saved file can be checked without querying the corpus:

      mix pramana.pilot.scope --validate /tmp/pramana-pilot-scope.json
  """

  use Mix.Task

  alias Pramana.Pilot.Scope
  alias Pramana.Pilot.ScopeArtifact

  @switches [release_id: :string, out: :string, validate: :string]

  @impl Mix.Task
  def run(argv) do
    {opts, rest} = OptionParser.parse!(argv, strict: @switches)

    if rest != [], do: Mix.raise("unexpected argument(s): #{Enum.join(rest, " ")}")

    case opts[:validate] do
      path when is_binary(path) ->
        validate_file(path)

      nil ->
        materialize(opts)
    end
  end

  defp materialize(opts) do
    release_id =
      opts[:release_id] ||
        Mix.raise("--release-id is required; scope may not bind to an implicit release")

    out = opts[:out] || Mix.raise("--out is required; no repository artifact is written by default")

    Mix.Task.run("app.start")

    case Scope.materialize(release_id) do
      {:ok, artifact} ->
        bytes = ScopeArtifact.encode(artifact)
        File.mkdir_p!(Path.dirname(Path.expand(out)))
        File.write!(out, bytes)

        Mix.shell().info("""
        pilot scope materialized
          release: #{artifact["release"]["release_id"]}
          scope:   #{artifact["scope_content_sha256"]}
          seeds:   #{artifact["denominators"]["combined_seed_count"]}
          works:   #{artifact["denominators"]["total_work_count"]}
          edges:   #{artifact["denominators"]["relation_edge_count"]}
          output:  #{Path.expand(out)}

        The pilot_scope preflight gate remains blocked until this live artifact is reviewed.
        """)

      {:error, reason} ->
        Mix.raise("pilot scope refused: #{inspect(reason)}")
    end
  end

  defp validate_file(path) do
    artifact = path |> File.read!() |> ScopeArtifact.decode!()

    case ScopeArtifact.validate(artifact) do
      :ok ->
        Mix.shell().info(
          "pilot scope artifact valid; scope=#{artifact["scope_content_sha256"]}; " <>
            "release=#{artifact["release"]["release_id"]}"
        )

      {:error, errors} ->
        Mix.raise("pilot scope artifact invalid:\n  - " <> Enum.join(errors, "\n  - "))
    end
  end
end
