defmodule PramanaWeb.MCP.Tools.GetParallels do
  @moduledoc """
  Cross-tradition parallels for a passage or a work — from curated scholarship.

  "What is the Pāli parallel to this Āgama passage?" is answered from SuttaCentral's
  hand-built comparative data, not from embedding similarity. That distinction is the
  point: a scholar established these relations and typed them by strength, so an answer
  can say *how* two texts are related and *who* says so. `CLAUDE.md` invariant #5 —
  deterministic before probabilistic.

  ## Relation strength is never flattened

  | relation | meaning |
  |---|---|
  | `full` | a full parallel |
  | `sections` | a section corresponds |
  | `resembling` | resembles, without being a parallel |
  | `mentions` | mentions in passing |
  | `retells` | retells the story |

  Collapsing these into "related" would let a passing mention be presented as a parallel,
  which is the same class of error as presenting a commentary as scripture.

  ## A URN when we have the text, an id when we do not

  Where the parallel is a Taishō text in this corpus, `urn` resolves and the passage can
  be fetched and quoted. Where it is a Pāli sutta, `urn` is **null** and only the
  SuttaCentral id is given — that is a real limit, stated rather than hidden. The id is
  checkable at suttacentral.net.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Pramana.Parallels
  alias PramanaWeb.MCP.Reply

  schema do
    field(:work_id, :string,
      description: "A work id in this corpus, e.g. T0099 for the Saṃyukta Āgama."
    )

    field(:uid, :string,
      description:
        "A SuttaCentral text id instead, e.g. sa1, mn10, an1.1-5. Use this to ask " <>
          "about a text that is not in this corpus."
    )

    field(:relations, :string,
      description:
        "Comma-separated relation types to include: full, sections, resembling, " <>
          "mentions, retells. Defaults to all. Use `full` alone for parallels proper."
    )
  end

  @impl true
  def execute(params, frame) do
    case fetch(params) do
      {:error, message} ->
        {:reply, Response.error(Response.tool(), message), frame}

      {:ok, subject, parallels} ->
        {:reply, Reply.json("get_parallels", params, payload(subject, parallels)), frame}
    end
  end

  defp fetch(%{work_id: work_id} = params) when is_binary(work_id) do
    {:ok, %{work_id: work_id}, Parallels.for_work(work_id, relations: relations(params))}
  end

  defp fetch(%{uid: uid}) when is_binary(uid) do
    {:ok, %{uid: uid, anchor: anchor(uid)}, Parallels.for_uid(uid)}
  end

  defp fetch(_), do: {:error, "Give either work_id or uid."}

  defp anchor(uid) do
    case Parallels.anchor(uid) do
      nil -> nil
      a -> %{urn: a.urn, work_id: a.work_id, acronym: a.acronym, volpage: a.volpage}
    end
  end

  defp relations(params) do
    case params[:relations] do
      nil -> Parallels.relations()
      list -> list |> String.split(",") |> Enum.map(&String.trim/1)
    end
  end

  defp payload(subject, parallels) do
    grouped =
      parallels
      |> Enum.group_by(& &1.relation)
      |> Enum.map(fn {relation, items} ->
        %{
          relation: relation,
          count: length(items),
          # In this corpus and therefore quotable, versus known but not held.
          in_corpus: Enum.count(items, &(&1.urn != nil)),
          parallels: Enum.map(items, &parallel/1)
        }
      end)
      |> Enum.sort_by(&{relation_rank(&1.relation), -&1.count})

    Map.merge(subject, %{
      total: length(parallels),
      groups: grouped,
      source: "SuttaCentral sc-data — hand-curated comparative scholarship, not similarity",
      note: note(parallels)
    })
  end

  defp parallel(p) do
    %{
      uid: p.uid,
      # Null means the text is not in this corpus — a Pāli sutta, say. The relation is
      # still real scholarship; we simply cannot quote the other side.
      urn: p.urn,
      work_id: p.work_id,
      relation: p.relation,
      partial: p.partial
    }
  end

  # Strongest first, so a `full` parallel is never buried under passing mentions.
  defp relation_rank("full"), do: 0
  defp relation_rank("sections"), do: 1
  defp relation_rank("resembling"), do: 2
  defp relation_rank("retells"), do: 3
  defp relation_rank("mentions"), do: 4
  defp relation_rank(_), do: 5

  defp note([]), do: "No parallels are recorded for this text."

  defp note(parallels) do
    outside = Enum.count(parallels, &(&1.urn == nil))

    base =
      "Relation type states how strong the link is; `full` is a parallel, `mentions` is " <>
        "a passing reference. Do not present them as equivalent."

    if outside > 0 do
      base <>
        " #{outside} of these are NOT in this corpus (no `urn`) — most are Pāli. " <>
        "Their ids are checkable at suttacentral.net, but the text cannot be quoted from here."
    else
      base
    end
  end
end
