defmodule PramanaWeb.MCP.Reply do
  @moduledoc """
  Every tool response carries the call that produced it.

  A URN is a reproducible citation of a **passage**: resolve it against the same `bake_id`
  and you get the same bytes. This does the same thing one layer up, for a **retrieval** —
  `{tool, arguments, bake_id}` is enough to run the query again and get the same answer.

  That is what `docs/IDEAS.md` stars as *"show your work" mode*, in its smallest useful
  form. A model writing a sourced report can attach the `replay` record beside each claim,
  and a reader can check not only that the quotation is real but that the search which found
  it was the search the report says it was.

  ## Stateless on purpose

  No session, no trace table, no accumulation. `CLAUDE.md` invariant #7 says the MCP surface
  is read-only — *tools read, the CLI writes* — and a per-session trace would be a write
  path from the model's side of the boundary, however benign. A response that describes
  itself needs neither.

  ## It also makes `bake_id` uniform

  Nine of the fifteen tools attached `bake_id` and six did not, each building it inline.
  `survey_corpus` was among the six, which is the worst of them: it is the tool whose whole
  purpose is to support a claim about *how often*, and a count without the corpus it counted
  is not evidence of anything.
  """

  alias Anubis.Server.Response

  @doc """
  Wraps a payload with the call that produced it and the corpus that answered.

  `arguments` is what the caller actually passed, not the tool's defaults: the point is to
  reproduce *this* answer, and a default that changes later would silently reproduce a
  different one.

  Tool and arguments come **before** the payload so a call reads as *this tool, these
  arguments, this result* — and so the fifteen existing `Response.json(Response.tool(), …)`
  calls could be converted by inserting a prefix, rather than by finding the closing paren
  of a payload that spans thirty lines.
  """
  @spec json(String.t(), map(), map()) :: Response.t()
  def json(tool, arguments, payload) when is_binary(tool) and is_map(payload) do
    # THE SURFACE THE WHOLE THESIS RESTS ON, AND IT WAS UNOBSERVED. Every tool builds its
    # response here, so this is the one place that sees them all.
    #
    # A COUNT, not a duration: this runs after the work, and timing a tool properly needs a
    # hook around `execute/2` that the server does not currently expose. Which tools are
    # called and how often is most of the value and was previously zero; the honest thing is
    # to report what is measured rather than a duration that would be the time to build a map.
    Pramana.Telemetry.emit([:pramana, :mcp, :tool], %{calls: 1}, %{tool: tool})

    payload
    |> Map.put(:bake_id, Pramana.Bake.current_id())
    |> Map.put(:replay, %{tool: tool, arguments: normalize(arguments)})
    |> then(&Response.json(Response.tool(), &1))
  end

  @doc """
  An error a model can branch on, not only read.

  Nineteen error paths across seventeen tools were each a hand-written sentence. Prose is the
  right thing to *show* a caller and the wrong thing to give it as a contract: a model cannot
  distinguish "this URN does not exist" from "this work is not in the bake" from "your query
  was empty" without matching on English, which changes whenever someone improves the wording.

  So an error carries a **`reason`** — a stable, snake_case atom naming the failure — beside
  the sentence, and the sentence stays as good as it was. It also carries `bake_id` and
  `replay`, because a failure is as much a fact about a corpus as a result is: "no passage at
  this URN" is true of *this* bake and may be false of the next.

  The payload is JSON in the error body rather than bare text, so the same parse works
  whether a call succeeded or failed.
  """
  @spec error(String.t(), map(), atom(), String.t()) :: Response.t()
  def error(tool, arguments, reason, message)
      when is_binary(tool) and is_atom(reason) and is_binary(message) do
    Pramana.Telemetry.emit([:pramana, :mcp, :tool], %{calls: 1}, %{tool: tool, error: reason})

    %{
      error: %{reason: reason, message: message},
      bake_id: Pramana.Bake.current_id(),
      replay: %{tool: tool, arguments: normalize(arguments)}
    }
    |> Jason.encode!()
    |> then(&Response.error(Response.tool(), &1))
  end

  # Struct-free and atom-keyed, so the record round-trips through JSON as what was sent.
  # A nil-valued option is dropped rather than recorded: it was not part of the call, and a
  # replay that re-sends it would pin a default that is free to change.
  defp normalize(arguments) do
    arguments
    |> Map.new(fn {k, v} -> {to_string(k), v} end)
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end
end
