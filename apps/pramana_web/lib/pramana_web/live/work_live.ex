defmodule PramanaWeb.WorkLive do
  @moduledoc """
  A work's structure, without its text.

  Nobody reads a canon linearly and no context window holds a whole work — T0220a is
  92,192 segments — so the outline is how a reader decides *what to open*, and it is
  frequently the first thing anyone sees about a text.

  That makes it a provenance surface, not a table of contents. Without origin and role
  here, a Kamakura-period sectarian commentary and a Kumārajīva translation look
  identical: same shape, same 品 headings, same juan count. `Corpus.outline/1` returns
  the axes for exactly this reason, and this page leads with them.

  Also shown: what a reader has to know before quoting from this work at all — whether
  its anchors are checkable against a printed page, and what its licence permits.
  """
  use PramanaWeb, :live_view

  alias Pramana.Apparatus
  alias Pramana.Corpus
  alias Pramana.Relations

  @impl true
  def mount(%{"work_id" => work_id}, _session, socket) do
    case Corpus.outline(work_id) do
      {:ok, outline} ->
        {:ok,
         socket
         |> assign(
           work_id: work_id,
           outline: outline,
           error: nil,
           page_title: outline.title || work_id
         )
         |> assign(relations: Relations.parallels_of(work_id))
         |> assign(apparatus: apparatus_summary(work_id))}

      {:error, reason} ->
        {:ok,
         assign(socket,
           work_id: work_id,
           outline: nil,
           relations: [],
           apparatus: nil,
           error: reason,
           page_title: work_id
         )}
    end
  end

  # How much of THIS work the witnesses disagree over. A work-level number, because "does
  # this text have a variant apparatus at all" is a question a reader asks before opening
  # it, and `Apparatus.at/1` only answers per line.
  defp apparatus_summary(work_id) do
    case Apparatus.count_for_work(work_id) do
      0 -> nil
      count -> %{segments: count}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div :if={@error} class="alert alert-error text-sm">
        <div>
          <p class="font-medium">No work with that id is in this bake.</p>
          <p class="font-mono text-xs">{@work_id}</p>
        </div>
      </div>

      <div :if={@outline} class="space-y-6">
        <section class="space-y-2">
          <div class="flex flex-wrap items-center gap-x-2 gap-y-1 text-xs">
            <span class="badge badge-sm badge-outline">{@outline.provenance_label}</span>
            <span class="font-medium">{@outline.work_id}</span>
            <span :if={@outline.division} class="text-base-content/60">
              · {@outline.division}
              <span :if={@outline.division_en}>({@outline.division_en})</span>
            </span>
            <span :if={@outline.attributed_author} class="text-base-content/60">
              · {@outline.attributed_author}
            </span>
          </div>
          <h1 class="text-xl font-semibold">{@outline.title || @outline.work_id}</h1>
          <p class="font-mono text-xs text-base-content/60">{@outline.urn_prefix}</p>
        </section>

        <section class="flex flex-wrap gap-4 rounded-lg bg-base-200/40 p-4 text-sm">
          <div>
            <div class="text-xs text-base-content/60">fascicles (juan)</div>
            <div class="font-medium">{@outline.juan_count || "—"}</div>
          </div>
          <div>
            <div class="text-xs text-base-content/60">sections</div>
            <div class="font-medium">{length(@outline.entries)}</div>
          </div>
          <div>
            <div class="text-xs text-base-content/60">witness</div>
            <div class="font-medium">{@outline.witness}</div>
          </div>
          <div :if={@apparatus}>
            <div class="text-xs text-base-content/60">lines with variants</div>
            <div class="font-medium">{@apparatus.segments}</div>
          </div>
        </section>

        <section :if={@relations != []} class="space-y-2">
          <h2 class="font-semibold">Other works transmitting this material</h2>
          <p class="text-xs text-base-content/60">
            Candidates for 異譯本 — <strong>not</strong>
            established alternate translations. The evidence is shared passages, which
            cannot tell a genuine re-translation from two collections that overlap.
          </p>
          <ul class="space-y-1 text-sm">
            <li :for={related <- @relations} class="flex flex-wrap items-baseline gap-2">
              <.link navigate={~p"/works/#{related[:work_id]}"} class="link link-hover font-medium">
                {related[:work_id]}
              </.link>
              <span class="text-base-content/70">{related[:title]}</span>
              <span :if={related[:attributed_author]} class="text-base-content/60">
                · {related[:attributed_author]}
              </span>
              <span class="badge badge-sm badge-ghost">{related[:confidence]}</span>
              <span :if={shared(related)} class="text-xs text-base-content/50">
                {shared(related)} shared passages
              </span>
            </li>
          </ul>
        </section>

        <section class="space-y-2">
          <h2 class="font-semibold">Contents</h2>
          <p :if={@outline.entries == []} class="text-sm text-base-content/70">
            This work records no internal divisions. That is a fact about the edition,
            not a gap in the bake — many short texts have none.
          </p>
          <ul class="space-y-1 text-sm">
            <li :for={entry <- @outline.entries} class="flex gap-2">
              <span class="w-20 shrink-0 font-mono text-xs text-base-content/50">
                {entry.type}{entry.n}
              </span>
              <.link
                :if={entry.urn}
                navigate={~p"/passage?#{[urn: entry.urn]}"}
                class="link link-hover"
              >
                {entry.title}
              </.link>
              <span :if={is_nil(entry.urn)} class="text-base-content/60">
                {entry.title}
                <span class="text-xs">— recorded with no anchor, so it cannot be opened</span>
              </span>
            </li>
          </ul>
        </section>
      </div>
    </Layouts.app>
    """
  end

  # The evidence rides along untouched so it can be argued with; the count of shared
  # passages is the part a reader weighs.
  defp shared(%{evidence: %{"full_parallels" => n}}), do: n
  defp shared(_), do: nil
end
