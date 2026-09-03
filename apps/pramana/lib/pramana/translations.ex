defmodule Pramana.Translations do
  @moduledoc """
  The translation pool, and the policy that decides which rendering a caller sees.

  ## There is no "the" translation

  `docs/TRANSLATION.md` starts from the observation that this corpus has *never* had a
  single translation of anything: the Chinese canon carries 2–6 translations of the same
  Sanskrit work (異譯本 — the Lotus Sūtra three times), and SuttaCentral carries Sujato,
  Brahmali, Patton and Anandajoti on overlapping suttas. Model disagreement is not a new
  problem introduced by LLMs; it is the normal condition of the field, and the machinery
  built for the human case handles the machine case unchanged.

  So this module never picks a winner implicitly. Callers supply a **policy** and get
  back what that policy selected, along with how many other renderings existed —
  because "there were four and you are seeing one" is information the reader needs.

  ## Three tiers

  | tier | what | reproducible | citable |
  |---|---|---|---|
  | `t0` | a human translator | yes | yes, attributed to a person |
  | `t1` | baked, pinned model + prompt + glossary | yes | yes, attributed to a model+config |
  | `t2` | generated at query time | no | shown, marked provisional |

  ## What this module will not do

  It will not return a rendering as a source span. `resolve/1` yields a map whose
  `provenance.method` is `"human"`, `"llm"` or `"hybrid"`, and `Pramana.Guard` rejects a
  non-human rendering presented as canonical (`CLAUDE.md` invariant #7). The rendering
  is reachable only through a URN that names its source anchor, so the citation a reader
  copies always points at the text being translated.
  """

  import Ecto.Query

  alias Pramana.Corpus
  alias Pramana.Corpus.Segment
  alias Pramana.Corpus.Text
  alias Pramana.Corpus.Translation
  alias Pramana.Repo
  alias Pramana.URN

  @tiers ~w(t0 t1 t2)
  @methods ~w(human llm hybrid)
  @review_states ~w(raw machine_verified human_reviewed approved)

  @policy_keys [
    :lang,
    :prefer,
    :translator,
    :model,
    :mode,
    :tier,
    :redistributable_only,
    :min_review_state
  ]

  @default_policy %{
    lang: "en",
    # Tier order, strongest provenance first. A human rendering beats a baked one beats
    # an ephemeral one unless the caller says otherwise.
    prefer: ["t0", "t1", "t2"],
    translator: nil,
    model: nil,
    mode: :single,
    tier: nil,
    redistributable_only: false,
    min_review_state: nil
  }

  @doc "The tiers, strongest provenance first."
  @spec tiers() :: [String.t()]
  def tiers, do: @tiers

  @doc "The recognised production methods."
  @spec methods() :: [String.t()]
  def methods, do: @methods

  @doc "Review states, weakest first. Order is meaningful: `min_review_state` is a floor."
  @spec review_states() :: [String.t()]
  def review_states, do: @review_states

  @doc """
  Normalizes and validates a selection policy.

  Raises on an unknown key. A silently-ignored `translator:` would hand back some other
  translator's words under the name the caller asked for, which is worse than an error —
  the same reasoning as the search options in `Pramana.Retrieval.Lexical`.
  """
  @spec policy(keyword() | map()) :: map()
  def policy(opts \\ []) do
    opts = Map.new(opts)

    case Map.keys(opts) -- @policy_keys do
      [] -> :ok
      unknown -> raise ArgumentError, "unknown translation policy option: #{inspect(unknown)}"
    end

    @default_policy
    |> Map.merge(opts)
    |> validate_policy()
  end

  defp validate_policy(policy) do
    if policy.tier && policy.tier not in @tiers do
      raise ArgumentError,
            "unknown tier #{inspect(policy.tier)}, expected one of #{inspect(@tiers)}"
    end

    if policy.min_review_state && policy.min_review_state not in @review_states do
      raise ArgumentError, "unknown review state #{inspect(policy.min_review_state)}"
    end

    policy
  end

  @doc """
  Every rendering of an anchor, ordered by the policy's preference.

  The full pool, unnarrowed except by the policy's filters — this is what `mode:
  :compare` returns, and what makes divergence visible instead of hidden behind a
  silent choice.
  """
  @spec pool(String.t(), keyword() | map()) :: [map()]
  def pool(anchor_urn, opts \\ []) do
    policy = policy(opts)

    from(t in Translation, where: t.anchor_urn == ^anchor_urn and t.lang == ^policy.lang)
    |> apply_filters(policy)
    |> Repo.all()
    |> Enum.map(&present/1)
    |> sort_by_policy(policy)
  end

  @doc """
  Every rendering whose anchor **contains** this span, rather than equalling it.

  A translator does not always work at the grain the source is addressed in. 84000 marks
  the Degé Kangyur's folios, so its English is anchored to the seven-line range a folio
  holds — and a caller asking for `@51.100a.3` is asking about a line inside that range.
  Exact matching answers "no translation" there, which is false.

  Containment is by segment ordinal, recorded on the rendering when it is stored, because
  the alternative is comparing locators — and a locator grammar belongs to its edition,
  so `51.100a.3` is only "inside" `51.100a.1-51.100a.7` if you know how Derge folios
  work. Ordinals are the corpus's own ordering and mean the same thing in every source.

  Renderings found this way carry `covers: :containing_range`, so a caller can tell a
  translation OF this passage from one that includes it.

  **The work is read from the segment, never from the URN.** `urn.work` is the work
  component of the *address*, and for CBETA that is the juan — `T0099_015`, where the
  work is `T0099`. Matching on it found nothing for every range-anchored English
  rendering of the Chinese canon, which is 2,089 of the first 3,354: the English existed,
  was correctly anchored, and was unreachable from the line it renders. Rules 41 and 68 —
  the same assumption, in a second place, found by checking whether a model could actually
  get to the thing that had just shipped.
  """
  @spec covering(String.t(), keyword() | map()) :: [map()]
  def covering(span_urn, opts \\ []) do
    policy = policy(opts)

    with {:ok, urn} <- URN.parse(span_urn),
         {:ok, {ordinal, work_id}} <- ordinal_of(urn) do
      from(t in Translation,
        where: t.work_id == ^work_id and t.lang == ^policy.lang,
        where: fragment("(? -> 'ordinal_start')::int <= ?", t.meta, ^ordinal),
        where: fragment("(? -> 'ordinal_end')::int >= ?", t.meta, ^ordinal)
      )
      |> apply_filters(policy)
      |> Repo.all()
      |> Enum.map(&Map.put(present(&1), :covers, :containing_range))
      |> sort_by_policy(policy)
    else
      _ -> []
    end
  end

  # The span's position in its text, and the work that text belongs to. A range URN is
  # located by where it starts. Both come from the segment row, because both are
  # properties of the text rather than of the citation grammar it is addressed in.
  defp ordinal_of(%URN{} = urn) do
    anchor = URN.to_string(%{urn | locator_end: nil, rendering: nil})

    query =
      from s in Segment,
        join: t in Text,
        on: t.id == s.text_id,
        where: s.urn == ^anchor,
        select: {s.ordinal, t.work_id}

    case Repo.one(query) do
      nil -> :error
      {ordinal, work_id} -> {:ok, {ordinal, work_id}}
    end
  end

  @doc """
  Applies a selection policy to an anchor.

  Returns `%{rendering: …, alternatives: n, pool: [...]}`, where `rendering` is nil when
  nothing satisfied the policy. `alternatives` counts renderings that existed but were
  not chosen: a caller showing one translation of four should be able to say so.

  With `mode: :compare` the pool is returned in full and `rendering` is the first.

  When nothing is anchored to exactly this span, renderings whose anchor **contains** it
  are returned instead — see `covering/2`. That fallback is what makes a folio-anchored
  translation reachable from a line, and it never silently substitutes: those renderings
  carry `covers: :containing_range` and their own, wider, `anchor_urn`.
  """
  @spec select(String.t(), keyword() | map()) :: map()
  def select(anchor_urn, opts \\ []) do
    policy = policy(opts)

    pool =
      case pool(anchor_urn, policy) do
        [] -> covering(anchor_urn, policy)
        exact -> exact
      end

    %{
      anchor_urn: anchor_urn,
      lang: policy.lang,
      rendering: List.first(pool),
      alternatives: max(length(pool) - 1, 0),
      pool: if(policy.mode == :compare, do: pool, else: []),
      policy: policy
    }
  end

  defp apply_filters(query, policy) do
    query
    |> filter_translator(policy.translator)
    |> filter_model(policy.model)
    |> filter_tier(policy.tier)
    |> filter_redistributable(policy.redistributable_only)
    |> filter_review_state(policy.min_review_state)
  end

  defp filter_translator(query, nil), do: query
  defp filter_translator(query, id), do: where(query, [t], t.translator_id == ^id)

  defp filter_model(query, nil), do: query
  defp filter_model(query, model), do: where(query, [t], t.model_id == ^model)

  defp filter_tier(query, nil), do: query
  defp filter_tier(query, tier), do: where(query, [t], t.tier == ^tier)

  defp filter_redistributable(query, true), do: where(query, [t], t.redistributable)
  defp filter_redistributable(query, _), do: query

  defp filter_review_state(query, nil), do: query

  # A floor, not an equality: asking for `human_reviewed` should also accept `approved`.
  # Comparing the strings would exclude the stronger state, which is the wrong direction
  # to fail in.
  defp filter_review_state(query, minimum) do
    allowed = Enum.drop_while(@review_states, &(&1 != minimum))
    where(query, [t], t.review_state in ^allowed)
  end

  # Ordering is the policy's `prefer` list, then translator id for stability. Sorting in
  # Elixir rather than SQL because the tier order is caller-supplied and a CASE built
  # from user input is how an injection gets written.
  defp sort_by_policy(renderings, policy) do
    Enum.sort_by(renderings, fn r ->
      {Enum.find_index(policy.prefer, &(&1 == r.tier)) || length(policy.prefer), r.translator_id}
    end)
  end

  @doc """
  Resolves a rendering URN — `pramana:sc.ms:mn1@1.1#tr:en/sujato` — to a span.

  The shape matches `Pramana.Corpus.resolve/1` so the guard can check a rendering with
  the same code path as a source span, including `provenance.method`, which is what
  makes invariant #7 enforceable rather than aspirational.
  """
  @spec resolve(String.t()) :: {:ok, map()} | {:error, atom()}
  def resolve(urn_string) when is_binary(urn_string) do
    with {:ok, urn} <- URN.parse(urn_string),
         {:ok, {lang, translator_id}} <- fetch_rendering(urn),
         anchor = URN.to_string(URN.anchor(urn)),
         {:ok, rendering} <- fetch(anchor, lang, translator_id) do
      {:ok, span(rendering, urn_string, anchor)}
    end
  end

  defp fetch_rendering(%URN{rendering: nil}), do: {:error, :not_a_rendering}
  defp fetch_rendering(%URN{rendering: rendering}), do: {:ok, rendering}

  defp fetch(anchor, lang, translator_id) do
    case Repo.one(
           from t in Translation,
             where:
               t.anchor_urn == ^anchor and t.lang == ^lang and
                 t.translator_id == ^translator_id
         ) do
      nil -> {:error, :not_found}
      rendering -> {:ok, rendering}
    end
  end

  defp span(rendering, urn_string, anchor) do
    %{
      urn: urn_string,
      # The source this renders, always present. A reader who wants to check the
      # translation is one lookup away from the words it is a translation OF.
      anchor_urn: anchor,
      content: rendering.text,
      # `sha256`, matching what `Pramana.Corpus` returns. It was `content_sha256` here and
      # `sha256` there, and `get_passage` reaches for `span.sha256` — so any rendering URN
      # crashed the tool with a KeyError rather than answering. Two names for one field
      # across a boundary is a bug waiting for the first caller who crosses it.
      sha256: rendering.text_sha256,
      provenance: provenance(rendering)
    }
  end

  @doc """
  The provenance a rendering carries into a tool response.

  `method` is the field `Pramana.Guard` reads. Everything else is what a reader needs to
  judge the rendering: who made it, under what licence, reviewed how far, and — for a
  generated one — with which model, prompt and glossary, so it can be reproduced or
  disputed.
  """
  @spec provenance(Translation.t()) :: map()
  def provenance(%Translation{} = t) do
    %{
      layer: "translation",
      method: t.method,
      tier: t.tier,
      translator_id: t.translator_id,
      translator: t.translator_name,
      lang: t.lang,
      review_state: t.review_state,
      model_id: t.model_id,
      prompt_version: t.prompt_version,
      glossary_id: t.glossary_id,
      license_spdx: t.license_spdx,
      license_class: t.license_class,
      redistributable: t.redistributable,
      attribution: t.attribution,
      # Stated rather than implied. A rendering is evidence of how someone read the
      # passage, never evidence of what the passage says.
      citable_as_source: false
    }
  end

  @doc """
  Stores renderings, replacing any previous rendering by the same translator.

  Takes maps with at least `anchor_urn`, `work_id`, `lang`, `translator_id`, `tier`,
  `method` and `text`; `text_sha256` is computed here so no caller can store a hash that
  does not cover the text it ships with.
  """
  @spec store([map()]) :: {:ok, non_neg_integer()}
  def store(rows) when is_list(rows) do
    now = DateTime.utc_now()

    prepared = Enum.map(rows, &prepare(&1, now))

    {written, _} =
      Pramana.Batch.insert_all(Translation, prepared,
        on_conflict:
          {:replace,
           [
             :text,
             :text_sha256,
             :translator_name,
             :tier,
             :method,
             :model_id,
             :prompt_version,
             :glossary_id,
             :bake_id,
             :review_state,
             :license_spdx,
             :license_class,
             :redistributable,
             :attribution,
             :source_file,
             :meta,
             :updated_at
           ]},
        conflict_target: [:anchor_urn, :lang, :translator_id]
      )

    {:ok, written}
  end

  defp prepare(row, now) do
    text = Map.fetch!(row, :text)

    row
    |> Map.put(:text_sha256, :crypto.hash(:sha256, text) |> Base.encode16(case: :lower))
    |> Map.put_new(:review_state, "raw")
    |> Map.put_new(:redistributable, false)
    |> Map.put_new(:meta, %{})
    |> Map.merge(%{inserted_at: now, updated_at: now})
  end

  @doc """
  Anchors in a work that have no rendering in a language.

  Coverage is a claim a reader will act on, so it is measured rather than assumed: a
  translation that covers 60% of a sutta must not be presented as a translation of the
  sutta.
  """
  @spec coverage(String.t(), keyword() | map()) :: map()
  def coverage(work_id, opts \\ []) do
    policy = policy(opts)

    anchors =
      Repo.aggregate(
        from(s in Corpus.Segment,
          join: t in Corpus.Text,
          on: t.id == s.text_id,
          where: t.work_id == ^work_id
        ),
        :count
      )

    by_translator =
      Repo.all(
        from t in Translation,
          where: t.work_id == ^work_id and t.lang == ^policy.lang,
          group_by: [t.translator_id, t.tier],
          select: {t.translator_id, t.tier, count(t.id)},
          order_by: [desc: count(t.id)]
      )

    %{
      work_id: work_id,
      lang: policy.lang,
      anchors: anchors,
      translators:
        Enum.map(by_translator, fn {id, tier, n} ->
          %{
            translator_id: id,
            tier: tier,
            rendered: n,
            coverage: if(anchors > 0, do: Float.round(n / anchors, 3), else: 0.0)
          }
        end)
    }
  end

  @doc "Pool counts, for the inventory and the gate."
  @spec stats() :: map()
  def stats do
    %{
      renderings: Repo.aggregate(Translation, :count),
      by_lang: group_count(:lang),
      by_tier: group_count(:tier),
      by_method: group_count(:method),
      by_license_class: group_count(:license_class),
      translators:
        Repo.all(
          from t in Translation,
            group_by: [t.translator_id, t.translator_name, t.tier],
            select: %{
              translator_id: t.translator_id,
              translator: t.translator_name,
              tier: t.tier,
              renderings: count(t.id)
            },
            order_by: [desc: count(t.id)]
        ),
      # How many anchors carry more than one rendering — the pool's reason to exist.
      # Counted over a SUBQUERY: a grouped query returns one row per anchor, so
      # `Repo.one` on it raises once any anchor has a second translator, which is the
      # moment this number starts being interesting.
      anchors_with_multiple:
        Repo.aggregate(
          subquery(
            from t in Translation,
              group_by: [t.anchor_urn, t.lang],
              having: count(t.id) > 1,
              select: %{anchor_urn: t.anchor_urn, lang: t.lang}
          ),
          :count
        )
    }
  end

  @doc """
  Renderings whose licence could not be established, grouped by translator.

  A rendering with `license_class: "unknown"` is held and searchable but never
  redistributable. This is the list someone works through to turn a guess into a fact —
  and while it is non-empty, it is the honest answer to "can we publish the pool".
  """
  @spec unlicensed() :: [map()]
  def unlicensed do
    Repo.all(
      from t in Translation,
        where: t.license_class == "unknown" or not t.redistributable,
        group_by: [t.translator_id, t.lang, t.license_class, t.redistributable],
        select: %{
          translator_id: t.translator_id,
          lang: t.lang,
          license_class: t.license_class,
          redistributable: t.redistributable,
          renderings: count(t.id)
        },
        order_by: [desc: count(t.id)]
    )
  end

  defp group_count(field) do
    Repo.all(
      from t in Translation,
        group_by: field(t, ^field),
        select: {field(t, ^field), count(t.id)},
        order_by: [desc: count(t.id)]
    )
    |> Map.new()
  end

  defp present(%Translation{} = t) do
    %{
      id: t.id,
      anchor_urn: t.anchor_urn,
      urn: rendering_urn(t),
      lang: t.lang,
      tier: t.tier,
      method: t.method,
      translator_id: t.translator_id,
      translator: t.translator_name,
      text: t.text,
      # The SAME hash `resolve/1` returns for this rendering. Without it a caller could
      # verify a rendering fetched by URN and not the identical one listed in a pool,
      # which makes verifiability depend on which call you happened to make — and
      # `CLAUDE.md` invariant #1 is that no unattributed text leaves the API.
      sha256: t.text_sha256,
      review_state: t.review_state,
      license_class: t.license_class,
      redistributable: t.redistributable,
      attribution: t.attribution,
      provenance: provenance(t)
    }
  end

  # Search options this understands. An unknown option RAISES rather than being ignored,
  # the rule `Retrieval.Lexical` already follows: a filter silently dropped is a filter a
  # caller believes is applied, and here that caller may be deciding what to publish.
  @search_opts [:lang, :limit, :translator, :redistributable_only, :work_id]

  @doc """
  Renderings whose text matches a query — *"which line does this translator render this
  way"*, which is the question the anchor-keyed functions above cannot ask.

  Without it, an English query reached the lexical retriever, which reads `segments`, and
  returned **Pāli passages sharing character n-grams with the English** — three confident
  results with nothing to do with the question. 210,756 renderings were reachable only
  through an anchor a caller already had.

  ## Every result is a rendering, and says so

  A hit carries `anchor_urn` — the source line it renders — and the full provenance record,
  including `citable_as_source: false`. It is **not** a search result in the sense the
  retrieval layer means: nothing here may be quoted as what a text says, only as how
  somebody rendered it. Invariant #8 is structural, and this is the surface where it would
  be easiest to lose, because a fluent English sentence reads like an answer.

  This is why it is not a third arm in the hybrid fusion. Fused into one ranked list, a
  rendering and a source span would arrive as peers and the distinction would survive only
  as a field somebody remembers to read — the same objection that kept the glossary out of
  RRF, for a stronger reason.

  ## Options

    * `:lang` — defaults to `"en"`, the only language with a text index
    * `:limit`, `:translator`, `:work_id`
    * `:redistributable_only` — as elsewhere, what we are willing to act on
  """
  @spec search(String.t(), keyword()) ::
          {:ok, %{results: [map()], match: :all_terms | :any_term}} | {:error, atom()}
  def search(query, opts \\ [])

  def search(query, opts) when is_binary(query) do
    case Keyword.keys(opts) -- @search_opts do
      [] ->
        {hits, match} = do_search(String.trim(query), opts)
        {:ok, %{results: hits, match: match}}

      unknown ->
        raise ArgumentError, "unknown option(s) #{inspect(unknown)}"
    end
  end

  def search(_query, _opts), do: {:error, :bad_query}

  defp do_search("", _opts), do: {[], :all_terms}

  # ALL TERMS FIRST, THEN ANY, AND THE ANSWER SAYS WHICH.
  #
  # The unit here is one rendered LINE — usually a single sentence — so requiring every
  # query term in one row is far stricter than it looks. "Baka Brahmā" returns nothing
  # while "Baka" and "Brahmā" each return the same discourse, because it names them on
  # different lines. Requiring all terms alone is a search that answers "not here" about
  # text it holds.
  #
  # Loosening to any-term unconditionally would be worse: one common word would fill the
  # results of a precise query. So it is a FALLBACK and the mode is REPORTED — exactly what
  # `Retrieval.Lexical` does with `phrase` and its `ngram` fallback, for the same reason. A
  # caller told `:any_term` knows the terms were not found together.
  defp do_search(query, opts) do
    case Repo.all(all_terms(query, opts)) |> Enum.map(&hit/1) do
      [] -> {Repo.all(any_term(query, opts)) |> Enum.map(&hit/1), :any_term}
      hits -> {hits, :all_terms}
    end
  end

  defp all_terms(query, opts) do
    from(t in Translation,
      where:
        fragment(
          "to_tsvector('english', ?) @@ websearch_to_tsquery('english', ?)",
          t.text,
          ^query
        ),
      order_by: [
        desc:
          fragment(
            "ts_rank(to_tsvector('english', ?), websearch_to_tsquery('english', ?))",
            t.text,
            ^query
          )
      ]
    )
    |> common(opts)
  end

  # `websearch_to_tsquery` has no or-by-default mode, so the query is rebuilt: each word
  # becomes a term and they are joined with `|`. Punctuation is STRIPPED rather than
  # escaped, because a tsquery operator arriving from a user is a syntax error at best and
  # someone else's query at worst.
  defp any_term(query, opts) do
    words = String.split(query, ~r/[^\p{L}\p{N}]+/u, trim: true)

    if words == [] do
      from(t in Translation, where: false)
    else
      joined = Enum.join(words, " | ")

      from(t in Translation,
        where: fragment("to_tsvector('english', ?) @@ to_tsquery('english', ?)", t.text, ^joined),
        order_by: [
          desc:
            fragment(
              "ts_rank(to_tsvector('english', ?), to_tsquery('english', ?))",
              t.text,
              ^joined
            )
        ]
      )
      |> common(opts)
    end
  end

  defp common(query, opts) do
    lang = Keyword.get(opts, :lang, "en")

    query
    |> where([t], t.lang == ^lang)
    |> limit(^Keyword.get(opts, :limit, 10))
    |> filter_translator(opts[:translator])
    |> filter_work(opts[:work_id])
    |> filter_redistributable(opts[:redistributable_only])
  end

  # `filter_translator/2` and `filter_redistributable/2` are the ones `pool/2` already uses.
  # A second copy would be a second definition of what "only what we may republish" means,
  # in the module where that phrase decides a licensing question.
  defp filter_work(query, nil), do: query
  defp filter_work(query, work_id), do: where(query, [t], t.work_id == ^work_id)

  # ANCHOR FIRST, TEXT SECOND. The shape says what this is: a rendering OF something, whose
  # source is one resolve away. A map leading with the English would read as a passage.
  defp hit(%Translation{} = t) do
    %{
      anchor_urn: t.anchor_urn,
      rendering_urn: rendering_urn(t),
      work_id: t.work_id,
      text: t.text,
      text_sha256: t.text_sha256,
      translator: t.translator_name || t.translator_id,
      lang: t.lang,
      provenance: provenance(t)
    }
  end

  @doc "The rendering URN for a stored translation."
  @spec rendering_urn(Translation.t()) :: String.t()
  def rendering_urn(%Translation{} = t) do
    "#{t.anchor_urn}#tr:#{t.lang}/#{t.translator_id}"
  end
end
