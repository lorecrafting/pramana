defmodule Pramana.Translate.Glossary do
  @moduledoc """
  Pinned term renderings, for the prompt a generative arm is given.

  `docs/PLAN.md` § E1 specifies the index tier as "prose, glossary-pinned", and this is
  the pinning half. It lives in Elixir and not in `priv/embed`, which is the boundary
  `docs/ELIXIR.md` names as the one the architecture test cannot enforce: a term table
  inside the sidecar is the drift, so the terms are chosen here and arrive there as
  opaque text.

  ## Only term-like entries, and a consensus among them

  The glossaries hold 24,811 Chinese-English pairs and most are **definitions rather than
  renderings** — `娑婆` glosses as "a transliteration of Sabhā (= Sahā, the name of the
  world in which we live)", which is true and is not what a translator should write.
  Pinning those would be worse than pinning nothing. What survives the filter is 4,533
  terms, of which **4,353 are unanimous across every glossary that records them** and 180
  are contested; the contested ones are the famous ones — `四聖諦` appears as "four noble
  truths", "four truths of the noble ones" and "truths of the noble ones".

  ## Three characters and up, because two-character terms are mostly function words

  62% of the term-like entries are two characters, and that band mixes real vocabulary
  (`般若`, `涅槃`) with grammar: the first pinned prompt this produced opened with
  `云何 = why?`, which is "how" or "what is" at least as often, and `比丘 = bhikṣu`, which
  moves the English AWAY from the "monk" a reader would type. Multi-character compounds
  are where the doctrinal vocabulary actually lives — `四聖諦`, `八正道`, `四念處`,
  `七覺支`, `十二因緣`, `三十七道品` are every one of them three characters or more — and
  the two-character terms this drops are largely ones a model already transliterates
  consistently without being told.

  ## Pinning is a hypothesis here, not a settled good

  It is worth stating what could go wrong, because the index tier is scored on whether a
  *reader's* English reaches the line rather than on terminological correctness. The
  glossary renders `四念處` as "four applications of mindfulness"; the gold set asks "What
  are the four **foundations** of mindfulness?" Pinning the lexicographer's phrasing can
  therefore move the rendering AWAY from the phrasing a reader will type. Which effect
  dominates is measured, not assumed — see `docs/PROXIES.md`.
  """

  alias Pramana.Repo

  @max_pins 12

  @doc """
  The consensus rendering for every term-like glossary entry.

  Returns `[{chinese, english}]` sorted longest-first, so that a passage containing
  `四無量心` pins that rather than the `四` inside it.
  """
  @spec table() :: [{String.t(), String.t()}]
  def table do
    """
    WITH term_like AS (
      SELECT chinese, lower(trim(english)) AS en
      FROM glossary_entries
      WHERE chinese IS NOT NULL AND english IS NOT NULL
        AND char_length(chinese) BETWEEN 3 AND 8
        AND char_length(english) BETWEEN 3 AND 40
        AND english !~ '(name of|transliteration|a kind of|see |cf\\.|abbrev)'
        AND english !~ ',|;|\\('
    ),
    counted AS (SELECT chinese, en, count(*) n FROM term_like GROUP BY 1, 2),
    ranked AS (
      SELECT chinese, en,
             row_number() OVER (PARTITION BY chinese ORDER BY n DESC, char_length(en)) rn
      FROM counted
    )
    SELECT chinese, en FROM ranked WHERE rn = 1
    """
    |> Repo.query!()
    |> Map.fetch!(:rows)
    |> Enum.map(fn [zh, en] -> {zh, en} end)
    |> Enum.sort_by(fn {zh, _} -> -String.length(zh) end)
  end

  @doc """
  The pins that apply to one passage: the terms it actually contains.

  Capped at #{@max_pins}, longest first. A prompt carrying four thousand terms is a prompt
  the model reads instead of the passage, and the long terms are the technical ones — a
  passage containing `四無量心` is better served by pinning that than by pinning the
  common characters inside it.

  Overlaps are dropped: once `四無量心` is pinned, `無量` inside it is not, because two
  pins covering the same characters give the model contradictory instructions about one
  span.
  """
  @spec pins_for(String.t(), [{String.t(), String.t()}]) :: [{String.t(), String.t()}]
  def pins_for(passage, table) do
    table
    |> Enum.filter(fn {zh, _en} -> String.contains?(passage, zh) end)
    |> Enum.reduce([], &keep_unless_covered/2)
    |> Enum.reverse()
    |> Enum.take(@max_pins)
  end

  defp keep_unless_covered({zh, en}, kept) do
    if covered?(kept, zh), do: kept, else: [{zh, en} | kept]
  end

  defp covered?(kept, zh), do: Enum.any?(kept, fn {other, _} -> String.contains?(other, zh) end)

  @doc """
  The instruction a chat-shaped arm is given, or `nil` when nothing applies.

  Returns `nil` rather than an empty instruction so a passage with no pinned terms is
  prompted exactly as an unpinned run would prompt it — otherwise the comparison measures
  the presence of a preamble rather than the presence of terms.
  """
  @spec instruction(String.t(), [{String.t(), String.t()}]) :: String.t() | nil
  def instruction(passage, table) do
    case pins_for(passage, table) do
      [] ->
        nil

      pins ->
        terms = Enum.map_join(pins, "\n", fn {zh, en} -> "  #{zh} = #{en}" end)

        "Render these terms exactly as given:\n#{terms}\n\n" <>
          "Translate the passage below into English. Reply with the translation only."
    end
  end
end
