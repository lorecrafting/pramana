defmodule PramanaWeb.CheckAdmission do
  @moduledoc """
  Shared, node-local admission for report verification workers.

  Reader pages and MCP `verify_report` calls use the same finite capacity. A permit is
  acquired before a report worker is started and is released only after that invocation
  finishes its cleanup. Capacity refusal is an execution outcome, never an evidence
  verdict.

  The shared counter lives outside this GenServer in `:persistent_term`, so a supervised
  restart cannot reopen capacity while older admitted coordinators still hold permits.
  The server links to admitted coordinators so a server crash cancels their remaining
  work; permit release is idempotent and can complete against a restarted server.

  This bounds report workers on one BEAM node. It is not a distributed semaphore, an
  Anubis session-queue bound, or a guarantee that already-dispatched database/native work
  has been recalled.
  """

  use GenServer

  @default_max_active 4
  @max_configured_active 64

  defmodule Permit do
    @moduledoc false
    @enforce_keys [:counter, :lease]
    defstruct [:counter, :lease]
  end

  @type permit :: %Permit{}

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
  @spec acquire(GenServer.server()) :: {:ok, permit()} | {:error, :busy | :unavailable}
  def acquire(server \\ __MODULE__) do
    try do
      GenServer.call(server, {:acquire, self()})
    catch
      :exit, _ -> {:error, :unavailable}
    end
  end

  @doc "Release a permit. Safe to call more than once and after the admission server restarts."
  @spec release(GenServer.server(), permit()) :: :ok
  def release(server \\ __MODULE__, %Permit{} = permit) do
    release_counter(permit)

    try do
      GenServer.cast(server, {:released, self(), permit})
    catch
      :exit, _ -> :ok
    end

    :ok
  end

  @doc false
  @spec stats(GenServer.server()) :: %{active: non_neg_integer(), max_active: pos_integer()}
  def stats(server \\ __MODULE__), do: GenServer.call(server, :stats)

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    configured =
      Keyword.get_lazy(opts, :max_active, fn ->
        Application.get_env(:pramana_web, __MODULE__, [])
        |> Keyword.get(:max_active, @default_max_active)
      end)

    max_active = validate_max_active!(configured)
    name = Keyword.get(opts, :name, __MODULE__)
    counter_key = Keyword.get(opts, :counter_key, {__MODULE__, :counter, name})
    counter = persistent_counter(counter_key)

    {:ok, %{counter: counter, max_active: max_active, permits: %{}}}
  end

  @impl true
  def handle_call({:acquire, coordinator}, _from, state) when is_pid(coordinator) do
    cond do
      Map.has_key?(state.permits, coordinator) ->
        {:reply, {:error, :busy}, state}

      true ->
        case reserve(state.counter, state.max_active) do
          {:ok, permit} ->
            Process.link(coordinator)
            {:reply, {:ok, permit}, put_in(state.permits[coordinator], permit)}

          :busy ->
            {:reply, {:error, :busy}, state}
        end
    end
  end

  def handle_call(:stats, _from, state) do
    {:reply,
     %{active: :atomics.get(state.counter, 1), max_active: state.max_active}, state}
  end

  @impl true
  def handle_cast({:released, coordinator, permit}, state) do
    case state.permits do
      %{^coordinator => ^permit} ->
        Process.unlink(coordinator)
        {:noreply, %{state | permits: Map.delete(state.permits, coordinator)}}

      _ ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:EXIT, coordinator, _reason}, state) do
    case Map.pop(state.permits, coordinator) do
      {nil, _} ->
        {:noreply, state}

      {permit, permits} ->
        release_counter(permit)
        {:noreply, %{state | permits: permits}}
    end
  end

  defp validate_max_active!(value)
       when is_integer(value) and value > 0 and value <= @max_configured_active,
       do: value

  defp validate_max_active!(value) do
    raise ArgumentError,
          "report-check max_active must be an integer between 1 and #{@max_configured_active}, got: #{inspect(value)}"
  end

  defp persistent_counter(key) do
    case :persistent_term.get(key, :missing) do
      :missing ->
        counter = :atomics.new(1, signed: false)
        :persistent_term.put(key, counter)
        counter

      counter ->
        counter
    end
  end

  defp reserve(counter, max_active) do
    current = :atomics.get(counter, 1)

    cond do
      current >= max_active ->
        :busy

      :atomics.compare_exchange(counter, 1, current, current + 1) == :ok ->
        lease = :atomics.new(1, signed: false)
        :atomics.put(lease, 1, 1)
        {:ok, %Permit{counter: counter, lease: lease}}

      true ->
        reserve(counter, max_active)
    end
  end

  defp release_counter(%Permit{counter: counter, lease: lease}) do
    if :atomics.compare_exchange(lease, 1, 1, 0) == :ok do
      case :atomics.add_get(counter, 1, -1) do
        count when count >= 0 -> :ok
        _ -> raise "report-check admission counter underflow"
      end
    else
      :ok
    end
  end
end
