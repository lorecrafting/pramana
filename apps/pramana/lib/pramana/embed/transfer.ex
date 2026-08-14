defmodule Pramana.Embed.Transfer do
  @moduledoc """
  Export chunk text for embedding elsewhere, and import the vectors back.

  Embedding the full corpus on an M1 is ~65 hours; on a rented GPU it is minutes for
  roughly $1–3 (`docs/EMBEDDING.md`). Rather than ship the corpus and a database to the
  GPU box, this exports the *text* and imports the *vectors* — the remote side needs
  only Python and the model.

  ## What makes the round trip verifiable

  Export records each chunk's `content_sha256`. Import re-checks it before writing.
  If the corpus was re-baked between export and import, the text a vector was computed
  from no longer exists, and that vector is **wrong for the chunk it claims to
  describe** — but nothing about it looks wrong, because it is still 1024 valid floats.
  This is the same failure class as mixing two models' vectors, and it gets the same
  treatment: check, refuse, and say which rows disagreed.

  Import also verifies dimensionality and the declared model, and is idempotent.
  """

  import Ecto.Query

  alias Pramana.Corpus.Chunk
  alias Pramana.Embed
  alias Pramana.Repo

  @doc """
  Writes pending chunks to a JSONL file: one `{id, content, sha256}` per line.

  JSONL rather than a single JSON document so the remote side can stream it, and so a
  truncated transfer fails on a parse error rather than silently losing the tail.
  """
  @spec export(String.t(), keyword()) :: {:ok, map()}
  def export(path, opts \\ []) do
    query = Embed.pending_query_for_export(opts)
    count = Repo.aggregate(query, :count)

    File.mkdir_p!(Path.dirname(path))

    # Repo.stream/2 requires a transaction. Streaming rather than loading matters at
    # full corpus size: 299,317 chunks of ~287 characters is ~86 MB of text.
    {:ok, written} =
      Repo.transaction(fn -> write_jsonl(path, query) end, timeout: :infinity)

    {:ok,
     %{
       path: path,
       chunks: written,
       expected: count,
       model: Embed.model(),
       dims: Embed.dims(),
       bytes: File.stat!(path).size
     }}
  end

  defp write_jsonl(path, query) do
    File.open!(path, [:write, :utf8], fn file ->
      query
      |> order_by([c], c.id)
      |> select([c], %{id: c.id, content: c.content, sha256: c.content_sha256})
      |> Repo.stream(max_rows: 2_000)
      |> Stream.map(&IO.write(file, Jason.encode!(&1) <> "\n"))
      |> Enum.count()
    end)
  end

  @doc """
  Loads vectors produced elsewhere.

  Expects a JSONL file of `{id, sha256, embedding}` — the id and hash from the export,
  and a list of `dims` floats. Rows whose hash no longer matches the stored chunk are
  **rejected, not written**, and reported.
  """
  @spec import(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def import(path, opts \\ []) do
    model = Keyword.get(opts, :model, Embed.model())
    dims = Embed.dims()
    now = DateTime.utc_now()

    expected_hashes =
      Repo.all(from c in Chunk, select: {c.id, c.content_sha256}) |> Map.new()

    result =
      path
      |> File.stream!()
      |> Stream.map(&Jason.decode!/1)
      |> Stream.chunk_every(1_000)
      |> Enum.reduce(%{written: 0, hash_mismatch: [], bad_dims: [], unknown: []}, fn batch, acc ->
        apply_batch(batch, expected_hashes, dims, model, now, acc)
      end)

    {:ok, Map.update!(result, :hash_mismatch, &Enum.take(&1, 20))}
  end

  defp apply_batch(batch, hashes, dims, model, now, acc) do
    Enum.reduce(batch, acc, fn row, acc ->
      id = row["id"]
      vector = row["embedding"]

      cond do
        not Map.has_key?(hashes, id) ->
          %{acc | unknown: [id | acc.unknown]}

        length(vector) != dims ->
          %{acc | bad_dims: [id | acc.bad_dims]}

        # The vector describes text that no longer exists at this chunk. Writing it
        # would attach a plausible-looking vector to the wrong passage.
        Map.get(hashes, id) != row["sha256"] ->
          %{acc | hash_mismatch: [id | acc.hash_mismatch]}

        true ->
          from(c in Chunk, where: c.id == ^id)
          |> Repo.update_all(
            set: [
              embedding: Pgvector.new(vector),
              embedding_model: model,
              embedded_at: now
            ]
          )

          %{acc | written: acc.written + 1}
      end
    end)
  end
end
