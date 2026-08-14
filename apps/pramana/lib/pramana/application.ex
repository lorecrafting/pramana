defmodule Pramana.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Pramana.Repo,
      {Oban, Application.fetch_env!(:pramana, Oban)},
      {DNSCluster, query: Application.get_env(:pramana, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Pramana.PubSub}
      # Start a worker by calling: Pramana.Worker.start_link(arg)
      # {Pramana.Worker, arg}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Pramana.Supervisor)
  end
end
