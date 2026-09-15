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

  ## It takes a small connection pool, and that is not a micro-optimisation

  `config/dev.exs` sets `pool_size: 25`, sized for `mix pramana.bake`'s concurrency, and
  every dev-env BEAM takes that whole pool. Postgres ships with `max_connections = 100`,
  so **four long-lived dev processes exhaust the server** — and this one is long-lived by
  design: an editor keeps it open for the whole session, and a second editor makes two.

  That is not a hypothetical. On 2026-09-02, two of these plus a forgotten `mix phx.server`
  starved `mix pramana.gate`, which reported `FAILED test` while every test passed and
  buried the real cause in 2,090 lines of `Oban.Notifiers.Postgres failed to connect`. A
  resource budget consumed by an idle process fails somewhere else, with a misleading name.

  **Nothing in the MCP request path fans out**: stdio serialises requests over one stream
  and every tool handler runs sequential `Repo` calls on the caller's process, so the
  server can use exactly one connection at a time. Four leaves headroom for Oban's
  notifier and Ecto's own internals. `mix phx.server` keeps the full pool, because an HTTP
  transport really does serve concurrent requests.
  """

  use Mix.Task

  # One connection for the request in flight, three for Oban's notifier and Ecto's
  # internals. See the moduledoc: the default is sized for the bake, and four of these
  # would exhaust a stock Postgres between them.
  @pool_size 4

  @impl Mix.Task
  def run(_argv) do
    Logger.configure(level: :warning)
    Application.put_env(:logger, :default_handler, false)

    # Before `app.start`, which is when the Repo reads its configuration.
    Pramana.Runtime.use_small_pool!(@pool_size)

    Mix.Task.run("app.start")

    {:ok, _pid} =
      Anubis.Server.Supervisor.start_link(PramanaWeb.MCP.Server, transport: :stdio)

    Process.sleep(:infinity)
  end
end
