defmodule Pramana.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias Pramana.Embed.Serving
  alias Pramana.Publishing.Guard

  @impl true
  def start(_type, _args) do
    # BEFORE the supervisor starts anything, so a job that fails during boot is still
    # reported. Attaching is idempotent.
    Pramana.Telemetry.attach()

    children =
      [
        Pramana.Repo,
        {Oban, Application.fetch_env!(:pramana, Oban)},
        {DNSCluster, query: Application.get_env(:pramana, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Pramana.PubSub},
        # Opt-in: loading BGE-M3 costs ~80s and 2.2 GB, which tests and migrations
        # must not pay. Absent, semantic retrieval degrades to lexical and says so.
        Serving.child_spec_if_enabled(),
        # AFTER the Repo, because it asks the database a question. Only present when this
        # node declares itself public, and then it stops the node rather than let one
        # wrong DATABASE_URL serve the research corpus to everyone.
        Guard.child_spec_if_public()
      ]
      |> Enum.reject(&is_nil/1)

    Supervisor.start_link(children, strategy: :one_for_one, name: Pramana.Supervisor)
  end
end
