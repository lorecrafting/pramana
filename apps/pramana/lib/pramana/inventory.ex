defmodule Pramana.Inventory do
  @moduledoc """
  What is actually in the current bake, as live counts.

  Exists so a caller can tell **"the canon does not say that"** from **"that part of the
  canon is not loaded yet"** — opposite answers that look identical from an empty result
  set.

  This lives in the domain app, not in the MCP resource that serves it: `pramana_web` is
  a transport and must not build queries (`docs/CHECKS.md`, architecture review). Phase 8
  will want the same numbers for the reader, and a second implementation is how two
  surfaces start disagreeing about what the corpus contains.
  """

  import Ecto.Query

  alias Pramana.Bake
  alias Pramana.Corpus.Work
  alias Pramana.Coverage
  alias Pramana.Repo
  alias Pramana.Retrieval.Semantic

  @note "Counts are live for the current bake. Absence from this inventory means a " <>
          "text is not loaded, which is different from the canon not containing it."

  @doc "The full inventory: bake identity, corpus size, provenance breakdowns, coverage."
  @spec snapshot() :: map()
  def snapshot do
    %{
      bake_id: Bake.current_id(),
      pipeline_version: Bake.pipeline_version(),
      corpus: Bake.stats(),
      embedding_coverage: Semantic.coverage(),
      by_composition_origin: count_by(:composition_origin),
      by_text_role: count_by(:text_role),
      divisions: divisions(),
      # What is NOT here. The provenance breakdown above says the corpus holds no
      # Japanese-composed works, which is true and, without this, badly misleading.
      taisho_coverage: Coverage.taisho(),
      tibetan_coverage: Coverage.tibetan(),
      note: @note
    }
  end

  @doc """
  Works grouped by one provenance axis, commonest first.

  A null axis is reported as `"unattributed"` rather than dropped: 古逸部 material
  recovered at Dunhuang records where a text was *found*, not where it was composed, so
  null is a considered answer and hiding it would overstate what the corpus knows.
  """
  @spec count_by(atom()) :: %{String.t() => non_neg_integer()}
  def count_by(field) when is_atom(field) do
    Repo.all(
      from(w in Work,
        group_by: field(w, ^field),
        select: {field(w, ^field), count(w.id)},
        order_by: [desc: count(w.id)]
      )
    )
    |> Map.new(fn {key, n} -> {key || "unattributed", n} end)
  end

  @doc "Taishō divisions (部) present in the bake, with work counts."
  @spec divisions() :: [map()]
  def divisions do
    Repo.all(
      from(w in Work,
        where: not is_nil(w.division),
        group_by: [w.division, w.division_en],
        select: %{division: w.division, division_en: w.division_en, works: count(w.id)},
        order_by: [desc: count(w.id)]
      )
    )
  end
end
