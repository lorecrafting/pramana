defmodule PramanaFoundry.DurableStore.Gateway do
  @moduledoc """
  Protected, single-connection authority gateway.

  The caller supplies only semantic command data and a validated kernel proposal. SQL,
  the connection and protected table layout never cross this process boundary.
  """

  use GenServer

  @capacity_probe_timeout_ms 5_000

  alias PramanaFoundry.DurableStore.{
    Authority,
    Capacity,
    Database,
    Encoding,
    Kernel,
    Owner,
    PathIdentity,
    ProtectedPrimitives,
    ProtectedVerifier,
    RecordCodec,
    TransitionPlan
  }

  def initialize(path, opts \\ []) do
    case PathIdentity.new(path) do
      {:ok, identity} ->
        with :ok <- PathIdentity.validate_new_database(identity),
             {:ok, owner} <- Owner.acquire(identity, opts) do
          try do
            with :ok <- Database.initialize_owned(owner, opts),
                 {:ok, _created} <- PathIdentity.existing(owner.identity.path) do
              :ok
            end
          after
            Owner.release(owner)
          end
        end

      {:error, :target_exists} ->
        {:error, :already_initialized}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def migrate(path, opts \\ []) do
    with {:ok, identity} <- PathIdentity.existing(path),
         {:ok, owner} <- Owner.acquire(identity, opts) do
      try do
        with :ok <- PathIdentity.revalidate(owner.identity),
             :ok <- Database.migrate_protected_owned(owner),
             {:ok, conn} <- Database.open(owner.identity),
             :ok <- PathIdentity.revalidate(owner.identity) do
          result = Database.record_v1_migration(conn)
          close_result = Database.close(conn)

          with {:ok, :ok} <- result, :ok <- close_result, do: :ok
        end
      after
        Owner.release(owner)
      end
    end
  end

  def start_link(opts) do
    {gen_opts, init_opts} = Keyword.split(opts, [:name])
    GenServer.start_link(__MODULE__, init_opts, gen_opts)
  end

  def status(server), do: GenServer.call(server, :status)

  def transact(server, actor_id, command, proposal),
    do: GenServer.call(server, {:transact, actor_id, command, proposal})

  @doc false
  def transact_verified(server, capability, actor_id, command, proposal, protected_facts),
    do:
      GenServer.call(
        server,
        {:transact_verified, capability, actor_id, command, proposal, protected_facts}
      )

  def command(server, command_id), do: GenServer.call(server, {:command, command_id})

  @doc "Executes one capability-authenticated protected semantic command."
  def protected_command(server, capability, actor_id, request),
    do: GenServer.call(server, {:protected_command, capability, actor_id, request})

  @doc "Atomically commits an ordered protected-operation and domain-proposal bundle."
  def atomic_bundle(server, capability, actor_id, envelope),
    do: GenServer.call(server, {:atomic_bundle, capability, actor_id, envelope})

  @doc "Reads a bounded root-derived protected fact without exposing SQL or table names."
  def protected_query(server, capability, query),
    do: GenServer.call(server, {:protected_query, capability, query})

  @doc "Returns bounded store identity, sequence frontiers and typed root pointer slots."
  def protected_snapshot(server, capability),
    do: GenServer.call(server, {:protected_snapshot, capability})

  def counts(server), do: GenServer.call(server, :counts)
  def backup(server, path), do: GenServer.call(server, {:backup, path}, :infinity)
  def operational_health(server), do: GenServer.call(server, :operational_health, :infinity)

  def recent_events(server, limit) when is_integer(limit),
    do: GenServer.call(server, {:recent_events, limit})

  def recent_events(_server, _limit),
    do: {:error, {:invalid_limit, %{minimum: 1, maximum: 1_000}}}

  def checkpoint(server), do: GenServer.call(server, :checkpoint, :infinity)

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    path = Keyword.fetch!(opts, :path)

    case PathIdentity.existing(path) do
      {:error, :database_not_found} ->
        {:ok, recovery_state(path, :not_initialized)}

      {:ok, identity} ->
        open(identity, opts)

      {:error, reason} ->
        {:ok, recovery_state(path, reason)}
    end
  end

  @impl true
  def terminate(_reason, state) do
    Enum.each(state.operational_health_requests, fn {token, request} ->
      send(request.pid, {:cancel_capacity_probe, token})
    end)

    _ = Database.close(state.conn)
    if state.owner, do: Owner.release(state.owner)
    :ok
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, %{mode: state.mode, reason: state.reason, path: state.path}, state}
  end

  def handle_call(:operational_health, _from, %{mode: :recovery} = state) do
    {:reply,
     {:error,
      {:recovery_mode, state.reason,
       %{capacity: %{status: :unknown}, last_durable_sequence: :unknown}}}, state}
  end

  def handle_call(:operational_health, from, state) do
    case read_operational_health(state) do
      {:ok, health} ->
        owner = self()
        token = make_ref()

        {pid, monitor} =
          spawn_monitor(fn ->
            capacity_probe_controller(
              owner,
              token,
              state.capacity_probe,
              state.path,
              state.capacity_probe_timeout_ms
            )
          end)

        request = %{
          from: from,
          health: health,
          pid: pid,
          monitor: monitor,
          caller_monitor: Process.monitor(elem(from, 0))
        }

        {:noreply, put_in(state.operational_health_requests[token], request)}

      {:error, _reason} = result ->
        {:reply, result, transition_after_result(state, result)}
    end
  end

  def handle_call({:recent_events, _limit}, _from, %{mode: :recovery} = state) do
    {:reply, {:error, {:recovery_mode, state.reason}}, state}
  end

  def handle_call({:recent_events, limit}, _from, state) do
    result = query_recent_events(state.conn, limit)
    {:reply, result, transition_after_result(state, result)}
  end

  def handle_call(:checkpoint, _from, %{mode: :recovery} = state) do
    {:reply, {:error, {:recovery_mode, state.reason}}, state}
  end

  def handle_call(:checkpoint, _from, state) do
    result = checkpoint_database(state.conn, state.maintenance_fault)
    {:reply, result, transition_after_result(state, result)}
  end

  def handle_call({:transact, _actor_id, _command, _proposal}, _from, %{mode: :recovery} = state) do
    {:reply, {:error, {:recovery_mode, state.reason}}, state}
  end

  def handle_call({:transact, actor_id, command, proposal}, _from, state) do
    result = do_transact(state.conn, actor_id, command, proposal, %{}, state.fault)

    next_state = transition_after_result(state, result)

    {:reply, result, next_state}
  end

  def handle_call(
        {:transact_verified, _capability, _actor_id, _command, _proposal, _facts},
        _from,
        %{mode: :recovery} = state
      ) do
    {:reply, {:error, {:recovery_mode, state.reason}}, state}
  end

  def handle_call(
        {:transact_verified, capability, actor_id, command, proposal, facts},
        _from,
        state
      ) do
    result =
      with true <- capability === state.protected_capability do
        case ProtectedPrimitives.authority_mode(state.conn) do
          {:ok, :root} ->
            {:error, :legacy_protected_route_retired}

          {:ok, _legacy_mode} ->
            do_verified_transact(state.conn, actor_id, command, proposal, facts, state.fault)

          {:error, _reason} = error ->
            error
        end
      else
        false -> {:error, :unauthorized_protected_operation}
      end

    next_state = transition_after_result(state, result)

    {:reply, result, next_state}
  end

  def handle_call({:command, _command_id}, _from, %{mode: :recovery} = state) do
    {:reply, {:error, {:recovery_mode, state.reason}}, state}
  end

  def handle_call({:command, command_id}, _from, state) do
    result = fetch_command(state.conn, command_id)
    next = transition_after_result(state, result)
    reply = if next.mode == :recovery, do: {:error, {:recovery_mode, next.reason}}, else: result
    {:reply, reply, next}
  end

  def handle_call(
        {:protected_command, _capability, _actor_id, _request},
        _from,
        %{mode: :recovery} = state
      ) do
    {:reply, {:error, {:recovery_mode, state.reason}}, state}
  end

  def handle_call({:protected_command, capability, actor_id, request}, _from, state) do
    result =
      if capability === state.protected_capability do
        case ProtectedPrimitives.authority_mode(state.conn) do
          {:ok, :legacy} ->
            {:error, :legacy_authority_mode_active}

          {:ok, _mode} ->
            ProtectedPrimitives.execute(
              state.conn,
              actor_id,
              request,
              state.writer_epoch,
              state.fault
            )

          {:error, _reason} = error ->
            error
        end
      else
        {:error, :unauthorized_protected_operation}
      end

    {:reply, result, transition_after_result(state, result)}
  end

  def handle_call(
        {:atomic_bundle, _capability, _actor_id, _envelope},
        _from,
        %{mode: :recovery} = state
      ) do
    {:reply, {:error, {:recovery_mode, state.reason}}, state}
  end

  def handle_call({:atomic_bundle, capability, actor_id, envelope}, _from, state) do
    result =
      if capability === state.protected_capability do
        case ProtectedPrimitives.authority_mode(state.conn) do
          {:ok, :legacy} ->
            {:error, :legacy_authority_mode_active}

          {:ok, _mode} ->
            do_atomic_bundle(
              state.conn,
              actor_id,
              envelope,
              state.writer_epoch,
              state.fault
            )

          {:error, _reason} = error ->
            error
        end
      else
        {:error, :unauthorized_protected_operation}
      end

    {:reply, result, transition_after_result(state, result)}
  end

  def handle_call(
        {:protected_query, _capability, _query},
        _from,
        %{mode: :recovery} = state
      ) do
    {:reply, {:error, {:recovery_mode, state.reason}}, state}
  end

  def handle_call({:protected_query, capability, query}, _from, state) do
    result =
      if capability === state.protected_capability do
        ProtectedPrimitives.query(state.conn, query)
      else
        {:error, :unauthorized_protected_operation}
      end

    {:reply, result, transition_after_result(state, result)}
  end

  def handle_call(
        {:protected_snapshot, _capability},
        _from,
        %{mode: :recovery} = state
      ) do
    {:reply, {:error, {:recovery_mode, state.reason}}, state}
  end

  def handle_call({:protected_snapshot, capability}, _from, state) do
    result =
      if capability === state.protected_capability do
        ProtectedPrimitives.snapshot(state.conn, state.writer_epoch)
      else
        {:error, :unauthorized_protected_operation}
      end

    {:reply, result, transition_after_result(state, result)}
  end

  def handle_call(:counts, _from, %{mode: :recovery} = state) do
    {:reply, {:error, {:recovery_mode, state.reason}}, state}
  end

  def handle_call(:counts, _from, state) do
    tables =
      ~w(inputs commands command_results events projections effects claims ledger_generations reservations)

    result =
      with {:ok, %{content: content}} <- Authority.read(state.conn, :all) do
        {:ok, Map.new(tables, &{&1, content[&1].count})}
      end

    {:reply, result, transition_after_result(state, result)}
  end

  def handle_call({:backup, _path}, _from, %{mode: :recovery} = state) do
    {:reply, {:error, {:recovery_mode, state.reason}}, state}
  end

  def handle_call({:backup, path}, _from, state) do
    result = backup_database(state.conn, path, state.maintenance_fault)
    {:reply, result, transition_after_result(state, result)}
  end

  @impl true
  def handle_info({:operational_health_capacity, token, result}, state) do
    case Map.pop(state.operational_health_requests, token) do
      {nil, _requests} ->
        {:noreply, state}

      {request, requests} ->
        Process.demonitor(request.monitor, [:flush])
        Process.demonitor(request.caller_monitor, [:flush])
        physical = normalize_capacity_result(result)
        GenServer.reply(request.from, {:ok, add_physical_capacity(request.health, physical)})
        {:noreply, %{state | operational_health_requests: requests}}
    end
  end

  def handle_info({:operational_health_capacity_timeout, token}, state) do
    case Map.pop(state.operational_health_requests, token) do
      {nil, _requests} ->
        {:noreply, state}

      {request, requests} ->
        Process.demonitor(request.monitor, [:flush])
        Process.demonitor(request.caller_monitor, [:flush])

        GenServer.reply(
          request.from,
          {:ok, add_physical_capacity(request.health, {:unknown, :capacity_probe_timeout})}
        )

        {:noreply, %{state | operational_health_requests: requests}}
    end
  end

  def handle_info({:DOWN, monitor, :process, pid, reason}, state) do
    case find_health_request(state.operational_health_requests, monitor, pid) do
      nil ->
        {:noreply, state}

      {token, request, :worker} ->
        Process.demonitor(request.caller_monitor, [:flush])

        physical = {:unknown, {:capacity_probe_worker_exit, reason}}
        GenServer.reply(request.from, {:ok, add_physical_capacity(request.health, physical)})
        {:noreply, update_in(state.operational_health_requests, &Map.delete(&1, token))}

      {token, request, :caller} ->
        send(request.pid, {:cancel_capacity_probe, token})
        Process.demonitor(request.monitor, [:flush])
        {:noreply, update_in(state.operational_health_requests, &Map.delete(&1, token))}
    end
  end

  defp find_health_request(requests, monitor, pid) do
    Enum.find_value(requests, fn {token, request} ->
      cond do
        request.monitor == monitor and request.pid == pid -> {token, request, :worker}
        request.caller_monitor == monitor -> {token, request, :caller}
        true -> nil
      end
    end)
  end

  defp open(identity, opts) do
    path = identity.path

    with {:ok, owner} <- Owner.acquire(identity, opts) do
      open_result =
        with :ok <- PathIdentity.revalidate(owner.identity),
             {:ok, conn} <- Database.open(owner.identity),
             :ok <- PathIdentity.revalidate(owner.identity) do
          {:ok, conn}
        end

      case open_result do
        {:ok, conn} ->
          with :ok <- maybe_limit_pages(conn, Keyword.get(opts, :max_page_count)) do
            {:ok,
             %{
               path: path,
               conn: conn,
               owner: owner,
               mode: :ready,
               reason: nil,
               fault: Keyword.get(opts, :fault),
               maintenance_fault: Keyword.get(opts, :maintenance_fault),
               capacity_probe: Keyword.get(opts, :capacity_probe, &Capacity.probe/1),
               capacity_probe_timeout_ms:
                 Keyword.get(opts, :capacity_probe_timeout_ms, @capacity_probe_timeout_ms),
               operational_health_requests: %{},
               protected_capability:
                 Keyword.get_lazy(opts, :protected_capability, fn -> make_ref() end),
               writer_epoch:
                 Keyword.get_lazy(opts, :writer_epoch, fn ->
                   16 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
                 end)
             }}
          else
            {:error, reason} ->
              Database.close(conn)
              Owner.release(owner)

              {:ok, recovery_state(path, reason)}
          end

        {:error, reason} ->
          Owner.release(owner)

          {:ok, recovery_state(path, reason)}
      end
    else
      {:error, reason} ->
        {:ok, recovery_state(path, reason)}
    end
  end

  defp do_transact(conn, actor_id, command, proposal, protected, fault) do
    with {:ok, canonical, digest, normalized_command} <- prepare_command(actor_id, command) do
      command_id = normalized_command["command_id"]

      case existing(conn, command_id, actor_id, digest) do
        {:ok, result} ->
          {:ok, result, :idempotent}

        {:error, :not_found} ->
          case normalize_candidate(proposal) do
            {:ok, normalized} ->
              commit_bundle(
                conn,
                actor_id,
                normalized_command,
                canonical,
                digest,
                normalized,
                protected,
                fault
              )

            {:error, reason} ->
              {:error, reason}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp do_verified_transact(conn, actor_id, command, proposal, facts, fault) do
    with {:ok, canonical, digest, normalized_command} <- prepare_command(actor_id, command) do
      command_id = normalized_command["command_id"]

      case existing(conn, command_id, actor_id, digest) do
        {:ok, result} ->
          {:ok, result, :idempotent}

        {:error, :not_found} ->
          with {:ok, normalized} <- normalize_candidate(proposal),
               {:ok, protected} <-
                 ProtectedVerifier.derive(normalized_command, normalized, facts) do
            commit_bundle(
              conn,
              actor_id,
              normalized_command,
              canonical,
              digest,
              normalized,
              protected,
              fault
            )
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp do_atomic_bundle(conn, actor_id, envelope, writer_epoch, fault) do
    with {:ok, normalized, canonical, digest} <- normalize_atomic_envelope(actor_id, envelope) do
      command_id = normalized["command"]["command_id"]

      case existing_atomic_bundle(conn, command_id, actor_id, digest) do
        {:ok, result} ->
          {:ok, result, :idempotent}

        {:error, :not_found} ->
          commit_atomic_bundle(conn, normalized, canonical, digest, writer_epoch, fault)

        {:error, _reason} = error ->
          error
      end
    end
  end

  defp normalize_atomic_envelope(actor_id, envelope) do
    with :ok <- validate_actor(actor_id),
         {:ok, normalized_input} <- canonical_value(envelope),
         {:ok, carrier} <- atomic_carrier(normalized_input),
         2 <- normalized_input["schema_version"],
         ^actor_id <- normalized_input["actor_id"],
         true <- plain_map?(normalized_input["inputs"]),
         {:ok, command} <- RecordCodec.normalize(:command, normalized_input["command"]),
         {:ok, operations} <- normalize_atomic_operations(normalized_input["operations"]),
         {:ok, carried} <-
           normalize_atomic_carrier(carrier, normalized_input[carrier], operations),
         normalized <- %{
           "schema_version" => 2,
           "actor_id" => actor_id,
           "inputs" => normalized_input["inputs"],
           "command" => command,
           "operations" => operations,
           carrier => carried
         },
         {:ok, canonical} <- Encoding.canonical(normalized),
         {:ok, digest} <-
           Encoding.semantic_digest("pramana-foundry-atomic-bundle-v2", normalized) do
      {:ok, normalized, canonical, digest}
    else
      {:error, _reason} = error -> error
      _ -> {:error, :invalid_atomic_bundle}
    end
  end

  defp normalize_atomic_operations(operations) when is_list(operations) do
    operations
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {entry, ordinal}, {:ok, acc} ->
      with true <- plain_map?(entry),
           true <-
             Map.keys(entry) |> Enum.sort() == ~w(expected_revisions operation schema_version),
           1 <- entry["schema_version"],
           true <- plain_map?(entry["expected_revisions"]),
           true <- plain_map?(entry["operation"]),
           type when is_binary(type) <- entry["operation"]["type"],
           true <- ProtectedPrimitives.supported_operation_type?(type) do
        normalized =
          entry
          |> Map.put("ordinal", ordinal)
          |> Map.put("operation_type", type)

        {:cont, {:ok, [normalized | acc]}}
      else
        _ -> {:halt, {:error, :invalid_atomic_operation}}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end

  defp normalize_atomic_operations(_operations), do: {:error, :invalid_atomic_operations}

  defp existing_atomic_bundle(conn, command_id, actor_id, digest) do
    with {:ok, rows} <-
           Database.query(
             conn,
             "SELECT actor_id, request_digest, result FROM atomic_bundles WHERE command_id = ?",
             [command_id]
           ) do
      case rows do
        [[^actor_id, ^digest, bytes]] ->
          decode_json_map(bytes)

        [[_actor, _digest, _bytes]] ->
          {:error, :idempotency_conflict}

        [] ->
          with {:ok, [[domain_count]]} <-
                 Database.query(conn, "SELECT count(*) FROM commands WHERE command_id = ?", [
                   command_id
                 ]),
               {:ok, [[root_count]]} <-
                 Database.query(conn, "SELECT count(*) FROM root_commands WHERE command_id = ?", [
                   command_id
                 ]) do
            if domain_count == 0 and root_count == 0,
              do: {:error, :not_found},
              else: {:error, :idempotency_conflict}
          end

        _ ->
          {:error, :duplicate_atomic_command}
      end
    end
  end

  defp commit_atomic_bundle(conn, envelope, canonical, digest, writer_epoch, fault) do
    result =
      Database.transaction(conn, fn ->
        with :ok <- validate_atomic_prestate(conn, envelope["operations"]),
             {:ok, staged} <- stage_atomic_operations(conn, envelope, digest, writer_epoch),
             :ok <- inject(fault, :after_protected) do
          case staged do
            {:quarantined, operation_results, reason} ->
              commit_quarantined_atomic_bundle(
                conn,
                envelope,
                canonical,
                digest,
                operation_results,
                reason,
                fault
              )

            {:accepted, operation_results} ->
              commit_accepted_atomic_bundle(
                conn,
                envelope,
                canonical,
                digest,
                operation_results,
                fault
              )
          end
        else
          {:error, reason} when reason in [:incomplete_read_set, :stale_read_set] ->
            {:error,
             {:atomic_rejection, reason, unexecuted_operation_results(envelope, digest, reason)}}

          {:error, _reason} = error ->
            error
        end
      end)

    case result do
      {:ok, {:accepted, durable}} ->
        atomic_reply(envelope, durable, :committed, fault)

      {:ok, {:quarantined, durable}} ->
        atomic_reply(envelope, durable, :quarantined, fault)

      {:error, {:atomic_rejection, reason, operation_results}} ->
        persist_atomic_rejection(
          conn,
          envelope,
          canonical,
          digest,
          reason,
          operation_results,
          fault
        )

      {:error, reason} ->
        {:error, {:storage_unavailable, reason}}
    end
  end

  defp stage_atomic_operations(conn, envelope, digest, writer_epoch) do
    operations = envelope["operations"]

    operations
    |> Enum.reduce_while({:ok, []}, fn entry, {:ok, acc} ->
      ordinal = entry["ordinal"]

      with {:ok, staged_reads} <- ProtectedPrimitives.required_revisions(conn, entry["operation"]) do
        request = %{
          "schema_version" => 1,
          "command_id" => atomic_operation_id(digest, ordinal),
          "expected_revisions" => staged_reads,
          "operation" => entry["operation"]
        }

        case ProtectedPrimitives.execute_in_transaction(
               conn,
               envelope["actor_id"],
               request,
               writer_epoch
             ) do
          {:ok, result, status} when status in [:accepted, :idempotent] ->
            with true <- result["disposition"] == "accepted",
                 {:ok, result, settlement_status} <-
                   maybe_persist_nonstart(conn, entry["operation"], result) do
              item = atomic_operation_result(entry, request, result, "committed")

              if settlement_status == :duplicate do
                rejected =
                  duplicate_operation_results(envelope, digest, item, acc)

                {:halt, {:error, {:atomic_rejection, :duplicate_receipt, rejected}}}
              else
                {:cont, {:ok, [item | acc]}}
              end
            else
              false ->
                rejected =
                  rejected_operation_results(
                    envelope,
                    digest,
                    acc,
                    :cached_rejected_operation
                  )

                {:halt, {:error, {:atomic_rejection, :cached_rejected_operation, rejected}}}

              {:error, reason} ->
                item = atomic_operation_result(entry, request, result, "rolled_back")
                rejected = rejected_operation_results(envelope, digest, [item | acc], reason)
                {:halt, {:error, {:atomic_rejection, reason, rejected}}}
            end

          {:ok, result, :rejected} ->
            item = atomic_operation_result(entry, request, result, "rolled_back")
            reason = result["reason_code"] || "protected_rejection"
            rejected = rejected_operation_results(envelope, digest, [item | acc], reason)
            {:halt, {:error, {:atomic_rejection, reason, rejected}}}

          {:ok, result, :quarantined} when ordinal == 0 and length(operations) == 1 ->
            item = atomic_operation_result(entry, request, result, "committed")

            {:halt,
             {:ok,
              {:quarantined, Enum.reverse([item | acc]),
               result["reason_code"] || "protected_quarantine"}}}

          {:ok, result, :quarantined} ->
            item = atomic_operation_result(entry, request, result, "rolled_back")

            rejected =
              rejected_operation_results(
                envelope,
                digest,
                [item | acc],
                "quarantine_requires_single_operation"
              )

            {:halt,
             {:error, {:atomic_rejection, "quarantine_requires_single_operation", rejected}}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      else
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, {:quarantined, _results, _reason} = value} -> {:ok, value}
      {:ok, results} when is_list(results) -> {:ok, {:accepted, Enum.reverse(results)}}
      error -> error
    end
  end

  defp validate_atomic_prestate(conn, operations) do
    operations
    |> Enum.reduce_while({:ok, []}, fn entry, {:ok, prior} ->
      with {:ok, required} <-
             ProtectedPrimitives.required_bundle_prestate_revisions(
               conn,
               entry["operation"],
               Enum.reverse(prior)
             ) do
        supplied = entry["expected_revisions"]

        cond do
          required == supplied ->
            {:cont, {:ok, [entry["operation"] | prior]}}

          Enum.sort(Map.keys(required)) == Enum.sort(Map.keys(supplied)) ->
            {:halt, {:error, :stale_read_set}}

          true ->
            {:halt, {:error, :incomplete_read_set}}
        end
      else
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, _prior} -> :ok
      error -> error
    end
  end

  defp unexecuted_operation_results(envelope, digest, reason),
    do: rejected_operation_results(envelope, digest, [], reason)

  defp rejected_operation_results(envelope, digest, executed, reason) do
    executed =
      executed
      |> Enum.map(&rolled_back_operation_result(&1, reason))
      |> Map.new(&{&1["ordinal"], &1})

    Enum.map(envelope["operations"], fn entry ->
      Map.get_lazy(executed, entry["ordinal"], fn ->
        request = %{
          "schema_version" => 1,
          "command_id" => atomic_operation_id(digest, entry["ordinal"]),
          "expected_revisions" => entry["expected_revisions"],
          "operation" => entry["operation"]
        }

        atomic_operation_result(
          entry,
          request,
          %{
            "schema_version" => 1,
            "command_id" => request["command_id"],
            "disposition" => "unexecuted",
            "reason_code" => atomic_reason(reason),
            "facts" => %{}
          },
          "unexecuted"
        )
      end)
    end)
  end

  defp rolled_back_operation_result(item, reason) do
    result = %{
      "schema_version" => 1,
      "command_id" => get_in(item, ["request", "command_id"]),
      "disposition" => "rolled_back",
      "reason_code" => atomic_reason(reason),
      "facts" => %{}
    }

    item
    |> Map.put("execution_status", "rolled_back")
    |> Map.put("result", result)
  end

  defp duplicate_operation_results(envelope, digest, duplicate, earlier) do
    settlement = get_in(duplicate, ["result", "facts", "infrastructure_settlement"])

    duplicate = %{
      duplicate
      | "execution_status" => "duplicate",
        "result" => %{
          "schema_version" => 1,
          "command_id" => get_in(duplicate, ["request", "command_id"]),
          "disposition" => "duplicate",
          "reason_code" => "duplicate_receipt",
          "facts" => %{"infrastructure_settlement" => settlement}
        }
    }

    rejected_operation_results(envelope, digest, earlier, :duplicate_receipt)
    |> List.replace_at(duplicate["ordinal"], duplicate)
  end

  defp maybe_persist_nonstart(
         conn,
         %{"type" => "settle_claim", "outcome" => "non_started"} = op,
         result
       ) do
    with {:ok, settlement} <-
           ProtectedPrimitives.persist_nonstart_settlement(conn, op, result["facts"]) do
      status = if settlement["duplicate"] == true, do: :duplicate, else: :new
      settlement = Map.delete(settlement, "duplicate")
      {:ok, put_in(result, ["facts", "infrastructure_settlement"], settlement), status}
    end
  end

  defp maybe_persist_nonstart(_conn, _operation, result), do: {:ok, result, :none}

  defp atomic_operation_result(entry, request, result, execution_status) do
    %{
      "ordinal" => entry["ordinal"],
      "operation_kind" => "protected",
      "operation_type" => entry["operation_type"],
      "execution_status" => execution_status,
      "request" => request,
      "result" => result
    }
  end

  defp atomic_operation_id(digest, ordinal), do: "atomic-v2/#{digest}/#{ordinal}"

  defp commit_accepted_atomic_bundle(
         conn,
         envelope,
         canonical,
         digest,
         operation_results,
         fault
       ) do
    actor_id = envelope["actor_id"]
    command = envelope["command"]
    {domain_canonical, domain_digest} = prepare_command!(actor_id, command)

    with {:ok, proposal, discriminator} <-
           atomic_domain_proposal(conn, envelope, operation_results),
         :ok <- check_expected_revisions(conn, command, proposal, %{}),
         {:ok, {:accepted, domain_result}} <-
           commit_accepted_bundle(
             conn,
             actor_id,
             command,
             domain_canonical,
             domain_digest,
             proposal,
             %{},
             nil,
             :bundle_v2
           ),
         :ok <- inject(fault, :after_domain),
         durable <-
           atomic_result(
             command["command_id"],
             "accepted",
             nil,
             operation_results,
             domain_result,
             discriminator
           ),
         :ok <-
           persist_atomic_records(
             conn,
             envelope,
             canonical,
             digest,
             durable,
             operation_results,
             domain_result
           ),
         {:ok, _checked} <- Authority.read(conn, :all),
         :ok <- inject(fault, :before_commit) do
      {:ok, {:accepted, durable}}
    else
      {:error, reason}
      when reason in [:incomplete_expected_revisions, :projection_read_mismatch] ->
        {:error,
         {:atomic_rejection, reason,
          rejected_operation_results(envelope, digest, operation_results, reason)}}

      {:error, {:revision_conflict, _key, _expected, _actual} = reason} ->
        {:error,
         {:atomic_rejection, reason,
          rejected_operation_results(envelope, digest, operation_results, reason)}}

      {:error, {:plan_rejected, reason}} ->
        {:error,
         {:atomic_rejection, reason,
          rejected_operation_results(envelope, digest, operation_results, reason)}}

      {:error, _reason} = error ->
        error
    end
  end

  defp commit_quarantined_atomic_bundle(
         conn,
         envelope,
         canonical,
         digest,
         operation_results,
         reason,
         fault
       ) do
    actor_id = envelope["actor_id"]
    command = envelope["command"]
    {domain_canonical, domain_digest} = prepare_command!(actor_id, command)
    reason_code = atomic_reason(reason)

    with {:ok, {:rejected, domain_result}} <-
           commit_rejected_command(
             conn,
             actor_id,
             command,
             domain_canonical,
             domain_digest,
             {:atomic, reason_code},
             :bundle_v2
           ),
         durable <-
           atomic_result(
             command["command_id"],
             "quarantined",
             reason_code,
             operation_results,
             domain_result
           ),
         :ok <-
           persist_atomic_records(
             conn,
             envelope,
             canonical,
             digest,
             durable,
             operation_results,
             domain_result
           ),
         {:ok, _checked} <- Authority.read(conn, :all),
         :ok <- inject(fault, :before_commit) do
      {:ok, {:quarantined, durable}}
    end
  end

  defp persist_atomic_rejection(
         conn,
         envelope,
         canonical,
         digest,
         reason,
         operation_results,
         fault
       ) do
    actor_id = envelope["actor_id"]
    command = envelope["command"]
    {domain_canonical, domain_digest} = prepare_command!(actor_id, command)
    reason_code = atomic_reason(reason)

    transaction_result =
      Database.transaction(conn, fn ->
        with {:ok, {:rejected, domain_result}} <-
               commit_rejected_command(
                 conn,
                 actor_id,
                 command,
                 domain_canonical,
                 domain_digest,
                 {:atomic, reason_code},
                 :bundle_v2
               ),
             durable <-
               atomic_result(
                 command["command_id"],
                 "rejected",
                 reason_code,
                 operation_results,
                 domain_result
               ),
             :ok <-
               persist_atomic_records(
                 conn,
                 envelope,
                 canonical,
                 digest,
                 durable,
                 operation_results,
                 domain_result
               ),
             {:ok, _checked} <- Authority.read(conn, :all),
             :ok <- inject(fault, :before_commit) do
          {:ok, durable}
        end
      end)

    case transaction_result do
      {:ok, durable} -> atomic_reply(envelope, durable, :rejected, fault)
      {:error, why} -> {:error, {:storage_unavailable, why}}
    end
  end

  defp persist_atomic_records(
         conn,
         envelope,
         canonical,
         digest,
         durable,
         operation_results,
         domain_result
       ) do
    command_id = envelope["command"]["command_id"]

    with {:ok, result_bytes} <- Encoding.json(durable),
         :ok <-
           Database.execute(
             conn,
             "INSERT INTO atomic_bundles(command_id, actor_id, request_digest, schema_version, disposition, reason_code, canonical_envelope, result) VALUES (?, ?, ?, 2, ?, ?, ?, ?)",
             [
               command_id,
               envelope["actor_id"],
               digest,
               durable["disposition"],
               durable["reason_code"],
               {:blob, canonical},
               {:blob, result_bytes}
             ]
           ),
         :ok <- persist_atomic_operation_rows(conn, command_id, operation_results),
         domain_entry <- %{
           "ordinal" => length(operation_results),
           "operation_kind" => "domain",
           "operation_type" => envelope["command"]["type"],
           "execution_status" =>
             if(durable["disposition"] == "accepted", do: "committed", else: "rejected"),
           # Keyed by the envelope's real carrier. Previously this always wrote
           # "proposal", which is nil for a plan-bearing envelope — recording that no
           # proposal existed for a bundle that had just committed one. A
           # proposal-bearing row is byte-identical to before, so stored histories and
           # the protected domain-row validator are unaffected.
           "request" => atomic_domain_request(envelope),
           "result" => domain_result
         },
         :ok <- persist_atomic_operation_rows(conn, command_id, [domain_entry]) do
      :ok
    end
  end

  defp persist_atomic_operation_rows(conn, command_id, entries) do
    Enum.reduce_while(entries, :ok, fn entry, :ok ->
      with {:ok, request_bytes} <- Encoding.json(entry["request"]),
           {:ok, result_bytes} <-
             Encoding.json(%{
               "schema_version" => 1,
               "execution_status" => entry["execution_status"],
               "operation_result" => entry["result"]
             }),
           :ok <-
             Database.execute(
               conn,
               "INSERT INTO durable_operations(owner_kind, owner_id, ordinal, operation_kind, operation_type, request, result) VALUES ('bundle_v2', ?, ?, ?, ?, ?, ?)",
               [
                 command_id,
                 entry["ordinal"],
                 entry["operation_kind"],
                 entry["operation_type"],
                 {:blob, request_bytes},
                 {:blob, result_bytes}
               ]
             ) do
        {:cont, :ok}
      else
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp atomic_result(command_id, disposition, reason, operation_results, domain_result),
    do: atomic_result(command_id, disposition, reason, operation_results, domain_result, nil)

  # The selected discriminator is recorded because it cannot be recomputed later.
  # infrastructure_discriminator/3 derives from the *current* policy row and fails closed
  # once that policy is revised, so a value not written down at commit time is
  # unrecoverable in principle rather than merely inconvenient.
  defp atomic_result(
         command_id,
         disposition,
         reason,
         operation_results,
         domain_result,
         discriminator
       ) do
    %{
      "schema_version" => 2,
      "command_id" => command_id,
      "disposition" => disposition,
      "reason_code" => reason,
      "committed_seq" => domain_result["committed_seq"],
      "operations" =>
        Enum.map(operation_results, fn item ->
          Map.take(item, ~w(ordinal operation_kind operation_type execution_status result))
        end),
      "domain_result" => domain_result,
      "selected_discriminator" => discriminator
    }
  end

  defp prepare_command!(actor_id, command) do
    case prepare_command(actor_id, command) do
      {:ok, canonical, digest, _normalized} -> {canonical, digest}
    end
  end

  defp atomic_reply(envelope, _durable, _status, :after_commit_before_reply),
    do: {:error, {:outcome_unknown, envelope["command"]["command_id"]}}

  defp atomic_reply(_envelope, durable, status, _fault), do: {:ok, durable, status}

  defp atomic_reason({:revision_conflict, _key, _expected, _actual}), do: "revision_conflict"
  defp atomic_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp atomic_reason(reason) when is_binary(reason) and reason != "", do: reason
  defp atomic_reason(_reason), do: "atomic_bundle_rejected"

  defp canonical_value(value) do
    with {:ok, bytes} <- Encoding.json(value), do: decode_json_map(bytes)
  end

  defp decode_json_map(bytes) when is_binary(bytes) do
    try do
      case :json.decode(bytes) do
        value when is_map(value) -> {:ok, normalize_json(value)}
        _ -> {:error, :invalid_json_map}
      end
    rescue
      _ -> {:error, :invalid_json_map}
    end
  end

  defp normalize_json(:null), do: nil
  defp normalize_json(value) when is_list(value), do: Enum.map(value, &normalize_json/1)

  defp normalize_json(value) when is_map(value),
    do: Map.new(value, fn {key, item} -> {key, normalize_json(item)} end)

  defp normalize_json(value), do: value

  defp plain_map?(value), do: is_map(value) and not is_struct(value)

  # A v2 envelope carries either a precomputed proposal or an unresolved transition plan,
  # never both and never neither. The digest is computed over whichever it carries, so a
  # plan-bearing command digests over its *unresolved* plan: the same command must digest
  # identically regardless of which alternative the protected discriminator later selects,
  # or an idempotent retry after a lost reply could not find its original result.
  # A proposal-bearing envelope commits what it carried. A plan-bearing one is resolved
  # here: the protected layer derives the discriminator from facts staged inside this same
  # transaction, and the codec mechanically selects and substitutes. Gateway never
  # executes candidate code to decide what commits, and never accepts a caller's copy of
  # an authoritative fact — bind/3 takes the staged results, not a supplied map.
  defp atomic_domain_proposal(_conn, %{"proposal" => proposal}, _results),
    do: {:ok, proposal, nil}

  defp atomic_domain_proposal(conn, %{"plan" => plan}, results) do
    with {:ok, discriminator} <- protected_discriminator(conn, plan, results),
         {:ok, proposal} <- TransitionPlan.bind(plan, discriminator, results) do
      {:ok, proposal, discriminator}
    else
      # Tagged so a rejected plan can never be mistaken for an infrastructure fault.
      # Untagged, these errors reached the generic catch-all, were mapped to
      # :storage_unavailable, and flipped the whole Gateway into permanent recovery mode
      # for every actor. A candidate-authored plan being wrong is an ordinary rejection.
      # The tag also means this does not have to enumerate TransitionPlan's error
      # vocabulary, and cannot accidentally swallow a genuine storage failure.
      {:error, reason} -> {:error, {:plan_rejected, reason}}
    end
  end

  # The kind is a closed vocabulary validated by TransitionPlan, so this maps a name to
  # one fixed protected function rather than dispatching on caller-supplied text.
  defp protected_discriminator(
         conn,
         %{"discriminator_kind" => "infrastructure_limit_v1"} = plan,
         results
       ) do
    with {:ok, settlement} <- staged_settlement_fact(plan, results) do
      ProtectedPrimitives.infrastructure_discriminator(
        conn,
        settlement["effect_id"],
        settlement
      )
    end
  end

  defp protected_discriminator(_conn, _plan, _results),
    do: {:error, :unsupported_discriminator_kind}

  # Resolved through the ordinal the plan's settlement binding declares, not by scanning
  # every staged result for a unique settlement. The scanning form failed closed, but it
  # would have refused a legitimate bundle settling two independent role launches
  # atomically, and it let the discriminator describe a settlement the plan never bound.
  defp staged_settlement_fact(plan, results) do
    case Enum.filter(plan["bindings"], &(&1["output_kind"] == "nonstart_settlement_v1")) do
      [binding] ->
        settlement =
          results
          |> Enum.find(%{}, &(&1["ordinal"] == binding["operation_ordinal"]))
          |> get_in(["result", "facts", "infrastructure_settlement"])

        if is_map(settlement),
          do: {:ok, settlement},
          else: {:error, :discriminator_settlement_unavailable}

      _ ->
        {:error, :discriminator_settlement_unavailable}
    end
  end

  defp atomic_carrier(input) do
    case Enum.sort(Map.keys(input)) do
      ~w(actor_id command inputs operations proposal schema_version) -> {:ok, "proposal"}
      ~w(actor_id command inputs operations plan schema_version) -> {:ok, "plan"}
      _ -> {:error, :invalid_atomic_bundle}
    end
  end

  defp atomic_carrier_name(%{"plan" => _}), do: "plan"
  defp atomic_carrier_name(_envelope), do: "proposal"

  @doc false
  # Public to the protected validator, which must reconstruct exactly this shape.
  def atomic_domain_request(envelope) do
    carrier = atomic_carrier_name(envelope)

    %{
      "command" => envelope["command"],
      "inputs" => envelope["inputs"],
      carrier => envelope[carrier]
    }
  end

  defp normalize_atomic_carrier("proposal", value, _operations), do: normalize_candidate(value)

  defp normalize_atomic_carrier("plan", value, operations) do
    with {:ok, plan} <- TransitionPlan.validate(value),
         :ok <- plan_describes_operations(plan, operations) do
      {:ok, plan}
    end
  end

  # A plan whose declared operations disagree with the ones the envelope actually stages
  # is incoherent. derive_output/2 validates against the real staged result, so this was
  # not unsound, but an incoherent plan should be refused here rather than tolerated
  # because a later check happens to catch the consequence.
  defp plan_describes_operations(plan, operations) do
    declared =
      Enum.map(plan["protected_operations"], &{&1["ordinal"], &1["type"]})

    staged =
      operations
      |> Enum.with_index()
      |> Enum.map(fn {entry, index} -> {index, entry["operation"]["type"]} end)

    if declared == staged, do: :ok, else: {:error, :plan_operations_mismatch}
  end

  defp normalize_candidate(proposal) do
    case Kernel.normalize_bundle(proposal) do
      {:error, :projection_transition_bijection} ->
        {:error, {:bundle_rejected, :projection_transition_bijection}}

      {:error, :invalid_projection} ->
        {:error, :invalid_projection_revision}

      result ->
        result
    end
  end

  defp prepare_command(actor_id, command) do
    with :ok <- validate_actor(actor_id),
         {:ok, normalized_command} <- RecordCodec.normalize(:command, command),
         {:ok, canonical} <-
           Encoding.canonical(%{
             "domain" => "pramana-foundry-command-v1",
             "schema_version" => 1,
             "actor_id" => actor_id,
             "command" => normalized_command
           }) do
      {:ok, canonical, Encoding.digest(canonical), normalized_command}
    end
  end

  defp commit_bundle(conn, actor_id, command, canonical, digest, proposal, protected, fault) do
    transaction_result =
      Database.transaction(conn, fn ->
        case check_expected_revisions(conn, command, proposal, protected) do
          :ok ->
            commit_accepted_bundle(
              conn,
              actor_id,
              command,
              canonical,
              digest,
              proposal,
              protected,
              fault
            )

          {:error, {:revision_conflict, _key, _expected, _actual} = reason} ->
            commit_rejected_command(conn, actor_id, command, canonical, digest, reason)

          {:error, reason} ->
            {:error, reason}
        end
      end)

    case transaction_result do
      {:ok, {:accepted, result}} ->
        case fault do
          :after_commit_before_reply ->
            {:error, {:outcome_unknown, get(command, "command_id")}}

          {:halt, :after_commit} ->
            System.halt(72)

          _other ->
            {:ok, result, :committed}
        end

      {:ok, {:rejected, result}} ->
        {:ok, result, :rejected}

      {:error, reason} ->
        cond do
          match?({:authority_corrupt, _table, _identity, _why}, reason) -> {:error, reason}
          match?({:storage_unavailable, _why}, reason) -> {:error, reason}
          semantic_rejection?(reason) -> {:error, {:bundle_rejected, reason}}
          true -> {:error, {:storage_unavailable, reason}}
        end
    end
  end

  defp commit_accepted_bundle(
         conn,
         actor_id,
         command,
         canonical,
         digest,
         proposal,
         protected,
         fault,
         durable_owner \\ :domain_v1
       ) do
    with :ok <- inject(fault, :before_write),
         :ok <- insert_input(conn, actor_id, command, canonical, digest),
         :ok <- inject(fault, :after_input),
         :ok <- insert_command(conn, actor_id, command, digest),
         :ok <- inject(fault, :after_command),
         :ok <- insert_events(conn, get(proposal, :events, []), get(command, "command_id")),
         :ok <- inject(fault, :after_events),
         :ok <-
           insert_projections(
             conn,
             get(proposal, :events, []),
             get(proposal, :projections, [])
           ),
         :ok <- inject(fault, :after_projections),
         :ok <-
           insert_intents(conn, get(proposal, :intents, []), get(command, "command_id")),
         :ok <- inject(fault, :after_intents),
         :ok <- insert_generations(conn, get(protected, :ledger_generations, [])),
         :ok <- inject(fault, :after_generations),
         :ok <- insert_claims(conn, get(protected, :claims, [])),
         :ok <- inject(fault, :after_claims),
         :ok <- insert_reservations(conn, get(protected, :reservations, [])),
         :ok <- inject(fault, :after_reservations),
         {:ok, committed_seq} <- current_seq(conn),
         {:ok, result} <-
           insert_result(
             conn,
             get(command, "command_id"),
             get(proposal, :result),
             committed_seq
           ),
         :ok <- maybe_persist_v1_domain_operation(conn, command, durable_owner),
         :ok <- inject(fault, :after_result),
         {:ok, _checked} <-
           Authority.read(conn, {
             :touched,
             %{
               command_id: get(command, "command_id"),
               committed_seq: committed_seq,
               revisions: touched_revisions(proposal, protected)
             }
           }),
         :ok <- inject(fault, :before_commit) do
      {:ok, {:accepted, result}}
    end
  end

  defp commit_rejected_command(
         conn,
         actor_id,
         command,
         canonical,
         digest,
         reason,
         durable_owner \\ :domain_v1
       ) do
    with :ok <- insert_input(conn, actor_id, command, canonical, digest),
         :ok <- insert_command(conn, actor_id, command, digest),
         {:ok, committed_seq} <- current_seq(conn),
         {:ok, result} <-
           insert_result(
             conn,
             get(command, "command_id"),
             %{
               schema_version: 1,
               disposition: "rejected",
               reason_code: rejection_reason_code(reason)
             },
             committed_seq
           ),
         :ok <- maybe_persist_v1_domain_operation(conn, command, durable_owner),
         {:ok, _checked} <-
           Authority.read(conn, {
             :touched,
             %{
               command_id: get(command, "command_id"),
               committed_seq: committed_seq,
               revisions: []
             }
           }) do
      {:ok, {:rejected, result}}
    end
  end

  defp rejection_reason_code({:revision_conflict, _key, _expected, _actual}),
    do: "revision_conflict"

  defp rejection_reason_code({:atomic, reason}) when is_binary(reason), do: reason

  defp maybe_persist_v1_domain_operation(_conn, _command, :bundle_v2), do: :ok

  defp maybe_persist_v1_domain_operation(conn, command, :domain_v1) do
    Database.execute(
      conn,
      "INSERT INTO durable_operations(owner_kind, owner_id, ordinal, operation_kind, operation_type, request, result) " <>
        "SELECT 'domain_v1', c.command_id, 0, 'domain', c.command_type, i.canonical_request, r.result " <>
        "FROM commands c JOIN inputs i ON i.input_id = c.input_id JOIN command_results r ON r.command_id = c.command_id " <>
        "WHERE c.command_id = ?",
      [command["command_id"]]
    )
  end

  defp insert_input(conn, actor_id, command, canonical, digest) do
    Database.execute(
      conn,
      "INSERT INTO inputs(input_id, actor_id, request_digest, canonical_request, protocol_version) VALUES (?, ?, ?, ?, 1)",
      ["input:" <> get(command, "command_id"), actor_id, digest, {:blob, canonical}]
    )
  end

  defp insert_command(conn, actor_id, command, digest) do
    Database.execute(
      conn,
      "INSERT INTO commands(command_id, input_id, actor_id, request_digest, command_type, protocol_version) VALUES (?, ?, ?, ?, ?, 1)",
      [
        get(command, "command_id"),
        "input:" <> get(command, "command_id"),
        actor_id,
        digest,
        get(command, "type")
      ]
    )
  end

  defp insert_events(conn, events, command_id) do
    reduce_insert(events, fn event ->
      with {:ok, encoded} <- RecordCodec.encode(:event, event),
           {projection_namespace, projection_entity_id} <- event_carrier(event) do
        Database.execute(
          conn,
          "INSERT INTO events(event_id, command_id, schema_version, event_type, projection_namespace, projection_entity_id, event) VALUES (?, ?, 1, ?, ?, ?, ?)",
          [
            get(event, :event_id),
            command_id,
            get(event, :type),
            projection_namespace,
            projection_entity_id,
            {:blob, encoded}
          ]
        )
      end
    end)
  end

  defp event_carrier(event) do
    case get(event, :payload)["projection"] do
      nil -> {nil, nil}
      projection -> {projection["namespace"], projection["entity_id"]}
    end
  end

  defp insert_projections(conn, events, projections) do
    with {:ok, plan} <- RecordCodec.projection_plan(events, projections),
         {:ok, initial} <- projection_initial_state(conn, plan) do
      Enum.reduce_while(plan, {:ok, initial}, fn {carrier, projection} = step, {:ok, state} ->
        key = {projection["namespace"], projection["entity_id"]}

        with {:ok, next} <- RecordCodec.apply_projection(state, step),
             entry <- Map.fetch!(next, key),
             true <-
               entry == %{
                 revision: projection["revision"],
                 last_event_id: projection["last_event_id"],
                 value: projection["value"]
               },
             {:ok, encoded} <- RecordCodec.encode(:projection, projection),
             :ok <- materialize_projection(conn, projection, encoded),
             {:ok, [[1]]} <- Database.query(conn, "SELECT changes()"),
             {:ok, %{value: stored}} <-
               Authority.read(
                 conn,
                 {:materialized_projection, elem(key, 0), elem(key, 1), carrier["event_id"]}
               ),
             true <- stored == projection do
          {:cont, {:ok, next}}
        else
          false -> {:halt, {:error, :projection_materialization_mismatch}}
          {:ok, rows} -> {:halt, {:error, {:projection_cas_failed, rows}}}
          {:error, _reason} = error -> {:halt, error}
        end
      end)
      |> then(fn
        {:ok, _state} -> :ok
        error -> error
      end)
    end
  end

  defp projection_initial_state(conn, plan) do
    plan
    |> Enum.map(fn {_carrier, projection} ->
      {projection["namespace"], projection["entity_id"]}
    end)
    |> Enum.uniq()
    |> Enum.reduce_while({:ok, %{}}, fn {namespace, entity_id} = key, {:ok, state} ->
      case Authority.read(conn, {:materialized_projection, namespace, entity_id, :stored}) do
        {:ok, :absent} ->
          {:cont, {:ok, state}}

        {:ok, %{value: projection}} ->
          entry = %{
            revision: projection["revision"],
            last_event_id: projection["last_event_id"],
            value: projection["value"]
          }

          {:cont, {:ok, Map.put(state, key, entry)}}

        {:error, _reason} = error ->
          {:halt, error}
      end
    end)
  end

  defp materialize_projection(conn, projection, encoded) do
    if projection["expected_revision"] == -1 do
      Database.execute(
        conn,
        "INSERT INTO projections(namespace, entity_id, schema_version, revision, last_event_id, projection) VALUES (?, ?, 1, ?, ?, ?)",
        [
          projection["namespace"],
          projection["entity_id"],
          projection["revision"],
          projection["last_event_id"],
          {:blob, encoded}
        ]
      )
    else
      Database.execute(
        conn,
        "UPDATE projections SET revision = ?, last_event_id = ?, projection = ? WHERE namespace = ? AND entity_id = ? AND revision = ?",
        [
          projection["revision"],
          projection["last_event_id"],
          {:blob, encoded},
          projection["namespace"],
          projection["entity_id"],
          projection["expected_revision"]
        ]
      )
    end
  end

  defp insert_intents(conn, intents, command_id) do
    reduce_insert(intents, fn intent ->
      with {:ok, encoded} <- RecordCodec.encode(:intent, intent) do
        Database.execute(
          conn,
          "INSERT INTO effects(effect_id, command_id, schema_version, request_digest, status, intent) VALUES (?, ?, 1, ?, ?, ?)",
          [
            get(intent, :effect_id),
            command_id,
            get(intent, :request_digest),
            get(intent, :status),
            {:blob, encoded}
          ]
        )
      end
    end)
  end

  defp insert_generations(conn, generations) do
    reduce_insert(generations, fn generation ->
      retained = Map.put(generation, "revision", 0)

      with {:ok, normalized} <- RecordCodec.normalize(:ledger_generation, retained) do
        Database.execute(
          conn,
          "INSERT INTO ledger_generations(generation_id, parent_generation_id, schema_version, revision, allocation, consumed) VALUES (?, ?, 1, 0, ?, ?)",
          [
            normalized["generation_id"],
            normalized["parent_generation_id"],
            normalized["allocation"],
            normalized["consumed"]
          ]
        )
      end
    end)
  end

  defp insert_claims(conn, claims) do
    reduce_insert(claims, fn claim ->
      with {:ok, encoded} <- RecordCodec.encode(:claim, claim) do
        Database.execute(
          conn,
          "INSERT INTO claims(claim_id, effect_id, writer_epoch, status, claim) VALUES (?, ?, ?, ?, ?)",
          [
            get(claim, :claim_id),
            get(claim, :effect_id),
            get(claim, :writer_epoch),
            get(claim, :status),
            {:blob, encoded}
          ]
        )
      end
    end)
  end

  defp insert_reservations(conn, reservations) do
    reduce_insert(reservations, fn reservation ->
      with {:ok, encoded} <- RecordCodec.encode(:reservation, reservation) do
        Database.execute(
          conn,
          "INSERT INTO reservations(reservation_id, generation_id, claim_id, dimension, units, status, reservation) VALUES (?, ?, ?, ?, ?, ?, ?)",
          [
            get(reservation, :reservation_id),
            get(reservation, :generation_id),
            get(reservation, :claim_id),
            get(reservation, :dimension),
            get(reservation, :units),
            get(reservation, :status),
            {:blob, encoded}
          ]
        )
      end
    end)
  end

  defp insert_result(conn, command_id, result, committed_seq) do
    with {:ok, durable} <- RecordCodec.materialize_result(result, committed_seq),
         {:ok, encoded} <- RecordCodec.encode(:result, durable),
         :ok <-
           Database.execute(
             conn,
             "INSERT INTO command_results(command_id, schema_version, disposition, reason_code, result, committed_seq) VALUES (?, 1, ?, ?, ?, ?)",
             [
               command_id,
               get(result, :disposition),
               get(result, :reason_code),
               {:blob, encoded},
               committed_seq
             ]
           ) do
      RecordCodec.decode(:result, encoded)
    end
  end

  defp existing(conn, command_id, actor_id, digest) do
    with {:ok, [[atomic_count]]} <-
           Database.query(conn, "SELECT count(*) FROM atomic_bundles WHERE command_id = ?", [
             command_id
           ]) do
      if atomic_count > 0 or ProtectedPrimitives.root_command_id_exists?(conn, command_id) do
        {:error, :idempotency_conflict}
      else
        case Authority.read(conn, {:command, command_id}) do
          {:ok, :absent} ->
            {:error, :not_found}

          {:ok, %{actor_id: ^actor_id, digest: ^digest, result: result}} ->
            {:ok, result}

          {:ok, %{}} ->
            {:error, :idempotency_conflict}

          {:error, _reason} = error ->
            error
        end
      end
    else
      {:error, _reason} = error -> error
    end
  end

  defp fetch_command(conn, command_id) do
    if valid_identity?(command_id) do
      case Authority.read(conn, {:command, command_id}) do
        {:ok, :absent} -> {:error, :not_found}
        {:ok, %{result: result}} -> {:ok, result}
        {:error, _reason} = error -> error
      end
    else
      {:error, :invalid_command_id}
    end
  end

  defp current_seq(conn) do
    case Database.query(conn, "SELECT coalesce(max(seq), 0) FROM events") do
      {:ok, [[seq]]} -> {:ok, seq}
      {:error, reason} -> {:error, reason}
    end
  end

  defp check_expected_revisions(conn, command, proposal, protected) do
    expected = get(command, "expected_revisions")

    required =
      required_projection_reads(proposal) |> Map.merge(get(protected, :required_revisions, %{}))

    with true <- Enum.all?(required, fn {key, value} -> Map.get(expected, key) == value end),
         :ok <- validate_projection_read_alignment(proposal, expected) do
      Enum.reduce_while(expected, :ok, fn {key, expected_value}, :ok ->
        case read_revision(conn, key) do
          {:ok, actual} when actual == expected_value -> {:cont, :ok}
          {:ok, actual} -> {:halt, {:error, {:revision_conflict, key, expected_value, actual}}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
    else
      false -> {:error, :incomplete_expected_revisions}
      {:error, _reason} = error -> error
    end
  end

  defp required_projection_reads(proposal) do
    Enum.reduce(get(proposal, :projections, []), %{}, fn projection, acc ->
      expected = get(projection, :expected_revision)
      value = if expected == -1, do: "absent", else: expected

      Map.put_new(
        acc,
        projection_key(get(projection, :namespace), get(projection, :entity_id)),
        value
      )
    end)
  end

  defp touched_revisions(proposal, protected) do
    projection_keys =
      Enum.map(get(proposal, :projections, []), fn projection ->
        {:projection, projection["namespace"], projection["entity_id"]}
      end)

    ledger_keys =
      Enum.map(get(protected, :ledger_generations, []), fn generation ->
        {:ledger, generation["generation_id"]}
      end)

    projection_keys ++ ledger_keys
  end

  defp validate_projection_read_alignment(proposal, expected) do
    if Enum.all?(required_projection_reads(proposal), fn {key, expected_value} ->
         Map.get(expected, key) == expected_value
       end),
       do: :ok,
       else: {:error, :projection_read_mismatch}
  end

  defp read_revision(conn, key) when is_binary(key) do
    typed = RecordCodec.decode_revision_key(key)

    case typed do
      {:error, reason} ->
        {:error, {reason, key}}

      {:ok, typed_key} ->
        with {:ok, value} <- Authority.read(conn, {:revision, typed_key}) do
          case value do
            :absent -> {:ok, "absent"}
            %{revision: revision} -> {:ok, revision}
          end
        end
    end
  end

  defp projection_key(namespace, entity_id) do
    "projection/" <> encode_key(namespace) <> "/" <> encode_key(entity_id)
  end

  defp encode_key(value), do: Base.url_encode64(value, padding: false)

  defp validate_actor(actor_id) when is_binary(actor_id) and actor_id != "" do
    if String.valid?(actor_id), do: :ok, else: {:error, :invalid_actor}
  end

  defp validate_actor(_actor_id), do: {:error, :invalid_actor}
  defp valid_identity?(value), do: is_binary(value) and value != "" and String.valid?(value)

  defp reduce_insert(values, fun) do
    Enum.reduce_while(values, :ok, fn value, :ok ->
      case fun.(value) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp inject(:write_error, :before_write), do: {:error, :injected_write_error}
  defp inject(:full, :before_write), do: {:error, :injected_full}
  defp inject(:after_protected, :after_protected), do: {:error, :injected_after_protected}
  defp inject(:after_domain, :after_domain), do: {:error, :injected_after_domain}
  defp inject(:before_commit, :before_commit), do: {:error, :injected_crash_before_commit}
  defp inject({:halt, :before_commit}, :before_commit), do: System.halt(71)
  defp inject({:after_insert, point}, point), do: {:error, {:injected_after_insert, point}}
  defp inject(_fault, _point), do: :ok

  defp transition_after_result(state, result) do
    case result do
      {:error, {:storage_unavailable, _reason}} ->
        %{state | mode: :recovery, reason: result}

      {:error, {:authority_corrupt, _type, _identity, _reason} = reason} ->
        %{state | mode: :recovery, reason: reason}

      _other ->
        state
    end
  end

  defp semantic_rejection?(reason) do
    match?({:revision_conflict, _rows}, reason) or
      match?({:revision_conflict, _key, _expected, _actual}, reason) or
      reason in [:incomplete_expected_revisions, :projection_read_mismatch] or
      match?({:unsupported_revision_key, _key}, reason) or
      match?({:invalid_revision_key, _key}, reason)
  end

  defp maybe_limit_pages(_conn, nil), do: :ok

  defp maybe_limit_pages(conn, pages) when is_integer(pages) and pages > 0 do
    with {:ok, [[current]]} <- Database.query(conn, "PRAGMA page_count") do
      # A schema migration can legitimately make an existing absolute fixture limit
      # smaller than the already committed database.  In that case retain the same
      # bounded-growth fault probe by treating the requested pages as additional room.
      target = if pages <= current, do: current + pages, else: pages

      case Database.query(conn, "PRAGMA max_page_count = #{target}") do
        {:ok, [[actual]]} when actual <= target -> :ok
        {:ok, rows} -> {:error, {:page_limit_failed, rows}}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_limit_pages(_conn, _pages), do: {:error, :invalid_page_limit}

  defp read_operational_health(state) do
    with {:ok, [[page_count]]} <- Database.query(state.conn, "PRAGMA page_count"),
         {:ok, [[page_size]]} <- Database.query(state.conn, "PRAGMA page_size"),
         {:ok, [[max_page_count]]} <- Database.query(state.conn, "PRAGMA max_page_count"),
         {:ok, [[last_sequence]]} <-
           Database.query(state.conn, "SELECT coalesce(max(seq), 0) FROM events") do
      {:ok,
       %{
         mode: :ready,
         last_durable_sequence: last_sequence,
         database_bytes: page_count * page_size,
         wal_bytes: file_size(state.path <> "-wal"),
         capacity: %{
           sqlite_page_count: page_count,
           sqlite_max_page_count: max_page_count,
           sqlite_available_bytes: max(max_page_count - page_count, 0) * page_size
         }
       }}
    else
      {:error, reason} -> {:error, {:storage_unavailable, reason}}
      other -> {:error, {:storage_unavailable, {:invalid_health_result, other}}}
    end
  end

  defp add_physical_capacity(health, physical) do
    capacity =
      Map.merge(health.capacity, %{
        physical_available_bytes: physical,
        status: if(is_integer(physical), do: :known, else: :unknown)
      })

    %{health | capacity: capacity}
  end

  defp query_recent_events(_conn, limit) when limit < 1 or limit > 1_000,
    do: {:error, {:invalid_limit, %{minimum: 1, maximum: 1_000}}}

  defp query_recent_events(conn, limit) do
    case Database.query(
           conn,
           "SELECT seq, event_id, command_id, event_type FROM events ORDER BY seq DESC LIMIT ?",
           [limit]
         ) do
      {:ok, rows} ->
        {:ok,
         Enum.map(rows, fn [sequence, event_id, command_id, event_type] ->
           %{
             sequence: sequence,
             event_id: event_id,
             command_id: command_id,
             event_type: event_type
           }
         end)}

      {:error, reason} ->
        {:error, {:storage_unavailable, reason}}
    end
  end

  defp checkpoint_database(conn, fault) do
    with {:ok, before_view} <- Authority.read(conn, :all),
         :ok <- inject_maintenance(fault, :before_checkpoint),
         {:ok, [[busy, log_frames, checkpointed_frames]]} <-
           run_maintenance_operation(fault, :during_checkpoint, conn, fn ->
             Database.query(conn, "PRAGMA wal_checkpoint(TRUNCATE)")
           end),
         true <- busy == 0,
         :ok <- inject_maintenance(fault, :after_checkpoint),
         {:ok, after_view} <- Authority.read(conn, :all),
         true <- before_view.content == after_view.content,
         true <- before_view.reconstructed == after_view.reconstructed,
         {:ok, [[last_sequence]]} <-
           Database.query(conn, "SELECT coalesce(max(seq), 0) FROM events") do
      {:ok,
       %{
         busy: busy,
         log_frames: log_frames,
         checkpointed_frames: checkpointed_frames,
         last_durable_sequence: last_sequence
       }}
    else
      false -> {:error, {:authority_corrupt, "sqlite", "checkpoint", :content_mismatch}}
      {:error, {:authority_corrupt, _table, _identity, _reason} = reason} -> {:error, reason}
      {:error, reason} -> {:error, {:storage_unavailable, reason}}
      other -> {:error, {:storage_unavailable, {:checkpoint_failed, other}}}
    end
  end

  defp inject_maintenance({:halt, point}, point), do: System.halt(74)
  defp inject_maintenance({:error, point}, point), do: {:error, {:injected_maintenance, point}}
  defp inject_maintenance(_fault, _point), do: :ok

  defp start_maintenance_fault({:during, point, fun}, point, conn) when is_function(fun, 1),
    do: fun.(conn)

  defp start_maintenance_fault(_fault, _point, _conn), do: :ok

  defp run_maintenance_operation(fault, point, conn, operation) do
    case start_maintenance_fault(fault, point, conn) do
      {:scoped, finish} when is_function(finish, 1) ->
        try do
          result = operation.()

          case finish.(result) do
            :ok -> result
            {:error, _reason} = error -> error
            other -> {:error, {:maintenance_fault_cleanup_failed, other}}
          end
        catch
          kind, reason ->
            stacktrace = __STACKTRACE__
            _ = finish.({:raised, kind, reason})
            :erlang.raise(kind, reason, stacktrace)
        end

      :ok ->
        operation.()

      {:error, _reason} = error ->
        error

      other ->
        {:error, {:invalid_maintenance_fault_result, other}}
    end
  end

  defp capacity_probe_controller(owner, token, probe, path, timeout_ms) do
    owner_monitor = Process.monitor(owner)
    controller = self()

    {probe_pid, probe_monitor} =
      spawn_monitor(fn ->
        result = invoke_capacity_probe(probe, path)
        send(controller, {:capacity_probe_result, self(), result})
      end)

    timer = Process.send_after(controller, :capacity_probe_timeout, timeout_ms)

    await_capacity_probe(
      owner,
      owner_monitor,
      token,
      probe_pid,
      probe_monitor,
      timer
    )
  end

  defp await_capacity_probe(owner, owner_monitor, token, probe_pid, probe_monitor, timer) do
    receive do
      {:capacity_probe_result, ^probe_pid, result} ->
        Process.cancel_timer(timer)
        Process.demonitor(probe_monitor, [:flush])
        Process.demonitor(owner_monitor, [:flush])
        send(owner, {:operational_health_capacity, token, result})

      :capacity_probe_timeout ->
        stop_capacity_probe(probe_pid, probe_monitor)
        Process.demonitor(owner_monitor, [:flush])
        send(owner, {:operational_health_capacity_timeout, token})

      {:cancel_capacity_probe, ^token} ->
        Process.cancel_timer(timer)
        stop_capacity_probe(probe_pid, probe_monitor)
        Process.demonitor(owner_monitor, [:flush])

      {:DOWN, ^owner_monitor, :process, ^owner, _reason} ->
        Process.cancel_timer(timer)
        stop_capacity_probe(probe_pid, probe_monitor)

      {:DOWN, ^probe_monitor, :process, ^probe_pid, reason} ->
        Process.cancel_timer(timer)
        Process.demonitor(owner_monitor, [:flush])

        send(
          owner,
          {:operational_health_capacity, token, {:error, {:capacity_probe_worker_exit, reason}}}
        )
    end
  end

  defp stop_capacity_probe(probe_pid, probe_monitor) do
    Process.exit(probe_pid, :kill)

    receive do
      {:DOWN, ^probe_monitor, :process, ^probe_pid, _reason} -> :ok
    end
  end

  defp invoke_capacity_probe(probe, path) do
    probe.(path)
  rescue
    error -> {:error, {:capacity_probe_exception, error}}
  catch
    :exit, reason -> {:error, {:capacity_probe_exit, reason}}
  end

  defp normalize_capacity_result(result) do
    case result do
      {:ok, bytes} when is_integer(bytes) and bytes >= 0 -> bytes
      {:error, reason} -> {:unknown, reason}
      other -> {:unknown, {:invalid_capacity_result, other}}
    end
  end

  defp file_size(path) do
    case File.stat(path) do
      {:ok, stat} -> stat.size
      {:error, :enoent} -> 0
      {:error, reason} -> {:unknown, reason}
    end
  end

  defp backup_database(conn, path, fault) do
    with {:ok, source_view} <- Authority.read(conn, :all),
         {:ok, target} <- PathIdentity.new(path),
         {:ok, database_rows} <- Database.query(conn, "PRAGMA database_list"),
         source_path when is_binary(source_path) and source_path != "" <-
           Enum.find_value(database_rows, fn
             [_seq, "main", value] -> value
             _row -> nil
           end),
         {:ok, source} <- PathIdentity.existing(source_path),
         :ok <- PathIdentity.validate_new_database(target),
         :ok <- PathIdentity.validate_publication(source, [target]),
         false <- PathIdentity.collision?(source, target) do
      perform_backup(conn, target, source_view, fault)
    else
      {:error, :target_exists} -> {:error, :backup_exists}
      true -> {:error, :backup_path_collision}
      {:error, reason} -> {:error, reason}
    end
  end

  defp perform_backup(conn, target, source_view, fault) do
    escaped = String.replace(target.path, "'", "''")

    with :ok <-
           run_maintenance_operation(fault, :during_backup, conn, fn ->
             Database.execute(conn, "VACUUM INTO '#{escaped}'")
           end),
         :ok <- maybe_interrupt_backup(fault),
         {:ok, snapshot} <- PathIdentity.existing(target.path),
         {:ok, result} <- verify_backup(snapshot, source_view, fault) do
      {:ok, result}
    else
      {:error, {:storage_unavailable, _reason} = reason} -> {:error, reason}
      {:error, reason} -> {:error, {:storage_unavailable, {:backup_failed, reason}}}
      other -> {:error, {:storage_unavailable, {:backup_failed, other}}}
    end
  end

  defp maybe_interrupt_backup(fault), do: inject_maintenance(fault, :after_backup_snapshot)

  defp verify_backup(snapshot, source_view, fault) do
    path = snapshot.path

    open_result =
      with :ok <- PathIdentity.revalidate(snapshot),
           {:ok, conn} <- Database.open(snapshot),
           :ok <- PathIdentity.revalidate(snapshot) do
        {:ok, conn}
      end

    case open_result do
      {:ok, backup} ->
        result =
          with {:ok, backup_view} <- Authority.read(backup, :all),
               true <- source_view.content == backup_view.content,
               true <- source_view.reconstructed == backup_view.reconstructed,
               :ok <- sync_snapshot(path, fault) do
            {:ok,
             %{
               path: path,
               content: backup_view.content,
               reconstruction: publication_reconstruction(backup_view.reconstructed)
             }}
          else
            false -> {:error, :backup_content_mismatch}
            {:error, reason} -> {:error, reason}
          end

        _ = Database.close(backup)
        result

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp sync_snapshot(path, fault) do
    with :ok <- sync_file(path, fault),
         :ok <- sync_directory(Path.dirname(path)) do
      :ok
    end
  end

  defp sync_file(path, fault) do
    case :file.open(String.to_charlist(path), [:read, :binary, :raw]) do
      {:ok, file} ->
        try do
          with :ok <- start_maintenance_fault(fault, :during_backup_sync, file) do
            :file.sync(file)
          end
        after
          _ = :file.close(file)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp sync_directory(path) do
    case :file.open(String.to_charlist(path), [:read, :raw, :directory]) do
      {:ok, directory} ->
        try do
          :file.sync(directory)
        after
          _ = :file.close(directory)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp publication_reconstruction(state) do
    bytes = :erlang.term_to_binary(state, [:deterministic])

    %{
      projection_count: map_size(state),
      sha256: Encoding.digest(bytes),
      state: state
    }
  end

  defp recovery_state(path, reason) do
    %{
      path: path,
      conn: nil,
      owner: nil,
      mode: :recovery,
      reason: reason,
      fault: nil,
      maintenance_fault: nil,
      capacity_probe: &Capacity.probe/1,
      capacity_probe_timeout_ms: @capacity_probe_timeout_ms,
      operational_health_requests: %{}
    }
  end

  defp get(map, key, default \\ nil)

  defp get(map, key, default) when is_atom(key),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))

  defp get(map, key, default) when is_binary(key), do: Map.get(map, key, default)
end
