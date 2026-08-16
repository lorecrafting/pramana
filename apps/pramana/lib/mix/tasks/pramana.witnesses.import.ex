defmodule Mix.Tasks.Pramana.Witnesses.Import do
  @shortdoc "Records each text's witness sigla from its own pinned TEI header"

  @moduledoc """
  Reads `<witness xml:id="wit1">【宋】</witness>` declarations from every CBETA file and
  stores them on the text.

      mix pramana.witnesses.import
      mix pramana.witnesses.import --work T0262

  ## Why this is per text and not a lookup table

  A `<rdg wit="#wit1">` refers to a witness declared in **that file's own header**, and
  the ids are not stable. Measured across all 2,471 files:

      wit1  38 distinct meanings — 宋 in 832 files, 明 in 375, 甲 in 322, 原 in 149
      wit2  33 distinct meanings
      only 4 of 23 ids mean one thing everywhere

  A global table would therefore report a Ming variant as a Song one in about a thousand
  works, in the tradition's own sigla, with nothing about the output looking wrong. The
  apparatus is only worth shipping if the witness attached to a reading is the right one.

  ## Why it does not re-bake

  Re-normalizing would delete and rebuild segments, which cascades to chunks and to
  `chunk_vectors` — 344,200 embeddings, and 40 minutes of GPU. This reads the pinned raw
  file and updates `texts.meta` in place. The source of truth is unchanged and the result
  is still checkable against `raw/`.
  """

  use Mix.Task

  import Ecto.Query

  alias Pramana.Acquire.CBETA
  alias Pramana.Acquire.Lockfile
  alias Pramana.Corpus.Text
  alias Pramana.Repo

  @switches [work: :string]

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _, _} = OptionParser.parse(argv, switches: @switches)

    texts = texts(opts[:work])
    if texts == [], do: Mix.raise("no CBETA texts matched")

    Mix.shell().info("#{length(texts)} text(s)")

    {updated, empty, unreadable} =
      Enum.reduce(texts, {0, 0, []}, fn text, {updated, empty, unreadable} ->
        case witnesses_for(text) do
          {:ok, map} when map_size(map) > 0 ->
            store!(text, map)
            {updated + 1, empty, unreadable}

          {:ok, _empty} ->
            {updated, empty + 1, unreadable}

          {:error, reason} ->
            {updated, empty, [{text.work_id, reason} | unreadable]}
        end
      end)

    report(updated, empty, unreadable)
  end

  defp texts(nil),
    do: Repo.all(from t in Text, where: t.source_id == "cbeta", order_by: t.work_id)

  defp texts(work),
    do: Repo.all(from t in Text, where: t.source_id == "cbeta" and t.work_id == ^work)

  # Only the header is parsed. Witness declarations live in `<teiHeader>`, and some files
  # are several megabytes of body that would be read for nothing.
  defp witnesses_for(text) do
    with {:ok, xml} <- read_raw(text) do
      header =
        case String.split(xml, "</teiHeader>", parts: 2) do
          [head | _] -> head
          _ -> xml
        end

      {:ok,
       ~r/<witness xml:id="([^"]+)">([^<]*)<\/witness>/
       |> Regex.scan(header)
       |> Map.new(fn [_, id, sigil] -> {id, sigil} end)}
    end
  end

  defp read_raw(text) do
    canon = text.witness_id
    number = String.replace_prefix(text.work_id, canon, "")
    volume = String.to_integer(text.volume || "0")
    path = Path.join([Lockfile.raw_dir(), text.source_id, CBETA.work_path(canon, volume, number)])

    case File.read(path) do
      {:ok, xml} -> {:ok, xml}
      {:error, reason} -> {:error, {:raw_unreadable, path, reason}}
    end
  end

  defp store!(text, map) do
    meta = Map.put(text.meta || %{}, "witnesses", map)

    from(t in Text, where: t.id == ^text.id)
    |> Repo.update_all(set: [meta: meta, updated_at: DateTime.utc_now()])
  end

  defp report(updated, empty, unreadable) do
    Mix.shell().info("""

    witness sigla imported
      texts updated:      #{updated}
      no declarations:    #{empty}
      unreadable:         #{length(unreadable)}
    """)

    for {work, reason} <- Enum.take(unreadable, 10) do
      Mix.shell().error("  FAILED #{work}: #{inspect(reason)}")
    end
  end
end
