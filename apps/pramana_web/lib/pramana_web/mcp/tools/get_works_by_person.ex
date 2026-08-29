defmodule PramanaWeb.MCP.Tools.GetWorksByPerson do
  @moduledoc """
  Everything one person translated or composed, gathered under a single identity.

  A byline is what the edition printed — `劉宋 求那跋陀羅譯`, `宋 求那跋陀羅譯`,
  `劉宋 天竺三藏求那跋陀羅譯` — and those are three strings for one man. Searching the text
  finds one of them. This asks by **DILA authority id**, which is why the answer is 31 works
  rather than whichever spelling you happened to type.

  `provenance.authority_id` on any passage is where that id comes from, so the flow is:
  find a passage, read its `authority_id`, ask this for the rest of the hand.

  ## The bylines come back with the works

  They are the evidence for the grouping, and a caller may disagree with it. Roughly 40% of
  bylines cannot be resolved confidently and carry no id at all — they name someone the
  authority does not record under that spelling, name several people at once, or carry a
  dynasty no namesake shares. Those are refusals, not gaps, and `Pramana.Authority` never
  claims `certain`: the name is certainly in the byline, that it denotes this person rather
  than an unrecorded namesake is an inference.

  ## Nothing here is text

  Works, titles and attribution only. Fetch any of them by URN to read them, under the same
  guard and the same provenance as anything else.
  """

  use Anubis.Server.Component, type: :tool

  alias Pramana.Authority
  alias PramanaWeb.MCP.Reply

  schema do
    field(:authority_id, :string,
      required: true,
      description:
        "A DILA authority person id, e.g. A000527 for 求那跋陀羅. Read it from any " <>
          "passage's provenance.authority_id."
    )

    field(:limit, :integer, description: "Maximum works to return (default 100).")
  end

  @impl true
  def execute(%{authority_id: id} = params, frame) do
    result = Authority.works(id, limit: params[:limit] || 100)

    payload =
      result
      |> Map.put(:note, note(result))
      |> Map.put(:bake_id, Pramana.Bake.current_id())

    {:reply, Reply.json("get_works_by_person", params, payload), frame}
  end

  # `count` is every work with this id; `returned` is this page. Reporting only the page
  # would make a limit look like a total, which is the denominator failure this project
  # treats as its most characteristic bug.
  defp note(%{count: 0}),
    do:
      "No work in this bake carries that authority id. About 40% of bylines resolve to no " <>
        "person at all — a refusal rather than a gap — so a translator being absent here " <>
        "does not mean the corpus lacks their work."

  defp note(%{count: count, returned: returned}) when count > returned,
    do:
      "#{count} works carry this id; #{returned} returned. Raise `limit` for the rest. " <>
        "The bylines listed are the evidence for the grouping and are never `certain`."

  defp note(_),
    do:
      "The bylines listed are the evidence for the grouping. An authority link is " <>
        "`probable`, never `certain`: the name is in the byline, but that it denotes this " <>
        "person rather than an unrecorded namesake is an inference."
end
