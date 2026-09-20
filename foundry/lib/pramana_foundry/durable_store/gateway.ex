defmodule PramanaFoundry.DurableStore.Gateway do
  @moduledoc """
  Protected, single-connection authority gateway.

  The caller supplies only semantic command data and a validated kernel proposal. SQL,
  the connection and protected table layout never cross this process boundary.
  """

  use GenServer

  alias PramanaFoundry.DurableStore.{
    Authority,
    Database,
    Encoding,
    Kernel,
    Owner,
    PathIdentity,
    ProtectedVerifier,
    RecordCodec
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
  def counts(server), do: GenServer.call(server, :counts)
  def backup(server, path), do: GenServer.call(server, {:backup, path}, :infinity)

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    path = Keyword.fetch!(opts, :path)

    case PathIdentity.existing(path) do
      {:error, :database_not_found} ->
        {:ok,
         %{
           path: path,
           conn: nil,
           owner: nil,
           mode: :recovery,
           reason: :not_initialized,
           fault: nil
         }}

      {:ok, identity} ->
        open(identity, opts)

      {:error, reason} ->
        {:ok,
         %{
           path: path,
           conn: nil,
           owner: nil,
           mode: :recovery,
           reason: reason,
           fault: nil
         }}
    end
  end

  @impl true
  def terminate(_reason, state) do
    _ = Database.close(state.conn)
    if state.owner, do: Owner.release(state.owner)
    :ok
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, %{mode: state.mode, reason: state.reason, path: state.path}, state}
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
        do_verified_transact(state.conn, actor_id, command, proposal, facts, state.fault)
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
    result = backup_database(state.conn, path)
    {:reply, result, transition_after_result(state, result)}
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
               protected_capability:
                 Keyword.get_lazy(opts, :protected_capability, fn -> make_ref() end)
             }}
          else
            {:error, reason} ->
              Database.close(conn)
              Owner.release(owner)

              {:ok,
               %{path: path, conn: nil, owner: nil, mode: :recovery, reason: reason, fault: nil}}
          end

        {:error, reason} ->
          Owner.release(owner)

          {:ok,
           %{
             path: path,
             conn: nil,
             owner: nil,
             mode: :recovery,
             reason: reason,
             fault: nil
           }}
      end
    else
      {:error, reason} ->
        {:ok, %{path: path, conn: nil, owner: nil, mode: :recovery, reason: reason, fault: nil}}
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
         fault
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

  defp commit_rejected_command(conn, actor_id, command, canonical, digest, reason) do
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
    case Database.query(conn, "PRAGMA max_page_count = #{pages}") do
      {:ok, [[actual]]} when actual <= pages -> :ok
      {:ok, rows} -> {:error, {:page_limit_failed, rows}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_limit_pages(_conn, _pages), do: {:error, :invalid_page_limit}

  defp backup_database(conn, path) do
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
         false <- PathIdentity.collision?(source, target),
         escaped <- String.replace(target.path, "'", "''"),
         :ok <- Database.execute(conn, "VACUUM INTO '#{escaped}'"),
         {:ok, snapshot} <- PathIdentity.existing(target.path) do
      verify_backup(snapshot, source_view)
    else
      {:error, :target_exists} -> {:error, :backup_exists}
      true -> {:error, :backup_path_collision}
      {:error, reason} -> {:error, reason}
    end
  end

  defp verify_backup(snapshot, source_view) do
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
               :ok <- sync_snapshot(path) do
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

  defp sync_snapshot(path) do
    with {:ok, file} <- :file.open(String.to_charlist(path), [:read, :binary, :raw]),
         :ok <- :file.sync(file),
         :ok <- :file.close(file),
         {:ok, directory} <-
           :file.open(String.to_charlist(Path.dirname(path)), [:read, :raw, :directory]),
         :ok <- :file.sync(directory),
         :ok <- :file.close(directory) do
      :ok
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

  defp get(map, key, default \\ nil)

  defp get(map, key, default) when is_atom(key),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))

  defp get(map, key, default) when is_binary(key), do: Map.get(map, key, default)
end
