defmodule Mix.Tasks.Pramana.Mcp.Stdio do
  @shortdoc "Runs the Pramāṇa MCP server over stdio"

  @moduledoc """
  Runs the MCP server over stdio, for local clients such as Claude Code.

      mix pramana.mcp.stdio

  The HTTP transport (`mix phx.server`, then `POST /mcp`) serves the same tools over
  the same corpus — stdio and Streamable HTTP are two transports over one
  implementation, not two implementations.

  Logging goes to a file, never stdout: on stdio, stdout *is* the protocol channel and
  a stray log line corrupts the stream.
  """

  use Mix.Task

  @impl Mix.Task
  def run(_argv) do
    Logger.configure(level: :warning)
    Application.put_env(:logger, :default_handler, false)

    Mix.Task.run("app.start")

    {:ok, _pid} =
      Anubis.Server.Supervisor.start_link(PramanaWeb.MCP.Server, transport: :stdio)

    Process.sleep(:infinity)
  end
end
