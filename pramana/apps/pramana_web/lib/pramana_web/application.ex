defmodule PramanaWeb.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      PramanaWeb.Telemetry,
      {DynamicSupervisor,
       strategy: :one_for_one, name: PramanaWeb.CheckAdmission.PermitSupervisor},
      PramanaWeb.CheckAdmission,
      # Start a worker by calling: PramanaWeb.Worker.start_link(arg)
      # {PramanaWeb.Worker, arg},
      # Start to serve requests, typically the last entry
      PramanaWeb.Endpoint,
      {PramanaWeb.MCP.Server, transport: :streamable_http}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: PramanaWeb.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    PramanaWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
