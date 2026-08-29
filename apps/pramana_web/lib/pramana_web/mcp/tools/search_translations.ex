defmodule PramanaWeb.MCP.Tools.SearchTranslations do
  @moduledoc """
  Finds a **rendering** by its own words, and returns the source line it renders.

  `search` reads the source text. Ask it an English question and it answers with source-
  language passages that happen to share character n-grams with the English — confident
  results with nothing to do with the question. This is the tool for an English phrase.

  ## The answer is an anchor, never the rendering

  Every hit leads with `anchor_urn`, the source line, because that is the thing a citation
  may point at. The rendering itself carries `citable_as_source: false` and its own
  `rendering_urn` — a fragment over the anchor, never a top-level URN, which is what makes
  `CLAUDE.md` invariant #8 structural rather than a rule to remember. A fluent English
  sentence is exactly the kind of result a model will quote as though it were the text.

  ## `match` says how hard the search had to work

  The unit is one rendered line, usually a single sentence, so requiring every query term
  in one row is stricter than it looks: `Baka Brahmā` finds nothing that way while `Baka`
  and `Brahmā` each return the same discourse, which names them on different lines. When
  all terms find nothing the search falls back to any term and reports `match: "any_term"`.
  A caller told that knows the words were not found together.

  Measured on 40 cases drawn from the corpus without consulting the retriever: **70.0%,
  mean rank 1.68**. Every miss is a formulaic phrase that matched a different line better.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Pramana.Translations
  alias PramanaWeb.MCP.Reply

  schema do
    field(:query, :string,
      required: true,
      description: "A phrase in the translation's language, e.g. \"the four noble truths\"."
    )

    field(:limit, :integer, description: "Maximum renderings to return (default 10).")

    field(:translator, :string, description: "Restrict to one translator id, e.g. sujato.")

    field(:redistributable_only, :boolean,
      description: "Only renderings we may republish. Default false."
    )
  end

  @impl true
  def execute(%{query: query} = params, frame) do
    opts =
      [limit: params[:limit] || 10]
      |> maybe_put(:translator, params[:translator])
      |> maybe_put(:redistributable_only, params[:redistributable_only])

    case Translations.search(query, opts) do
      {:ok, found} ->
        payload = %{
          query: query,
          match: to_string(found.match),
          results: Enum.map(found.results, &present/1),
          note: note(found.match),
          bake_id: Pramana.Bake.current_id()
        }

        {:reply, Reply.json("search_translations", params, payload), frame}

      {:error, _} ->
        {:reply,
         Response.error(
           Response.tool(),
           "A query must be a string of words to look for in the renderings."
         ), frame}
    end
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp note(:all_terms),
    do:
      "Every result contains all your terms. These are RENDERINGS: cite `anchor_urn`, " <>
        "never the translated text."

  defp note(:any_term),
    do:
      "No rendering contains all your terms, so these match SOME of them — the unit is " <>
        "one line and your words may sit on different lines of the same discourse. " <>
        "These are RENDERINGS: cite `anchor_urn`, never the translated text."

  defp present(r) do
    %{
      anchor_urn: r.anchor_urn,
      rendering_urn: r.rendering_urn,
      work_id: r.work_id,
      text: r.text,
      sha256: r.text_sha256,
      translator: r.translator,
      lang: r.lang,
      provenance: r.provenance
    }
  end
end
