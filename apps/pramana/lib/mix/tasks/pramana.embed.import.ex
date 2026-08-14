defmodule Mix.Tasks.Pramana.Embed.Import do
  @shortdoc "Imports vectors produced on a GPU elsewhere"

  @moduledoc """
      mix pramana.embed.import --in /tmp/vectors.jsonl

  Verifies each row's `content_sha256` against the stored chunk before writing. A
  vector computed from text that has since changed is REJECTED rather than written,
  because it would attach a plausible-looking vector to the wrong passage and nothing
  would look wrong — it is still 1024 valid floats.
  """

  use Mix.Task

  alias Pramana.Embed.Transfer

  @switches [in: :string, model: :string]

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _, _} = OptionParser.parse(argv, switches: @switches)
    path = Keyword.fetch!(opts, :in)

    {:ok, r} = Transfer.import(path, opts)

    Mix.shell().info("""

    imported #{r.written} vector(s)
      hash mismatches (rejected): #{length(r.hash_mismatch)}
      wrong dimensions (rejected): #{length(r.bad_dims)}
      unknown chunk ids (rejected): #{length(r.unknown)}
    """)

    if r.hash_mismatch != [] do
      Mix.shell().error("""
      Rejected #{length(r.hash_mismatch)} vector(s) whose source text no longer matches.
      The corpus was re-baked after the export. Re-export and re-embed those chunks.
      Sample ids: #{inspect(Enum.take(r.hash_mismatch, 10))}
      """)
    end
  end
end
