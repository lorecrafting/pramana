defmodule PramanaWeb.MCP.Tools.GetOutline do
  @moduledoc """
  A work's table of contents, each entry resolvable to a URN.

  Exists so a caller can survey structure *without* pulling text. That distinction
  matters at this scale: T0262 alone is 5,341 segments and the full canon is millions,
  so "read the work and find the relevant chapter" is not an available strategy. Fetch
  the outline, pick a chapter, then fetch that passage with context.

  The data is CBETA's own `<cb:mulu>` markup — 28 品 chapters, 7 卷 fascicles and 2
  prefaces for the Lotus Sūtra — not an outline we inferred.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Pramana.Corpus

  schema do
    field(:work_id, :string,
      required: true,
      description: "A work id, e.g. T0262 for the Lotus Sutra."
    )
  end

  @impl true
  def execute(%{work_id: work_id}, frame) do
    case Corpus.outline(work_id) do
      {:ok, outline} ->
        payload =
          outline
          # Every tool names the corpus it answered from; an outline is as
          # bake-dependent as a passage, since a re-bake can change the structure.
          |> Map.put(:bake_id, Pramana.Bake.current_id())

        {:reply, Response.json(Response.tool(), payload), frame}

      {:error, :not_found} ->
        {:reply,
         Response.error(
           Response.tool(),
           "No work #{work_id} in the current bake. Use search to find what is available."
         ), frame}
    end
  end
end
