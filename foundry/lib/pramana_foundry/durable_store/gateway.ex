defmodule PramanaFoundry.DurableStore.Gateway do
  @moduledoc """
  Protected, single-connection authority gateway.

  The caller supplies only semantic command data and a validated kernel proposal. SQL,
  the connection and protected table layout never cross this process boundary.
  """

  use GenServer

  alias PramanaFoundry.DurableStore.{Database, Encoding, Kernel, ProtectedVerifier}

  @command_keys ~w(schema_version command_id expected_revisions type target_ids payload)
  @command_types ~w(legacy_event_append enqueue steer pause resume cancel reset propose submit_artifact submit_review request_effect record_receipt)

  def initialize(path, opts \\ []), do: Database.initialize(path, opts)

  def migrate(path, opts \\ []) do
    with {:ok, owner} <- Owner.acquire(path, opts) do
      try do
        with {:ok, conn} <- Database.open(path) do
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
  def transact_verified(server, actor_id, command, proposal, protected_facts),
    do: GenServer.call(server, {:transact_verified, actor_id, command, proposal, protected_facts})

  def command(server, command_id), do: GenServer.call(server, {:command, command_id})
  def counts(server), do: GenServer.call(server, :counts)
  def backup(server, path), do: GenServer.call(server, {:backup, path}, :infinity)

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    path = Keyword.fetch!(opts, :path)

    case File.stat(path) do
      {:error, :enoent} ->
        {:ok, %{path: path, conn: nil, mode: :recovery, reason: :not_initialized, fault: nil}}

      {:ok, _stat} ->
        open(path, opts)

      {:error, reason} ->
        {:ok,
         %{path: path, conn: nil, mode: :recovery, reason: {:stat_failed, reason}, fault: nil}}
    end
  end

  @impl true
  def terminate(_reason, state), do: Database.close(state.conn)

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
        {:transact_verified, _actor_id, _command, _proposal, _facts},
        _from,
        %{mode: :recovery} = state
      ) do
    {:reply, {:error, {:recovery_mode, state.reason}}, state}
  end

  def handle_call({:transact_verified, actor_id, command, proposal, facts}, _from, state) do
    result =
      with :ok <- Kernel.validate_bundle(proposal),
           {:ok, protected} <- ProtectedVerifier.derive(proposal, facts) do
        do_transact(state.conn, actor_id, command, proposal, protected, state.fault)
      end

    next_state = transition_after_result(state, result)

    {:reply, result, next_state}
  end

  def handle_call({:command, _command_id}, _from, %{mode: :recovery} = state) do
    {:reply, {:error, {:recovery_mode, state.reason}}, state}
  end

  def handle_call({:command, command_id}, _from, state) do
    result = fetch_command(state.conn, command_id)

    case result do
      {:error, reason} when reason in [:corrupt_result, :unsupported_result_version] ->
        next = %{state | mode: :recovery, reason: {:corrupt_authority, reason}}
        {:reply, {:error, {:recovery_mode, next.reason}}, next}

      _other ->
        {:reply, result, state}
    end
  end

  def handle_call(:counts, _from, %{mode: :recovery} = state) do
    {:reply, {:error, {:recovery_mode, state.reason}}, state}
  end

  def handle_call(:counts, _from, state) do
    tables =
      ~w(inputs commands command_results events projections effects claims ledger_generations reservations)

    result =
      with {:ok, %{content: content}} <- Authority.read(state.conn, :all) do
        {:ok, Map.new(tables, &{&1, length(content[&1])})}
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

  defp open(path, opts) do
    case Database.open(path) do
      {:ok, conn} ->
        with :ok <- maybe_limit_pages(conn, Keyword.get(opts, :max_page_count)) do
          {:ok,
           %{path: path, conn: conn, mode: :ready, reason: nil, fault: Keyword.get(opts, :fault)}}
        else
          {:error, reason} ->
            Database.close(conn)
            {:ok, %{path: path, conn: nil, mode: :recovery, reason: reason, fault: nil}}
        end

      {:error, reason} ->
        {:ok, %{path: path, conn: nil, mode: :recovery, reason: reason, fault: nil}}
    end
  end

  defp do_transact(conn, actor_id, command, proposal, protected, fault) do
    with :ok <- validate_actor(actor_id),
         :ok <- validate_command(command),
         {:ok, canonical} <-
           Encoding.canonical(%{
             "domain" => "pramana-foundry-command-v1",
             "schema_version" => 1,
             "actor_id" => actor_id,
             "command" => command
           }),
         digest <- Encoding.digest(canonical),
         command_id <- get(command, "command_id") do
      case existing(conn, command_id, actor_id, digest) do
        {:ok, result} ->
          {:ok, result, :idempotent}

        {:error, :not_found} ->
          commit_bundle(conn, actor_id, command, canonical, digest, proposal, protected, fault)

        {:error, reason} ->
          {:error, reason}
      end
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
      with {:ok, encoded} <- RecordCodec.encode(:event, event) do
        Database.execute(
          conn,
          "INSERT INTO events(event_id, command_id, schema_version, event_type, event) VALUES (?, ?, 1, ?, ?)",
          [get(event, :event_id), command_id, get(event, :type), {:blob, encoded}]
        )
      end
    end)
  end

  defp insert_projections(conn, events, projections) do
    with {:ok, plan} <- RecordCodec.projection_plan(events, projections),
         {:ok, initial} <- projection_initial_state(conn, plan) do
      Enum.reduce_while(plan, {:ok, initial}, fn {_carrier, projection} = step, {:ok, state} ->
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
               Authority.read(conn, {:revision, {:projection, elem(key, 0), elem(key, 1)}}),
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
      case Authority.read(conn, {:revision, {:projection, namespace, entity_id}}) do
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
      Database.execute(
        conn,
        "INSERT INTO ledger_generations(generation_id, parent_generation_id, schema_version, revision, allocation, consumed) VALUES (?, ?, 1, 0, ?, ?)",
        [
          get(generation, :generation_id),
          get(generation, :parent_generation_id),
          get(generation, :allocation),
          get(generation, :consumed)
        ]
      )
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
    case Database.query(
           conn,
           "SELECT c.actor_id, c.request_digest, r.schema_version, r.disposition, r.reason_code, r.committed_seq, r.result FROM commands c JOIN command_results r ON r.command_id = c.command_id WHERE c.command_id = ?",
           [command_id]
         ) do
      {:ok, []} ->
        {:error, :not_found}

      {:ok, [[^actor_id, ^digest, schema, disposition, reason, committed_seq, encoded]]} ->
        decode_result(encoded, schema, disposition, reason, committed_seq)

      {:ok, [_row]} ->
        {:error, :idempotency_conflict}

      {:error, reason} ->
        {:error, {:storage_unavailable, reason}}
    end
  end

  defp fetch_command(conn, command_id) do
    case Database.query(
           conn,
           "SELECT schema_version, disposition, reason_code, committed_seq, result FROM command_results WHERE command_id = ?",
           [
             command_id
           ]
         ) do
      {:ok, [[schema, disposition, reason, committed_seq, encoded]]} ->
        decode_result(encoded, schema, disposition, reason, committed_seq)

      {:ok, []} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp decode_json(encoded) do
    value = encoded |> :json.decode() |> decoded_nulls()

    if is_map(value) and value["schema_version"] == 1,
      do: {:ok, value},
      else: {:error, :unsupported_result_version}
  rescue
    _ -> {:error, :corrupt_result}
  end

  defp decoded_nulls(:null), do: nil
  defp decoded_nulls(value) when is_list(value), do: Enum.map(value, &decoded_nulls/1)

  defp decoded_nulls(value) when is_map(value),
    do: Map.new(value, fn {key, item} -> {key, decoded_nulls(item)} end)

  defp decoded_nulls(value), do: value

  defp decode_result(encoded, schema, disposition, reason, committed_seq) do
    with {:ok, value} <- decode_json(encoded),
         true <-
           Map.keys(value) |> Enum.sort() ==
             ~w(committed_seq disposition reason_code schema_version),
         true <- value["schema_version"] == schema and schema == 1,
         true <-
           value["disposition"] == disposition and
             disposition in ["accepted", "rejected", "blocked"],
         true <- value["reason_code"] == reason,
         true <- is_nil(reason) or (is_binary(reason) and reason != ""),
         true <-
           value["committed_seq"] == committed_seq and is_integer(committed_seq) and
             committed_seq >= 0 do
      {:ok, value}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :corrupt_result}
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
    case String.split(key, "/", parts: 3) do
      ["projection", namespace, entity_id] ->
        read_optional_revision(
          conn,
          "SELECT revision FROM projections WHERE namespace = ? AND entity_id = ?",
          [decode_key(namespace), decode_key(entity_id)]
        )

      ["dependency", namespace, entity_id] ->
        read_optional_revision(
          conn,
          "SELECT revision FROM projections WHERE namespace = ? AND entity_id = ?",
          [decode_key(namespace), decode_key(entity_id)]
        )

      ["policy", encoded_id] ->
        read_optional_revision(
          conn,
          "SELECT revision FROM policy_revisions WHERE policy_revision_id = ?",
          [decode_key(encoded_id)]
        )

      ["control", encoded_id] ->
        read_optional_revision(
          conn,
          "SELECT revision FROM control_revisions WHERE control_id = ?",
          [decode_key(encoded_id)]
        )

      ["ledger", encoded_id] ->
        read_optional_revision(
          conn,
          "SELECT revision FROM ledger_generations WHERE generation_id = ?",
          [decode_key(encoded_id)]
        )

      _other ->
        {:error, {:unsupported_revision_key, key}}
    end
  rescue
    _ -> {:error, {:invalid_revision_key, key}}
  end

  defp read_optional_revision(conn, sql, params) do
    case Database.query(conn, sql, params) do
      {:ok, []} -> {:ok, "absent"}
      {:ok, [[revision]]} -> {:ok, revision}
      {:ok, rows} -> {:error, {:invalid_revision_rows, rows}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp projection_key(namespace, entity_id) do
    "projection/" <> encode_key(namespace) <> "/" <> encode_key(entity_id)
  end

  defp encode_key(value), do: Base.url_encode64(value, padding: false)
  defp decode_key(value), do: Base.url_decode64!(value, padding: false)

  defp validate_actor(actor_id) when is_binary(actor_id) and actor_id != "", do: :ok
  defp validate_actor(_actor_id), do: {:error, :invalid_actor}

  defp validate_command(command) when is_map(command) do
    keys = Map.keys(command)

    with true <- Enum.all?(keys, &is_binary/1),
         true <- Enum.sort(keys) == Enum.sort(@command_keys),
         1 <- get(command, "schema_version"),
         id when is_binary(id) and id != "" <- get(command, "command_id"),
         type when type in @command_types <- get(command, "type"),
         revisions when is_map(revisions) <- get(command, "expected_revisions"),
         targets when is_map(targets) <- get(command, "target_ids"),
         payload when is_map(payload) <- get(command, "payload"),
         {:ok, _canonical} <- Encoding.canonical(command) do
      :ok
    else
      1 -> {:error, :invalid_command}
      _ -> {:error, :invalid_command}
    end
  end

  defp validate_command(_command), do: {:error, :invalid_command}

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

      {:error, :corrupt_result} ->
        %{state | mode: :recovery, reason: {:corrupt_authority, :corrupt_result}}

      {:error, :unsupported_result_version} ->
        %{state | mode: :recovery, reason: {:corrupt_authority, :unsupported_result_version}}

      {:error, {:invalid_stored_body, _table, _rowid, _reason}} ->
        %{state | mode: :recovery, reason: {:corrupt_authority, result}}

      {:error, reason} when reason in [:projection_replay_mismatch, :invalid_projection_event] ->
        %{state | mode: :recovery, reason: {:corrupt_authority, reason}}

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
               reconstruction: backup_view.reconstructed
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

  if false do
  defp authoritative_content(conn) do
    tables = [
      {"metadata", "key"},
      {"inputs", "input_id"},
      {"commands", "command_id"},
      {"command_results", "command_id"},
      {"events", "seq"},
      {"projections", "namespace, entity_id"},
      {"effects", "effect_id"},
      {"claims", "claim_id"},
      {"receipts", "receipt_id"},
      {"leases", "lease_id"},
      {"ledger_generations", "generation_id"},
      {"reservations", "reservation_id"},
      {"policy_revisions", "policy_revision_id"},
      {"control_revisions", "control_id"},
      {"artifact_references", "artifact_id"},
      {"import_runs", "source_digest"},
      {"legacy_records", "source_digest, line_number"},
      {"sqlite_sequence", "name"}
    ]

    Enum.reduce_while(tables, {:ok, %{}}, fn {table, ordering}, {:ok, acc} ->
      case Database.query(conn, "SELECT * FROM #{table} ORDER BY #{ordering}") do
        {:ok, rows} ->
          digest =
            rows
            |> :erlang.term_to_binary([:deterministic])
            |> Encoding.digest()

          {:cont, {:ok, Map.put(acc, table, %{count: length(rows), sha256: digest})}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp validate_reconstruction(conn) do
    with {:ok, event_rows} <-
           Database.query(conn, "SELECT seq, event_id, command_id FROM events ORDER BY seq"),
         {:ok, result_rows} <-
           Database.query(
             conn,
             "SELECT command_id, committed_seq FROM command_results ORDER BY command_id"
           ),
         {:ok, projection_rows} <-
           Database.query(
             conn,
             "SELECT last_event_id FROM projections WHERE last_event_id IS NOT NULL ORDER BY namespace, entity_id"
           ) do
      event_ids = MapSet.new(event_rows, fn [_seq, event_id, _command_id] -> event_id end)
      max_seq = event_rows |> List.last([0, nil, nil]) |> hd()

      cond do
        not Enum.all?(result_rows, fn [_command_id, committed_seq] -> committed_seq <= max_seq end) ->
          {:error, :result_sequence_not_reconstructable}

        not Enum.all?(projection_rows, fn [event_id] -> MapSet.member?(event_ids, event_id) end) ->
          {:error, :projection_event_not_reconstructable}

        true ->
          :ok
      end
    end
  end

  defp reconstruction_evidence(conn) do
    with {:ok, event_rows} <- Database.query(conn, "SELECT event FROM events ORDER BY seq"),
         {:ok, reconstructed} <- replay_projection_events(event_rows),
         {:ok, projection_rows} <-
           Database.query(
             conn,
             "SELECT namespace, entity_id, revision, last_event_id, projection FROM projections ORDER BY namespace, entity_id"
           ),
         {:ok, stored} <- stored_projection_state(projection_rows),
         true <- reconstructed == stored do
      bytes = :erlang.term_to_binary(reconstructed, [:deterministic])
      {:ok, %{projection_count: map_size(reconstructed), sha256: Encoding.digest(bytes)}}
    else
      false -> {:error, :projection_replay_mismatch}
      {:error, reason} -> {:error, reason}
    end
  end

  defp replay_projection_events(event_rows) do
    Enum.reduce_while(event_rows, {:ok, %{}}, fn [bytes], {:ok, state} ->
      with {:ok, event} <- decode_json(bytes) do
        case get(get(event, :payload, %{}), :projection) do
          nil ->
            {:cont, {:ok, state}}

          projection when is_map(projection) ->
            namespace = get(projection, :namespace)
            entity_id = get(projection, :entity_id)
            revision = get(projection, :revision)
            value = get(projection, :value)
            key = {namespace, entity_id}

            expected_revision =
              case Map.get(state, key) do
                nil -> 0
                previous -> previous.revision + 1
              end

            if is_binary(namespace) and is_binary(entity_id) and is_integer(revision) and
                 revision == expected_revision and is_map(value) do
              next = %{revision: revision, last_event_id: get(event, :event_id), value: value}
              {:cont, {:ok, Map.put(state, key, next)}}
            else
              {:halt, {:error, :invalid_projection_event}}
            end

          _other ->
            {:halt, {:error, :invalid_projection_event}}
        end
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp stored_projection_state(rows) do
    Enum.reduce_while(rows, {:ok, %{}}, fn [namespace, entity_id, revision, last_event_id, bytes],
                                           {:ok, state} ->
      with {:ok, projection} <- decode_json(bytes),
           value when is_map(value) <- get(projection, :value) do
        entry = %{revision: revision, last_event_id: last_event_id, value: value}
        {:cont, {:ok, Map.put(state, {namespace, entity_id}, entry)}}
      else
        _ -> {:halt, {:error, :invalid_projection_body}}
      end
    end)
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

  defp key_for(map, key) do
    if Enum.any?(Map.keys(map), &is_binary/1), do: Atom.to_string(key), else: key
  end

  defp get(map, key, default \\ nil)

  defp get(map, key, default) when is_atom(key),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))

  defp get(map, key, default) when is_binary(key), do: Map.get(map, key, default)
end
