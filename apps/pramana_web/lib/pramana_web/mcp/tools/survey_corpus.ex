defmodule PramanaWeb.MCP.Tools.SurveyCorpus do
  @moduledoc """
  Exhaustive counts for a phrase across the whole corpus.

  Use this instead of `search` when the question is *how much* or *where*, not *show
  me some*. `search` returns a ranked handful; this counts everything and breaks it
  down by composition origin, text role, and Taishō division.

  The distinction matters because a model handed five results will generalise from
  five results. "Appears 340 times across 89 works, 71% of them Chinese-composed
  commentary" is a different claim from "here are five passages", and only one of them
  is defensible.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Pramana.Retrieval.Survey

  schema do
    field(:query, :string,
      required: true,
      description: "Exact phrase to count, in the source language, e.g. 一切眾生皆有佛性."
    )

    field(:origin, :string,
      description: "Restrict to a composition origin: indic, chinese, japanese, tibetan, korean."
    )

    field(:role, :string,
      description:
        "Restrict to a text role: root, treatise, commentary, subcommentary, " <>
          "apocryphon, catalogue, history."
    )

    field(:division, :string,
      description: "Restrict to one Taishō division (部), e.g. 阿含部, 經疏部, 疑似部."
    )

    field(:top_works, :integer, description: "How many top works to list. Default 10.")
  end

  @impl true
  def execute(params, frame) do
    opts =
      [
        origin: params[:origin],
        role: params[:role],
        division: params[:division],
        top_works: params[:top_works]
      ]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    case Survey.survey(params.query, opts) do
      {:ok, result} ->
        {:reply, Response.json(Response.tool(), result), frame}

      {:error, :empty_query} ->
        {:reply, Response.error(Response.tool(), "Query is empty."), frame}

      {:error, reason} ->
        {:reply, Response.error(Response.tool(), "Survey failed: #{reason}"), frame}
    end
  end
end
