defmodule PramanaWeb.CheckAdmission do
  @moduledoc """
  Shared, node-local admission for report verification workers.

  Reader pages and MCP `verify_report` calls use the same finite capacity. Admission is
  represented by supervised permit processes rather than a raw counter: one live permit
  means one admitted report coordinator. A permit monitors its coordinator and disappears
  automatically if that coordinator dies, including an untrappable exit.

  The permit supervisor is a sibling of this GenServer. Restarting only the admission
  server therefore does not forget active work; the replacement server binds to and counts
  the same live permit children before admitting anything else. The admission server pins
  one permit-supervisor generation. If that supervisor dies, admission stays unavailable
  for the rest of this application lifetime rather than adopting a fresh zero-count pool
  while old workers are still stopping.

  This bounds report workers on one BEAM node. It is not a distributed semaphore, an
  Anubis session-queue bound, or a guarantee that already-dispatched database/native work
  has been recalled.
  """

  use GenServer

  @default_max_active 4
  @max_configured_active 64
  @default_permit_supervisor PramanaWeb.CheckAdmission.PermitSupervisor

  defmodule Permit do
    @moduledoc false
    use GenServer

    @activation_timeout_ms 5_000

    @doc false
    def child_spec({_owner, _issuer} = args) do
      %{
        id: __MODULE__,
        start: {__MODULE__, :start_link, [args]},
        restart: :temporary,
        shutdown: 1_000,
        type: :worker
      }
    end

    def start_link({owner, issuer}) when is_pid(owner) and is_pid(issuer) do
      GenServer.start_link(__MODULE__, {owner, issuer})
    end

    @doc false
    def activate(pid) when is_pid(pid) do
      GenServer.call(pid, :activate)
    catch
      :exit, _ -> {:error, :unavailable}
    end

    @impl true
    def init({owner, issuer}) do
      owner_ref = Process.monitor(owner)
      issuer_ref = Process.monitor(issuer)
      timer = Process.send_after(self(), :activation_expired, @activation_timeout_ms)

      {:ok,
       %{
         owner: owner,
         owner_ref: owner_ref,
         issuer: issuer,
         issuer_ref: issuer_ref,
         activation_timer: timer,
         activated?: false
       }}
    end

    @impl true
    def handle_call(:activate, _from, %{activated?: false} = state) do
      _ = Process.cancel_timer(state.activation_timer)
      Process.demonitor(state.issuer_ref, [:flush])

      {:reply, :ok, %{state | activated?: true, issuer_ref: nil, activation_timer: nil}}
    end

    def handle_call(:activate, _from, state), do: {:reply, :ok, state}

    @impl true
    def handle_info(
          {:DOWN, owner_ref, :process, owner, _reason},
          %{owner_ref: owner_ref, owner: owner} = state
        ),
        do: {:stop, :normal, state}

    def handle_info(
          {:DOWN, issuer_ref, :process, issuer, _reason},
          %{activated?: false, issuer_ref: issuer_ref, issuer: issuer} = state
        ),
        do: {:stop, :normal, state}

    def handle_info(:activation_expired, %{activated?: false} = state),
      do: {:stop, :normal, state}

    def handle_info(_message, state), do: {:noreply, state}
  end

  defmodule Token do
    @moduledoc false
    @enforce_keys [:pid, :permit_supervisor]
    defstruct [:pid, :permit_supervisor]
  end

  @type token :: %Token{}
  @type stats :: %{active: non_neg_integer(), max_active: pos_integer()}

  @doc false
  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :id, __MODULE__),
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5_000
    }
  end

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Acquire one node-local report-check permit for the calling coordinator."
  @spec acquire(GenServer.server()) :: {:ok, token()} | {:error, :busy | :unavailable}
  def acquire(server \\ __MODULE__) do
    case GenServer.call(server, {:acquire, self()}) do
      {:ok, %Token{} = token} -> activate(token)
      {:error, reason} when reason in [:busy, :unavailable] -> {:error, reason}
    end
  catch
    :exit, _ -> {:error, :unavailable}
  end

  @doc "Release a permit. Safe after its process already terminated."
  @spec release(token()) :: :ok
  def release(%Token{pid: pid, permit_supervisor: supervisor}) do
    case DynamicSupervisor.terminate_child(supervisor, pid) do
      :ok -> :ok
      {:error, _reason} -> :ok
    end
  catch
    :exit, _ -> :ok
  end

  @doc false
  @spec stats(GenServer.server()) :: stats() | {:error, :unavailable}
  def stats(server \\ __MODULE__), do: GenServer.call(server, :stats)

  @impl true
  def init(opts) do
    opts = Keyword.validate!(opts, [:id, :name, :max_active, :permit_supervisor])
    configured = Application.get_env(:pramana_web, __MODULE__, [])

    unless Keyword.keyword?(configured) do
      raise ArgumentError, "report-check admission configuration must be a keyword list"
    end

    configured = Keyword.validate!(configured, [:max_active])

    max_active =
      opts
      |> Keyword.get(:max_active, Keyword.get(configured, :max_active, @default_max_active))
      |> validate_max_active!()

    permit_supervisor = Keyword.get(opts, :permit_supervisor, @default_permit_supervisor)

    case resolve_server(permit_supervisor) do
      {:ok, permit_supervisor_pid} ->
        {:ok,
         %{
           max_active: max_active,
           permit_supervisor: permit_supervisor,
           permit_supervisor_pid: permit_supervisor_pid,
           permit_supervisor_ref: Process.monitor(permit_supervisor_pid),
           available?: true
         }}

      {:error, :unavailable} ->
        {:stop, :permit_supervisor_unavailable}
    end
  end

  @impl true
  def handle_call({:acquire, _coordinator}, _from, %{available?: false} = state) do
    {:reply, {:error, :unavailable}, state}
  end

  def handle_call({:acquire, coordinator}, _from, state) when is_pid(coordinator) do
    {:reply, start_permit(state, coordinator), state}
  end

  def handle_call(:stats, _from, %{available?: false} = state) do
    {:reply, {:error, :unavailable}, state}
  end

  def handle_call(:stats, _from, state) do
    case active_count(state.permit_supervisor_pid) do
      {:ok, active} ->
        {:reply, %{active: active, max_active: state.max_active}, state}

      {:error, :unavailable} ->
        {:reply, {:error, :unavailable}, %{state | available?: false}}
    end
  end

  @impl true
  def handle_info(
        {:DOWN, permit_supervisor_ref, :process, permit_supervisor_pid, _reason},
        %{
          permit_supervisor_ref: permit_supervisor_ref,
          permit_supervisor_pid: permit_supervisor_pid
        } = state
      ) do
    {:noreply, %{state | available?: false}}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp activate(%Token{} = token) do
    case Permit.activate(token.pid) do
      :ok ->
        {:ok, token}

      {:error, :unavailable} ->
        release(token)
        {:error, :unavailable}
    end
  end

  defp start_permit(state, coordinator) do
    with {:ok, active} <- active_count(state.permit_supervisor_pid),
         true <- active < state.max_active,
         {:ok, pid} <- start_permit_child(state.permit_supervisor_pid, coordinator) do
      {:ok, %Token{pid: pid, permit_supervisor: state.permit_supervisor_pid}}
    else
      false -> {:error, :busy}
      {:error, :unavailable} -> {:error, :unavailable}
    end
  end

  defp active_count(supervisor) do
    %{active: active} = DynamicSupervisor.count_children(supervisor)
    {:ok, active}
  catch
    :exit, _ -> {:error, :unavailable}
  end

  defp start_permit_child(supervisor, coordinator) do
    case DynamicSupervisor.start_child(supervisor, {Permit, {coordinator, self()}}) do
      {:ok, pid} -> {:ok, pid}
      {:ok, pid, _info} -> {:ok, pid}
      {:error, _reason} -> {:error, :unavailable}
    end
  catch
    :exit, _ -> {:error, :unavailable}
  end

  defp resolve_server(pid) when is_pid(pid) do
    if Process.alive?(pid), do: {:ok, pid}, else: {:error, :unavailable}
  end

  defp resolve_server(name) do
    case GenServer.whereis(name) do
      pid when is_pid(pid) -> {:ok, pid}
      _ -> {:error, :unavailable}
    end
  catch
    :exit, _ -> {:error, :unavailable}
  end

  defp validate_max_active!(value)
       when is_integer(value) and value > 0 and value <= @max_configured_active,
       do: value

  defp validate_max_active!(value) do
    raise ArgumentError,
          "report-check max_active must be an integer between 1 and #{@max_configured_active}, got: #{inspect(value)}"
  end
end
