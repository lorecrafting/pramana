defmodule PramanaWeb.MCP.Tools.GetPerson do
  @moduledoc """
  Who a byline names: dates, sect, place, teachers, students, and the id that leaves.

  `get_works_by_person` says what one hand produced. This says whose hand it was, and it is
  what makes the rest legible — a work's date bound is uninterpretable without the lifespan
  it came from, and "the Caodong reading of this passage" is not a query anyone can run
  until a person carries a sect.

  Read `provenance.authority_id` off any passage, then ask this.

  ## Dates are ranges, and the width is the claim

  DILA records a birth as a year, as a full date, or as a span, and each `birth`/`death`
  here keeps **both ends** plus `exact`. A date known to the day and a date known to the
  decade are different evidence, and collapsing them to one number destroys the difference
  irreversibly. `note` carries whatever qualification DILA attached.

  `null` means no date is recorded — never a guess, and never an empty range standing in
  for one.

  ## Lineage is reported, never inferred

  `teachers` and `students` are what DILA states, each with the `source` that states it.
  Nothing here derives a relationship from shared dates, shared sect, or co-occurrence in a
  text. Inferred lineage is how a scholarly claim gets manufactured out of a coincidence,
  and this project's whole posture is that a claim carries its warrant or does not travel.

  A chain can branch — a person may have several recorded teachers — and it can cycle,
  because sources disagree about who taught whom and the authority records the
  disagreement. `Pramana.Authority.teacher_chain/2` walks it and stops; a cycle is data,
  not a bug.

  ## A place resolves into two region schemes, and both are returned

  `place_of_origin` is the string the person authority printed — 錢唐. `place` is what the
  place authority knows about that id, and it carries **two independent regions**:

  - `district` / `district_path` — the modern administrative path,
    `中國-浙江省-杭州市-下城區`, which is what makes places group by province.
  - `historical_region` — the unit of its own time: 江南東道, 隴右道, 西突厥. Tang circuits,
    not modern states, and this is the one a scholar means by "a Jiangnan translator".

  Both spellings are returned because the two authority files are maintained separately and
  can disagree; neither is corrected against the other.

  `lon` and `lat` are named rather than returned as a pair, because DILA publishes `<geo>`
  **longitude first** — the reverse of TEI's own convention — and `certainty` is DILA's own
  and travels with the value. `place` is `null` where the place file does not define the id,
  which is a missing record rather than a place nothing is known about.

  ## `external_ids` is the exit from this corpus

  Wikidata Q-ids and whatever else DILA carries. They are pass-throughs — nothing here
  fetches them and their correctness is DILA's claim, not ours — but they are how a caller
  joins a translator to dates, places and bibliography this corpus will never hold.

  ## Nothing here is text, and an id is not a certainty

  Identity and attribution only; fetch any work by URN to read it. And an authority link is
  `probable`, never `certain`: the name is certainly in the byline, that it denotes this
  person rather than an unrecorded namesake is an inference. About 40% of bylines resolve
  to nobody at all, which is a refusal rather than a gap.
  """

  use Anubis.Server.Component, type: :tool

  alias Pramana.Authority
  alias PramanaWeb.MCP.Reply

  schema do
    field(:authority_id, :string,
      required: true,
      description:
        "A DILA authority person id, e.g. A000527. Read it from any passage's " <>
          "provenance.authority_id, or from get_works_by_person."
    )

    field(:teacher_chain_depth, :integer,
      description:
        "How far to walk the teacher chain upward, default 0 (do not walk). The chain " <>
          "follows the first recorded teacher at each step and reports whether it branched."
    )
  end

  @impl true
  def execute(%{authority_id: id} = params, frame) do
    case Authority.person(id) do
      nil ->
        {:reply,
         Reply.error(
           "get_person",
           params,
           :unknown_authority_id,
           "No authority person #{id}. Ids come from provenance.authority_id on a passage; " <>
             "an unrecognised one is an unknown id, not a person with nothing recorded."
         ), frame}

      person ->
        payload =
          person
          |> maybe_chain(id, params[:teacher_chain_depth])
          |> Map.put(:note, note(person))

        {:reply, Reply.json("get_person", params, payload), frame}
    end
  end

  defp maybe_chain(person, _id, depth) when depth in [nil, 0], do: person

  defp maybe_chain(person, id, depth),
    do: Map.put(person, :teacher_chain, Authority.teacher_chain(id, depth: depth))

  # The note says what is MISSING, because that is what a caller cannot see. A person with
  # no dates and a person whose dates were not looked up are the same shape in the response.
  defp note(person) do
    gaps =
      [
        {is_nil(person.birth) and is_nil(person.death), "no birth or death date is recorded"},
        {is_nil(person.sect), "no sect is recorded"},
        {is_nil(person.place), "no place of origin resolves"},
        {person.external_ids == %{}, "no external id (Wikidata or otherwise) is recorded"},
        {person.lineage.teachers == [] and person.lineage.students == [],
         "no teacher or student is recorded"}
      ]
      |> Enum.filter(&elem(&1, 0))
      |> Enum.map(&elem(&1, 1))

    base =
      "Identity and attribution from DILA's person authority, CC BY-SA 3.0. Relations are " <>
        "as DILA states them and are never inferred. An authority link on a work is " <>
        "`probable`, never `certain`."

    case gaps do
      [] -> base
      gaps -> base <> " For this person " <> Enum.join(gaps, ", ") <> "."
    end
  end
end
