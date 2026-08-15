defmodule PramanaWeb.MCP.Tools.GetPassage do
  @moduledoc """
  Resolves a Pramāṇa URN to the exact passage it addresses.

  Returns **structured data, never prose** (`CLAUDE.md` invariant #1): every response
  carries the URN, character and byte offsets, a sha256, and full multi-axis
  provenance, so the caller can independently verify anything it goes on to quote.
  This is also what makes the Phase 8 reader cheap — the UI becomes a renderer.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Pramana.Corpus
  alias Pramana.Reader

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
  end

  @impl true
  def execute(%{urn: urn} = params, frame) do
    before_n = params[:context_before] || 0
    after_n = params[:context_after] || 0

    if before_n > 0 or after_n > 0 do
      with_context(urn, before_n, after_n, frame)
    else
      single(urn, frame)
    end
  end

  defp with_context(urn, before_n, after_n, frame) do
    case Corpus.context(urn, before: before_n, after: after_n) do
      {:ok, ctx} ->
        payload = %{
          # The range URN covering the window. Citable and verifiable as a unit.
          urn: ctx.urn,
          text: ctx.text,
          segment_count: ctx.segment_count,
          focus: payload(ctx.focus),
          # Neighbours are full spans, each independently verifiable — the readable
          # `text` above is a convenience, not a substitute for attribution.
          before: Enum.map(ctx.before, &payload/1),
          after: Enum.map(ctx.after, &payload/1)
        }

        {:reply, Response.json(Response.tool(), payload), frame}

      {:error, reason} ->
        {:reply, Response.error(Response.tool(), error_message(urn, reason)), frame}
    end
  end

  defp single(urn, frame) do
    case Corpus.resolve(urn) do
      {:ok, span} ->
        {:reply, Response.json(Response.tool(), payload(span)), frame}

      {:error, reason} ->
        {:reply, Response.error(Response.tool(), error_message(urn, reason)), frame}
    end
  end

  defp error_message(urn, :bad_urn),
    do: "Malformed URN: #{urn}. Expected pramana:<source>.<witness>:<work>[@<locator>]."

  defp error_message(urn, :not_found),
    do:
      "No passage exists at #{urn}. This URN is well-formed but addresses nothing " <>
        "in the current bake — do not cite it."

  defp payload(span) do
    %{
      urn: span.urn,
      bake_id: Pramana.Bake.current_id(),
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
      apparatus: span.meta["apparatus"],
      notes: span.meta["notes"],
      editorial_punctuation: span.meta["editorial_punctuation"] == true
    }
  end
end
