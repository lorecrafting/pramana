defmodule PramanaFoundry.DurableStore.RecordCodec do
  @moduledoc false

  alias PramanaFoundry.DurableStore.Encoding

  @bundle ~w(schema_version result events projections intents)
  @result ~w(schema_version disposition reason_code)
  @stored_result ~w(schema_version disposition reason_code committed_seq)
  @event ~w(schema_version event_id type payload)
  @projection ~w(schema_version namespace entity_id expected_revision revision last_event_id value)
  @intent ~w(schema_version effect_id request_digest status value)
  @claim ~w(schema_version claim_id effect_id writer_epoch status value)
  @reservation ~w(schema_version reservation_id generation_id claim_id dimension units status value)
  @candidate_ledger ~w(schema_version generation_id parent_generation_id allocation consumed)
  @ledger ~w(schema_version generation_id parent_generation_id revision allocation consumed)
  @legacy_record ~w(schema_version source_digest line_number byte_start byte_end record_digest valid error raw_record_digest)
  @command_request ~w(domain schema_version actor_id command)
  @command ~w(schema_version command_id expected_revisions type target_ids payload)
  @command_types ~w(legacy_event_append enqueue steer pause resume cancel reset propose submit_artifact submit_review request_effect record_receipt)
  @manifest ~w(schema_version source_path archived_path source_digest source_bytes byte_range line_count valid_count invalid_count errors)
  @manifest_error ~w(line byte_start byte_end record_digest error)
  @event_types ~w(legacy_event ticket_created ticket_enqueued ticket_steered ticket_paused ticket_resumed ticket_cancelled effect_requested receipt_recorded)
  @intent_types ~w(launch prompt check freeze build integrate activate cleanup git_update)

  def normalize_bundle(value) do
    with {:ok, map} <- normalize_map(value),
         :ok <- supported_version(map),
         :ok <- keys(map, ~w(schema_version result), @bundle),
         {:ok, result} <- normalize(:candidate_result, map["result"]),
         {:ok, events} <- normalize_list(Map.get(map, "events", []), :event),
         {:ok, projections} <- normalize_list(Map.get(map, "projections", []), :projection),
         {:ok, intents} <- normalize_list(Map.get(map, "intents", []), :intent),
         normalized <- %{
           "schema_version" => 1,
           "result" => result,
           "events" => events,
           "projections" => projections,
           "intents" => intents
         },
         {:ok, _plan} <- projection_plan(events, projections) do
      {:ok, normalized}
    else
      {:error, _reason} = error -> error
      _ -> {:error, :invalid_bundle}
    end
  end

  def normalize(:candidate_result, value) do
    with {:ok, map} <- normalize_map(value),
         :ok <- supported_version(map),
         :ok <- keys(map, ~w(schema_version disposition), @result),
         false <- Map.has_key?(map, "committed_seq"),
         normalized <- Map.put_new(map, "reason_code", nil),
         :ok <- result_semantics(normalized) do
      {:ok, normalized}
    else
      true -> {:error, :candidate_committed_seq_forbidden}
      {:error, _reason} = error -> error
      _ -> {:error, :invalid_result}
    end
  end

  def normalize(:result, value) do
    with {:ok, map} <- normalize_map(value),
         :ok <- supported_version(map),
         :ok <- keys(map, @stored_result, @stored_result),
         :ok <- result_semantics(map),
         seq when is_integer(seq) and seq >= 0 <- map["committed_seq"] do
      {:ok, map}
    else
      {:error, _reason} = error -> error
      _ -> {:error, :invalid_result}
    end
  end

  def normalize(:event, value) do
    with {:ok, map} <- normalize_map(value),
         :ok <- keys(map, @event, @event),
         true <- map["schema_version"] == 1,
         :ok <- nonempty(map, ~w(event_id type)),
         true <- map["type"] in @event_types,
         true <- plain_map?(map["payload"]),
         :ok <- validate_projection_payload(map["payload"]) do
      {:ok, map}
    else
      {:error, _reason} = error -> error
      _ -> {:error, :invalid_event}
    end
  end

  def normalize(:projection, value) do
    with {:ok, map} <- normalize_map(value),
         :ok <- keys(map, @projection, @projection),
         true <- map["schema_version"] == 1,
         :ok <- nonempty(map, ~w(namespace entity_id last_event_id)),
         expected when is_integer(expected) and expected >= -1 <- map["expected_revision"],
         revision when is_integer(revision) and revision == expected + 1 <- map["revision"],
         true <- plain_map?(map["value"]) do
      {:ok, map}
    else
      {:error, _reason} = error -> error
      _ -> {:error, :invalid_projection}
    end
  end

  def normalize(:intent, value) do
    with {:ok, map} <- normalize_map(value),
         :ok <- keys(map, @intent, @intent),
         true <- map["schema_version"] == 1,
         :ok <- nonempty(map, ~w(effect_id request_digest)),
         "pending" <- map["status"],
         true <- plain_map?(map["value"]),
         operation when operation in @intent_types <- map["value"]["operation"],
         {:ok, expected_digest} <-
           Encoding.semantic_digest("pramana-foundry-effect-request-v1", %{
             "effect_id" => map["effect_id"],
             "operation" => map["value"]
           }),
         ^expected_digest <- map["request_digest"] do
      {:ok, map}
    else
      {:error, _reason} = error -> error
      _ -> {:error, :invalid_intent}
    end
  end

  def normalize(:claim, value) do
    with {:ok, map} <- normalize_map(value),
         :ok <- keys(map, @claim, @claim),
         true <- map["schema_version"] == 1,
         :ok <- nonempty(map, ~w(claim_id effect_id writer_epoch)),
         "claimed" <- map["status"],
         %{"verified" => true} <- map["value"] do
      {:ok, map}
    else
      {:error, _reason} = error -> error
      _ -> {:error, :invalid_claim}
    end
  end

  def normalize(:reservation, value) do
    with {:ok, map} <- normalize_map(value),
         :ok <- keys(map, @reservation, @reservation),
         true <- map["schema_version"] == 1,
         :ok <- nonempty(map, ~w(reservation_id generation_id claim_id dimension)),
         units when is_integer(units) and units > 0 <- map["units"],
         "reserved" <- map["status"],
         %{"verified" => true} <- map["value"] do
      {:ok, map}
    else
      {:error, _reason} = error -> error
      _ -> {:error, :invalid_reservation}
    end
  end

  def normalize(:candidate_ledger_generation, value) do
    with {:ok, map} <- normalize_map(value),
         :ok <- keys(map, @candidate_ledger, @candidate_ledger),
         1 <- map["schema_version"],
         :ok <- nonempty(map, ~w(generation_id)),
         nil <- map["parent_generation_id"],
         allocation when is_integer(allocation) and allocation >= 0 <- map["allocation"],
         consumed when is_integer(consumed) and consumed >= 0 and consumed <= allocation <-
           map["consumed"] do
      {:ok, map}
    else
      {:error, _reason} = error -> error
      _ -> {:error, :unsupported_ledger_generation}
    end
  end

  def normalize(:ledger_generation, value) do
    with {:ok, map} <- normalize_map(value),
         :ok <- keys(map, @ledger, @ledger),
         1 <- map["schema_version"],
         :ok <- nonempty(map, ~w(generation_id)),
         nil <- map["parent_generation_id"],
         0 <- map["revision"],
         allocation when is_integer(allocation) and allocation >= 0 <- map["allocation"],
         consumed when is_integer(consumed) and consumed >= 0 and consumed <= allocation <-
           map["consumed"] do
      {:ok, map}
    else
      {:error, _reason} = error -> error
      _ -> {:error, :unsupported_ledger_generation}
    end
  end

  def normalize(:legacy_record, value) do
    with {:ok, map} <- normalize_map(value),
         :ok <- keys(map, @legacy_record, @legacy_record),
         1 <- map["schema_version"],
         :ok <- nonempty(map, ~w(source_digest record_digest raw_record_digest)),
         true <- lowercase_digest?(map["source_digest"]),
         true <- lowercase_digest?(map["record_digest"]),
         true <- lowercase_digest?(map["raw_record_digest"]),
         line when is_integer(line) and line > 0 <- map["line_number"],
         start when is_integer(start) and start >= 0 <- map["byte_start"],
         finish when is_integer(finish) and finish >= start <- map["byte_end"],
         true <- is_boolean(map["valid"]),
         :ok <- legacy_error(map["valid"], map["error"]) do
      {:ok, map}
    else
      {:error, _reason} = error -> error
      _ -> {:error, :invalid_legacy_record}
    end
  end

  def normalize(:command_request, value) do
    with {:ok, map} <- normalize_map(value),
         :ok <- keys(map, @command_request, @command_request),
         "pramana-foundry-command-v1" <- map["domain"],
         1 <- map["schema_version"],
         :ok <- nonempty(map, ~w(actor_id)),
         {:ok, command} <- normalize(:command, map["command"]) do
      {:ok, Map.put(map, "command", command)}
    else
      {:error, _reason} = error -> error
      _ -> {:error, :invalid_command_request}
    end
  end

  def normalize(:command, value) do
    with {:ok, map} <- normalize_map(value),
         :ok <- supported_version(map),
         :ok <- keys(map, @command, @command),
         :ok <- nonempty(map, ~w(command_id type)),
         true <- map["type"] in @command_types,
         true <- plain_map?(map["expected_revisions"]),
         :ok <- revision_reads(map["expected_revisions"]),
         true <- plain_map?(map["target_ids"]),
         true <- plain_map?(map["payload"]) do
      {:ok, map}
    else
      {:error, _reason} = error -> error
      _ -> {:error, :invalid_command}
    end
  end

  def normalize(:import_manifest, value) do
    with {:ok, map} <- normalize_map(value),
         :ok <- keys(map, @manifest, @manifest),
         1 <- map["schema_version"],
         :ok <- nonempty(map, ~w(source_path archived_path source_digest)),
         true <- lowercase_digest?(map["source_digest"]),
         true <- nonnegative_integer?(map["source_bytes"]),
         true <- nonnegative_integer?(map["line_count"]),
         true <- nonnegative_integer?(map["valid_count"]),
         true <- nonnegative_integer?(map["invalid_count"]),
         true <- map["valid_count"] + map["invalid_count"] == map["line_count"],
         :ok <- byte_range(map["byte_range"], map["source_bytes"]),
         :ok <- manifest_errors(map["errors"], map["invalid_count"]) do
      {:ok, map}
    else
      {:error, _reason} = error -> error
      _ -> {:error, :invalid_import_manifest}
    end
  end

  def normalize(:import_placeholder, value) do
    with {:ok, map} <- normalize_map(value),
         :ok <- keys(map, ~w(schema_version status source_digest), ~w(schema_version status source_digest)),
         1 <- map["schema_version"],
         "importing" <- map["status"],
         true <- lowercase_digest?(map["source_digest"]) do
      {:ok, map}
    else
      {:error, _reason} = error -> error
      _ -> {:error, :invalid_import_placeholder}
    end
  end

  def normalize(:import_placeholder, value) do
    with {:ok, map} <- normalize_map(value),
         :ok <-
           keys(
             map,
             ~w(schema_version status source_digest),
             ~w(schema_version status source_digest)
           ),
         1 <- map["schema_version"],
         "importing" <- map["status"],
         true <- lowercase_digest?(map["source_digest"]) do
      {:ok, map}
    else
      {:error, _reason} = error -> error
      _ -> {:error, :invalid_import_placeholder}
    end
  end

  def normalize(:scaffold, value) do
    with {:ok, map} <- normalize_map(value),
         :ok <- keys(map, ~w(schema_version), ~w(schema_version)),
         1 <- map["schema_version"] do
      {:ok, map}
    else
      {:error, _reason} = error -> error
      _ -> {:error, :invalid_scaffold}
    end
  end

  def materialize_result(candidate, committed_seq)
      when is_integer(committed_seq) and committed_seq >= 0 do
    with {:ok, normalized} <- normalize(:candidate_result, candidate),
         stored <- Map.put(normalized, "committed_seq", committed_seq),
         {:ok, stored} <- normalize(:result, stored) do
      {:ok, stored}
    end
  end

  def materialize_result(_candidate, _seq), do: {:error, :invalid_committed_seq}

  def encode(type, value) do
    with {:ok, normalized} <- normalize(type, value),
         {:ok, bytes} <- Encoding.json(normalized) do
      {:ok, bytes}
    end
  end

  def decode(type, bytes) when is_binary(bytes) do
    with {:ok, decoded} <- decode_json(bytes),
         {:ok, normalized} <- normalize(type, decoded),
         :ok <- canonical_bytes(type, bytes, normalized) do
      {:ok, normalized}
    end
  end

  def decode(_type, _bytes), do: {:error, :not_binary}

  def decode_bound(:result, bytes, %{
        schema_version: schema,
        disposition: disposition,
        reason_code: reason,
        committed_seq: seq
      }) do
    with {:ok, value} <- decode(:result, bytes),
         true <- value["schema_version"] == schema,
         true <- value["disposition"] == disposition,
         true <- value["reason_code"] == reason,
         true <- value["committed_seq"] == seq do
      {:ok, value}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :relational_binding_mismatch}
    end
  end

  def decode_bound(:event, bytes, %{schema_version: schema, event_id: id, type: type}) do
    with {:ok, value} <- decode(:event, bytes),
         true <-
           value["schema_version"] == schema and value["event_id"] == id and value["type"] == type do
      {:ok, value}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :relational_binding_mismatch}
    end
  end

  def decode_bound(:projection, bytes, columns) do
    with {:ok, value} <- decode(:projection, bytes),
         true <- value["schema_version"] == columns.schema_version,
         true <- value["namespace"] == columns.namespace,
         true <- value["entity_id"] == columns.entity_id,
         true <- value["revision"] == columns.revision,
         true <- value["last_event_id"] == columns.last_event_id do
      {:ok, value}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :relational_binding_mismatch}
    end
  end

  def decode_bound(:intent, bytes, columns) do
    with {:ok, value} <- decode(:intent, bytes),
         true <- value["schema_version"] == columns.schema_version,
         true <- value["effect_id"] == columns.effect_id,
         true <- value["request_digest"] == columns.request_digest,
         true <- value["status"] == columns.status do
      {:ok, value}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :relational_binding_mismatch}
    end
  end

  def decode_bound(:claim, bytes, columns) do
    with {:ok, value} <- decode(:claim, bytes),
         true <- value["schema_version"] == columns.schema_version,
         true <- value["claim_id"] == columns.claim_id,
         true <- value["effect_id"] == columns.effect_id,
         true <- value["writer_epoch"] == columns.writer_epoch,
         true <- value["status"] == columns.status do
      {:ok, value}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :relational_binding_mismatch}
    end
  end

  def decode_bound(:reservation, bytes, columns) do
    with {:ok, value} <- decode(:reservation, bytes),
         true <- value["schema_version"] == columns.schema_version,
         true <- value["reservation_id"] == columns.reservation_id,
         true <- value["generation_id"] == columns.generation_id,
         true <- value["claim_id"] == columns.claim_id,
         true <- value["dimension"] == columns.dimension,
         true <- value["units"] == columns.units,
         true <- value["status"] == columns.status do
      {:ok, value}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :relational_binding_mismatch}
    end
  end

  def decode_bound(:ledger_generation, value, columns) when is_map(value) do
    with {:ok, normalized} <- normalize(:ledger_generation, value),
         true <- normalized["generation_id"] == columns.generation_id,
         true <- normalized["parent_generation_id"] == columns.parent_generation_id,
         true <- normalized["schema_version"] == columns.schema_version,
         true <- normalized["revision"] == columns.revision,
         true <- normalized["allocation"] == columns.allocation,
         true <- normalized["consumed"] == columns.consumed do
      {:ok, normalized}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :relational_binding_mismatch}
    end
  end

  def decode_bound(:legacy_record, value, columns) when is_map(value) do
    with {:ok, normalized} <- normalize(:legacy_record, value),
         true <- normalized["source_digest"] == columns.source_digest,
         true <- normalized["line_number"] == columns.line_number,
         true <- normalized["byte_start"] == columns.byte_start,
         true <- normalized["byte_end"] == columns.byte_end,
         true <- normalized["record_digest"] == columns.record_digest,
         true <- normalized["valid"] == columns.valid,
         true <- normalized["error"] == columns.error do
      {:ok, normalized}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :relational_binding_mismatch}
    end
  end

  def decode_bound(:command_request, bytes, columns) do
    with {:ok, value} <- decode(:command_request, bytes),
         true <- value["schema_version"] == columns.protocol_version,
         true <- value["actor_id"] == columns.actor_id,
         true <- Encoding.digest(bytes) == columns.request_digest,
         true <- value["command"]["command_id"] == columns.command_id,
         true <- value["command"]["type"] == columns.command_type,
         true <- columns.input_id == "input:" <> columns.command_id do
      {:ok, value}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :relational_binding_mismatch}
    end
  end

  def decode_bound(:import_manifest, bytes, columns) do
    with {:ok, value} <- decode(:import_manifest, bytes),
         true <- value["source_digest"] == columns.source_digest,
         true <- value["source_path"] == columns.source_path,
         true <- value["archived_path"] == columns.archived_path,
         true <- value["source_bytes"] == columns.source_bytes,
         true <- value["line_count"] == columns.line_count,
         true <- value["valid_count"] == columns.valid_count,
         true <- value["invalid_count"] == columns.invalid_count do
      {:ok, value}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :relational_binding_mismatch}
    end
  end

  def projection_plan(events, projections) do
    transitions =
      Enum.flat_map(events, fn event ->
        case event["payload"]["projection"] do
          nil -> []
          transition -> [%{"event_id" => event["event_id"], "transition" => transition}]
        end
      end)

    with true <- unique?(Enum.map(events, & &1["event_id"])),
         true <- length(transitions) == length(projections),
         true <- unique?(Enum.map(projections, & &1["last_event_id"])),
         :ok <- match_transitions(transitions, projections) do
      {:ok, Enum.zip(transitions, projections)}
    else
      false -> {:error, :projection_transition_bijection}
      {:error, _reason} = error -> error
    end
  end

  def apply_projection(state, {carrier, projection}) do
    transition = carrier["transition"]
    key = {transition["namespace"], transition["entity_id"]}

    expected =
      case Map.get(state, key) do
        nil -> -1
        prior -> prior.revision
      end

    if projection["expected_revision"] == expected and transition["revision"] == expected + 1 do
      {:ok,
       Map.put(state, key, %{
         revision: transition["revision"],
         last_event_id: carrier["event_id"],
         value: transition["value"]
       })}
    else
      {:error, :projection_revision_sequence}
    end
  end

  def reduce_projection_plan(plan, initial_state) when is_list(plan) and is_map(initial_state) do
    reduce_transitions(plan, initial_state)
  end

  def reconstruct(event_values, stored) do
    transitions =
      Enum.flat_map(event_values, fn event ->
        case event["payload"]["projection"] do
          nil ->
            []

          transition ->
            [
              {%{"event_id" => event["event_id"], "transition" => transition},
               transition_to_projection(event, transition)}
            ]
        end
      end)

    with {:ok, reconstructed} <- reduce_transitions(transitions, %{}),
         true <- reconstructed == stored do
      {:ok, reconstructed}
    else
      false -> {:error, :projection_replay_mismatch}
      {:error, _reason} = error -> error
    end
  end

  defp match_transitions(transitions, projections) do
    Enum.zip(transitions, projections)
    |> Enum.reduce_while(:ok, fn {carrier, projection}, :ok ->
      transition = carrier["transition"]

      cond do
        carrier["event_id"] != projection["last_event_id"] ->
          {:halt, {:error, :projection_event_missing}}

        Map.take(transition, ~w(namespace entity_id revision value)) !=
            Map.take(projection, ~w(namespace entity_id revision value)) ->
          {:halt, {:error, :projection_transition_mismatch}}

        true ->
          {:cont, :ok}
      end
    end)
  end

  defp transition_to_projection(event, transition) do
    %{
      "expected_revision" => transition["revision"] - 1,
      "revision" => transition["revision"],
      "last_event_id" => event["event_id"]
    }
  end

  defp validate_projection_payload(payload) do
    if Map.has_key?(payload, "projection") do
      with {:ok, transition} <- normalize_map(payload["projection"]),
           :ok <-
             keys(
               transition,
               ~w(namespace entity_id revision value),
               ~w(namespace entity_id revision value)
             ),
           :ok <- nonempty(transition, ~w(namespace entity_id)),
           revision when is_integer(revision) and revision >= 0 <- transition["revision"],
           true <- plain_map?(transition["value"]) do
        :ok
      else
        {:error, _reason} = error -> error
        _ -> {:error, :invalid_projection_transition}
      end
    else
      :ok
    end
  end

  defp reduce_transitions(transitions, state) do
    Enum.reduce_while(transitions, {:ok, state}, fn transition, {:ok, acc} ->
      case apply_projection(acc, transition) do
        {:ok, next} -> {:cont, {:ok, next}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp result_semantics(map) do
    case {map["schema_version"], map["disposition"], map["reason_code"]} do
      {1, "accepted", nil} ->
        :ok

      {1, disposition, reason}
      when disposition in ["rejected", "blocked"] and is_binary(reason) and reason != "" ->
        :ok

      _ ->
        {:error, :invalid_result_semantics}
    end
  end

  defp normalize_list(value, type) when is_list(value) do
    Enum.reduce_while(value, {:ok, []}, fn item, {:ok, acc} ->
      case normalize(type, item) do
        {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> then(fn
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end)
  end

  defp normalize_list(_value, _type), do: {:error, :invalid_collection}

  defp normalize_map(value) when is_map(value) and not is_struct(value) do
    Enum.reduce_while(value, {:ok, %{}}, fn {key, item}, {:ok, acc} ->
      normalized_key =
        cond do
          is_binary(key) -> key
          is_atom(key) -> Atom.to_string(key)
          true -> nil
        end

      cond do
        is_nil(normalized_key) or normalized_key == "" or not String.valid?(normalized_key) ->
          {:halt, {:error, :invalid_key}}

        Map.has_key?(acc, normalized_key) ->
          {:halt, {:error, :duplicate_field}}

        true ->
          {:cont, {:ok, Map.put(acc, normalized_key, item)}}
      end
    end)
  end

  defp normalize_map(_value), do: {:error, :invalid_object}

  defp keys(map, required, allowed) do
    present = Map.keys(map)

    cond do
      Enum.any?(required, &(&1 not in present)) -> {:error, :missing_field}
      Enum.any?(present, &(&1 not in allowed)) -> {:error, :unknown_field}
      true -> :ok
    end
  end

  defp nonempty(map, fields) do
    if Enum.all?(fields, &(is_binary(map[&1]) and map[&1] != "")),
      do: :ok,
      else: {:error, :invalid_identity}
  end

  defp supported_version(%{"schema_version" => 1}), do: :ok
  defp supported_version(%{"schema_version" => _version}), do: {:error, :unsupported_version}
  defp supported_version(_map), do: {:error, :missing_field}

  defp byte_range(value, source_bytes) do
    with {:ok, range} <- normalize_map(value),
         :ok <- keys(range, ~w(start end), ~w(start end)),
         0 <- range["start"],
         ^source_bytes <- range["end"] do
      :ok
    else
      {:error, _reason} = error -> error
      _ -> {:error, :invalid_byte_range}
    end
  end

  defp manifest_errors(errors, invalid_count) when is_list(errors) do
    with true <- proper_list?(errors) and length(errors) == invalid_count do
      Enum.reduce_while(errors, :ok, fn error, :ok ->
        with {:ok, item} <- normalize_map(error),
             :ok <- keys(item, @manifest_error, @manifest_error),
             true <- is_integer(item["line"]) and item["line"] > 0,
             true <- nonnegative_integer?(item["byte_start"]),
             true <- is_integer(item["byte_end"]) and item["byte_end"] >= item["byte_start"],
             true <- lowercase_digest?(item["record_digest"]),
             true <- is_binary(item["error"]) and item["error"] != "" do
          {:cont, :ok}
        else
          _ -> {:halt, {:error, :invalid_manifest_error}}
        end
      end)
    else
      false -> {:error, :invalid_manifest_error_count}
    end
  end

  defp manifest_errors(_errors, _invalid_count), do: {:error, :invalid_manifest_errors}

  defp legacy_error(true, nil), do: :ok
  defp legacy_error(false, error) when is_binary(error) and error != "", do: :ok
  defp legacy_error(_valid, _error), do: {:error, :invalid_legacy_error}

  defp revision_reads(reads) do
    if Enum.all?(reads, fn {key, value} ->
         is_binary(key) and key != "" and (value == "absent" or (is_integer(value) and value >= 0))
       end),
       do: :ok,
       else: {:error, :invalid_expected_revisions}
  end

  defp lowercase_digest?(value) when is_binary(value),
    do:
      byte_size(value) == 64 and value == String.downcase(value) and
        Regex.match?(~r/\A[0-9a-f]+\z/, value)

  defp lowercase_digest?(_value), do: false
  defp nonnegative_integer?(value), do: is_integer(value) and value >= 0

  defp plain_map?(value), do: is_map(value) and not is_struct(value)
  defp unique?(values), do: length(values) == length(Enum.uniq(values))

  defp decode_json(bytes) do
    {:ok, bytes |> :json.decode() |> decoded_nulls()}
  rescue
    _ -> {:error, :malformed_json}
  catch
    _, _ -> {:error, :malformed_json}
  end

  defp canonical_bytes(:command_request, bytes, normalized) do
    with {:ok, canonical} <- Encoding.canonical(normalized),
         true <- canonical == bytes do
      :ok
    else
      false -> {:error, :noncanonical_json}
      {:error, reason} -> {:error, reason}
    end
  end

  defp canonical_bytes(_type, bytes, normalized) do
    with {:ok, canonical} <- Encoding.json(normalized),
         true <- canonical == bytes do
      :ok
    else
      false -> {:error, :noncanonical_json}
      {:error, reason} -> {:error, reason}
    end
  end

  defp decoded_nulls(:null), do: nil
  defp decoded_nulls(value) when is_list(value), do: Enum.map(value, &decoded_nulls/1)

  defp decoded_nulls(value) when is_map(value),
    do: Map.new(value, fn {key, item} -> {key, decoded_nulls(item)} end)

  defp decoded_nulls(value), do: value
end
