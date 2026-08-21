defmodule Mix.Tasks.Pramana.Embed.Export do
  @shortdoc "Exports pending chunk text for embedding on a GPU elsewhere"

  @moduledoc """
      mix pramana.embed.export --out /tmp/pramana_chunks.jsonl
      mix pramana.embed.export --division 阿含部 --out /tmp/agama.jsonl
      mix pramana.embed.export --source sc --out /tmp/pali.jsonl   # re-embed one source

  `--source` exports every vector row of that source **regardless of whether it already
  has an embedding**, which is what a re-embedding experiment needs. Without it, only
  rows that are missing a vector or carry another model's are exported.

  Writes one `{id, content, sha256}` per line. Send this to the GPU box, run
  `priv/embed/embed_gpu.py`, and bring the vectors back with
  `mix pramana.embed.import`.

  The hash travels with the text so import can prove the vector still describes the
  chunk it claims to. See `docs/EMBEDDING.md`.
  """

  use Mix.Task

  alias Pramana.Embed.Transfer

  @switches [out: :string, division: :string, source: :string]

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _, _} = OptionParser.parse(argv, switches: @switches)
    path = Keyword.get(opts, :out, "priv/embed/chunks.jsonl")

    {:ok, info} = Transfer.export(path, opts)

    Mix.shell().info("""

    exported #{info.chunks} chunk(s)
      file:   #{info.path}  (#{Float.round(info.bytes / 1_000_000, 1)} MB)
      model:  #{info.model}
      dims:   #{info.dims}

    Next, on the GPU host:
      python priv/embed/embed_gpu.py --in chunks.jsonl --out vectors.jsonl
    Then back here:
      mix pramana.embed.import --in vectors.jsonl
    """)
  end
end
