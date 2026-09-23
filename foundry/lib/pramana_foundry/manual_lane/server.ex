defmodule PramanaFoundry.ManualLane.Server do
  @moduledoc """
  Starts and owns the manual lane's own `Gateway`, behind the `PRAMANA_MANUAL_LANE` flag
  (`docs/batch-d/THIN-LANE-DESIGN-2026-09-23.md` §5). The store lives at its own path and is
  disjoint from the legacy `state/current/{events,coordinator,telemetry}.jsonl` files:
  nothing here reads or writes them.

  On first start against a store with no root policy `"manual-lane"`, it seeds the policy,
  its control and its `starts.developer`/`starts.reviewer` ledgers from a JSON file at
  `:manual_lane, :policy_path` (Q3). The seed is refused when the policy's
  `independent_of_roles.reviewer` omits `"developer"`: a missing key would impose no
  independence at all. Seeding is otherwise a no-op once the policy exists, so a restart
  never re-seeds.

  The gateway's protected capability never leaves this process tree: `context/0` hands the
  gateway pid, capability and writer_epoch to modules in the same supervision tree (the
  backend, the CLI), never to a file or a wire.
  """
  use GenServer

  alias PramanaFoundry.DurableStore.Gateway
  alias PramanaFoundry.RuntimeRoot

  @policy_id "manual-lane"
  @control_id "manual-lane"
  @developer_ledger_id "manual-lane-developer"
  @reviewer_ledger_id "manual-lane-reviewer"

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "The gateway pid, capability, writer_epoch, repo and store_path. Same process tree only."
  def context, do: GenServer.call(__MODULE__, :context)

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    config = Keyword.merge(Application.get_env(:pramana_foundry, :manual_lane, []), opts)
    repo = Keyword.get(config, :repo)
    store_path = store_path(config)

    with :ok <- require_repo(repo),
         :ok <- ensure_store_initialized(store_path),
         capability <- make_ref(),
         writer_epoch <- fresh_epoch(),
         {:ok, gateway} <-
           Gateway.start_link(
             path: store_path,
             protected_capability: capability,
             writer_epoch: writer_epoch
           ),
         :ok <- seed(gateway, capability, Keyword.get(config, :policy_path)) do
      {:ok,
       %{
         gateway: gateway,
         capability: capability,
         writer_epoch: writer_epoch,
         repo: repo,
         store_path: store_path
       }}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call(:context, _from, state) do
    {:reply, Map.take(state, [:gateway, :capability, :writer_epoch, :repo, :store_path]), state}
  end

  @impl true
  def handle_info({:EXIT, pid, reason}, %{gateway: pid} = state), do: {:stop, reason, state}
  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %{gateway: gateway}) do
    if Process.alive?(gateway), do: GenServer.stop(gateway)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  defp require_repo(nil), do: {:error, :manual_lane_repo_missing}
  defp require_repo(_repo), do: :ok

  defp store_path(config) do
    Keyword.get(config, :store_path) ||
      Path.join(
        Keyword.get(config, :runtime_root) || RuntimeRoot.fetch!(),
        "state/manual-lane/authority.sqlite3"
      )
  end

  defp ensure_store_initialized(path) do
    if File.exists?(path) do
      :ok
    else
      File.mkdir_p!(Path.dirname(path))
      Gateway.initialize(path)
    end
  end

  defp fresh_epoch, do: 16 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

  # ── Seeding (Q3) ─────────────────────────────────────────────────────────────────────

  defp seed(gateway, capability, policy_path) do
    query = %{"schema_version" => 1, "type" => "policy", "policy_id" => @policy_id}

    case Gateway.protected_query(gateway, capability, query) do
      {:ok, _fact} -> :ok
      {:error, :policy_not_found} -> seed_from_file(gateway, capability, policy_path)
      {:error, reason} -> {:error, reason}
    end
  end

  defp seed_from_file(_gateway, _capability, nil),
    do: {:error, :manual_lane_policy_path_missing}

  defp seed_from_file(gateway, capability, policy_path) do
    with {:ok, contents} <- File.read(policy_path),
         seed <- :json.decode(contents),
         :ok <- validate_independence(seed) do
      apply_seed(gateway, capability, seed)
    end
  rescue
    error -> {:error, {:manual_lane_seed_invalid, error}}
  end

  defp validate_independence(seed) do
    reviewer_independent_of =
      seed
      |> Map.get("policy", %{})
      |> Map.get("independent_of_roles", %{})
      |> Map.get("reviewer", [])

    if is_list(reviewer_independent_of) and "developer" in reviewer_independent_of do
      :ok
    else
      {:error, :manual_lane_seed_independence_missing}
    end
  end

  defp apply_seed(gateway, capability, seed) do
    policy = seed |> Map.fetch!("policy") |> Map.put("check_set", [])
    control = Map.get(seed, "control", %{"status" => "active"})
    starts = Map.fetch!(seed, "starts")

    with {:ok, _} <-
           run_seed_op(gateway, capability, "manual-lane-seed-policy", %{
             "type" => "set_policy",
             "policy_id" => @policy_id,
             "value" => policy
           }),
         {:ok, _} <-
           run_seed_op(gateway, capability, "manual-lane-seed-control", %{
             "type" => "set_control",
             "control_id" => @control_id,
             "value" => control
           }),
         {:ok, _} <-
           run_seed_op(gateway, capability, "manual-lane-seed-ledger-developer", %{
             "type" => "grant_ledger",
             "ledger_id" => @developer_ledger_id,
             "generation" => 0,
             "dimension" => "starts.developer",
             "units" => Map.fetch!(starts, "developer")
           }),
         {:ok, _} <-
           run_seed_op(gateway, capability, "manual-lane-seed-ledger-reviewer", %{
             "type" => "grant_ledger",
             "ledger_id" => @reviewer_ledger_id,
             "generation" => 0,
             "dimension" => "starts.reviewer",
             "units" => Map.fetch!(starts, "reviewer")
           }) do
      :ok
    end
  end

  defp run_seed_op(gateway, capability, id, operation) do
    case send_command(gateway, capability, id <> "-probe", %{}, operation) do
      {:ok,
       %{"reason_code" => "incomplete_read_set", "facts" => %{"required_revisions" => reads}},
       :committed} ->
        gateway |> send_command(capability, id, reads, operation) |> normalize()

      other ->
        normalize(other)
    end
  end

  defp normalize({:ok, %{"disposition" => "accepted"} = result, :committed}), do: {:ok, result}

  defp normalize({:ok, result, _status}),
    do: {:error, {:manual_lane_seed_rejected, result}}

  defp normalize({:error, _reason} = error), do: error

  defp send_command(gateway, capability, id, reads, operation) do
    Gateway.protected_command(gateway, capability, "manual-lane-seed", %{
      "schema_version" => 1,
      "command_id" => id,
      "expected_revisions" => reads,
      "operation" => operation
    })
  end
end
