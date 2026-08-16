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

  alias Pramana.Corpus.ChunkVector
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
      Repo.all(from v in ChunkVector, select: {v.id, v.content_sha256}) |> Map.new()

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

  # Validation and writing are separated deliberately. Every row is checked first, and
  # only the survivors are written — in ONE statement per batch.
  #
  # The previous version issued a `Repo.update_all` per row: 299,317 separate UPDATEs for
  # a full corpus, each triggering incremental HNSW index maintenance. Measured
  # 2026-08-14, that made storing the vectors slower than computing them — 88 minutes of
  # import against 34 minutes of GPU. The batching cost nothing in safety: the hash check
  # that rejects a vector whose text has changed happens before any row is written, and
  # rejected rows never reach the statement.
  defp apply_batch(batch, hashes, dims, model, now, acc) do
    {acc, writable} =
      Enum.reduce(batch, {acc, []}, fn row, {acc, writable} ->
        id = row["id"]
        vector = row["embedding"]

        cond do
          not Map.has_key?(hashes, id) ->
            {%{acc | unknown: [id | acc.unknown]}, writable}

          length(vector) != dims ->
            {%{acc | bad_dims: [id | acc.bad_dims]}, writable}

          # The vector describes text that no longer exists at this chunk. Writing it
          # would attach a plausible-looking vector to the wrong passage, and nothing
          # about the result would look wrong — it is still 1024 valid floats.
          Map.get(hashes, id) != row["sha256"] ->
            {%{acc | hash_mismatch: [id | acc.hash_mismatch]}, writable}

          true ->
            {acc, [{id, vector} | writable]}
        end
      end)

    write!(writable, model, now)
    %{acc | written: acc.written + length(writable)}
  end

  defp write!([], _model, _now), do: :ok

  defp write!(rows, model, now) do
    # `$1`/`$2` are the model and timestamp; each row then contributes an id and a vector
    # literal. 1,000 rows is 2,002 parameters, well inside Postgres's 65,535 limit.
    {placeholders, params} =
      rows
      |> Enum.with_index()
      |> Enum.map_reduce([], fn {{id, vector}, i}, params ->
        n = 3 + i * 2
        {"($#{n}::bigint, $#{n + 1}::text)", [vector_literal(vector), id | params]}
      end)

    sql = """
    UPDATE chunk_vectors AS cv
    SET embedding = v.embedding::vector,
        embedding_model = $1,
        embedded_at = $2
    FROM (VALUES #{Enum.join(placeholders, ", ")}) AS v(id, embedding)
    WHERE cv.id = v.id
    """

    Repo.query!(sql, [model, now | Enum.reverse(params)])
    :ok
  end

  # pgvector parses its own text form, so the vector crosses as one parameter rather
  # than 1,024.
  defp vector_literal(vector), do: "[" <> Enum.map_join(vector, ",", &to_string/1) <> "]"
end
