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

  ## Not here yet: 異譯本

  The Chinese canon holds several independent translations of the same Indic original —
  Kumārajīva's Lotus Sūtra beside Dharmarakṣa's. That is a third kind of version, and the
  relation vocabulary already has a slot for it (`parallel_of` in `Pramana.Relations`),
  but **nothing populates it**: the only asserted relations so far are 90 `comments_on`
  links. Returning an always-empty `alternates` key would promise a comparison this
  corpus cannot yet make. Populating it is part of translator fingerprinting (#23).

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
         # Said once, structurally, rather than left for a caller to infer: these are
         # different witnesses to a tradition, not editions of one another.
         note:
           "Renderings translate this passage. Parallels are DIFFERENT texts judged to " <>
             "transmit the same material; neither is a translation of the other."
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
