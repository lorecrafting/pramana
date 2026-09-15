defmodule Pramana.Cbeta.Byline do
  @moduledoc """
  Composition origin read from a CBETA work's own byline.

  `Pramana.Taisho.Divisions` assigns provenance from the 部 table, which exists for the
  **Taishō** and for nothing else. CBETA holds 26 collections; the second largest, X
  (卍新纂大日本續藏經, 1,236 works), has its own arrangement and no such table. Ingesting
  it without provenance would give a third of the Chinese corpus no origin axis at all,
  which is invariant #4 failing quietly.

  The edition states the claim itself, in the byline, and **the verb is the
  discriminator**:

      唐 王勃撰            Tang · Wang Bo · COMPOSED     -> chinese
      後秦 佛陀耶舍…譯      Later Qin · Buddhayaśas · TRANSLATED -> indic

  This is the same move as the Tengyur naming itself from its own incipit rather than
  from an acquired catalogue: the edition's own statement is better evidence than a
  modern editor's table, and unlike a table it is present for every work that has an
  author.

  ## It is validated, not asserted

  The rule was checked against the one collection where independent ground truth exists.
  For the Taishō, provenance is already derived from the 部 table, so the two can be
  compared over 2,077 works where both are known:

      byline says indic,   table says indic     1,645
      byline says chinese, table says chinese     375
      byline says chinese, table says indic        36
      byline says indic,   table says chinese      21

  **2,020 of 2,077 agree — 97.3%.**

  The 57 disagreements are not all the byline being wrong. The 部 table assigns by volume
  **range**, so a Chinese-composed work sitting inside an Indic division is mislabelled by
  the table and labelled correctly by its own byline. That is why this rule is a *fallback*
  and never overrides the division table for the Taishō: the table is the curated,
  work-number-precise source there, and disagreement is a question for a scholar rather
  than something to resolve by preferring whichever ran last.

  ## What it deliberately does not decide

  **`text_role` is left unknown.** The verb says how a text *arrived* — translated or
  composed — and `text_role` means what a text *does*: `root`, `treatise`, `commentary`,
  `history`. 撰 covers all of those. Guessing would put a wrong label on thousands of works
  in a field the API groups results by, and a null is honest where a guess is not.
  """

  # 譯 — translated. The work came from an Indic original, whoever carried it across.
  # `失譯` ("translator lost") is still a translation: the attribution is missing, not the
  # fact of translation.
  @translated ~w(譯 奉詔譯 共譯)

  # Composed, narrated, authored, compiled, recorded, annotated, glossed. All of these
  # describe someone writing rather than rendering, so the work originates where its
  # author did.
  @composed ~w(撰 述 著 集 錄 記 註 注 疏 解 選 編 修 造)

  @doc """
  Composition origin for a byline, as attributes ready to merge into a work.

  Returns `%{}` rather than a guess when the byline is absent or its verb is not one this
  rule recognises — an unlabelled work is a smaller problem than a mislabelled one, and
  the API can filter on "unknown" while it cannot detect a confident error.
  """
  @spec provenance(String.t() | nil) :: map()
  def provenance(byline) when is_binary(byline) do
    trimmed = String.trim(byline)

    cond do
      trimmed == "" -> %{}
      japanese?(trimmed) -> %{composition_origin: "japanese"}
      ends_with_any?(trimmed, @translated) -> %{composition_origin: "indic"}
      String.starts_with?(trimmed, "失譯") -> %{composition_origin: "indic"}
      ends_with_any?(trimmed, @composed) -> %{composition_origin: "chinese"}
      true -> %{}
    end
  end

  def provenance(_), do: %{}

  @doc """
  The verb this byline ends with, or `nil`. Exposed so a caller auditing the rule can see
  what it matched on rather than only what it concluded.
  """
  @spec verb(String.t() | nil) :: String.t() | nil
  def verb(byline) when is_binary(byline) do
    Enum.find(@translated ++ @composed, &String.ends_with?(String.trim(byline), &1))
  end

  def verb(_), do: nil

  # Checked BEFORE the verb, because a Japanese author also 撰s. X is published in Japan
  # and holds Japanese-composed material alongside the Chinese, so this is not hypothetical.
  defp japanese?(byline), do: String.contains?(byline, "日本")

  defp ends_with_any?(text, suffixes), do: Enum.any?(suffixes, &String.ends_with?(text, &1))
end
