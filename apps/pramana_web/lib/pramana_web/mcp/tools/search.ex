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
  alias Pramana.Embed
  alias Pramana.Retrieval.Hybrid
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
        "hybrid (default) = lexical + semantic fused by rank, the best option; " <>
          "phrase = exact substring only; ngram = character windows; " <>
          "semantic = meaning only; " <>
          "terms = jieba segmentation (unreliable for Buddhist vocabulary)."
    )

    field(:origin, :string,
      description:
        "Restrict by where the text was COMPOSED: indic, chinese, japanese, tibetan, " <>
          "korean. Use this to exclude later commentary and keep only Indic sources."
    )

    field(:role, :string,
      description: "Restrict by role: root, translation, commentary, subcommentary, apocryphon."
    )

    field(:division, :string,
      description:
        "Restrict to one Taishō division (部): 阿含部 (Āgama), 般若部 (Prajñāpāramitā), " <>
          "經疏部 (Chinese sūtra exegesis), 疑似部 (apocrypha), and so on."
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
        division: params[:division],
        exclude_origin: params[:exclude_origin],
        work_id: params[:work_id],
        juan: params[:juan]
      ]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    case dispatch(params, opts) do
      {:ok, found} ->
        {:reply, Response.json(Response.tool(), payload(found)), frame}

      {:error, :empty_query} ->
        {:reply, Response.error(Response.tool(), "Query is empty."), frame}

      {:error, reason} ->
        {:reply, Response.error(Response.tool(), "Search failed: #{reason}"), frame}
    end
  end

  # Hybrid by default: it is the only mode that finds BOTH the characters you typed and
  # passages that mean the same thing in different words. It degrades to lexical, and
  # says so, when no embedding serving is running.
  defp dispatch(params, opts) do
    case mode(params[:mode]) do
      :hybrid ->
        Hybrid.search(params.query, Keyword.put(opts, :serving, Embed.Serving.name()))

      :semantic ->
        Hybrid.search(
          params.query,
          opts |> Keyword.put(:serving, Embed.Serving.name()) |> Keyword.put(:semantic_only, true)
        )

      lexical_mode ->
        Lexical.search(params.query, Keyword.put(opts, :mode, lexical_mode))
    end
  end

  defp mode(nil), do: :hybrid

  defp mode(m) when m in ~w(hybrid semantic auto phrase ngram terms),
    do: String.to_existing_atom(m)

  defp mode(_), do: :hybrid

  defp payload(found) do
    %{
      query: found.query,
      # Which corpus these hits came from. An answer that cannot name its corpus is
      # not reproducible — see docs/ARCHITECTURE.md, Stage 5.
      bake_id: Pramana.Bake.current_id(),
      # Which strategy actually produced these hits. An :ngram result is weaker
      # evidence than a :phrase one, and a lexical-only hybrid run is weaker than a
      # fused one — saying so is more useful than hiding it.
      mode: Map.get(found, :mode, "hybrid"),
      retrievers: Map.get(found, :retrievers),
      search_terms: Map.get(found, :terms),
      embedding_coverage: Map.get(found, :coverage),
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

  # Lexical and hybrid results have different score shapes; both carry a span, which is
  # the part that must always be present because it is what the guard verifies.
  defp hit(r) do
    %{
      urn: r.span.urn,
      text: r.span.content,
      sha256: r.span.sha256,
      matched: Map.get(r, :matched_terms),
      score: Map.get(r, :score) || Map.get(r, :rrf_score),
      kind: r.span.kind,
      provenance: r.span.provenance,
      has_variants: is_map(r.span.meta) and Map.has_key?(r.span.meta, "apparatus")
    }
  end
end
