defmodule Pramana.Translators do
  @moduledoc """
  Which Chinese word each translator chose for the same thing — 異譯本 compared.

  Two translators rendering the same Indic original into Chinese make different lexical
  choices, and those choices are the most consequential thing about a translation. Whether
  *anattā* is 無我 ("there is no self") or 非我 ("this is not self") is one of the largest
  doctrinal disputes in the tradition, and it is a translator's decision. This finds those
  decisions by comparing parallel translations against each other.

  Deterministic: character n-gram rates, no model. `CLAUDE.md` invariant #5.

  ## The method, and the confound that dominated it

  For a pair of works recorded as `parallel_of` with different attributed translators,
  compare each n-gram's rate per 10,000 characters. A term frequent in one and absent from
  the other is a candidate rendering preference.

  **Punctuation had to be stripped, and stripping it was the difference between noise and
  signal.** CBETA's punctuation is a modern editorial addition and not in the witness — so a
  punctuation difference between two editions is the *editor's*, never the translator's.
  With it in, the top results for T0099 against T0100 were `？謂`, `、苦`, `、意`, `、鼻`,
  `、舌`: bigrams that are half punctuation. With it out, the same query returns

      入處  409:0   āyatana, the sense bases
      覺分  331:0   bodhyaṅga, the factors of awakening
      緣生  236:0   dependent arising
      道跡  286:1   paṭipadā, the path
      法律  218:0   dharma-vinaya
      士夫  187:0   puruṣa
      壞淨  154:0   avecca-pasāda, unshakeable confidence

  which is Guṇabhadra's technical vocabulary against the anonymous translator's, and is what
  the feature is for. Roughly ten of fourteen top results are genuine terms where before it
  was two.

  ## Where it does not work, measured

  **The Dharmapada pair stays noisy** — T0210 against T0212 returns `句經`, `經第`, `品法`,
  `品者`: fragments of chapter headings that sit inline in the body text of one edition and
  not the other. The method cannot tell a structural artefact from a lexical choice, so it
  works on prose sūtra collections and fails where an edition's apparatus leaks into its
  body. Results are returned with their counts so a reader can see which they are looking
  at; nothing here is presented as a finding rather than as evidence.
  """

  import Ecto.Query

  alias Pramana.Corpus.Text
  alias Pramana.Repo

  # Punctuation, and whitespace we introduced. Both are ours or the editor's, never the
  # translator's.
  @editorial ~r/[\s，。、；：？！「」『』（）〔〕【】…—·]/u

  @type preference :: %{
          term: String.t(),
          count: non_neg_integer(),
          other_count: non_neg_integer(),
          rate: float(),
          other_rate: float(),
          skew: float()
        }

  @doc """
  Terms one translation uses that its parallel does not, commonest skew first.

  ## Options

    * `:n` — n-gram length in characters, default 2. Buddhist technical terms are
      overwhelmingly two characters; 3 and 4 find compound formulae.
    * `:min_count` — floor on occurrences in the first work, default 12. Below that a
      "preference" is a handful of occurrences and reads as one.
    * `:limit` — default 20.
  """
  @spec preferences(String.t(), String.t(), keyword()) ::
          {:ok, [preference()]} | {:error, :not_found}
  def preferences(work_id, against_work_id, opts \\ []) do
    with {:ok, a} <- body(work_id),
         {:ok, b} <- body(against_work_id) do
      n = Keyword.get(opts, :n, 2)
      min_count = Keyword.get(opts, :min_count, 12)

      a_grams = ngrams(a, n)
      b_grams = ngrams(b, n)
      a_total = total(a_grams)
      b_total = total(b_grams)

      {:ok,
       a_grams
       |> Enum.filter(fn {_term, count} -> count >= min_count end)
       |> Enum.map(&preference(&1, b_grams, a_total, b_total))
       |> Enum.sort_by(& &1.skew, :desc)
       |> Enum.take(Keyword.get(opts, :limit, 20))}
    end
  end

  defp preference({term, count}, b_grams, a_total, b_total) do
    other = Map.get(b_grams, term, 0)
    rate = 10_000 * count / max(a_total, 1)
    other_rate = 10_000 * other / max(b_total, 1)

    %{
      term: term,
      count: count,
      other_count: other,
      rate: Float.round(rate, 2),
      other_rate: Float.round(other_rate, 2),
      # RATES, not counts. The two works are different lengths — T0099 is 1.7x T0100 — and
      # comparing raw counts would report that difference as a lexical preference.
      # The floor on the denominator keeps an absent term finite rather than infinite,
      # which would sort every hapax above every real preference.
      skew: Float.round(rate / max(other_rate, 0.05), 1)
    }
  end

  defp body(work_id) do
    case Repo.one(from t in Text, where: t.work_id == ^work_id, select: t.body, limit: 1) do
      nil -> {:error, :not_found}
      body -> {:ok, body}
    end
  end

  defp total(grams), do: grams |> Map.values() |> Enum.sum()

  # Editorial punctuation removed before windowing. See the moduledoc: this is the whole
  # difference between the top results being technical vocabulary and being `、苦`.
  defp ngrams(text, n) do
    chars = text |> String.replace(@editorial, "") |> String.graphemes() |> List.to_tuple()
    last = tuple_size(chars) - n

    if last < 0 do
      %{}
    else
      Enum.reduce(0..last, %{}, fn i, acc ->
        Map.update(acc, window(chars, i, n), 1, &(&1 + 1))
      end)
    end
  end

  defp window(chars, i, n), do: Enum.map_join(i..(i + n - 1), &elem(chars, &1))
end
