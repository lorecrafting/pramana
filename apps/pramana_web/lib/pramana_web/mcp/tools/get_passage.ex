defmodule PramanaWeb.MCP.Tools.GetPassage do
  @moduledoc """
  Resolves a Pramāṇa URN to the exact passage it addresses.

  Returns **structured data, never prose** (`CLAUDE.md` invariant #1): every response
  carries the URN, character and byte offsets, a sha256, and full multi-axis
  provenance, so the caller can independently verify anything it goes on to quote.
  This is also what makes the Phase 8 reader cheap — the UI becomes a renderer.
  """

  use Anubis.Server.Component, type: :tool

  alias Pramana.Corpus
  alias Pramana.Derge.Images
  alias Pramana.Reader
  alias Pramana.Translations
  alias PramanaWeb.MCP.Reply

  schema do
    field(:urn, :string,
      required: true,
      description:
        "A Pramana URN, e.g. pramana:cbeta.T:T0262_001@p0001a05 " <>
          "(source.witness:work@page-register-line). Ranges are accepted: " <>
          "...@p0001c18-p0001c21 resolves and verifies as a single unit."
    )

    field(:context_before, :integer,
      description:
        "Include this many preceding lines. Taisho lines are typographic and break " <>
          "mid-sentence, so one line alone is often unreadable. Max 50."
    )

    field(:context_after, :integer, description: "Include this many following lines. Max 50.")

    field(:translation, :string,
      description:
        "Attach translations of the passage in this language, e.g. `en`. The source " <>
          "text is always returned unchanged; translations arrive in a separate " <>
          "`translations` key, never merged into `text`."
    )

    field(:translator, :string,
      description:
        "Pin one translator by id, e.g. `sujato` or `brahmali`. Without it the pool is " <>
          "returned in preference order and `alternatives` says how many were not shown."
    )

    field(:compare_translations, :boolean,
      description:
        "Return EVERY rendering rather than the preferred one. There is no single " <>
          "English translation of this material; comparing is the honest default when " <>
          "a passage is contested."
    )
  end

  @impl true
  def execute(%{urn: urn} = params, frame) do
    before_n = params[:context_before] || 0
    after_n = params[:context_after] || 0

    if before_n > 0 or after_n > 0 do
      with_context(urn, before_n, after_n, params, frame)
    else
      single(urn, params, frame)
    end
  end

  # Translations are attached under their own key and never folded into `text`. A model
  # that receives Sujato's English in the field where the Pāli belongs will quote it as
  # the Pāli — which is `CLAUDE.md` invariant #7 failing at the presentation layer rather
  # than in the guard, where nothing would catch it.
  defp translations(span_urn, params) do
    case params[:translation] do
      nil ->
        nil

      lang ->
        policy = [
          lang: lang,
          translator: params[:translator],
          mode: if(params[:compare_translations], do: :compare, else: :single)
        ]

        selection = Translations.select(span_urn, policy)

        %{
          lang: lang,
          rendering: selection.rendering,
          alternatives: selection.alternatives,
          pool: selection.pool,
          # Stated in every response rather than left to the caller to remember.
          citable_as_source: false
        }
    end
  end

  defp with_context(urn, before_n, after_n, params, frame) do
    case Corpus.context(urn, before: before_n, after: after_n) do
      {:ok, ctx} ->
        payload = %{
          # The range URN covering the window. Citable and verifiable as a unit.
          urn: ctx.urn,
          text: ctx.text,
          segment_count: ctx.segment_count,
          focus: payload(ctx.focus, params),
          # Neighbours are full spans, each independently verifiable — the readable
          # `text` above is a convenience, not a substitute for attribution.
          before: Enum.map(ctx.before, &payload(&1, params)),
          after: Enum.map(ctx.after, &payload(&1, params))
        }

        {:reply, Reply.json("get_passage", params, payload), frame}

      {:error, reason} ->
        {:reply,
         Reply.error("get_passage", params, reason_code(reason), error_message(urn, reason)),
         frame}
    end
  end

  defp single(urn, params, frame) do
    case Corpus.resolve(urn) do
      {:ok, span} ->
        {:reply, Reply.json("get_passage", params, payload(span, params)), frame}

      {:error, reason} ->
        {:reply,
         Reply.error("get_passage", params, reason_code(reason), error_message(urn, reason)),
         frame}
    end
  end

  # The reason a MODEL branches on, beside the sentence a person reads. `:bad_urn` is the
  # caller's mistake and `:not_found` is a fact about this bake — two different next steps,
  # and previously distinguishable only by matching on English.
  # `Corpus.resolve/1` returns exactly these two, so there is no catch-all: dialyzer refuses a
  # clause it can prove unreachable, and a defensive fallback here would be dead code
  # pretending to be caution. If a third reason is ever added, this stops compiling — which
  # is the correct place to be told.
  defp reason_code(:bad_urn), do: :bad_urn
  defp reason_code(:not_found), do: :not_found

  defp error_message(urn, :bad_urn),
    do: "Malformed URN: #{urn}. Expected pramana:<source>.<witness>:<work>[@<locator>]."

  defp error_message(urn, :not_found),
    do:
      "No passage exists at #{urn}. This URN is well-formed but addresses nothing " <>
        "in the current bake — do not cite it."

  # A RENDERING IS NOT A PASSAGE, AND SAYING SO IS INVARIANT #8.
  #
  # `Corpus.resolve/1` routes a URN carrying `#tr:<lang>/<translator>` to the translation
  # layer, so this tool really can be handed one — and it crashed on every rendering URN
  # with `KeyError: key :sha256`, because a rendering span has no offsets into a witness
  # and named its hash differently. Found 2026-09-03 by performing `docs/CHECKS.md` §2's
  # invariant #8 audit by hand.
  #
  # It answers now, and the answer leads with what the thing is. No offsets are invented:
  # a rendering has none, and a fabricated range would be exactly the false precision the
  # citation guard exists to make impossible. `anchor_urn` is what a caller cites.
  defp payload(%{anchor_urn: anchor} = span, _params) when is_binary(anchor) do
    %{
      urn: span.urn,
      layer: "translation",
      citable_as_source: false,
      anchor_urn: anchor,
      text: span.content,
      sha256: span.sha256,
      provenance: span.provenance,
      note:
        "This is a RENDERING of #{anchor}, not a passage of any witness. Cite " <>
          "`anchor_urn` and quote the source there; a translation is never citable as " <>
          "source, and a generated one carries `method` other than `human`. It has no " <>
          "offsets because it indexes no edition — fetch `anchor_urn` for those."
    }
  end

  defp payload(span, params) do
    %{
      urn: span.urn,
      text: span.content,
      sha256: span.sha256,
      offsets: %{
        char_start: span.char_start,
        char_end: span.char_end,
        byte_start: span.byte_start,
        byte_end: span.byte_end
      },
      kind: span.kind,
      provenance: span.provenance,
      # Where a human goes to check this against the published edition. Absent rather
      # than guessed when no confirmed template exists for the source.
      reader: Reader.reference(span.urn, span.provenance),
      # The photograph of the leaf this was printed on, where one exists. The strongest
      # form of "check us against the print" this corpus can offer, and it is a LINK:
      # BDRC serves the image, the attribution says so, and nothing here has read it.
      page_image: page_image(span.urn),
      apparatus: span.meta["apparatus"],
      # A count, not the resolved variants: resolving witness ids needs the text's own
      # sigla (they are per file — `wit1` means 38 different things across the canon), and
      # doing it here would duplicate `Pramana.Apparatus` in a second response shape where
      # the two could drift. This tells a reader there is something to look at;
      # `compare_witnesses` tells them what.
      variant_count: length(span.meta["apparatus"] || []),
      notes: span.meta["notes"],
      editorial_punctuation: span.meta["editorial_punctuation"] == true,
      translations: translations(span.urn, params)
    }
  end

  defp page_image(urn) do
    case Images.for_urn(urn) do
      {:ok, image} -> image
      :error -> nil
    end
  end
end
