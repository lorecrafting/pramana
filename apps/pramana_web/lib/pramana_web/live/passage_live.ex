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
    and hiding the disagreement would make it a reading text. Witnesses are named from
    **this text's own header**, never from a global table: `wit1` means 38 different
    things across the canon, so a shared table would confidently misattribute a Ming
    variant to the Song edition in about a thousand works;
  - **rare characters** with their mappings, since those are the content a reader cannot
    reconstruct from anything else;
  - **provenance**, in words, above the text rather than below it;
  - a link into the **published edition**, and the **photograph of the woodblock leaf**
    where BDRC has one. This is the strongest form of "check us against the print" the
    corpus can offer, and it belongs on the human surface more than anywhere else — the
    MCP tools have carried both for phases while the reader, the thing an actual scholar
    opens, had neither;
  - the **translation pool**, all of it — a rendering is never presented as *the*
    translation, and a machine translation is never presented as source (`docs/LAYERS.md`
    and invariant #8);
  - **parallels and alternates**, labelled as what they are. A parallel is a different
    text judged to transmit the same material, not a translation of this one, and an
    alternate is a candidate for 異譯本 rather than an established alternate translation —
    the curated data cannot tell T0099/T0100 (a real one) from T0099/T0125 (two different
    Āgama collections) and this page must not either.
  """
  use PramanaWeb, :live_view

  import PramanaWeb.ReaderComponents

  alias Pramana.Apparatus
  alias Pramana.Commentary
  alias Pramana.Compare
  alias Pramana.Corpus
  alias Pramana.Derge.Images
  alias Pramana.Reader

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
         |> assign(versions: versions_for(urn))
         |> assign(apparatus: apparatus_for(urn))
         |> assign(glosses: Commentary.glosses_on(urn, limit: 8))
         |> assign(
           edition_link: Reader.reference(urn, context.focus.provenance),
           page_image: page_image(urn)
         )
         |> assign(page_title: page_title(context.focus))}

      {:error, reason} ->
        {:noreply,
         assign(socket,
           urn: urn,
           context: nil,
           outline: nil,
           versions: nil,
           apparatus: nil,
           glosses: [],
           edition_link: nil,
           page_image: nil,
           error: reason
         )}
    end
  end

  def handle_params(_params, _uri, socket) do
    {:noreply,
     assign(socket,
       urn: nil,
       context: nil,
       outline: nil,
       versions: nil,
       apparatus: nil,
       glosses: [],
       edition_link: nil,
       page_image: nil,
       error: :bad_urn
     )}
  end

  # Absent rather than guessed. `Images.for_urn/1` returns `:error` for anything that is
  # not a Degé folio and for folios the scan index does not cover, and a broken <img> is a
  # worse claim than no image.
  defp page_image(urn) do
    case Images.for_urn(urn) do
      {:ok, image} -> image
      :error -> nil
    end
  end

  # `Apparatus.at/1` rather than the raw `meta["apparatus"]` the line already carries,
  # because only this names the witnesses — and it names them from the text's OWN header.
  # A range URN is refused rather than answered for one of its lines, which is why this
  # can return an error for a passage that resolves perfectly well.
  defp apparatus_for(urn) do
    case Apparatus.at(urn) do
      {:ok, %{variants: []}} -> nil
      {:ok, apparatus} -> apparatus
      {:error, _} -> nil
    end
  end

  # `Compare.versions/2` returns `nil` for a section with nothing in it rather than an
  # empty structure pretending to be an answer, and this page renders that distinction:
  # a passage with no recorded parallel shows no parallels heading at all, instead of a
  # heading over an empty list that reads as "we looked and the tradition is silent".
  defp versions_for(urn) do
    case Compare.versions(urn, include_text: false) do
      {:ok, versions} -> versions
      {:error, _} -> nil
    end
  end

  # The note explains the three sections above it and is noise without them — and worse
  # than noise, since a reader who sees "Parallels are DIFFERENT texts…" under a passage
  # showing no parallels has been told about a section that is not there.
  defp shows_versions?(%{renderings: nil, parallels: nil, alternates: nil}), do: false
  defp shows_versions?(versions) when is_map(versions), do: true
  defp shows_versions?(_), do: false

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

        <section :if={@glosses != []} class="space-y-2">
          <h2 class="font-semibold">Commentary on this line</h2>
          <p class="text-xs text-base-content/60">
            Found by lemma match: each commentary quotes this line verbatim before glossing
            it. A commentary explains scripture and is <strong>never citable as</strong>
            scripture — follow the link to read it in its own place.
          </p>
          <ul class="space-y-2 text-sm">
            <li :for={g <- @glosses} class="border-l-2 border-base-300 pl-3">
              <.link navigate={~p"/passage?#{[urn: g.commentary_urn]}"} class="link font-medium">
                {g.commentary_title || g.commentary_work_id}
              </.link>
              <span :if={g.commentary_author} class="text-base-content/60">
                · {g.commentary_author}
              </span>
              <div class="font-mono text-xs text-base-content/50">{g.commentary_urn}</div>
              <div class="text-base-content/70">
                quotes <span class="font-medium">{g.lemma}</span>
              </div>
            </li>
          </ul>
        </section>

        <section :if={@edition_link || @page_image} class="space-y-2">
          <h2 class="font-semibold">Check it against the edition</h2>
          <div :if={@edition_link} class="text-sm">
            <a href={@edition_link.url} target="_blank" rel="noopener" class="link">
              {@edition_link.edition}
            </a>
            <span class="text-base-content/60">
              — opens the {@edition_link.granularity}, not the line.
              <span :if={@edition_link.anchor}>
                Its {@edition_link.anchor_label} for this line is <code class="font-mono">{@edition_link.anchor}</code>.
              </span>
            </span>
            <p class="mt-1 text-xs text-base-content/50">
              The URN is the citation; this link is a convenience and is <strong>not verified</strong>
              — these readers return HTTP 200 for any path, so it cannot be checked by
              fetching it.
            </p>
          </div>

          <div :if={@page_image} class="space-y-1 text-sm">
            <a href={@page_image.image_url} target="_blank" rel="noopener" class="link">
              Photograph of the woodblock leaf — volume {@page_image.volume}, folio {@page_image.folio}
            </a>
            <p class="text-xs text-base-content/50">
              {@page_image.attribution}. Served by BDRC; nothing here has read it.
            </p>
          </div>
        </section>

        <section :if={@apparatus} class="space-y-2">
          <h2 class="flex items-baseline gap-2 font-semibold">
            Variant readings
            <span class="text-sm font-normal text-base-content/60">
              {length(@apparatus.variants)} across {@apparatus.lemma_count} lemma(s)
            </span>
          </h2>
          <p class="text-xs text-base-content/60">
            Where the witnesses this edition collated read differently from the base text.
            Sigla come from this text's own header — they are not stable across the canon.
          </p>
          <ul class="space-y-1 text-sm">
            <li :for={variant <- @apparatus.variants} class="flex flex-wrap items-baseline gap-2">
              <span class="font-medium">{variant.lemma}</span>
              <span class="text-base-content/50">]</span>
              <span :if={variant.omitted} class="italic text-base-content/60">omitted</span>
              <span :if={!variant.omitted}>{variant.reading}</span>
              <span :if={variant.witness} class="badge badge-sm badge-outline">
                {variant.witness}
              </span>
              <span :if={is_nil(variant.witness)} class="badge badge-sm badge-ghost">
                {variant.witness_id} — witness unidentified for this text
              </span>
            </li>
          </ul>
        </section>

        <section :if={@versions && @versions.renderings} class="space-y-2">
          <h2 class="flex items-baseline gap-2 font-semibold">
            Translations
            <span class="text-sm font-normal text-base-content/60">
              {@versions.renderings.count} in {@versions.renderings.lang}
            </span>
          </h2>
          <p class="text-xs text-base-content/60">
            The whole pool, not a winner. A rendering is addressed as a fragment of this
            passage's URN, so stripping it always leaves a citable source.
          </p>
          <article
            :for={rendering <- @versions.renderings.pool}
            class="space-y-1 rounded-lg bg-base-200/40 p-3"
          >
            <p class="leading-relaxed">{rendering.text}</p>
            <div class="flex flex-wrap items-center gap-2 text-xs text-base-content/60">
              <span class="badge badge-sm badge-outline">{rendering.tier}</span>
              <span :if={rendering.method != "human"} class="badge badge-sm badge-warning">
                {rendering.method}-generated — not citable as source
              </span>
              <span>{rendering.translator || rendering.translator_id}</span>
              <span class="font-mono break-all">{rendering.urn}</span>
            </div>
          </article>
        </section>

        <section :if={@versions && @versions.parallels} class="space-y-2">
          <h2 class="flex items-baseline gap-2 font-semibold">
            Parallels
            <span class="text-sm font-normal text-base-content/60">
              {@versions.parallels.total} recorded · {@versions.parallels.quotable} resolvable here
            </span>
          </h2>
          <p class="text-xs text-base-content/60">
            Different texts judged to transmit the same material. Neither is a translation
            of the other.
          </p>
          <p
            :if={@versions.parallels.referenced_but_not_held > 0}
            class="alert alert-info alert-soft text-xs"
          >
            {@versions.parallels.referenced_but_not_held} of these point at texts this bake
            does not hold, so they cannot be opened. They are counted rather than dropped:
            a parallel we cannot show still tells you it exists.
          </p>
          <ul class="space-y-1 text-sm">
            <li
              :for={parallel <- Enum.take(@versions.parallels.versions, 25)}
              class="flex flex-wrap items-baseline gap-2"
            >
              <span class="badge badge-sm badge-ghost">{parallel[:relation]}</span>
              <span :if={parallel[:partial]} class="badge badge-sm badge-outline">partial</span>
              <span class="text-base-content/60">{parallel[:uid]}</span>
              <.link
                :if={parallel[:urn]}
                navigate={~p"/passage?#{[urn: parallel[:urn]]}"}
                class="link link-hover font-mono text-xs break-all"
              >
                {parallel[:urn]}
              </.link>
              <span :if={is_nil(parallel[:urn])} class="text-xs text-base-content/50">
                not in this bake
              </span>
            </li>
          </ul>
        </section>

        <section :if={@versions && @versions.alternates} class="space-y-2">
          <h2 class="font-semibold">
            Other works transmitting this material
            <span class="text-sm font-normal text-base-content/60">
              {@versions.alternates.count}
            </span>
          </h2>
          <p class="text-xs text-base-content/60">
            Candidates for 異譯本 — <strong>not</strong>
            established alternate translations. The evidence is shared passages, which
            cannot distinguish a genuine re-translation from two different collections
            that overlap.
          </p>
          <ul class="space-y-1 text-sm">
            <li :for={work <- @versions.alternates.works} class="flex flex-wrap items-baseline gap-2">
              <span class="font-medium">{work[:work_id]}</span>
              <span class="text-base-content/70">{work[:title]}</span>
              <span :if={work[:attributed_author]} class="text-base-content/60">
                · {work[:attributed_author]}
              </span>
              <span class="badge badge-sm badge-ghost">{work[:confidence]}</span>
            </li>
          </ul>
        </section>

        <p :if={shows_versions?(@versions)} class="text-xs text-base-content/60">
          {@versions.note}
        </p>

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
