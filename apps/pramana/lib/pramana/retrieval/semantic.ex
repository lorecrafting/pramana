defmodule Pramana.Retrieval.Semantic do
  @moduledoc """
  Dense vector search over chunk embeddings.

  Finds passages by meaning rather than by characters — the thing the bigram index
  structurally cannot do. Searching 佛性 will not lexically match a passage that says
  如來藏, even though the two terms name the same doctrine.

  Results carry the same span shape as everything else, so a semantic hit is verified
  by the same guard as a direct lookup (`CLAUDE.md` invariant #1). A chunk's URN is a
  range of real citation anchors, never an invented id.

  ## Honest limits

  - **Only chunks with a vector are searchable.** Coverage is partial while the corpus
    is being embedded, and `coverage/1` reports it rather than letting a caller mistake
    a small candidate pool for a small canon.
  - Vectors from a different model are excluded. Mixing models silently corrupts
    ranking, since every value is a valid float and nothing fails loudly.
  - BGE-M3 is multilingual but not trained on Classical Chinese specifically. Whether
    it is the right model here is an open question that the Phase 4 eval harness turns
    from opinion into measurement.
  """

  import Ecto.Query
  import Pgvector.Ecto.Query

  alias Pramana.Corpus
  alias Pramana.Corpus.Chunk
  alias Pramana.Corpus.Text
  alias Pramana.Corpus.Work
  alias Pramana.Embed
  alias Pramana.Repo

  @default_limit 20
  @max_limit 200

  @known_opts [
    :limit,
    :mode,
    :origin,
    :role,
    :division,
    :work_id,
    :juan,
    :exclude_origin,
    :serving,
    :lexical_only,
    :semantic_only,
    :sequence_length,
    :batch_size
  ]

  @type opts :: [
          limit: pos_integer(),
          origin: String.t() | [String.t()],
          role: String.t() | [String.t()],
          division: String.t(),
          work_id: String.t(),
          exclude_origin: String.t() | [String.t()],
          serving: Nx.Serving.t()
        ]

  @doc """
  Searches by meaning.

  Requires an `Nx.Serving` to embed the query — pass `:serving`, or let it build one
  (which costs ~80 s of model load, so a long-lived caller should build it once).
  """
  @spec search(String.t(), opts()) :: {:ok, map()} | {:error, atom()}
  def search(query, opts \\ [])

  def search(query, opts) when is_binary(query) do
    validate_opts!(opts)

    case String.trim(query) do
      "" -> {:error, :empty_query}
      trimmed -> {:ok, run(trimmed, opts)}
    end
  end

  def search(_, _), do: {:error, :bad_query}

  @doc false
  def validate_opts!(opts) do
    case Keyword.keys(opts) -- @known_opts do
      [] -> :ok
      unknown -> raise ArgumentError, "unknown search option(s): #{inspect(unknown)}"
    end
  end

  @doc """
  Searches with an already-computed query vector.

  Useful when the caller batches queries, and for tests that must not load a model.
  """
  @spec search_vector([float()], opts()) :: map()
  def search_vector(vector, opts \\ []) do
    limit = opts |> Keyword.get(:limit, @default_limit) |> min(@max_limit) |> max(1)
    embedding = Pgvector.new(vector)

    results =
      Chunk
      |> where([c], not is_nil(c.embedding) and c.embedding_model == ^Embed.model())
      |> join(:inner, [c], t in Text, on: t.id == c.text_id)
      |> join(:inner, [c, t], w in Work, on: w.id == t.work_id)
      |> apply_filters(opts)
      # <#> is negative inner product in pgvector; on unit vectors that orders
      # identically to cosine similarity, and it is what the HNSW index was built for.
      |> order_by([c], max_inner_product(c.embedding, ^embedding))
      |> limit(^limit)
      |> select([c, t, w], %{
        chunk: c,
        work: w,
        text: t,
        score: max_inner_product(c.embedding, ^embedding)
      })
      |> Repo.all()
      |> Enum.map(&to_result/1)

    %{results: results, total: length(results), model: Embed.model()}
  end

  @doc """
  How much of the corpus is actually searchable by vector.

  Reported alongside results so partial coverage is never mistaken for a small canon.
  """
  @spec coverage(keyword()) :: map()
  def coverage(opts \\ []) do
    base =
      from c in Chunk,
        join: t in Text,
        on: t.id == c.text_id,
        join: w in Work,
        on: w.id == t.work_id

    base = apply_filters(base, opts)

    total = Repo.aggregate(base, :count)
    embedded = Repo.aggregate(where(base, [c], not is_nil(c.embedding)), :count)

    %{
      embedded: embedded,
      total: total,
      percent: if(total > 0, do: Float.round(100 * embedded / total, 1), else: 0.0)
    }
  end

  defp run(query, opts) do
    serving = Keyword.get_lazy(opts, :serving, fn -> Embed.build_serving(opts) end)
    %{embedding: vector} = embed_query(serving, query)

    vector
    |> Nx.to_flat_list()
    |> search_vector(opts)
    |> Map.put(:query, query)
  end

  # A supervised serving is referenced by NAME and driven with batched_run/2, which
  # shares one loaded model across callers. An inline serving struct is run directly.
  # Accepting both means a caller can pass Pramana.Embed.Serving.name() without caring
  # which it got.
  defp embed_query(serving, query) when is_atom(serving),
    do: Nx.Serving.batched_run(serving, query)

  defp embed_query(serving, query), do: Nx.Serving.run(serving, query)

  defp apply_filters(query, opts) do
    query
    |> filter_in(opts[:origin], :composition_origin)
    |> filter_in(opts[:role], :text_role)
    |> filter_not_in(opts[:exclude_origin], :composition_origin)
    |> filter_eq(opts[:division], :division)
    |> filter_work(opts[:work_id])
  end

  defp filter_in(query, nil, _field), do: query

  defp filter_in(query, value, field),
    do: where(query, [_c, _t, w], field(w, ^field) in ^List.wrap(value))

  defp filter_not_in(query, nil, _field), do: query

  defp filter_not_in(query, value, field) do
    values = List.wrap(value)
    where(query, [_c, _t, w], field(w, ^field) not in ^values or is_nil(field(w, ^field)))
  end

  defp filter_eq(query, nil, _field), do: query
  defp filter_eq(query, value, field), do: where(query, [_c, _t, w], field(w, ^field) == ^value)

  defp filter_work(query, nil), do: query
  defp filter_work(query, work_id), do: where(query, [_c, t], t.work_id == ^work_id)

  defp to_result(%{chunk: chunk, score: score}) do
    %{
      urn: chunk.urn,
      content: chunk.content,
      # pgvector's <#> returns NEGATIVE inner product, so flip it back to a similarity
      # where larger means closer. Reporting the raw value would invert the ranking to
      # anyone reading it.
      similarity: -score,
      juan: chunk.juan,
      segment_count: chunk.segment_count,
      span: span_for(chunk)
    }
  end

  # A chunk's URN is a range of real anchors, so the span resolves through the ordinary
  # path and stays guard-verifiable.
  defp span_for(chunk) do
    case Corpus.resolve(chunk.urn) do
      {:ok, span} -> span
      {:error, _} -> nil
    end
  end
end
