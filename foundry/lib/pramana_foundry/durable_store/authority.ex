defmodule PramanaFoundry.DurableStore.Authority do
  @moduledoc false

  alias PramanaFoundry.DurableStore.{Database, Encoding, LegacyLine, RecordCodec}

  @registry [
    {"metadata", "key", ~w(key value)},
    {"inputs", "input_id", ~w(input_id actor_id request_digest canonical_request protocol_version)},
    {"commands", "command_id", ~w(command_id input_id actor_id request_digest command_type protocol_version)},
    {"command_results", "command_id", ~w(command_id schema_version disposition reason_code result committed_seq)},
    {"events", "seq", ~w(seq event_id command_id schema_version event_type event)},
    {"projections", "namespace, entity_id", ~w(namespace entity_id schema_version revision last_event_id projection)},
    {"effects", "effect_id", ~w(effect_id command_id schema_version request_digest status intent)},
    {"ledger_generations", "generation_id", ~w(generation_id parent_generation_id schema_version revision allocation consumed)},
    {"claims", "claim_id", ~w(claim_id effect_id writer_epoch status claim)},
    {"reservations", "reservation_id", ~w(reservation_id generation_id claim_id dimension units status reservation)},
    {"receipts", "receipt_id", ~w(receipt_id effect_id request_id schema_version receipt)},
    {"leases", "lease_id", ~w(lease_id claim_id schema_version lease)},
    {"policy_revisions", "policy_revision_id", ~w(policy_revision_id command_id schema_version revision policy)},
    {"control_revisions", "control_id", ~w(control_id command_id schema_version revision control)},
    {"artifact_references", "artifact_id", ~w(artifact_id command_id schema_version digest reference)},
    {"import_runs", "source_digest", ~w(source_digest source_path archived_path source_bytes line_count valid_count invalid_count manifest)},
    {"legacy_records", "source_digest, line_number", ~w(source_digest line_number byte_start byte_end record_digest valid error raw_record)},
    {"sqlite_sequence", "name", ~w(name seq)}
  ]

  @unsupported ~w(receipts leases policy_revisions control_revisions artifact_references)
  @required_indexes ~w(one_active_claim_per_effect events_command_idx effects_command_idx reservations_generation_idx)

  def registry, do: @registry

  def read(conn, :all) do
    with :ok <- validate_schema(conn),
         {:ok, content} <- content(conn),
         {:ok, view} <- validate_content(content) do
      {:ok, Map.put(view, :content, content)}
    end
  end

  def read(conn, {:command, command_id}) when is_binary(command_id) and command_id != "" do
    with {:ok, command_rows} <-
           query(
             conn,
             "SELECT command_id, input_id, actor_id, request_digest, command_type, protocol_version FROM commands WHERE command_id = ?",
             [command_id]
           ) do
      case command_rows do
        [] -> {:ok, :absent}
        [row] -> read_command_closure(conn, row)
        _ -> corrupt("commands", command_id, :duplicate_identity)
      end
    end
  end

  def read(conn, {:revision, {:projection, namespace, entity_id}}),
    do: read_projection(conn, namespace, entity_id)

  def read(conn, {:revision, {:dependency, namespace, entity_id}}),
    do: read_projection(conn, namespace, entity_id)

  def read(conn, {:revision, {:ledger, generation_id}}),
    do: read_ledger(conn, generation_id)

  def read(conn, {:revision, {kind, id}}) when kind in [:policy, :control] do
    {table, column} =
      if kind == :policy,
        do: {"policy_revisions", "policy_revision_id"},
        else: {"control_revisions", "control_id"}

    with {:ok, rows} <- query(conn, "SELECT * FROM #{table} WHERE #{column} = ?", [id]) do
      case rows do
        [] -> {:ok, :absent}
        _ -> corrupt(table, id, :unsupported_retained_authority)
      end
    end
  end

  def read(conn, {:import, digest}) when is_binary(digest) do
    with {:ok, rows} <-
           query(
             conn,
             "SELECT source_digest, source_path, archived_path, source_bytes, line_count, valid_count, invalid_count, manifest FROM import_runs WHERE source_digest = ?",
             [digest]
           ) do
      case rows do
        [] -> {:ok, :absent}
        [row] -> validate_import_group(conn, row)
        _ -> corrupt("import_runs", digest, :duplicate_identity)
      end
    end
  end

  def read(conn, {:touched, %{command_id: command_id} = touched}) do
    with {:ok, command_view} <- read(conn, {:command, command_id}),
         true <- command_view != :absent,
         :ok <- validate_touched_revisions(conn, Map.get(touched, :revisions, [])) do
      {:ok, command_view}
    else
      false -> corrupt("commands", command_id, :missing_after_write)
      {:error, _reason} = error -> error
    end
  end

  def read(_conn, scope), do: corrupt("authority", inspect(scope), :unsupported_read_scope)

  def content(conn) do
    Enum.reduce_while(@registry, {:ok, %{}}, fn {table, ordering, _columns}, {:ok, acc} ->
      case stream_rows(conn, "SELECT * FROM #{table} ORDER BY #{ordering}") do
        {:ok, rows} -> {:cont, {:ok, Map.put(acc, table, rows)}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp validate_schema(conn) do
    expected = Enum.map(@registry, &elem(&1, 0)) |> MapSet.new()

    with {:ok, table_rows} <-
           query(
             conn,
             "SELECT name FROM sqlite_schema WHERE type='table' ORDER BY name"
           ),
         actual <- MapSet.new(table_rows, fn [name] -> name end),
         true <- actual == expected,
         :ok <- validate_table_shapes(conn),
         {:ok, index_rows} <-
           query(
             conn,
             "SELECT name FROM sqlite_schema WHERE type='index' AND sql IS NOT NULL ORDER BY name"
           ),
         index_names <- MapSet.new(index_rows, fn [name] -> name end),
         true <- Enum.all?(@required_indexes, &MapSet.member?(index_names, &1)) do
      :ok
    else
      false -> corrupt("sqlite_schema", "inventory", :schema_mismatch)
      {:error, _reason} = error -> error
    end
  end

  defp validate_table_shapes(conn) do
    Enum.reduce_while(@registry, :ok, fn
      {"sqlite_sequence", _ordering, columns}, :ok ->
        validate_columns(conn, "sqlite_sequence", columns, false)

      {table, _ordering, columns}, :ok ->
        validate_columns(conn, table, columns, true)
    end)
  end

  defp validate_columns(conn, table, expected, strict?) do
    with {:ok, column_rows} <- query(conn, "PRAGMA table_info('#{table}')"),
         ^expected <- Enum.map(column_rows, fn [_cid, name | _] -> name end),
         {:ok, table_rows} <- query(conn, "PRAGMA table_list('#{table}')"),
         true <- valid_table_list?(table_rows, strict?) do
      {:cont, :ok}
    else
      _ -> {:halt, corrupt_value(table, "schema", :schema_mismatch)}
    end
  end

  defp valid_table_list?([[_schema, _name, "table", _ncol, _wr, strict]], expected),
    do: strict == if(expected, do: 1, else: 0)

  defp valid_table_list?(_rows, _expected), do: false

  defp validate_content(content) do
    with :ok <- validate_metadata(content["metadata"]),
         :ok <- validate_unsupported(content),
         {:ok, commands} <- decode_commands(content),
         {:ok, events} <- decode_events(content["events"]),
         :ok <- validate_sequence(events, content["sqlite_sequence"]),
         {:ok, projections} <- decode_projections(content["projections"]),
         {:ok, effects} <- decode_effects(content["effects"]),
         {:ok, ledgers} <- decode_ledgers(content["ledger_generations"]),
         {:ok, claims} <- decode_claims(content["claims"]),
         {:ok, reservations} <- decode_reservations(content["reservations"]),
         :ok <- validate_command_relations(commands, events, effects),
         :ok <- validate_event_owners(events, commands),
         :ok <- validate_protected(effects, ledgers, claims, reservations),
         {:ok, reconstructed} <- validate_reconstruction(events, projections),
         {:ok, imports} <- validate_imports_from_content(content) do
      {:ok,
       %{
         commands: commands,
         events: events,
         projections: projections,
         reconstructed: reconstructed,
         effects: effects,
         ledgers: ledgers,
         claims: claims,
         reservations: reservations,
         imports: imports
       }}
    end
  end

  defp validate_metadata(rows) do
    allowed =
      MapSet.new(~w(schema_version protocol_version event_version projection_version installation_id repository_id migration_v1))

    values = Map.new(rows, fn [key, value] -> {key, value} end)

    cond do
      length(rows) != map_size(values) -> corrupt_value("metadata", "keys", :duplicate_key)
      not MapSet.subset?(MapSet.new(Map.keys(values)), allowed) ->
        corrupt_value("metadata", "keys", :unknown_key)
      Enum.any?(~w(schema_version protocol_version event_version projection_version), &(values[&1] != "1")) ->
        corrupt_value("metadata", "versions", :unsupported_version)
      not valid_identity?(values["installation_id"]) or not valid_identity?(values["repository_id"]) ->
        corrupt_value("metadata", "identity", :invalid_identity)
      Map.has_key?(values, "migration_v1") and values["migration_v1"] != "complete" ->
        corrupt_value("metadata", "migration_v1", :invalid_migration_state)
      true -> :ok
    end
  end

  defp validate_unsupported(content) do
    case Enum.find(@unsupported, &(content[&1] != [])) do
      nil -> :ok
      table -> corrupt_value(table, "retained", :unsupported_retained_authority)
    end
  end

  defp decode_commands(content) do
    inputs = Map.new(content["inputs"], fn [id, actor, digest, bytes, protocol] -> {id, {actor, digest, bytes, protocol}} end)
    results = Map.new(content["command_results"], fn [id, schema, disposition, reason, bytes, seq] -> {id, {schema, disposition, reason, bytes, seq}} end)

    if map_size(inputs) != length(content["inputs"]) or map_size(results) != length(content["command_results"]) do
      corrupt("commands", "relations", :duplicate_identity)
    else
      Enum.reduce_while(content["commands"], {:ok, %{}}, fn [id, input_id, actor, digest, type, protocol], {:ok, acc} ->
        with {:ok, {input_actor, input_digest, request, input_protocol}} <- required(inputs, input_id, "inputs", input_id),
             {:ok, {schema, disposition, reason, result, seq}} <- required(results, id, "command_results", id),
             true <- actor == input_actor and digest == input_digest and protocol == input_protocol,
             {:ok, request_value} <- bound("inputs", input_id, :command_request, request, %{
               input_id: input_id, actor_id: actor, request_digest: digest,
               protocol_version: protocol, command_id: id, command_type: type
             }),
             {:ok, result_value} <- bound("command_results", id, :result, result, %{
               schema_version: schema, disposition: disposition, reason_code: reason,
               committed_seq: seq
             }) do
          value = %{id: id, input_id: input_id, actor_id: actor, digest: digest, type: type,
                    protocol: protocol, request: request_value, result: result_value}
          {:cont, {:ok, Map.put(acc, id, value)}}
        else
          false -> {:halt, corrupt("commands", id, :binding_mismatch)}
          {:error, _reason} = error -> {:halt, error}
        end
      end)
      |> then(fn
        {:ok, commands} when map_size(commands) == length(content["commands"]) and
                              map_size(inputs) == map_size(commands) and
                              map_size(results) == map_size(commands) -> {:ok, commands}
        {:ok, _commands} -> corrupt("commands", "cardinality", :required_relation_missing)
        error -> error
      end)
    end
  end

  defp decode_events(rows) do
    Enum.reduce_while(rows, {:ok, []}, fn [seq, id, command_id, schema, type, bytes], {:ok, acc} ->
      case bound("events", id, :event, bytes, %{schema_version: schema, event_id: id, type: type}) do
        {:ok, value} -> {:cont, {:ok, [%{seq: seq, id: id, command_id: command_id, value: value} | acc]}}
        error -> {:halt, error}
      end
    end)
    |> reverse_ok()
  end

  defp decode_projections(rows) do
    Enum.reduce_while(rows, {:ok, %{}}, fn [namespace, entity_id, schema, revision, last_event_id, bytes], {:ok, acc} ->
      columns = %{namespace: namespace, entity_id: entity_id, schema_version: schema,
                  revision: revision, last_event_id: last_event_id}
      case bound("projections", {namespace, entity_id}, :projection, bytes, columns) do
        {:ok, value} ->
          entry = %{revision: revision, last_event_id: last_event_id, value: value["value"]}
          {:cont, {:ok, Map.put(acc, {namespace, entity_id}, entry)}}
        error -> {:halt, error}
      end
    end)
  end

  defp decode_effects(rows) do
    decode_bound_map(rows, "effects", fn [id, command_id, schema, digest, status, bytes] ->
      with {:ok, value} <- bound("effects", id, :intent, bytes, %{effect_id: id,
             schema_version: schema, request_digest: digest, status: status}) do
        {:ok, id, %{id: id, command_id: command_id, value: value}}
      end
    end)
  end

  defp decode_ledgers(rows) do
    decode_bound_map(rows, "ledger_generations", fn [id, parent, schema, revision, allocation, consumed] ->
      value = %{"schema_version" => schema, "generation_id" => id,
                "parent_generation_id" => parent, "revision" => revision,
                "allocation" => allocation, "consumed" => consumed}
      columns = %{generation_id: id, parent_generation_id: parent, schema_version: schema,
                  revision: revision, allocation: allocation, consumed: consumed}
      with {:ok, decoded} <- bound_value("ledger_generations", id, :ledger_generation, value, columns) do
        {:ok, id, decoded}
      end
    end)
  end

  defp decode_claims(rows) do
    decode_bound_map(rows, "claims", fn [id, effect_id, epoch, status, bytes] ->
      with {:ok, value} <- bound("claims", id, :claim, bytes, %{schema_version: 1,
             claim_id: id, effect_id: effect_id, writer_epoch: epoch, status: status}) do
        {:ok, id, %{id: id, effect_id: effect_id, value: value}}
      end
    end)
  end

  defp decode_reservations(rows) do
    decode_bound_map(rows, "reservations", fn [id, generation_id, claim_id, dimension, units, status, bytes] ->
      with {:ok, value} <- bound("reservations", id, :reservation, bytes, %{
             schema_version: 1, reservation_id: id, generation_id: generation_id,
             claim_id: claim_id, dimension: dimension, units: units, status: status}) do
        {:ok, id, %{id: id, generation_id: generation_id, claim_id: claim_id, units: units, value: value}}
      end
    end)
  end

  defp decode_bound_map(rows, table, fun) do
    Enum.reduce_while(rows, {:ok, %{}}, fn row, {:ok, acc} ->
      case fun.(row) do
        {:ok, id, value} when not is_map_key(acc, id) -> {:cont, {:ok, Map.put(acc, id, value)}}
        {:ok, id, _value} -> {:halt, corrupt(table, id, :duplicate_identity)}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp validate_sequence(events, rows) do
    seqs = Enum.map(events, & &1.seq)
    max_seq = List.last(seqs, 0)

    cond do
      seqs != Enum.to_list(1..max_seq//1) and seqs != [] ->
        corrupt_value("events", "sequence", :sequence_gap)
      events == [] and rows == [] -> :ok
      events != [] and rows == [["events", max_seq]] -> :ok
      true -> corrupt_value("sqlite_sequence", "events", :invalid_sequence)
    end
  end

  defp validate_command_relations(commands, events, effects) do
    max_seq = events |> List.last(%{seq: 0}) |> Map.fetch!(:seq)
    grouped_events = Enum.group_by(events, & &1.command_id)
    grouped_effects = Enum.group_by(Map.values(effects), & &1.command_id)

    Enum.reduce_while(commands, :ok, fn {id, command}, :ok ->
      owned_events = Map.get(grouped_events, id, [])
      owned_effects = Map.get(grouped_effects, id, [])
      disposition = command.result["disposition"]
      committed_seq = command.result["committed_seq"]
      seqs = Enum.map(owned_events, & &1.seq)

      valid =
        committed_seq >= 0 and committed_seq <= max_seq and
          (seqs == [] or (contiguous?(seqs) and committed_seq == List.last(seqs))) and
          (disposition == "accepted" or (owned_events == [] and owned_effects == []))

      if valid, do: {:cont, :ok}, else: {:halt, corrupt("command_results", id, :invalid_sequence_or_disposition)}
    end)
  end

  defp validate_event_owners(events, commands) do
    case Enum.find(events, &(not Map.has_key?(commands, &1.command_id))) do
      nil -> :ok
      event -> corrupt_value("events", event.id, :missing_command)
    end
  end

  defp validate_protected(effects, ledgers, claims, reservations) do
    with :ok <- validate_claim_relations(effects, claims, reservations),
         :ok <- validate_reservation_relations(ledgers, claims, reservations),
         :ok <- validate_ledger_funding(ledgers, reservations) do
      :ok
    end
  end

  defp validate_claim_relations(effects, claims, reservations) do
    Enum.reduce_while(claims, :ok, fn {id, claim}, :ok ->
      owned = Enum.filter(reservations, fn {_rid, row} -> row.claim_id == id end)
      if Map.has_key?(effects, claim.effect_id) and length(owned) == 1,
        do: {:cont, :ok},
        else: {:halt, corrupt("claims", id, :required_relation_missing)}
    end)
  end

  defp validate_reservation_relations(ledgers, claims, reservations) do
    Enum.reduce_while(reservations, :ok, fn {id, row}, :ok ->
      valid = Map.has_key?(ledgers, row.generation_id) and Map.has_key?(claims, row.claim_id)
      if valid, do: {:cont, :ok}, else: {:halt, corrupt("reservations", id, :required_relation_missing)}
    end)
  end

  defp validate_ledger_funding(ledgers, reservations) do
    Enum.reduce_while(ledgers, :ok, fn {id, ledger}, :ok ->
      reserved = reservations |> Map.values() |> Enum.filter(&(&1.generation_id == id)) |> Enum.sum_by(& &1.units)
      if reserved == ledger["allocation"] - ledger["consumed"],
        do: {:cont, :ok},
        else: {:halt, corrupt("ledger_generations", id, :funding_mismatch)}
    end)
  end

  defp validate_reconstruction(events, stored) do
    values = Enum.map(events, & &1.value)
    case RecordCodec.reconstruct(values, stored) do
      {:ok, state} -> {:ok, state}
      {:error, reason} -> corrupt("projections", "reconstruction", reason)
    end
  end

  defp validate_imports_from_content(content) do
    records = Enum.group_by(content["legacy_records"], &hd/1)

    Enum.reduce_while(content["import_runs"], {:ok, %{}}, fn row, {:ok, acc} ->
      digest = hd(row)
      case validate_import_rows(row, Map.get(records, digest, [])) do
        {:ok, manifest} -> {:cont, {:ok, Map.put(acc, digest, manifest)}}
        error -> {:halt, error}
      end
    end)
  end

  defp validate_import_group(conn, row) do
    digest = hd(row)
    with {:ok, records} <- query(conn, "SELECT source_digest, line_number, byte_start, byte_end, record_digest, valid, error, raw_record FROM legacy_records WHERE source_digest = ? ORDER BY line_number", [digest]) do
      validate_import_rows(row, records)
    end
  end

  defp validate_import_rows([digest, source_path, archived_path, source_bytes, lines, valid, invalid, bytes], rows) do
    columns = %{source_digest: digest, source_path: source_path, archived_path: archived_path,
                source_bytes: source_bytes, line_count: lines, valid_count: valid, invalid_count: invalid}
    with {:ok, manifest} <- bound("import_runs", digest, :import_manifest, bytes, columns),
         {:ok, summary} <- reduce_legacy_rows(digest, rows),
         true <- summary.offset == source_bytes and summary.lines == lines and
                   summary.valid == valid and summary.invalid == invalid,
         true <- summary.errors == manifest["errors"],
         true <- summary.digest == digest do
      {:ok, manifest}
    else
      false -> corrupt("legacy_records", digest, :import_evidence_mismatch)
      {:error, _reason} = error -> error
    end
  end

  defp reduce_legacy_rows(digest, rows) do
    initial = %{offset: 0, lines: 0, valid: 0, invalid: 0, errors: [], hash: :crypto.hash_init(:sha256)}

    Enum.reduce_while(rows, {:ok, initial}, fn [source, line, start, finish, record_digest, valid, error, raw], {:ok, acc} ->
      {classified_valid, classified_error} = LegacyLine.classify(raw)
      row_value = %{"schema_version" => 1, "source_digest" => source, "line_number" => line,
                    "byte_start" => start, "byte_end" => finish, "record_digest" => record_digest,
                    "valid" => valid == 1, "error" => error,
                    "raw_record_digest" => Encoding.digest(raw)}
      columns = %{source_digest: source, line_number: line, byte_start: start, byte_end: finish,
                  record_digest: record_digest, valid: valid == 1, error: error}
      with true <- source == digest and line == acc.lines + 1 and start == acc.offset and finish == start + byte_size(raw),
           true <- record_digest == Encoding.digest(raw),
           true <- {valid == 1, error} == {classified_valid, classified_error},
           {:ok, _decoded} <- bound_value("legacy_records", {digest, line}, :legacy_record, row_value, columns) do
        error_entry = if valid == 0, do: [%{"line" => line, "byte_start" => start, "byte_end" => finish,
          "record_digest" => record_digest, "error" => error}], else: []
        next = %{offset: finish, lines: line, valid: acc.valid + valid,
                 invalid: acc.invalid + if(valid == 0, do: 1, else: 0),
                 errors: acc.errors ++ error_entry, hash: :crypto.hash_update(acc.hash, raw)}
        {:cont, {:ok, next}}
      else
        false -> {:halt, corrupt("legacy_records", {digest, line}, :invalid_retained_evidence)}
        {:error, _reason} = error_value -> {:halt, error_value}
      end
    end)
    |> then(fn
      {:ok, summary} -> {:ok, Map.put(summary, :digest, summary.hash |> :crypto.hash_final() |> Base.encode16(case: :lower))}
      error -> error
    end)
  end

  defp read_command_closure(conn, [id, input_id, actor, digest, type, protocol]) do
    with {:ok, input_rows} <- query(conn, "SELECT input_id, actor_id, request_digest, canonical_request, protocol_version FROM inputs WHERE input_id = ?", [input_id]),
         {:ok, result_rows} <- query(conn, "SELECT command_id, schema_version, disposition, reason_code, result, committed_seq FROM command_results WHERE command_id = ?", [id]),
         {:ok, event_rows} <- query(conn, "SELECT seq, event_id, command_id, schema_version, event_type, event FROM events WHERE command_id = ? ORDER BY seq", [id]),
         {:ok, effect_rows} <- query(conn, "SELECT effect_id, command_id, schema_version, request_digest, status, intent FROM effects WHERE command_id = ? ORDER BY effect_id", [id]),
         {:ok, [[max_seq]]} <- query(conn, "SELECT coalesce(max(seq), 0) FROM events"),
         [[^input_id, ^actor, ^digest, request, ^protocol]] <- input_rows,
         [[^id, schema, disposition, reason, result, committed_seq]] <- result_rows,
         {:ok, request_value} <- bound("inputs", input_id, :command_request, request, %{input_id: input_id,
             actor_id: actor, request_digest: digest, protocol_version: protocol, command_id: id, command_type: type}),
         {:ok, result_value} <- bound("command_results", id, :result, result, %{schema_version: schema,
             disposition: disposition, reason_code: reason, committed_seq: committed_seq}),
         {:ok, events} <- decode_events(event_rows),
         {:ok, effects} <- decode_effects(effect_rows),
         true <- valid_scoped_result?(result_value, events, effects, max_seq),
         :ok <- validate_scoped_effects(conn, effects) do
      {:ok, %{id: id, actor_id: actor, digest: digest, request: request_value,
              result: result_value, events: events, effects: effects}}
    else
      [] -> corrupt("commands", id, :required_relation_missing)
      false -> corrupt("command_results", id, :invalid_sequence_or_disposition)
      {:error, _reason} = error -> error
      _ -> corrupt("commands", id, :required_relation_missing)
    end
  end

  defp valid_scoped_result?(result, events, effects, max_seq) do
    seqs = Enum.map(events, & &1.seq)
    committed = result["committed_seq"]
    committed >= 0 and committed <= max_seq and
      (seqs == [] or (contiguous?(seqs) and committed == List.last(seqs))) and
      (result["disposition"] == "accepted" or (events == [] and map_size(effects) == 0))
  end

  defp read_projection(conn, namespace, entity_id) do
    with {:ok, rows} <- query(conn, "SELECT namespace, entity_id, schema_version, revision, last_event_id, projection FROM projections WHERE namespace = ? AND entity_id = ?", [namespace, entity_id]) do
      case rows do
        [] -> {:ok, :absent}
        [[^namespace, ^entity_id, schema, revision, last_event_id, bytes]] ->
          with {:ok, projection} <- bound("projections", {namespace, entity_id}, :projection, bytes,
                 %{namespace: namespace, entity_id: entity_id, schema_version: schema,
                   revision: revision, last_event_id: last_event_id}),
               {:ok, event_rows} <- query(conn, "SELECT schema_version, event_id, event_type, event FROM events WHERE event_id = ?", [last_event_id]),
               [[event_schema, ^last_event_id, event_type, event_bytes]] <- event_rows,
               {:ok, _event} <- bound("events", last_event_id, :event, event_bytes,
                 %{schema_version: event_schema, event_id: last_event_id, type: event_type}) do
            {:ok, %{revision: revision, value: projection}}
          else
            [] -> corrupt("projections", {namespace, entity_id}, :missing_event)
            {:error, _reason} = error -> error
            _ -> corrupt("projections", {namespace, entity_id}, :invalid_event_relation)
          end
        _ -> corrupt("projections", {namespace, entity_id}, :duplicate_identity)
      end
    end
  end

  defp read_ledger(conn, generation_id) do
    with {:ok, rows} <- query(conn, "SELECT generation_id, parent_generation_id, schema_version, revision, allocation, consumed FROM ledger_generations WHERE generation_id = ?", [generation_id]) do
      case rows do
        [] -> {:ok, :absent}
        [[^generation_id, parent, schema, revision, allocation, consumed]] ->
          value = %{"schema_version" => schema, "generation_id" => generation_id,
                    "parent_generation_id" => parent, "revision" => revision,
                    "allocation" => allocation, "consumed" => consumed}
          columns = %{generation_id: generation_id, parent_generation_id: parent, schema_version: schema,
                      revision: revision, allocation: allocation, consumed: consumed}
          with {:ok, decoded} <- bound_value("ledger_generations", generation_id, :ledger_generation, value, columns),
               {:ok, reservation_rows} <- query(conn, "SELECT reservation_id, generation_id, claim_id, dimension, units, status, reservation FROM reservations WHERE generation_id = ? ORDER BY reservation_id", [generation_id]),
               {:ok, reservations} <- decode_reservations(reservation_rows),
               true <-
                 Enum.sum_by(Map.values(reservations), & &1.units) == allocation - consumed,
               :ok <- validate_scoped_reservations(conn, reservations) do
            {:ok, %{revision: revision, value: decoded}}
          else
            false -> corrupt("ledger_generations", generation_id, :funding_mismatch)
            {:error, _reason} = error -> error
          end
        _ -> corrupt("ledger_generations", generation_id, :duplicate_identity)
      end
    end
  end

  defp validate_scoped_effects(conn, effects) do
    Enum.reduce_while(effects, :ok, fn {effect_id, _effect}, :ok ->
      with {:ok, rows} <-
             query(
               conn,
               "SELECT claim_id, effect_id, writer_epoch, status, claim FROM claims WHERE effect_id = ? ORDER BY claim_id",
               [effect_id]
             ),
           {:ok, claims} <- decode_claims(rows),
           :ok <- validate_scoped_claims(conn, claims) do
        {:cont, :ok}
      else
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp validate_scoped_claims(conn, claims) do
    Enum.reduce_while(claims, :ok, fn {claim_id, _claim}, :ok ->
      with {:ok, rows} <-
             query(
               conn,
               "SELECT reservation_id, generation_id, claim_id, dimension, units, status, reservation FROM reservations WHERE claim_id = ? ORDER BY reservation_id",
               [claim_id]
             ),
           {:ok, reservations} <- decode_reservations(rows),
           true <- map_size(reservations) == 1,
           :ok <- validate_scoped_reservations(conn, reservations),
           :ok <- validate_scoped_ledgers(conn, reservations) do
        {:cont, :ok}
      else
        false -> {:halt, corrupt("claims", claim_id, :required_relation_missing)}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp validate_scoped_reservations(conn, reservations) do
    Enum.reduce_while(reservations, :ok, fn {reservation_id, reservation}, :ok ->
      with {:ok, claim_rows} <-
             query(
               conn,
               "SELECT claim_id, effect_id, writer_epoch, status, claim FROM claims WHERE claim_id = ?",
               [reservation.claim_id]
             ),
           {:ok, claims} <- decode_claims(claim_rows),
           %{effect_id: effect_id} <- claims[reservation.claim_id],
           {:ok, effect_rows} <-
             query(
               conn,
               "SELECT effect_id, command_id, schema_version, request_digest, status, intent FROM effects WHERE effect_id = ?",
               [effect_id]
             ),
           {:ok, effects} <- decode_effects(effect_rows),
           true <- Map.has_key?(effects, effect_id) do
        {:cont, :ok}
      else
        false -> {:halt, corrupt("reservations", reservation_id, :required_relation_missing)}
        nil -> {:halt, corrupt("reservations", reservation_id, :required_relation_missing)}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp validate_scoped_ledgers(conn, reservations) do
    Enum.reduce_while(reservations, :ok, fn {_id, reservation}, :ok ->
      case read_ledger(conn, reservation.generation_id) do
        {:ok, %{}} -> {:cont, :ok}
        {:ok, :absent} ->
          {:halt,
           corrupt("reservations", reservation.id, :required_ledger_generation_missing)}

        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp validate_touched_revisions(conn, revisions) do
    Enum.reduce_while(revisions, :ok, fn key, :ok ->
      case read(conn, {:revision, key}) do
        {:ok, _value} -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp query(conn, sql, params \\ []) do
    case Database.query(conn, sql, params) do
      {:ok, rows} -> {:ok, rows}
      {:error, reason} -> {:error, {:storage_unavailable, reason}}
    end
  rescue
    error -> {:error, {:storage_unavailable, {:exception, error}}}
  end

  defp stream_rows(conn, sql, params \\ []) do
    case Database.fold(conn, sql, params, [], fn row, acc -> [row | acc] end) do
      {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
      {:error, reason} -> {:error, {:storage_unavailable, reason}}
    end
  rescue
    error -> {:error, {:storage_unavailable, {:exception, error}}}
  end

  defp bound(table, identity, type, bytes, columns) do
    case RecordCodec.decode_bound(type, bytes, columns) do
      {:ok, value} -> {:ok, value}
      {:error, reason} -> corrupt(table, identity, reason)
    end
  end

  defp bound_value(table, identity, type, value, columns) do
    case RecordCodec.decode_bound(type, value, columns) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, reason} -> corrupt(table, identity, reason)
    end
  end

  defp required(map, key, table, identity) do
    case Map.fetch(map, key) do
      {:ok, value} -> {:ok, value}
      :error -> corrupt(table, identity, :required_relation_missing)
    end
  end

  defp contiguous?([]), do: true
  defp contiguous?([first | rest]), do: rest == Enum.to_list((first + 1)..(first + length(rest))//1)
  defp valid_identity?(value), do: is_binary(value) and value != "" and String.valid?(value)
  defp reverse_ok({:ok, values}), do: {:ok, Enum.reverse(values)}
  defp reverse_ok(error), do: error
  defp corrupt(table, identity, reason), do: {:error, corrupt_value(table, identity, reason)}
  defp corrupt_value(table, identity, reason), do: {:authority_corrupt, table, identity, reason}
end
