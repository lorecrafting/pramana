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

  schema do
    field(:urn, :string,
      required: true,
      description:
        "A Pramana URN, e.g. pramana:cbeta.T:T0262_001@p0001a05 " <>
          "(source.witness:work@page-register-line)."
    )
  end

  @impl true
  def execute(%{urn: urn}, frame) do
    case Corpus.resolve(urn) do
      {:ok, span} ->
        {:reply, Response.json(Response.tool(), payload(span)), frame}

      {:error, :bad_urn} ->
        {:reply,
         Response.error(
           Response.tool(),
           "Malformed URN: #{urn}. Expected pramana:<source>.<witness>:<work>[@<locator>]."
         ), frame}

      {:error, :not_found} ->
        {:reply,
         Response.error(
           Response.tool(),
           "No passage exists at #{urn}. This URN is well-formed but addresses nothing " <>
             "in the current bake — do not cite it."
         ), frame}
    end
  end

  defp payload(span) do
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
      apparatus: span.meta["apparatus"],
      notes: span.meta["notes"],
      editorial_punctuation: span.meta["editorial_punctuation"] == true
    }
  end
end
