defmodule Pramana.Compare do
  @moduledoc """
  The same passage, set beside its other versions.

  Two kinds of "other version" exist in this corpus today, and they are **not the same
  kind of claim**, so they are returned in separate keys rather than merged into one
  list:

  | key | what it is | evidence |
  |---|---|---|
  | `renderings` | translations of *this* passage | the translation pool (#39) |
  | `parallels` | the same discourse in another language or recension | hand-curated scholarship (#18) |

  A rendering is someone's English for the text in front of you. A parallel is a
  *different text* that scholars judge to transmit the same discourse. Presenting them
  together as "versions" would let a Pāli sutta be read as a translation of a Chinese
  one, when neither is a translation of the other — both descend from something earlier.

  ## `alternates` — work-level siblings, and what they are not

  The Chinese canon holds several independent translations of the same Indic original.
  `alternates` returns work-level `parallel_of` relations, derived from SuttaCentral's
  curated passage parallels aggregated to the work — 41 Chinese pairs clear the evidence
  threshold.

  **They are candidates for 異譯本, not established alternate translations.** T0099
  雜阿含經 and T0100 別譯雜阿含經 share 706 curated passages and the second's name says it
  is a separate translation — a real 異譯本. T0099 and T0125 share 88 and are the Saṃyukta
  and Ekottarika Āgama: **different collections**, neither translating the other. The
  parallel data cannot tell those two situations apart, so `confidence` and `evidence`
  travel with every entry and nothing here decides for the reader.

  This section previously read "Not here yet: 異譯本" and said returning an always-empty
  key would promise a comparison the corpus could not make. That was true until the
  relations were derived (#23, 2026-08-24).

  ## Comparison is retrieval that has already been done

  Nothing here is computed by similarity. Parallels come from SuttaCentral's 388,074
  curated relations. `get_parallels` is the retrieval side of this and shipped in #18;
  this module is the presentation side —
  it resolves each end to an actual quotable passage, so a caller gets text rather than
  a list of identifiers it must then chase.

  ## What is deliberately absent

  No divergence score, and no judgement about which version is better or earlier. Scoring
  where versions differ is Phase 6 (#23), and it needs the embeddings that Phase 3 is
  only now putting in place. Returning a number before it can be computed honestly would
  be worse than returning none.
  """

  alias Pramana.Corpus
  alias Pramana.Parallels
  alias Pramana.Relations
  alias Pramana.Translations
  alias Pramana.URN

  @default_relations ~w(full resembling)

  @doc """
  Assembles every version of the passage at `urn`.

  Options:

    * `:lang` — translation language for the rendering pool (default `"en"`)
    * `:translator` — pin one translator
    * `:relations` — which parallel strengths to include (default full + resembling)
    * `:include_text` — resolve each parallel to its passage (default `true`)
    * `:limit` — cap on parallels resolved (default 10)

  Returns `nil` for a section that has nothing rather than an empty structure pretending
  to be an answer.
  """
  @spec versions(String.t(), keyword()) :: {:ok, map()} | {:error, atom()}
  def versions(urn, opts \\ []) do
    with {:ok, _parsed} <- URN.parse(urn),
         {:ok, span} <- Corpus.resolve(urn) do
      {:ok,
       %{
         urn: urn,
         passage: span,
         renderings: renderings(urn, opts),
         parallels: parallels(work_id(span), opts),
         alternates: alternates(work_id(span)),
         # Said once, structurally, rather than left for a caller to infer: these are
         # different witnesses to a tradition, not editions of one another.
         note:
           "Renderings translate this passage. Parallels are DIFFERENT texts judged to " <>
             "transmit the same material; neither is a translation of the other. " <>
             "Alternates are whole works transmitting the same material as this one — " <>
             "candidates for 異譯本, NOT established alternate translations."
       }}
    end
  end

  defp renderings(urn, opts) do
    selection =
      Translations.select(urn,
        lang: Keyword.get(opts, :lang, "en"),
        translator: opts[:translator],
        mode: :compare
      )

    case selection.pool do
      [] -> nil
      pool -> %{lang: selection.lang, count: length(pool), pool: pool}
    end
  end

  # The work id comes from the RESOLVED passage, not from the URN's work component. In
  # the Taishō those differ: `pramana:cbeta.T:T0099_001@…` addresses juan 1 of T0099, so
  # the component is `T0099_001` while the work is `T0099`. Parsing the id out of the URN
  # would silently find no parallels for every Chinese passage in the corpus — an empty
  # comparison that reads as "no parallels exist".
  defp work_id(span), do: get_in(span, [:provenance, :work_id])

  # WORK-level siblings, where `parallels` above is PASSAGE-level. A reader asking "is
  # there another version of this text" wants the work; a reader asking "what else says
  # this" wants the passage. Both are real questions and the answers are different objects.
  #
  # `nil` rather than `[]` when there are none, matching every other section here: an empty
  # list reads as "we looked and the tradition is silent", and only 41 Chinese work pairs
  # clear the evidence threshold, so most passages genuinely have nothing to show.
  #
  # Each entry carries `confidence` and `evidence` untouched. These are **candidates for
  # 異譯本, not established alternate translations** — T0099/T0100 is a genuine alternate
  # translation and T0099/T0125 is two different Āgama collections, and the curated
  # parallel data that produced both cannot tell them apart. Flattening that away would be
  # the exact failure invariant #4 exists to prevent.
  defp alternates(nil), do: nil

  defp alternates(work_id) do
    case Relations.parallels_of(work_id) do
      [] -> nil
      list -> %{count: length(list), works: list}
    end
  end

  defp parallels(nil, _opts), do: nil

  defp parallels(work_id, opts) do
    relations = Keyword.get(opts, :relations, @default_relations)
    limit = Keyword.get(opts, :limit, 10)

    work_id
    |> Parallels.for_work(relations: relations)
    # A parallel we cannot resolve is a reference, not a passage. Dropping the
    # unresolvable ones silently would misrepresent how much of the comparison we hold,
    # so they are counted separately below.
    |> Enum.split_with(&(&1.urn != nil))
    |> then(fn {resolvable, unresolvable} ->
      shown = Enum.take(resolvable, limit)

      %{
        total: length(resolvable) + length(unresolvable),
        quotable: length(resolvable),
        # Named honestly: these are texts the scholarship links to this one that this
        # corpus does not hold. Silence would read as "there are none".
        referenced_but_not_held: length(unresolvable),
        versions: Enum.map(shown, &resolve_parallel(&1, opts))
      }
    end)
    |> case do
      %{total: 0} -> nil
      result -> result
    end
  end

  defp resolve_parallel(parallel, opts) do
    base = %{
      uid: parallel.uid,
      urn: parallel.urn,
      work_id: parallel.work_id,
      # The strength of the claim, never flattened to "related".
      relation: parallel.relation,
      partial: parallel.partial
    }

    if Keyword.get(opts, :include_text, true) do
      Map.put(base, :passage, resolve_or_nil(parallel.urn))
    else
      base
    end
  end

  defp resolve_or_nil(nil), do: nil

  defp resolve_or_nil(urn) do
    case Corpus.resolve(urn) do
      {:ok, span} -> span
      {:error, _} -> nil
    end
  end
end
