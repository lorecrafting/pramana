defmodule PramanaWeb.MCP.Tools.CompareWitnesses do
  @moduledoc """
  Where the manuscript witnesses to a line disagree.

  The Taishō collates the Song, Yuan, Ming, Koryŏ and other editions against its base
  text and prints the differences; CBETA encodes them, and **572,701 segments here carry
  one**. "This character differs in the Song edition" is what a philologist actually
  needs, and it is a question no other AI tool over this corpus can answer.

  Each reading names its witness in the edition's **own sigla** (【宋】, 【元】, 【明】).
  Those ids are declared per file and are not stable across the canon — `wit1` means 38
  different things — so an unresolvable id is reported as unidentified rather than
  guessed at. See `Pramana.Apparatus`.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Pramana.Apparatus
  alias PramanaWeb.MCP.Reply

  schema do
    field(:urn, :string,
      required: true,
      description:
        "A single-line URN, e.g. pramana:cbeta.T:T1982_001@p0459c10. A range addresses " <>
          "several lines and is refused: the apparatus of the first line is not the " <>
          "apparatus of the range."
    )
  end

  @impl true
  def execute(%{urn: urn} = params, frame) do
    case Apparatus.at(urn) do
      {:ok, payload} ->
        {:reply, Reply.json("compare_witnesses", params, payload), frame}

      {:error, :not_a_single_line} ->
        {:reply,
         Response.error(
           Response.tool(),
           "#{urn} addresses a range of lines. Variants are recorded per line, so ask " <>
             "for one — the apparatus of the first line is not the apparatus of the range."
         ), frame}

      {:error, :not_found} ->
        {:reply,
         Response.error(
           Response.tool(),
           "No passage exists at #{urn}. This URN is well-formed but addresses nothing " <>
             "in the current bake — do not cite it."
         ), frame}

      {:error, _} ->
        {:reply,
         Response.error(
           Response.tool(),
           "Malformed URN: #{urn}. Expected pramana:<source>.<witness>:<work>@<locator>."
         ), frame}
    end
  end
end
