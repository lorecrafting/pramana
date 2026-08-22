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
  alias Pramana.Corpus.ChunkVector
  alias Pramana.Repo

  # Base model plus the Tibetan LoRA adapter trained by `priv/embed/modal_train_tibetan.py`.
  # The suffix is not decoration: vectors from the adapted model are NOT comparable with
  # stock bge-m3 vectors, and this string is the only thing that tells them apart. Changing
  # it makes every existing vector outstanding, which is exactly right — adopting a
  # different model means re-embedding the corpus, not mixing two in one index.
  #
  # Measured before adoption, related-vs-unrelated gap on adjacent chunks of one work:
  # bo +0.0098 -> +0.1883 (19x), pli +0.0693 -> +0.1405, lzh +0.0845 -> +0.1903. The base
  # model rated an adjacent Tibetan chunk at 0.984 and an unrelated one at 0.974.
  # REVERTED to stock. The Tibetan LoRA (see docs/STATUS.md) posted excellent proxy
  # numbers — 19x discrimination gap, 3.4x in-batch top-1 — and then scored 0/20 on
  # Tibetan retrieval against the real corpus, down from 7/20. Overall 79.5% -> 70.7%.
  # The adapter, its training script and its pair set are kept; the vectors are not.
  @model "BAAI/bge-m3"

  # WHERE THE WEIGHTS COME FROM, which is a different question from what `@model` records.
  #
  # Conflating the two broke query embedding: `@model` is written into
  # `chunk_vectors.embedding_model` to tell adapted vectors from stock ones, and it was
  # ALSO the HuggingFace repo id Bumblebee loads — so renaming it for the first purpose
  # sent Bumblebee looking for a repository that does not exist.
  #
  # The tempting fix is worse than the bug: keep loading `BAAI/bge-m3` and record the
  # composite name. Then QUERIES are embedded with the stock model while the documents are
  # adapted, which is precisely the mixing `embedding_model` exists to prevent — and it
  # fails silently, because every value is still a valid float.
  #
  # So the local weights must BE the adapted model. `priv/models/<name>` is produced by
  # `mix pramana.embed.fetch_model`, which merges the adapter into the base on the GPU and
  # brings the result back.
  @local_model_dir "priv/models/bge-m3-tibetan-lora-v1"

  # The stock model, still the base for everything and the fallback when no adapted
  # weights are present locally.
  @base_model "BAAI/bge-m3"
  @dims 1024

  # The token window vectors are expected to carry. MUST match `MAX_LENGTH` in
  # `priv/embed/modal_embed.py` and `priv/embed/embed_gpu.py` — those produce the vectors,
  # and each now reports the window it used so a mismatch is recorded rather than assumed.
  # Not a free parameter: `Pramana.Chunk.Builder`'s per-script chunk sizes are derived FROM
  # this number, so changing it without re-deriving them re-opens the truncation defect
  # that once left 76.2% of Pāli vectors describing a prefix.
  @max_length 320
  # p99 of real chunk token lengths is 298; 320 covers everything with minimal padding.
  @sequence_length 320
  @batch_size 16

  @doc "The model identity recorded alongside every vector."
  @spec model() :: String.t()
  def model, do: @model

  @doc "Embedding dimensionality."
  @spec dims() :: pos_integer()
  def dims, do: @dims

  @doc "The token window vectors are expected to carry."
  @spec max_length() :: pos_integer()
  def max_length, do: @max_length

  @doc """
  Where the weights are loaded from, and whether they match what `model/0` records.

  Returns `{:ok, source}` or `{:error, :adapted_weights_missing}`. The error is the
  important case: `@model` says these vectors are adapted, so embedding a query with the
  stock model would compare a stock query against adapted documents and rank by noise
  without failing.
  """
  @spec weights_source() :: {:ok, {:local, String.t()} | {:hf, String.t()}} | {:error, atom()}
  def weights_source do
    cond do
      not adapted?() -> {:ok, {:hf, @base_model}}
      File.dir?(@local_model_dir) -> {:ok, {:local, @local_model_dir}}
      true -> {:error, :adapted_weights_missing}
    end
  end

  @doc "Whether `model/0` names an adapted model rather than the stock one."
  @spec adapted?() :: boolean()
  def adapted?, do: @model != @base_model

  @doc "Where adapted weights are expected on disk."
  @spec local_model_dir() :: String.t()
  def local_model_dir, do: @local_model_dir

  @doc """
  Builds an `Nx.Serving` for the embedding model.

  Loading and XLA compilation cost roughly 80 seconds, so a caller should build this
  once and reuse it across batches rather than per call.
  """
  @spec build_serving(keyword()) :: Nx.Serving.t()
  def build_serving(opts \\ []) do
    batch_size = Keyword.get(opts, :batch_size, @batch_size)
    sequence_length = Keyword.get(opts, :sequence_length, @sequence_length)

    # Raises rather than falling back to the stock model. A serving that quietly embeds
    # queries with different weights from the documents returns confident nonsense, and no
    # check downstream would catch it.
    source =
      case weights_source() do
        {:ok, source} ->
          source

        {:error, :adapted_weights_missing} ->
          raise """
          #{@model} is the recorded model, but no adapted weights are present at
          #{@local_model_dir}.

          Embedding a query with the stock model against adapted document vectors ranks by
          noise and fails silently. Run `mix pramana.embed.fetch_model` to bring the merged
          weights back, or set `@model` to #{@base_model} and re-embed the corpus.
          """
      end

    {:ok, model_info} = Bumblebee.load_model(source)
    # The tokenizer is unchanged by LoRA — only the weights move — so it always comes from
    # the base repository, which also keeps the merged directory to weights alone.
    {:ok, tokenizer} = Bumblebee.load_tokenizer({:hf, @base_model})

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
  A serving tuned for embedding ONE query at a time.

  A serving compiled for batch 16 pads a single query to 16 rows and does 16× the work:
  measured at 10.6 s for one short query, which is unusable interactively. Batch 1 with
  a shorter sequence length is the query-time configuration; the batch-16 serving stays
  for bulk indexing, where throughput is what matters.
  """
  @spec build_query_serving(keyword()) :: Nx.Serving.t()
  def build_query_serving(opts \\ []) do
    build_serving(
      Keyword.merge(
        [batch_size: 1, sequence_length: Keyword.get(opts, :sequence_length, 128)],
        opts
      )
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

  @doc """
  The outstanding-chunk query, for `Pramana.Embed.Transfer` to export.

  Exposed rather than duplicated: two definitions of "outstanding" would drift, and the
  drift would show up as chunks silently never embedded.
  """
  @spec pending_query_for_export(keyword()) :: Ecto.Query.t()
  def pending_query_for_export(opts \\ []), do: pending_query(opts)

  defp cap_batch(batch, taken, nil), do: {[batch], taken}
  defp cap_batch(_batch, taken, cap) when taken >= cap, do: {:halt, taken}
  defp cap_batch(batch, taken, cap), do: {[Enum.take(batch, cap - taken)], taken + length(batch)}

  defp min_or(value, nil), do: value
  defp min_or(value, cap), do: min(value, cap)

  defp pending_batch(batch_size, opts) do
    pending_query(opts)
    |> order_by([v], v.id)
    |> limit(^batch_size)
    |> select([v], %{id: v.id, content: v.content})
    |> Repo.all()
  end

  # Outstanding means: no vector, a vector from a DIFFERENT model, or one taken at a
  # different token WINDOW. Mixing any of those in one index silently corrupts search —
  # every value is a valid float, so nothing would fail loudly.
  #
  # The window matters for the same reason the model does: a chunk longer than
  # `max_length` is embedded as a prefix, so the same chunk at 320 and at 512 yields two
  # vectors describing different amounts of text. Measured 2026-08-20, 6.3% of Pāli
  # chunks exceed 320. A NULL window is left alone rather than treated as stale: it means
  # the producer did not report one, and re-embedding the corpus to learn a number nobody
  # recorded would be expensive guesswork.
  defp pending_query(opts) do
    query =
      from v in ChunkVector,
        where:
          is_nil(v.embedding) or v.embedding_model != ^@model or
            (not is_nil(v.embedding_max_length) and v.embedding_max_length != ^@max_length)

    query
    |> filter_kind(opts[:kind])
    |> filter_division(opts[:division])
  end

  # Re-embedding ONE source, whatever its vectors' current state. `pending_query/1` asks
  # "what is missing"; this asks "what must be redone", which is a different question and
  # the one a window-size or chunk-size experiment needs. Kept separate so a normal run
  # can never widen into re-embedding a source that was already done.
  @doc false
  @spec redo_query_for_export(keyword()) :: Ecto.Query.t()
  def redo_query_for_export(opts) do
    source = Keyword.fetch!(opts, :source)

    from v in ChunkVector,
      join: c in Chunk,
      on: c.id == v.chunk_id,
      join: t in assoc(c, :text),
      where: t.source_id == ^source
  end

  # A vector kind is worth embedding separately: `source` vectors are the corpus, and a
  # run that meant to fill in only the new translation vectors should not silently
  # re-embed 299,317 Chinese passages.
  defp filter_kind(query, nil), do: query
  defp filter_kind(query, kind), do: from(v in query, where: v.kind == ^kind)

  defp filter_division(query, nil), do: query

  defp filter_division(query, division) do
    from v in query,
      join: c in Chunk,
      on: c.id == v.chunk_id,
      join: t in assoc(c, :text),
      join: w in Pramana.Corpus.Work,
      on: w.id == t.work_id,
      where: w.division == ^division
  end

  defp embed_batch(serving, batch) do
    results = Nx.Serving.run(serving, Enum.map(batch, & &1.content))
    now = DateTime.utc_now()

    Repo.transaction(fn ->
      batch
      |> Enum.zip(results)
      |> Enum.each(fn {chunk, %{embedding: vector}} ->
        from(v in ChunkVector, where: v.id == ^chunk.id)
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
