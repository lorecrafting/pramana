defmodule PramanaFoundry.DurableStore.Authority do
  @moduledoc false

  alias PramanaFoundry.DurableStore.{
    Database,
    Encoding,
    LegacyLine,
    ProtectedPrimitives,
    RecordCodec
  }

  @registry [
    {"metadata", "key", ~w(key value)},
    {"inputs", "input_id",
     ~w(input_id actor_id request_digest canonical_request protocol_version)},
    {"commands", "command_id",
     ~w(command_id input_id actor_id request_digest command_type protocol_version)},
    {"command_results", "command_id",
     ~w(command_id schema_version disposition reason_code result committed_seq)},
    {"events", "seq",
     ~w(seq event_id command_id schema_version event_type projection_namespace projection_entity_id event)},
    {"projections", "namespace, entity_id",
     ~w(namespace entity_id schema_version revision last_event_id projection)},
    {"effects", "effect_id",
     ~w(effect_id command_id schema_version request_digest status intent)},
    {"ledger_generations", "generation_id",
     ~w(generation_id parent_generation_id schema_version revision allocation consumed)},
    {"claims", "claim_id", ~w(claim_id effect_id writer_epoch status claim)},
    {"reservations", "reservation_id",
     ~w(reservation_id generation_id claim_id dimension units status reservation)},
    {"receipts", "receipt_id", ~w(receipt_id effect_id request_id schema_version receipt)},
    {"leases", "lease_id", ~w(lease_id claim_id schema_version lease)},
    {"policy_revisions", "policy_revision_id",
     ~w(policy_revision_id command_id schema_version revision policy)},
    {"control_revisions", "control_id",
     ~w(control_id command_id schema_version revision control)},
    {"artifact_references", "artifact_id",
     ~w(artifact_id command_id schema_version digest reference)},
    {"import_runs", "source_digest",
     ~w(source_digest source_path archived_path source_bytes line_count valid_count invalid_count manifest)},
    {"legacy_records", "source_digest, line_number",
     ~w(source_digest line_number byte_start byte_end record_digest valid error raw_record)},
    {"root_commands", "seq",
     ~w(seq command_id actor_id request_digest canonical_request schema_version operation disposition reason_code result)},
    {"authenticated_inboxes", "execution_id",
     ~w(execution_id actor_id revision last_sequence sealed_sequence state)},
    {"authenticated_inbox_items", "execution_id, sequence",
     ~w(execution_id sequence item_kind disposition item_digest item)},
    {"root_policies", "policy_id", ~w(policy_id revision state)},
    {"root_policy_history", "policy_id, revision",
     ~w(policy_id revision prior_revision command_id state)},
    {"root_controls", "control_id", ~w(control_id revision state)},
    {"root_control_history", "control_id, revision",
     ~w(control_id revision prior_revision command_id state)},
    {"root_ledgers", "ledger_id, generation",
     ~w(ledger_id generation parent_ledger_id parent_generation dimension revision status authorized available held consumed delegated retired state)},
    {"root_reservations", "reservation_id",
     ~w(reservation_id ledger_id generation dimension owner_kind owner_id units revision status claim_id state)},
    {"root_effects", "effect_id",
     ~w(effect_id request_digest policy_id policy_revision control_id control_revision operation scope ticket_id attempt_id execution_id status revision state)},
    {"root_claims", "claim_id", ~w(claim_id effect_id writer_epoch status revision state)},
    {"root_receipts", "receipt_id",
     ~w(receipt_id claim_id request_id outcome receipt_digest state)},
    {"root_leases", "lease_id", ~w(lease_id claim_id resource_id status revision state)},
    {"root_pointers", "pointer_kind", ~w(pointer_kind producer_status revision state)},
    {"atomic_bundles", "command_id",
     ~w(command_id actor_id request_digest schema_version disposition reason_code canonical_envelope result)},
    {"durable_operations", "owner_kind, owner_id, ordinal",
     ~w(owner_kind owner_id ordinal operation_kind operation_type request result)},
    {"root_infrastructure_settlements", "effect_id",
     ~w(effect_id claim_id receipt_id role work_owner infrastructure_generation predecessor_effect_id failure_class ordinal state)},
    {"root_attempt_closures", "ticket_id, attempt_id", ~w(ticket_id attempt_id scope state)},
    {"sqlite_sequence", "name", ~w(name seq)}
  ]

  @unsupported ~w(receipts leases policy_revisions control_revisions artifact_references)
  def registry, do: @registry

  def read(conn, :all) do
    with :ok <- validate_foreign_keys(conn),
         :ok <- validate_schema(conn),
         {:ok, rows} <- validation_rows(conn),
         {:ok, view} <- validate_content(conn, rows),
         :ok <- ProtectedPrimitives.validate(conn),
         {:ok, content} <- content(conn) do
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

  def read(conn, {:materialized_projection, namespace, entity_id, :stored}),
    do: read_projection(conn, namespace, entity_id, :stored)

  def read(conn, {:materialized_projection, namespace, entity_id, carrier_event_id}),
    do: read_projection(conn, namespace, entity_id, {:through, carrier_event_id})

  def read(conn, {:revision, {:ledger, generation_id}}),
    do: read_ledger(conn, generation_id)

  def read(conn, {:revision, {:root_ledger, ledger_id, generation}}) do
    with {:ok, rows} <-
           query(
             conn,
             "SELECT revision FROM root_ledgers WHERE ledger_id = ? AND generation = ?",
             [ledger_id, generation]
           ) do
      case rows do
        [] -> {:ok, :absent}
        [[revision]] -> {:ok, %{revision: revision}}
        _ -> corrupt("root_ledgers", ledger_id, :duplicate_identity)
      end
    end
  end

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
         true <- command_view.result["committed_seq"] == touched.committed_seq,
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
      initial = %{count: 0, hash: :crypto.hash_init(:sha256)}

      case Database.fold(
             conn,
             "SELECT * FROM #{table} ORDER BY #{ordering}",
             [],
             initial,
             &digest_row/2
           ) do
        {:ok, summary} ->
          digest = summary.hash |> :crypto.hash_final() |> Base.encode16(case: :lower)
          {:cont, {:ok, Map.put(acc, table, %{count: summary.count, sha256: digest})}}

        {:error, _reason} = error ->
          {:halt, error}
      end
    end)
  end

  defp validation_rows(conn) do
    Enum.reduce_while(@registry, {:ok, %{}}, fn
      {"legacy_records", _ordering, _columns}, {:ok, acc} ->
        {:cont, {:ok, Map.put(acc, "legacy_records", [])}}

      {table, ordering, _columns}, {:ok, acc} ->
        case stream_rows(conn, "SELECT * FROM #{table} ORDER BY #{ordering}") do
          {:ok, rows} -> {:cont, {:ok, Map.put(acc, table, rows)}}
          {:error, _reason} = error -> {:halt, error}
        end
    end)
  end

  defp validate_schema(conn) do
    with {:ok, expected} <- Database.expected_schema_contract(),
         {:ok, actual} <- Database.schema_contract(conn),
         true <- actual == expected do
      :ok
    else
      false -> corrupt("sqlite_schema", "inventory", :schema_mismatch)
      {:error, _reason} = error -> error
    end
  end

  defp validate_content(conn, content) do
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
         :ok <- validate_effect_owners(effects, commands),
         :ok <- validate_protected(effects, ledgers, claims, reservations),
         {:ok, reconstructed} <- validate_reconstruction(events, projections),
         {:ok, imports} <- validate_imports(conn, content["import_runs"]) do
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
      MapSet.new(
        ~w(schema_version protocol_version event_version projection_version installation_id repository_id migration_v1) ++
          ~w(protected_schema_version migration_fr08a_v1 migration_atomic_bundle_v2) ++
          ~w(migration_attempt_closure_v3)
      )

    values = Map.new(rows, fn [key, value] -> {key, value} end)

    cond do
      length(rows) != map_size(values) ->
        corrupt("metadata", "keys", :duplicate_key)

      not MapSet.subset?(MapSet.new(Map.keys(values)), allowed) ->
        corrupt("metadata", "keys", :unknown_key)

      Enum.any?(
        ~w(schema_version protocol_version event_version projection_version),
        &(values[&1] != "1")
      ) ->
        corrupt("metadata", "versions", :unsupported_version)

      not valid_identity?(values["installation_id"]) or
          not valid_identity?(values["repository_id"]) ->
        corrupt("metadata", "identity", :invalid_identity)

      Map.has_key?(values, "migration_v1") and values["migration_v1"] != "complete" ->
        corrupt("metadata", "migration_v1", :invalid_migration_state)

      values["protected_schema_version"] != "3" ->
        corrupt("metadata", "protected_schema_version", :unsupported_version)

      values["migration_fr08a_v1"] != "complete" ->
        corrupt("metadata", "migration_fr08a_v1", :invalid_migration_state)

      values["migration_atomic_bundle_v2"] != "complete" ->
        corrupt("metadata", "migration_atomic_bundle_v2", :invalid_migration_state)

      values["migration_attempt_closure_v3"] != "complete" ->
        corrupt("metadata", "migration_attempt_closure_v3", :invalid_migration_state)

      true ->
        :ok
    end
  end

  defp validate_unsupported(content) do
    case Enum.find(@unsupported, &(content[&1] != [])) do
      nil -> :ok
      table -> corrupt(table, "retained", :unsupported_retained_authority)
    end
  end

  defp decode_commands(content) do
    inputs =
      Map.new(content["inputs"], fn [id, actor, digest, bytes, protocol] ->
        {id, {actor, digest, bytes, protocol}}
      end)

    results =
      Map.new(content["command_results"], fn [id, schema, disposition, reason, bytes, seq] ->
        {id, {schema, disposition, reason, bytes, seq}}
      end)

    if map_size(inputs) != length(content["inputs"]) or
         map_size(results) != length(content["command_results"]) do
      corrupt("commands", "relations", :duplicate_identity)
    else
      Enum.reduce_while(content["commands"], {:ok, %{}}, fn [
                                                              id,
                                                              input_id,
                                                              actor,
                                                              digest,
                                                              type,
                                                              protocol
                                                            ],
                                                            {:ok, acc} ->
        with {:ok, {input_actor, input_digest, request, input_protocol}} <-
               required(inputs, input_id, "inputs", input_id),
             {:ok, {schema, disposition, reason, result, seq}} <-
               required(results, id, "command_results", id),
             true <-
               actor == input_actor and digest == input_digest and protocol == input_protocol,
             {:ok, request_value} <-
               bound("inputs", input_id, :command_request, request, %{
                 input_id: input_id,
                 actor_id: actor,
                 request_digest: digest,
                 protocol_version: protocol,
                 command_id: id,
                 command_type: type
               }),
             {:ok, result_value} <-
               bound("command_results", id, :result, result, %{
                 schema_version: schema,
                 disposition: disposition,
                 reason_code: reason,
                 committed_seq: seq
               }) do
          value = %{
            id: id,
            input_id: input_id,
            actor_id: actor,
            digest: digest,
            type: type,
            protocol: protocol,
            request: request_value,
            result: result_value
          }

          {:cont, {:ok, Map.put(acc, id, value)}}
        else
          false -> {:halt, corrupt("commands", id, :binding_mismatch)}
          {:error, _reason} = error -> {:halt, error}
        end
      end)
      |> then(fn
        {:ok, commands} ->
          if map_size(commands) == length(content["commands"]) and
               map_size(inputs) == map_size(commands) and
               map_size(results) == map_size(commands) and
               commands
               |> Map.values()
               |> MapSet.new(& &1.input_id)
               |> MapSet.size() == map_size(commands),
             do: {:ok, commands},
             else: corrupt("commands", "cardinality", :required_relation_missing)

        error ->
          error
      end)
    end
  end

  defp decode_events(rows) do
    Enum.reduce_while(rows, {:ok, []}, fn row, {:ok, acc} ->
      case decode_event_row(row) do
        {:ok, event} -> {:cont, {:ok, [event | acc]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> reverse_ok()
  end

  defp decode_event_row([
         seq,
         id,
         command_id,
         schema,
         type,
         projection_namespace,
         projection_entity_id,
         bytes
       ]) do
    with {:ok, value} <-
           bound("events", id, :event, bytes, %{
             schema_version: schema,
             event_id: id,
             type: type
           }),
         true <- event_carrier_matches?(value, projection_namespace, projection_entity_id) do
      {:ok, %{seq: seq, id: id, command_id: command_id, value: value}}
    else
      false -> corrupt("events", id, :relational_binding_mismatch)
      {:error, _reason} = error -> error
    end
  end

  defp decode_projections(rows) do
    Enum.reduce_while(rows, {:ok, %{}}, fn [
                                             namespace,
                                             entity_id,
                                             schema,
                                             revision,
                                             last_event_id,
                                             bytes
                                           ],
                                           {:ok, acc} ->
      columns = %{
        namespace: namespace,
        entity_id: entity_id,
        schema_version: schema,
        revision: revision,
        last_event_id: last_event_id
      }

      case bound("projections", {namespace, entity_id}, :projection, bytes, columns) do
        {:ok, value} ->
          entry = %{revision: revision, last_event_id: last_event_id, value: value["value"]}
          {:cont, {:ok, Map.put(acc, {namespace, entity_id}, entry)}}

        error ->
          {:halt, error}
      end
    end)
  end

  defp decode_effects(rows) do
    decode_bound_map(rows, "effects", fn [id, command_id, schema, digest, status, bytes] ->
      with {:ok, value} <-
             bound("effects", id, :intent, bytes, %{
               effect_id: id,
               schema_version: schema,
               request_digest: digest,
               status: status
             }) do
        {:ok, id, %{id: id, command_id: command_id, value: value}}
      end
    end)
  end

  defp decode_ledgers(rows) do
    decode_bound_map(rows, "ledger_generations", fn [
                                                      id,
                                                      parent,
                                                      schema,
                                                      revision,
                                                      allocation,
                                                      consumed
                                                    ] ->
      value = %{
        "schema_version" => schema,
        "generation_id" => id,
        "parent_generation_id" => parent,
        "revision" => revision,
        "allocation" => allocation,
        "consumed" => consumed
      }

      columns = %{
        generation_id: id,
        parent_generation_id: parent,
        schema_version: schema,
        revision: revision,
        allocation: allocation,
        consumed: consumed
      }

      with {:ok, decoded} <-
             bound_value("ledger_generations", id, :ledger_generation, value, columns) do
        {:ok, id, decoded}
      end
    end)
  end

  defp decode_claims(rows) do
    decode_bound_map(rows, "claims", fn [id, effect_id, epoch, status, bytes] ->
      with {:ok, value} <-
             bound("claims", id, :claim, bytes, %{
               schema_version: 1,
               claim_id: id,
               effect_id: effect_id,
               writer_epoch: epoch,
               status: status
             }) do
        {:ok, id, %{id: id, effect_id: effect_id, value: value}}
      end
    end)
  end

  defp decode_reservations(rows) do
    decode_bound_map(rows, "reservations", fn [
                                                id,
                                                generation_id,
                                                claim_id,
                                                dimension,
                                                units,
                                                status,
                                                bytes
                                              ] ->
      with {:ok, value} <-
             bound("reservations", id, :reservation, bytes, %{
               schema_version: 1,
               reservation_id: id,
               generation_id: generation_id,
               claim_id: claim_id,
               dimension: dimension,
               units: units,
               status: status
             }) do
        {:ok, id,
         %{id: id, generation_id: generation_id, claim_id: claim_id, units: units, value: value}}
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
        corrupt("events", "sequence", :sequence_gap)

      events == [] and rows == [] ->
        :ok

      events != [] and rows == [["events", max_seq]] ->
        :ok

      true ->
        corrupt("sqlite_sequence", "events", :invalid_sequence)
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

      if valid,
        do: {:cont, :ok},
        else: {:halt, corrupt("command_results", id, :invalid_sequence_or_disposition)}
    end)
  end

  defp validate_event_owners(events, commands) do
    case Enum.find(events, &(not Map.has_key?(commands, &1.command_id))) do
      nil -> :ok
      event -> corrupt("events", event.id, :missing_command)
    end
  end

  defp validate_effect_owners(effects, commands) do
    case Enum.find(effects, fn {_id, effect} ->
           case commands[effect.command_id] do
             %{result: %{"disposition" => "accepted"}} -> false
             _other -> true
           end
         end) do
      nil -> :ok
      {id, _effect} -> corrupt("effects", id, :missing_command)
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

      if valid,
        do: {:cont, :ok},
        else: {:halt, corrupt("reservations", id, :required_relation_missing)}
    end)
  end

  defp validate_ledger_funding(ledgers, reservations) do
    Enum.reduce_while(ledgers, :ok, fn {id, ledger}, :ok ->
      reserved =
        reservations
        |> Map.values()
        |> Enum.filter(&(&1.generation_id == id))
        |> Enum.sum_by(& &1.units)

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

  defp validate_imports(conn, import_rows) do
    with {:ok, [[orphan_count]]} <-
           query(
             conn,
             "SELECT count(*) FROM legacy_records r LEFT JOIN import_runs i ON i.source_digest = r.source_digest WHERE i.source_digest IS NULL"
           ),
         true <- orphan_count == 0 do
      Enum.reduce_while(import_rows, {:ok, %{}}, fn row, {:ok, acc} ->
        digest = hd(row)

        case validate_import_group(conn, row) do
          {:ok, manifest} -> {:cont, {:ok, Map.put(acc, digest, manifest)}}
          error -> {:halt, error}
        end
      end)
    else
      false -> corrupt("legacy_records", "orphan", :missing_import_run)
      {:error, _reason} = error -> error
    end
  end

  defp validate_import_group(
         conn,
         [digest, source_path, archived_path, source_bytes, lines, valid, invalid, bytes]
       ) do
    columns = %{
      source_digest: digest,
      source_path: source_path,
      archived_path: archived_path,
      source_bytes: source_bytes,
      line_count: lines,
      valid_count: valid,
      invalid_count: invalid
    }

    initial = %{
      offset: 0,
      lines: 0,
      valid: 0,
      invalid: 0,
      errors: [],
      hash: :crypto.hash_init(:sha256)
    }

    with {:ok, manifest} <- bound("import_runs", digest, :import_manifest, bytes, columns),
         {:ok, summary} <-
           Database.fold(
             conn,
             "SELECT source_digest, line_number, byte_start, byte_end, record_digest, valid, error, raw_record FROM legacy_records WHERE source_digest = ? ORDER BY line_number",
             [digest],
             initial,
             &reduce_legacy_row(digest, &1, &2)
           ),
         summary <- finish_legacy_summary(summary),
         true <-
           summary.offset == source_bytes and summary.lines == lines and
             summary.valid == valid and summary.invalid == invalid,
         true <- summary.errors == manifest["errors"],
         true <- summary.digest == digest do
      {:ok, manifest}
    else
      false -> corrupt("legacy_records", digest, :import_evidence_mismatch)
      {:error, {:authority_corrupt, _table, _identity, _reason} = reason} -> {:error, reason}
      {:error, reason} -> {:error, {:storage_unavailable, reason}}
    end
  end

  defp reduce_legacy_row(
         digest,
         [source, line, start, finish, record_digest, valid, error, raw],
         acc
       ) do
    {classified_valid, classified_error} = LegacyLine.classify(raw)

    row_value = %{
      "schema_version" => 1,
      "source_digest" => source,
      "line_number" => line,
      "byte_start" => start,
      "byte_end" => finish,
      "record_digest" => record_digest,
      "valid" => valid == 1,
      "error" => error,
      "raw_record_digest" => Encoding.digest(raw)
    }

    columns = %{
      source_digest: source,
      line_number: line,
      byte_start: start,
      byte_end: finish,
      record_digest: record_digest,
      valid: valid == 1,
      error: error
    }

    with true <-
           source == digest and line == acc.lines + 1 and start == acc.offset and
             finish == start + byte_size(raw),
         true <- record_digest == Encoding.digest(raw),
         true <- {valid == 1, error} == {classified_valid, classified_error},
         {:ok, _decoded} <-
           bound_value("legacy_records", {digest, line}, :legacy_record, row_value, columns) do
      errors =
        if valid == 0 do
          [
            %{
              "line" => line,
              "byte_start" => start,
              "byte_end" => finish,
              "record_digest" => record_digest,
              "error" => error
            }
            | acc.errors
          ]
        else
          acc.errors
        end

      %{
        offset: finish,
        lines: line,
        valid: acc.valid + valid,
        invalid: acc.invalid + if(valid == 0, do: 1, else: 0),
        errors: errors,
        hash: :crypto.hash_update(acc.hash, raw)
      }
    else
      false -> {:halt, corrupt("legacy_records", {digest, line}, :invalid_retained_evidence)}
      {:error, _reason} = error_value -> {:halt, error_value}
    end
  end

  defp finish_legacy_summary(summary) do
    digest = summary.hash |> :crypto.hash_final() |> Base.encode16(case: :lower)
    summary |> Map.put(:errors, Enum.reverse(summary.errors)) |> Map.put(:digest, digest)
  end

  defp read_command_closure(conn, [id, _input_id, _actor, _digest, _type, _protocol]) do
    with {:ok, owner} <- read_command_owner(conn, id),
         :ok <- validate_sequence_frontier(conn),
         :ok <- validate_event_projection_closures(conn, owner.events),
         :ok <- validate_scoped_effects(conn, owner.effects) do
      {:ok,
       %{
         id: id,
         actor_id: owner.actor_id,
         digest: owner.digest,
         request: owner.request,
         result: owner.result,
         events: owner.events,
         effects: owner.effects
       }}
    else
      [] -> corrupt("commands", id, :required_relation_missing)
      false -> corrupt("command_results", id, :invalid_sequence_or_disposition)
      {:error, _reason} = error -> error
      _ -> corrupt("commands", id, :required_relation_missing)
    end
  end

  defp read_command_owner(conn, id) do
    with {:ok, rows} <-
           query(
             conn,
             "SELECT c.input_id, c.actor_id, c.request_digest, c.command_type, c.protocol_version, i.input_id, i.actor_id, i.request_digest, i.canonical_request, i.protocol_version, r.schema_version, r.disposition, r.reason_code, r.result, r.committed_seq FROM commands c LEFT JOIN inputs i ON i.input_id = c.input_id LEFT JOIN command_results r ON r.command_id = c.command_id WHERE c.command_id = ?",
             [id]
           ),
         [
           [
             input_id,
             actor,
             digest,
             type,
             protocol,
             input_id,
             actor,
             digest,
             request,
             protocol,
             schema,
             disposition,
             reason,
             result,
             committed_seq
           ]
         ] <- rows,
         :ok <- validate_owner_fields(id, request, schema, disposition, result, committed_seq),
         {:ok, request_value} <-
           bound("inputs", input_id, :command_request, request, %{
             input_id: input_id,
             actor_id: actor,
             request_digest: digest,
             protocol_version: protocol,
             command_id: id,
             command_type: type
           }),
         {:ok, result_value} <-
           bound("command_results", id, :result, result, %{
             schema_version: schema,
             disposition: disposition,
             reason_code: reason,
             committed_seq: committed_seq
           }),
         {:ok, event_rows} <-
           query(
             conn,
             "SELECT seq, event_id, command_id, schema_version, event_type, projection_namespace, projection_entity_id, event FROM events WHERE command_id = ? ORDER BY seq",
             [id]
           ),
         {:ok, effect_rows} <-
           query(
             conn,
             "SELECT effect_id, command_id, schema_version, request_digest, status, intent FROM effects WHERE command_id = ? ORDER BY effect_id",
             [id]
           ),
         {:ok, [[max_seq]]} <- query(conn, "SELECT coalesce(max(seq), 0) FROM events"),
         {:ok, events} <- decode_events(event_rows),
         {:ok, effects} <- decode_effects(effect_rows),
         true <- valid_scoped_result?(result_value, events, effects, max_seq) do
      {:ok,
       %{
         actor_id: actor,
         digest: digest,
         request: request_value,
         result: result_value,
         events: events,
         effects: effects
       }}
    else
      false -> corrupt("command_results", id, :invalid_sequence_or_disposition)
      {:error, _reason} = error -> error
      _other -> corrupt("commands", id, :required_relation_missing)
    end
  end

  defp validate_owner_fields(id, request, schema, disposition, result, committed_seq) do
    if is_binary(request) and is_integer(schema) and is_binary(disposition) and
         is_binary(result) and is_integer(committed_seq) do
      :ok
    else
      corrupt("commands", id, :required_relation_missing)
    end
  end

  defp valid_scoped_result?(result, events, effects, max_seq) do
    seqs = Enum.map(events, & &1.seq)
    committed = result["committed_seq"]

    committed >= 0 and committed <= max_seq and
      (seqs == [] or (contiguous?(seqs) and committed == List.last(seqs))) and
      (result["disposition"] == "accepted" or (events == [] and map_size(effects) == 0))
  end

  defp validate_event_projection_closures(conn, events) do
    Enum.reduce_while(events, :ok, fn event, :ok ->
      case event.value["payload"]["projection"] do
        nil ->
          {:cont, :ok}

        %{"namespace" => namespace, "entity_id" => entity_id} ->
          case read_projection(conn, namespace, entity_id) do
            {:ok, %{}} ->
              {:cont, :ok}

            {:ok, :absent} ->
              {:halt, corrupt("events", event.id, :required_projection_missing)}

            {:error, _reason} = error ->
              {:halt, error}
          end
      end
    end)
  end

  defp read_projection(conn, namespace, entity_id, mode \\ :final) do
    with {:ok, rows} <-
           query(
             conn,
             "SELECT namespace, entity_id, schema_version, revision, last_event_id, projection FROM projections WHERE namespace = ? AND entity_id = ?",
             [namespace, entity_id]
           ) do
      case rows do
        [] ->
          validate_projection_absence(conn, namespace, entity_id, mode)

        [[^namespace, ^entity_id, schema, revision, last_event_id, bytes]] ->
          with {:ok, projection} <-
                 bound("projections", {namespace, entity_id}, :projection, bytes, %{
                   namespace: namespace,
                   entity_id: entity_id,
                   schema_version: schema,
                   revision: revision,
                   last_event_id: last_event_id
                 }),
               {:ok, event_rows} <-
                 query(
                   conn,
                   "SELECT seq, event_id, command_id, schema_version, event_type, projection_namespace, projection_entity_id, event FROM events WHERE event_id = ?",
                   [last_event_id]
                 ),
               {:ok, [%{value: event}]} <- decode_events(event_rows),
               true <- projection_matches_event?(projection, event),
               chain_mode <- if(mode == :stored, do: {:through, last_event_id}, else: mode),
               :ok <- validate_projection_chain(conn, projection, chain_mode) do
            {:ok, %{revision: revision, value: projection}}
          else
            [] ->
              corrupt("projections", {namespace, entity_id}, :missing_event)

            {:error, _reason} = error ->
              error

            false ->
              corrupt("projections", {namespace, entity_id}, :projection_event_mismatch)

            _ ->
              corrupt("projections", {namespace, entity_id}, :invalid_event_relation)
          end

        _ ->
          corrupt("projections", {namespace, entity_id}, :duplicate_identity)
      end
    end
  end

  defp validate_projection_absence(_conn, _namespace, _entity_id, :stored), do: {:ok, :absent}

  defp validate_projection_absence(conn, namespace, entity_id, _mode) do
    with {:ok, rows} <-
           query(
             conn,
             "SELECT event_id FROM events WHERE projection_namespace = ? AND projection_entity_id = ? ORDER BY seq LIMIT 1",
             [namespace, entity_id]
           ) do
      case rows do
        [] ->
          {:ok, :absent}

        [[event_id]] ->
          corrupt("projections", {namespace, entity_id}, {:missing_for_carrier, event_id})

        _other ->
          corrupt("projections", {namespace, entity_id}, :invalid_event_relation)
      end
    end
  end

  defp projection_matches_event?(projection, event) do
    case event["payload"]["projection"] do
      nil ->
        false

      transition ->
        transition["namespace"] == projection["namespace"] and
          transition["entity_id"] == projection["entity_id"] and
          transition["revision"] == projection["revision"] and
          transition["value"] == projection["value"] and
          event["event_id"] == projection["last_event_id"]
    end
  end

  defp validate_projection_chain(conn, projection, mode) do
    last_event_id = projection["last_event_id"]

    with {:ok, [[last_seq]]} <-
           query(conn, "SELECT seq FROM events WHERE event_id = ?", [last_event_id]),
         {:ok, {sql, params}} <- projection_chain_query(projection, mode, last_seq),
         initial <- %{state: %{}, commands: MapSet.new(), last_event_id: nil},
         {:ok, summary} <-
           Database.fold(
             conn,
             sql,
             params,
             initial,
             fn row, acc ->
               case decode_projection_carrier(row, projection) do
                 {:ok, %{id: event_id, command_id: command_id, transition: transition}} ->
                   candidate = %{
                     "schema_version" => 1,
                     "namespace" => transition["namespace"],
                     "entity_id" => transition["entity_id"],
                     "expected_revision" => transition["revision"] - 1,
                     "revision" => transition["revision"],
                     "last_event_id" => event_id,
                     "value" => transition["value"]
                   }

                   carrier = %{"event_id" => event_id, "transition" => transition}

                   case RecordCodec.apply_projection(acc.state, {carrier, candidate}) do
                     {:ok, state} ->
                       %{
                         state: state,
                         commands: MapSet.put(acc.commands, command_id),
                         last_event_id: event_id
                       }

                     {:error, reason} ->
                       {:halt,
                        corrupt(
                          "projections",
                          {projection["namespace"], projection["entity_id"]},
                          reason
                        )}
                   end

                 {:error, _reason} = error ->
                   {:halt, error}
               end
             end
           ),
         expected_stored <- %{
           {projection["namespace"], projection["entity_id"]} => %{
             revision: projection["revision"],
             last_event_id: projection["last_event_id"],
             value: projection["value"]
           }
         },
         true <- summary.last_event_id == last_event_id,
         true <- summary.state == expected_stored,
         :ok <- validate_projection_owners(conn, summary.commands, mode) do
      :ok
    else
      false ->
        corrupt(
          "projections",
          {projection["namespace"], projection["entity_id"]},
          :incomplete_projection_history
        )

      {:error, {:authority_corrupt, _table, _identity, _reason} = reason} ->
        {:error, reason}

      {:error, reason} ->
        corrupt(
          "projections",
          {projection["namespace"], projection["entity_id"]},
          reason
        )
    end
  end

  defp projection_chain_query(projection, mode, last_seq) do
    base =
      "SELECT seq, event_id, command_id, schema_version, event_type, projection_namespace, projection_entity_id, event FROM events WHERE projection_namespace = ? AND projection_entity_id = ?"

    params = [projection["namespace"], projection["entity_id"]]

    case mode do
      :final ->
        {:ok, {base <> " ORDER BY seq", params}}

      {:through, event_id} ->
        if event_id == projection["last_event_id"] do
          {:ok, {base <> " AND seq <= ? ORDER BY seq", params ++ [last_seq]}}
        else
          {:error, :invalid_projection_validation_scope}
        end

      _other ->
        {:error, :invalid_projection_validation_scope}
    end
  end

  defp decode_projection_carrier(row, projection) do
    with {:ok, event} <- decode_event_row(row),
         %{
           value: %{
             "payload" => %{
               "projection" =>
                 %{
                   "namespace" => namespace,
                   "entity_id" => entity_id
                 } = transition
             }
           }
         } <- event,
         true <- namespace == projection["namespace"] and entity_id == projection["entity_id"] do
      {:ok, Map.put(event, :transition, transition)}
    else
      {:error, _reason} = error -> error
      _other -> corrupt("events", event_identity(row), :relational_binding_mismatch)
    end
  end

  defp event_identity([_seq, event_id | _rest]), do: event_id
  defp event_identity(_row), do: "projection_carrier"

  defp validate_command_owners(conn, command_ids) do
    Enum.reduce_while(command_ids, :ok, fn command_id, :ok ->
      case read_command_owner(conn, command_id) do
        {:ok, %{result: %{"disposition" => "accepted"}}} -> {:cont, :ok}
        {:ok, _owner} -> {:halt, corrupt("commands", command_id, :invalid_event_owner)}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp validate_projection_owners(_conn, _command_ids, {:through, _event_id}), do: :ok

  defp validate_projection_owners(conn, command_ids, :final),
    do: validate_command_owners(conn, command_ids)

  defp read_ledger(conn, generation_id) do
    with {:ok, rows} <-
           query(
             conn,
             "SELECT generation_id, parent_generation_id, schema_version, revision, allocation, consumed FROM ledger_generations WHERE generation_id = ?",
             [generation_id]
           ) do
      case rows do
        [] ->
          {:ok, :absent}

        [[^generation_id, parent, schema, revision, allocation, consumed]] ->
          value = %{
            "schema_version" => schema,
            "generation_id" => generation_id,
            "parent_generation_id" => parent,
            "revision" => revision,
            "allocation" => allocation,
            "consumed" => consumed
          }

          columns = %{
            generation_id: generation_id,
            parent_generation_id: parent,
            schema_version: schema,
            revision: revision,
            allocation: allocation,
            consumed: consumed
          }

          with {:ok, decoded} <-
                 bound_value(
                   "ledger_generations",
                   generation_id,
                   :ledger_generation,
                   value,
                   columns
                 ),
               {:ok, reservation_rows} <-
                 query(
                   conn,
                   "SELECT reservation_id, generation_id, claim_id, dimension, units, status, reservation FROM reservations WHERE generation_id = ? ORDER BY reservation_id",
                   [generation_id]
                 ),
               {:ok, reservations} <- decode_reservations(reservation_rows),
               true <-
                 Enum.sum_by(Map.values(reservations), & &1.units) == allocation - consumed,
               :ok <- validate_scoped_reservations(conn, reservations) do
            {:ok, %{revision: revision, value: decoded}}
          else
            false -> corrupt("ledger_generations", generation_id, :funding_mismatch)
            {:error, _reason} = error -> error
          end

        _ ->
          corrupt("ledger_generations", generation_id, :duplicate_identity)
      end
    end
  end

  defp validate_scoped_effects(conn, effects) do
    Enum.reduce_while(effects, :ok, fn {effect_id, effect}, :ok ->
      with {:ok, %{result: %{"disposition" => "accepted"}}} <-
             read_command_owner(conn, effect.command_id),
           {:ok, rows} <-
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
        _other -> {:halt, corrupt("effects", effect_id, :invalid_command_owner)}
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
           true <- Map.has_key?(effects, effect_id),
           %{command_id: command_id} <- effects[effect_id],
           {:ok, %{result: %{"disposition" => "accepted"}}} <-
             read_command_owner(conn, command_id),
           {:ok, [[reservation_count]]} <-
             query(conn, "SELECT count(*) FROM reservations WHERE claim_id = ?", [
               reservation.claim_id
             ]),
           true <- reservation_count == 1 do
        {:cont, :ok}
      else
        false -> {:halt, corrupt("reservations", reservation_id, :required_relation_missing)}
        nil -> {:halt, corrupt("reservations", reservation_id, :required_relation_missing)}
        {:error, _reason} = error -> {:halt, error}
        _other -> {:halt, corrupt("reservations", reservation_id, :invalid_command_owner)}
      end
    end)
  end

  defp validate_sequence_frontier(conn) do
    with {:ok, [[count, minimum, maximum]]} <-
           query(
             conn,
             "SELECT count(*), coalesce(min(seq), 0), coalesce(max(seq), 0) FROM events"
           ),
         {:ok, sequence_rows} <-
           query(conn, "SELECT name, seq FROM sqlite_sequence ORDER BY name"),
         true <-
           (count == 0 and minimum == 0 and maximum == 0 and sequence_rows == []) or
             (count > 0 and minimum == 1 and maximum == count and
                sequence_rows == [["events", maximum]]) do
      :ok
    else
      false -> corrupt("sqlite_sequence", "events", :invalid_sequence)
      {:error, _reason} = error -> error
      _ -> corrupt("events", "sequence", :sequence_gap)
    end
  end

  defp validate_foreign_keys(conn) do
    case query(conn, "PRAGMA foreign_key_check") do
      {:ok, []} -> :ok
      {:ok, rows} -> corrupt("sqlite", "physical", rows)
      {:error, _reason} = error -> error
    end
  end

  defp event_carrier_matches?(event, nil, nil),
    do: event["payload"]["projection"] == nil

  defp event_carrier_matches?(event, namespace, entity_id) do
    case event["payload"]["projection"] do
      %{"namespace" => ^namespace, "entity_id" => ^entity_id} -> true
      _other -> false
    end
  end

  defp validate_scoped_ledgers(conn, reservations) do
    Enum.reduce_while(reservations, :ok, fn {_id, reservation}, :ok ->
      case read_ledger(conn, reservation.generation_id) do
        {:ok, %{}} ->
          {:cont, :ok}

        {:ok, :absent} ->
          {:halt, corrupt("reservations", reservation.id, :required_ledger_generation_missing)}

        {:error, _reason} = error ->
          {:halt, error}
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

  defp digest_row(row, %{count: count, hash: hash} = acc) do
    encoded = :erlang.term_to_binary(row, [:deterministic])
    frame = <<byte_size(encoded)::unsigned-big-64, encoded::binary>>
    %{acc | count: count + 1, hash: :crypto.hash_update(hash, frame)}
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

  defp contiguous?(values) do
    case values do
      [] -> true
      [first | rest] -> rest == Enum.to_list((first + 1)..(first + length(rest))//1)
    end
  end

  defp valid_identity?(value), do: is_binary(value) and value != "" and String.valid?(value)
  defp reverse_ok({:ok, values}), do: {:ok, Enum.reverse(values)}
  defp reverse_ok(error), do: error
  defp corrupt(table, identity, reason), do: {:error, corrupt_value(table, identity, reason)}
  defp corrupt_value(table, identity, reason), do: {:authority_corrupt, table, identity, reason}
end
