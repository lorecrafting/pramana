defmodule PramanaWeb.MCP.Tools.GetCommentaries do
  @moduledoc """
  What explains a given work — and what a commentary itself explains.

  `text_role` could already say a work *is* a commentary. This answers *what of*, which
  is the question people actually have: "commentary on the Lotus Sūtra", not "Chinese
  commentary".

  ## A commentary explains scripture and is not scripture

  Results are grouped by composition origin and text role and carry each work's dates,
  so a 7th-century Chinese gloss is never confused with a 1990s one — and nothing here
  returns quotable text. To read a commentary you fetch its passages by URN like any
  other text, where the citation guard and provenance apply unchanged. Pulling a
  commentary in because it explains a sūtra must never let it be quoted *as* the sūtra.

  ## Every relation states how it was established

  `method` and `confidence` travel with each result, because a catalogue assertion, a
  source manifest, a title match and an LLM inference are four different claims
  (`CLAUDE.md` invariant #5). `title_match` with `confidence: uncertain` means several
  works share the matched title — for instance every commentary on 般若波羅蜜多心經 matches
  all four surviving Chinese translations of it. That ambiguity is real and is reported
  rather than resolved.
  """

  use Anubis.Server.Component, type: :tool

  alias PramanaWeb.MCP.Reply
  alias Pramana.Provenance
  alias Pramana.Relations

  schema do
    field(:work_id, :string,
      required: true,
      description: "A work id, e.g. T0262 for the Lotus Sutra."
    )

    field(:direction, :string,
      description:
        "explains_this (default) = works that comment on this one; " <>
          "this_explains = what this work comments on, walked back to root scripture."
    )
  end

  @impl true
  def execute(%{work_id: work_id} = params, frame) do
    payload =
      case params[:direction] do
        "this_explains" -> upward(work_id)
        _ -> downward(work_id)
      end

    {:reply,
     Reply.json(
       "get_commentaries",
       params,
       Map.put(payload, :bake_id, Pramana.Bake.current_id())
     ), frame}
  end

  defp downward(work_id) do
    commentaries = Relations.commentaries_on(work_id)

    %{
      work_id: work_id,
      direction: "explains_this",
      total: length(commentaries),
      groups: group(commentaries),
      note:
        "These works EXPLAIN #{work_id}; none of them is #{work_id}. Fetch a passage by " <>
          "URN to quote one, and attribute it to the commentary, never to the text it " <>
          "comments on."
    }
  end

  defp upward(work_id) do
    chain = Relations.resolve_root(work_id)

    # A relation whose target is NOT in the corpus cannot be walked, but it is still an
    # assertion. Reporting only the walkable chain made the Huang Nianzu commentary —
    # which explicitly declares `comments_on: xia-lianju-conflation` — come back as "not
    # recorded as explaining anything, it may be a root text". That is false, and it is
    # the same absence-mistaken-for-silence error `Pramana.Coverage` exists to prevent.
    unresolved =
      work_id
      |> Relations.explains()
      |> Enum.filter(&(is_nil(&1.work_id) and not is_nil(&1.work_ref)))

    %{
      work_id: work_id,
      direction: "this_explains",
      # The PATH, not just the destination: a subcommentary on a commentary on a sūtra
      # returns all three, so the intermediate layers are visible rather than collapsed
      # into a claim that it explains the sūtra directly.
      chain: chain,
      depth: length(chain),
      unresolved_targets: unresolved,
      note: upward_note(work_id, chain, unresolved)
    }
  end

  defp upward_note(work_id, [], []),
    do: "#{work_id} is not recorded as explaining anything — it may be a root text."

  defp upward_note(_work_id, [], unresolved) do
    refs = Enum.map_join(unresolved, ", ", & &1.work_ref)

    "Declared to explain #{refs}, but that work is NOT in this corpus, so the chain " <>
      "cannot be walked. The relation is asserted, not unknown."
  end

  defp upward_note(_work_id, _chain, _unresolved),
    do: "Read left to right: each step explains the next."

  # Grouped for the same reason search results are: so the distinction cannot be
  # flattened by a caller reading a flat list.
  defp group(commentaries) do
    commentaries
    |> Enum.group_by(&{&1.composition_origin, &1.text_role})
    |> Enum.map(fn {{origin, role}, works} ->
      %{
        composition_origin: origin || Provenance.unattributed(),
        text_role: role || Provenance.unattributed(),
        label: Provenance.label(origin, role),
        count: length(works),
        works: Enum.map(works, &work/1)
      }
    end)
    |> Enum.sort_by(&{-&1.count, &1.composition_origin})
  end

  defp work(w) do
    %{
      work_id: w.work_id,
      title: w.title,
      attributed_author: w.attributed_author,
      period: period(w),
      relation: w.relation,
      scope: w.scope,
      target_urn: w.target_urn,
      # How this link was established, and how strongly. Never averaged away.
      method: w.method,
      confidence: w.confidence,
      evidence: w.evidence
    }
  end

  defp period(%{date_start: nil, date_end: nil}), do: nil
  defp period(%{date_start: s, date_end: nil}), do: "#{s}–"
  defp period(%{date_start: nil, date_end: e}), do: "–#{e}"
  defp period(%{date_start: s, date_end: e}), do: "#{s}–#{e}"
end
