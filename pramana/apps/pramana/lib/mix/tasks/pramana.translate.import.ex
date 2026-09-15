defmodule Mix.Tasks.Pramana.Translate.Import do
  @shortdoc "Stores generated renderings as tier-1 translations"

  @moduledoc """
      mix pramana.translate.import --in /tmp/renderings-mitra.jsonl --translator-id model:mitra

  Reads what `priv/embed/modal_translate.py` produced and stores it as `tier: "t1"`,
  `method: "llm"` renderings anchored to the chunks they translate.

  **What is stored here can never be cited as source.** `CLAUDE.md` invariant #8:
  generated text is a layer over a source anchor, never a top-level URN, and
  `Pramana.Guard` rejects any quote resolving to `method != human` presented as
  canonical. `--translator-id` is the identity a reader sees beside the text, and it is
  given rather than derived because comparing arms means holding several at once.

  A row whose `sha256` no longer matches its chunk is **rejected and counted**, not
  stored: the passage may have been re-chunked since export, and a rendering of text that
  is no longer there would attach to whatever now occupies that id.
  """

  use Mix.Task

  alias Pramana.Translate.Transfer

  @switches [in: :string, translator_id: :string, lang: :string]

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _} = OptionParser.parse!(argv, strict: @switches)

    path = opts[:in] || Mix.raise("--in is required")
    translator_id = opts[:translator_id] || Mix.raise("--translator-id is required")
    File.exists?(path) || Mix.raise("no such file: #{path}")

    {:ok, info} = Transfer.import(path, translator_id, opts)

    Mix.shell().info("""

    imported renderings as #{translator_id}
      read:       #{info.read}
      written:    #{info.written}  (tier t1, method llm — never citable as source)
      #{gap("sha256 mismatch", info.mismatched, "re-chunked since export; NOT stored")}
      #{gap("empty", info.empty, "the model returned nothing; NOT stored")}

    Next:
      mix pramana.vectors --translations --source cbeta --lang en
      mix pramana.embed
      PRAMANA_EMBEDDING=1 mix pramana.recall --renderings --to cbeta.T
    """)
  end

  # Printed even at zero. A rejection count that appears only when non-zero reads as
  # "there were none" when the line is simply absent — rules 22, 44 and 54: publish the
  # gap, not just the total.
  defp gap(label, count, why) do
    "#{String.pad_trailing(label <> ":", 12)}#{count}  (#{why})"
  end
end
