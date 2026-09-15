defmodule Mix.Tasks.Pramana.Translate.Export do
  @shortdoc "Exports passages for generation on a rented GPU"

  @moduledoc """
      mix pramana.translate.export --out /tmp/passages.jsonl --work T0026 --limit 200
      mix pramana.translate.export --covered-by patton --limit 300 --out /tmp/bakeoff.jsonl

  Writes one `{id, sha256, content, target_lang}` per line — the input
  `priv/embed/modal_translate.py` reads. Bring the renderings back with
  `mix pramana.translate.import`.

  **`--covered-by` is what a model bake-off wants.** It selects only chunks a named human
  translator already renders, so every generated passage has a human rendering to be
  blinded against in `mix pramana.translate.bakeoff` — and so `mix pramana.recall
  --renderings` can score the arms on the same passages the human is scored on.

  The hash travels with the text so the import can prove the rendering still describes
  the passage it claims to. `docs/PLAN.md` § E1.
  """

  use Mix.Task

  alias Pramana.Translate.Transfer

  @switches [
    out: :string,
    work: :string,
    works: :string,
    covered_by: :string,
    limit: :integer,
    lang: :string,
    glossary: :boolean
  ]

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _} = OptionParser.parse!(argv, strict: @switches)
    path = Keyword.get(opts, :out, "/tmp/pramana_passages.jsonl")

    {:ok, info} = Transfer.export(path, opts)

    if info.chunks == 0 do
      Mix.raise("no chunks matched — nothing to translate, and an empty tranche is not a run")
    end

    Mix.shell().info("""

    exported #{info.chunks} passage(s)
      file:   #{info.path}  (#{Float.round(info.bytes / 1_000_000, 2)} MB)
      target: #{info.lang}

    Next:
      modal volume put pramana-translate #{info.path} /passages.jsonl
      modal run priv/embed/modal_translate.py --arm mitra
      modal volume get pramana-translate /renderings-mitra.jsonl /tmp/renderings-mitra.jsonl
      mix pramana.translate.import --in /tmp/renderings-mitra.jsonl --translator-id model:mitra
    """)
  end
end
