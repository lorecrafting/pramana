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
  alias PramanaWeb.MCP.Reply
  alias Pramana.Provenance
  alias Pramana.Reader
  alias Pramana.Retrieval
  alias Pramana.Retrieval.Semantic

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

    field(:normalize_variants, :boolean,
      description:
        "Expand the query across variant Han forms (異體字). CBETA writes 眾生 and 說法; " <>
          "searching the simplified 众生 or the Japanese 説法 otherwise returns NOTHING. " <>
          "Turn this on if a query in one orthographic tradition finds nothing. The " <>
          "stored text is never normalised — this expands the QUERY only, and the " <>
          "response reports what was expanded."
    )

    field(:exclude_origin, :string, description: "Exclude a composition origin.")
    field(:work_id, :string, description: "Restrict to one work, e.g. T0262.")
    field(:juan, :integer, description: "Restrict to one fascicle.")
  end

  # The cap this tool's schema already advertises ("capped at 200"), now ENFORCED here
  # rather than by the retriever clamping in silence. The domain refuses an over-limit
  # outright, because a caller in code asking for more than exists should be told; a
  # model filling in a tool parameter should not get an error for a number this tool
  # documents as capped. The boundary is where user input becomes a request.
  defp capped_limit(nil), do: nil
  defp capped_limit(limit) when is_integer(limit), do: min(limit, Semantic.max_limit())
  defp capped_limit(_limit), do: nil

  @impl true
  def execute(params, frame) do
    opts =
      [
        limit: capped_limit(params[:limit]),
        mode: mode(params[:mode]),
        origin: params[:origin],
        role: params[:role],
        division: params[:division],
        exclude_origin: params[:exclude_origin],
        normalize_variants: params[:normalize_variants],
        work_id: params[:work_id],
        juan: params[:juan]
      ]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    case dispatch(params, opts) do
      {:ok, found} ->
        {:reply, Reply.json("search", params, payload(found)), frame}

      {:error, :empty_query} ->
        {:reply, Response.error(Response.tool(), "Query is empty."), frame}

      {:error, reason} ->
        {:reply, Response.error(Response.tool(), "Search failed: #{reason}"), frame}
    end
  end

  # Hybrid by default: it is the only mode that finds BOTH the characters you typed and
  # passages that mean the same thing in different words. It degrades to lexical, and
  # says so, when no embedding serving is running.
  #
  # `Pramana.Retrieval.search/2` does the routing, because the Phase 8 reader needs the
  # identical routing and two surfaces resolving `"semantic"` differently would be one
  # corpus answering a question two ways.
  defp dispatch(params, opts) do
    Retrieval.search(params.query, opts)
  end

  defp mode(m), do: Retrieval.mode(m)

  defp payload(found) do
    %{
      query: found.query,
      # Which corpus these hits came from. An answer that cannot name its corpus is
      # not reproducible — see docs/ARCHITECTURE.md, Stage 5.
      # Which strategy actually produced these hits. An :ngram result is weaker
      # evidence than a :phrase one, and a lexical-only hybrid run is weaker than a
      # fused one — saying so is more useful than hiding it.
      mode: Map.get(found, :mode, "hybrid"),
      retrievers: Map.get(found, :retrievers),
      search_terms: Map.get(found, :terms),
      # Which characters were expanded, so a hit on a different orthographic form is
      # visible rather than surprising.
      variants: Map.get(found, :variants),
      embedding_coverage: Map.get(found, :coverage),
      # How close the best semantic match was, and what that means. Reported rather than
      # acted on: a hard cut-off would cost ~45 retrieval cases to gain 1 absence case.
      # `no_close_match` is as near as this corpus comes to saying "I do not have this".
      semantic_confidence: Map.get(found, :semantic_confidence),
      total: found.total,
      groups: group_by_provenance(found.results)
    }
  end

  # Grouped, never flat — `Pramana.Provenance.group/1`, which is where the rule lives so
  # that the reader and this tool cannot describe the same bucket differently. This adds
  # only the wire shape.
  defp group_by_provenance(results) do
    results
    |> Provenance.group()
    |> Enum.map(fn bucket -> %{bucket | results: Enum.map(bucket.results, &hit/1)} end)
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
      reader: Reader.reference(r.span.urn, r.span.provenance),
      has_variants: is_map(r.span.meta) and Map.has_key?(r.span.meta, "apparatus")
    }
  end
end
