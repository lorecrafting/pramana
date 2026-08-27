defmodule PramanaWeb.SearchLive do
  @moduledoc """
  Search across the canons, with the provenance of every hit attached to it.

  ## What this view is, and is not

  It is a **renderer** over `Pramana.Retrieval`. It computes nothing about the
  corpus: not a count, not a filter, not a label. If a screen here needs domain logic
  that does not exist yet, the API is missing something and the fix belongs there —
  otherwise the reader and the MCP surface start answering the same question differently,
  which for a corpus is worse than either being wrong alone.

  ## Why results are grouped and not ranked flat

  A flat list lets a Kamakura-period Japanese commentary sit directly beneath an Indian
  sūtra with nothing between them, and rank order gives a reader no reason to look
  closer. `Pramana.Provenance.group/1` buckets by composition origin and text role and
  names each bucket in plain language, so mis-attribution requires ignoring a heading
  rather than merely missing a field. That is `CLAUDE.md` invariant #4 — enforced by the
  shape of the page, not by hoping.

  ## Index coverage is computed once per session, not once per search

  `Semantic.coverage/1` counts, over the whole corpus, how much of it carries a vector.
  It is honest and it is **expensive**: 2.7 s at 850k chunks, against 49–96 ms for the
  lexical retrieval it sits beside. `Hybrid` recomputes it on every search because an MCP
  caller makes one request and needs the number attached to it.

  A person makes twenty searches in a session and the answer is the same every time —
  coverage is a property of the corpus and the index, never of the query. So it is
  computed at `mount/3` and shown as what it is, a **corpus-wide** figure. That is also
  clearer than what it replaced: the per-search number silently reflected the origin and
  role filters, and was labelled as though it described the whole corpus.

  It refreshes on every mount, which includes a reconnect and any navigation back to this
  page — so an import that lands mid-session is picked up the next time the page is
  entered, and never goes stale in a way a reader could act on.

  ## Why the caveats are always on screen

  An empty result means either *the canon does not say this* or *that part of the canon
  is not loaded*, and those are indistinguishable from the results alone. Both are
  rendered above the results, every time: what is not ingested (`Pramana.Coverage`) and
  what is ingested but not vector-indexed.
  """
  use PramanaWeb, :live_view

  import PramanaWeb.ReaderComponents

  alias Pramana.Cbeta.Collections
  alias Pramana.Corpus
  alias Pramana.Coverage
  alias Pramana.Provenance
  alias Pramana.Retrieval
  alias Pramana.Retrieval.Semantic

  # Every mode the retriever actually implements, with the sentence a reader needs to
  # weigh the evidence. `phrase` is strong evidence; `ngram` is a character-window
  # fallback and much weaker, and a reader who is not told cannot tell them apart.
  @modes [
    {"hybrid", "Hybrid — characters and meaning, fused by rank"},
    {"phrase", "Phrase — the exact characters, nothing else"},
    {"ngram", "N-gram — character windows; a weak fallback"},
    {"semantic", "Semantic — meaning only, no character match required"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Search",
       modes: @modes,
       origins: Provenance.origins(),
       roles: Provenance.roles(),
       witnesses: witness_options(),
       caveat: Coverage.caveat(),
       # Once, here — see the moduledoc. Not per search.
       index_coverage: Semantic.coverage(),
       result: nil,
       searching?: false,
       error: nil
     )
     |> assign(form: to_form(default_params()))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    form_params = Map.merge(default_params(), Map.take(params, Map.keys(default_params())))

    socket = assign(socket, form: to_form(form_params))

    case String.trim(form_params["q"] || "") do
      "" -> {:noreply, assign(socket, result: nil, error: nil, searching?: false)}
      query -> {:noreply, run_search(socket, query, form_params)}
    end
  end

  @impl true
  def handle_event("search", %{"q" => q} = params, socket) do
    # The query lives in the URL so a search is a link someone can send to a colleague
    # alongside the passage it found.
    {:noreply, push_patch(socket, to: ~p"/?#{search_params(params, q)}")}
  end

  def handle_event("clear", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/")}
  end

  defp default_params do
    %{
      "q" => "",
      "mode" => "hybrid",
      "origin" => "",
      "role" => "",
      "witness" => "",
      "limit" => "20"
    }
  end

  # The collections actually held, read from the corpus rather than listed here — a menu
  # that offers a canon the bake does not contain is a promise of an empty result set.
  # Labelled with CBETA's own names, so a reader chooses 大正新脩大藏經 rather than "T".
  defp witness_options do
    for %{id: id, name: name} <- Collections.all(),
        id in Corpus.witnesses_held("cbeta"),
        do: {id, "#{id} · #{name}"}
  end

  defp search_params(params, q) do
    default_params()
    |> Map.merge(Map.take(params, Map.keys(default_params())))
    |> Map.put("q", q)
    |> Enum.reject(fn {_k, v} -> v in ["", nil] end)
  end

  defp run_search(socket, query, params) do
    # `Retrieval.mode/1`, never `String.to_existing_atom/1`. The atom table is global
    # mutable state and `:phrase` only enters it when `Retrieval.Lexical` loads, so
    # converting here raised on the first phrase search in a fresh VM and worked on every
    # one after — the exact failure `docs/STATUS.md` records for the MCP tool, walked into
    # again from a second surface. That is why the mapping lives in the domain.
    opts =
      [
        limit: parse_limit(params["limit"]),
        mode: Retrieval.mode(params["mode"]),
        # The banner carries the session's copy; recomputing it here would add ~2.7 s to
        # every search for an answer that cannot have changed.
        coverage: false
      ]
      |> put_unless_blank(:origin, params["origin"])
      |> put_unless_blank(:role, params["role"])
      |> put_unless_blank(:witness_id, params["witness"])

    case Retrieval.search(query, opts) do
      {:ok, found} ->
        assign(socket,
          result: normalize_result(found),
          groups: Provenance.group(found.results),
          error: nil,
          searching?: false
        )

      {:error, reason} ->
        assign(socket, result: nil, groups: [], error: reason, searching?: false)
    end
  end

  # A lexical result and a fused one are different shapes: `Lexical` reports the mode it
  # ended up using and no coverage, `Hybrid` reports which retrievers ran. The view fills
  # in what is absent with `nil` and renders the difference rather than flattening it —
  # a phrase search genuinely did not consult the vector index, and saying so is the
  # point of reporting retrievers at all.
  defp normalize_result(found) do
    %{
      results: found.results,
      total: found.total,
      mode: Map.get(found, :mode),
      retrievers: Map.get(found, :retrievers) || ["lexical"],
      semantic_confidence: Map.get(found, :semantic_confidence),
      expanded_terms: Map.get(found, :expanded_terms) || Map.get(found, :terms),
      bake_id: Map.get(found, :bake_id) || Pramana.Bake.current_id()
    }
  end

  # A limit the caller cannot read back is a limit that silently truncated them; the
  # retriever clamps and reports, and this only has to refuse nonsense.
  defp parse_limit(value) do
    case Integer.parse(value || "20") do
      {n, _} when n > 0 -> min(n, 100)
      _ -> 20
    end
  end

  defp put_unless_blank(opts, _key, value) when value in ["", nil], do: opts
  defp put_unless_blank(opts, key, value), do: Keyword.put(opts, key, value)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.form for={@form} phx-submit="search" class="space-y-3">
        <div class="flex gap-2">
          <input
            type="text"
            name="q"
            value={@form.params["q"]}
            placeholder="如是我聞 · dukkha · what did the Buddha realise under the bodhi tree"
            class="input input-bordered flex-1 text-lg"
            autocomplete="off"
            autofocus
          />
          <button type="submit" class="btn btn-primary" phx-disable-with="Searching…">
            Search
          </button>
        </div>

        <div class="flex flex-wrap items-center gap-2 text-sm">
          <select name="mode" class="select select-bordered select-sm max-w-xs">
            <option
              :for={{value, label} <- @modes}
              value={value}
              selected={@form.params["mode"] == value}
            >
              {label}
            </option>
          </select>

          <select name="origin" class="select select-bordered select-sm">
            <option value="">any origin</option>
            <option
              :for={origin <- @origins}
              value={origin}
              selected={@form.params["origin"] == origin}
            >
              {origin}
            </option>
          </select>

          <select name="witness" class="select select-bordered select-sm max-w-xs">
            <option value="">any collection</option>
            <option
              :for={{id, label} <- @witnesses}
              value={id}
              selected={@form.params["witness"] == id}
            >
              {label}
            </option>
          </select>

          <select name="role" class="select select-bordered select-sm">
            <option value="">any role</option>
            <option :for={role <- @roles} value={role} selected={@form.params["role"] == role}>
              {role}
            </option>
          </select>

          <select name="limit" class="select select-bordered select-sm">
            <option
              :for={n <- ["10", "20", "50", "100"]}
              value={n}
              selected={@form.params["limit"] == n}
            >
              {n} results
            </option>
          </select>

          <button :if={@result} type="button" phx-click="clear" class="btn btn-ghost btn-sm">
            clear
          </button>
        </div>
      </.form>

      <.coverage_note
        caveat={@caveat}
        coverage={@index_coverage}
        retrievers={@result && @result.retrievers}
        confidence={@result && @result.semantic_confidence}
      />

      <div :if={@error} class="alert alert-error text-sm">
        {error_message(@error)}
      </div>

      <div :if={@result} class="space-y-4">
        <div class="flex flex-wrap items-baseline gap-2 text-sm text-base-content/70">
          <span class="font-medium text-base-content">{@result.total} passage(s)</span>
          <span>in {length(@groups)} provenance group(s)</span>
          <span :if={@result.expanded_terms not in [nil, [], %{}]} class="text-base-content/60">
            · expanded to {inspect(@result.expanded_terms)}
          </span>
          <span class="ml-auto font-mono text-xs">
            bake {String.slice(@result.bake_id || "", 0, 12)}
          </span>
        </div>

        <p :if={@result.total == 0} class="text-sm text-base-content/70">
          Nothing in the loaded corpus matches. That is not the same as the canon being
          silent — read the note above for what is not loaded, and try
          <span class="font-mono">phrase</span>
          mode or a different orthographic form.
        </p>

        <section :for={group <- @groups} class="space-y-2">
          <h2 class="flex items-baseline gap-2 border-b border-base-300 pb-1">
            <span class="font-semibold">{group.label}</span>
            <span class="text-sm text-base-content/60">{group.count}</span>
          </h2>

          <article :for={hit <- group.results} class="space-y-1 rounded-lg bg-base-200/40 p-3">
            <p class="text-lg leading-relaxed break-words">{hit.span.content}</p>
            <.provenance_line provenance={hit.span.provenance} />
            <.citation span={hit.span} />
          </article>
        </section>
      </div>

      <div :if={is_nil(@result)} class="prose prose-sm max-w-none text-base-content/70">
        <p>
          Every passage returned here carries its URN, its byte offsets and its SHA-256, so
          a quotation can be checked against the printed edition rather than trusted.
        </p>
      </div>
    </Layouts.app>
    """
  end

  defp error_message(:empty_query), do: "Type something to search for."
  defp error_message(:bad_query), do: "That query could not be read as text."
  defp error_message(other), do: "Search failed: #{inspect(other)}"
end
