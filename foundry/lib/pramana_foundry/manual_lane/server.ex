defmodule PramanaFoundry.ManualLane.Server do
  @moduledoc """
  Starts and owns the manual lane's own `Gateway`, behind the `FOUNDRY_MANUAL_LANE` flag
  (`docs/batch-d/THIN-LANE-DESIGN-2026-09-23.md` §5). The store lives at its own path and is
  disjoint from the legacy `state/current/{events,coordinator,telemetry}.jsonl` files:
  nothing here reads or writes them.

  On first start against a store with no root policy `"manual-lane"`, it seeds the policy,
  its control and its `starts.developer`/`starts.reviewer` ledgers from a JSON file at
  `:manual_lane, :policy_path` or `FOUNDRY_MANUAL_LANE_POLICY` (Q3). The seed is refused when the policy's
  `independent_of_roles.reviewer` omits `"developer"`: a missing key would impose no
  independence at all. Each of the four is seeded only while it is missing, so a restart
  completes an interrupted seed and never re-seeds a present one.

  The gateway's protected capability never leaves this process tree: `context/0` hands the
  gateway pid, capability and writer_epoch to modules in the same supervision tree (the
  backend, the CLI), never to a file or a wire.
  """
  use GenServer

  alias PramanaFoundry.DurableStore.Gateway
  alias PramanaFoundry.ManualLane.Backend
  alias PramanaFoundry.RuntimeRoot

  require Logger

  # The Backend's ids, so the seed and the lane agree on what they name.
  @policy_id Backend.ids().policy_id
  @control_id Backend.ids().control_id
  @developer_ledger_id Backend.ids().ledgers["developer"]
  @reviewer_ledger_id Backend.ids().ledgers["reviewer"]
  @not_found [:not_found, :policy_not_found, :control_not_found, :ledger_not_found]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "The gateway pid, capability, writer_epoch, repo and store_path. Same process tree only."
  def context, do: GenServer.call(__MODULE__, :context)

  @doc """
  Restarts a Gateway left in recovery by an unclean stop, once, with `evidence`: the
  operator's attestation that no other lane process owns the store (A1). Core archives it
  with the old owner marker. It is never defaulted, generated or kept for a later restart.
  """
  def recover(evidence), do: GenServer.call(__MODULE__, {:recover, evidence})

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    config =
      :pramana_foundry
      |> Application.get_env(:manual_lane, [])
      |> Keyword.merge(env_config())
      |> Keyword.merge(opts)

    case open(config, nil) do
      {:ok, state} -> {:ok, state}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call(:context, _from, state) do
    {:reply, Map.take(state, [:gateway, :capability, :writer_epoch, :repo, :store_path]), state}
  end

  def handle_call({:recover, evidence}, _from, state) do
    cond do
      not (is_binary(evidence) and String.trim(evidence) != "") ->
        {:reply, {:error, :recovery_evidence_required}, state}

      Gateway.status(state.gateway).mode != :recovery ->
        {:reply, {:error, :lane_not_in_recovery}, state}

      true ->
        # Its `:EXIT` arrives after `state.gateway` names the new Gateway, so it is ignored.
        GenServer.stop(state.gateway)

        case open(state.config, "operator_attestation: " <> evidence) do
          {:ok, next} ->
            status = Gateway.status(next.gateway)
            if status.mode == :ready, do: Logger.info("manual lane left recovery")
            {:reply, {:ok, status}, next}

          {:error, reason} ->
            {:stop, reason, {:error, reason}, Map.delete(state, :gateway)}
        end
    end
  end

  # A Gateway in recovery (an unclean previous owner, say) is kept, unseeded, so every lane
  # command reports it instead of the Server crash-looping.
  defp open(config, evidence) do
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
             writer_epoch: writer_epoch,
             recovery_evidence: evidence
           ),
         :ok <- seed_unless_recovering(gateway, capability, Keyword.get(config, :policy_path)) do
      {:ok,
       %{
         gateway: gateway,
         capability: capability,
         writer_epoch: writer_epoch,
         repo: repo,
         store_path: store_path,
         config: config
       }}
    end
  end

  defp seed_unless_recovering(gateway, capability, policy_path) do
    case Gateway.status(gateway) do
      %{mode: :recovery, reason: reason} ->
        Logger.warning("manual lane entered recovery: #{inspect(reason)}",
          lane_recovery_reason: inspect(reason)
        )

        :ok

      _ready ->
        seed(gateway, capability, policy_path)
    end
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

  # A release has no config/runtime.exs, so the launcher (`bin/foundry-lane`) sets these at
  # start. They override compile-time config; an empty variable counts as unset.
  @env_vars [
    repo: "FOUNDRY_MANUAL_LANE_REPO",
    policy_path: "FOUNDRY_MANUAL_LANE_POLICY",
    store_path: "FOUNDRY_MANUAL_LANE_STORE"
  ]

  defp env_config do
    for {key, var} <- @env_vars,
        value <- [System.get_env(var)],
        value not in [nil, ""],
        do: {key, value}
  end

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

  @seed_queries [
    policy: %{"type" => "policy", "policy_id" => @policy_id},
    control: %{"type" => "control", "control_id" => @control_id},
    developer: %{"type" => "ledger", "ledger_id" => @developer_ledger_id, "generation" => 0},
    reviewer: %{"type" => "ledger", "ledger_id" => @reviewer_ledger_id, "generation" => 0}
  ]

  # Each seed op runs while its object is missing, so a seed interrupted between ops is
  # completed by the next start (review A3). A fully seeded store never reads the file.
  defp seed(gateway, capability, policy_path) do
    missing =
      Enum.reduce_while(@seed_queries, {:ok, []}, fn {name, query}, {:ok, acc} ->
        case Gateway.protected_query(gateway, capability, Map.put(query, "schema_version", 1)) do
          {:ok, _fact} -> {:cont, {:ok, acc}}
          {:error, reason} when reason in @not_found -> {:cont, {:ok, acc ++ [name]}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    case missing do
      {:ok, []} -> :ok
      {:ok, names} -> seed_from_file(gateway, capability, policy_path, names)
      error -> error
    end
  end

  defp seed_from_file(_gateway, _capability, nil, _names),
    do: {:error, :manual_lane_policy_path_missing}

  defp seed_from_file(gateway, capability, policy_path, names) do
    with {:ok, contents} <- File.read(policy_path),
         seed <- :json.decode(contents),
         :ok <- validate_independence(seed) do
      apply_seed(gateway, capability, seed, names)
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

  # `allowed_profiles` is pinned: unset, Core allows whatever profile a request names (A2).
  defp apply_seed(gateway, capability, seed, names) do
    policy =
      seed
      |> Map.fetch!("policy")
      |> Map.merge(%{"check_set" => [], "allowed_profiles" => ["unspecified"]})

    control = Map.get(seed, "control", %{"status" => "active"})
    starts = Map.fetch!(seed, "starts")

    ops = [
      policy:
        {"manual-lane-seed-policy",
         %{"type" => "set_policy", "policy_id" => @policy_id, "value" => policy}},
      control:
        {"manual-lane-seed-control",
         %{"type" => "set_control", "control_id" => @control_id, "value" => control}},
      developer:
        {"manual-lane-seed-ledger-developer",
         %{
           "type" => "grant_ledger",
           "ledger_id" => @developer_ledger_id,
           "generation" => 0,
           "dimension" => "starts.developer",
           "units" => Map.fetch!(starts, "developer")
         }},
      reviewer:
        {"manual-lane-seed-ledger-reviewer",
         %{
           "type" => "grant_ledger",
           "ledger_id" => @reviewer_ledger_id,
           "generation" => 0,
           "dimension" => "starts.reviewer",
           "units" => Map.fetch!(starts, "reviewer")
         }}
    ]

    Enum.reduce_while(Keyword.take(ops, names), :ok, fn {_name, {id, operation}}, :ok ->
      case run_seed_op(gateway, capability, id, operation) do
        {:ok, _} -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
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

  # A replayed accepted op is as good as a fresh one (A3).
  defp normalize({:ok, %{"disposition" => "accepted"} = result, status})
       when status in [:committed, :idempotent],
       do: {:ok, result}

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
