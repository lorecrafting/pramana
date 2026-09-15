defmodule Pramana.Derge.Genre do
  @moduledoc """
  What a Tibetan title says about the work's place in a commentarial chain.

  `mix pramana.relations.derive` links a Chinese commentary to its root because the
  commentary's title *contains* the root's: 仁王護國般若波羅蜜多經疏 contains
  仁王護國般若波羅蜜多經. **Tibetan does not work that way**, which is why running that task
  over 2,675 newly-titled Tengyur works found nothing:

      toh4210  ཚད་མ་རྣམ་འགྲེལ་གྱི་ཚིག་ལེའུར་བྱས་པ    Pramāṇavārttika-kārikā   (the root)
      toh4216  ཚད་མ་རྣམ་འགྲེལ་གྱི་འགྲེལ་པ            Pramāṇavārttika-vṛtti

  Neither contains the other. They share a **stem** — `ཚད་མ་རྣམ་འགྲེལ` — and differ by a
  genre suffix naming what kind of text this is. So the stem finds the family and the
  suffix gives the direction, which is the part a shared-text graph cannot supply
  (`docs/PROXIES.md`: its edges are mostly not citations at all).

  ## The suffixes, counted before they were trusted

  Across the 4,575 Tibetan works that carry a title, the commonest endings are ritual
  rather than exegetical — `སྒྲུབ་ཐབས` (sādhana) appears about 700 times and `ཆོ་ག`
  (vidhi) 120. Those are **not** commentary and must not be read as it: a sādhana named
  after a deity shares a stem with every other sādhana for that deity, which would
  manufacture a commentarial chain out of a liturgical one.

  What is left is a modest, genuine set — 321 works whose title ends in one.

  ## Depth, and why the nearest parent is not always the root

      toh4221  ཚད་མ་རྣམ་འགྲེལ་གྱི་རྒྱན                 Pramāṇavārttika-alaṃkāra
      toh4222  ཚད་མ་རྣམ་འགྲེལ་གྱི་རྒྱན་གྱི་འགྲེལ་བཤད    ṭīkā *on the alaṃkāra*

  `toh4222` explains `toh4221`, not the root verses. Treating every member of a stem
  family as commenting on its root would assert something the title denies. So a parent is
  the **longest** other title this one extends, and only the cluster's root when nothing
  more specific fits.
  """

  # Ordered longest-first so `རྒྱ་ཆེར་འགྲེལ་པ` is not matched as `འགྲེལ་པ`, and
  # `འགྲེལ་བཤད` is not matched as `བཤད་པ`.
  #
  # `depth` is the commentarial layer the suffix names: 0 is a root text, 1 explains a
  # root, 2 explains an explanation. It decides `comments_on` versus `subcommentary_of`
  # only as a fallback — the parent's own genre decides it when a parent is found.
  @genres [
    {"རྒྱ་ཆེར་འགྲེལ་པ", :tika, 1},
    {"རྒྱ་ཆེར་འགྲེལ", :tika, 1},
    {"རྒྱ་ཆེར་བཤད་པ", :tika, 1},
    {"འགྲེལ་བཤད", :tika, 2},
    {"དཀའ་འགྲེལ", :panjika, 1},
    {"འགྲེལ་པ", :vrtti, 1},
    {"བཤད་པ", :bhasya, 1},
    {"ཚིག་ལེའུར་བྱས་པ", :karika, 0},
    {"ཚིག་ལེའུར་བྱས", :karika, 0}
  ]

  # Ritual and devotional genres. Present in force and deliberately NOT commentarial: a
  # sādhana shares its stem with every other sādhana for the same deity.
  @non_exegetical ["སྒྲུབ་ཐབས", "ཆོ་ག", "བསྟོད་པ", "སྔགས", "མན་ངག"]

  # `ཞེས་བྱ་བ` / `ཅེས་བྱ་བ` — "called", a title-forming particle that can follow the genre.
  @called ~r/(་?(ཞེས|ཅེས|ཞེའོ)་བྱ་བ)+$/u

  # Genitive particles joining stem to genre. Trimmed so `ཚད་མ་རྣམ་འགྲེལ་གྱི་` and
  # `ཚད་མ་རྣམ་འགྲེལ` compare equal.
  @genitive ~r/(་?(གྱི|ཀྱི|གི|ཡི|འི))$/u

  @doc "The genre suffixes recognised, longest first."
  @spec genres() :: [{String.t(), atom(), non_neg_integer()}]
  def genres, do: @genres

  @doc """
  Splits a title into its stem and what the suffix says about it.

  Returns `{stem, genre, depth}`, or `:none` when the title names no commentarial genre —
  which includes every ritual text, and is the answer for most of the canon.
  """
  @spec classify(String.t()) :: {String.t(), atom(), non_neg_integer()} | :none
  def classify(title) when is_binary(title) do
    trimmed = String.replace(title, @called, "")

    if ritual?(trimmed), do: :none, else: match_genre(trimmed)
  end

  defp ritual?(title), do: Enum.any?(@non_exegetical, &String.contains?(title, &1))

  defp match_genre(title) do
    Enum.find_value(@genres, :none, fn {suffix, genre, depth} ->
      if String.ends_with?(title, suffix), do: stem_for(title, suffix, genre, depth)
    end)
  end

  defp stem_for(title, suffix, genre, depth) do
    stem =
      title
      |> String.slice(0, String.length(title) - String.length(suffix))
      # The tsheg comes off FIRST: the particle sits at the end of the stem but the
      # separator sits after it, so testing for `གྱི$` against `…གྱི་` never matches and
      # every stem kept its genitive.
      |> String.trim_trailing("་")
      |> String.replace(@genitive, "")
      |> String.trim_trailing("་")
      |> String.trim()

    if stem == "", do: nil, else: {stem, genre, depth}
  end

  @doc """
  The relation a work of this genre bears to a parent of that one.

  A commentary on a commentary is a **subcommentary**, and that is read from the parent
  rather than from this work's own suffix: `འགྲེལ་པ` on a root is a `vṛtti`, and the same
  suffix on a `རྒྱན` is one layer further out.
  """
  @spec relation_to(non_neg_integer() | nil) :: String.t()
  def relation_to(nil), do: "comments_on"
  def relation_to(parent_depth) when parent_depth >= 1, do: "subcommentary_of"
  def relation_to(_), do: "comments_on"

  @doc """
  Trims a title to the form two titles can be compared in.

  A parent's title carries no genitive linking it to a suffix it does not have, so the
  particle has to come off both sides before one can be tested as a prefix of the other.
  """
  @spec comparable(String.t()) :: String.t()
  def comparable(title) do
    title
    |> String.replace(@called, "")
    |> String.trim_trailing("་")
    |> String.replace(@genitive, "")
    |> String.trim_trailing("་")
    |> String.trim()
  end
end
