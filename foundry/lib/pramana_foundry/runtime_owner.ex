defmodule PramanaFoundry.RuntimeOwner do
  @moduledoc """
  Owns the fenced effect topology.

  The lease is the first child of a `:rest_for_one` supervisor and all effectful
  children follow it. Reverse shutdown therefore drains effects (including checked
  cleanup receipts) while the lease remains responsive, then releases the fence.
  Abnormal lease loss stops every later effect before restart is attempted; the
  durable unclean marker makes that restart and automatic takeover fail closed.
  """

  use Supervisor

  alias PramanaFoundry.RuntimeLease

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @spec owned?(Supervisor.supervisor()) :: boolean()
  def owned?(_owner \\ __MODULE__), do: RuntimeLease.owned?()

  @doc false
  def bridge_port(_owner \\ __MODULE__), do: RuntimeLease.bridge_port()

  @impl true
  def init(opts) do
    runtime_root = Keyword.fetch!(opts, :runtime_root)
    effects = Keyword.get(opts, :children, [])
    lease_name = Keyword.get(opts, :lease_name, RuntimeLease)

    children =
      [
        {RuntimeLease,
         runtime_root: runtime_root,
         name: lease_name,
         owner_name: Keyword.get(opts, :name, __MODULE__)}
      ] ++ effects

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
