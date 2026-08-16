defmodule PramanaWeb.MCP.Tools.DefineFromCanon do
  @moduledoc """
  Finds where the canon defines a term, so a definition can be **quoted** rather than
  composed.

  Both traditions mark definitions with fixed formulae — 云何為X in Chinese,
  Katamañca X in Pāli — because these texts were made to be recited. Searching for the
  formula immediately followed by the term finds the handful of places the canon stops
  to say what something is, out of the thousands where it merely uses the word.

  This tool does not know what a term means. It knows where the tradition says what it
  means, which is a smaller claim and a checkable one.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Pramana.Definitions

  schema do
    field(:term, :string,
      required: true,
      description:
        "The term to find defined, in its own script — 正見, or sammādiṭṭhi. Not an " <>
          "English gloss: the search is for the canon's own words."
    )

    field(:language, :string,
      description:
        "Which tradition's formulae to use: lzh (Literary Chinese) or pli (Pāli). " <>
          "Inferred from the term's script when omitted."
    )

    field(:limit, :integer, description: "Maximum passages to return. Defaults to 10.")

    field(:redistributable_only, :boolean,
      description: "Restrict to sources whose licence permits republication."
    )

    field(:origin, {:list, :string},
      description:
        "Restrict by composition origin: indic, chinese, japanese, korean, tibetan, " <>
          "unattributed. A definition from a Japanese-composed commentary is a " <>
          "different kind of evidence from one in a translated sūtra."
    )
  end

  @impl true
  def execute(%{term: term} = params, frame) do
    opts =
      [
        language: params[:language],
        limit: params[:limit],
        redistributable_only: params[:redistributable_only],
        origin: params[:origin]
      ]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    {:ok, payload} = Definitions.find(term, opts)

    payload =
      Map.put(
        payload,
        :note,
        "These are passages where the canon states a definition, found by its own " <>
          "definitional formulae. Several texts may define a term differently; that is " <>
          "doctrinal history, not noise. Nothing here is a synthesised gloss."
      )

    {:reply, Response.json(Response.tool(), payload), frame}
  end
end
