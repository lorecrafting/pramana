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
  alias Pramana.Authority
  alias Pramana.Corpus
  alias Pramana.Reader
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
         |> assign(person: person(outline))
         |> assign(apparatus: apparatus_summary(work_id))
         |> assign(edition_link: edition_link(outline))}

      {:error, reason} ->
        {:ok,
         assign(socket,
           work_id: work_id,
           outline: nil,
           relations: [],
           apparatus: nil,
           edition_link: nil,
           error: reason,
           page_title: work_id
         )}
    end
  end

  # How much of THIS work the witnesses disagree over. A work-level number, because "does
  # this text have a variant apparatus at all" is a question a reader asks before opening
  # it, and `Apparatus.at/1` only answers per line.
  # A work page is where someone decides whether to trust a text, so it is where the
  # publisher's own copy is most worth one click away. `urn_prefix` is the work URN with no
  # locator, which is exactly the granularity these links open at.
  defp edition_link(outline), do: Reader.reference(outline.urn_prefix, %{source: outline.source})

  # WHO THE BYLINE DENOTES, where it could be resolved. `nil` on roughly 40% of works, and
  # that is a refusal rather than a gap — see `Pramana.Authority`. A section with nothing in
  # it is not rendered, which is this reader's rule everywhere: an empty "Attributed to"
  # heading would assert that we looked and found a person with no details, when in fact no
  # person was identified at all.
  defp person(%{authority_id: id}) when is_binary(id), do: Authority.person(id)
  defp person(_outline), do: nil

  # A lifespan as a printed span. Both ends when both are known, and an open end shown as an
  # open end — `– 1018` means "no later than", and flattening it to "1018" would assert a
  # birth year nobody recorded.
  defp lifespan(%{birth: nil, death: nil}), do: nil

  defp lifespan(person) do
    case {year(person.birth), year(person.death)} do
      {nil, nil} -> nil
      {born, nil} -> "b. #{born}"
      {nil, died} -> "d. #{died}"
      {born, died} -> "#{born}–#{died}"
    end
  end

  defp year(nil), do: nil
  defp year(%{earliest: nil, latest: nil}), do: nil
  defp year(%{earliest: %Date{} = date}), do: date.year
  defp year(%{latest: %Date{} = date}), do: date.year
  defp year(_), do: nil

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
          <p :if={@edition_link} class="text-xs text-base-content/60">
            Published by
            <a href={@edition_link.url} target="_blank" rel="noopener" class="link">
              {@edition_link.edition}
            </a>
            — a convenience, not the citation.
          </p>

          <div :if={@person} class="mt-3 rounded-lg border border-base-300 bg-base-200/40 p-3 text-xs">
            <div class="flex flex-wrap items-baseline gap-x-2">
              <span class="font-medium text-sm">{@person.name}</span>
              <span :if={@person.dynasty} class="text-base-content/60">{@person.dynasty}</span>
              <span :if={lifespan(@person)} class="text-base-content/60">
                {lifespan(@person)}
              </span>
              <span :if={@person.sect} class="badge badge-xs badge-outline">{@person.sect}</span>
            </div>

            <p :if={@person.also_known_as != []} class="mt-1 text-base-content/60">
              also {Enum.join(@person.also_known_as, "、")}
            </p>

            <p :if={@person.place} class="mt-1 text-base-content/60">
              {@person.place.name}
              <span :if={@person.place.historical_region}>
                · {@person.place.historical_region}
              </span>
              <span :if={@person.place.district} class="text-base-content/40">
                · {@person.place.district}
              </span>
            </p>

            <p
              :if={@person.lineage.teachers != [] or @person.lineage.students != []}
              class="mt-1 text-base-content/60"
            >
              <span :if={@person.lineage.teachers != []}>
                taught by {Enum.map_join(@person.lineage.teachers, "、", & &1.name)}
              </span>
              <span :if={@person.lineage.students != []}>
                · taught {Enum.map_join(@person.lineage.students, "、", & &1.name)}
              </span>
            </p>

            <%!--
            The caveats are not a footnote. A reader who takes this panel as settled fact has
            been misled by a surface that looked more certain than the data: the link is an
            inference, and the dates are a bound on a life rather than a date of composition.
            --%>
            <p class="mt-2 text-base-content/50">
              Identified from the byline and DILA's person authority (CC BY-SA 3.0) — <span class="font-medium">probable, never certain</span>: the name is in the
              byline; that it denotes this person rather than an unrecorded namesake is an
              inference.
              <span :if={lifespan(@person)}>
                Dates are the span of a life, not of the work.
              </span>
            </p>
          </div>
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
          <h2 class="font-semibold">Search inside this work</h2>
          <p class="text-xs text-base-content/60">
            A work can run to 92,192 printed lines. Finding a phrase in one is a different
            act from finding it in the canon, and the outline cannot do it.
          </p>
          <form action={~p"/"} method="get" class="flex gap-2">
            <input type="hidden" name="work" value={@work_id} />
            <input type="hidden" name="mode" value="phrase" />
            <input
              type="text"
              name="q"
              placeholder={"a phrase in #{@outline.title || @work_id}"}
              class="input input-bordered input-sm flex-1"
              autocomplete="off"
            />
            <button type="submit" class="btn btn-sm btn-primary">Search</button>
          </form>
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
