defmodule Pramana.Runtime do
  @moduledoc """
  What a process declares about itself before the application starts.

  One function so far, and it lives here rather than on `Pramana.Repo` for a reason the
  build enforces: `mix pramana.mcp.stdio` needs it and lives in `apps/pramana_web`, which
  `Architecture.BoundariesTest` forbids from touching the repo at all. That boundary is
  right — the web app is transport and the domain app owns the data — and its allowlist is
  empty, which is worth keeping. So the web app calls a domain function, which is exactly
  what the test's failure message prescribes.
  """

  @doc """
  Shrinks this process's connection pool, before the application starts.

  `config/dev.exs` sets `pool_size: 25`, sized for `mix pramana.bake`'s concurrency, and
  **every dev BEAM takes that whole pool whether it can use it or not.** Postgres ships
  `max_connections = 100`, so four processes exhaust the server between them — and the
  failure never names the cause: `mix pramana.gate` reported `FAILED test` with every test
  passing, twice, once because two editor MCP servers were idle in another terminal and
  once because a stage of the gate ran seven steps at once.

  So a process that reads a few aggregates should say so. `mix pramana.docs.figures` runs
  nine counts and `mix pramana.mcp.stdio` serialises one request at a time over a single
  stream; neither can use 25 connections, and holding them is what makes the budget bite at
  four processes instead of twenty.

  **This is not lowering `pool_size`**, which `docs/DEV_ENV.md` says not to do and is right
  about: 25 is what makes the bake and the eval runs fast. It is one process declaring what
  it can actually use.

  Must be called **before** `Mix.Task.run("app.start")`, which is when the repo reads its
  configuration — afterwards it does nothing, silently, which is why callers do it as their
  first statement.
  """
  @spec use_small_pool!(pos_integer()) :: :ok
  def use_small_pool!(size) when is_integer(size) and size > 0 do
    config = Application.get_env(:pramana, Pramana.Repo, [])
    Application.put_env(:pramana, Pramana.Repo, Keyword.put(config, :pool_size, size))
  end
end
