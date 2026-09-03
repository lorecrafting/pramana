defmodule PramanaWeb.MCP.Tools.GetCommentaryOutline do
  @moduledoc """
  Where in its root a commentary does its work — the 科文 outline, by juan.

  `get_glosses` answers *what explains this line*, from the root's side. This is the same
  evidence from the commentary's side: **which parts of the root this commentary works
  over, and which it passes by.**

  ## A shape, not a list

  `T1509` 大智度論 anchors 21,834 lemmas to `T0223`. A hundred of them answers nothing and
  all of them are not an answer either, so this returns the distribution: 27 juan touched,
  with the lemma and line counts in each. That is what tells a reader whether the
  commentary will help with the passage they care about, which a page of lemmas does not.

  Fetch the lemmas themselves with `get_glosses` on a line the outline points at.

  ## An absent juan is a claim, and a stated one

  A juan the commentary never quotes does not appear. 科文 alignment sees verbatim
  quotation only, so an absent juan means *nothing here was quoted* — usually because the
  commentary stops partway through its root, sometimes because it paraphrases that stretch.
  **It never means the juan is missing from the corpus**, and the reply says so, because a
  gap in a list of divisions is exactly the shape a reader mistakes for an absence in the
  canon.
  """

  use Anubis.Server.Component, type: :tool

  alias Pramana.Commentary
  alias PramanaWeb.MCP.Reply

  schema do
    field(:work_id, :string,
      required: true,
      description: "A commentary's work id, e.g. T1509 for 大智度論."
    )
  end

  @impl true
  def execute(%{work_id: work_id} = params, frame) do
    outline = Commentary.outline(work_id)

    payload =
      outline
      |> Map.put(:note, note(outline))
      |> Map.put(:bake_id, Pramana.Bake.current_id())

    {:reply, Reply.json("get_commentary_outline", params, payload), frame}
  end

  defp note(%{roots: []}) do
    "No 科文 alignment exists for this work. That is NOT evidence it explains nothing: " <>
      "alignment needs an asserted relation to a root held in this corpus, and it sees " <>
      "verbatim quotation only, so a commentary that paraphrases aligns to nothing. Ask " <>
      "`get_commentaries` with `direction: this_explains` for what it is recorded as " <>
      "explaining at all."
  end

  defp note(%{lemmas: lemmas, roots: roots}) do
    juan = roots |> Enum.map(&length(&1.juan)) |> Enum.sum()

    "#{lemmas} lemmas anchored across #{juan} juan of #{length(roots)} root(s), by " <>
      "deterministic lemma match — every one is a phrase this commentary quotes verbatim " <>
      "before glossing it. A juan absent from this list is one nothing was quoted from, " <>
      "which is a fact about the commentary and NOT about the corpus: the root is held in " <>
      "full. Counts are complete rather than a page — fetch the lemmas for any line with " <>
      "`get_glosses`."
  end
end
