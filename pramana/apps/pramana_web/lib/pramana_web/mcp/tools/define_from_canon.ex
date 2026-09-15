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

  ## Grouped by provenance, and why that became urgent

  Results come back bucketed by composition origin and text role, exactly as `search`
  does, because "the canon defines X" is a claim about *who* is defining it. This tool's
  own `origin` field has always said that "a definition from a Japanese-composed
  commentary is a different kind of evidence from one in a translated sūtra" — and it
  returned a flat list in which the two were indistinguishable without inspecting every
  result.

  That was survivable while the Taishō was the whole corpus and definitional formulae
  matched root scripture almost exclusively. CBETA X added 1,230 mostly-commentarial
  works, and a commentary QUOTING 云何為二法 is a genuine lexical match for it: 云何為二法
  now ranks X0771 釋摩訶衍論疏, a Chinese commentary, above the Ekottarika Āgama passage.
  Both are real results. Presenting them in one undifferentiated list is how a Ming
  gloss gets reported as the canon's definition.
  """

  use Anubis.Server.Component, type: :tool

  alias Pramana.Definitions
  alias Pramana.Provenance
  alias PramanaWeb.MCP.Reply

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
      payload
      # Grouped, never flat — `Pramana.Provenance.group/1`, the same function `search`
      # uses, so the two tools cannot describe one provenance bucket differently.
      |> Map.put(:groups, group(payload.results))
      |> Map.delete(:results)
      |> Map.put(
        :note,
        "These are passages where the canon states a definition, found by its own " <>
          "definitional formulae. Several texts may define a term differently; that is " <>
          "doctrinal history, not noise — and it is only readable if you attend to WHICH " <>
          "bucket each definition came from. A commentary quoting a formula is a genuine " <>
          "match for it, so a gloss by a Ming exegete and a definition in a translated " <>
          "sūtra can both appear here. They are not the same kind of evidence. Nothing " <>
          "here is a synthesised gloss."
      )

    {:reply, Reply.json("define_from_canon", params, payload), frame}
  end

  defp group(results) do
    results
    |> Provenance.group()
    |> Enum.map(fn bucket ->
      %{bucket | results: Enum.map(bucket.results, &definition/1)}
    end)
  end

  # The FORMULA travels with each result. Which of 云何為 / 何謂 / 何等為 matched is
  # evidence about how strong the claim is — `云何為` is unambiguous, `何謂` also occurs in
  # ordinary rhetorical questions — and it is the kind of thing a flat payload drops.
  defp definition(result) do
    %{
      urn: result.span.urn,
      text: result.span.content,
      sha256: result.span.sha256,
      formula: result[:formula],
      matched_phrase: result[:matched_phrase],
      provenance: result.span.provenance
    }
  end
end
