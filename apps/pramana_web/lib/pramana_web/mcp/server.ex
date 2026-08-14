defmodule PramanaWeb.MCP.Server do
  @moduledoc """
  The MCP surface over the baked corpus.

  This is the decoupling boundary from `docs/ARCHITECTURE.md`: the model never touches
  the database, only these tools, and every tool returns URN-addressed structured data
  it can independently verify. Any model can drive it — swapping models changes
  nothing about the corpus.

  Served over Streamable HTTP at `/mcp` and over stdio via `mix pramana.mcp.stdio`.
  """

  use Anubis.Server,
    name: "pramana",
    version: "0.1.0",
    capabilities: [:tools]

  component(PramanaWeb.MCP.Tools.GetPassage)
  component(PramanaWeb.MCP.Tools.VerifyCitation)

  @impl true
  def init(_client_info, frame), do: {:ok, frame}
end
