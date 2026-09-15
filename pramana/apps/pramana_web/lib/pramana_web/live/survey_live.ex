defmodule PramanaWeb.SurveyLive do
  @moduledoc """
  How often the canon says something, and where — counted, not sampled.

  Top-k retrieval structurally cannot answer this. It returns the best twenty hits and
  says nothing about whether there are twenty-one or twenty thousand, or whether they
  cluster in a single commentary or spread across the tradition. A reader given twenty
  results will generalise from them, and so will a model.

  This page exists because **a search page invites exactly that mistake**. Search was the
  first thing built here and for two phases it was the only thing a human could do, which
  means every claim a person formed from this corpus was formed from a ranked sample. The
  MCP surface has had `survey_corpus` since Phase 3 with a note telling models to run it
  *before* claiming anything about how often the canon says something. A person had no
  equivalent.

  What it shows, and why each is a different question:

  - **occurrences and distinct works** — 34,775 segments in 3,700 works is a commonplace;
    34,775 in one work is that work's idiom.
  - **by composition origin and text role** — whether a phrase is Indic scripture or
    Chinese exegesis. The same string in both is a transmission fact.
  - **by division** — the Taishō's own 部 classification, which is the tradition's own
    answer to "what kind of text is this".
  - **the works that use it most** — where to go and read.

  It counts in SQL over the bigram index: 1.2 s over 10.7M segments.
  """
  use PramanaWeb, :live_view

  import PramanaWeb.ReaderComponents

  alias Pramana.Provenance
  alias Pramana.Retrieval.Survey

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Survey", result: nil, error: nil, query: "")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    query = String.trim(params["q"] || "")

    socket = assign(socket, query: query)

    if query == "" do
      {:noreply, assign(socket, result: nil, error: nil)}
    else
      {:noreply, run(socket, query)}
    end
  end

  @impl true
  def handle_event("survey", %{"q" => q}, socket) do
    {:noreply, push_patch(socket, to: ~p"/survey?#{[q: q]}")}
  end

  defp run(socket, query) do
    case Survey.survey(query) do
      {:ok, result} -> assign(socket, result: result, error: nil)
      {:error, reason} -> assign(socket, result: nil, error: reason)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section class="space-y-1">
        <h1 class="text-xl font-semibold">Survey the corpus</h1>
        <p class="text-sm text-base-content/70">
          Every occurrence, counted — not the best twenty. Ask this before claiming
          anything about how often or where the canon says something.
        </p>
      </section>

      <form phx-submit="survey" class="flex gap-2">
        <input
          type="text"
          name="q"
          value={@query}
          placeholder="一切眾生 · 如是我聞"
          class="input input-bordered flex-1 text-lg"
          autocomplete="off"
        />
        <button type="submit" class="btn btn-primary" phx-disable-with="Counting…">Count</button>
      </form>

      <div :if={@error} class="alert alert-error text-sm">
        {error_message(@error)}
      </div>

      <div :if={@result} class="space-y-6">
        <.coverage_note caveat={@result.coverage_caveat} />

        <section class="flex flex-wrap gap-6 rounded-lg bg-base-200/40 p-4">
          <div>
            <div class="text-xs text-base-content/60">printed lines containing it</div>
            <div class="text-2xl font-semibold">{@result.total_segments}</div>
          </div>
          <div>
            <div class="text-xs text-base-content/60">distinct works</div>
            <div class="text-2xl font-semibold">{@result.distinct_works}</div>
          </div>
          <div class="self-end text-xs text-base-content/60">
            {spread_note(@result)}
          </div>
        </section>

        <div class="grid gap-6 sm:grid-cols-2">
          <.breakdown
            title="By composition origin"
            note="Where the text was composed — not what language it is written in."
            rows={@result.by_origin}
            total={@result.total_segments}
            label_fun={&Provenance.origin_label/1}
          />
          <.breakdown
            title="By text role"
            note="What the text IS: scripture, treatise, commentary, apocryphon."
            rows={@result.by_role}
            total={@result.total_segments}
            label_fun={&Provenance.role_label/1}
          />
        </div>

        <section :if={@result.by_division != []} class="space-y-2">
          <h2 class="font-semibold">By Taishō division (部)</h2>
          <p class="text-xs text-base-content/60">
            The tradition's own classification of what kind of text this is.
          </p>
          <ul class="space-y-1 text-sm">
            <li :for={row <- @result.by_division} class="flex items-baseline gap-2">
              <span class="w-16 text-right font-mono text-xs">{row.segments}</span>
              <span>{row.division}</span>
              <span :if={row.division_en} class="text-base-content/60">({row.division_en})</span>
            </li>
          </ul>
        </section>

        <section :if={@result.top_works != []} class="space-y-2">
          <h2 class="font-semibold">Where it is used most</h2>
          <ul class="space-y-1 text-sm">
            <li :for={work <- @result.top_works} class="flex flex-wrap items-baseline gap-2">
              <span class="w-16 text-right font-mono text-xs">{work.segments}</span>
              <.link navigate={~p"/works/#{work.work_id}"} class="link link-hover font-medium">
                {work.work_id}
              </.link>
              <span class="text-base-content/70">{work.title}</span>
              <span class="badge badge-sm badge-outline">
                {Provenance.label(work.composition_origin, work.text_role)}
              </span>
            </li>
          </ul>
        </section>

        <p class="font-mono text-xs text-base-content/50">
          bake {String.slice(@result.bake_id || "", 0, 12)}
        </p>
      </div>
    </Layouts.app>
    """
  end

  attr :title, :string, required: true
  attr :note, :string, required: true
  attr :rows, :list, required: true
  attr :total, :integer, required: true
  attr :label_fun, :any, required: true

  defp breakdown(assigns) do
    ~H"""
    <section class="space-y-2">
      <h2 class="font-semibold">{@title}</h2>
      <p class="text-xs text-base-content/60">{@note}</p>
      <ul class="space-y-1 text-sm">
        <li :for={row <- @rows} class="flex items-baseline gap-2">
          <span class="w-16 text-right font-mono text-xs">{row.segments}</span>
          <span class="w-12 text-right font-mono text-xs text-base-content/50">
            {percent(row.segments, @total)}
          </span>
          <span>{@label_fun.(row.key)}</span>
        </li>
      </ul>
    </section>
    """
  end

  defp percent(_n, 0), do: "—"
  defp percent(n, total), do: "#{Float.round(100 * n / total, 1)}%"

  # The number that decides whether a count means anything. Concentration is the whole
  # reason to survey rather than sample: a phrase in one work is that work's idiom, and a
  # phrase across three thousand is the tradition's.
  defp spread_note(%{total_segments: 0}), do: "Nothing in the loaded corpus uses this."

  defp spread_note(%{total_segments: total, distinct_works: works, top_works: [top | _]})
       when works > 0 do
    share = round(100 * top.segments / total)

    "#{Float.round(total / works, 1)} lines per work on average; " <>
      "the heaviest single work holds #{share}% of all occurrences."
  end

  defp spread_note(_), do: nil

  defp error_message(:empty_query), do: "Type something to count."
  defp error_message(other), do: "Survey failed: #{inspect(other)}"
end
