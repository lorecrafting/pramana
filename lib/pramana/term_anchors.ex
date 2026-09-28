defmodule Pramana.TermAnchors do
  @moduledoc """
  The same term, as three traditions name it.

  Built from the glossaries 84000 publishes with each translation: 56,382 entries, 16,741
  distinct Sanskrit terms and 25,524 Tibetan ones, with **865 carrying all three of
  Sanskrit, Tibetan and Chinese**. `dharma` / `ཆོས།` / `法` is one row, attested by the
  people who made the translation rather than assembled by matching strings.

  Sampled against the corpus itself, 59 of 60 three-way anchors are reachable in *both*
  canons — the Chinese term occurs in the Taishō and the Tibetan in the Kangyur — so an
  anchor is a query a reader can actually run. The exception was a proper name that the
  Chinese transliterates differently, which is the expected shape of the miss.

  ## Divergence is the point, not a problem

  **2,756 Sanskrit terms are rendered by more than one Tibetan.** `parivrājaka` appears as
  `ཀུན་ཏུ་རྒྱུ་བ།`, `ཀུན་ཏུ་རྒྱུ།` and `ཀུན་དུ་རྒྱུ།`; translators of different texts, and different
  centuries, made different choices. This module never collapses them into a winner —
  `renderings/2` returns the set with how often each was used and where, which is the same
  refusal `Pramana.Translations` makes about whole passages, one word down.

  ## Attestation travels with the term

  Most of the Sanskrit here is a **reconstruction**: 84000 marks it `sourceUnspecified`,
  meaning no surviving Sanskrit witness of that text says it. Only 2,783 entries carry
  Sanskrit attested in a source. `attested_only: true` narrows a query to what a witness
  actually says, and the attestation is on every row returned so a caller who does not ask
  still cannot mistake one for the other.
  """

  import Ecto.Query

  alias Pramana.Corpus.GlossaryEntry
  alias Pramana.Repo

  @languages [:sanskrit, :tibetan, :chinese, :english, :wylie, :pali]

  @typedoc "One term as a translator glossed it, with where each form comes from."
  @type anchor :: %{
          sanskrit: String.t() | nil,
          tibetan: String.t() | nil,
          wylie: String.t() | nil,
          chinese: String.t() | nil,
          english: String.t() | nil,
          attestation: %{atom() => String.t() | nil},
          work_id: String.t() | nil,
          definition: String.t() | nil
        }

  @doc """
  Every glossed entry whose term in `language` is exactly `term`.

  Exact rather than fuzzy: these are lexicon entries, and a substring match on `ཆོས།`
  would return every compound containing it. Options:

    * `:attested_only` — only entries whose Sanskrit is attested in a source, not
      reconstructed
    * `:limit` — default 50
  """
  @spec lookup(atom(), String.t(), keyword()) :: [anchor()]
  def lookup(language, term, opts \\ []) when language in @languages and is_binary(term) do
    GlossaryEntry
    |> where(^[{language, term}])
    |> attested(opts[:attested_only])
    |> limit(^Keyword.get(opts, :limit, 50))
    |> Repo.all()
    |> Enum.map(&present/1)
  end

  @doc """
  How one Sanskrit term was rendered, and how often each rendering was chosen.

  The answer to "what do the Tibetans call this" is usually several things. Ordered by how
  many texts used each, which is a fact about the corpus rather than a judgement about the
  translation.
  """
  @spec renderings(String.t(), keyword()) :: [map()]
  def renderings(sanskrit, opts \\ []) when is_binary(sanskrit) do
    GlossaryEntry
    |> where([g], g.sanskrit == ^sanskrit)
    |> attested(opts[:attested_only])
    |> group_by([g], [g.tibetan, g.wylie, g.english])
    |> select([g], %{
      tibetan: g.tibetan,
      wylie: g.wylie,
      english: g.english,
      texts: count(g.work_id, :distinct),
      entries: count(g.id)
    })
    |> order_by([g], desc: count(g.id))
    |> Repo.all()
  end

  @doc """
  Terms that carry all three of Sanskrit, Tibetan and Chinese.

  The Phase 5 anchor set: a term a reader can look for in either canon and a query can
  cross between them.
  """
  @spec three_way(keyword()) :: [anchor()]
  def three_way(opts \\ []) do
    GlossaryEntry
    |> where([g], not is_nil(g.sanskrit) and not is_nil(g.tibetan) and not is_nil(g.chinese))
    |> attested(opts[:attested_only])
    |> order_by([g], asc: g.sanskrit)
    |> limit(^Keyword.get(opts, :limit, 100))
    |> Repo.all()
    |> Enum.map(&present/1)
  end

  @doc "Counts for the inventory, including how much of the Sanskrit is reconstructed."
  @spec stats() :: map()
  def stats do
    Repo.one(
      from g in GlossaryEntry,
        select: %{
          entries: count(g.id),
          sanskrit: count(g.sanskrit),
          tibetan: count(g.tibetan),
          chinese: count(g.chinese),
          distinct_sanskrit: fragment("count(distinct ?)", g.sanskrit),
          distinct_tibetan: fragment("count(distinct ?)", g.tibetan),
          sanskrit_attested_in_a_source:
            fragment("count(*) filter (where ? = 'source')", g.sanskrit_attestation),
          three_way:
            fragment(
              "count(*) filter (where ? is not null and ? is not null and ? is not null)",
              g.sanskrit,
              g.tibetan,
              g.chinese
            )
        }
    )
  end

  @doc """
  Sanskrit terms with more than one Tibetan rendering, most divergent first.

  2,756 of them. This is the corpus's own evidence that a term does not have *a*
  translation, gathered without asking a model anything.
  """
  @spec divergent(keyword()) :: [map()]
  def divergent(opts \\ []) do
    Repo.all(
      from g in GlossaryEntry,
        where: not is_nil(g.sanskrit) and not is_nil(g.tibetan),
        group_by: g.sanskrit,
        having: count(g.tibetan, :distinct) > 1,
        select: %{
          sanskrit: g.sanskrit,
          renderings: count(g.tibetan, :distinct),
          entries: count(g.id)
        },
        order_by: [desc: count(g.tibetan, :distinct), asc: g.sanskrit],
        limit: ^Keyword.get(opts, :limit, 50)
    )
  end

  defp attested(query, true), do: where(query, [g], g.sanskrit_attestation == "source")
  defp attested(query, _), do: query

  defp present(%GlossaryEntry{} = entry) do
    %{
      sanskrit: entry.sanskrit,
      tibetan: entry.tibetan,
      wylie: entry.wylie,
      chinese: entry.chinese,
      english: entry.english,
      english_alternatives: entry.english_alternatives,
      # Never omitted. A caller holding `yūpa` with no note that it is reconstructed will
      # cite it as though a Sanskrit text said so.
      attestation: %{
        sanskrit: entry.sanskrit_attestation,
        tibetan: entry.tibetan_attestation,
        chinese: entry.chinese_attestation
      },
      work_id: entry.work_id,
      definition: entry.definition,
      source: entry.source_id
    }
  end
end
