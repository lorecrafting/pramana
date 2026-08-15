defmodule PramanaWeb.MCP.Resources.Inventory do
  @moduledoc """
  What is actually in this bake, as an MCP resource.

  Live counts rather than prose, so a model can tell the difference between "the canon
  does not say that" and "that part of the canon is not loaded yet."
  """

  # See `PramanaWeb.MCP.Resources.Guide` — the macro generates `name/0` from these
  # options and does not mark it overridable.
  use Anubis.Server.Component,
    type: :resource,
    uri: "pramana://inventory",
    name: "Corpus inventory",
    mime_type: "application/json"

  import Ecto.Query

  alias Anubis.Server.Response
  alias Pramana.Bake
  alias Pramana.Corpus.Work
  alias Pramana.Repo
  alias Pramana.Retrieval.Semantic

  @impl true
  def description,
    do: "Live counts for the current bake: works, segments, provenance, embedding coverage."

  @impl true
  def read(_params, frame) do
    {:reply, Response.json(Response.resource(), inventory()), frame}
  end

  defp inventory do
    %{
      bake_id: Bake.current_id(),
      pipeline_version: Bake.pipeline_version(),
      corpus: Bake.stats(),
      embedding_coverage: Semantic.coverage(),
      by_composition_origin: group(:composition_origin),
      by_text_role: group(:text_role),
      divisions: divisions(),
      note:
        "Counts are live for the current bake. Absence from this inventory means a " <>
          "text is not loaded, which is different from the canon not containing it."
    }
  end

  defp group(field) do
    Repo.all(
      from(w in Work,
        group_by: field(w, ^field),
        select: {field(w, ^field), count(w.id)},
        order_by: [desc: count(w.id)]
      )
    )
    |> Map.new(fn {key, n} -> {key || "unattributed", n} end)
  end

  defp divisions do
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
