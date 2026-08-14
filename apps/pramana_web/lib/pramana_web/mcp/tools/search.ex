defmodule PramanaWeb.MCP.Tools.Search do
  @moduledoc """
  Lexical search over the corpus, with provenance filtering.

  Every hit is a full span — URN, offsets, sha256, provenance — so anything the caller
  goes on to quote can be verified with `verify_citation` (`CLAUDE.md` invariant #1).

  Results are **grouped by composition origin and text role**. That grouping is the
  point, not decoration: it is what stops a Japanese sectarian commentary being
  presented as an Indian sūtra. Phase 2 extends this once the Taishō 56–84 material is
  ingested, but the response shape is established here so no answer path is ever
  written against a flat list.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Pramana.Retrieval.Lexical

  schema do
    field(:query, :string,
      required: true,
      description:
        "Text to search for, in the source language (e.g. 如是我聞). " <>
          "Tried as an exact phrase first, then as overlapping character windows."
    )

    field(:limit, :integer, description: "Max results, default 20, capped at 200.")

    field(:mode, :string,
      description:
        "phrase = exact substring only; ngram = character windows; " <>
          "terms = jieba segmentation (unreliable for Buddhist vocabulary); " <>
          "auto (default) = phrase then ngram."
    )

    field(:origin, :string,
      description:
        "Restrict by where the text was COMPOSED: indic, chinese, japanese, tibetan, " <>
          "korean. Use this to exclude later commentary and keep only Indic sources."
    )

    field(:role, :string,
      description: "Restrict by role: root, translation, commentary, subcommentary, apocryphon."
    )

    field(:exclude_origin, :string, description: "Exclude a composition origin.")
    field(:work_id, :string, description: "Restrict to one work, e.g. T0262.")
    field(:juan, :integer, description: "Restrict to one fascicle.")
  end

  @impl true
  def execute(params, frame) do
    opts =
      [
        limit: params[:limit],
        mode: mode(params[:mode]),
        origin: params[:origin],
        role: params[:role],
        exclude_origin: params[:exclude_origin],
        work_id: params[:work_id],
        juan: params[:juan]
      ]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    case Lexical.search(params.query, opts) do
      {:ok, found} ->
        {:reply, Response.json(Response.tool(), payload(found)), frame}

      {:error, :empty_query} ->
        {:reply, Response.error(Response.tool(), "Query is empty."), frame}

      {:error, reason} ->
        {:reply, Response.error(Response.tool(), "Search failed: #{reason}"), frame}
    end
  end

  defp mode(nil), do: :auto

  defp mode(m) when m in ~w(auto phrase ngram terms), do: String.to_existing_atom(m)
  defp mode(_), do: :auto

  defp payload(found) do
    %{
      query: found.query,
      # Which corpus these hits came from. An answer that cannot name its corpus is
      # not reproducible — see docs/ARCHITECTURE.md, Stage 5.
      bake_id: Pramana.Bake.current_id(),
      # Which strategy actually produced these hits. A caller should weigh an :ngram
      # result less than a :phrase one — saying so is more useful than hiding it.
      mode: found.mode,
      search_terms: found.terms,
      total: found.total,
      groups: group_by_provenance(found.results)
    }
  end

  # Grouped, never flat. See the module doc.
  defp group_by_provenance(results) do
    results
    |> Enum.group_by(fn r ->
      p = r.span.provenance
      {p.composition_origin, p.text_role}
    end)
    |> Enum.map(fn {{origin, role}, group} ->
      %{
        composition_origin: origin || "uncatalogued",
        text_role: role || "uncatalogued",
        count: length(group),
        results: Enum.map(group, &hit/1)
      }
    end)
    |> Enum.sort_by(& &1.composition_origin)
  end

  defp hit(r) do
    %{
      urn: r.span.urn,
      text: r.span.content,
      sha256: r.span.sha256,
      matched: r.matched_terms,
      score: r.score,
      kind: r.span.kind,
      provenance: r.span.provenance,
      has_variants: is_map(r.span.meta) and Map.has_key?(r.span.meta, "apparatus")
    }
  end
end
