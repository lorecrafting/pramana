defmodule Pramana.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias Pramana.Embed.Serving
  alias Pramana.Publishing.Guard
  alias Pramana.Runtime

  @impl true
  def start(_type, _args) do
    if Runtime.reviewer?() and Guard.public?(),
      do: raise("PRAMANA_REVIEWER and PRAMANA_PUBLIC cannot both be enabled")

    # BEFORE the supervisor starts anything, so a job that fails during boot is still
    # reported. Attaching is idempotent.
    Pramana.Telemetry.attach()

    children =
      [
        Pramana.Repo,
        # Synchronous admission after database startup, before jobs, model loading
        # or the web supervisor. Failure unwinds already-started children.
        Guard.child_spec_if_public(),
        background_jobs(),
        {DNSCluster, query: Application.get_env(:pramana, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Pramana.PubSub},
        # Opt-in: loading BGE-M3 costs ~80s and 2.2 GB, which tests and migrations
        # must not pay. Absent, semantic retrieval degrades to lexical and says so.
        unless(Runtime.reviewer?(), do: Serving.child_spec_if_enabled()),
        PramanaWeb.Supervisor
      ]
      |> Enum.reject(&is_nil/1)

    Supervisor.start_link(children, strategy: :one_for_one, name: Pramana.Supervisor)
  end

  @impl true
  def config_change(changed, _new, removed) do
    PramanaWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  # Public serving must not consume queued bakes, prune history or elect an Oban
  # database peer. Disabling queues alone leaves other writers running. The package
  # remains available to administrative processes; only this instance is omitted.
  defp background_jobs do
    unless Guard.public?() or Runtime.reviewer?(),
      do: {Oban, Application.fetch_env!(:pramana, Oban)}
  end
end
