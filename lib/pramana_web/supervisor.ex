defmodule PramanaWeb.Supervisor do
  @moduledoc false

  use Supervisor

  def start_link(_arg), do: Supervisor.start_link(__MODULE__, [], name: __MODULE__)

  @impl Supervisor
  def init(_arg) do
    permit_supervisor =
      Supervisor.child_spec(
        {DynamicSupervisor,
         strategy: :one_for_one, name: PramanaWeb.CheckAdmission.PermitSupervisor},
        id: PramanaWeb.CheckAdmission.PermitSupervisor,
        restart: :temporary
      )

    children = [
      PramanaWeb.Telemetry,
      permit_supervisor,
      PramanaWeb.CheckAdmission,
      # Start a worker by calling: PramanaWeb.Worker.start_link(arg)
      # {PramanaWeb.Worker, arg},
      # Start to serve requests, typically the last entry
      PramanaWeb.Endpoint,
      {PramanaWeb.MCP.Server, transport: :streamable_http}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
