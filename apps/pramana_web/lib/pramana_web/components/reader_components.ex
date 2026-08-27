defmodule PramanaWeb.ReaderComponents do
  @moduledoc """
  The pieces of the reader that carry an invariant, rather than the ones that carry a
  layout.

  Every one of these exists because something in `CLAUDE.md` has to survive contact with
  a human interface:

  - `provenance_line/1` — invariant #4. A Kamakura-period Japanese commentary must never
    be presentable as an Indian sūtra, so origin and role travel *with* the passage and
    are rendered as words, not as a colour or an icon a reader can learn to ignore.
  - `citation/1` — invariant #1 and #2. Nothing is quotable from this reader without its
    URN and its sha256 travelling with it, and the URN is the edition's own citation
    grammar rather than an id we minted.
  - `coverage_note/1` — the Coverage doctrine. An absence must read as a gap in what is
    loaded, never as the tradition being silent.

  The reader is a **renderer**. If one of these needs to compute something about the
  corpus, that means the domain is missing a function — add it there. The provenance
  grouping already made that trip: it lived in the MCP tool and now lives in
  `Pramana.Provenance.group/1`, because two surfaces describing one bucket differently is
  how a corpus starts contradicting itself.
  """
  use PramanaWeb, :html

  alias Pramana.Embed.Serving
  alias Pramana.Provenance

  @doc """
  Where a passage comes from, in words.

  Origin and role first, because those are the axes a reader can get wrong in a way that
  matters. The edition reference — Taishō volume, page, register, line — comes second and
  is what makes the claim checkable against print.
  """
  attr :provenance, :map, required: true
  attr :class, :string, default: nil

  def provenance_line(assigns) do
    ~H"""
    <div class={["flex flex-wrap items-center gap-x-2 gap-y-1 text-xs", @class]}>
      <span class="badge badge-sm badge-outline">
        {Provenance.label(@provenance[:composition_origin], @provenance[:text_role])}
      </span>
      <.link
        :if={@provenance[:work_id]}
        navigate={~p"/works/#{@provenance[:work_id]}"}
        class="link link-hover font-medium"
      >
        {@provenance[:work_id]}
      </.link>
      <span :if={@provenance[:title]} class="text-base-content/70">{@provenance[:title]}</span>
      <span :if={@provenance[:attributed_author]} class="text-base-content/60">
        · {@provenance[:attributed_author]}
        <span :if={@provenance[:attribution_confidence] not in [nil, "certain"]}>
          ({@provenance[:attribution_confidence]})
        </span>
      </span>
      <span :if={@provenance[:division]} class="text-base-content/60">
        · {@provenance[:division]}
      </span>
      <span class="text-base-content/60">· {printed_reference(@provenance)}</span>
      <span :if={addressing_caveat(@provenance)} class="badge badge-sm badge-warning">
        {addressing_caveat(@provenance)}
      </span>
    </div>
    """
  end

  # THREE levels, not two, and the middle one is the whole reason the field exists.
  #
  # `canonical` is checkable against a published critical edition. `edition_page` is a
  # page number PRINTED IN THE PHYSICAL BOOK, recovered by our extraction — a reader with
  # the book can turn to it, and the risk sits in the extraction rather than in the anchor.
  # `derived` has no intrinsic anchor at all: positions come from file structure and move
  # when the file does.
  #
  # This rendered "edition_page anchor — not checkable against a printed page", which
  # inverts the middle case: an edition page is exactly a printed page. `Pramana.Corpus`
  # records that collapsing `edition_page` into `derived` "understated what can be
  # verified", and this reader was doing it again one layer up — over 4,576 texts,
  # including the whole Degé Tengyur.
  defp addressing_caveat(%{addressing: "derived"}),
    do: "derived anchor — no printed page to check against"

  defp addressing_caveat(%{addressing: "edition_page"}),
    do: "anchored to the printed page, not to a critical edition"

  defp addressing_caveat(_), do: nil

  @doc """
  A passage's citation: the URN, and the hash that makes quoting it verifiable.

  Displayed rather than hidden behind a button, because the URN *is* the citation — a
  scholar checking us against a print edition reads `T0262_001@p0001c19` as Taishō volume,
  page, register and line, and that legibility is the whole point of adopting each
  tradition's grammar instead of minting ids.
  """
  attr :span, :map, required: true

  def citation(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center gap-2 font-mono text-xs text-base-content/60">
      <.link navigate={~p"/passage?#{[urn: @span.urn]}"} class="link link-hover break-all">
        {@span.urn}
      </.link>
      <span class="hidden sm:inline">sha256:{String.slice(@span.sha256, 0, 12)}…</span>
      <span :if={volume_of(@span)} class="badge badge-xs">
        vol. {volume_of(@span)}
      </span>
    </div>
    """
  end

  @doc """
  What the corpus does not hold, stated wherever results are shown.

  Two separate silences, and both are lies by omission if unstated: a canon that is not
  ingested (`Pramana.Coverage`), and a canon that is ingested but not indexed for meaning
  — CBETA's X collection is baked, lexically searchable and carries no vectors, which a
  chunk-level coverage figure of 100% happily concealed.
  """
  attr :coverage, :map, default: nil
  attr :caveat, :string, default: nil
  attr :retrievers, :list, default: nil

  def coverage_note(assigns) do
    ~H"""
    <div
      :if={@caveat || (@coverage && @coverage[:note]) || @retrievers}
      class="alert alert-info alert-soft text-xs"
    >
      <.icon name="hero-information-circle" class="size-4 shrink-0" />
      <div class="space-y-1">
        <p :if={@caveat}>{@caveat}</p>
        <p :if={@coverage && @coverage[:note]}>{@coverage[:note]}</p>
        <p :if={@retrievers}>
          Searched by: {Enum.join(@retrievers, " + ")}.
          <span :if={"semantic" not in @retrievers}>
            Meaning-based matches were not considered — only the characters you typed. {semantic_absent_because()}
          </span>
        </p>
      </div>
    </div>
    """
  end

  # WHY the semantic arm did not run, which is a different fact from THAT it did not.
  #
  # "No serving is running" is fixed by starting the server differently and says nothing
  # about the corpus; "nothing is embedded" is a fact about the corpus and no restart will
  # help. Reporting only the symptom leaves a reader to guess which, and the guess decides
  # whether they conclude the canon is thin.
  defp semantic_absent_because do
    if Serving.available?() do
      "The serving is running, so this query reached nothing embedded."
    else
      "No embedding serving is running here — start the server with PRAMANA_EMBEDDING=1 " <>
        "to enable it. This is a property of this process, not of the corpus."
    end
  end

  @doc """
  One printed line, set for reading.

  Classical Chinese at a size that can actually be read, and an empty line rendered as
  what it is — a line whose printed content is a note or a rare character, not a line
  with nothing on it. Those exist: one line in the whole CBETA corpus is the single
  character 䦚 and nothing else.
  """
  attr :span, :map, required: true
  attr :focus, :boolean, default: false

  def passage_line(assigns) do
    ~H"""
    <div class={[
      "flex gap-3 rounded px-2 py-1",
      @focus && "bg-primary/10 ring-1 ring-primary/30"
    ]}>
      <span class="w-24 shrink-0 pt-1 font-mono text-xs text-base-content/40">
        {locator(@span)}
      </span>
      <div class="min-w-0 flex-1">
        <p :if={@span.content != ""} class="text-lg leading-relaxed break-words">
          {@span.content}
        </p>
        <p :if={@span.content == ""} class="text-sm text-base-content/50 italic">
          {empty_line_reason(@span)}
        </p>
        <.line_meta meta={@span.meta} />
      </div>
    </div>
    """
  end

  attr :meta, :map, default: %{}

  defp line_meta(assigns) do
    ~H"""
    <div :if={is_map(@meta) and @meta != %{}} class="mt-1 space-y-1 text-xs">
      <p :for={note <- Map.get(@meta, "notes", [])} class="text-base-content/60">
        <span class="badge badge-xs badge-ghost mr-1">note</span>{note}
      </p>
      <p :for={g <- Map.get(@meta, "gaiji", [])} class="text-base-content/60">
        <span class="badge badge-xs badge-ghost mr-1">rare glyph</span>
        {gaiji_label(g)}
      </p>
      <div :for={app <- Map.get(@meta, "apparatus", [])} class="text-base-content/70">
        <span class="badge badge-xs badge-accent mr-1">variant</span>
        <span class="font-medium">{app["lem"]}</span>
        <span :for={rdg <- app["rdgs"] || []} class="ml-2">] {reading_text(rdg)}</span>
      </div>
    </div>
    """
  end

  # THE WITNESS ID IS NOT SHOWN HERE, and its absence is the point. `meta["apparatus"]`
  # carries the raw `wit="#wit1"` from the file, and `wit1` means 38 different things
  # across the canon — 宋 in 832 files, 明 in 375, 甲 in 322. Rendering it beside a reading
  # would put a sigil-shaped string in front of a reader who has every reason to take it
  # for one. Naming a witness requires that text's own header, which is what
  # `Pramana.Apparatus.at/1` does, and the passage page shows the named version for the
  # line in focus. Here — on neighbouring lines — a reader is told a variant EXISTS and
  # can open that line to find out whose it is.

  # A witness that OMITS the lemma is not a witness with empty text: "omitted" is a
  # reading, and printing nothing for it would silently turn a real variant into a blank.
  defp reading_text(%{"omitted" => true}), do: "(omitted)"
  defp reading_text(%{"text" => text}), do: text
  defp reading_text(_), do: "(omitted)"

  defp gaiji_label(%{"mapping" => %{"unicode" => unicode}} = g) when is_binary(unicode),
    do: "#{unicode} (#{g["ref"]})"

  defp gaiji_label(%{"mapping" => %{"composition" => comp}} = g) when is_binary(comp),
    do: "#{comp} (#{g["ref"]}) — no Unicode character exists for this glyph"

  defp gaiji_label(g), do: "#{g["ref"]} — unmapped"

  # Never "(blank)": the segmenter only emits a line that had something printed on it, so
  # if the text is empty the content is in the metadata and the reader should be told
  # which kind it is.
  defp empty_line_reason(%{meta: meta}) when is_map(meta) do
    cond do
      Map.has_key?(meta, "gaiji") -> "a rare character, below"
      Map.has_key?(meta, "notes") -> "an interlinear note, below"
      Map.has_key?(meta, "apparatus") -> "a variant reading, below"
      true -> "printed, but carrying no body text"
    end
  end

  defp empty_line_reason(_), do: "printed, but carrying no body text"

  # A page/register/line for the Chinese canons, and the edition's own anchor for the
  # traditions that do not have one — SuttaCentral segment ids, Derge folio/side/line.
  # Falling through to a dash would tell a Pāli reader their passage has no citation,
  # when in fact `sn6.4:1.1` IS the citation and is printed in the URN two lines below.
  defp locator(%{provenance: p} = span) when is_map(p) do
    case [
           p[:juan] && "j#{p[:juan]}",
           p[:page] && "#{p[:page]}#{p[:register]}#{pad_line(p[:line])}"
         ]
         |> Enum.reject(&is_nil/1) do
      [] -> urn_locator(span)
      parts -> Enum.join(parts, " ")
    end
  end

  defp locator(span), do: urn_locator(span)

  defp urn_locator(%{urn: urn}) when is_binary(urn) do
    case String.split(urn, "@", parts: 2) do
      [_, locator] -> locator
      _ -> "—"
    end
  end

  defp urn_locator(_), do: "—"

  defp pad_line(nil), do: ""
  defp pad_line(n), do: String.pad_leading(Integer.to_string(n), 2, "0")

  defp printed_reference(p) do
    volume = p[:volume] && "vol. #{p[:volume]}"
    page = p[:page] && "p. #{p[:page]}#{p[:register]}#{pad_line(p[:line])}"

    [p[:witness], volume, page]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp volume_of(%{provenance: %{volume: volume}}), do: volume
  defp volume_of(_), do: nil
end
