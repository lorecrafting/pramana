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
  alias Pramana.Corpus.ChunkVector
  alias Pramana.Corpus.Source
  alias Pramana.Corpus.Text
  alias Pramana.Corpus.Work
  alias Pramana.Embed
  alias Pramana.Repo

  @default_limit 20
  @max_limit 200

  # Ceiling on how far an iterative scan will walk before giving up. Generous enough for
  # a division holding a few percent of the corpus, bounded so a filter matching almost
  # nothing degrades to a slow query rather than a full scan of 299k vectors.
  @max_scan_tuples 200_000

  # A chunk may carry a source vector and one translation vector per translator, so the
  # ANN scan must return more rows than the caller asked for chunks. Four is comfortably
  # above the current maximum (source + 2 translators on any shared anchor).
  @vector_overfetch 4

  @known_opts [
    :limit,
    :vector_kinds,
    :vector_lang,
    :balance,
    :per_tradition,
    :source_id,
    :redistributable_only,
    :license_class,
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

    validate_limit!(opts[:limit])
  end

  @doc "The largest number of results this retriever will return."
  @spec max_limit() :: pos_integer()
  def max_limit, do: @max_limit

  # A limit above the maximum used to be clamped SILENTLY, and it cost a published claim:
  # a probe asked for `limit: 500`, got 200, and the finding was written up as "absent
  # from the top 500" when it meant the top 200. The conclusion happened to survive; the
  # label did not. This is the same category as an unknown option being ignored, and it
  # gets the same answer — the caller is told rather than quietly given something else.
  #
  # Callers that legitimately take user input clamp at their own boundary, where the cap
  # is part of the published contract: `PramanaWeb.MCP.Tools.Search` documents "capped at
  # 200" and enforces it before calling.
  defp validate_limit!(nil), do: :ok

  defp validate_limit!(limit) when is_integer(limit) and limit > @max_limit do
    raise ArgumentError,
          "limit #{limit} exceeds the maximum of #{@max_limit}; ask for at most " <>
            "#{@max_limit}, and clamp at your own boundary if the value came from a user"
  end

  defp validate_limit!(_limit), do: :ok

  @doc """
  Searches with an already-computed query vector.

  Useful when the caller batches queries, and for tests that must not load a model.
  """
  @spec search_vector([float()], opts()) :: map()
  def search_vector(vector, opts \\ [])

  # RETRIEVE per tradition, rather than filtering a globally-ranked list afterwards.
  #
  # `balance: :tradition` interleaves the traditions PRESENT IN THE POOL, which cannot help
  # when the pool has only one. Measured on "What are the four noble truths?": the top 30
  # is 100% Pāli, the first Tibetan result is at **rank 142**, and Pāli holds **193 of 200**
  # slots — while 250 Tibetan chunks contain the term and carry an English rendering. All
  # 55,135 English rendering vectors compete in one space, and for a doctrinal question the
  # Pāli canon's English is the most direct statement of that doctrine. Balancing is a
  # ranking remedy applied to a retrieval problem; it operates one stage too late.
  #
  # So each tradition gets its own search and its own quota, and the results interleave.
  # One query per tradition rather than one overall — affordable now that `coverage/1` is
  # not adding ~1.1 s to each.
  #
  # Opt-in for the same reason `balance` is: right for "what does the canon say about X",
  # wrong for "find the passage I just quoted", where the tradition is not in doubt and
  # forcing three canons into the results only pushes the answer down.
  #
  # That was an assertion when it was written. It is now measured over the full 1,400-case
  # gold set (3h09m), and it holds — the trade is about 11:1 against:
  #
  #     retrieval / pali      53.3% -> 42.7%   -16 cases
  #     retrieval / tibetan   31.3% -> 21.9%    -6 cases
  #     topical  / tibetan     0.0% -> 22.2%    +2 cases
  #     answered from any canon  72.7% -> 54.5%
  #
  # `retrieval/tibetan` is the surprising one and worth keeping in mind before trying this
  # again: guaranteeing Tibetan a third of the slots made Tibetan pinpoint retrieval WORSE.
  # More room only helps a canon whose internal ranking can use it, and Tibetan's mean
  # pairwise cosine is 0.9727 (#10) — the extra slots fill with near-ties. See
  # docs/STATUS.md.
  def search_vector(vector, opts) when is_list(opts) do
    if opts[:per_tradition],
      do: per_tradition_search(vector, opts),
      else: single_search(vector, opts)
  end

  # Equal slots per tradition. That is a CLAIM — that each canon deserves equal voice on a
  # doctrinal question — and not an inference from corpus size, which is 2,471 Chinese,
  # 8,442 Pāli and 4,575 Tibetan works. Stated here so it can be argued with.
  #
  # Read from the CORPUS, not from a list in this module. The hand-written version named
  # 4 of the 8 registered sources, and a source in no group is not ranked lower but
  # INVISIBLE: it is never queried, so it returns nothing and says nothing. Two instances,
  # one live and one waiting — `local-huang-nianzu-jie` holds 848 embedded chunks that
  # per-tradition search could not reach, and `sat` (Taishō 56–84) would have been
  # unreachable the day #14 unblocks. Both are the failure `Pramana.Coverage` exists to
  # prevent, and neither would have raised.
  #
  # `sources` is six rows. Grouping them per search is a sub-millisecond lookup against a
  # path already measured at ~36 s per eval case, and it is the only version that cannot
  # drift: a source that exists is grouped BECAUSE it exists, rather than because someone
  # remembered to add it here. That is the same move as #43's deletion of `@filter_keys` —
  # the thing that had to be remembered is gone.
  defp tradition_groups do
    Repo.all(from s in Source, select: {s.tradition, s.id})
    |> Enum.group_by(fn {tradition, _id} -> tradition end, fn {_t, id} -> id end)
  end

  defp per_tradition_search(vector, opts) do
    limit = opts |> Keyword.get(:limit, @default_limit) |> min(@max_limit) |> max(1)

    per_group =
      tradition_groups()
      |> Map.values()
      |> Enum.map(fn sources ->
        vector
        |> single_search(Keyword.merge(opts, source_id: sources, limit: limit))
        |> Map.get(:results)
      end)
      |> Enum.reject(&(&1 == []))

    results = per_group |> interleave() |> Enum.take(limit)

    %{results: results, total: length(results), model: Embed.model()}
  end

  defp single_search(vector, opts) do
    limit = opts |> Keyword.get(:limit, @default_limit) |> min(@max_limit) |> max(1)
    embedding = Pgvector.new(vector)

    query =
      ChunkVector
      |> where([v], not is_nil(v.embedding) and v.embedding_model == ^Embed.model())
      |> filter_vector_kinds(opts[:vector_kinds])
      |> filter_vector_lang(opts[:vector_lang])
      |> join(:inner, [v], c in Chunk, as: :chunk, on: c.id == v.chunk_id)
      |> join(:inner, [v, c], t in Text, as: :text, on: t.id == c.text_id)
      |> join(:inner, [v, c, t], w in Work, as: :work, on: w.id == t.work_id)
      |> apply_filters(opts)
      # <#> is negative inner product in pgvector; on unit vectors that orders
      # identically to cosine similarity, and it is what the HNSW index was built for.
      |> order_by([v], max_inner_product(v.embedding, ^embedding))
      # Over-fetch, because several vectors of the SAME chunk can match — a passage and
      # its English rendering are both in the index — and collapsing them afterwards
      # would otherwise return fewer chunks than asked for.
      |> limit(^(limit * @vector_overfetch))
      |> select([v, c, t, w], %{
        vector: %{
          kind: v.kind,
          lang: v.lang,
          translator_id: v.translator_id
        },
        chunk: c,
        work: w,
        text: t,
        score: max_inner_product(v.embedding, ^embedding)
      })

    results =
      query
      |> fetch()
      |> Enum.map(&to_result/1)
      # `relaxed_order` may return rows slightly out of distance order, so ranking is
      # re-established here rather than trusted from the scan.
      |> Enum.sort_by(& &1.similarity, :desc)
      |> collapse_by_chunk()
      |> balance(opts[:balance])
      |> Enum.take(limit)

    %{results: results, total: length(results), model: Embed.model()}
  end

  # Which vector kinds may answer.
  #
  # `source` and `translation` by default. A `translation` vector renders THIS passage,
  # so letting an English query reach it is simply the passage answering in another
  # language. A `parallel_gloss` renders a DIFFERENT text, and including it by default is
  # measurably not free: adding 1,665 of them for one division moved English-into-Chinese
  # from 0% to 33.3% and cost Pāli pinpoint retrieval 37.5% -> 27.5%, because English
  # vectors from every tradition compete in one space. Overall fell 81.7% -> 80.8%.
  #
  # So it is opt-in until there is a balancing story — per-tradition quotas, a diversity
  # term in fusion, something measured rather than guessed. The capability exists and can
  # be asked for; it does not silently tax the default path. See #43.
  @default_vector_kinds ~w(source translation)

  # Delegates rather than duplicating the binding logic: the coverage query names its
  # vector binding and the search query does not, and a second positional `[v]` here
  # would silently filter the wrong table in one of them.
  defp filter_vector_kinds(query, nil),
    do: filter_vector_kinds(query, @default_vector_kinds)

  defp filter_vector_kinds(query, kinds) do
    if has_named_binding?(query, :vector) do
      where(query, [vector: v], v.kind in ^List.wrap(kinds))
    else
      where(query, [v], v.kind in ^List.wrap(kinds))
    end
  end

  defp filter_vector_lang(query, nil), do: query

  defp filter_vector_lang(query, lang) do
    if has_named_binding?(query, :vector) do
      where(query, [vector: v], v.lang in ^List.wrap(lang))
    else
      where(query, [v], v.lang in ^List.wrap(lang))
    end
  end

  # Interleave the traditions so one cannot monopolise the head of the list.
  #
  # English vectors from every tradition compete in a single space, and there is nothing
  # in a similarity ranking that keeps any of them reachable — #43 measured 1,665 gloss
  # vectors displacing Pāli answers, and a whole-canon gloss layer would be ~300,000
  # against 14,781. Round-robin by source, preserving each tradition's internal order, so
  # a caller asking one question of a multi-tradition corpus sees more than one canon.
  #
  # Opt-in, and deliberately so: it is the right behaviour for a topical question and the
  # wrong one for "find the passage I just quoted", where the tradition is not in doubt
  # and interleaving only pushes the answer down. The caller knows which it is asking.
  defp balance(results, :tradition) do
    results
    |> Enum.group_by(&tradition_of/1)
    |> Enum.map(fn {_source, group} -> group end)
    |> interleave()
  end

  defp balance(results, _), do: results

  # The URN's source component IS the tradition here: cbeta and local commentary are
  # Chinese, sc is Pāli. Read from the URN rather than the provenance map so a result
  # whose span failed to resolve still balances rather than silently clustering.
  defp tradition_of(result) do
    case String.split(result.urn, [":", "."], parts: 3) do
      ["pramana", source | _] -> source
      _ -> "unknown"
    end
  end

  defp interleave([]), do: []

  defp interleave(groups) do
    {heads, rests} =
      groups
      |> Enum.reject(&(&1 == []))
      |> Enum.map(fn [head | rest] -> {head, rest} end)
      |> Enum.unzip()

    heads ++ interleave(rests)
  end

  # One chunk, one result — but keep a record of EVERY vector that matched it. A hit that
  # came through Sujato's English is a different kind of evidence from one that came
  # through the Pāli, and a caller that cannot tell them apart will present the first as
  # the second.
  defp collapse_by_chunk(results) do
    results
    |> Enum.group_by(& &1.urn)
    |> Enum.map(fn {_urn, [best | _] = all} ->
      Map.put(best, :matched_via, Enum.map(all, & &1.matched_via) |> List.flatten())
    end)
    |> Enum.sort_by(& &1.similarity, :desc)
  end

  # THIS IS A CORRECTNESS FIX, not a tuning knob.
  #
  # Every query goes through the iterative scan, so there is no longer a list of
  # "options that narrow the candidate set" to keep in step with `apply_filters/2` — an
  # omission from that list used to mean a filter that silently under-returned, and the
  # list itself was the thing that had to be remembered. Now nothing does.
  #
  # There used to be a second clause taking a plain index scan when no filter was
  # present, ~3x faster and correct precisely because nothing narrowed the candidates.
  # It is gone: every query now carries a vector-kind filter, since the default kinds
  # exclude `parallel_gloss`, so the plain scan would post-filter and under-return on
  # every single search. It cost Pāli pinpoint retrieval 37.5% -> 30.0% in the one run
  # where both were true at once.
  #
  # Postgres plans these as an HNSW index scan FOLLOWED BY the join and the provenance
  # filter. HNSW yields only `ef_search` candidates (40 by default), so filtering those
  # to a division holding 3.4% of the corpus discards nearly all of them: a request for
  # 10 results returned 5, and narrower filters returned NONE — while the matching text
  # sat in the table, embedded and correct.
  #
  # That failure is invisible. An empty result set reads as "the canon does not say
  # this" when the truth is "the index never looked there", and it strikes precisely the
  # provenance filters this project exists to provide.
  #
  # pgvector 0.8's iterative scan keeps pulling candidates until the limit is satisfied
  # or `max_scan_tuples` is exhausted. `SET LOCAL` needs a transaction, and it is worth
  # the ~3x latency because the alternative is silently wrong answers.
  defp fetch(query) do
    Repo.transaction(fn ->
      Repo.query!("SET LOCAL hnsw.iterative_scan = relaxed_order")
      Repo.query!("SET LOCAL hnsw.max_scan_tuples = #{@max_scan_tuples}")
      Repo.all(query)
    end)
    |> case do
      {:ok, rows} -> rows
    end
  end

  @doc """
  How much of the corpus is actually searchable by vector.

  Reported alongside results so partial coverage is never mistaken for a small canon.
  """
  @spec coverage(keyword()) :: map()
  def coverage(opts \\ []) do
    # The DENOMINATOR is the corpus — chunks — not the vector rows. Counting vectors
    # would make a corpus that has been chunked but not yet vectorised report `total: 0`,
    # which reads as "there is nothing to search" rather than "nothing is embedded yet",
    # and would let a corpus with translation vectors for 2% of its chunks report 100%
    # coverage. The number exists to stop partial data being mistaken for a small canon;
    # that only works if the whole canon is the denominator.
    chunks =
      from c in Chunk,
        as: :chunk,
        join: t in Text,
        as: :text,
        on: t.id == c.text_id,
        join: w in Work,
        as: :work,
        on: w.id == t.work_id

    chunks = apply_filters(chunks, opts)

    total = Repo.aggregate(chunks, :count)

    # A SEMI-JOIN, not `distinct` over a join. The question is whether each chunk has at
    # least one qualifying vector, and `exists` lets the planner stop at the first one;
    # `distinct` made it build the whole 560,238 x 617,038 join and then deduplicate.
    # Measured on the full corpus, same answer both ways (560,238): the SQL alone goes
    # 1,778 ms -> 527 ms, but the honest figure is the whole call, **1,224 ms -> 921 ms**,
    # about 300 ms saved per search. The rest is `total` plus Ecto overhead, and the
    # remaining ~900 ms is largely inherent: 560,238 index probes cost what they cost.
    #
    # Every search pays it — `Hybrid.run/2` calls this once per query — and it is database
    # time, so it shows up in no CPU profile. Caching is the obvious alternative and is the
    # wrong one: this number exists so an empty result cannot be mistaken for a small
    # canon, and a stale cache reports a corpus fuller than it is. Embedding state also
    # changes WITHOUT a re-bake, so `bake_id` is not even a sound key.
    qualifying_vectors =
      from(v in ChunkVector,
        where: v.chunk_id == parent_as(:chunk).id and not is_nil(v.embedding)
      )
      |> filter_vector_kinds(opts[:vector_kinds])
      |> filter_vector_lang(opts[:vector_lang])

    embedded =
      chunks
      |> where([chunk: _c], exists(qualifying_vectors))
      |> Repo.aggregate(:count)

    %{
      embedded: embedded,
      total: total,
      percent: if(total > 0, do: Float.round(100 * embedded / total, 1), else: 0.0),
      by_kind: vectors_by_kind()
    }
  end

  # How many vectors of each kind exist, alongside the chunk-level coverage above. A
  # chunk with a source vector and two translation vectors is one covered chunk and
  # three vectors; reporting only one of those numbers hides what the index contains.
  defp vectors_by_kind do
    Repo.all(
      from v in ChunkVector,
        group_by: [v.kind, v.lang],
        select: %{
          kind: v.kind,
          lang: v.lang,
          vectors: count(v.id),
          embedded: count(v.embedding)
        },
        order_by: [desc: count(v.id)]
    )
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
    |> filter_source(opts[:source_id])
    |> filter_license(opts)
    |> filter_work(opts[:work_id])
  end

  # NAMED bindings, not positional. These filters used `[_c, _t, w]`, which was correct
  # while the query was chunk-text-work and silently pointed at the wrong table the
  # moment a vector join went in front of it — a filter reading the wrong column returns
  # a plausible result set and reports no error. `[work: w]` cannot drift.
  defp filter_in(query, nil, _field), do: query

  defp filter_in(query, value, field),
    do: where(query, [work: w], field(w, ^field) in ^List.wrap(value))

  defp filter_not_in(query, nil, _field), do: query

  defp filter_not_in(query, value, field) do
    values = List.wrap(value)
    where(query, [work: w], field(w, ^field) not in ^values or is_nil(field(w, ^field)))
  end

  defp filter_eq(query, nil, _field), do: query
  defp filter_eq(query, value, field), do: where(query, [work: w], field(w, ^field) == ^value)

  defp filter_work(query, nil), do: query
  defp filter_work(query, work_id), do: where(query, [text: t], t.work_id == ^work_id)

  defp filter_source(query, nil), do: query

  defp filter_source(query, source_ids),
    do: where(query, [text: t], t.source_id in ^List.wrap(source_ids))

  # See `Pramana.Retrieval.Lexical.filter_license/2` — this is what makes the licence
  # posture enforceable rather than a promise kept by hand.
  defp filter_license(query, opts) do
    query
    |> filter_redistributable(opts[:redistributable_only])
    |> filter_license_class(opts[:license_class])
  end

  defp filter_redistributable(query, true),
    do:
      join(query, :inner, [text: t], src in Source,
        on: src.id == t.source_id and src.redistributable
      )

  defp filter_redistributable(query, _), do: query

  defp filter_license_class(query, nil), do: query

  defp filter_license_class(query, value) do
    values = List.wrap(value)

    join(query, :inner, [text: t], src in Source,
      on: src.id == t.source_id and src.license_class in ^values
    )
  end

  defp to_result(%{chunk: chunk, score: score, vector: vector}) do
    %{
      urn: chunk.urn,
      content: chunk.content,
      # How this chunk was found. `kind: "translation"` means the QUERY matched an
      # English rendering; `content` above is still the source, and the URN still
      # addresses the source, which is the only thing citable.
      matched_via: [
        %{
          kind: vector.kind,
          lang: vector.lang,
          translator_id: vector.translator_id,
          similarity: -score
        }
      ],
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
