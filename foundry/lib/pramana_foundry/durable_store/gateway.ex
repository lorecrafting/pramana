defmodule PramanaFoundry.DurableStore.Gateway do
  @moduledoc """
  Protected, single-connection authority gateway.

  The caller supplies only semantic command data and a validated kernel proposal. SQL,
  the connection and protected table layout never cross this process boundary.
  """

  use GenServer

  alias PramanaFoundry.DurableStore.{Database, Encoding, Kernel}

  @command_keys ~w(schema_version command_id expected_revisions type target_ids payload)

  def initialize(path, opts \\ []), do: Database.initialize(path, opts)

  def start_link(opts) do
    {gen_opts, init_opts} = Keyword.split(opts, [:name])
    GenServer.start_link(__MODULE__, init_opts, gen_opts)
  end

  def status(server), do: GenServer.call(server, :status)
  def transact(server, actor_id, command, proposal), do: GenServer.call(server, {:transact, actor_id, command, proposal})
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
        {:ok, %{path: path, conn: nil, mode: :recovery, reason: {:stat_failed, reason}, fault: nil}}
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
    result = do_transact(state.conn, actor_id, command, proposal, state.fault)
    next_state = if storage_failure?(result), do: %{state | mode: :recovery, reason: result}, else: state
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
    tables = ~w(inputs commands command_results events projections effects claims ledger_generations reservations)

    result =
      Enum.reduce_while(tables, {:ok, %{}}, fn table, {:ok, acc} ->
        case Database.query(state.conn, "SELECT count(*) FROM #{table}") do
          {:ok, [[count]]} -> {:cont, {:ok, Map.put(acc, table, count)}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    {:reply, result, state}
  end

  def handle_call({:backup, _path}, _from, %{mode: :recovery} = state) do
    {:reply, {:error, {:recovery_mode, state.reason}}, state}
  end

  def handle_call({:backup, path}, _from, state) do
    result = backup_database(state.conn, path)
    {:reply, result, state}
  end

  defp open(path, opts) do
    case Database.open(path) do
      {:ok, conn} ->
        with :ok <- maybe_limit_pages(conn, Keyword.get(opts, :max_page_count)) do
          {:ok, %{path: path, conn: conn, mode: :ready, reason: nil, fault: Keyword.get(opts, :fault)}}
        else
          {:error, reason} ->
            Database.close(conn)
            {:ok, %{path: path, conn: nil, mode: :recovery, reason: reason, fault: nil}}
        end

      {:error, reason} ->
        {:ok, %{path: path, conn: nil, mode: :recovery, reason: reason, fault: nil}}
    end
  end

  defp do_transact(conn, actor_id, command, proposal, fault) do
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
        {:ok, result} -> {:ok, result, :idempotent}
        {:error, :not_found} -> commit_bundle(conn, actor_id, command, canonical, digest, proposal, fault)
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp commit_bundle(conn, actor_id, command, canonical, digest, proposal, fault) do
    with :ok <- Kernel.validate_bundle(proposal) do
      transaction_result =
        Database.transaction(conn, fn ->
          with :ok <- check_expected_revisions(conn, command, proposal, protected),
               :ok <- inject(fault, :before_write),
               :ok <- insert_input(conn, actor_id, command, canonical, digest),
               :ok <- insert_command(conn, actor_id, command, digest),
               :ok <- insert_events(conn, get(proposal, :events, []), get(command, "command_id")),
               :ok <- insert_projections(conn, get(proposal, :projections, [])),
               :ok <- insert_intents(conn, get(proposal, :intents, []), get(command, "command_id")),
               :ok <- insert_generations(conn, get(proposal, :ledger_generations, [])),
               :ok <- insert_claims(conn, get(proposal, :claims, [])),
               :ok <- insert_reservations(conn, get(proposal, :reservations, [])),
               :ok <- inject(fault, :before_commit),
               {:ok, committed_seq} <- current_seq(conn),
               {:ok, result} <- insert_result(conn, get(command, "command_id"), get(proposal, :result), committed_seq) do
            {:ok, result}
          end
        end)

      case transaction_result do
        {:ok, result} ->
          case fault do
            :after_commit_before_reply ->
              {:error, {:outcome_unknown, get(command, "command_id")}}

            {:halt, :after_commit} ->
              System.halt(72)

            _other ->
              {:ok, result, :committed}
          end

        {:error, reason} ->
          if constraint_failure?(reason),
            do: {:error, {:bundle_rejected, reason}},
            else: {:error, {:storage_unavailable, reason}}
      end
    end
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
      [get(command, "command_id"), "input:" <> get(command, "command_id"), actor_id, digest, get(command, "type")]
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

  defp insert_projections(conn, projections) do
    reduce_insert(projections, fn projection ->
      with :ok <- check_projection_revision(conn, projection),
           {:ok, encoded} <- RecordCodec.encode(:projection, projection) do
        expected = get(projection, :expected_revision)

        if expected == -1 do
          Database.execute(
            conn,
            "INSERT INTO projections(namespace, entity_id, schema_version, revision, last_event_id, projection) VALUES (?, ?, 1, ?, ?, ?)",
            [get(projection, :namespace), get(projection, :entity_id), get(projection, :revision), get(projection, :last_event_id), {:blob, encoded}]
          )
        else
          Database.execute(
            conn,
            "UPDATE projections SET revision = ?, last_event_id = ?, projection = ? WHERE namespace = ? AND entity_id = ? AND revision = ?",
            [get(projection, :revision), get(projection, :last_event_id), {:blob, encoded}, get(projection, :namespace), get(projection, :entity_id), expected]
          )
        end
      end
    end)
  end

  defp check_projection_revision(conn, projection) do
    expected = get(projection, :expected_revision)

    case Database.query(conn, "SELECT revision FROM projections WHERE namespace = ? AND entity_id = ?", [get(projection, :namespace), get(projection, :entity_id)]) do
      {:ok, []} when expected == -1 -> :ok
      {:ok, [[revision]]} when revision == expected -> :ok
      {:ok, rows} -> {:error, {:revision_conflict, rows}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp insert_intents(conn, intents, command_id) do
    reduce_insert(intents, fn intent ->
      with {:ok, encoded} <- RecordCodec.encode(:intent, intent) do
        Database.execute(
          conn,
          "INSERT INTO effects(effect_id, command_id, schema_version, request_digest, status, intent) VALUES (?, ?, 1, ?, ?, ?)",
          [get(intent, :effect_id), command_id, get(intent, :request_digest), get(intent, :status), {:blob, encoded}]
        )
      end
    end)
  end

  defp insert_generations(conn, generations) do
    reduce_insert(generations, fn generation ->
      Database.execute(
        conn,
        "INSERT INTO ledger_generations(generation_id, parent_generation_id, schema_version, revision, allocation, consumed) VALUES (?, ?, 1, 0, ?, ?)",
        [get(generation, :generation_id), get(generation, :parent_generation_id), get(generation, :allocation), get(generation, :consumed)]
      )
    end)
  end

  defp insert_claims(conn, claims) do
    reduce_insert(claims, fn claim ->
      with {:ok, encoded} <- RecordCodec.encode(:claim, claim) do
        Database.execute(
          conn,
          "INSERT INTO claims(claim_id, effect_id, writer_epoch, status, claim) VALUES (?, ?, ?, ?, ?)",
          [get(claim, :claim_id), get(claim, :effect_id), get(claim, :writer_epoch), get(claim, :status), {:blob, encoded}]
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
          [get(reservation, :reservation_id), get(reservation, :generation_id), get(reservation, :claim_id), get(reservation, :dimension), get(reservation, :units), get(reservation, :status), {:blob, encoded}]
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
             [command_id, get(result, :disposition), get(result, :reason_code), {:blob, encoded}, committed_seq]
           ) do
      RecordCodec.decode(:result, encoded)
    end
  end

  defp existing(conn, command_id, actor_id, digest) do
    case Database.query(
           conn,
           "SELECT c.actor_id, c.request_digest, r.result FROM commands c JOIN command_results r ON r.command_id = c.command_id WHERE c.command_id = ?",
           [command_id]
         ) do
      {:ok, []} -> {:error, :not_found}
      {:ok, [[^actor_id, ^digest, encoded]]} -> decode_json(encoded)
      {:ok, [_row]} -> {:error, :idempotency_conflict}
      {:error, reason} -> {:error, {:storage_unavailable, reason}}
    end
  end

  defp fetch_command(conn, command_id) do
    case Database.query(conn, "SELECT result FROM command_results WHERE command_id = ?", [command_id]) do
      {:ok, [[encoded]]} -> decode_json(encoded)
      {:ok, []} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
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
  defp decoded_nulls(value) when is_map(value), do: Map.new(value, fn {key, item} -> {key, decoded_nulls(item)} end)
  defp decoded_nulls(value), do: value

  defp current_seq(conn) do
    case Database.query(conn, "SELECT coalesce(max(seq), 0) FROM events") do
      {:ok, [[seq]]} -> {:ok, seq}
      {:error, reason} -> {:error, reason}
    end
  end

  defp check_expected_revisions(conn, command, proposal, protected) do
    expected = get(command, "expected_revisions")
    required = required_projection_reads(proposal) |> Map.merge(get(protected, :required_revisions, %{}))

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
        read_optional_revision(conn, "SELECT revision FROM policy_revisions WHERE policy_revision_id = ?", [decode_key(encoded_id)])

      ["control", encoded_id] ->
        read_optional_revision(conn, "SELECT revision FROM control_revisions WHERE control_id = ?", [decode_key(encoded_id)])

      ["ledger", encoded_id] ->
        read_optional_revision(conn, "SELECT revision FROM ledger_generations WHERE generation_id = ?", [decode_key(encoded_id)])

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
         type when is_binary(type) and type != "" <- get(command, "type"),
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
  defp inject(_fault, _point), do: :ok

  defp storage_failure?({:error, {:storage_unavailable, _reason}}), do: true
  defp storage_failure?(_result), do: false

  defp constraint_failure?(reason) do
    message = inspect(reason)
    String.contains?(message, "constraint failed") or String.contains?(message, "UNIQUE constraint")
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
    cond do
      File.exists?(path) ->
        {:error, :backup_exists}

      not absolute_clean_path?(path) ->
        {:error, :invalid_backup_path}

      true ->
        escaped = String.replace(path, "'", "''")

        with :ok <- Database.execute(conn, "VACUUM INTO '#{escaped}'") do
          verify_backup(conn, path)
        end
    end
  end

  defp verify_backup(source, path) do
    case Database.open(path) do
      {:ok, backup} ->
        result =
          with {:ok, source_content} <- authoritative_content(source),
               {:ok, backup_content} <- authoritative_content(backup),
               true <- source_content == backup_content do
            {:ok, %{path: path, content: backup_content}}
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

  defp authoritative_content(conn) do
    tables = ~w(inputs commands command_results events projections effects claims ledger_generations reservations legacy_records)

    Enum.reduce_while(tables, {:ok, %{}}, fn table, {:ok, acc} ->
      case Database.query(conn, "SELECT * FROM #{table} ORDER BY rowid") do
        {:ok, rows} ->
          digest =
            rows
            |> :erlang.term_to_binary([:deterministic])
            |> Encoding.digest()

          {:cont, {:ok, Map.put(acc, table, %{count: length(rows), sha256: digest})}}

        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp absolute_clean_path?(path) do
    Path.type(path) == :absolute and Path.expand(path) == path and Path.basename(path) not in ["", ".", ".."]
  end

  defp key_for(map, key) do
    if Enum.any?(Map.keys(map), &is_binary/1), do: Atom.to_string(key), else: key
  end

  defp get(map, key, default \\ nil)
  defp get(map, key, default) when is_atom(key), do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  defp get(map, key, default) when is_binary(key), do: Map.get(map, key, default)
end
