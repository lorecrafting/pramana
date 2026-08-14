defmodule Pramana.Embed do
  @moduledoc """
  Dense embeddings for retrieval chunks.

  Runs BGE-M3 in-process through Bumblebee and EXLA — the Phase 0 spike established
  that its XLM-RoBERTa-large backbone loads there for dense vectors, while the sparse
  and ColBERT heads ship as loose `.pt` files Bumblebee will not read. Dense is what
  hybrid retrieval needs first; the multi-vector ladder is in `docs/ELIXIR.md`.

  ## Measured throughput

  On an Apple M1 (8 cores, 16 GB), batch 16 at sequence length 320:

      1.60 s/chunk  ->  0.62 chunks/sec

  which is 4.5 hours for 阿含部 and **133 hours for the full corpus**. Sequence length
  matters more than batch size here: real chunks are p99 298 tokens, so the initial
  512-token padding wasted 40% of the compute, and batch 32 is *slower* than 16 because
  16 GB starts swapping.

  Local is fine for a division-sized proof and impractical for the whole canon. See
  `docs/EMBEDDING.md` for the hosted-versus-rented analysis and why a hosted embedding
  API is a reproducibility hazard rather than merely a cost question.

  ## Resumability

  Embedding is idempotent and resumable: a chunk with a vector from the current model
  is skipped. A run killed at 40% resumes at 40%.
  """

  import Ecto.Query

  alias Pramana.Corpus.Chunk
  alias Pramana.Repo

  @model "BAAI/bge-m3"
  @dims 1024
  # p99 of real chunk token lengths is 298; 320 covers everything with minimal padding.
  @sequence_length 320
  @batch_size 16

  @doc "The model identity recorded alongside every vector."
  @spec model() :: String.t()
  def model, do: @model

  @doc "Embedding dimensionality."
  @spec dims() :: pos_integer()
  def dims, do: @dims

  @doc """
  Builds an `Nx.Serving` for the embedding model.

  Loading and XLA compilation cost roughly 80 seconds, so a caller should build this
  once and reuse it across batches rather than per call.
  """
  @spec build_serving(keyword()) :: Nx.Serving.t()
  def build_serving(opts \\ []) do
    batch_size = Keyword.get(opts, :batch_size, @batch_size)
    sequence_length = Keyword.get(opts, :sequence_length, @sequence_length)

    {:ok, model_info} = Bumblebee.load_model({:hf, @model})
    {:ok, tokenizer} = Bumblebee.load_tokenizer({:hf, @model})

    Bumblebee.Text.text_embedding(model_info, tokenizer,
      compile: [batch_size: batch_size, sequence_length: sequence_length],
      defn_options: [compiler: EXLA],
      output_attribute: :hidden_state,
      output_pool: :mean_pooling,
      # Normalised vectors mean cosine distance reduces to inner product, which is
      # what the HNSW index is built for.
      embedding_processor: :l2_norm
    )
  end

  @doc """
  Embeds outstanding chunks.

  Options:
    * `:division`  — restrict to one Taishō 部, e.g. `"阿含部"`
    * `:limit`     — stop after this many chunks
    * `:serving`   — reuse a serving built by `build_serving/1`
    * `:on_batch`  — called with `%{done:, total:, elapsed_ms:}` after each batch

  Returns `{:ok, count}`.
  """
  @spec run(keyword()) :: {:ok, non_neg_integer()}
  def run(opts \\ []) do
    serving = Keyword.get_lazy(opts, :serving, fn -> build_serving(opts) end)
    batch_size = Keyword.get(opts, :batch_size, @batch_size)
    cap = Keyword.get(opts, :limit)
    total = min_or(pending_count(opts), cap)
    started = System.monotonic_time(:millisecond)

    done =
      Stream.repeatedly(fn -> pending_batch(batch_size, opts) end)
      |> Stream.take_while(&(&1 != []))
      # `:limit` is a TOTAL cap, not a per-batch one. Applying it per batch made
      # `--limit 32` embed every outstanding chunk, 32 at a time.
      |> Stream.transform(0, &cap_batch(&1, &2, cap))
      |> Enum.reduce(0, fn batch, acc ->
        embed_batch(serving, batch)
        done = acc + length(batch)

        if callback = opts[:on_batch] do
          callback.(%{
            done: done,
            total: total,
            elapsed_ms: System.monotonic_time(:millisecond) - started
          })
        end

        done
      end)

    {:ok, done}
  end

  @doc "How many chunks still need a vector from the current model."
  @spec pending_count(keyword()) :: non_neg_integer()
  def pending_count(opts \\ []), do: Repo.aggregate(pending_query(opts), :count)

  defp cap_batch(batch, taken, nil), do: {[batch], taken}
  defp cap_batch(_batch, taken, cap) when taken >= cap, do: {:halt, taken}
  defp cap_batch(batch, taken, cap), do: {[Enum.take(batch, cap - taken)], taken + length(batch)}

  defp min_or(value, nil), do: value
  defp min_or(value, cap), do: min(value, cap)

  defp pending_batch(batch_size, opts) do
    pending_query(opts)
    |> order_by([c], c.id)
    |> limit(^batch_size)
    |> select([c], %{id: c.id, content: c.content})
    |> Repo.all()
  end

  # Outstanding means: no vector, or a vector from a DIFFERENT model. Mixing vectors
  # from two models in one index silently corrupts search — every value is a valid
  # float, so nothing would fail loudly.
  defp pending_query(opts) do
    query =
      from c in Chunk,
        where: is_nil(c.embedding) or c.embedding_model != ^@model

    case opts[:division] do
      nil ->
        query

      division ->
        from c in query,
          join: t in assoc(c, :text),
          join: w in Pramana.Corpus.Work,
          on: w.id == t.work_id,
          where: w.division == ^division
    end
  end

  defp embed_batch(serving, batch) do
    results = Nx.Serving.run(serving, Enum.map(batch, & &1.content))
    now = DateTime.utc_now()

    Repo.transaction(fn ->
      batch
      |> Enum.zip(results)
      |> Enum.each(fn {chunk, %{embedding: vector}} ->
        from(c in Chunk, where: c.id == ^chunk.id)
        |> Repo.update_all(
          set: [
            embedding: Pgvector.new(Nx.to_flat_list(vector)),
            embedding_model: @model,
            embedded_at: now
          ]
        )
      end)
    end)
  end
end
