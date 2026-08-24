defmodule Pramana.Retrieval.Terms do
  @moduledoc """
  English doctrinal terms mapped to the Chinese the canon actually prints, expanded at
  **query time only**.

  ## The hole this closes

  `topical/chinese` scored **0%** and `topical/chinese-native` scored **100%** — the same
  twelve questions, differing only in the language they were asked in. The passages are
  indexed and findable; an English query simply never reaches them, because the Chinese
  canon has no English layer to match against and BGE-M3 does not cross into Literary
  Chinese unaided (#42, #43).

  Rewriting the query into Chinese fixes it. Measured over those twelve:

      English query (shipped default)        0.0%  (0/12)
      a natural Chinese rendering           91.7%  (11/12)  mean rank 1.0

  ## Why a glossary and not a translation model

  Because the failure mode is **term choice**, and it is worth ~50 points. The same
  twelve, asked with equally legitimate synonyms, collapse:

      八聖道分 for 八正道 · 四念住 for 四念處 · 七菩提分 for 七覺支
      六處 for 六入處 · 四等心 for 四無量心 · 空定 for 空三昧

      a defensible synonym                  41.7%  (5/12)   mean rank 2.8

  Each of those is real Buddhist Chinese and each is a register **this corpus does not
  print here**, so a lexical match against it returns nothing. A translation model must
  gamble on one rendering. A glossary does not have to: `applications of mindfulness`
  maps to **both** 念住 and 念處, and expanding to every attested form is strictly better
  than picking the likeliest one. That is the whole argument for doing this
  deterministically, and it is `CLAUDE.md` invariant #5 — deterministic before
  probabilistic — arriving at a better answer rather than merely a cheaper one.

  ## Query-side only, never at index time

  Exactly as `Pramana.Retrieval.Variants`: the stored text stays byte-identical to the
  witness, the index is untouched, and the response reports what was expanded so a hit on
  a term the reader did not type is visible rather than surprising.

  ## Where the mappings come from

  `glossary_entries` — 84000's own translator glossaries, **1,105 English↔Chinese pairs**.
  Scholarship, not invention: each pair is a term a translator recorded against a text
  they published. Nothing here is hand-written, which matters because a hand-written
  mapping tuned against the gold set would make the eval measure itself.

  Coverage is the binding limit and is stated rather than hidden: 1,105 pairs is a
  fraction of Buddhist doctrinal vocabulary, so this fires on some queries and not
  others. Growing it is acquisition work, not a code change.
  """

  import Ecto.Query

  alias Pramana.Repo

  # Below this an English headword is too generic to be evidence. `god`, `path`, `mind`
  # appear inside unrelated questions and would drag in Chinese terms the reader never
  # asked about — and a precision failure is worse than a recall miss here, because the
  # reader cannot see it. Same reasoning as Variants excluding `kSemanticVariant`.
  @min_headword_length 8

  # A query is a question, not a document. More than a few doctrinal terms in one query
  # means the matcher is firing on generic language rather than on subject matter.
  @max_headwords 3

  @doc """
  Chinese terms for the English doctrinal vocabulary in `query`.

  Returns `[]` for a query that already contains Han — a Chinese query needs no
  translation, and the corpus answers it at mean rank 1.25 already.

  Matching is on **maximal** headwords: `four noble truths` wins over `noble`, so the
  specific term displaces the generic one it contains rather than both firing.
  """
  @spec expand(String.t()) :: [String.t()]
  def expand(query) when is_binary(query) do
    if String.match?(query, ~r/\p{Han}/u) do
      []
    else
      query
      |> matching_headwords()
      |> maximal()
      |> Enum.sort_by(&String.length(elem(&1, 0)), :desc)
      |> Enum.take(@max_headwords)
      |> Enum.flat_map(fn {_english, chinese} -> chinese end)
      |> Enum.uniq()
    end
  end

  def expand(_), do: []

  # One query against the 1,105 rows that carry Chinese, asking Postgres which headwords
  # are contained in this question. Cheaper than loading the table and matching in Elixir,
  # and it keeps the comparison case-insensitive in one place.
  defp matching_headwords(query) do
    normalized = String.downcase(query)

    from(g in "glossary_entries",
      where:
        not is_nil(g.chinese) and g.chinese != "" and
          not is_nil(g.english) and
          fragment("length(?) >= ?", g.english, ^@min_headword_length) and
          fragment("position(lower(?) in ?) > 0", g.english, ^normalized),
      select: {g.english, g.chinese}
    )
    |> Repo.all()
    |> Enum.group_by(fn {english, _} -> String.downcase(english) end, &elem(&1, 1))
    |> Enum.map(fn {english, chinese} -> {english, Enum.uniq(chinese)} end)
  end

  # Drop any headword contained in a longer one that also matched. `dependent` and
  # `twelve links of dependent origination` both match the same question, and only the
  # second is about the doctrine — the first maps to 依他起[相], an unrelated Yogācāra term.
  defp maximal(matches) do
    Enum.reject(matches, fn {english, _} ->
      Enum.any?(matches, fn {other, _} ->
        other != english and String.contains?(other, english)
      end)
    end)
  end
end
