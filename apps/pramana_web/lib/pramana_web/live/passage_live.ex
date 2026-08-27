defmodule PramanaWeb.PassageLive do
  @moduledoc """
  One passage, in its printed context, with everything that makes it checkable.

  A Taishō line is a *typographic* unit — it breaks mid-sentence, at 17 characters,
  wherever the block-cutter ran out of column — so a single segment is frequently
  unreadable alone. `Pramana.Corpus.context/2` returns the neighbours, and each of them
  is a full span with its own URN: the window is a reading convenience and never a new
  citable unit.

  What the page insists on showing, because each is a claim a reader may need to check:

  - the **URN and sha256** of the focused line, which is what a quotation is verified
    against;
  - the **variant apparatus**, when the witnesses disagree — this is a critical edition
    and hiding the disagreement would make it a reading text;
  - **rare characters** with their mappings, since those are the content a reader cannot
    reconstruct from anything else;
  - **provenance**, in words, above the text rather than below it.
  """
  use PramanaWeb, :live_view

  import PramanaWeb.ReaderComponents

  alias Pramana.Corpus

  @window 6

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Passage", window: @window)}
  end

  @impl true
  def handle_params(%{"urn" => urn}, _uri, socket) do
    case Corpus.context(urn, before: @window, after: @window) do
      {:ok, context} ->
        {:noreply,
         socket
         |> assign(urn: urn, context: context, error: nil)
         |> assign(outline: outline_for(context.focus))
         |> assign(page_title: page_title(context.focus))}

      {:error, reason} ->
        {:noreply, assign(socket, urn: urn, context: nil, outline: nil, error: reason)}
    end
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, assign(socket, urn: nil, context: nil, outline: nil, error: :bad_urn)}
  end

  defp page_title(%{provenance: %{work_id: work_id}}), do: work_id
  defp page_title(_), do: "Passage"

  # The outline is fetched here rather than rendered from the passage, because a reader
  # who has landed mid-work from a search result needs to know where in the work they
  # are — and nobody reads a canon linearly.
  defp outline_for(%{provenance: %{work_id: work_id}}) when is_binary(work_id) do
    case Corpus.outline(work_id) do
      {:ok, outline} -> outline
      {:error, _} -> nil
    end
  end

  defp outline_for(_), do: nil

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div :if={@error} class="alert alert-error text-sm">
        <div>
          <p class="font-medium">{error_message(@error)}</p>
          <p class="font-mono text-xs">{@urn}</p>
        </div>
      </div>

      <div :if={@context} class="space-y-6">
        <section class="space-y-2">
          <.provenance_line provenance={@context.focus.provenance} class="text-sm" />
          <h1 class="text-xl font-semibold">
            {@context.focus.provenance[:title] || @context.focus.provenance[:work_id]}
          </h1>
        </section>

        <section class="rounded-lg border border-base-300 p-4">
          <div class="space-y-1">
            <.passage_line :for={span <- @context.before} span={span} />
            <.passage_line span={@context.focus} focus />
            <.passage_line :for={span <- @context.after} span={span} />
          </div>
        </section>

        <section class="space-y-2 rounded-lg bg-base-200/40 p-4 text-sm">
          <h2 class="font-semibold">Citation</h2>
          <dl class="grid grid-cols-[max-content_1fr] gap-x-4 gap-y-1 font-mono text-xs break-all">
            <dt class="text-base-content/60">line</dt>
            <dd>{@context.focus.urn}</dd>
            <dt class="text-base-content/60">window</dt>
            <dd>{@context.urn}</dd>
            <dt class="text-base-content/60">sha256</dt>
            <dd>{@context.focus.sha256}</dd>
            <dt class="text-base-content/60">bytes</dt>
            <dd>{@context.focus.byte_start}–{@context.focus.byte_end}</dd>
          </dl>
          <p class="text-xs text-base-content/60">
            The window URN covers {@context.segment_count} printed lines and resolves as a unit;
            the line URN is what a quotation of this line is verified against.
          </p>
        </section>

        <section :if={@outline && @outline.entries != []} class="space-y-2">
          <h2 class="font-semibold">{@outline.entries |> length()} sections in this work</h2>
          <ul class="max-h-64 space-y-1 overflow-y-auto text-sm">
            <li :for={entry <- @outline.entries} class="flex gap-2">
              <span class="w-16 shrink-0 font-mono text-xs text-base-content/50">
                {entry.type}{entry.n}
              </span>
              <.link navigate={~p"/passage?#{[urn: entry.urn]}"} class="link link-hover">
                {entry.title}
              </.link>
            </li>
          </ul>
        </section>
      </div>
    </Layouts.app>
    """
  end

  defp error_message(:bad_urn), do: "That is not a URN this corpus can parse."

  defp error_message(:not_found),
    do: "No passage with that URN is in this bake. It may belong to a collection not loaded."

  defp error_message(other), do: "Could not resolve the passage: #{inspect(other)}"
end
