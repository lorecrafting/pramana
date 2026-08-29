defmodule PramanaWeb.MCP.Tools.GetQuotations do
  @moduledoc """
  Every other text that reproduces this passage word for word.

  Commentaries quote their root texts constantly, and the Chinese canon recycles stock
  passages across works compiled centuries apart. The graph is built by scanning for
  **character identity** — no model, no embedding, no similarity threshold — so a result
  is either true or it is a bug, never a judgement call.

  **Neither end is marked as the origin.** Identical characters say nothing about who
  quoted whom; that is a conclusion about dates and transmission, and this evidence does
  not carry it. A tool that labelled one end "source" would be adding a claim the scan
  cannot support.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias PramanaWeb.MCP.Reply
  alias Pramana.Quotations

  schema do
    field(:urn, :string,
      required: true,
      description:
        "The passage to look up, e.g. pramana:cbeta.T:T0125_024@p0676c15. Any recorded " <>
          "reuse OVERLAPPING this line is returned — a commentary quoting a clause of it " <>
          "is still quoting it."
    )

    field(:limit, :integer, description: "Maximum quotations to return. Defaults to 50.")
  end

  @impl true
  def execute(%{urn: urn} = params, frame) do
    opts = if params[:limit], do: [limit: params[:limit]], else: []

    case Quotations.quoting(urn, opts) do
      {:ok, payload} ->
        {:reply, Reply.json("get_quotations", params, payload), frame}

      {:error, :not_found} ->
        {:reply,
         Response.error(
           Response.tool(),
           "No passage exists at #{urn}. This URN is well-formed but addresses nothing " <>
             "in the current bake — do not cite it."
         ), frame}

      {:error, _} ->
        {:reply,
         Response.error(
           Response.tool(),
           "Malformed URN: #{urn}. Expected pramana:<source>.<witness>:<work>@<locator>."
         ), frame}
    end
  end
end
