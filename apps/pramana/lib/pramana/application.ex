defmodule Pramana.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias Pramana.Embed.Serving

  @impl true
  def start(_type, _args) do
    children =
      [
        Pramana.Repo,
        {Oban, Application.fetch_env!(:pramana, Oban)},
        {DNSCluster, query: Application.get_env(:pramana, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Pramana.PubSub},
        # Opt-in: loading BGE-M3 costs ~80s and 2.2 GB, which tests and migrations
        # must not pay. Absent, semantic retrieval degrades to lexical and says so.
        Serving.child_spec_if_enabled()
      ]
      |> Enum.reject(&is_nil/1)

    Supervisor.start_link(children, strategy: :one_for_one, name: Pramana.Supervisor)
  end
end
