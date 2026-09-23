defmodule PramanaFoundry.DurableStore.ProtectedPrimitives do
  @moduledoc false

  alias PramanaFoundry.DurableStore.{Database, Encoding, TransitionPlan}

  @dimensions ~w(starts.pm starts.developer starts.reviewer starts.check starts.build operations.integration operations.activation model_requests validations)
  @operation_types ~w(set_policy set_control append_inbox seal_inbox grant_ledger delegate_allocation return_allocation reserve release_reservation close_generation reset_generation create_effect claim_effect reclaim_claim issue_claim cancel_effect settle_claim close_attempt)
  @closed_effect_statuses ~w(succeeded failed non_started cancelled)
  @closed_reservation_statuses ~w(consumed released retired)
  @effect_observation_sections ~w(claims receipts reservations leases)
  @effect_observation_max_items 50
  @effect_observation_max_offset 1_000_000
  @effect_observation_min_bytes 1_024
  @effect_observation_max_bytes 262_144
  @effect_observation_max_scalar_bytes 256

  @doc false
  def supported_operation_type?(type), do: type in @operation_types

  @doc false
  def execute(conn, actor_id, request, writer_epoch, fault \\ nil) do
    with :ok <- identity(actor_id),
         :ok <- identity(writer_epoch),
         {:ok, request} <- normalize_request(request),
         :ok <- validate_public_command_identity(conn, request["command_id"]),
         {:ok, digest} <- request_digest(actor_id, request) do
      case existing_command(conn, request["command_id"], actor_id, digest) do
        {:ok, result} ->
          {:ok, result, :idempotent}

        {:error, :not_found} ->
          with :ok <- validate_operation_envelope(request["operation"]) do
            execute_new(conn, actor_id, request, writer_epoch, digest, fault)
            |> case do
              {:ok, result} ->
                if fault == :after_commit_before_reply,
                  do: {:error, {:storage_unavailable, :injected_after_commit_before_reply}},
                  else: {:ok, result, :committed}

              {:error, :invalid_fields} ->
                {:error, :invalid_protected_request}

              {:error, :invalid_identity} ->
                {:error, :invalid_protected_request}

              {:error, reason} ->
                {:error, {:storage_unavailable, reason}}
            end
          else
            _ -> {:error, :invalid_protected_request}
          end

        {:error, _reason} = error ->
          error
      end
    end
  end

  @doc false
  def execute_in_transaction(conn, actor_id, request, writer_epoch) do
    with :ok <- identity(actor_id),
         :ok <- identity(writer_epoch),
         {:ok, request} <- normalize_request(request),
         {:ok, digest} <- request_digest(actor_id, request),
         :ok <- validate_operation_envelope(request["operation"]) do
      case existing_command(conn, request["command_id"], actor_id, digest) do
        {:ok, result} ->
          {:ok, result, :idempotent}

        {:error, :not_found} ->
          case apply_new(conn, actor_id, request, writer_epoch) do
            {:ok, facts} ->
              with {:ok, result} <-
                     persist_result(
                       conn,
                       actor_id,
                       request,
                       digest,
                       "accepted",
                       nil,
                       facts
                     ) do
                {:ok, result, :accepted}
              end

            {:quarantine, reason, facts} ->
              with {:ok, result} <-
                     persist_result(
                       conn,
                       actor_id,
                       request,
                       digest,
                       "rejected",
                       Atom.to_string(reason),
                       facts
                     ) do
                {:ok, result, :quarantined}
              end

            {:reject, reason, facts} ->
              with {:ok, result} <-
                     persist_result(
                       conn,
                       actor_id,
                       request,
                       digest,
                       "rejected",
                       Atom.to_string(reason),
                       facts
                     ) do
                {:ok, result, :rejected}
              end

            {:error, _reason} = error ->
              error
          end

        {:error, _reason} = error ->
          error
      end
    else
      _ -> {:error, :invalid_protected_request}
    end
  end

  @doc false
  def required_revisions(conn, operation), do: required_reads(conn, operation)

  @doc false
  def required_bundle_prestate_revisions(conn, operation, prior_operations) do
    with {:ok, required} <- required_reads(conn, operation),
         {:ok, extra_keys} <- staged_prestate_keys(conn, operation, prior_operations) do
      Enum.reduce_while(extra_keys, {:ok, required}, fn key, {:ok, acc} ->
        case current_revision(conn, key) do
          {:ok, revision} -> {:cont, {:ok, Map.put(acc, key, revision)}}
          {:error, _reason} = error -> {:halt, error}
        end
      end)
    end
  end

  defp staged_prestate_keys(
         conn,
         %{"type" => "settle_claim", "outcome" => "non_started", "claim_id" => claim_id},
         prior_operations
       ) do
    with %{"effect_id" => effect_id} <-
           Enum.find(prior_operations, fn op ->
             op["type"] == "claim_effect" and op["claim_id"] == claim_id
           end),
         {:ok, lineage, predecessor} <-
           staged_effect_lineage(conn, effect_id, prior_operations) do
      {:ok, ["settlement/" <> effect_id, lineage | predecessor]}
    else
      nil -> {:ok, []}
      _ -> {:error, :invalid_staged_settlement_dependency}
    end
  end

  defp staged_prestate_keys(_conn, _operation, _prior_operations), do: {:ok, []}

  defp staged_effect_lineage(conn, effect_id, prior_operations) do
    case Enum.find(prior_operations, fn op ->
           op["type"] == "create_effect" and op["effect_id"] == effect_id
         end) do
      effect when is_map(effect) ->
        with role when is_binary(role) <- get_in(effect, ["request", "role"]),
             generation when is_integer(generation) <-
               get_in(effect, ["request", "phase_generation"]),
             ticket_id when is_binary(ticket_id) <- effect["ticket_id"],
             attempt_id when is_binary(attempt_id) <- effect["attempt_id"] do
          owner = assignment_id(ticket_id, attempt_id, role)
          predecessor = optional_settlement_predecessor(effect["predecessor_effect_id"])
          {:ok, encoded_infrastructure_lineage_key(role, owner, generation), predecessor}
        else
          _ -> {:error, :invalid_staged_effect}
        end

      nil ->
        with {:ok, effect} <- load_effect(conn, effect_id) do
          {:ok, infrastructure_lineage_key(effect),
           optional_settlement_predecessor(effect.predecessor_effect_id)}
        end
    end
  end

  defp optional_settlement_predecessor(id) when is_binary(id), do: ["settlement/" <> id]
  defp optional_settlement_predecessor(_id), do: []

  @doc false
  def persist_nonstart_settlement(conn, operation, facts) do
    effect = facts["effect"]
    claim = facts["claim"]
    receipt = facts["receipt"]
    payload = operation["payload"]

    with "non_started" <- operation["outcome"],
         true <- is_map(effect) and is_map(claim) and is_map(receipt),
         true <- receipt["outcome"] == "non_started",
         true <- receipt["claim_id"] == claim["claim_id"],
         failure_class when is_binary(failure_class) and failure_class != "" <-
           payload["failure_class"],
         role when role in ~w(developer reviewer pm check freeze build integration activation) <-
           effect["role"],
         work_owner when is_binary(work_owner) and work_owner != "" <- effect["assignment_id"],
         generation when is_integer(generation) and generation >= 0 <- effect["phase_generation"],
         {:ok, existing} <- existing_infrastructure_settlement(conn, effect["effect_id"]),
         {:ok, [[prior_count]]} <-
           Database.query(
             conn,
             "SELECT count(*) FROM root_infrastructure_settlements WHERE role = ? AND work_owner = ? AND infrastructure_generation = ?",
             [role, work_owner, generation]
           ),
         ordinal <- if(existing == :absent, do: prior_count + 1, else: existing["ordinal"]),
         :ok <-
           if(existing == :absent,
             do:
               validate_nonstart_predecessor(
                 conn,
                 effect,
                 role,
                 work_owner,
                 generation,
                 ordinal
               ),
             else: :ok
           ),
         state <- %{
           "schema_version" => 1,
           "effect_id" => effect["effect_id"],
           "claim_id" => claim["claim_id"],
           "receipt_id" => receipt["receipt_id"],
           "role" => role,
           "work_owner" => work_owner,
           "infrastructure_generation" => generation,
           "predecessor_effect_id" => effect["predecessor_effect_id"],
           "failure_class" => failure_class,
           "ordinal" => ordinal
         },
         {:ok, state} <- persist_or_match_infrastructure_settlement(conn, existing, state) do
      {:ok, state}
    else
      _ -> {:error, :invalid_nonstart_infrastructure_settlement}
    end
  end

  defp existing_infrastructure_settlement(conn, effect_id) do
    with {:ok, rows} <-
           Database.query(
             conn,
             "SELECT state FROM root_infrastructure_settlements WHERE effect_id = ?",
             [effect_id]
           ) do
      case rows do
        [] -> {:ok, :absent}
        [[bytes]] -> decode(bytes)
        _ -> {:error, :duplicate_infrastructure_settlement}
      end
    end
  end

  defp persist_or_match_infrastructure_settlement(conn, :absent, state) do
    with {:ok, bytes} <- encode(state),
         :ok <-
           Database.execute(
             conn,
             "INSERT INTO root_infrastructure_settlements(effect_id, claim_id, receipt_id, role, work_owner, infrastructure_generation, predecessor_effect_id, failure_class, ordinal, state) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
             [
               state["effect_id"],
               state["claim_id"],
               state["receipt_id"],
               state["role"],
               state["work_owner"],
               state["infrastructure_generation"],
               state["predecessor_effect_id"],
               state["failure_class"],
               state["ordinal"],
               {:blob, bytes}
             ]
           ) do
      {:ok, state}
    end
  end

  defp persist_or_match_infrastructure_settlement(_conn, existing, state)
       when existing == state,
       do: {:ok, Map.put(state, "duplicate", true)}

  defp persist_or_match_infrastructure_settlement(_conn, _existing, _state),
    do: {:error, :invalid_nonstart_infrastructure_settlement}

  defp validate_nonstart_predecessor(
         _conn,
         %{"predecessor_effect_id" => nil},
         _role,
         _owner,
         _generation,
         1
       ),
       do: :ok

  defp validate_nonstart_predecessor(conn, effect, role, owner, generation, ordinal) do
    with predecessor when is_binary(predecessor) <- effect["predecessor_effect_id"],
         {:ok, [[^role, ^owner, ^generation, prior_ordinal]]} <-
           Database.query(
             conn,
             "SELECT role, work_owner, infrastructure_generation, ordinal FROM root_infrastructure_settlements WHERE effect_id = ?",
             [predecessor]
           ),
         true <- prior_ordinal + 1 == ordinal do
      :ok
    else
      _ -> {:error, :invalid_nonstart_predecessor}
    end
  end

  @doc """
  Re-derives the discriminator for a past settlement from retained policy history.

  Both the commit path and revalidation use this function. Reading the current policy head
  instead failed closed once policy was revised, which stranded a proved non-start at commit
  time (contract reading Q5: it must still settle) and would report a valid historical
  commit as corrupt on revalidation. `root_policy_history` retains every revision under `PRIMARY KEY(policy_id,
  revision)` with a chain constraint, and its lineage is validated on open, so the limit
  in force at the effect's recorded `policy_revision` is recoverable and integrity-checked.

  Fails closed when the history row is absent, the limit is missing or non-positive, or
  the settlement disagrees with the effect.
  """
  @spec infrastructure_discriminator_at_revision(term(), String.t(), map()) ::
          {:ok, String.t()} | {:error, atom()}
  def infrastructure_discriminator_at_revision(conn, effect_id, settlement)
      when is_map(settlement) do
    with {:ok, effect} <- load_effect(conn, effect_id),
         true <- effect.role == settlement["role"],
         {:ok, [[bytes]]} <-
           Database.query(
             conn,
             "SELECT state FROM root_policy_history WHERE policy_id = ? AND revision = ?",
             [effect.policy_id, effect.policy_revision]
           ),
         {:ok, state} <- decode(bytes),
         limits when is_map(limits) <- get_in(state, ["value", "infrastructure_attempt_limits"]),
         limit when is_integer(limit) and limit > 0 <- Map.get(limits, effect.role),
         ordinal when is_integer(ordinal) and ordinal > 0 <- settlement["ordinal"] do
      if ordinal < limit,
        do: {:ok, "below_infrastructure_limit"},
        else: {:ok, "infrastructure_limit_reached"}
    else
      _ -> {:error, :infrastructure_limit_undecidable}
    end
  end

  def infrastructure_discriminator_at_revision(_conn, _effect_id, _settlement),
    do: {:error, :infrastructure_limit_undecidable}

  defp execute_new(conn, actor_id, request, writer_epoch, digest, fault) do
    Database.transaction(conn, fn ->
      case apply_new(conn, actor_id, request, writer_epoch) do
        {:ok, facts} ->
          persist_committed_result(
            conn,
            actor_id,
            request,
            digest,
            "accepted",
            nil,
            facts,
            fault
          )

        {:quarantine, reason, facts} ->
          persist_committed_result(
            conn,
            actor_id,
            request,
            digest,
            "rejected",
            Atom.to_string(reason),
            facts,
            fault
          )

        {:reject, reason, facts} ->
          {:error, {:semantic_rejection, reason, facts}}

        {:error, _reason} = error ->
          error
      end
    end)
    |> case do
      {:error, {:semantic_rejection, reason, facts}} ->
        Database.transaction(conn, fn ->
          persist_committed_result(
            conn,
            actor_id,
            request,
            digest,
            "rejected",
            Atom.to_string(reason),
            facts,
            fault
          )
        end)

      result ->
        result
    end
  end

  defp persist_committed_result(
         conn,
         actor_id,
         request,
         digest,
         disposition,
         reason,
         facts,
         fault
       ) do
    with {:ok, result} <-
           persist_result(conn, actor_id, request, digest, disposition, reason, facts),
         :ok <- persist_v1_operation(conn, request["command_id"]),
         :ok <- inject(fault, :before_commit) do
      {:ok, result}
    end
  end

  defp persist_v1_operation(conn, command_id) do
    Database.execute(
      conn,
      "INSERT INTO durable_operations(owner_kind, owner_id, ordinal, operation_kind, operation_type, request, result) " <>
        "SELECT 'protected_v1', command_id, 0, 'protected', operation, canonical_request, result FROM root_commands WHERE command_id = ?",
      [command_id]
    )
  end

  defp validate_operation_envelope(%{"type" => type} = operation)
       when type in @operation_types do
    identity_fields =
      case type do
        "set_policy" ->
          ~w(policy_id)

        "set_control" ->
          ~w(control_id)

        type when type in ["append_inbox", "seal_inbox"] ->
          ~w(execution_id)

        "grant_ledger" ->
          ~w(ledger_id)

        "delegate_allocation" ->
          ~w(parent_ledger_id child_ledger_id)

        "return_allocation" ->
          ~w(child_ledger_id)

        "reserve" ->
          ~w(reservation_id ledger_id owner_kind owner_id)

        "release_reservation" ->
          ~w(reservation_id)

        "close_generation" ->
          ~w(ledger_id)

        "reset_generation" ->
          ~w(ledger_id)

        "create_effect" ->
          ~w(effect_id operation scope ticket_id attempt_id execution_id policy_id control_id)

        "claim_effect" ->
          ~w(effect_id claim_id writer_epoch)

        "reclaim_claim" ->
          ~w(claim_id prior_writer_epoch new_writer_epoch proof)

        "issue_claim" ->
          ~w(claim_id writer_epoch)

        "cancel_effect" ->
          ~w(effect_id)

        "settle_claim" ->
          ~w(claim_id receipt_id request_id outcome proof)

        "close_attempt" ->
          ~w(scope ticket_id attempt_id)
      end

    with true <- plain_map?(operation),
         :ok <- identities(operation, identity_fields),
         true <- valid_operation_scalars?(type, operation),
         true <- proper_list?(operation["reservation_ids"] || []),
         true <- Enum.all?(operation["reservation_ids"] || [], &is_binary/1),
         true <- proper_list?(operation["leases"] || []),
         true <-
           Enum.all?(operation["leases"] || [], fn lease ->
             plain_map?(lease) and is_binary(lease["lease_id"]) and
               is_binary(lease["resource_id"])
           end) do
      :ok
    else
      _ -> {:error, :invalid_operation_envelope}
    end
  end

  defp validate_operation_envelope(%{"type" => type}) when is_binary(type), do: :ok
  defp validate_operation_envelope(_operation), do: {:error, :invalid_operation_envelope}

  defp valid_operation_scalars?(type, op)
       when type in ["grant_ledger", "reserve"] do
    nonnegative_integer?(op["generation"]) and positive_integer?(op["units"])
  end

  defp valid_operation_scalars?("delegate_allocation", op) do
    nonnegative_integer?(op["parent_generation"]) and
      nonnegative_integer?(op["child_generation"]) and positive_integer?(op["units"])
  end

  defp valid_operation_scalars?("return_allocation", op),
    do: nonnegative_integer?(op["child_generation"]) and positive_integer?(op["units"])

  defp valid_operation_scalars?("close_generation", op),
    do: nonnegative_integer?(op["generation"])

  defp valid_operation_scalars?("reset_generation", op) do
    nonnegative_integer?(op["old_generation"]) and
      nonnegative_integer?(op["new_generation"]) and positive_integer?(op["units"]) and
      (is_nil(op["parent_ledger_id"]) or is_binary(op["parent_ledger_id"])) and
      (is_nil(op["parent_generation"]) or nonnegative_integer?(op["parent_generation"]))
  end

  defp valid_operation_scalars?("append_inbox", op),
    do: positive_integer?(op["sequence"]) and is_binary(op["item_kind"])

  defp valid_operation_scalars?("seal_inbox", op),
    do: nonnegative_integer?(op["last_sequence"])

  defp valid_operation_scalars?("create_effect", op) do
    nonnegative_integer?(op["policy_revision"]) and nonnegative_integer?(op["control_revision"]) and
      plain_map?(op["request"])
  end

  defp valid_operation_scalars?(_type, _op), do: true

  defp nonnegative_integer?(value), do: is_integer(value) and value >= 0
  defp positive_integer?(value), do: is_integer(value) and value > 0

  @doc false
  def authority_mode(conn) do
    with {:ok, [[root_count]]} <- Database.query(conn, "SELECT count(*) FROM root_commands"),
         {:ok, [[legacy_count]]} <-
           Database.query(
             conn,
             "SELECT (SELECT count(*) FROM claims) + (SELECT count(*) FROM reservations) + (SELECT count(*) FROM ledger_generations) + (SELECT count(*) FROM receipts) + (SELECT count(*) FROM leases)"
           ) do
      case {root_count, legacy_count} do
        {root, 0} when root > 0 -> {:ok, :root}
        {0, legacy} when legacy > 0 -> {:ok, :legacy}
        {0, 0} -> {:ok, :empty_or_legacy}
        _ -> {:error, :conflicting_authority_modes}
      end
    end
  end

  @doc false
  def query(conn, query) do
    with {:ok, query} <- string_map(query),
         1 <- query["schema_version"],
         type when is_binary(type) <- query["type"] do
      case type do
        "inbox" ->
          inbox_fact(conn, query["execution_id"])

        "policy" ->
          simple_fact(conn, "root_policies", "policy_id", query["policy_id"])

        "control" ->
          simple_fact(conn, "root_controls", "control_id", query["control_id"])

        "ledger" ->
          ledger_fact(conn, query["ledger_id"], query["generation"])

        "effect" ->
          effect_fact(conn, query["effect_id"])

        "effect_observation_page" ->
          effect_observation_page(conn, query)

        "claim" ->
          claim_fact(conn, query["claim_id"])

        "reservation" ->
          reservation_fact(conn, query["reservation_id"])

        "receipt" ->
          receipt_fact(conn, query["receipt_id"])

        "lease" ->
          lease_fact(conn, query["lease_id"])

        "command" ->
          command_fact(conn, query["command_id"])

        "infrastructure_settlement" ->
          protected_row(
            conn,
            "SELECT state FROM root_infrastructure_settlements WHERE effect_id = ?",
            [query["effect_id"]]
          )

        "pointer" ->
          pointer_fact(conn, query["pointer_kind"])

        _ ->
          {:error, :unsupported_protected_query}
      end
    else
      _ -> {:error, :invalid_protected_query}
    end
  end

  @doc false
  def root_command_id_exists?(conn, command_id) do
    case Database.query(conn, "SELECT 1 FROM root_commands WHERE command_id = ?", [command_id]) do
      {:ok, []} -> false
      {:ok, [[1]]} -> true
      _ -> true
    end
  end

  @doc false
  def snapshot(conn, writer_epoch) do
    with :ok <- identity(writer_epoch),
         {:ok, metadata_rows} <- Database.query(conn, "SELECT key, value FROM metadata"),
         metadata <- Map.new(metadata_rows, fn [key, value] -> {key, value} end),
         {:ok, [[event_seq]]} <- Database.query(conn, "SELECT coalesce(max(seq), 0) FROM events"),
         {:ok, [[root_seq]]} <-
           Database.query(conn, "SELECT coalesce(max(seq), 0) FROM root_commands"),
         {:ok, authority_mode} <- authority_mode(conn),
         {:ok, revision_frontiers} <- revision_frontiers(conn),
         {:ok, pointers} <- all_pointer_facts(conn) do
      {:ok,
       %{
         "schema_version" => 1,
         "installation_id" => metadata["installation_id"],
         "repository_id" => metadata["repository_id"],
         "writer_epoch" => writer_epoch,
         "sql_schema_version" => metadata["schema_version"],
         "protected_schema_version" => metadata["protected_schema_version"],
         "protocol_version" => metadata["protocol_version"],
         "event_version" => metadata["event_version"],
         "projection_version" => metadata["projection_version"],
         "last_domain_event_sequence" => event_seq,
         "last_protected_command_sequence" => root_seq,
         "authority_mode" => Atom.to_string(authority_mode),
         "fact_revision_frontiers" => revision_frontiers,
         "pointers" => pointers
       }}
    end
  end

  @doc false
  def validate(conn) do
    with :ok <- validate_blob_rows(conn, "root_commands", "result"),
         :ok <- validate_blob_rows(conn, "authenticated_inboxes", "state"),
         :ok <- validate_blob_rows(conn, "authenticated_inbox_items", "item"),
         :ok <- validate_blob_rows(conn, "root_policies", "state"),
         :ok <- validate_blob_rows(conn, "root_policy_history", "state"),
         :ok <- validate_blob_rows(conn, "root_controls", "state"),
         :ok <- validate_blob_rows(conn, "root_control_history", "state"),
         :ok <- validate_blob_rows(conn, "root_ledgers", "state"),
         :ok <- validate_blob_rows(conn, "root_reservations", "state"),
         :ok <- validate_blob_rows(conn, "root_effects", "state"),
         :ok <- validate_blob_rows(conn, "root_claims", "state"),
         :ok <- validate_blob_rows(conn, "root_receipts", "state"),
         :ok <- validate_blob_rows(conn, "root_leases", "state"),
         :ok <- validate_blob_rows(conn, "root_pointers", "state"),
         :ok <- validate_blob_rows(conn, "root_infrastructure_settlements", "state"),
         :ok <- validate_blob_rows(conn, "root_attempt_closures", "state"),
         :ok <- validate_attempt_closures(conn),
         :ok <- validate_atomic_bundle_rows(conn),
         :ok <- validate_root_commands(conn),
         :ok <- validate_simple_history(conn),
         :ok <- validate_root_pointers(conn),
         :ok <- validate_inboxes(conn),
         :ok <- validate_ledgers(conn),
         :ok <- validate_ledger_tree(conn),
         :ok <- validate_reservations(conn),
         :ok <- validate_state_bindings(conn),
         :ok <- validate_effect_relations(conn),
         :ok <- validate_semantic_relations(conn),
         :ok <- validate_authority_command_provenance(conn) do
      :ok
    end
  end

  defp apply_new(conn, actor_id, request, writer_epoch) do
    operation = request["operation"]

    with :ok <- complete_read_set(conn, operation, request["expected_revisions"]) do
      operation =
        case operation["type"] do
          type when type in ["append_inbox", "seal_inbox", "create_effect", "settle_claim"] ->
            Map.put(operation, "authenticated_actor", actor_id)

          type when type in ["set_policy", "set_control"] ->
            Map.put(operation, "root_command_id", request["command_id"])

          type when type in ["claim_effect", "reclaim_claim", "issue_claim"] ->
            Map.put(operation, "current_writer_epoch", writer_epoch)

          _type ->
            operation
        end

      apply_operation(conn, operation)
    else
      {:error, reason} when reason in [:incomplete_read_set, :stale_read_set] ->
        required =
          case required_reads(conn, operation) do
            {:ok, reads} -> reads
            _ -> %{}
          end

        {:reject, reason, %{"required_revisions" => required}}

      {:error, _reason} = error ->
        error
    end
  end

  defp inject(:before_commit, :before_commit), do: {:error, :injected_crash_before_commit}
  defp inject({:halt, :before_commit}, :before_commit), do: System.halt(71)
  defp inject(_fault, _point), do: :ok

  defp apply_operation(conn, %{"type" => "set_policy"} = operation) do
    upsert_simple_root(conn, "root_policies", "policy_id", operation["policy_id"], operation)
  end

  defp apply_operation(conn, %{"type" => "set_control"} = operation) do
    with {:ok, facts} <-
           upsert_simple_root(
             conn,
             "root_controls",
             "control_id",
             operation["control_id"],
             operation
           ),
         {:ok, outstanding} <-
           fence_control_descendants(conn, operation["control_id"], operation["value"]) do
      {:ok, Map.put(facts, "outstanding_claim_ids", outstanding)}
    else
      {:error, :invalid_control_state} -> {:reject, :invalid_control_state, %{}}
      {:error, _reason} = error -> error
    end
  end

  defp apply_operation(conn, %{"type" => "append_inbox"} = operation) do
    with :ok <-
           exact_keys(
             operation,
             ~w(type execution_id sequence item_kind payload authenticated_actor)
           ),
         :ok <- identities(operation, ~w(execution_id item_kind)),
         true <- operation["item_kind"] in ~w(result exit observation),
         sequence when is_integer(sequence) and sequence > 0 <- operation["sequence"],
         true <- plain_value?(operation["payload"]),
         {:ok, digest} <-
           Encoding.semantic_digest("pramana-foundry-authenticated-inbox-item-v1", %{
             "execution_id" => operation["execution_id"],
             "sequence" => sequence,
             "item_kind" => operation["item_kind"],
             "payload" => operation["payload"]
           }),
         {:ok, current} <- load_inbox(conn, operation["execution_id"]),
         {:ok, disposition} <- inbox_append_guard(current, sequence),
         {:ok, item_bytes} <-
           encode(%{
             "schema_version" => 1,
             "execution_id" => operation["execution_id"],
             "sequence" => sequence,
             "item_kind" => operation["item_kind"],
             "disposition" => disposition,
             "item_digest" => digest,
             "payload" => operation["payload"]
           }),
         :ok <-
           write_inbox_head(
             conn,
             current,
             operation["execution_id"],
             operation["authenticated_actor"],
             sequence
           ),
         :ok <-
           Database.execute(
             conn,
             "INSERT INTO authenticated_inbox_items(execution_id, sequence, item_kind, disposition, item_digest, item) VALUES (?, ?, ?, ?, ?, ?)",
             [
               operation["execution_id"],
               sequence,
               operation["item_kind"],
               disposition,
               digest,
               {:blob, item_bytes}
             ]
           ),
         {:ok, fact} <- inbox_fact(conn, operation["execution_id"]) do
      {:ok, %{"inbox" => fact}}
    else
      false ->
        {:reject, :invalid_inbox_item, %{}}

      {:error, reason} when reason in [:inbox_sequence_conflict, :inbox_actor_conflict] ->
        {:reject, reason, %{}}

      {:error, _reason} = error ->
        error

      _ ->
        {:reject, :invalid_inbox_item, %{}}
    end
  end

  defp apply_operation(conn, %{"type" => "seal_inbox"} = operation) do
    with :ok <- exact_keys(operation, ~w(type execution_id last_sequence authenticated_actor)),
         :ok <- identity(operation["execution_id"]),
         last when is_integer(last) and last >= 0 <- operation["last_sequence"],
         {:ok, %{last_sequence: ^last, sealed_sequence: nil} = inbox} <-
           load_existing_inbox(conn, operation["execution_id"]),
         true <- inbox.actor_id == operation["authenticated_actor"],
         next <- %{inbox | revision: inbox.revision + 1, sealed_sequence: last},
         {:ok, bytes} <- encode(inbox_state(operation["execution_id"], next)),
         :ok <-
           Database.execute(
             conn,
             "UPDATE authenticated_inboxes SET revision = ?, sealed_sequence = ?, state = ? WHERE execution_id = ? AND revision = ? AND sealed_sequence IS NULL",
             [next.revision, last, {:blob, bytes}, operation["execution_id"], inbox.revision]
           ),
         {:ok, [[1]]} <- Database.query(conn, "SELECT changes()"),
         {:ok, fact} <- inbox_fact(conn, operation["execution_id"]) do
      {:ok, %{"inbox" => fact}}
    else
      {:ok, %{sealed_sequence: sealed}} when not is_nil(sealed) ->
        {:reject, :inbox_already_sealed, %{}}

      {:ok, _inbox} ->
        {:reject, :inbox_sequence_conflict, %{}}

      {:error, :not_found} ->
        {:reject, :inbox_not_found, %{}}

      {:error, _reason} = error ->
        error

      _ ->
        {:reject, :invalid_inbox_seal, %{}}
    end
  end

  defp apply_operation(conn, %{"type" => "grant_ledger"} = operation) do
    with :ok <- exact_keys(operation, ~w(type ledger_id generation dimension units)),
         :ok <- identity(operation["ledger_id"]),
         generation when is_integer(generation) and generation >= 0 <- operation["generation"],
         dimension when dimension in @dimensions <- operation["dimension"],
         units when is_integer(units) and units >= 0 <- operation["units"],
         {:ok, :absent} <- load_ledger(conn, operation["ledger_id"], generation),
         ledger <- %{
           ledger_id: operation["ledger_id"],
           generation: generation,
           parent_ledger_id: nil,
           parent_generation: nil,
           dimension: dimension,
           revision: 0,
           status: "open",
           authorized: units,
           available: units,
           held: 0,
           consumed: 0,
           delegated: 0,
           retired: 0
         },
         :ok <- insert_ledger(conn, ledger) do
      {:ok, %{"ledger" => public_ledger(ledger)}}
    else
      {:ok, _existing} -> {:reject, :ledger_exists, %{}}
      {:error, _reason} = error -> error
      _ -> {:reject, :invalid_ledger_grant, %{}}
    end
  end

  defp apply_operation(conn, %{"type" => "delegate_allocation"} = operation) do
    keys =
      ~w(type parent_ledger_id parent_generation child_ledger_id child_generation dimension units)

    with :ok <- exact_keys(operation, keys),
         :ok <- identities(operation, ~w(parent_ledger_id child_ledger_id)),
         true <- operation["parent_ledger_id"] != operation["child_ledger_id"],
         {:ok, parent} <-
           load_existing_ledger(
             conn,
             operation["parent_ledger_id"],
             operation["parent_generation"]
           ),
         "open" <- parent.status,
         true <- parent.dimension == operation["dimension"],
         units when is_integer(units) and units > 0 and units <= parent.available <-
           operation["units"],
         {:ok, :absent} <-
           load_ledger(conn, operation["child_ledger_id"], operation["child_generation"]),
         next_parent <- %{
           parent
           | revision: parent.revision + 1,
             available: parent.available - units,
             delegated: parent.delegated + units
         },
         child <- %{
           ledger_id: operation["child_ledger_id"],
           generation: operation["child_generation"],
           parent_ledger_id: parent.ledger_id,
           parent_generation: parent.generation,
           dimension: parent.dimension,
           revision: 0,
           status: "open",
           authorized: units,
           available: units,
           held: 0,
           consumed: 0,
           delegated: 0,
           retired: 0
         },
         :ok <- update_ledger(conn, parent, next_parent),
         :ok <- insert_ledger(conn, child) do
      {:ok,
       %{
         "parent_ledger" => public_ledger(next_parent),
         "child_ledger" => public_ledger(child)
       }}
    else
      {:ok, _existing} -> {:reject, :child_ledger_exists, %{}}
      {:error, :not_found} -> {:reject, :parent_ledger_not_found, %{}}
      {:error, _reason} = error -> error
      _ -> {:reject, :allocation_not_permitted, %{}}
    end
  end

  defp apply_operation(conn, %{"type" => "return_allocation"} = operation) do
    keys = ~w(type child_ledger_id child_generation units)

    with :ok <- exact_keys(operation, keys),
         :ok <- identity(operation["child_ledger_id"]),
         {:ok, child} <-
           load_existing_ledger(
             conn,
             operation["child_ledger_id"],
             operation["child_generation"]
           ),
         parent_id when is_binary(parent_id) <- child.parent_ledger_id,
         {:ok, parent} <- load_existing_ledger(conn, parent_id, child.parent_generation),
         "open" <- child.status,
         "open" <- parent.status,
         units when is_integer(units) and units > 0 and units <= child.available <-
           operation["units"],
         0 <- child.held,
         0 <- child.delegated,
         next_child <- %{
           child
           | revision: child.revision + 1,
             authorized: child.authorized - units,
             available: child.available - units
         },
         next_parent <- %{
           parent
           | revision: parent.revision + 1,
             delegated: parent.delegated - units,
             available: parent.available + units
         },
         true <- next_parent.delegated >= 0,
         :ok <- update_ledger(conn, child, next_child),
         :ok <- update_ledger(conn, parent, next_parent) do
      {:ok,
       %{
         "parent_ledger" => public_ledger(next_parent),
         "child_ledger" => public_ledger(next_child)
       }}
    else
      {:error, :not_found} -> {:reject, :ledger_not_found, %{}}
      {:error, _reason} = error -> error
      _ -> {:reject, :allocation_return_not_permitted, %{}}
    end
  end

  defp apply_operation(conn, %{"type" => "reserve"} = operation) do
    keys = ~w(type reservation_id ledger_id generation owner_kind owner_id units)

    with :ok <- exact_keys(operation, keys),
         :ok <- identities(operation, ~w(reservation_id ledger_id owner_kind owner_id)),
         {:ok, ledger} <-
           load_existing_ledger(conn, operation["ledger_id"], operation["generation"]),
         "open" <- ledger.status,
         units when is_integer(units) and units > 0 and units <= ledger.available <-
           operation["units"],
         {:ok, []} <-
           Database.query(
             conn,
             "SELECT reservation_id FROM root_reservations WHERE reservation_id = ?",
             [operation["reservation_id"]]
           ),
         reservation <- %{
           reservation_id: operation["reservation_id"],
           ledger_id: ledger.ledger_id,
           generation: ledger.generation,
           dimension: ledger.dimension,
           owner_kind: operation["owner_kind"],
           owner_id: operation["owner_id"],
           units: units,
           revision: 0,
           status: "proposed",
           claim_id: nil
         },
         :ok <- insert_reservation(conn, reservation) do
      {:ok,
       %{
         "ledger" => public_ledger(ledger),
         "reservation" => public_reservation(reservation)
       }}
    else
      {:error, :not_found} -> {:reject, :ledger_not_found, %{}}
      {:error, _reason} = error -> error
      _ -> {:reject, :reservation_not_permitted, %{}}
    end
  end

  defp apply_operation(conn, %{"type" => "release_reservation"} = operation) do
    with :ok <- exact_keys(operation, ~w(type reservation_id proof)),
         "unissued" <- operation["proof"],
         {:ok, reservation} <- load_reservation(conn, operation["reservation_id"]),
         true <- reservation.status in ["proposed", "reserved", "issued_unknown"],
         :ok <- release_guard(conn, reservation),
         {:ok, ledger} <-
           load_existing_ledger(conn, reservation.ledger_id, reservation.generation),
         target <- if(ledger.status == "open", do: "released", else: "retired"),
         next_reservation <- %{
           reservation
           | revision: reservation.revision + 1,
             status: target
         },
         next_ledger <-
           if(reservation.status == "proposed",
             do: ledger,
             else: release_hold(ledger, reservation.units)
           ),
         :ok <- update_reservation(conn, reservation, next_reservation),
         :ok <- maybe_update_ledger(conn, ledger, next_ledger) do
      {:ok,
       %{
         "ledger" => public_ledger(next_ledger),
         "reservation" => public_reservation(next_reservation)
       }}
    else
      {:error, :not_found} ->
        {:reject, :reservation_not_found, %{}}

      {:error, reason} when reason in [:claim_already_issued, :unissued_proof_required] ->
        {:reject, reason, %{}}

      {:error, _reason} = error ->
        error

      _ ->
        {:reject, :reservation_release_not_permitted, %{}}
    end
  end

  defp apply_operation(conn, %{"type" => "close_generation"} = operation) do
    with :ok <- exact_keys(operation, ~w(type ledger_id generation)),
         {:ok, ledgers} <-
           subtree_ledgers(conn, operation["ledger_id"], operation["generation"]),
         {:ok, %{"status" => "open"}} <-
           ledger_fact(conn, operation["ledger_id"], operation["generation"]),
         :ok <- close_subtree(conn, ledgers),
         {:ok, closed} <-
           subtree_ledgers(conn, operation["ledger_id"], operation["generation"]) do
      {:ok, %{"ledgers" => Enum.map(closed, &public_ledger/1)}}
    else
      {:error, :not_found} -> {:reject, :ledger_not_found, %{}}
      {:error, _reason} = error -> error
      _ -> {:reject, :generation_already_closed, %{}}
    end
  end

  defp apply_operation(
         conn,
         %{"type" => "reset_generation", "parent_ledger_id" => nil} = operation
       ) do
    keys =
      ~w(type ledger_id old_generation new_generation parent_ledger_id parent_generation units)

    old_generation = operation["old_generation"]

    with :ok <- exact_keys(operation, keys),
         nil <- operation["parent_generation"],
         true <- operation["new_generation"] == old_generation + 1,
         {:ok, old} <- load_existing_ledger(conn, operation["ledger_id"], old_generation),
         nil <- old.parent_ledger_id,
         "open" <- old.status,
         {:ok, ^old_generation} <- current_generation(conn, old.ledger_id),
         units when is_integer(units) and units >= 0 and units <= old.available <-
           operation["units"],
         {:ok, :absent} <-
           load_ledger(conn, operation["ledger_id"], operation["new_generation"]),
         {:ok, subtree} <- subtree_ledgers(conn, old.ledger_id, old.generation),
         :ok <- close_subtree(conn, subtree),
         {:ok, closed} <- load_existing_ledger(conn, old.ledger_id, old.generation),
         fresh <- %{
           ledger_id: old.ledger_id,
           generation: operation["new_generation"],
           parent_ledger_id: nil,
           parent_generation: nil,
           dimension: old.dimension,
           revision: 0,
           status: "open",
           authorized: units,
           available: units,
           held: 0,
           consumed: 0,
           delegated: 0,
           retired: 0
         },
         :ok <- insert_ledger(conn, fresh) do
      {:ok,
       %{
         "closed_generation" => public_ledger(closed),
         "new_generation" => public_ledger(fresh),
         "transfer_kind" => "explicit_root_reset_unused_authority"
       }}
    else
      {:ok, _existing} -> {:reject, :new_generation_exists, %{}}
      {:error, :not_found} -> {:reject, :ledger_not_found, %{}}
      {:error, _reason} = error -> error
      _ -> {:reject, :generation_reset_not_permitted, %{}}
    end
  end

  defp apply_operation(conn, %{"type" => "reset_generation"} = operation) do
    keys =
      ~w(type ledger_id old_generation new_generation parent_ledger_id parent_generation units)

    old_generation = operation["old_generation"]

    with :ok <- exact_keys(operation, keys),
         true <- operation["new_generation"] == old_generation + 1,
         {:ok, old} <-
           load_existing_ledger(conn, operation["ledger_id"], old_generation),
         "open" <- old.status,
         {:ok, ^old_generation} <- current_generation(conn, old.ledger_id),
         true <- old.parent_ledger_id == operation["parent_ledger_id"],
         true <- old.parent_generation == operation["parent_generation"],
         {:ok, parent} <-
           load_existing_ledger(conn, old.parent_ledger_id, old.parent_generation),
         "open" <- parent.status,
         units when is_integer(units) and units >= 0 and units <= parent.available <-
           operation["units"],
         {:ok, :absent} <-
           load_ledger(conn, operation["ledger_id"], operation["new_generation"]),
         {:ok, subtree} <- subtree_ledgers(conn, old.ledger_id, old.generation),
         :ok <- close_subtree(conn, subtree),
         {:ok, closed} <- load_existing_ledger(conn, old.ledger_id, old.generation),
         next_parent <- %{
           parent
           | revision: parent.revision + 1,
             available: parent.available - units,
             delegated: parent.delegated + units
         },
         fresh <- %{
           ledger_id: old.ledger_id,
           generation: operation["new_generation"],
           parent_ledger_id: parent.ledger_id,
           parent_generation: parent.generation,
           dimension: old.dimension,
           revision: 0,
           status: "open",
           authorized: units,
           available: units,
           held: 0,
           consumed: 0,
           delegated: 0,
           retired: 0
         },
         :ok <- update_ledger(conn, parent, next_parent),
         :ok <- insert_ledger(conn, fresh) do
      {:ok,
       %{
         "closed_generation" => public_ledger(closed),
         "new_generation" => public_ledger(fresh),
         "parent_ledger" => public_ledger(next_parent)
       }}
    else
      {:ok, _existing} -> {:reject, :new_generation_exists, %{}}
      {:error, :not_found} -> {:reject, :ledger_not_found, %{}}
      {:error, _reason} = error -> error
      _ -> {:reject, :generation_reset_not_permitted, %{}}
    end
  end

  defp apply_operation(conn, %{"type" => "create_effect"} = operation) do
    keys =
      ~w(type effect_id request operation scope ticket_id attempt_id execution_id policy_id policy_revision control_id control_revision reservation_ids leases authenticated_actor)

    with :ok <- exact_keys(operation, keys),
         :ok <-
           identities(
             operation,
             ~w(effect_id operation scope ticket_id attempt_id execution_id policy_id control_id)
           ),
         true <- plain_map?(operation["request"]),
         :ok <- identities(operation["request"], ~w(request_id role)),
         :ok <- identity(operation["authenticated_actor"]),
         phase_generation when is_integer(phase_generation) and phase_generation >= 0 <-
           Map.get(operation["request"], "phase_generation", 0),
         operation_ordinal when is_integer(operation_ordinal) and operation_ordinal >= 0 <-
           Map.get(operation["request"], "operation_ordinal", 0),
         predecessor_effect_id <- operation["request"]["predecessor_effect_id"],
         :ok <- attempt_open(conn, operation["ticket_id"], operation["attempt_id"]),
         :ok <- semantic_effect_available(conn, operation),
         :ok <-
           predecessor_guard(
             conn,
             operation,
             phase_generation,
             operation_ordinal,
             predecessor_effect_id
           ),
         {:ok, request_digest} <-
           Encoding.semantic_digest("pramana-foundry-effect-request-v1", %{
             "effect_id" => operation["effect_id"],
             "operation" => operation["operation"],
             "scope" => operation["scope"],
             "ticket_id" => operation["ticket_id"],
             "attempt_id" => operation["attempt_id"],
             "execution_id" => operation["execution_id"],
             "request" => operation["request"]
           }),
         true <- proper_list?(operation["reservation_ids"]),
         true <- proper_list?(operation["leases"]),
         {:ok, policy} <- load_simple(conn, "root_policies", "policy_id", operation["policy_id"]),
         {:ok, control} <-
           load_simple(conn, "root_controls", "control_id", operation["control_id"]),
         true <- policy.revision == operation["policy_revision"],
         true <- control.revision == operation["control_revision"],
         :ok <- allowed_effect?(policy.value, control.value, operation),
         :ok <- nonstart_allowance(conn, policy.value, operation),
         {:ok, reservations} <- load_effect_reservations(conn, operation),
         :ok <- reservation_dimensions(operation, reservations),
         {:ok, lease_specs} <- normalize_lease_specs(operation["leases"]),
         :ok <- lease_specs_available(conn, lease_specs),
         {:ok, []} <-
           Database.query(conn, "SELECT effect_id FROM root_effects WHERE effect_id = ?", [
             operation["effect_id"]
           ]),
         effect <- %{
           effect_id: operation["effect_id"],
           request_digest: request_digest,
           policy_id: operation["policy_id"],
           policy_revision: operation["policy_revision"],
           control_id: operation["control_id"],
           control_revision: operation["control_revision"],
           operation: operation["operation"],
           scope: operation["scope"],
           ticket_id: operation["ticket_id"],
           attempt_id: operation["attempt_id"],
           execution_id: operation["execution_id"],
           assignment_id:
             assignment_id(
               operation["ticket_id"],
               operation["attempt_id"],
               operation["request"]["role"]
             ),
           role: operation["request"]["role"],
           phase_generation: phase_generation,
           operation_ordinal: operation_ordinal,
           predecessor_effect_id: predecessor_effect_id,
           request_id: operation["request"]["request_id"],
           issuer: operation["authenticated_actor"],
           channel: "protected-gateway",
           profile: Map.get(operation["request"], "profile", "unspecified"),
           deadline: Map.get(operation["request"], "deadline"),
           status: "pending",
           revision: 0,
           reservation_ids: Enum.map(reservations, & &1.reservation_id)
         },
         :ok <- insert_effect(conn, effect),
         {:ok, activated_reservations} <- activate_reservations(conn, reservations),
         :ok <- insert_pending_leases(conn, operation["effect_id"], lease_specs),
         {:ok, ledgers} <- ledger_facts_for_reservations(conn, activated_reservations) do
      {:ok,
       %{
         "effect" => public_effect(effect),
         "reservations" => Enum.map(activated_reservations, &public_reservation/1),
         "ledgers" => ledgers,
         "lease_specs" => lease_specs
       }}
    else
      {:error, reason}
      when reason in [
             :policy_not_found,
             :control_not_found,
             :effect_not_allowed,
             :control_not_active,
             :reservation_not_found,
             :reservation_owner_mismatch,
             :reservation_not_held,
             :reservation_activation_not_permitted,
             :lease_conflict,
             :duplicate_semantic_operation,
             :duplicate_request_identity,
             :operation_dimension_mismatch,
             :nonstart_allowance_exhausted,
             :predecessor_not_terminal,
             :predecessor_identity_mismatch,
             :attempt_closed
           ] ->
        {:reject, reason, %{}}

      {:error, _reason} = error ->
        error

      _ ->
        {:reject, :invalid_effect_request, %{}}
    end
  end

  defp apply_operation(conn, %{"type" => "claim_effect"} = operation) do
    with :ok <-
           exact_keys(
             operation,
             ~w(type effect_id claim_id writer_epoch current_writer_epoch)
           ),
         :ok <- identities(operation, ~w(effect_id claim_id writer_epoch)),
         true <- operation["writer_epoch"] == operation["current_writer_epoch"],
         {:ok, effect} <- load_effect(conn, operation["effect_id"]),
         "pending" <- effect.status,
         {:ok, policy} <- load_simple(conn, "root_policies", "policy_id", effect.policy_id),
         {:ok, control} <- load_simple(conn, "root_controls", "control_id", effect.control_id),
         true <- policy.revision == effect.policy_revision,
         true <- control.revision == effect.control_revision,
         :ok <- control_active?(control.value),
         :ok <- predecessor_current?(conn, effect),
         {:ok, reservations} <- reservations_for_effect(conn, effect.effect_id),
         true <- reservations != [],
         true <- Enum.all?(reservations, &(&1.status == "reserved" and is_nil(&1.claim_id))),
         :ok <- reservations_open?(conn, reservations),
         :ok <- lease_specs_available(conn, effect.lease_specs),
         claim <- %{
           claim_id: operation["claim_id"],
           effect_id: effect.effect_id,
           writer_epoch: operation["writer_epoch"],
           status: "claimed",
           revision: 0
         },
         next_effect <- %{effect | status: "claimed", revision: effect.revision + 1},
         :ok <- insert_claim(conn, claim),
         :ok <- bind_reservations_to_claim(conn, reservations, claim.claim_id),
         :ok <- update_effect(conn, effect, next_effect),
         :ok <- materialize_leases(conn, effect.effect_id, claim.claim_id) do
      {:ok,
       %{
         "claim" => public_claim(claim),
         "effect" => public_effect(next_effect)
       }}
    else
      {:error, :not_found} ->
        {:reject, :effect_not_found, %{}}

      {:error, reason}
      when reason in [
             :control_not_active,
             :predecessor_not_terminal,
             :ledger_closed,
             :ledger_generation_superseded,
             :lease_conflict
           ] ->
        {:reject, reason, %{}}

      {:error, _reason} = error ->
        error

      _ ->
        {:reject, :claim_not_permitted, %{}}
    end
  end

  defp apply_operation(conn, %{"type" => "issue_claim"} = operation) do
    with :ok <- exact_keys(operation, ~w(type claim_id writer_epoch current_writer_epoch)),
         {:ok, claim} <- load_claim(conn, operation["claim_id"]),
         "claimed" <- claim.status,
         true <- claim.writer_epoch == operation["writer_epoch"],
         true <- claim.writer_epoch == operation["current_writer_epoch"],
         {:ok, effect} <- load_effect(conn, claim.effect_id),
         "claimed" <- effect.status,
         {:ok, policy} <- load_simple(conn, "root_policies", "policy_id", effect.policy_id),
         {:ok, control} <- load_simple(conn, "root_controls", "control_id", effect.control_id),
         true <- policy.revision == effect.policy_revision,
         true <- control.revision == effect.control_revision,
         :ok <- control_active?(control.value),
         :ok <- predecessor_current?(conn, effect),
         {:ok, reservations} <- reservations_for_claim(conn, claim.claim_id),
         true <- reservations != [] and Enum.all?(reservations, &(&1.status == "reserved")),
         :ok <- reservations_open?(conn, reservations),
         next_claim <- %{claim | status: "issued", revision: claim.revision + 1},
         next_effect <- %{effect | status: "issued", revision: effect.revision + 1},
         :ok <- update_claim(conn, claim, next_claim),
         :ok <- update_effect(conn, effect, next_effect),
         :ok <- update_reservation_statuses(conn, reservations, "issued_unknown") do
      {:ok,
       %{
         "claim" => public_claim(next_claim),
         "effect" => public_effect(next_effect)
       }}
    else
      {:error, :not_found} ->
        {:reject, :claim_not_found, %{}}

      {:error, :control_not_active} ->
        {:reject, :control_not_active, %{}}

      {:error, :predecessor_not_terminal} ->
        {:reject, :predecessor_not_terminal, %{}}

      {:error, :ledger_closed} ->
        {:reject, :ledger_closed, %{}}

      {:error, :ledger_generation_superseded} ->
        {:reject, :ledger_generation_superseded, %{}}

      {:error, _reason} = error ->
        error

      _ ->
        {:reject, :claim_issue_not_permitted, %{}}
    end
  end

  defp apply_operation(conn, %{"type" => "reclaim_claim"} = operation) do
    keys =
      ~w(type claim_id prior_writer_epoch new_writer_epoch proof current_writer_epoch)

    with :ok <- exact_keys(operation, keys),
         :ok <- identities(operation, ~w(claim_id prior_writer_epoch new_writer_epoch proof)),
         "issuer_quiescent" <- operation["proof"],
         true <- operation["new_writer_epoch"] == operation["current_writer_epoch"],
         true <- operation["prior_writer_epoch"] != operation["new_writer_epoch"],
         {:ok, claim} <- load_claim(conn, operation["claim_id"]),
         "claimed" <- claim.status,
         true <- claim.writer_epoch == operation["prior_writer_epoch"],
         {:ok, effect} <- load_effect(conn, claim.effect_id),
         "claimed" <- effect.status,
         {:ok, control} <- load_simple(conn, "root_controls", "control_id", effect.control_id),
         true <- control.revision == effect.control_revision,
         :ok <- control_active?(control.value),
         {:ok, reservations} <- reservations_for_claim(conn, claim.claim_id),
         :ok <- reservations_open?(conn, reservations),
         next <- %{
           claim
           | writer_epoch: operation["new_writer_epoch"],
             revision: claim.revision + 1
         },
         :ok <- update_claim(conn, claim, next) do
      {:ok,
       %{
         "claim" => public_claim(next),
         "takeover" => %{
           "prior_writer_epoch" => claim.writer_epoch,
           "new_writer_epoch" => next.writer_epoch,
           "proof" => "issuer_quiescent"
         }
       }}
    else
      {:error, reason}
      when reason in [
             :not_found,
             :control_not_active,
             :ledger_closed,
             :ledger_generation_superseded
           ] ->
        {:reject, reason, %{}}

      {:error, _reason} = error ->
        error

      _ ->
        {:reject, :claim_takeover_not_permitted, %{}}
    end
  end

  defp apply_operation(conn, %{"type" => "settle_claim"} = operation) do
    keys = ~w(type claim_id receipt_id request_id outcome proof payload authenticated_actor)

    with :ok <- exact_keys(operation, keys),
         :ok <- identities(operation, ~w(claim_id receipt_id request_id outcome proof)),
         true <- operation["outcome"] in ~w(succeeded failed non_started unknown),
         true <- operation["proof"] in ~w(delivered issuer_quiescent outcome_unknown),
         true <- plain_value?(operation["payload"]),
         {:ok, claim} <- load_claim(conn, operation["claim_id"]),
         {:ok, effect} <- load_effect(conn, claim.effect_id),
         :ok <- settlement_provenance(operation, claim, effect),
         {:ok, digest} <- receipt_digest(operation),
         {:ok, prior_receipts} <- receipts_for_claim(conn, claim.claim_id),
         {:ok, request_receipts} <- receipts_for_request(conn, operation["request_id"]),
         {:ok, observation_receipts} <- receipts_for_id(conn, operation["receipt_id"]) do
      cond do
        # A claim that was never issued has no observation to conflict with; quarantining
        # it commits a state the restart check refuses (ledger finding 1).
        claim.status in ["claimed", "cancelled"] ->
          {:reject, :claim_settlement_not_permitted, %{}}

        observation_conflict?(observation_receipts, operation, digest, claim) ->
          quarantine_conflicting_receipt(conn, operation, digest, claim, effect)

        Enum.any?(request_receipts, &(&1.claim_id != claim.claim_id)) ->
          quarantine_conflicting_receipt(conn, operation, digest, claim, effect)

        true ->
          settle_with_receipts(conn, operation, digest, claim, effect, prior_receipts)
      end
    else
      {:error, :not_found} ->
        {:reject, :claim_not_found, %{}}

      {:error, :receipt_provenance_mismatch} ->
        {:reject, :receipt_provenance_mismatch, %{}}

      {:error, _reason} = error ->
        error

      _ ->
        {:reject, :invalid_claim_settlement, %{}}
    end
  end

  defp apply_operation(conn, %{"type" => "cancel_effect"} = operation) do
    with :ok <- exact_keys(operation, ~w(type effect_id proof)),
         true <- operation["proof"] in ~w(unissued issuer_quiescent control_ack),
         {:ok, effect} <- load_effect(conn, operation["effect_id"]) do
      cancel_effect(conn, effect, operation["proof"])
    else
      {:error, :not_found} -> {:reject, :effect_not_found, %{}}
      {:error, _reason} = error -> error
      _ -> {:reject, :invalid_cancellation, %{}}
    end
  end

  # FR-08B protected items, item 1: the terminal_settlement_v1 producer. Closes a
  # (ticket, attempt) only when every effect under it is settled and every reservation it
  # activated is consumed, released or retired. The row makes the closure terminal:
  # create_effect refuses work under a closed attempt. Keyed on scope and attempt, never
  # on a role. A later conflicting receipt may still quarantine a closed attempt's effect
  # (R5); that moves no units, so the fact stays true as a statement about the ledger.
  defp apply_operation(conn, %{"type" => "close_attempt"} = operation) do
    with :ok <- exact_keys(operation, ~w(type scope ticket_id attempt_id)),
         :ok <- identities(operation, ~w(scope ticket_id attempt_id)),
         true <- operation["scope"] == "ticket:" <> operation["ticket_id"],
         :ok <- attempt_open(conn, operation["ticket_id"], operation["attempt_id"]),
         {:ok, effects} <-
           attempt_effects(
             conn,
             operation["scope"],
             operation["ticket_id"],
             operation["attempt_id"]
           ),
         true <- Enum.all?(effects, &(&1.status in @closed_effect_statuses)),
         {:ok, reservations} <- attempt_reservations(conn, effects),
         true <- Enum.all?(reservations, &(&1.status in @closed_reservation_statuses)),
         fact <- attempt_settlement(operation, effects, reservations),
         {:ok, bytes} <- encode(fact),
         :ok <-
           Database.execute(
             conn,
             "INSERT INTO root_attempt_closures(ticket_id, attempt_id, scope, state) VALUES (?, ?, ?, ?)",
             [operation["ticket_id"], operation["attempt_id"], operation["scope"], {:blob, bytes}]
           ) do
      {:ok, %{"attempt_settlement" => fact}}
    else
      {:error, :attempt_closed} -> {:reject, :attempt_closed, %{}}
      {:error, _reason} = error -> error
      false -> {:reject, :attempt_not_settled, %{}}
      _ -> {:reject, :invalid_attempt_closure, %{}}
    end
  end

  defp apply_operation(_conn, _operation), do: {:reject, :unsupported_operation, %{}}

  defp observation_conflict?([], _operation, _digest, _claim), do: false

  defp observation_conflict?(receipts, operation, digest, claim) do
    not Enum.all?(receipts, fn receipt ->
      receipt.receipt_id == operation["receipt_id"] and receipt.claim_id == claim.claim_id and
        receipt.request_id == operation["request_id"] and
        receipt.outcome == operation["outcome"] and receipt.receipt_digest == digest
    end)
  end

  defp subtree_ledgers(conn, ledger_id, generation) do
    sql =
      "WITH RECURSIVE tree(ledger_id, generation) AS (" <>
        "SELECT ledger_id, generation FROM root_ledgers WHERE ledger_id = ? AND generation = ? " <>
        "UNION ALL SELECT c.ledger_id, c.generation FROM root_ledgers c JOIN tree p " <>
        "ON c.parent_ledger_id = p.ledger_id AND c.parent_generation = p.generation) " <>
        "SELECT l.ledger_id, l.generation, l.parent_ledger_id, l.parent_generation, l.dimension, l.revision, l.status, l.authorized, l.available, l.held, l.consumed, l.delegated, l.retired " <>
        "FROM root_ledgers l JOIN tree t ON t.ledger_id = l.ledger_id AND t.generation = l.generation " <>
        "ORDER BY l.ledger_id, l.generation"

    with :ok <- identity(ledger_id),
         true <- is_integer(generation) and generation >= 0,
         {:ok, rows} <- Database.query(conn, sql, [ledger_id, generation]) do
      {:ok, Enum.map(rows, &ledger_from_row/1)}
    else
      false -> {:error, :invalid_ledger_generation}
      {:error, _reason} = error -> error
    end
  end

  defp subtree_read_keys(conn, ledger_id, generation) do
    with {:ok, ledgers} <- subtree_ledgers(conn, ledger_id, generation) do
      ledger_keys = Enum.map(ledgers, &ledger_key(&1.ledger_id, &1.generation))

      dependent =
        Enum.flat_map(ledgers, fn ledger ->
          generation_dependency_keys(conn, ledger.ledger_id, ledger.generation)
        end)

      {:ok, Enum.uniq(ledger_keys ++ dependent)}
    end
  end

  defp generation_dependency_keys(conn, ledger_id, generation) do
    case Database.query(
           conn,
           "SELECT reservation_id, owner_kind, owner_id, claim_id FROM root_reservations WHERE ledger_id = ? AND generation = ? AND status = 'reserved' ORDER BY reservation_id",
           [ledger_id, generation]
         ) do
      {:ok, rows} ->
        Enum.flat_map(rows, fn [reservation_id, owner_kind, owner_id, claim_id] ->
          claim_keys = if is_binary(claim_id), do: ["claim/" <> claim_id], else: []

          effect_keys =
            if owner_kind == "effect", do: effect_authority_keys(conn, owner_id), else: []

          ["reservation/" <> reservation_id | claim_keys ++ effect_keys]
        end)

      _ ->
        []
    end
  end

  defp close_subtree(conn, ledgers) do
    with :ok <-
           Enum.reduce_while(ledgers, :ok, fn ledger, :ok ->
             case if(ledger.status == "open",
                    do: revoke_unissued_generation(conn, ledger),
                    else: :ok
                  ) do
               :ok -> {:cont, :ok}
               error -> {:halt, error}
             end
           end) do
      Enum.reduce_while(ledgers, :ok, fn ledger, :ok ->
        with {:ok, current} <- load_existing_ledger(conn, ledger.ledger_id, ledger.generation),
             true <- current.status in ["open", "closed"],
             next <- %{
               current
               | revision: current.revision + 1,
                 status: "closed",
                 retired: current.retired + current.available,
                 available: 0
             },
             :ok <-
               if(current.status == "closed", do: :ok, else: update_ledger(conn, current, next)) do
          {:cont, :ok}
        else
          {:error, _reason} = error -> {:halt, error}
          _ -> {:halt, {:error, :generation_already_closed}}
        end
      end)
    end
  end

  defp revoke_unissued_generation(conn, ledger) do
    with {:ok, rows} <-
           Database.query(
             conn,
             "SELECT reservation_id, ledger_id, generation, dimension, owner_kind, owner_id, units, revision, status, claim_id FROM root_reservations WHERE ledger_id = ? AND generation = ? AND status = 'reserved' ORDER BY reservation_id",
             [ledger.ledger_id, ledger.generation]
           ),
         reservations <- Enum.map(rows, &reservation_from_row/1),
         :ok <- release_many(conn, reservations),
         :ok <- cancel_unissued_effect_owners(conn, reservations) do
      :ok
    end
  end

  defp cancel_unissued_effect_owners(conn, reservations) do
    reservations
    |> Enum.filter(&(&1.owner_kind == "effect"))
    |> Enum.map(& &1.owner_id)
    |> Enum.uniq()
    |> Enum.reduce_while(:ok, fn effect_id, :ok ->
      case load_effect(conn, effect_id) do
        {:ok, %{status: "pending"} = effect} ->
          next = %{effect | status: "cancelled", revision: effect.revision + 1}

          case update_effect(conn, effect, next) do
            :ok -> {:cont, :ok}
            error -> {:halt, error}
          end

        {:ok, %{status: "claimed"} = effect} ->
          with {:ok, [[claim_id]]} <-
                 Database.query(conn, "SELECT claim_id FROM root_claims WHERE effect_id = ?", [
                   effect_id
                 ]),
               {:ok, claim} <- load_claim(conn, claim_id),
               next_claim <- %{claim | status: "cancelled", revision: claim.revision + 1},
               next_effect <- %{effect | status: "cancelled", revision: effect.revision + 1},
               :ok <- update_claim(conn, claim, next_claim),
               :ok <- update_effect(conn, effect, next_effect),
               :ok <- settle_leases(conn, claim_id, "cancelled") do
            {:cont, :ok}
          else
            {:error, _reason} = error -> {:halt, error}
          end

        {:ok, _effect} ->
          {:cont, :ok}

        {:error, :not_found} ->
          {:cont, :ok}

        {:error, _reason} = error ->
          {:halt, error}
      end
    end)
  end

  defp cancel_effect(conn, %{status: "issued"} = effect, "control_ack") do
    with {:ok, [[claim_id]]} <-
           Database.query(
             conn,
             "SELECT claim_id FROM root_claims WHERE effect_id = ? AND status = 'issued'",
             [effect.effect_id]
           ) do
      {:ok,
       %{
         "effect" => public_effect(effect),
         "control_status" => "revocation_pending",
         "outstanding_claim_ids" => [claim_id]
       }}
    end
  end

  defp cancel_effect(conn, %{status: "pending"} = effect, "unissued") do
    with {:ok, reservations} <- reservations_for_effect(conn, effect.effect_id),
         :ok <- release_many(conn, reservations),
         next <- %{effect | status: "cancelled", revision: effect.revision + 1},
         :ok <- update_effect(conn, effect, next) do
      {:ok, %{"effect" => public_effect(next), "outstanding_claim_ids" => []}}
    end
  end

  defp cancel_effect(conn, %{status: "claimed"} = effect, "issuer_quiescent") do
    with {:ok, [[claim_id]]} <-
           Database.query(
             conn,
             "SELECT claim_id FROM root_claims WHERE effect_id = ? AND status = 'claimed'",
             [effect.effect_id]
           ),
         {:ok, claim} <- load_claim(conn, claim_id),
         {:ok, reservations} <- reservations_for_claim(conn, claim_id),
         :ok <- release_many(conn, reservations),
         next_claim <- %{claim | status: "cancelled", revision: claim.revision + 1},
         next_effect <- %{effect | status: "cancelled", revision: effect.revision + 1},
         :ok <- update_claim(conn, claim, next_claim),
         :ok <- update_effect(conn, effect, next_effect),
         :ok <- settle_leases(conn, claim_id, "cancelled") do
      {:ok,
       %{
         "effect" => public_effect(next_effect),
         "claim" => public_claim(next_claim),
         "outstanding_claim_ids" => []
       }}
    end
  end

  defp cancel_effect(_conn, _effect, _proof), do: {:reject, :cancellation_not_permitted, %{}}

  defp fence_control_descendants(_conn, _control_id, %{"status" => "active"}), do: {:ok, []}

  defp fence_control_descendants(conn, control_id, %{"status" => "cancel_requested"}) do
    with {:ok, rows} <-
           Database.query(
             conn,
             "SELECT effect_id FROM root_effects WHERE control_id = ? AND status IN ('pending', 'claimed', 'issued', 'unknown', 'reconciliation_required') ORDER BY effect_id",
             [control_id]
           ) do
      Enum.reduce_while(rows, {:ok, []}, fn [effect_id], {:ok, outstanding} ->
        with {:ok, effect} <- load_effect(conn, effect_id) do
          case effect.status do
            "pending" ->
              case cancel_effect(conn, effect, "unissued") do
                {:ok, _facts} -> {:cont, {:ok, outstanding}}
                error -> {:halt, error}
              end

            "claimed" ->
              case cancel_effect(conn, effect, "issuer_quiescent") do
                {:ok, _facts} -> {:cont, {:ok, outstanding}}
                error -> {:halt, error}
              end

            status when status in ["issued", "unknown", "reconciliation_required"] ->
              case Database.query(
                     conn,
                     "SELECT claim_id FROM root_claims WHERE effect_id = ? ORDER BY claim_id",
                     [effect_id]
                   ) do
                {:ok, claims} ->
                  {:cont, {:ok, outstanding ++ Enum.map(claims, &hd/1)}}

                error ->
                  {:halt, error}
              end
          end
        else
          error -> {:halt, error}
        end
      end)
    end
  end

  defp fence_control_descendants(_conn, _control_id, _value),
    do: {:error, :invalid_control_state}

  defp effect_dependency_keys(conn, effect_id) do
    reservation_keys =
      case reservations_for_effect(conn, effect_id) do
        {:ok, values} -> Enum.flat_map(values, &full_reservation_keys/1)
        _ -> []
      end

    claim_keys =
      case Database.query(
             conn,
             "SELECT claim_id FROM root_claims WHERE effect_id = ? ORDER BY claim_id",
             [effect_id]
           ) do
        {:ok, rows} -> Enum.map(rows, fn [claim_id] -> "claim/" <> claim_id end)
        _ -> []
      end

    effect_authority_keys(conn, effect_id) ++ reservation_keys ++ claim_keys
  end

  defp release_many(conn, reservations) do
    Enum.reduce_while(reservations, :ok, fn reservation, :ok ->
      with true <- reservation.status == "reserved",
           {:ok, ledger} <-
             load_existing_ledger(conn, reservation.ledger_id, reservation.generation),
           next_reservation <- %{
             reservation
             | status: if(ledger.status == "open", do: "released", else: "retired"),
               revision: reservation.revision + 1
           },
           next_ledger <- release_hold(ledger, reservation.units),
           :ok <- update_reservation(conn, reservation, next_reservation),
           :ok <- update_ledger(conn, ledger, next_ledger) do
        {:cont, :ok}
      else
        {:error, _reason} = error -> {:halt, error}
        _ -> {:halt, {:error, :reservation_release_not_permitted}}
      end
    end)
  end

  defp settle_with_receipts(conn, operation, digest, claim, effect, receipts) do
    exact =
      Enum.find(receipts, fn receipt ->
        receipt.receipt_id == operation["receipt_id"] and
          receipt.request_id == operation["request_id"] and
          receipt.outcome == operation["outcome"] and receipt.receipt_digest == digest
      end)

    cond do
      exact ->
        {:ok,
         %{
           "claim" => public_claim(claim),
           "effect" => public_effect(effect),
           "receipt" => public_receipt(exact)
         }}

      # A quarantined claim is not reconciled by an ordinary receipt. Quarantine does not
      # store the conflicting receipt, so the earlier unknown-only history below would read a
      # later known outcome as a reconciliation and settle it with no recovery record
      # (FR-10 Q3 probe, quarantine_exit_probe_test.exs). Leaving quarantine needs an explicit
      # recovery operation, which FR-10 owns; until then it fails closed.
      claim.status == "reconciliation_required" ->
        quarantine_conflicting_receipt(conn, operation, digest, claim, effect)

      # An unknown receipt carries less information than any stored receipt, never
      # conflicting information: store it and leave the status alone (FR-10 finding B). A
      # late timeout must not re-quarantine an effect already settled from its outcome.
      receipts != [] and operation["outcome"] == "unknown" ->
        stale_unknown_receipt(conn, operation, digest, claim, effect)

      receipts != [] ->
        if Enum.all?(receipts, &(&1.outcome == "unknown")) do
          reconciled_settlement(conn, operation, digest, claim, effect)
        else
          quarantine_conflicting_receipt(conn, operation, digest, claim, effect)
        end

      true ->
        first_settlement(conn, operation, digest, claim, effect)
    end
  end

  defp stale_unknown_receipt(conn, operation, digest, claim, effect) do
    receipt = receipt(operation, digest, claim.claim_id)

    with :ok <- settlement_proof("unknown", operation["proof"]),
         :ok <- insert_receipt(conn, receipt) do
      {:ok,
       %{
         "claim" => public_claim(claim),
         "effect" => public_effect(effect),
         "receipt" => public_receipt(receipt)
       }}
    else
      {:error, :invalid_receipt_proof} -> {:reject, :invalid_receipt_proof, %{}}
      {:error, _reason} = error -> error
    end
  end

  defp settlement_provenance(operation, claim, effect) do
    with true <- operation["request_id"] == effect.request_id,
         true <- operation["authenticated_actor"] == effect.issuer,
         true <- effect.channel == "protected-gateway",
         true <-
           operation["proof"] != "issuer_quiescent" or
             operation["payload"]["quiescence_epoch"] == claim.writer_epoch do
      :ok
    else
      _ -> {:error, :receipt_provenance_mismatch}
    end
  end

  defp reconciled_settlement(conn, operation, digest, claim, effect) do
    receipt = receipt(operation, digest, claim.claim_id)

    with :ok <- settlement_proof(operation["outcome"], operation["proof"]),
         {:ok, reservations} <- reservations_for_claim(conn, claim.claim_id),
         :ok <- insert_receipt(conn, receipt),
         :ok <- settle_reservations(conn, reservations, operation["outcome"]),
         next_claim <- %{
           claim
           | status: operation["outcome"],
             revision: claim.revision + 1
         },
         next_effect <- %{
           effect
           | status: operation["outcome"],
             revision: effect.revision + 1
         },
         :ok <- update_claim(conn, claim, next_claim),
         :ok <- update_effect(conn, effect, next_effect),
         :ok <- settle_leases(conn, claim.claim_id, operation["outcome"]),
         {:ok, ledgers} <- ledger_facts_for_reservations(conn, reservations) do
      {:ok,
       %{
         "claim" => public_claim(next_claim),
         "effect" => public_effect(next_effect),
         "receipt" => public_receipt(receipt),
         "ledgers" => ledgers
       }}
    else
      {:error, reason} when reason in [:invalid_receipt_proof] -> {:reject, reason, %{}}
      {:error, _reason} = error -> error
    end
  end

  defp first_settlement(conn, operation, digest, claim, effect) do
    outcome = operation["outcome"]

    with true <- claim.status in ["issued", "unknown"],
         :ok <- settlement_proof(outcome, operation["proof"]),
         {:ok, reservations} <- reservations_for_claim(conn, claim.claim_id),
         true <- reservations != [],
         receipt <- receipt(operation, digest, claim.claim_id),
         :ok <- insert_receipt(conn, receipt),
         :ok <- settle_reservations(conn, reservations, outcome),
         next_status <- if(outcome == "unknown", do: "unknown", else: outcome),
         next_claim <- %{claim | status: next_status, revision: claim.revision + 1},
         next_effect <- %{effect | status: next_status, revision: effect.revision + 1},
         :ok <- update_claim(conn, claim, next_claim),
         :ok <- update_effect(conn, effect, next_effect),
         :ok <- settle_leases(conn, claim.claim_id, outcome),
         {:ok, ledger_facts} <- ledger_facts_for_reservations(conn, reservations) do
      {:ok,
       %{
         "claim" => public_claim(next_claim),
         "effect" => public_effect(next_effect),
         "receipt" => public_receipt(receipt),
         "ledgers" => ledger_facts
       }}
    else
      {:error, reason} when reason in [:invalid_receipt_proof] -> {:reject, reason, %{}}
      {:error, _reason} = error -> error
      _ -> {:reject, :claim_settlement_not_permitted, %{}}
    end
  end

  defp quarantine_conflicting_receipt(conn, operation, digest, claim, effect) do
    attempted = receipt(operation, digest, claim.claim_id)
    next_claim = %{claim | status: "reconciliation_required", revision: claim.revision + 1}
    next_effect = %{effect | status: "reconciliation_required", revision: effect.revision + 1}

    with :ok <- update_claim(conn, claim, next_claim),
         :ok <- update_effect(conn, effect, next_effect),
         :ok <- retain_leases(conn, claim.claim_id) do
      {:quarantine, :conflicting_receipt,
       %{
         "claim" => public_claim(next_claim),
         "effect" => public_effect(next_effect),
         "attempted_receipt" => public_receipt(attempted)
       }}
    end
  end

  defp upsert_simple_root(conn, table, id_column, id, operation) do
    with :ok <- exact_keys(operation, ["type", id_column, "value", "root_command_id"]),
         :ok <- identity(id),
         true <- plain_map?(operation["value"]),
         {:ok, current} <- load_simple_optional(conn, table, id_column, id),
         revision <- if(current == :absent, do: 0, else: current.revision + 1),
         state <- %{
           "schema_version" => 1,
           id_column => id,
           "revision" => revision,
           "value" => operation["value"]
         },
         {:ok, bytes} <- encode(state),
         :ok <-
           insert_simple_history(
             conn,
             table,
             id_column,
             id,
             revision,
             operation["root_command_id"],
             bytes
           ),
         :ok <- write_simple(conn, table, id_column, id, revision, bytes, current) do
      {:ok, %{String.trim_trailing(table, "s") => state}}
    else
      {:error, _reason} = error -> error
      _ -> {:reject, :invalid_root_revision, %{}}
    end
  end

  defp complete_read_set(conn, operation, supplied) do
    with {:ok, required} <- required_reads(conn, operation),
         {:ok, supplied} <- normalize_read_set(supplied),
         true <- Map.keys(required) |> Enum.sort() == Map.keys(supplied) |> Enum.sort(),
         true <- required == supplied do
      :ok
    else
      false ->
        case normalize_read_set(supplied) do
          {:ok, supplied} ->
            case required_reads(conn, operation) do
              {:ok, required} ->
                if Map.keys(required) |> Enum.sort() == Map.keys(supplied) |> Enum.sort(),
                  do: {:error, :stale_read_set},
                  else: {:error, :incomplete_read_set}

              error ->
                error
            end

          _ ->
            {:error, :incomplete_read_set}
        end

      {:error, _reason} = error ->
        error

      _ ->
        {:error, :incomplete_read_set}
    end
  end

  defp required_reads(conn, %{"type" => type} = operation) when type in @operation_types do
    with {:ok, keys} <- operation_read_keys(conn, type, operation) do
      Enum.reduce_while(keys, {:ok, %{}}, fn key, {:ok, acc} ->
        case current_revision(conn, key) do
          {:ok, revision} -> {:cont, {:ok, Map.put(acc, key, revision)}}
          {:error, _reason} = error -> {:halt, error}
        end
      end)
    end
  end

  defp required_reads(_conn, _operation), do: {:ok, %{}}

  defp operation_read_keys(_conn, "set_policy", op),
    do: {:ok, ["policy/" <> to_string(op["policy_id"])]}

  defp operation_read_keys(conn, "set_control", op) do
    base = ["control/" <> to_string(op["control_id"])]

    if get_in(op, ["value", "status"]) == "cancel_requested" do
      with {:ok, rows} <-
             Database.query(
               conn,
               "SELECT effect_id FROM root_effects WHERE control_id = ? AND status IN ('pending', 'claimed', 'issued', 'unknown', 'reconciliation_required') ORDER BY effect_id",
               [op["control_id"]]
             ) do
        keys =
          Enum.flat_map(rows, fn [effect_id] ->
            ["effect/" <> effect_id | effect_dependency_keys(conn, effect_id)]
          end)

        {:ok, Enum.uniq(base ++ keys)}
      end
    else
      {:ok, base}
    end
  end

  defp operation_read_keys(_conn, "append_inbox", op),
    do: {:ok, ["inbox/" <> to_string(op["execution_id"])]}

  defp operation_read_keys(_conn, "seal_inbox", op),
    do: {:ok, ["inbox/" <> to_string(op["execution_id"])]}

  defp operation_read_keys(_conn, "grant_ledger", op),
    do: {:ok, [ledger_key(op["ledger_id"], op["generation"])]}

  defp operation_read_keys(_conn, "delegate_allocation", op),
    do:
      {:ok,
       [
         ledger_key(op["parent_ledger_id"], op["parent_generation"]),
         ledger_key(op["child_ledger_id"], op["child_generation"])
       ]}

  defp operation_read_keys(conn, "return_allocation", op) do
    child = ledger_key(op["child_ledger_id"], op["child_generation"])

    case load_ledger(conn, op["child_ledger_id"], op["child_generation"]) do
      {:ok, %{parent_ledger_id: parent, parent_generation: generation}}
      when is_binary(parent) ->
        {:ok, [child, ledger_key(parent, generation)]}

      _ ->
        {:ok, [child]}
    end
  end

  defp operation_read_keys(_conn, "reserve", op),
    do:
      {:ok,
       [
         ledger_key(op["ledger_id"], op["generation"]),
         "reservation/" <> to_string(op["reservation_id"])
       ]}

  defp operation_read_keys(conn, "release_reservation", op),
    do: {:ok, reservation_dependency_keys(conn, op["reservation_id"])}

  defp operation_read_keys(conn, "close_generation", op),
    do: subtree_read_keys(conn, op["ledger_id"], op["generation"])

  defp operation_read_keys(conn, "reset_generation", op) do
    base =
      [
        ledger_key(op["ledger_id"], op["old_generation"]),
        ledger_key(op["ledger_id"], op["new_generation"])
      ] ++
        if(is_binary(op["parent_ledger_id"]),
          do: [ledger_key(op["parent_ledger_id"], op["parent_generation"])],
          else: []
        )

    with {:ok, subtree} <- subtree_read_keys(conn, op["ledger_id"], op["old_generation"]) do
      {:ok, Enum.uniq(base ++ subtree)}
    end
  end

  defp operation_read_keys(conn, "close_attempt", op) do
    with {:ok, effects} <-
           attempt_effects(
             conn,
             to_string(op["scope"]),
             to_string(op["ticket_id"]),
             to_string(op["attempt_id"])
           ) do
      {:ok,
       [closure_key(op["ticket_id"], op["attempt_id"])] ++
         Enum.map(effects, &("effect/" <> &1.effect_id)) ++
         Enum.flat_map(effects, fn effect ->
           Enum.map(Map.get(effect, :reservation_ids, []), &("reservation/" <> &1))
         end)}
    end
  end

  defp operation_read_keys(conn, "create_effect", op) do
    base = [
      closure_key(op["ticket_id"], op["attempt_id"]),
      "effect/" <> to_string(op["effect_id"]),
      "policy/" <> to_string(op["policy_id"]),
      "control/" <> to_string(op["control_id"])
      | Enum.map(op["reservation_ids"] || [], &("reservation/" <> to_string(&1)))
    ]

    reservation_keys =
      Enum.flat_map(op["reservation_ids"] || [], &reservation_dependency_keys(conn, &1))

    lease_keys =
      Enum.map(op["leases"] || [], fn lease ->
        id = Map.get(lease, "lease_id", Map.get(lease, :lease_id))
        "lease/" <> to_string(id)
      end)

    {:ok, Enum.uniq(base ++ reservation_keys ++ lease_keys)}
  end

  defp operation_read_keys(conn, "claim_effect", op) do
    reservations =
      case reservations_for_effect(conn, op["effect_id"]) do
        {:ok, values} -> Enum.flat_map(values, &full_reservation_keys/1)
        _ -> []
      end

    authority = effect_authority_keys(conn, op["effect_id"])

    {:ok,
     Enum.uniq([
       "effect/" <> to_string(op["effect_id"]),
       "claim/" <> to_string(op["claim_id"])
       | authority ++ reservations
     ])}
  end

  defp operation_read_keys(conn, "cancel_effect", op) do
    effect_key = "effect/" <> to_string(op["effect_id"])

    case load_effect(conn, op["effect_id"]) do
      {:ok, effect} ->
        reservation_keys =
          case reservations_for_effect(conn, effect.effect_id) do
            {:ok, values} -> Enum.flat_map(values, &full_reservation_keys/1)
            _ -> []
          end

        claim_keys =
          case Database.query(
                 conn,
                 "SELECT claim_id FROM root_claims WHERE effect_id = ? ORDER BY claim_id",
                 [effect.effect_id]
               ) do
            {:ok, rows} -> Enum.map(rows, fn [id] -> "claim/" <> id end)
            _ -> []
          end

        lease_keys = Enum.map(effect.lease_specs, &("lease/" <> &1["lease_id"]))
        authority_keys = ["policy/" <> effect.policy_id, "control/" <> effect.control_id]

        {:ok,
         Enum.uniq([effect_key | authority_keys ++ reservation_keys ++ claim_keys ++ lease_keys])}

      _ ->
        {:ok, [effect_key]}
    end
  end

  defp operation_read_keys(conn, "settle_claim", op) do
    with {:ok, base} <- claim_operation_read_keys(conn, "settle_claim", op) do
      if op["outcome"] == "non_started" do
        case load_claim(conn, op["claim_id"]) do
          {:ok, claim} ->
            case load_effect(conn, claim.effect_id) do
              {:ok, effect} ->
                lineage = infrastructure_lineage_key(effect)
                settlement = "settlement/" <> effect.effect_id

                predecessor =
                  if is_binary(effect.predecessor_effect_id),
                    do: ["settlement/" <> effect.predecessor_effect_id],
                    else: []

                {:ok, Enum.uniq(base ++ [settlement, lineage] ++ predecessor)}

              _ ->
                {:ok, base}
            end

          _ ->
            {:ok, base}
        end
      else
        {:ok, base}
      end
    end
  end

  defp operation_read_keys(conn, type, op) when type in ["reclaim_claim", "issue_claim"],
    do: claim_operation_read_keys(conn, type, op)

  defp operation_read_keys(_conn, _type, _op), do: {:ok, []}

  defp claim_operation_read_keys(conn, type, op) do
    claim_key = "claim/" <> to_string(op["claim_id"])

    case load_claim(conn, op["claim_id"]) do
      {:ok, claim} ->
        effect_keys =
          case load_effect(conn, claim.effect_id) do
            {:ok, effect} ->
              [
                "effect/" <> effect.effect_id,
                "policy/" <> effect.policy_id,
                "control/" <> effect.control_id
              ] ++
                predecessor_read_keys(conn, effect) ++
                Enum.map(effect.lease_specs, &("lease/" <> &1["lease_id"]))

            _ ->
              []
          end

        reservation_keys =
          case reservations_for_claim(conn, claim.claim_id) do
            {:ok, values} -> Enum.flat_map(values, &full_reservation_keys/1)
            _ -> []
          end

        receipt_keys =
          if type == "settle_claim", do: ["receipt/" <> to_string(op["receipt_id"])], else: []

        {:ok, Enum.uniq([claim_key | effect_keys ++ reservation_keys ++ receipt_keys])}

      _ ->
        {:ok, [claim_key]}
    end
  end

  defp reservation_dependency_keys(conn, id) do
    base = ["reservation/" <> to_string(id)]

    case load_reservation(conn, id) do
      {:ok, reservation} -> base ++ reservation_keys(reservation)
      _ -> base
    end
  end

  defp reservation_keys(reservation) do
    claim_keys = if reservation.claim_id, do: ["claim/" <> reservation.claim_id], else: []
    [ledger_key(reservation.ledger_id, reservation.generation) | claim_keys]
  end

  defp full_reservation_keys(reservation),
    do: ["reservation/" <> reservation.reservation_id | reservation_keys(reservation)]

  defp effect_authority_keys(conn, effect_id) do
    case load_effect(conn, effect_id) do
      {:ok, effect} ->
        [
          "effect/" <> effect.effect_id,
          "policy/" <> effect.policy_id,
          "control/" <> effect.control_id
        ] ++
          predecessor_read_keys(conn, effect) ++
          Enum.map(effect.lease_specs, &("lease/" <> &1["lease_id"]))

      _ ->
        ["effect/" <> to_string(effect_id)]
    end
  end

  defp predecessor_read_keys(conn, effect), do: predecessor_read_keys(conn, effect, MapSet.new())

  defp predecessor_read_keys(conn, %{predecessor_effect_id: id}, seen)
       when is_binary(id) do
    if MapSet.member?(seen, id) do
      ["effect/" <> id]
    else
      case load_effect(conn, id) do
        {:ok, predecessor} ->
          ["effect/" <> id | predecessor_read_keys(conn, predecessor, MapSet.put(seen, id))]

        _ ->
          ["effect/" <> id]
      end
    end
  end

  defp predecessor_read_keys(_conn, _effect, _seen), do: []

  defp current_revision(conn, "policy/" <> id),
    do: simple_revision(conn, "root_policies", "policy_id", id)

  defp current_revision(conn, "control/" <> id),
    do: simple_revision(conn, "root_controls", "control_id", id)

  defp current_revision(conn, "inbox/" <> id),
    do: simple_revision(conn, "authenticated_inboxes", "execution_id", id)

  defp current_revision(conn, "reservation/" <> id),
    do: simple_revision(conn, "root_reservations", "reservation_id", id)

  defp current_revision(conn, "effect/" <> id),
    do: simple_revision(conn, "root_effects", "effect_id", id)

  defp current_revision(conn, "claim/" <> id),
    do: simple_revision(conn, "root_claims", "claim_id", id)

  defp current_revision(conn, "lease/" <> id),
    do: simple_revision(conn, "root_leases", "lease_id", id)

  defp current_revision(conn, "receipt/" <> id) do
    with :ok <- identity(id),
         {:ok, rows} <-
           Database.query(conn, "SELECT 1 FROM root_receipts WHERE receipt_id = ?", [id]) do
      case rows do
        [] -> {:ok, "absent"}
        [[1]] -> {:ok, 0}
        _ -> {:error, :duplicate_protected_identity}
      end
    end
  end

  defp current_revision(conn, "settlement/" <> id) do
    with :ok <- identity(id),
         {:ok, rows} <-
           Database.query(
             conn,
             "SELECT 1 FROM root_infrastructure_settlements WHERE effect_id = ?",
             [id]
           ) do
      case rows do
        [] -> {:ok, "absent"}
        [[1]] -> {:ok, 0}
        _ -> {:error, :duplicate_protected_identity}
      end
    end
  end

  defp current_revision(conn, "infrastructure/" <> encoded) do
    with [role64, owner64, generation_text] <- String.split(encoded, "/", parts: 3),
         {:ok, role} <- Base.url_decode64(role64, padding: false),
         {:ok, owner} <- Base.url_decode64(owner64, padding: false),
         {generation, ""} when generation >= 0 <- Integer.parse(generation_text),
         {:ok, [[count]]} <-
           Database.query(
             conn,
             "SELECT count(*) FROM root_infrastructure_settlements WHERE role = ? AND work_owner = ? AND infrastructure_generation = ?",
             [role, owner, generation]
           ) do
      {:ok, count}
    else
      _ -> {:error, :invalid_read_set_key}
    end
  end

  defp current_revision(conn, "ledger/" <> rest) do
    case String.split(rest, "/", parts: 2) do
      [id, generation] ->
        case Integer.parse(generation) do
          {generation, ""} -> ledger_revision(conn, id, generation)
          _ -> {:error, :invalid_read_set_key}
        end

      _ ->
        {:error, :invalid_read_set_key}
    end
  end

  defp current_revision(conn, "closure/" <> encoded) do
    with [ticket64, attempt64] <- String.split(encoded, "/", parts: 2),
         {:ok, ticket_id} <- Base.url_decode64(ticket64, padding: false),
         {:ok, attempt_id} <- Base.url_decode64(attempt64, padding: false),
         {:ok, rows} <-
           Database.query(
             conn,
             "SELECT 1 FROM root_attempt_closures WHERE ticket_id = ? AND attempt_id = ?",
             [ticket_id, attempt_id]
           ) do
      case rows do
        [] -> {:ok, "absent"}
        [[1]] -> {:ok, 0}
        _ -> {:error, :duplicate_protected_identity}
      end
    else
      _ -> {:error, :invalid_read_set_key}
    end
  end

  defp current_revision(_conn, _key), do: {:error, :invalid_read_set_key}

  defp closure_key(ticket_id, attempt_id) do
    "closure/" <>
      Base.url_encode64(to_string(ticket_id), padding: false) <>
      "/" <> Base.url_encode64(to_string(attempt_id), padding: false)
  end

  defp infrastructure_lineage_key(effect) do
    encoded_infrastructure_lineage_key(
      effect.role,
      effect.assignment_id,
      effect.phase_generation
    )
  end

  defp encoded_infrastructure_lineage_key(role, owner, generation) do
    role = Base.url_encode64(role, padding: false)
    owner = Base.url_encode64(owner, padding: false)
    "infrastructure/#{role}/#{owner}/#{generation}"
  end

  defp simple_revision(conn, table, column, id) do
    with :ok <- identity(id),
         {:ok, rows} <-
           Database.query(conn, "SELECT revision FROM #{table} WHERE #{column} = ?", [id]) do
      case rows do
        [] -> {:ok, "absent"}
        [[revision]] -> {:ok, revision}
        _ -> {:error, :duplicate_protected_identity}
      end
    end
  end

  defp ledger_revision(conn, id, generation) do
    with {:ok, rows} <-
           Database.query(
             conn,
             "SELECT revision FROM root_ledgers WHERE ledger_id = ? AND generation = ?",
             [id, generation]
           ) do
      case rows do
        [] -> {:ok, "absent"}
        [[revision]] -> {:ok, revision}
        _ -> {:error, :duplicate_protected_identity}
      end
    end
  end

  defp normalize_request(request) do
    with {:ok, request} <- string_map(request),
         :ok <- exact_keys(request, ~w(schema_version command_id expected_revisions operation)),
         1 <- request["schema_version"],
         :ok <- identity(request["command_id"]),
         {:ok, _reads} <- normalize_read_set(request["expected_revisions"]),
         {:ok, operation} <- string_map(request["operation"]),
         type when type in @operation_types <- operation["type"] do
      {:ok, Map.put(request, "operation", operation)}
    else
      {:error, _reason} = error -> error
      _ -> {:error, :invalid_protected_command}
    end
  end

  defp normalize_read_set(reads) when is_map(reads) and not is_struct(reads) do
    Enum.reduce_while(reads, {:ok, %{}}, fn
      {key, value}, {:ok, acc}
      when is_binary(key) and (value == "absent" or (is_integer(value) and value >= 0)) ->
        {:cont, {:ok, Map.put(acc, key, value)}}

      _item, _acc ->
        {:halt, {:error, :invalid_read_set}}
    end)
  end

  defp normalize_read_set(_reads), do: {:error, :invalid_read_set}

  defp validate_public_command_identity(conn, command_id) do
    with false <- String.starts_with?(command_id, "atomic-v2/"),
         {:ok, [[domain_count]]} <-
           Database.query(conn, "SELECT count(*) FROM commands WHERE command_id = ?", [command_id]),
         true <- domain_count == 0 do
      :ok
    else
      _ -> {:error, :idempotency_conflict}
    end
  end

  defp request_digest(actor_id, request),
    do:
      Encoding.semantic_digest("pramana-foundry-protected-command-v1", %{
        "actor_id" => actor_id,
        "request" => request
      })

  defp existing_command(conn, command_id, actor_id, digest) do
    with {:ok, rows} <-
           Database.query(
             conn,
             "SELECT actor_id, request_digest, result FROM root_commands WHERE command_id = ?",
             [command_id]
           ) do
      case rows do
        [] ->
          case Database.query(conn, "SELECT 1 FROM commands WHERE command_id = ?", [command_id]) do
            {:ok, []} -> {:error, :not_found}
            {:ok, _rows} -> {:error, :idempotency_conflict}
            {:error, _reason} = error -> error
          end

        [[^actor_id, ^digest, bytes]] ->
          decode(bytes)

        [[_actor, _digest, _bytes]] ->
          {:error, :idempotency_conflict}

        _ ->
          {:error, :duplicate_protected_identity}
      end
    end
  end

  defp persist_result(conn, actor_id, request, digest, disposition, reason, facts) do
    with {:ok, [[next_seq]]} <-
           Database.query(conn, "SELECT coalesce(max(seq), 0) + 1 FROM root_commands"),
         result <- %{
           "schema_version" => 1,
           "command_id" => request["command_id"],
           "command_sequence" => next_seq,
           "disposition" => disposition,
           "reason_code" => reason,
           "facts" => facts
         },
         {:ok, canonical_request} <-
           encode(%{"actor_id" => actor_id, "schema_version" => 1, "request" => request}),
         {:ok, bytes} <- encode(result),
         :ok <-
           Database.execute(
             conn,
             "INSERT INTO root_commands(seq, command_id, actor_id, request_digest, canonical_request, schema_version, operation, disposition, reason_code, result) VALUES (?, ?, ?, ?, ?, 1, ?, ?, ?, ?)",
             [
               next_seq,
               request["command_id"],
               actor_id,
               digest,
               {:blob, canonical_request},
               request["operation"]["type"],
               disposition,
               reason,
               {:blob, bytes}
             ]
           ) do
      {:ok, result}
    end
  end

  defp load_inbox(conn, id) do
    case load_existing_inbox(conn, id) do
      {:ok, inbox} -> {:ok, inbox}
      {:error, :not_found} -> {:ok, :absent}
      error -> error
    end
  end

  defp load_existing_inbox(conn, id) do
    with {:ok, rows} <-
           Database.query(
             conn,
             "SELECT actor_id, revision, last_sequence, sealed_sequence FROM authenticated_inboxes WHERE execution_id = ?",
             [id]
           ) do
      case rows do
        [] ->
          {:error, :not_found}

        [[actor, revision, last, sealed]] ->
          {:ok,
           %{actor_id: actor, revision: revision, last_sequence: last, sealed_sequence: sealed}}

        _ ->
          {:error, :duplicate_protected_identity}
      end
    end
  end

  defp inbox_append_guard(:absent, 1), do: {:ok, "accepted"}
  defp inbox_append_guard(:absent, _sequence), do: {:error, :inbox_sequence_conflict}

  defp inbox_append_guard(%{last_sequence: last, sealed_sequence: sealed}, sequence)
       when sequence == last + 1 and not is_nil(sealed),
       do: {:ok, "late"}

  defp inbox_append_guard(%{last_sequence: last}, sequence) when sequence == last + 1,
    do: {:ok, "accepted"}

  defp inbox_append_guard(_inbox, _sequence), do: {:error, :inbox_sequence_conflict}

  defp write_inbox_head(conn, :absent, id, actor_id, sequence) do
    inbox = %{actor_id: actor_id, revision: 0, last_sequence: sequence, sealed_sequence: nil}

    with {:ok, bytes} <- encode(inbox_state(id, inbox)) do
      Database.execute(
        conn,
        "INSERT INTO authenticated_inboxes(execution_id, actor_id, revision, last_sequence, sealed_sequence, state) VALUES (?, ?, 0, ?, NULL, ?)",
        [id, inbox.actor_id, sequence, {:blob, bytes}]
      )
    end
  end

  defp write_inbox_head(conn, current, id, actor_id, sequence) do
    next = %{current | revision: current.revision + 1, last_sequence: sequence}

    with true <- current.actor_id == actor_id,
         {:ok, bytes} <- encode(inbox_state(id, next)) do
      Database.execute(
        conn,
        "UPDATE authenticated_inboxes SET revision = ?, last_sequence = ?, state = ? WHERE execution_id = ? AND revision = ?",
        [next.revision, sequence, {:blob, bytes}, id, current.revision]
      )
    else
      false -> {:error, :inbox_actor_conflict}
      {:error, _reason} = error -> error
    end
  end

  defp inbox_state(id, inbox) do
    %{
      "schema_version" => 1,
      "execution_id" => id,
      "actor_id" => inbox.actor_id,
      "revision" => inbox.revision,
      "last_sequence" => inbox.last_sequence,
      "sealed_sequence" => inbox.sealed_sequence
    }
  end

  defp inbox_fact(conn, id) do
    with :ok <- identity(id),
         {:ok, inbox} <- load_existing_inbox(conn, id),
         {:ok, rows} <-
           Database.query(
             conn,
             "SELECT sequence, item_kind, disposition, item_digest, item FROM authenticated_inbox_items WHERE execution_id = ? ORDER BY sequence",
             [id]
           ),
         {:ok, items} <- decode_inbox_items(rows),
         resolution <- inbox_resolution(inbox, items) do
      {:ok,
       inbox_state(id, inbox)
       |> Map.put("items", items)
       |> Map.put("resolution", resolution)}
    end
  end

  defp decode_inbox_items(rows) do
    Enum.reduce_while(rows, {:ok, []}, fn [sequence, kind, disposition, digest, bytes],
                                          {:ok, acc} ->
      case decode(bytes) do
        {:ok,
         %{
           "sequence" => ^sequence,
           "item_kind" => ^kind,
           "disposition" => ^disposition,
           "item_digest" => ^digest
         } = item} ->
          {:cont, {:ok, [item | acc]}}

        _ ->
          {:halt, {:error, :corrupt_inbox_item}}
      end
    end)
    |> then(fn
      {:ok, items} -> {:ok, Enum.reverse(items)}
      error -> error
    end)
  end

  defp inbox_resolution(%{sealed_sequence: nil}, _items), do: %{"status" => "open"}

  defp inbox_resolution(_inbox, items) do
    accepted = Enum.filter(items, &(&1["disposition"] == "accepted"))

    case Enum.find(accepted, &(&1["item_kind"] == "result")) do
      nil ->
        case Enum.find(accepted, &(&1["item_kind"] == "exit")) do
          nil ->
            %{"status" => "sealed_without_result_or_exit"}

          exit ->
            %{"status" => "exit", "sequence" => exit["sequence"], "payload" => exit["payload"]}
        end

      result ->
        %{"status" => "result", "sequence" => result["sequence"], "payload" => result["payload"]}
    end
  end

  defp load_simple_optional(conn, table, column, id) do
    case load_simple(conn, table, column, id) do
      {:ok, value} ->
        {:ok, value}

      {:error, reason} when reason in [:not_found, :policy_not_found, :control_not_found] ->
        {:ok, :absent}

      error ->
        error
    end
  end

  defp load_simple(conn, table, column, id) do
    with {:ok, rows} <-
           Database.query(conn, "SELECT revision, state FROM #{table} WHERE #{column} = ?", [id]) do
      case rows do
        [] ->
          {:error, if(table == "root_policies", do: :policy_not_found, else: :control_not_found)}

        [[revision, bytes]] ->
          with {:ok, state} <- decode(bytes),
               do: {:ok, %{revision: revision, value: state["value"]}}

        _ ->
          {:error, :duplicate_protected_identity}
      end
    end
  end

  defp write_simple(conn, table, column, id, revision, bytes, :absent) do
    Database.execute(
      conn,
      "INSERT INTO #{table}(#{column}, revision, state) VALUES (?, ?, ?)",
      [id, revision, {:blob, bytes}]
    )
  end

  defp write_simple(conn, table, column, id, revision, bytes, current) do
    Database.execute(
      conn,
      "UPDATE #{table} SET revision = ?, state = ? WHERE #{column} = ? AND revision = ?",
      [revision, {:blob, bytes}, id, current.revision]
    )
  end

  defp insert_simple_history(
         conn,
         "root_policies",
         "policy_id",
         id,
         revision,
         command_id,
         bytes
       ) do
    insert_history_row(
      conn,
      "root_policy_history",
      "policy_id",
      id,
      revision,
      command_id,
      bytes
    )
  end

  defp insert_simple_history(
         conn,
         "root_controls",
         "control_id",
         id,
         revision,
         command_id,
         bytes
       ) do
    insert_history_row(
      conn,
      "root_control_history",
      "control_id",
      id,
      revision,
      command_id,
      bytes
    )
  end

  defp insert_history_row(conn, table, column, id, revision, command_id, bytes) do
    prior = if revision == 0, do: nil, else: revision - 1

    Database.execute(
      conn,
      "INSERT INTO #{table}(#{column}, revision, prior_revision, command_id, state) VALUES (?, ?, ?, ?, ?)",
      [id, revision, prior, command_id, {:blob, bytes}]
    )
  end

  defp load_ledger(conn, id, generation) do
    with :ok <- identity(id),
         true <- is_integer(generation) and generation >= 0,
         {:ok, rows} <-
           Database.query(
             conn,
             "SELECT ledger_id, generation, parent_ledger_id, parent_generation, dimension, revision, status, authorized, available, held, consumed, delegated, retired FROM root_ledgers WHERE ledger_id = ? AND generation = ?",
             [id, generation]
           ) do
      case rows do
        [] -> {:ok, :absent}
        [row] -> {:ok, ledger_from_row(row)}
        _ -> {:error, :duplicate_protected_identity}
      end
    else
      false -> {:error, :invalid_ledger_identity}
      {:error, _reason} = error -> error
    end
  end

  defp load_existing_ledger(conn, id, generation) do
    case load_ledger(conn, id, generation) do
      {:ok, :absent} -> {:error, :not_found}
      other -> other
    end
  end

  defp current_generation(conn, id) do
    with :ok <- identity(id),
         {:ok, rows} <-
           Database.query(conn, "SELECT max(generation) FROM root_ledgers WHERE ledger_id = ?", [
             id
           ]) do
      case rows do
        [[generation]] when is_integer(generation) -> {:ok, generation}
        [[nil]] -> {:error, :not_found}
        _ -> {:error, :duplicate_protected_identity}
      end
    end
  end

  defp ledger_from_row([
         id,
         generation,
         parent_id,
         parent_generation,
         dimension,
         revision,
         status,
         authorized,
         available,
         held,
         consumed,
         delegated,
         retired
       ]) do
    %{
      ledger_id: id,
      generation: generation,
      parent_ledger_id: parent_id,
      parent_generation: parent_generation,
      dimension: dimension,
      revision: revision,
      status: status,
      authorized: authorized,
      available: available,
      held: held,
      consumed: consumed,
      delegated: delegated,
      retired: retired
    }
  end

  defp public_ledger(ledger) do
    ledger
    |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)
    |> Map.put("schema_version", 1)
  end

  defp insert_ledger(conn, ledger) do
    with {:ok, bytes} <- encode(public_ledger(ledger)) do
      Database.execute(
        conn,
        "INSERT INTO root_ledgers(ledger_id, generation, parent_ledger_id, parent_generation, dimension, revision, status, authorized, available, held, consumed, delegated, retired, state) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        ledger_params(ledger) ++ [{:blob, bytes}]
      )
    end
  end

  defp update_ledger(conn, old, next) do
    with true <- conserved?(next),
         {:ok, bytes} <- encode(public_ledger(next)),
         :ok <-
           Database.execute(
             conn,
             "UPDATE root_ledgers SET revision = ?, status = ?, authorized = ?, available = ?, held = ?, consumed = ?, delegated = ?, retired = ?, state = ? WHERE ledger_id = ? AND generation = ? AND revision = ?",
             [
               next.revision,
               next.status,
               next.authorized,
               next.available,
               next.held,
               next.consumed,
               next.delegated,
               next.retired,
               {:blob, bytes},
               old.ledger_id,
               old.generation,
               old.revision
             ]
           ),
         {:ok, [[1]]} <- Database.query(conn, "SELECT changes()") do
      :ok
    else
      false -> {:error, :ledger_conservation_violation}
      {:ok, _rows} -> {:error, :ledger_revision_conflict}
      {:error, _reason} = error -> error
    end
  end

  defp ledger_params(ledger) do
    [
      ledger.ledger_id,
      ledger.generation,
      ledger.parent_ledger_id,
      ledger.parent_generation,
      ledger.dimension,
      ledger.revision,
      ledger.status,
      ledger.authorized,
      ledger.available,
      ledger.held,
      ledger.consumed,
      ledger.delegated,
      ledger.retired
    ]
  end

  defp conserved?(ledger),
    do:
      ledger.authorized ==
        ledger.available + ledger.held + ledger.consumed + ledger.delegated + ledger.retired and
        Enum.all?(
          [
            ledger.authorized,
            ledger.available,
            ledger.held,
            ledger.consumed,
            ledger.delegated,
            ledger.retired
          ],
          &(&1 >= 0)
        )

  defp ledger_key(id, generation), do: "ledger/#{id}/#{generation}"

  defp insert_reservation(conn, reservation) do
    with {:ok, bytes} <- encode(public_reservation(reservation)) do
      Database.execute(
        conn,
        "INSERT INTO root_reservations(reservation_id, ledger_id, generation, dimension, owner_kind, owner_id, units, revision, status, claim_id, state) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        [
          reservation.reservation_id,
          reservation.ledger_id,
          reservation.generation,
          reservation.dimension,
          reservation.owner_kind,
          reservation.owner_id,
          reservation.units,
          reservation.revision,
          reservation.status,
          reservation.claim_id,
          {:blob, bytes}
        ]
      )
    end
  end

  defp load_reservation(conn, id) do
    with {:ok, rows} <-
           Database.query(
             conn,
             "SELECT reservation_id, ledger_id, generation, dimension, owner_kind, owner_id, units, revision, status, claim_id FROM root_reservations WHERE reservation_id = ?",
             [id]
           ) do
      case rows do
        [] -> {:error, :not_found}
        [row] -> {:ok, reservation_from_row(row)}
        _ -> {:error, :duplicate_protected_identity}
      end
    end
  end

  defp reservation_from_row([
         id,
         ledger_id,
         generation,
         dimension,
         owner_kind,
         owner_id,
         units,
         revision,
         status,
         claim_id
       ]) do
    %{
      reservation_id: id,
      ledger_id: ledger_id,
      generation: generation,
      dimension: dimension,
      owner_kind: owner_kind,
      owner_id: owner_id,
      units: units,
      revision: revision,
      status: status,
      claim_id: claim_id
    }
  end

  defp public_reservation(reservation) do
    reservation
    |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)
    |> Map.put("schema_version", 1)
  end

  defp update_reservation(conn, old, next) do
    with {:ok, bytes} <- encode(public_reservation(next)),
         :ok <-
           Database.execute(
             conn,
             "UPDATE root_reservations SET revision = ?, status = ?, claim_id = ?, state = ? WHERE reservation_id = ? AND revision = ?",
             [
               next.revision,
               next.status,
               next.claim_id,
               {:blob, bytes},
               old.reservation_id,
               old.revision
             ]
           ) do
      :ok
    end
  end

  defp release_guard(_conn, %{claim_id: nil}), do: :ok

  defp release_guard(conn, %{claim_id: claim_id}) do
    with {:ok, claim} <- load_claim(conn, claim_id) do
      if claim.status == "claimed", do: :ok, else: {:error, :claim_already_issued}
    end
  end

  defp reservations_open?(conn, reservations) do
    Enum.reduce_while(reservations, :ok, fn reservation, :ok ->
      case load_existing_ledger(conn, reservation.ledger_id, reservation.generation) do
        {:ok, %{status: "open"}} ->
          case current_generation(conn, reservation.ledger_id) do
            {:ok, generation} when generation == reservation.generation -> {:cont, :ok}
            {:ok, _newer} -> {:halt, {:error, :ledger_generation_superseded}}
            {:error, _reason} = error -> {:halt, error}
          end

        {:ok, %{status: "closed"}} ->
          {:halt, {:error, :ledger_closed}}

        {:error, _reason} = error ->
          {:halt, error}
      end
    end)
  end

  defp release_hold(ledger, units) do
    if ledger.status == "open" do
      %{
        ledger
        | revision: ledger.revision + 1,
          held: ledger.held - units,
          available: ledger.available + units
      }
    else
      %{
        ledger
        | revision: ledger.revision + 1,
          held: ledger.held - units,
          retired: ledger.retired + units
      }
    end
  end

  defp allowed_effect?(policy, control, operation) do
    with :ok <- control_active?(control),
         operations when is_list(operations) <- policy["allowed_operations"],
         scopes when is_list(scopes) <- policy["allowed_scopes"],
         roles when is_list(roles) <- policy["allowed_roles"] || [operation["request"]["role"]],
         profiles when is_list(profiles) <-
           policy["allowed_profiles"] || [operation["request"]["profile"] || "unspecified"],
         true <- operation["operation"] in operations,
         true <- operation["scope"] in scopes,
         true <- operation["scope"] == "ticket:" <> operation["ticket_id"],
         true <- operation["request"]["role"] in roles,
         true <- Map.get(operation["request"], "profile", "unspecified") in profiles,
         true <- deadline_allowed?(policy, operation["request"]["deadline"]) do
      :ok
    else
      {:error, _reason} = error -> error
      _ -> {:error, :effect_not_allowed}
    end
  end

  defp deadline_allowed?(policy, deadline) do
    case Map.fetch(policy, "allowed_deadlines") do
      :error -> is_nil(deadline)
      {:ok, deadlines} -> is_list(deadlines) and is_integer(deadline) and deadline in deadlines
    end
  end

  # One per-role limit, the same one the infrastructure discriminator reads. Reading the
  # policy-wide scalar `launch_non_start_limit` (default 0) here stranded every retry the
  # discriminator had just selected: the non-start settled below the limit, and the retry's
  # create_effect was refused (decide/3 design review, C2). The contract names the limit
  # `launch_non_start_limit` "per role and work owner"; the protected key that holds it per
  # role is `infrastructure_attempt_limits`.
  defp nonstart_allowance(conn, policy, operation) do
    limit =
      case policy["infrastructure_attempt_limits"] do
        limits when is_map(limits) -> Map.get(limits, operation["request"]["role"], 0)
        _ -> 0
      end

    with true <- is_integer(limit) and limit >= 0,
         {:ok, rows} <-
           Database.query(
             conn,
             "SELECT state FROM root_effects WHERE ticket_id = ? AND attempt_id = ? AND operation = ? AND status = 'non_started'",
             [operation["ticket_id"], operation["attempt_id"], operation["operation"]]
           ),
         count <-
           Enum.count(rows, fn [bytes] ->
             case decode(bytes) do
               {:ok, state} -> state["role"] == operation["request"]["role"]
               _ -> true
             end
           end),
         true <- count < limit or rows == [] do
      :ok
    else
      _ -> {:error, :nonstart_allowance_exhausted}
    end
  end

  defp control_active?(%{"status" => "active"}), do: :ok
  defp control_active?(_control), do: {:error, :control_not_active}

  defp load_effect_reservations(conn, operation) do
    effect_id = operation["effect_id"]

    operation["reservation_ids"]
    |> Enum.reduce_while({:ok, []}, fn id, {:ok, acc} ->
      case load_reservation(conn, id) do
        {:ok, reservation}
        when reservation.owner_kind == "effect" and
               reservation.owner_id == effect_id and
               reservation.status == "proposed" and is_nil(reservation.claim_id) ->
          {:cont, {:ok, [reservation | acc]}}

        {:ok, %{status: status}} when status != "proposed" ->
          {:halt, {:error, :reservation_not_held}}

        {:ok, _reservation} ->
          {:halt, {:error, :reservation_owner_mismatch}}

        {:error, :not_found} ->
          {:halt, {:error, :reservation_not_found}}

        error ->
          {:halt, error}
      end
    end)
    |> then(fn
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end)
  end

  defp activate_reservations(conn, reservations) do
    Enum.reduce_while(reservations, {:ok, []}, fn reservation, {:ok, acc} ->
      with "proposed" <- reservation.status,
           {:ok, ledger} <-
             load_existing_ledger(conn, reservation.ledger_id, reservation.generation),
           "open" <- ledger.status,
           true <- reservation.units <= ledger.available,
           next_ledger <- %{
             ledger
             | revision: ledger.revision + 1,
               available: ledger.available - reservation.units,
               held: ledger.held + reservation.units
           },
           next_reservation <- %{
             reservation
             | revision: reservation.revision + 1,
               status: "reserved"
           },
           :ok <- update_ledger(conn, ledger, next_ledger),
           :ok <- update_reservation(conn, reservation, next_reservation) do
        {:cont, {:ok, [next_reservation | acc]}}
      else
        {:error, _reason} = error -> {:halt, error}
        _ -> {:halt, {:error, :reservation_activation_not_permitted}}
      end
    end)
    |> then(fn
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end)
  end

  defp maybe_update_ledger(_conn, ledger, ledger), do: :ok
  defp maybe_update_ledger(conn, old, next), do: update_ledger(conn, old, next)

  defp normalize_lease_specs(specs) do
    Enum.reduce_while(specs, {:ok, []}, fn spec, {:ok, acc} ->
      with {:ok, spec} <- string_map(spec),
           :ok <- exact_keys(spec, ~w(lease_id resource_id)),
           :ok <- identities(spec, ~w(lease_id resource_id)) do
        {:cont, {:ok, [spec | acc]}}
      else
        _ -> {:halt, {:error, :invalid_lease_spec}}
      end
    end)
    |> then(fn
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end)
  end

  defp lease_specs_available(conn, specs) do
    Enum.reduce_while(specs, :ok, fn spec, :ok ->
      case Database.query(
             conn,
             "SELECT lease_id FROM root_leases WHERE lease_id = ? OR (resource_id = ? AND status IN ('held', 'retained'))",
             [spec["lease_id"], spec["resource_id"]]
           ) do
        {:ok, []} -> {:cont, :ok}
        {:ok, _rows} -> {:halt, {:error, :lease_conflict}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp attempt_open(conn, ticket_id, attempt_id) do
    case Database.query(
           conn,
           "SELECT 1 FROM root_attempt_closures WHERE ticket_id = ? AND attempt_id = ?",
           [ticket_id, attempt_id]
         ) do
      {:ok, []} -> :ok
      {:ok, _} -> {:error, :attempt_closed}
      {:error, _reason} = error -> error
    end
  end

  # Filtered by scope as well, so if an objective scope becomes admissible (O0 U9) a
  # ticket closure cannot silently widen over it (review of 03aff5db).
  defp attempt_effects(conn, scope, ticket_id, attempt_id) do
    with {:ok, rows} <-
           Database.query(
             conn,
             "SELECT effect_id FROM root_effects WHERE scope = ? AND ticket_id = ? AND attempt_id = ? ORDER BY effect_id",
             [scope, ticket_id, attempt_id]
           ) do
      Enum.reduce_while(rows, {:ok, []}, fn [id], {:ok, acc} ->
        case load_effect(conn, id) do
          {:ok, effect} -> {:cont, {:ok, acc ++ [effect]}}
          error -> {:halt, error}
        end
      end)
    end
  end

  # The activated set, not every reservation naming the effect as owner: a stray proposed
  # reservation holds no units and must not block the close (review F3).
  defp attempt_reservations(conn, effects) do
    effects
    |> Enum.flat_map(&Map.get(&1, :reservation_ids, []))
    |> Enum.reduce_while({:ok, []}, fn id, {:ok, acc} ->
      case load_reservation(conn, id) do
        {:ok, reservation} -> {:cont, {:ok, acc ++ [reservation]}}
        error -> {:halt, error}
      end
    end)
  end

  defp attempt_settlement(operation, effects, reservations) do
    units =
      Enum.reduce(reservations, %{}, fn reservation, acc ->
        update_in(
          acc,
          [Access.key(reservation.status, %{}), Access.key(reservation.dimension, 0)],
          &(&1 + reservation.units)
        )
      end)

    %{
      "schema_version" => 1,
      "scope" => operation["scope"],
      "ticket_id" => operation["ticket_id"],
      "attempt_id" => operation["attempt_id"],
      "effect_ids" => Enum.map(effects, & &1.effect_id),
      "settled_units" => units
    }
  end

  defp semantic_effect_available(conn, operation) do
    role = Map.get(operation["request"], "role")
    request_id = Map.get(operation["request"], "request_id")
    phase_generation = Map.get(operation["request"], "phase_generation", 0)
    ordinal = Map.get(operation["request"], "operation_ordinal", 0)

    with {:ok, request_rows} <- Database.query(conn, "SELECT state FROM root_effects"),
         false <-
           Enum.any?(request_rows, fn [bytes] ->
             case decode(bytes) do
               {:ok, state} -> state["request_id"] == request_id
               _ -> true
             end
           end),
         {:ok, rows} <-
           Database.query(
             conn,
             "SELECT state FROM root_effects WHERE ticket_id = ? AND attempt_id = ? AND operation = ? AND status IN ('pending', 'claimed', 'issued', 'unknown', 'reconciliation_required')",
             [operation["ticket_id"], operation["attempt_id"], operation["operation"]]
           ) do
      duplicate? =
        Enum.any?(rows, fn [bytes] ->
          case decode(bytes) do
            {:ok, state} ->
              state["role"] == role and state["phase_generation"] == phase_generation and
                state["operation_ordinal"] == ordinal

            _ ->
              true
          end
        end)

      if duplicate?, do: {:error, :duplicate_semantic_operation}, else: :ok
    else
      true -> {:error, :duplicate_request_identity}
      {:error, _reason} = error -> error
    end
  end

  defp assignment_id(ticket_id, attempt_id, role),
    do: Enum.join([ticket_id, attempt_id, role], ":")

  defp predecessor_guard(conn, operation, generation, ordinal, predecessor) do
    with {:ok, rows} <-
           Database.query(
             conn,
             "SELECT effect_id, state FROM root_effects WHERE ticket_id = ? AND attempt_id = ? AND operation = ? ORDER BY effect_id",
             [operation["ticket_id"], operation["attempt_id"], operation["operation"]]
           ),
         lineage <-
           Enum.flat_map(rows, fn [id, bytes] ->
             case decode(bytes) do
               {:ok, state} ->
                 if state["role"] == operation["request"]["role"], do: [{id, state}], else: []

               _ ->
                 []
             end
           end) do
      case lineage do
        [] ->
          if generation == 0 and ordinal == 0 and is_nil(predecessor),
            do: :ok,
            else: {:error, :predecessor_identity_mismatch}

        values ->
          {latest_id, latest} =
            Enum.max_by(values, fn {_id, state} -> state["operation_ordinal"] end)

          if predecessor == latest_id and generation == latest["phase_generation"] and
               ordinal == latest["operation_ordinal"] + 1 and
               latest["status"] in ~w(succeeded failed non_started cancelled) do
            :ok
          else
            {:error, :predecessor_not_terminal}
          end
      end
    end
  end

  defp predecessor_current?(conn, effect),
    do: predecessor_current?(conn, effect, MapSet.new([effect.effect_id]))

  defp predecessor_current?(
         _conn,
         %{operation_ordinal: 0, predecessor_effect_id: nil},
         _seen
       ),
       do: :ok

  defp predecessor_current?(conn, effect, seen) do
    with predecessor when is_binary(predecessor) <- effect.predecessor_effect_id,
         false <- MapSet.member?(seen, predecessor),
         {:ok, prior} <- load_effect(conn, predecessor),
         true <- prior.status in ~w(succeeded failed non_started cancelled),
         true <- prior.assignment_id == effect.assignment_id,
         true <- prior.phase_generation == effect.phase_generation,
         true <- prior.operation_ordinal + 1 == effect.operation_ordinal,
         :ok <- predecessor_current?(conn, prior, MapSet.put(seen, predecessor)) do
      :ok
    else
      _ -> {:error, :predecessor_not_terminal}
    end
  end

  defp reservation_dimensions(operation, reservations) do
    role = operation["request"]["role"]

    with {:ok, required} <- required_dimension(operation["operation"], role),
         true <- Enum.all?(reservations, &(&1.dimension == required)) do
      :ok
    else
      _ -> {:error, :operation_dimension_mismatch}
    end
  end

  defp required_dimension("launch", "pm"), do: {:ok, "starts.pm"}
  defp required_dimension("launch", "developer"), do: {:ok, "starts.developer"}
  defp required_dimension("launch", "reviewer"), do: {:ok, "starts.reviewer"}
  defp required_dimension("check", _role), do: {:ok, "starts.check"}
  defp required_dimension("build", _role), do: {:ok, "starts.build"}
  defp required_dimension("integration", _role), do: {:ok, "operations.integration"}
  defp required_dimension("activation", _role), do: {:ok, "operations.activation"}
  defp required_dimension("model_request", _role), do: {:ok, "model_requests"}
  defp required_dimension("validation", _role), do: {:ok, "validations"}
  defp required_dimension(_operation, _role), do: {:error, :operation_dimension_mismatch}

  # Lease requests are held in the effect's protected state until claim identity exists.
  defp insert_pending_leases(conn, effect_id, specs) do
    with {:ok, effect} <- load_effect(conn, effect_id),
         next <- Map.put(effect, :lease_specs, specs) do
      update_effect(conn, effect, next)
    end
  end

  defp insert_effect(conn, effect) do
    with {:ok, bytes} <- encode(public_effect(effect)) do
      Database.execute(
        conn,
        "INSERT INTO root_effects(effect_id, request_digest, policy_id, policy_revision, control_id, control_revision, operation, scope, ticket_id, attempt_id, execution_id, status, revision, state) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        [
          effect.effect_id,
          effect.request_digest,
          effect.policy_id,
          effect.policy_revision,
          effect.control_id,
          effect.control_revision,
          effect.operation,
          effect.scope,
          effect.ticket_id,
          effect.attempt_id,
          effect.execution_id,
          effect.status,
          effect.revision,
          {:blob, bytes}
        ]
      )
    end
  end

  defp load_effect(conn, id) do
    with {:ok, rows} <-
           Database.query(
             conn,
             "SELECT effect_id, request_digest, policy_id, policy_revision, control_id, control_revision, operation, scope, ticket_id, attempt_id, execution_id, status, revision, state FROM root_effects WHERE effect_id = ?",
             [id]
           ) do
      case rows do
        [] ->
          {:error, :not_found}

        [
          [
            effect_id,
            request_digest,
            policy_id,
            policy_revision,
            control_id,
            control_revision,
            operation,
            scope,
            ticket_id,
            attempt_id,
            execution_id,
            status,
            revision,
            bytes
          ]
        ] ->
          with {:ok, state} <- decode(bytes) do
            {:ok,
             %{
               effect_id: effect_id,
               request_digest: request_digest,
               policy_id: policy_id,
               policy_revision: policy_revision,
               control_id: control_id,
               control_revision: control_revision,
               operation: operation,
               scope: scope,
               ticket_id: ticket_id,
               attempt_id: attempt_id,
               execution_id: execution_id,
               assignment_id: state["assignment_id"],
               role: state["role"],
               phase_generation: state["phase_generation"],
               operation_ordinal: state["operation_ordinal"],
               predecessor_effect_id: state["predecessor_effect_id"],
               request_id: state["request_id"],
               issuer: state["issuer"],
               channel: state["channel"],
               profile: state["profile"],
               deadline: state["deadline"],
               status: status,
               revision: revision,
               reservation_ids: state["reservation_ids"] || [],
               lease_specs: state["lease_specs"] || []
             }}
          end

        _ ->
          {:error, :duplicate_protected_identity}
      end
    end
  end

  defp public_effect(effect) do
    %{
      "schema_version" => 1,
      "effect_id" => effect.effect_id,
      "request_digest" => effect.request_digest,
      "policy_id" => effect.policy_id,
      "policy_revision" => effect.policy_revision,
      "control_id" => effect.control_id,
      "control_revision" => effect.control_revision,
      "operation" => effect.operation,
      "scope" => effect.scope,
      "ticket_id" => effect.ticket_id,
      "attempt_id" => effect.attempt_id,
      "execution_id" => effect.execution_id,
      "assignment_id" => Map.get(effect, :assignment_id),
      "role" => Map.get(effect, :role),
      "phase_generation" => Map.get(effect, :phase_generation),
      "operation_ordinal" => Map.get(effect, :operation_ordinal),
      "predecessor_effect_id" => Map.get(effect, :predecessor_effect_id),
      "request_id" => Map.get(effect, :request_id),
      "issuer" => Map.get(effect, :issuer),
      "channel" => Map.get(effect, :channel),
      "profile" => Map.get(effect, :profile),
      "deadline" => Map.get(effect, :deadline),
      "status" => effect.status,
      "revision" => effect.revision,
      "reservation_ids" => Map.get(effect, :reservation_ids, []),
      "lease_specs" => Map.get(effect, :lease_specs, [])
    }
  end

  defp update_effect(conn, old, next) do
    with {:ok, bytes} <- encode(public_effect(next)),
         :ok <-
           Database.execute(
             conn,
             "UPDATE root_effects SET status = ?, revision = ?, state = ? WHERE effect_id = ? AND revision = ?",
             [next.status, next.revision, {:blob, bytes}, old.effect_id, old.revision]
           ) do
      :ok
    end
  end

  defp insert_claim(conn, claim) do
    with {:ok, bytes} <- encode(public_claim(claim)) do
      Database.execute(
        conn,
        "INSERT INTO root_claims(claim_id, effect_id, writer_epoch, status, revision, state) VALUES (?, ?, ?, ?, ?, ?)",
        [
          claim.claim_id,
          claim.effect_id,
          claim.writer_epoch,
          claim.status,
          claim.revision,
          {:blob, bytes}
        ]
      )
    end
  end

  defp load_claim(conn, id) do
    with {:ok, rows} <-
           Database.query(
             conn,
             "SELECT claim_id, effect_id, writer_epoch, status, revision FROM root_claims WHERE claim_id = ?",
             [id]
           ) do
      case rows do
        [] ->
          {:error, :not_found}

        [[claim_id, effect_id, epoch, status, revision]] ->
          {:ok,
           %{
             claim_id: claim_id,
             effect_id: effect_id,
             writer_epoch: epoch,
             status: status,
             revision: revision
           }}

        _ ->
          {:error, :duplicate_protected_identity}
      end
    end
  end

  defp public_claim(claim) do
    claim
    |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)
    |> Map.put("schema_version", 1)
  end

  defp update_claim(conn, old, next) do
    with {:ok, bytes} <- encode(public_claim(next)) do
      Database.execute(
        conn,
        "UPDATE root_claims SET writer_epoch = ?, status = ?, revision = ?, state = ? WHERE claim_id = ? AND revision = ?",
        [
          next.writer_epoch,
          next.status,
          next.revision,
          {:blob, bytes},
          old.claim_id,
          old.revision
        ]
      )
    end
  end

  defp bind_reservations_to_claim(conn, reservations, claim_id) do
    Enum.reduce_while(reservations, :ok, fn reservation, :ok ->
      next = %{reservation | claim_id: claim_id, revision: reservation.revision + 1}

      case update_reservation(conn, reservation, next) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp reservations_for_effect(conn, effect_id) do
    with {:ok, rows} <-
           Database.query(
             conn,
             "SELECT reservation_id, ledger_id, generation, dimension, owner_kind, owner_id, units, revision, status, claim_id FROM root_reservations WHERE owner_kind = 'effect' AND owner_id = ? ORDER BY reservation_id",
             [effect_id]
           ) do
      {:ok, Enum.map(rows, &reservation_from_row/1)}
    end
  end

  defp reservations_for_claim(conn, claim_id) do
    with {:ok, rows} <-
           Database.query(
             conn,
             "SELECT reservation_id, ledger_id, generation, dimension, owner_kind, owner_id, units, revision, status, claim_id FROM root_reservations WHERE claim_id = ? ORDER BY reservation_id",
             [claim_id]
           ) do
      {:ok, Enum.map(rows, &reservation_from_row/1)}
    end
  end

  defp update_reservation_statuses(conn, reservations, status) do
    Enum.reduce_while(reservations, :ok, fn reservation, :ok ->
      next = %{reservation | status: status, revision: reservation.revision + 1}

      case update_reservation(conn, reservation, next) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp materialize_leases(conn, effect_id, claim_id) do
    with {:ok, effect} <- load_effect(conn, effect_id) do
      Enum.reduce_while(effect.lease_specs, :ok, fn spec, :ok ->
        lease = %{
          lease_id: spec["lease_id"],
          claim_id: claim_id,
          resource_id: spec["resource_id"],
          status: "held",
          revision: 0
        }

        with {:ok, bytes} <- encode(public_lease(lease)),
             :ok <-
               Database.execute(
                 conn,
                 "INSERT INTO root_leases(lease_id, claim_id, resource_id, status, revision, state) VALUES (?, ?, ?, 'held', 0, ?)",
                 [lease.lease_id, claim_id, lease.resource_id, {:blob, bytes}]
               ) do
          {:cont, :ok}
        else
          {:error, _reason} = error -> {:halt, error}
        end
      end)
    end
  end

  defp public_lease(lease) do
    lease
    |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)
    |> Map.put("schema_version", 1)
  end

  defp receipt_digest(operation) do
    Encoding.semantic_digest("pramana-foundry-root-receipt-v1", %{
      "claim_id" => operation["claim_id"],
      "request_id" => operation["request_id"],
      "outcome" => operation["outcome"],
      "proof" => operation["proof"],
      "payload" => operation["payload"]
    })
  end

  defp receipt(operation, digest, claim_id) do
    %{
      receipt_id: operation["receipt_id"],
      claim_id: claim_id,
      request_id: operation["request_id"],
      outcome: operation["outcome"],
      receipt_digest: digest,
      proof: operation["proof"],
      payload: operation["payload"]
    }
  end

  defp public_receipt(receipt) do
    receipt
    |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)
    |> Map.put("schema_version", 1)
  end

  defp insert_receipt(conn, receipt) do
    with {:ok, bytes} <- encode(public_receipt(receipt)) do
      Database.execute(
        conn,
        "INSERT INTO root_receipts(receipt_id, claim_id, request_id, outcome, receipt_digest, state) VALUES (?, ?, ?, ?, ?, ?)",
        [
          receipt.receipt_id,
          receipt.claim_id,
          receipt.request_id,
          receipt.outcome,
          receipt.receipt_digest,
          {:blob, bytes}
        ]
      )
    end
  end

  defp receipts_for_claim(conn, claim_id) do
    receipt_rows(
      conn,
      "SELECT receipt_id, claim_id, request_id, outcome, receipt_digest, state FROM root_receipts WHERE claim_id = ? ORDER BY receipt_id",
      [claim_id]
    )
  end

  defp receipts_for_request(conn, request_id) do
    receipt_rows(
      conn,
      "SELECT receipt_id, claim_id, request_id, outcome, receipt_digest, state FROM root_receipts WHERE request_id = ? ORDER BY receipt_id",
      [request_id]
    )
  end

  defp receipts_for_id(conn, receipt_id) do
    receipt_rows(
      conn,
      "SELECT receipt_id, claim_id, request_id, outcome, receipt_digest, state FROM root_receipts WHERE receipt_id = ? ORDER BY receipt_id",
      [receipt_id]
    )
  end

  defp receipt_rows(conn, sql, parameters) do
    with {:ok, rows} <- Database.query(conn, sql, parameters) do
      Enum.reduce_while(rows, {:ok, []}, fn [id, claim, request, outcome, digest, bytes],
                                            {:ok, acc} ->
        case decode(bytes) do
          {:ok, state} ->
            value = %{
              receipt_id: id,
              claim_id: claim,
              request_id: request,
              outcome: outcome,
              receipt_digest: digest,
              proof: state["proof"],
              payload: state["payload"]
            }

            {:cont, {:ok, [value | acc]}}

          error ->
            {:halt, error}
        end
      end)
      |> then(fn
        {:ok, values} -> {:ok, Enum.reverse(values)}
        error -> error
      end)
    end
  end

  defp settlement_proof("non_started", "issuer_quiescent"), do: :ok
  defp settlement_proof("unknown", "outcome_unknown"), do: :ok
  defp settlement_proof(outcome, "delivered") when outcome in ~w(succeeded failed), do: :ok
  defp settlement_proof(_outcome, _proof), do: {:error, :invalid_receipt_proof}

  defp settle_reservations(_conn, _reservations, "unknown"), do: :ok

  defp settle_reservations(conn, reservations, outcome) do
    Enum.reduce_while(reservations, :ok, fn reservation, :ok ->
      with {:ok, ledger} <-
             load_existing_ledger(conn, reservation.ledger_id, reservation.generation),
           true <- reservation.status == "issued_unknown",
           {reservation_status, next_ledger} <-
             reservation_settlement(ledger, reservation, outcome),
           next_reservation <- %{
             reservation
             | status: reservation_status,
               revision: reservation.revision + 1
           },
           :ok <- update_reservation(conn, reservation, next_reservation),
           :ok <- update_ledger(conn, ledger, next_ledger) do
        {:cont, :ok}
      else
        {:error, _reason} = error -> {:halt, error}
        _ -> {:halt, {:error, :reservation_settlement_conflict}}
      end
    end)
  end

  defp reservation_settlement(ledger, reservation, outcome)
       when outcome in ~w(succeeded failed) do
    {"consumed",
     %{
       ledger
       | revision: ledger.revision + 1,
         held: ledger.held - reservation.units,
         consumed: ledger.consumed + reservation.units
     }}
  end

  defp reservation_settlement(ledger, reservation, "non_started") do
    target = if ledger.status == "open", do: "released", else: "retired"
    {target, release_hold(ledger, reservation.units)}
  end

  defp settle_leases(_conn, _claim_id, "unknown"), do: :ok
  defp settle_leases(conn, claim_id, _outcome), do: update_leases(conn, claim_id, "released")

  defp retain_leases(conn, claim_id),
    do: update_leases(conn, claim_id, "retained", ["held", "retained"])

  defp update_leases(
         conn,
         claim_id,
         status,
         from_statuses \\ ["held", "retained", "released"]
       ) do
    with {:ok, rows} <-
           Database.query(
             conn,
             "SELECT lease_id, claim_id, resource_id, status, revision FROM root_leases WHERE claim_id = ? ORDER BY lease_id",
             [claim_id]
           ) do
      Enum.reduce_while(rows, :ok, fn [id, claim, resource, old_status, revision], :ok ->
        if old_status not in from_statuses do
          {:cont, :ok}
        else
          next = %{
            lease_id: id,
            claim_id: claim,
            resource_id: resource,
            status: status,
            revision: revision + 1
          }

          with {:ok, bytes} <- encode(public_lease(next)),
               :ok <-
                 Database.execute(
                   conn,
                   "UPDATE root_leases SET status = ?, revision = ?, state = ? WHERE lease_id = ? AND revision = ?",
                   [status, revision + 1, {:blob, bytes}, id, revision]
                 ) do
            {:cont, :ok}
          else
            {:error, _reason} = error -> {:halt, error}
          end
        end
      end)
    end
  end

  defp ledger_facts_for_reservations(conn, reservations) do
    reservations
    |> Enum.map(&{&1.ledger_id, &1.generation})
    |> Enum.uniq()
    |> Enum.reduce_while({:ok, []}, fn {id, generation}, {:ok, acc} ->
      case load_existing_ledger(conn, id, generation) do
        {:ok, ledger} -> {:cont, {:ok, [public_ledger(ledger) | acc]}}
        error -> {:halt, error}
      end
    end)
    |> then(fn
      {:ok, ledgers} -> {:ok, Enum.reverse(ledgers)}
      error -> error
    end)
  end

  defp simple_fact(conn, table, column, id) do
    with {:ok, %{value: value, revision: revision}} <- load_simple(conn, table, column, id) do
      {:ok, %{"schema_version" => 1, column => id, "revision" => revision, "value" => value}}
    end
  end

  defp ledger_fact(conn, id, generation) do
    with {:ok, ledger} <- load_existing_ledger(conn, id, generation),
         {:ok, rows} <-
           Database.query(
             conn,
             "SELECT reservation_id, ledger_id, generation, dimension, owner_kind, owner_id, units, revision, status, claim_id FROM root_reservations WHERE ledger_id = ? AND generation = ? ORDER BY reservation_id",
             [id, generation]
           ) do
      {:ok,
       public_ledger(ledger)
       |> Map.put(
         "reservations",
         Enum.map(rows, &(reservation_from_row(&1) |> public_reservation()))
       )}
    end
  end

  defp effect_observation_page(conn, query) do
    with {:ok, request} <- normalize_effect_observation_request(query) do
      Database.transaction(conn, fn -> effect_observation_snapshot(conn, request) end)
    end
  end

  defp normalize_effect_observation_request(query) do
    with :ok <-
           exact_keys(query, ~w(schema_version type effect_id limit max_bytes cursor)),
         :ok <- bounded_observation_identity(query["effect_id"]),
         limit when is_integer(limit) and limit in 1..@effect_observation_max_items <-
           query["limit"],
         max_bytes
         when is_integer(max_bytes) and max_bytes >= @effect_observation_min_bytes and
                max_bytes <= @effect_observation_max_bytes <- query["max_bytes"],
         {:ok, cursor} <- normalize_effect_observation_cursor(query["cursor"]) do
      {:ok,
       %{
         effect_id: query["effect_id"],
         limit: limit,
         max_bytes: max_bytes,
         cursor: cursor
       }}
    else
      _ -> {:error, :invalid_protected_query}
    end
  end

  defp normalize_effect_observation_cursor(nil), do: {:ok, nil}

  defp normalize_effect_observation_cursor(cursor) do
    with {:ok, cursor} <- string_map(cursor),
         :ok <-
           exact_keys(
             cursor,
             ~w(schema_version query_type scope_digest source_digest protected_sequence effect_revision section offset)
           ),
         1 <- cursor["schema_version"],
         "effect_observation_page" <- cursor["query_type"],
         true <- digest_string?(cursor["scope_digest"]),
         true <- digest_string?(cursor["source_digest"]),
         sequence when is_integer(sequence) and sequence >= 0 <- cursor["protected_sequence"],
         revision when is_integer(revision) and revision >= 0 <- cursor["effect_revision"],
         section when section in @effect_observation_sections <- cursor["section"],
         offset
         when is_integer(offset) and offset >= 0 and
                offset <= @effect_observation_max_offset <- cursor["offset"] do
      {:ok, cursor}
    else
      _ -> {:error, :invalid_protected_query}
    end
  end

  defp effect_observation_snapshot(conn, request) do
    with {:ok, source} <- effect_observation_source(conn),
         {:ok, effect} <- bounded_effect_header(conn, request.effect_id),
         {:ok, scope_digest} <-
           Encoding.semantic_digest("pramana-foundry-effect-observation-scope-v1", %{
             "effect_id" => request.effect_id
           }),
         {:ok, source_digest} <-
           Encoding.semantic_digest("pramana-foundry-effect-observation-source-v1", %{
             "installation_id" => source["installation_id"],
             "repository_id" => source["repository_id"]
           }),
         :ok <-
           validate_effect_observation_cursor(
             request.cursor,
             scope_digest,
             source_digest,
             source["last_protected_command_sequence"],
             effect["revision"]
           ),
         {:ok, control} <- bounded_effect_control(conn, effect),
         {:ok, execution} <- bounded_effect_execution(conn, effect),
         {:ok, settlement} <- bounded_infrastructure_settlement(conn, effect),
         context <- %{
           source: Map.put(source, "effect_revision", effect["revision"]),
           effect: effect,
           control: control,
           execution: execution,
           settlement: settlement,
           scope_digest: scope_digest,
           source_digest: source_digest,
           protected_sequence: source["last_protected_command_sequence"],
           effect_revision: effect["revision"],
           limit: request.limit,
           max_bytes: request.max_bytes
         },
         {:ok, state} <- initial_effect_observation_state(context, request.cursor),
         {:ok, completed} <- read_effect_observation_sections(conn, context, state),
         response <- effect_observation_response(context, completed),
         true <- :erlang.external_size(response) <= context.max_bytes do
      {:ok, response}
    else
      false -> {:error, :protected_observation_oversized}
      error -> error
    end
  end

  # These summaries deliberately select only bounded scalar prefixes. In particular,
  # neither the control state nor inbox item blobs cross the SQLite boundary.
  defp bounded_effect_control(conn, effect) do
    columns = [
      {"control_id", :text},
      {"revision", :integer},
      {"json_extract(CAST(state AS TEXT), '$.value.status')", "status", :text}
    ]

    sql = "SELECT " <> bounded_select_list(columns) <> " FROM root_controls WHERE control_id = ?"

    with {:ok, rows} <- Database.query(conn, sql, [effect["control_id"]]),
         [row] <- rows,
         {:ok, control} <- decode_bounded_row(row, columns),
         true <- control["control_id"] == effect["control_id"],
         true <- nonnegative_integer?(control["revision"]),
         true <- control["status"] in ~w(active cancel_requested) do
      {:ok, Map.put(control, "schema_version", 1)}
    else
      {:error, _reason} = error -> error
      _ -> protected_observation_corrupt(effect["effect_id"])
    end
  end

  defp bounded_effect_execution(conn, effect) do
    columns = [
      {"i.execution_id", "execution_id", :text},
      {"i.revision", "revision", :integer},
      {"i.last_sequence", "last_sequence", :integer},
      {"coalesce(i.sealed_sequence, -1)", "sealed_sequence", :integer},
      {"coalesce((SELECT min(x.sequence) FROM authenticated_inbox_items x WHERE x.execution_id = i.execution_id AND x.disposition = 'accepted' AND x.item_kind = 'result'), -1)",
       "result_sequence", :integer},
      {"coalesce((SELECT min(x.sequence) FROM authenticated_inbox_items x WHERE x.execution_id = i.execution_id AND x.disposition = 'accepted' AND x.item_kind = 'exit'), -1)",
       "exit_sequence", :integer}
    ]

    sql =
      "SELECT " <>
        bounded_select_list(columns) <>
        " FROM authenticated_inboxes i WHERE i.execution_id = ?"

    with {:ok, rows} <- Database.query(conn, sql, [effect["execution_id"]]) do
      case rows do
        [] ->
          {:ok,
           %{
             "schema_version" => 1,
             "execution_id" => effect["execution_id"],
             "status" => "absent"
           }}

        [row] ->
          with {:ok, inbox} <- decode_bounded_row(row, columns),
               true <- inbox["execution_id"] == effect["execution_id"],
               true <- nonnegative_integer?(inbox["revision"]),
               true <- nonnegative_integer?(inbox["last_sequence"]),
               {:ok, summary} <- bounded_execution_summary(inbox) do
            {:ok, Map.merge(%{"schema_version" => 1}, summary)}
          else
            {:error, _reason} = error -> error
            _ -> protected_observation_corrupt(effect["effect_id"])
          end

        _ ->
          protected_observation_corrupt(effect["effect_id"])
      end
    end
  end

  defp bounded_execution_summary(%{"sealed_sequence" => -1} = inbox) do
    {:ok,
     inbox
     |> Map.take(~w(execution_id revision last_sequence))
     |> Map.put("sealed_sequence", nil)
     |> Map.put("status", "open")}
  end

  defp bounded_execution_summary(inbox) do
    sealed = inbox["sealed_sequence"]
    result = inbox["result_sequence"]
    exit = inbox["exit_sequence"]

    with true <- nonnegative_integer?(sealed) and sealed <= inbox["last_sequence"],
         true <- result == -1 or (is_integer(result) and result in 1..sealed),
         true <- exit == -1 or (is_integer(exit) and exit in 1..sealed) do
      {status, sequence} =
        cond do
          result != -1 -> {"result", result}
          exit != -1 -> {"exit", exit}
          true -> {"sealed_without_result_or_exit", nil}
        end

      summary =
        inbox
        |> Map.take(~w(execution_id revision last_sequence sealed_sequence))
        |> Map.put("status", status)

      {:ok, if(is_nil(sequence), do: summary, else: Map.put(summary, "sequence", sequence))}
    else
      _ -> protected_observation_corrupt(inbox["execution_id"])
    end
  end

  defp effect_observation_source(conn) do
    with {:ok, rows} <-
           Database.query(
             conn,
             "SELECT key, CAST(substr(CAST(value AS BLOB), 1, ? + 1) AS TEXT), length(CAST(value AS BLOB)) FROM metadata WHERE key IN ('installation_id', 'repository_id') ORDER BY key",
             [@effect_observation_max_scalar_bytes]
           ),
         {:ok, metadata} <- bounded_metadata(rows),
         {:ok, [[sequence]]} <-
           Database.query(conn, "SELECT coalesce(max(seq), 0) FROM root_commands"),
         true <- is_integer(sequence) and sequence >= 0 do
      {:ok,
       %{
         "installation_id" => metadata["installation_id"],
         "repository_id" => metadata["repository_id"],
         "last_protected_command_sequence" => sequence
       }}
    else
      {:error, _reason} = error -> error
      _ -> protected_observation_corrupt(:source)
    end
  end

  defp bounded_metadata(rows) when length(rows) == 2 do
    Enum.reduce_while(rows, {:ok, %{}}, fn
      [key, value, bytes], {:ok, acc} when key in ["installation_id", "repository_id"] ->
        case bounded_text_value(value, bytes, false) do
          {:ok, decoded} -> {:cont, {:ok, Map.put(acc, key, decoded)}}
          {:error, _reason} = error -> {:halt, error}
        end

      _row, _acc ->
        {:halt, protected_observation_corrupt(:source)}
    end)
    |> case do
      {:ok, %{"installation_id" => _, "repository_id" => _} = metadata} -> {:ok, metadata}
      {:ok, _metadata} -> protected_observation_corrupt(:source)
      error -> error
    end
  end

  defp bounded_metadata(_rows), do: protected_observation_corrupt(:source)

  defp bounded_effect_header(conn, effect_id) do
    columns = [
      {"effect_id", :text},
      {"ticket_id", :text},
      {"attempt_id", :text},
      {"execution_id", :text},
      {"control_id", :text},
      {"policy_id", :text},
      {"operation", :text},
      {"scope", :text},
      {"status", :text},
      {"revision", :integer},
      {"policy_revision", :integer},
      {"control_revision", :integer}
    ]

    sql =
      "SELECT " <> bounded_select_list(columns) <> " FROM root_effects WHERE effect_id = ?"

    with {:ok, rows} <- Database.query(conn, sql, [effect_id]) do
      case rows do
        [] ->
          {:error, :not_found}

        [row] ->
          with {:ok, effect} <- decode_bounded_row(row, columns),
               ^effect_id <- effect["effect_id"],
               true <-
                 effect["status"] in ~w(pending claimed issued unknown succeeded failed non_started cancelled reconciliation_required),
               true <- nonnegative_integer?(effect["revision"]),
               true <- nonnegative_integer?(effect["policy_revision"]),
               true <- nonnegative_integer?(effect["control_revision"]) do
            {:ok, Map.put(effect, "schema_version", 1)}
          else
            {:error, _reason} = error -> error
            _ -> protected_observation_corrupt(effect_id)
          end

        _ ->
          protected_observation_corrupt(effect_id)
      end
    end
  end

  defp bounded_infrastructure_settlement(conn, effect) do
    effect_id = effect["effect_id"]

    columns = [
      {"s.effect_id", "effect_id", :text},
      {"s.claim_id", "claim_id", :text},
      {"s.receipt_id", "receipt_id", :text},
      {"s.role", "role", :text},
      {"s.work_owner", "work_owner", :text},
      {"s.infrastructure_generation", "infrastructure_generation", :integer},
      {"s.predecessor_effect_id", "predecessor_effect_id", :nullable_text},
      {"s.failure_class", "failure_class", :text},
      {"s.ordinal", "ordinal", :integer},
      {"c.effect_id", "claim_effect_id", :text},
      {"c.status", "claim_status", :text},
      {"r.claim_id", "receipt_claim_id", :text},
      {"r.outcome", "receipt_outcome", :text},
      {"json_extract(CAST(e.state AS TEXT), '$.role')", "effect_role", :text},
      {"json_extract(CAST(e.state AS TEXT), '$.assignment_id')", "effect_work_owner", :text},
      {"json_extract(CAST(e.state AS TEXT), '$.phase_generation')", "effect_generation",
       :integer},
      {"json_extract(CAST(e.state AS TEXT), '$.predecessor_effect_id')", "effect_predecessor",
       :nullable_text},
      {"json_extract(CAST(r.state AS TEXT), '$.payload.failure_class')", "receipt_failure_class",
       :text}
    ]

    sql =
      "SELECT " <>
        bounded_select_list(columns) <>
        " FROM root_infrastructure_settlements s " <>
        "JOIN root_claims c ON c.claim_id = s.claim_id " <>
        "JOIN root_receipts r ON r.receipt_id = s.receipt_id " <>
        "JOIN root_effects e ON e.effect_id = s.effect_id " <>
        "WHERE s.effect_id = ?"

    with {:ok, rows} <- Database.query(conn, sql, [effect_id]),
         {:ok, required} <- required_infrastructure_settlement(conn, effect_id) do
      case {rows, required} do
        {[], nil} ->
          {:ok, nil}

        {[], required} when is_map(required) ->
          protected_observation_corrupt(effect_id)

        {[row], required} when is_map(required) ->
          with {:ok, value} <- decode_bounded_row(row, columns),
               ^effect_id <- value["effect_id"],
               ^effect_id <- value["claim_effect_id"],
               claim_id when is_binary(claim_id) <- value["claim_id"],
               ^claim_id <- value["receipt_claim_id"],
               true <- valid_settlement_current_status?(conn, effect, value),
               "non_started" <- value["receipt_outcome"],
               true <- value["role"] == value["effect_role"],
               true <- value["work_owner"] == value["effect_work_owner"],
               true <- value["infrastructure_generation"] == value["effect_generation"],
               true <- value["predecessor_effect_id"] == value["effect_predecessor"],
               true <- value["failure_class"] == value["receipt_failure_class"],
               true <- settlement_matches_required?(value, required),
               :ok <- validate_bounded_settlement_lineage(conn, value) do
            {:ok,
             value
             |> Map.drop(
               ~w(claim_effect_id claim_status receipt_claim_id receipt_outcome effect_role effect_work_owner effect_generation effect_predecessor receipt_failure_class)
             )
             |> Map.put("schema_version", 1)}
          else
            {:error, _reason} = error -> error
            _ -> protected_observation_corrupt(effect_id)
          end

        _ ->
          protected_observation_corrupt(effect_id)
      end
    end
  end

  defp required_infrastructure_settlement(conn, effect_id) do
    columns = [
      {"json_extract(CAST(d.result AS TEXT), '$.operation_result.facts.infrastructure_settlement.effect_id')",
       "effect_id", :text},
      {"json_extract(CAST(d.result AS TEXT), '$.operation_result.facts.infrastructure_settlement.claim_id')",
       "claim_id", :text},
      {"json_extract(CAST(d.result AS TEXT), '$.operation_result.facts.infrastructure_settlement.receipt_id')",
       "receipt_id", :text},
      {"json_extract(CAST(d.result AS TEXT), '$.operation_result.facts.infrastructure_settlement.role')",
       "role", :text},
      {"json_extract(CAST(d.result AS TEXT), '$.operation_result.facts.infrastructure_settlement.work_owner')",
       "work_owner", :text},
      {"json_extract(CAST(d.result AS TEXT), '$.operation_result.facts.infrastructure_settlement.infrastructure_generation')",
       "infrastructure_generation", :integer},
      {"json_extract(CAST(d.result AS TEXT), '$.operation_result.facts.infrastructure_settlement.predecessor_effect_id')",
       "predecessor_effect_id", :nullable_text},
      {"json_extract(CAST(d.result AS TEXT), '$.operation_result.facts.infrastructure_settlement.failure_class')",
       "failure_class", :text},
      {"json_extract(CAST(d.result AS TEXT), '$.operation_result.facts.infrastructure_settlement.ordinal')",
       "ordinal", :integer}
    ]

    sql =
      "SELECT " <>
        bounded_select_list(columns) <>
        " FROM durable_operations d " <>
        "JOIN atomic_bundles b ON b.command_id = d.owner_id " <>
        "WHERE d.owner_kind = 'bundle_v2' AND d.operation_kind = 'protected' " <>
        "AND d.operation_type = 'settle_claim' AND b.disposition = 'accepted' " <>
        "AND json_extract(CAST(d.request AS TEXT), '$.operation.outcome') = 'non_started' " <>
        "AND json_extract(CAST(d.result AS TEXT), '$.execution_status') = 'committed' " <>
        "AND json_extract(CAST(d.result AS TEXT), '$.operation_result.facts.effect.effect_id') = ?"

    case Database.query(conn, sql, [effect_id]) do
      {:ok, []} -> {:ok, nil}
      {:ok, [row]} -> decode_bounded_row(row, columns)
      {:error, _reason} = error -> error
      _ -> protected_observation_corrupt(effect_id)
    end
  end

  defp settlement_matches_required?(value, required) do
    Enum.all?(
      ~w(effect_id claim_id receipt_id role work_owner infrastructure_generation predecessor_effect_id failure_class ordinal),
      &(value[&1] == required[&1])
    )
  end

  defp validate_bounded_settlement_lineage(_conn, %{
         "predecessor_effect_id" => nil,
         "ordinal" => 1
       }),
       do: :ok

  defp validate_bounded_settlement_lineage(conn, value) do
    columns = [
      {"role", :text},
      {"work_owner", :text},
      {"infrastructure_generation", :integer},
      {"ordinal", :integer}
    ]

    sql =
      "SELECT " <>
        bounded_select_list(columns) <>
        " FROM root_infrastructure_settlements WHERE effect_id = ?"

    with predecessor when is_binary(predecessor) <- value["predecessor_effect_id"],
         {:ok, [row]} <- Database.query(conn, sql, [predecessor]),
         {:ok, prior} <- decode_bounded_row(row, columns),
         true <- prior["role"] == value["role"],
         true <- prior["work_owner"] == value["work_owner"],
         true <- prior["infrastructure_generation"] == value["infrastructure_generation"],
         true <- prior["ordinal"] + 1 == value["ordinal"] do
      :ok
    else
      _ -> protected_observation_corrupt(value["effect_id"])
    end
  end

  defp valid_settlement_current_status?(_conn, %{"status" => "non_started"}, %{
         "claim_status" => "non_started"
       }),
       do: true

  defp valid_settlement_current_status?(
         conn,
         %{"effect_id" => effect_id, "status" => "reconciliation_required"},
         %{
           "claim_id" => claim_id,
           "claim_status" => "reconciliation_required"
         }
       ) do
    sql =
      "SELECT count(*) FROM durable_operations d JOIN atomic_bundles b ON b.command_id = d.owner_id " <>
        "WHERE d.owner_kind = 'bundle_v2' AND d.operation_kind = 'protected' " <>
        "AND d.operation_type = 'settle_claim' AND b.disposition = 'quarantined' " <>
        "AND json_extract(CAST(d.result AS TEXT), '$.execution_status') = 'committed' " <>
        "AND json_extract(CAST(d.result AS TEXT), '$.operation_result.facts.effect.effect_id') = ? " <>
        "AND json_extract(CAST(d.result AS TEXT), '$.operation_result.facts.effect.status') = 'reconciliation_required' " <>
        "AND json_extract(CAST(d.result AS TEXT), '$.operation_result.facts.claim.claim_id') = ? " <>
        "AND json_extract(CAST(d.result AS TEXT), '$.operation_result.facts.claim.status') = 'reconciliation_required' " <>
        "AND json_extract(CAST(d.result AS TEXT), '$.operation_result.facts.attempted_receipt.outcome') <> 'non_started'"

    match?({:ok, [[count]]} when count > 0, Database.query(conn, sql, [effect_id, claim_id]))
  end

  defp valid_settlement_current_status?(_conn, _effect, _value), do: false

  defp validate_effect_observation_cursor(
         nil,
         _scope_digest,
         _source_digest,
         _sequence,
         _revision
       ),
       do: :ok

  defp validate_effect_observation_cursor(cursor, scope_digest, source_digest, sequence, revision) do
    cond do
      cursor["scope_digest"] != scope_digest -> {:error, :invalid_protected_query}
      cursor["source_digest"] != source_digest -> {:error, :stale_protected_cursor}
      cursor["protected_sequence"] != sequence -> {:error, :stale_protected_cursor}
      cursor["effect_revision"] != revision -> {:error, :stale_protected_cursor}
      true -> :ok
    end
  end

  defp initial_effect_observation_state(context, cursor) do
    {section, offset} =
      case cursor do
        nil -> {hd(@effect_observation_sections), 0}
        cursor -> {cursor["section"], cursor["offset"]}
      end

    state = %{
      section: section,
      offset: offset,
      relations: [],
      item_count: 0,
      truncated_reason: nil,
      receipts_complete: section in ~w(reservations leases)
    }

    if effect_observation_size(context, state, true) <= context.max_bytes,
      do: {:ok, state},
      else: {:error, :protected_observation_oversized}
  end

  defp read_effect_observation_sections(_conn, _context, %{truncated_reason: reason} = state)
       when not is_nil(reason),
       do: {:ok, state}

  defp read_effect_observation_sections(conn, context, state) do
    section_index = Enum.find_index(@effect_observation_sections, &(&1 == state.section))

    if is_nil(section_index) do
      {:error, :invalid_protected_query}
    else
      with {:ok, read} <- read_effect_observation_section(conn, context, state) do
        cond do
          not is_nil(read.truncated_reason) ->
            {:ok, read}

          section_index == length(@effect_observation_sections) - 1 ->
            {:ok, %{read | section: nil, offset: 0}}

          true ->
            next_section = Enum.at(@effect_observation_sections, section_index + 1)

            read_effect_observation_sections(conn, context, %{
              read
              | section: next_section,
                offset: 0,
                receipts_complete: read.receipts_complete or state.section == "receipts"
            })
        end
      end
    end
  end

  defp read_effect_observation_section(conn, context, state) do
    remaining = context.limit - state.item_count
    {sql, parameters, columns, kind} = observation_section_query(state.section, context.effect)
    params = parameters ++ [remaining + 1, state.offset]

    Database.fold(conn, sql, params, state, fn row, acc ->
      cond do
        acc.item_count >= context.limit ->
          {:halt, {:ok, %{acc | truncated_reason: "item_limit"}}}

        true ->
          case decode_bounded_row(row, columns) do
            {:ok, decoded} ->
              relation = decoded |> Map.put("schema_version", 1) |> Map.put("kind", kind)

              if valid_effect_observation_relation?(relation, context.effect["effect_id"]) do
                candidate = %{
                  acc
                  | relations: acc.relations ++ [relation],
                    item_count: acc.item_count + 1,
                    offset: acc.offset + 1
                }

                if effect_observation_size(context, candidate, true) <= context.max_bytes do
                  {:cont, candidate}
                else
                  {:halt,
                   {:ok,
                    %{
                      acc
                      | truncated_reason:
                          if(acc.item_count == 0, do: "oversized_row", else: "byte_limit")
                    }}}
                end
              else
                {:halt, protected_observation_corrupt(context.effect["effect_id"])}
              end

            {:error, _reason} = error ->
              {:halt, error}
          end
      end
    end)
    |> case do
      {:ok, %{truncated_reason: "oversized_row", item_count: 0}} ->
        {:error, :protected_observation_oversized}

      other ->
        other
    end
  end

  defp observation_section_query("claims", effect) do
    columns = [
      {"claim_id", :text},
      {"effect_id", :text},
      {"writer_epoch", :text},
      {"status", :text},
      {"revision", :integer}
    ]

    {"SELECT " <>
       bounded_select_list(columns) <>
       " FROM root_claims WHERE effect_id = ? ORDER BY claim_id LIMIT ? OFFSET ?",
     [effect["effect_id"]], columns, "claim"}
  end

  defp observation_section_query("receipts", effect) do
    columns = [
      {"r.receipt_id", "receipt_id", :text},
      {"r.claim_id", "claim_id", :text},
      {"r.request_id", "request_id", :text},
      {"r.outcome", "outcome", :text},
      {"r.receipt_digest", "receipt_digest", :text}
    ]

    {"SELECT " <>
       bounded_select_list(columns) <>
       " FROM root_receipts r JOIN root_claims c ON c.claim_id = r.claim_id " <>
       "WHERE c.effect_id = ? ORDER BY r.claim_id, r.receipt_id LIMIT ? OFFSET ?",
     [effect["effect_id"]], columns, "receipt"}
  end

  defp observation_section_query("reservations", effect) do
    columns = [
      {"reservation_id", :text},
      {"ledger_id", :text},
      {"generation", :integer},
      {"dimension", :text},
      {"owner_kind", :text},
      {"owner_id", :text},
      {"units", :integer},
      {"revision", :integer},
      {"status", :text},
      {"claim_id", :nullable_text}
    ]

    {"SELECT " <>
       bounded_select_list(columns) <>
       " FROM root_reservations WHERE owner_kind = 'effect' AND owner_id = ? " <>
       "ORDER BY reservation_id LIMIT ? OFFSET ?", [effect["effect_id"]], columns, "reservation"}
  end

  defp observation_section_query("leases", effect) do
    columns = [
      {"l.lease_id", "lease_id", :text},
      {"l.claim_id", "claim_id", :text},
      {"l.resource_id", "resource_id", :text},
      {"l.status", "status", :text},
      {"l.revision", "revision", :integer}
    ]

    {"SELECT " <>
       bounded_select_list(columns) <>
       " FROM root_leases l JOIN root_claims c ON c.claim_id = l.claim_id " <>
       "WHERE c.effect_id = ? ORDER BY l.claim_id, l.lease_id LIMIT ? OFFSET ?",
     [effect["effect_id"]], columns, "lease"}
  end

  defp valid_effect_observation_relation?(%{"kind" => "claim"} = relation, effect_id) do
    relation["effect_id"] == effect_id and nonempty_text?(relation["claim_id"]) and
      nonempty_text?(relation["writer_epoch"]) and
      relation["status"] in ~w(claimed issued unknown succeeded failed non_started cancelled reconciliation_required) and
      nonnegative_integer?(relation["revision"])
  end

  defp valid_effect_observation_relation?(%{"kind" => "receipt"} = relation, _effect_id) do
    Enum.all?(
      ~w(receipt_id claim_id request_id receipt_digest),
      &nonempty_text?(relation[&1])
    ) and relation["outcome"] in ~w(succeeded failed non_started unknown)
  end

  defp valid_effect_observation_relation?(%{"kind" => "reservation"} = relation, effect_id) do
    nonempty_text?(relation["reservation_id"]) and nonempty_text?(relation["ledger_id"]) and
      nonnegative_integer?(relation["generation"]) and nonempty_text?(relation["dimension"]) and
      relation["owner_kind"] == "effect" and relation["owner_id"] == effect_id and
      is_integer(relation["units"]) and relation["units"] > 0 and
      nonnegative_integer?(relation["revision"]) and
      relation["status"] in ~w(proposed reserved issued_unknown consumed released retired) and
      (is_nil(relation["claim_id"]) or nonempty_text?(relation["claim_id"]))
  end

  defp valid_effect_observation_relation?(%{"kind" => "lease"} = relation, _effect_id) do
    nonempty_text?(relation["lease_id"]) and nonempty_text?(relation["claim_id"]) and
      nonempty_text?(relation["resource_id"]) and
      relation["status"] in ~w(held released retained) and
      nonnegative_integer?(relation["revision"])
  end

  defp valid_effect_observation_relation?(_relation, _effect_id), do: false

  defp effect_observation_response(context, state) do
    next_cursor =
      if is_nil(state.section) do
        nil
      else
        effect_observation_cursor(context, state.section, state.offset)
      end

    response = %{
      "schema_version" => 1,
      "type" => "effect_observation_page",
      "source" => context.source,
      "effect" => context.effect,
      "control" => context.control,
      "execution" => context.execution,
      "relations" => state.relations,
      "infrastructure_settlement" => context.settlement,
      "settlement" => %{
        "schema_version" => 1,
        "status" => context.effect["status"],
        "receipt_history" => if(state.receipts_complete, do: "complete", else: "unknown")
      },
      "page" => %{
        "item_count" => state.item_count,
        "size_bytes" => 0,
        "truncated" => not is_nil(next_cursor),
        "truncated_reason" => state.truncated_reason,
        "next_cursor" => next_cursor
      }
    }

    put_effect_observation_size(response)
  end

  defp effect_observation_size(context, state, assume_truncated?) do
    section = state.section || List.last(@effect_observation_sections)

    provisional = %{
      state
      | section: if(assume_truncated?, do: section, else: state.section),
        truncated_reason: state.truncated_reason || if(assume_truncated?, do: "byte_limit")
    }

    context
    |> effect_observation_response(provisional)
    |> :erlang.external_size()
  end

  defp put_effect_observation_size(response) do
    sized = put_in(response, ["page", "size_bytes"], :erlang.external_size(response))
    stabilize_effect_observation_size(sized)
  end

  defp stabilize_effect_observation_size(response) do
    size = :erlang.external_size(response)

    if response["page"]["size_bytes"] == size,
      do: response,
      else:
        response |> put_in(["page", "size_bytes"], size) |> stabilize_effect_observation_size()
  end

  defp effect_observation_cursor(context, section, offset) do
    %{
      "schema_version" => 1,
      "query_type" => "effect_observation_page",
      "scope_digest" => context.scope_digest,
      "source_digest" => context.source_digest,
      "protected_sequence" => context.protected_sequence,
      "effect_revision" => context.effect_revision,
      "section" => section,
      "offset" => offset
    }
  end

  defp bounded_select_list(columns) do
    columns
    |> Enum.flat_map(fn
      {column, :text} -> bounded_text_select(column)
      {column, :nullable_text} -> bounded_text_select(column)
      {column, :integer} -> [column]
      {column, _key, :text} -> bounded_text_select(column)
      {column, _key, :nullable_text} -> bounded_text_select(column)
      {column, _key, :integer} -> [column]
    end)
    |> Enum.join(", ")
  end

  defp bounded_text_select(column) do
    [
      "CAST(substr(CAST(#{column} AS BLOB), 1, #{@effect_observation_max_scalar_bytes + 1}) AS TEXT)",
      "length(CAST(#{column} AS BLOB))"
    ]
  end

  defp decode_bounded_row(row, columns), do: decode_bounded_row(row, columns, %{})

  defp decode_bounded_row([], [], acc), do: {:ok, acc}

  defp decode_bounded_row([value, bytes | rest], [column | columns], acc)
       when elem(column, tuple_size(column) - 1) in [:text, :nullable_text] do
    {key, kind} = bounded_column_key_kind(column)

    case bounded_text_value(value, bytes, kind == :nullable_text) do
      {:ok, decoded} -> decode_bounded_row(rest, columns, Map.put(acc, key, decoded))
      {:error, _reason} = error -> error
    end
  end

  defp decode_bounded_row([value | rest], [column | columns], acc) do
    {key, :integer} = bounded_column_key_kind(column)

    if is_integer(value) do
      decode_bounded_row(rest, columns, Map.put(acc, key, value))
    else
      protected_observation_corrupt(key)
    end
  end

  defp decode_bounded_row(_row, _columns, _acc), do: protected_observation_corrupt(:row_shape)

  defp bounded_column_key_kind({column, kind}), do: {List.last(String.split(column, ".")), kind}
  defp bounded_column_key_kind({_column, key, kind}), do: {key, kind}

  defp bounded_text_value(nil, nil, true), do: {:ok, nil}

  defp bounded_text_value(value, bytes, _nullable?)
       when is_binary(value) and is_integer(bytes) and bytes >= 0 do
    cond do
      bytes > @effect_observation_max_scalar_bytes ->
        {:error, :protected_observation_oversized}

      bytes == 0 ->
        protected_observation_corrupt(:empty_scalar)

      byte_size(value) != bytes or not String.valid?(value) ->
        protected_observation_corrupt(:invalid_scalar)

      true ->
        {:ok, value}
    end
  end

  defp bounded_text_value(_value, _bytes, _nullable?),
    do: protected_observation_corrupt(:invalid_scalar)

  defp bounded_observation_identity(value) do
    with :ok <- identity(value),
         true <- byte_size(value) <= @effect_observation_max_scalar_bytes do
      :ok
    else
      _ -> {:error, :invalid_identity}
    end
  end

  defp digest_string?(value),
    do: is_binary(value) and byte_size(value) == 64 and String.match?(value, ~r/\A[0-9a-f]+\z/)

  defp nonempty_text?(value), do: is_binary(value) and value != "" and String.valid?(value)

  defp protected_observation_corrupt(identity),
    do: {:error, {:protected_corrupt, "effect_observation_page", identity}}

  defp effect_fact(conn, id) do
    with {:ok, effect} <- load_effect(conn, id),
         {:ok, claims} <-
           Database.query(
             conn,
             "SELECT claim_id FROM root_claims WHERE effect_id = ? ORDER BY claim_id",
             [id]
           ),
         {:ok, reservations} <- reservations_for_effect(conn, id) do
      claim_facts =
        Enum.map(claims, fn [claim_id] ->
          {:ok, claim} = load_claim(conn, claim_id)
          {:ok, receipts} = receipts_for_claim(conn, claim_id)

          public_claim(claim)
          |> Map.put("receipts", Enum.map(receipts, &public_receipt/1))
        end)

      {:ok,
       public_effect(effect)
       |> Map.put("claims", claim_facts)
       |> Map.put("reservations", Enum.map(reservations, &public_reservation/1))}
    end
  end

  defp claim_fact(conn, id) do
    with {:ok, claim} <- load_claim(conn, id),
         {:ok, receipts} <- receipts_for_claim(conn, id),
         {:ok, reservations} <- reservations_for_claim(conn, id),
         {:ok, leases} <-
           protected_rows(
             conn,
             "SELECT state FROM root_leases WHERE claim_id = ? ORDER BY lease_id",
             [id]
           ) do
      {:ok,
       public_claim(claim)
       |> Map.put("receipts", Enum.map(receipts, &public_receipt/1))
       |> Map.put("reservations", Enum.map(reservations, &public_reservation/1))
       |> Map.put("leases", leases)}
    end
  end

  defp reservation_fact(conn, id) do
    with {:ok, reservation} <- load_reservation(conn, id) do
      {:ok, public_reservation(reservation)}
    end
  end

  defp receipt_fact(conn, id) do
    protected_row(conn, "SELECT state FROM root_receipts WHERE receipt_id = ?", [id])
  end

  defp lease_fact(conn, id) do
    protected_row(conn, "SELECT state FROM root_leases WHERE lease_id = ?", [id])
  end

  defp protected_row(conn, sql, parameters) do
    with {:ok, rows} <- protected_rows(conn, sql, parameters) do
      case rows do
        [row] -> {:ok, row}
        [] -> {:error, :not_found}
        _ -> {:error, :duplicate_protected_identity}
      end
    end
  end

  defp protected_rows(conn, sql, parameters) do
    with {:ok, rows} <- Database.query(conn, sql, parameters) do
      Enum.reduce_while(rows, {:ok, []}, fn
        [bytes], {:ok, acc} ->
          case decode(bytes) do
            {:ok, value} -> {:cont, {:ok, [value | acc]}}
            {:error, _reason} = error -> {:halt, error}
          end

        _row, _acc ->
          {:halt, {:error, :corrupt_protected_row}}
      end)
      |> then(fn
        {:ok, values} -> {:ok, Enum.reverse(values)}
        error -> error
      end)
    end
  end

  defp revision_frontiers(conn) do
    sources = [
      {"inbox", "authenticated_inboxes"},
      {"policy", "root_policies"},
      {"control", "root_controls"},
      {"ledger", "root_ledgers"},
      {"reservation", "root_reservations"},
      {"effect", "root_effects"},
      {"claim", "root_claims"},
      {"lease", "root_leases"}
    ]

    Enum.reduce_while(sources, {:ok, %{}}, fn {name, table}, {:ok, acc} ->
      case Database.query(conn, "SELECT coalesce(max(revision), -1) FROM #{table}") do
        {:ok, [[revision]]} -> {:cont, {:ok, Map.put(acc, name, revision)}}
        {:error, _reason} = error -> {:halt, error}
        _ -> {:halt, {:error, :corrupt_revision_frontier}}
      end
    end)
  end

  defp command_fact(conn, id) do
    with {:ok, rows} <-
           Database.query(conn, "SELECT result FROM root_commands WHERE command_id = ?", [id]) do
      case rows do
        [[bytes]] -> decode(bytes)
        [] -> {:error, :not_found}
        _ -> {:error, :duplicate_protected_identity}
      end
    end
  end

  defp pointer_fact(conn, kind)
       when kind in ["accepted_source", "selected_deployment", "healthy_build"] do
    with {:ok, rows} <-
           Database.query(
             conn,
             "SELECT pointer_kind, producer_status, revision, state FROM root_pointers WHERE pointer_kind = ?",
             [kind]
           ) do
      case rows do
        [[^kind, status, revision, bytes]] ->
          with {:ok, state} <- decode(bytes),
               true <- state["producer_status"] == status and state["revision"] == revision do
            {:ok, state}
          else
            _ -> {:error, :corrupt_root_pointer}
          end

        [] ->
          {:error, :root_pointer_missing}

        _ ->
          {:error, :duplicate_protected_identity}
      end
    end
  end

  defp pointer_fact(_conn, _kind), do: {:error, :unsupported_root_pointer}

  defp all_pointer_facts(conn) do
    Enum.reduce_while(
      ~w(accepted_source selected_deployment healthy_build),
      {:ok, %{}},
      fn kind, {:ok, acc} ->
        case pointer_fact(conn, kind) do
          {:ok, fact} -> {:cont, {:ok, Map.put(acc, kind, fact)}}
          {:error, _reason} = error -> {:halt, error}
        end
      end
    )
  end

  defp validate_root_commands(conn) do
    with {:ok, rows} <-
           Database.query(
             conn,
             "SELECT seq, command_id, actor_id, request_digest, canonical_request, operation, disposition, reason_code, result FROM root_commands ORDER BY seq"
           ) do
      Enum.reduce_while(rows, :ok, fn
        [
          sequence,
          command_id,
          actor_id,
          digest,
          request_bytes,
          operation,
          disposition,
          reason,
          result_bytes
        ],
        :ok ->
          with {:ok, request_envelope} <- decode(request_bytes),
               ^actor_id <- request_envelope["actor_id"],
               %{"command_id" => ^command_id, "operation" => %{"type" => ^operation}} = request <-
                 request_envelope["request"],
               {:ok, ^digest} <- request_digest(actor_id, request),
               {:ok, result} <- decode(result_bytes),
               ^command_id <- result["command_id"],
               ^sequence <- result["command_sequence"],
               ^disposition <- result["disposition"],
               ^reason <- result["reason_code"] do
            {:cont, :ok}
          else
            _ -> {:halt, {:error, {:protected_corrupt, "root_commands", command_id}}}
          end
      end)
    end
  end

  defp validate_simple_history(conn) do
    Enum.reduce_while(
      [
        {"root_policies", "root_policy_history", "policy_id"},
        {"root_controls", "root_control_history", "control_id"}
      ],
      :ok,
      fn {head_table, history_table, id_column}, :ok ->
        sql =
          "SELECT h.#{id_column}, h.revision, h.prior_revision, h.command_id, h.state, c.canonical_request, c.result FROM #{history_table} h JOIN root_commands c ON c.command_id = h.command_id ORDER BY h.#{id_column}, h.revision"

        case Database.query(conn, sql) do
          {:ok, rows} ->
            with :ok <- validate_history_rows(rows, id_column, history_table),
                 {:ok, heads} <-
                   Database.query(
                     conn,
                     "SELECT #{id_column}, revision, state FROM #{head_table} ORDER BY #{id_column}"
                   ),
                 true <-
                   history_heads(rows) ==
                     Map.new(heads, fn [id, rev, state] -> {id, {rev, state}} end) do
              {:cont, :ok}
            else
              _ -> {:halt, {:error, {:protected_corrupt, history_table, :lineage}}}
            end

          {:error, _reason} = error ->
            {:halt, error}
        end
      end
    )
  end

  defp validate_history_rows(rows, id_column, _table) do
    type = if id_column == "policy_id", do: "set_policy", else: "set_control"

    Enum.reduce_while(rows, {:ok, %{}}, fn
      [id, revision, prior, command_id, state_bytes, request_bytes, result_bytes], {:ok, seen} ->
        expected_revision = Map.get(seen, id, 0)

        with true <- revision == expected_revision,
             true <- (revision == 0 and is_nil(prior)) or prior == revision - 1,
             {:ok, state} <- decode(state_bytes),
             true <- state[id_column] == id and state["revision"] == revision,
             {:ok, envelope} <- decode(request_bytes),
             %{"request" => request} <- envelope,
             %{"command_id" => ^command_id, "operation" => operation} <- request,
             ^type <- operation["type"],
             ^id <- operation[id_column],
             true <- operation["value"] == state["value"],
             {:ok, result} <- decode(result_bytes),
             "accepted" <- result["disposition"] do
          {:cont, {:ok, Map.put(seen, id, revision + 1)}}
        else
          _ -> {:halt, {:error, :invalid_history_provenance}}
        end
    end)
    |> case do
      {:ok, _seen} -> :ok
      error -> error
    end
  end

  defp history_heads(rows) do
    Enum.reduce(rows, %{}, fn [id, revision, _prior, _command, state | _], acc ->
      Map.put(acc, id, {revision, state})
    end)
  end

  defp validate_root_pointers(conn) do
    expected =
      MapSet.new(~w(accepted_source selected_deployment healthy_build), fn kind ->
        {kind, "absent", 0,
         %{
           "schema_version" => 1,
           "pointer_kind" => kind,
           "producer_status" => "absent",
           "revision" => 0,
           "value" => nil
         }}
      end)

    with {:ok, rows} <-
           Database.query(
             conn,
             "SELECT pointer_kind, producer_status, revision, state FROM root_pointers ORDER BY pointer_kind"
           ) do
      actual =
        Enum.reduce_while(rows, {:ok, MapSet.new()}, fn [kind, status, revision, bytes],
                                                        {:ok, acc} ->
          case decode(bytes) do
            {:ok, state} -> {:cont, {:ok, MapSet.put(acc, {kind, status, revision, state})}}
            _ -> {:halt, {:error, :invalid_pointer}}
          end
        end)

      case actual do
        {:ok, ^expected} -> :ok
        _ -> {:error, {:protected_corrupt, "root_pointers", :unauthorized_producer}}
      end
    end
  end

  defp validate_blob_rows(conn, table, column) do
    with {:ok, rows} <- Database.query(conn, "SELECT #{column} FROM #{table}") do
      Enum.reduce_while(rows, :ok, fn [bytes], :ok ->
        case decode(bytes) do
          {:ok, value} ->
            case encode(value) do
              {:ok, ^bytes} -> {:cont, :ok}
              _ -> {:halt, {:error, {:protected_corrupt, table, :noncanonical_blob}}}
            end

          _ ->
            {:halt, {:error, {:protected_corrupt, table, :invalid_blob}}}
        end
      end)
    end
  end

  defp validate_atomic_bundle_rows(conn) do
    with {:ok, bundles} <-
           Database.query(
             conn,
             "SELECT b.command_id, b.actor_id, b.request_digest, b.schema_version, b.disposition, b.reason_code, b.canonical_envelope, b.result, c.actor_id, c.request_digest, i.canonical_request, r.result " <>
               "FROM atomic_bundles b JOIN commands c ON c.command_id = b.command_id JOIN inputs i ON i.input_id = c.input_id JOIN command_results r ON r.command_id = c.command_id ORDER BY b.command_id"
           ),
         :ok <- validate_bundles(conn, bundles),
         {:ok, operations} <-
           Database.query(
             conn,
             "SELECT owner_kind, owner_id, ordinal, operation_kind, operation_type, request, result FROM durable_operations ORDER BY owner_kind, owner_id, ordinal"
           ),
         :ok <- validate_durable_operations(conn, operations),
         {:ok, settlements} <-
           Database.query(
             conn,
             "SELECT effect_id, claim_id, receipt_id, role, work_owner, infrastructure_generation, predecessor_effect_id, failure_class, ordinal, state FROM root_infrastructure_settlements ORDER BY effect_id"
           ) do
      validate_infrastructure_settlements(conn, settlements)
    end
  end

  # A closure row's columns must agree with the fact it stores.
  defp validate_attempt_closures(conn) do
    with {:ok, rows} <-
           Database.query(
             conn,
             "SELECT ticket_id, attempt_id, scope, state FROM root_attempt_closures"
           ) do
      Enum.reduce_while(rows, :ok, fn [ticket_id, attempt_id, scope, bytes], :ok ->
        case decode(bytes) do
          {:ok,
           %{
             "ticket_id" => ^ticket_id,
             "attempt_id" => ^attempt_id,
             "scope" => ^scope,
             "schema_version" => 1
           }} ->
            {:cont, :ok}

          _ ->
            {:halt, {:error, {:protected_corrupt, "root_attempt_closures", ticket_id}}}
        end
      end)
    end
  end

  defp validate_bundles(conn, rows) do
    Enum.reduce_while(rows, :ok, fn
      [
        id,
        actor,
        digest,
        2,
        disposition,
        reason,
        envelope_bytes,
        result_bytes,
        domain_actor,
        domain_digest,
        domain_request_bytes,
        domain_result_bytes
      ],
      :ok ->
        with {:ok, envelope} <- decode(envelope_bytes),
             true <- is_map(envelope),
             true <- is_map(envelope["command"]),
             2 <- envelope["schema_version"],
             ^id <- get_in(envelope, ["command", "command_id"]),
             ^actor <- envelope["actor_id"],
             ^actor <- domain_actor,
             {:ok, ^digest} <-
               Encoding.semantic_digest("pramana-foundry-atomic-bundle-v2", envelope),
             {:ok, domain_request} <- decode(domain_request_bytes),
             true <- is_map(domain_request),
             ^actor <- domain_request["actor_id"],
             true <- domain_request["command"] == envelope["command"],
             {:ok, expected_domain_bytes} <- Encoding.canonical(domain_request),
             true <- Encoding.digest(expected_domain_bytes) == domain_digest,
             {:ok, result} <- decode(result_bytes),
             true <- is_map(result),
             true <-
               Map.keys(result) |> Enum.sort() ==
                 ~w(command_id committed_seq disposition domain_result operations reason_code schema_version selected_discriminator),
             {:ok, domain_result} <- decode(domain_result_bytes),
             true <- is_map(domain_result),
             ^id <- result["command_id"],
             ^disposition <- result["disposition"],
             ^reason <- result["reason_code"],
             true <- result["domain_result"] == domain_result,
             :ok <- validate_bundle_operations(conn, id, envelope, result) do
          {:cont, :ok}
        else
          _ -> {:halt, {:error, {:protected_corrupt, "atomic_bundles", id}}}
        end

      row, :ok ->
        {:halt, {:error, {:protected_corrupt, "atomic_bundles", inspect(row)}}}
    end)
  end

  defp validate_bundle_operations(conn, command_id, envelope, result) do
    with {:ok, rows} <-
           Database.query(
             conn,
             "SELECT ordinal, operation_kind, operation_type, request, result FROM durable_operations WHERE owner_kind = 'bundle_v2' AND owner_id = ? ORDER BY ordinal",
             [command_id]
           ),
         operations when is_list(operations) <- envelope["operations"],
         operation_results when is_list(operation_results) <- result["operations"],
         true <- length(operation_results) == length(operations),
         expected_count <- length(operations) + 1,
         true <- length(rows) == expected_count,
         true <- row_ordinals(rows) == Enum.to_list(0..(expected_count - 1)//1),
         {protected_rows, [domain_row]} <- Enum.split(rows, expected_count - 1),
         {:ok, digest} <-
           Encoding.semantic_digest("pramana-foundry-atomic-bundle-v2", envelope),
         true <-
           Enum.zip([operations, operation_results, protected_rows])
           |> Enum.all?(fn tuple ->
             valid_bundle_protected_row?(conn, digest, result, tuple)
           end),
         true <- valid_bundle_domain_row?(domain_row, envelope, result),
         true <- valid_bundle_plan_binding?(conn, envelope, result) do
      :ok
    else
      _ -> {:error, :invalid_bundle_operation_binding}
    end
  end

  # Revalidates a plan-bound commit by reconstructing it.
  #
  # Comparing events alone is sufficient, but only because Authority's content validation
  # runs ahead of this in the same read: projection_matches_event?/2 ties each stored
  # projection to its carrier event's payload, and validate_reconstruction/2 rebuilds all
  # projections from events and compares. Pinning the events therefore pins the
  # projections transitively. If those checks were ever reordered after this one, a
  # projection comparison would have to be added here. Re-running the binding against
  # the original plan, the recorded discriminator and the persisted protected outcomes
  # must reproduce the committed events exactly. That proves those events could only have
  # come from that plan, those results and that discriminator, and it subsumes field-level
  # comparison rather than enumerating checks that need extending whenever a slot is added.
  #
  # The recorded discriminator is reconstructed from retained policy history, not trusted.
  # Trusting it left a hole: a store whose discriminator, events and projection were all
  # tampered coherently revalidated as valid, because the recorded value was the only free
  # input and nothing else read it. Recomputation uses
  # infrastructure_discriminator_at_revision/3, which reads the policy at the effect's
  # recorded revision rather than the head row, so a later policy revision does not turn a
  # valid historical commit into a corruption report.
  defp valid_bundle_plan_binding?(conn, envelope, result) do
    case envelope["plan"] do
      nil -> true
      plan -> valid_plan_binding?(conn, plan, envelope, result)
    end
  end

  # A bundle that committed no domain carriers has no binding to revalidate.
  defp valid_plan_binding?(_conn, _plan, _envelope, %{"disposition" => disposition})
       when disposition != "accepted",
       do: true

  defp valid_plan_binding?(conn, plan, envelope, result) do
    with discriminator when is_binary(discriminator) <- result["selected_discriminator"],
         staged when is_list(staged) <- result["operations"],
         :ok <- recorded_discriminator_reconstructs?(conn, plan, staged, discriminator),
         {:ok, proposal} <- TransitionPlan.bind(plan, discriminator, staged),
         {:ok, committed} <- committed_bundle_events(conn, envelope["command"]["command_id"]) do
      proposal["events"] == committed
    else
      _ -> false
    end
  end

  # An unconditional plan has one alternative and derives nothing, so the only value that
  # reconstructs is "unconditional" itself.
  defp recorded_discriminator_reconstructs?(
         _conn,
         %{"discriminator_kind" => "unconditional_v1"},
         _staged,
         recorded
       ) do
    if recorded == "unconditional",
      do: :ok,
      else: {:error, :discriminator_does_not_reconstruct}
  end

  defp recorded_discriminator_reconstructs?(conn, plan, staged, recorded) do
    with {:ok, settlement} <- bound_settlement_fact(plan, staged),
         {:ok, ^recorded} <-
           infrastructure_discriminator_at_revision(conn, settlement["effect_id"], settlement) do
      :ok
    else
      _ -> {:error, :discriminator_does_not_reconstruct}
    end
  end

  # Mirrors Gateway's ordinal resolution: the settlement is the one the plan's own
  # settlement binding names, not whichever one happens to be unique.
  defp bound_settlement_fact(plan, staged) do
    case Enum.filter(plan["bindings"], &(&1["output_kind"] == "nonstart_settlement_v1")) do
      [binding] ->
        settlement =
          staged
          |> Enum.find(%{}, &(&1["ordinal"] == binding["operation_ordinal"]))
          |> get_in(["result", "facts", "infrastructure_settlement"])

        if is_map(settlement), do: {:ok, settlement}, else: {:error, :settlement_unavailable}

      _ ->
        {:error, :settlement_unavailable}
    end
  end

  defp committed_bundle_events(conn, command_id) do
    with {:ok, rows} <-
           Database.query(
             conn,
             "SELECT event FROM events WHERE command_id = ? ORDER BY seq",
             [command_id]
           ),
         decoded <- Enum.map(rows, fn [bytes] -> decode(bytes) end),
         true <- Enum.all?(decoded, &match?({:ok, _}, &1)) do
      {:ok, Enum.map(decoded, fn {:ok, event} -> event end)}
    else
      _ -> {:error, :unreadable_committed_events}
    end
  end

  defp row_ordinals(rows) do
    Enum.map(rows, fn
      [ordinal | _] when is_integer(ordinal) -> ordinal
      _ -> :invalid
    end)
  end

  defp valid_bundle_protected_row?(
         conn,
         digest,
         bundle_result,
         {operation, operation_result, row}
       ) do
    case row do
      [ordinal, "protected", type, request_bytes, stored_bytes] ->
        expected_id = "atomic-v2/#{digest}/#{ordinal}"

        with true <- is_map(bundle_result),
             true <- is_map(operation),
             true <- is_map(operation_result),
             true <- operation["ordinal"] == ordinal,
             true <- operation["operation_type"] == type,
             true <-
               Map.keys(operation_result) |> Enum.sort() ==
                 ~w(execution_status operation_kind operation_type ordinal result),
             true <- operation_result["ordinal"] == ordinal,
             true <- operation_result["operation_kind"] == "protected",
             true <- operation_result["operation_type"] == type,
             status when status in ["committed", "duplicate", "rolled_back", "unexecuted"] <-
               operation_result["execution_status"],
             {:ok, request} <- decode(request_bytes),
             true <-
               Map.keys(request) |> Enum.sort() ==
                 ~w(command_id expected_revisions operation schema_version),
             ^expected_id <- request["command_id"],
             true <- request["operation"] == operation["operation"],
             {:ok, stored} <- decode(stored_bytes),
             true <-
               Map.keys(stored) |> Enum.sort() ==
                 ~w(execution_status operation_result schema_version),
             1 <- stored["schema_version"],
             ^status <- stored["execution_status"],
             true <- stored["operation_result"] == operation_result["result"],
             true <- valid_execution_status?(bundle_result["disposition"], status),
             true <- valid_operation_reason?(bundle_result, status, operation_result["result"]),
             true <-
               valid_protected_outcome_provenance(
                 conn,
                 status,
                 expected_id,
                 type,
                 request_bytes,
                 operation_result["result"]
               ) do
          true
        else
          _ -> false
        end

      _ ->
        false
    end
  end

  defp valid_execution_status?("accepted", "committed"), do: true
  defp valid_execution_status?("quarantined", "committed"), do: true

  defp valid_execution_status?("rejected", status) when status in ["rolled_back", "unexecuted"],
    do: true

  defp valid_execution_status?("rejected", "duplicate"), do: true

  defp valid_execution_status?(_disposition, _status), do: false

  defp valid_operation_reason?(_bundle, "committed", _result), do: true

  defp valid_operation_reason?(bundle, status, result)
       when is_map(bundle) and is_map(result) and
              status in ["duplicate", "rolled_back", "unexecuted"],
       do: result["reason_code"] == bundle["reason_code"]

  defp valid_operation_reason?(_bundle, _status, _result), do: false

  defp valid_protected_outcome_provenance(
         conn,
         "committed",
         command_id,
         type,
         request_bytes,
         operation_result
       ) do
    with {:ok, request} <- decode(request_bytes),
         true <- is_map(request),
         true <- is_map(operation_result),
         {:ok, [[^type, root_request_bytes, root_result_bytes]]} <-
           Database.query(
             conn,
             "SELECT operation, canonical_request, result FROM root_commands WHERE command_id = ?",
             [command_id]
           ),
         {:ok, root_request} <- decode(root_request_bytes),
         {:ok, root_result} <- decode(root_result_bytes),
         true <- is_map(root_request),
         true <- is_map(root_result),
         true <- root_request["request"] == request,
         true <- root_result == without_settlement_carrier(operation_result),
         true <-
           valid_committed_settlement_carrier(conn, request, root_result, operation_result) do
      true
    else
      _ -> false
    end
  end

  defp valid_protected_outcome_provenance(
         conn,
         "rolled_back",
         command_id,
         _type,
         _request,
         result
       ) do
    with true <- is_map(result),
         "rolled_back" <- result["disposition"],
         ^command_id <- result["command_id"],
         true <-
           Map.keys(result) |> Enum.sort() ==
             ~w(command_id disposition facts reason_code schema_version),
         true <- result["facts"] == %{},
         {:ok, [[0]]} <-
           Database.query(conn, "SELECT count(*) FROM root_commands WHERE command_id = ?", [
             command_id
           ]) do
      true
    else
      _ -> false
    end
  end

  defp valid_protected_outcome_provenance(
         conn,
         "duplicate",
         command_id,
         _type,
         request_bytes,
         result
       ) do
    with true <- is_map(result),
         facts when is_map(facts) <- result["facts"],
         settlement when is_map(settlement) <- facts["infrastructure_settlement"],
         {:ok, request} <- decode(request_bytes),
         true <- is_map(request),
         "duplicate" <- result["disposition"],
         ^command_id <- result["command_id"],
         true <-
           Map.keys(result) |> Enum.sort() ==
             ~w(command_id disposition facts reason_code schema_version),
         true <- Map.keys(facts) == ["infrastructure_settlement"],
         true <- valid_duplicate_settlement_carrier(conn, request, settlement),
         {:ok, [[0]]} <-
           Database.query(conn, "SELECT count(*) FROM root_commands WHERE command_id = ?", [
             command_id
           ]) do
      true
    else
      _ -> false
    end
  end

  defp valid_protected_outcome_provenance(conn, "unexecuted", command_id, _type, _request, result) do
    with true <- is_map(result),
         "unexecuted" <- result["disposition"],
         ^command_id <- result["command_id"],
         true <-
           Map.keys(result) |> Enum.sort() ==
             ~w(command_id disposition facts reason_code schema_version),
         true <- result["facts"] == %{},
         {:ok, [[0]]} <-
           Database.query(conn, "SELECT count(*) FROM root_commands WHERE command_id = ?", [
             command_id
           ]) do
      true
    else
      _ -> false
    end
  end

  defp valid_protected_outcome_provenance(
         _conn,
         _status,
         _command_id,
         _type,
         _request,
         _result
       ),
       do: false

  defp without_settlement_carrier(%{"facts" => facts} = result) when is_map(facts),
    do: %{result | "facts" => Map.delete(facts, "infrastructure_settlement")}

  defp without_settlement_carrier(result), do: result

  defp valid_committed_settlement_carrier(conn, request, root_result, operation_result) do
    operation = request["operation"]
    root_facts = root_result["facts"]
    operation_facts = operation_result["facts"]

    with true <- is_map(operation),
         true <- is_map(root_facts),
         true <- is_map(operation_facts) do
      receipt = root_facts["receipt"]
      settlement = operation_facts["infrastructure_settlement"]
      settlement_present? = Map.has_key?(operation_facts, "infrastructure_settlement")

      requires_settlement? =
        operation["type"] == "settle_claim" and is_map(receipt) and
          receipt["outcome"] == "non_started"

      cond do
        requires_settlement? and settlement_present? and is_map(settlement) ->
          valid_authoritative_settlement(conn, operation, root_facts, settlement)

        requires_settlement? ->
          false

        settlement_present? ->
          false

        true ->
          true
      end
    else
      _ -> false
    end
  end

  defp valid_authoritative_settlement(conn, operation, root_facts, settlement) do
    effect = root_facts["effect"]
    claim = root_facts["claim"]
    receipt = root_facts["receipt"]
    receipt_payload = if(is_map(receipt), do: receipt["payload"], else: nil)

    with true <- valid_settlement_shape?(settlement),
         true <- is_map(effect) and is_map(claim) and is_map(receipt),
         true <- is_map(receipt_payload),
         true <- settlement["effect_id"] == effect["effect_id"],
         true <- settlement["claim_id"] == claim["claim_id"],
         true <- settlement["receipt_id"] == receipt["receipt_id"],
         true <- settlement["role"] == effect["role"],
         true <- settlement["work_owner"] == effect["assignment_id"],
         true <- settlement["infrastructure_generation"] == effect["phase_generation"],
         true <- settlement["predecessor_effect_id"] == effect["predecessor_effect_id"],
         true <- settlement["claim_id"] == operation["claim_id"],
         true <- settlement["receipt_id"] == operation["receipt_id"],
         true <- receipt["request_id"] == operation["request_id"],
         true <- receipt["outcome"] == "non_started",
         true <- settlement["failure_class"] == receipt_payload["failure_class"],
         {:ok, settlement_bytes} <- encode(settlement),
         {:ok, [[^settlement_bytes]]} <-
           Database.query(
             conn,
             "SELECT state FROM root_infrastructure_settlements WHERE effect_id = ? AND claim_id = ? AND receipt_id = ?",
             [settlement["effect_id"], settlement["claim_id"], settlement["receipt_id"]]
           ) do
      true
    else
      _ -> false
    end
  end

  defp valid_duplicate_settlement_carrier(conn, request, settlement) do
    operation = request["operation"]
    payload = if(is_map(operation), do: operation["payload"], else: nil)

    with true <- is_map(operation),
         true <- is_map(payload),
         "settle_claim" <- operation["type"],
         "non_started" <- operation["outcome"],
         true <- valid_settlement_shape?(settlement),
         true <- settlement["claim_id"] == operation["claim_id"],
         true <- settlement["receipt_id"] == operation["receipt_id"],
         true <- settlement["failure_class"] == payload["failure_class"],
         {:ok, settlement_bytes} <- encode(settlement),
         {:ok, [[^settlement_bytes]]} <-
           Database.query(
             conn,
             "SELECT state FROM root_infrastructure_settlements WHERE effect_id = ? AND claim_id = ? AND receipt_id = ?",
             [settlement["effect_id"], settlement["claim_id"], settlement["receipt_id"]]
           ) do
      true
    else
      _ -> false
    end
  end

  defp valid_settlement_shape?(settlement) when is_map(settlement) do
    Map.keys(settlement) |> Enum.sort() ==
      ~w(claim_id effect_id failure_class infrastructure_generation ordinal predecessor_effect_id receipt_id role schema_version work_owner) and
      settlement["schema_version"] == 1 and is_binary(settlement["effect_id"]) and
      is_binary(settlement["claim_id"]) and is_binary(settlement["receipt_id"]) and
      is_binary(settlement["role"]) and is_binary(settlement["work_owner"]) and
      is_integer(settlement["infrastructure_generation"]) and
      settlement["infrastructure_generation"] >= 0 and
      (is_nil(settlement["predecessor_effect_id"]) or
         is_binary(settlement["predecessor_effect_id"])) and
      is_binary(settlement["failure_class"]) and is_integer(settlement["ordinal"]) and
      settlement["ordinal"] > 0
  end

  defp valid_settlement_shape?(_settlement), do: false

  # Delegates to Gateway rather than mirroring it. A hand-copied rule would be correct
  # only while both sides happen to agree: add a third carrier, update one side, and a
  # legitimately committed bundle reads as :protected_corrupt on its next validation.
  #
  # This is deliberately unlike the TransitionPlan/Kernel.Plan duplication, which exists
  # because those are different trust tiers and root must never execute candidate code.
  # Gateway and ProtectedPrimitives are the same trust tier, so duplication here buys
  # nothing and costs a silent divergence.
  defp expected_bundle_domain_request(envelope),
    do: PramanaFoundry.DurableStore.Gateway.atomic_domain_request(envelope)

  defp valid_bundle_domain_row?(row, envelope, result) do
    case row do
      [ordinal, "domain", type, request_bytes, result_bytes] ->
        expected_ordinal = length(envelope["operations"])

        expected_status =
          if result["disposition"] == "accepted", do: "committed", else: "rejected"

        with true <- ordinal == expected_ordinal,
             true <- type == envelope["command"]["type"],
             {:ok, request} <- decode(request_bytes),
             true <- request == expected_bundle_domain_request(envelope),
             {:ok, stored} <- decode(result_bytes),
             true <-
               Map.keys(stored) |> Enum.sort() ==
                 ~w(execution_status operation_result schema_version),
             1 <- stored["schema_version"],
             ^expected_status <- stored["execution_status"],
             true <- stored["operation_result"] == result["domain_result"] do
          true
        else
          _ -> false
        end

      _ ->
        false
    end
  end

  defp validate_durable_operations(conn, rows) do
    with :ok <- validate_domain_v1_operations(conn, rows),
         :ok <- validate_protected_v1_operations(conn, rows),
         true <-
           Enum.all?(rows, fn
             [owner, _id, ordinal, kind, type, request, result]
             when owner in ["domain_v1", "protected_v1", "bundle_v2"] and
                    is_integer(ordinal) and ordinal >= 0 and kind in ["domain", "protected"] and
                    is_binary(type) and is_binary(request) and is_binary(result) ->
               true

             _ ->
               false
           end) do
      :ok
    else
      _ -> {:error, {:protected_corrupt, "durable_operations", :invalid_history}}
    end
  end

  defp validate_domain_v1_operations(conn, rows) do
    actual =
      rows
      |> Enum.filter(&(Enum.at(&1, 0) == "domain_v1"))
      |> MapSet.new()

    with {:ok, expected_rows} <-
           Database.query(
             conn,
             "SELECT 'domain_v1', c.command_id, 0, 'domain', c.command_type, i.canonical_request, r.result " <>
               "FROM commands c JOIN inputs i ON i.input_id = c.input_id JOIN command_results r ON r.command_id = c.command_id " <>
               "LEFT JOIN atomic_bundles b ON b.command_id = c.command_id WHERE b.command_id IS NULL"
           ),
         true <- actual == MapSet.new(expected_rows) do
      :ok
    else
      _ -> {:error, :invalid_domain_v1_history}
    end
  end

  defp validate_protected_v1_operations(conn, rows) do
    actual =
      rows
      |> Enum.filter(&(Enum.at(&1, 0) == "protected_v1"))
      |> MapSet.new()

    with {:ok, expected_rows} <-
           Database.query(
             conn,
             "SELECT 'protected_v1', command_id, 0, 'protected', operation, canonical_request, result FROM root_commands " <>
               "WHERE command_id NOT LIKE 'atomic-v2/%'"
           ),
         true <- actual == MapSet.new(expected_rows),
         {:ok, [[orphan_atomic_roots]]} <-
           Database.query(
             conn,
             "SELECT count(*) FROM root_commands rc WHERE rc.command_id LIKE 'atomic-v2/%' AND NOT EXISTS (" <>
               "SELECT 1 FROM durable_operations d WHERE d.owner_kind = 'bundle_v2' AND d.operation_kind = 'protected' " <>
               "AND json_extract(CAST(d.request AS TEXT), '$.command_id') = rc.command_id)"
           ),
         true <- orphan_atomic_roots == 0 do
      :ok
    else
      _ -> {:error, :invalid_protected_v1_history}
    end
  end

  defp validate_infrastructure_settlements(conn, rows) do
    with {:ok, required_effects} <- required_settlement_effects(conn),
         true <- MapSet.new(Enum.map(rows, &hd/1)) == required_effects,
         :ok <- validate_settlement_rows(conn, rows),
         :ok <- validate_settlement_lineage(rows) do
      :ok
    else
      _ -> {:error, {:protected_corrupt, "root_infrastructure_settlements", :invalid_history}}
    end
  end

  defp required_settlement_effects(conn) do
    with {:ok, rows} <-
           Database.query(
             conn,
             "SELECT d.request, d.result FROM durable_operations d JOIN atomic_bundles b ON b.command_id = d.owner_id " <>
               "WHERE d.owner_kind = 'bundle_v2' AND d.operation_kind = 'protected' AND d.operation_type = 'settle_claim' AND b.disposition = 'accepted'"
           ) do
      Enum.reduce_while(rows, {:ok, MapSet.new()}, fn [request_bytes, result_bytes], {:ok, acc} ->
        with {:ok, request} <- decode(request_bytes),
             {:ok, stored} <- decode(result_bytes) do
          if get_in(request, ["operation", "outcome"]) == "non_started" and
               stored["execution_status"] == "committed" do
            case get_in(stored, ["operation_result", "facts", "effect", "effect_id"]) do
              effect_id when is_binary(effect_id) ->
                {:cont, {:ok, MapSet.put(acc, effect_id)}}

              _ ->
                {:halt, {:error, :invalid_settlement_carrier}}
            end
          else
            {:cont, {:ok, acc}}
          end
        else
          _ -> {:halt, {:error, :invalid_settlement_carrier}}
        end
      end)
    end
  end

  defp validate_settlement_rows(conn, rows) do
    Enum.reduce_while(rows, :ok, fn row, :ok ->
      case row do
        [
          effect_id,
          claim_id,
          receipt_id,
          role,
          owner,
          generation,
          predecessor,
          failure,
          ordinal,
          bytes
        ] ->
          with {:ok, [[effect_bytes]]} <-
                 Database.query(conn, "SELECT state FROM root_effects WHERE effect_id = ?", [
                   effect_id
                 ]),
               {:ok, [[claim_bytes]]} <-
                 Database.query(
                   conn,
                   "SELECT state FROM root_claims WHERE claim_id = ? AND effect_id = ?",
                   [claim_id, effect_id]
                 ),
               {:ok, [[receipt_bytes]]} <-
                 Database.query(
                   conn,
                   "SELECT state FROM root_receipts WHERE receipt_id = ? AND claim_id = ? AND outcome = 'non_started'",
                   [receipt_id, claim_id]
                 ),
               {:ok, effect} <- decode(effect_bytes),
               {:ok, claim} <- decode(claim_bytes),
               {:ok, receipt} <- decode(receipt_bytes),
               true <- claim["effect_id"] == effect_id,
               true <- receipt["claim_id"] == claim_id,
               failure_class when is_binary(failure_class) <-
                 get_in(receipt, ["payload", "failure_class"]),
               expected <- %{
                 "schema_version" => 1,
                 "effect_id" => effect_id,
                 "claim_id" => claim_id,
                 "receipt_id" => receipt_id,
                 "role" => effect["role"],
                 "work_owner" => effect["assignment_id"],
                 "infrastructure_generation" => effect["phase_generation"],
                 "predecessor_effect_id" => effect["predecessor_effect_id"],
                 "failure_class" => failure_class,
                 "ordinal" => ordinal
               },
               true <-
                 [role, owner, generation, predecessor, failure] ==
                   [
                     expected["role"],
                     expected["work_owner"],
                     expected["infrastructure_generation"],
                     expected["predecessor_effect_id"],
                     expected["failure_class"]
                   ],
               {:ok, ^bytes} <- encode(expected) do
            {:cont, :ok}
          else
            _ -> {:halt, {:error, :invalid_settlement_row}}
          end

        _ ->
          {:halt, {:error, :invalid_settlement_row}}
      end
    end)
  end

  defp validate_settlement_lineage(rows) do
    rows
    |> Enum.group_by(fn [_effect, _claim, _receipt, role, owner, generation | _] ->
      {role, owner, generation}
    end)
    |> Enum.reduce_while(:ok, fn {_identity, group}, :ok ->
      ordered = Enum.sort_by(group, &Enum.at(&1, 8))

      valid =
        Enum.with_index(ordered, 1)
        |> Enum.all?(fn {row, expected_ordinal} ->
          effect_id = Enum.at(row, 0)
          predecessor = Enum.at(row, 6)
          ordinal = Enum.at(row, 8)

          ordinal == expected_ordinal and
            if expected_ordinal == 1,
              do: is_nil(predecessor),
              else:
                predecessor == ordered |> Enum.at(expected_ordinal - 2) |> Enum.at(0) and
                  is_binary(effect_id)
        end)

      if valid, do: {:cont, :ok}, else: {:halt, {:error, :invalid_settlement_lineage}}
    end)
  end

  defp validate_inboxes(conn) do
    with {:ok, heads} <-
           Database.query(
             conn,
             "SELECT execution_id, last_sequence, sealed_sequence, state FROM authenticated_inboxes"
           ) do
      Enum.reduce_while(heads, :ok, fn [id, last, sealed, state_bytes], :ok ->
        with {:ok, items} <-
               Database.query(
                 conn,
                 "SELECT sequence, item_kind, disposition, item_digest, item FROM authenticated_inbox_items WHERE execution_id = ? ORDER BY sequence",
                 [id]
               ),
             true <- length(items) == last,
             true <- Enum.map(items, &hd/1) == Enum.to_list(1..last//1),
             true <- is_nil(sealed) or sealed <= last,
             :ok <- validate_inbox_items(id, sealed, items),
             {:ok, inbox} <- load_existing_inbox(conn, id),
             expected_state <- inbox_state(id, inbox),
             {:ok, ^expected_state} <- decode(state_bytes) do
          {:cont, :ok}
        else
          _ -> {:halt, {:error, {:protected_corrupt, "authenticated_inboxes", id}}}
        end
      end)
    end
  end

  defp validate_inbox_items(execution_id, sealed, items) do
    Enum.reduce_while(items, :ok, fn [sequence, kind, disposition, digest, bytes], :ok ->
      with {:ok, item} <- decode(bytes),
           true <- item["execution_id"] == execution_id,
           true <- item["sequence"] == sequence,
           true <- item["item_kind"] == kind,
           true <- item["disposition"] == disposition,
           expected_disposition <-
             if(is_integer(sealed) and sequence > sealed, do: "late", else: "accepted"),
           true <- disposition == expected_disposition,
           {:ok, ^digest} <-
             Encoding.semantic_digest("pramana-foundry-authenticated-inbox-item-v1", %{
               "execution_id" => execution_id,
               "sequence" => sequence,
               "item_kind" => kind,
               "payload" => item["payload"]
             }) do
        {:cont, :ok}
      else
        _ -> {:halt, {:error, :invalid_inbox_item_provenance}}
      end
    end)
  end

  defp validate_ledgers(conn) do
    with {:ok, rows} <-
           Database.query(
             conn,
             "SELECT ledger_id, generation, parent_ledger_id, parent_generation, dimension, revision, status, authorized, available, held, consumed, delegated, retired, state FROM root_ledgers"
           ) do
      Enum.reduce_while(rows, :ok, fn row, :ok ->
        {ledger_row, [state_bytes]} = Enum.split(row, 13)
        ledger = ledger_from_row(ledger_row)

        with true <- conserved?(ledger) and ledger.dimension in @dimensions,
             {:ok, expected} <- encode(public_ledger(ledger)),
             ^expected <- state_bytes do
          {:cont, :ok}
        else
          _ -> {:halt, {:error, {:protected_corrupt, "root_ledgers", ledger.ledger_id}}}
        end
      end)
    end
  end

  defp validate_ledger_tree(conn) do
    with {:ok, parents} <-
           Database.query(
             conn,
             "SELECT p.ledger_id, p.generation, p.delegated, coalesce(sum(c.authorized), 0) FROM root_ledgers p LEFT JOIN root_ledgers c ON c.parent_ledger_id = p.ledger_id AND c.parent_generation = p.generation AND c.dimension = p.dimension GROUP BY p.ledger_id, p.generation, p.delegated"
           ) do
      case Enum.find(parents, fn [_id, _generation, delegated, child_authorized] ->
             delegated != child_authorized
           end) do
        nil ->
          :ok

        [id, generation | _rest] ->
          {:error, {:protected_corrupt, "root_ledgers", {id, generation, :tree_conservation}}}
      end
    end
  end

  defp validate_reservations(conn) do
    with {:ok, rows} <-
           Database.query(
             conn,
             "SELECT l.ledger_id, l.generation, coalesce(sum(CASE WHEN r.status IN ('reserved', 'issued_unknown') THEN r.units ELSE 0 END), 0), coalesce(sum(CASE WHEN r.status = 'consumed' THEN r.units ELSE 0 END), 0) FROM root_ledgers l LEFT JOIN root_reservations r ON r.ledger_id = l.ledger_id AND r.generation = l.generation GROUP BY l.ledger_id, l.generation"
           ) do
      Enum.reduce_while(rows, :ok, fn [id, generation, held, consumed], :ok ->
        case load_existing_ledger(conn, id, generation) do
          {:ok, ledger} when ledger.held == held and ledger.consumed == consumed -> {:cont, :ok}
          _ -> {:halt, {:error, {:protected_corrupt, "root_reservations", id}}}
        end
      end)
    end
  end

  defp validate_effect_relations(conn) do
    with {:ok, rows} <-
           Database.query(
             conn,
             "SELECT c.claim_id, c.effect_id, c.status, e.status FROM root_claims c JOIN root_effects e ON e.effect_id = c.effect_id"
           ) do
      if Enum.all?(rows, fn [_claim_id, _effect_id, claim_status, effect_status] ->
           claim_status == effect_status or
             {claim_status, effect_status} in [{"claimed", "claimed"}, {"issued", "issued"}]
         end),
         do: :ok,
         else: {:error, {:protected_corrupt, "root_claims", :state_mismatch}}
    end
  end

  defp validate_semantic_relations(conn) do
    with :ok <- validate_effect_authority_relations(conn),
         :ok <- validate_receipt_provenance(conn),
         :ok <- validate_request_ownership(conn) do
      :ok
    end
  end

  defp validate_authority_command_provenance(conn) do
    with :ok <- validate_ledger_result_provenance(conn),
         :ok <- validate_effect_command_provenance(conn),
         :ok <- validate_claim_command_provenance(conn),
         :ok <- validate_typed_transition_replay(conn),
         :ok <- validate_current_transition_provenance(conn),
         :ok <- validate_reservation_command_provenance(conn) do
      :ok
    end
  end

  defp validate_ledger_result_provenance(conn) do
    with {:ok, command_rows} <-
           Database.query(
             conn,
             "SELECT operation, canonical_request, result FROM root_commands WHERE disposition = 'accepted' AND operation IN ('grant_ledger', 'delegate_allocation', 'reset_generation') ORDER BY seq"
           ),
         {:ok, origins} <- ledger_creation_origins(conn, command_rows),
         {:ok, ledger_rows} <-
           Database.query(
             conn,
             "SELECT ledger_id, generation, parent_ledger_id, parent_generation, dimension, revision, status, authorized, available, held, consumed, delegated, retired FROM root_ledgers"
           ) do
      Enum.reduce_while(ledger_rows, :ok, fn row, :ok ->
        ledger = public_ledger(ledger_from_row(row))

        origin = Map.get(origins, {ledger["ledger_id"], ledger["generation"]})

        origin? =
          is_map(origin) and origin["dimension"] == ledger["dimension"] and
            origin["parent_ledger_id"] == ledger["parent_ledger_id"] and
            origin["parent_generation"] == ledger["parent_generation"] and
            ledger["authorized"] <= origin["authorized"]

        if origin?,
          do: {:cont, :ok},
          else: {:halt, {:error, {:protected_corrupt, "root_ledgers", :command_provenance}}}
      end)
    end
  end

  defp ledger_creation_origins(conn, rows) do
    Enum.reduce_while(rows, {:ok, %{}}, fn [type, request_bytes, result_bytes], {:ok, acc} ->
      with {:ok, %{"request" => %{"operation" => operation}}} <- decode(request_bytes),
           ^type <- operation["type"],
           {:ok, result} <- decode(result_bytes),
           {:ok, fact} <- ledger_creation_fact(conn, operation, result["facts"]),
           key <- {fact["ledger_id"], fact["generation"]},
           false <- Map.has_key?(acc, key) do
        {:cont, {:ok, Map.put(acc, key, fact)}}
      else
        _ -> {:halt, {:error, :invalid_ledger_command_provenance}}
      end
    end)
  end

  defp ledger_creation_fact(_conn, %{"type" => "grant_ledger"} = operation, facts) do
    validate_creation_ledger(
      facts["ledger"],
      operation["ledger_id"],
      operation["generation"],
      nil,
      nil,
      operation["dimension"],
      operation["units"]
    )
  end

  defp ledger_creation_fact(_conn, %{"type" => "delegate_allocation"} = operation, facts) do
    validate_creation_ledger(
      facts["child_ledger"],
      operation["child_ledger_id"],
      operation["child_generation"],
      operation["parent_ledger_id"],
      operation["parent_generation"],
      operation["dimension"],
      operation["units"]
    )
  end

  defp ledger_creation_fact(conn, %{"type" => "reset_generation"} = operation, facts) do
    with {:ok, old} <-
           load_existing_ledger(conn, operation["ledger_id"], operation["old_generation"]) do
      validate_creation_ledger(
        facts["new_generation"],
        operation["ledger_id"],
        operation["new_generation"],
        operation["parent_ledger_id"],
        operation["parent_generation"],
        old.dimension,
        operation["units"]
      )
    end
  end

  defp validate_creation_ledger(
         fact,
         ledger_id,
         generation,
         parent_id,
         parent_generation,
         dimension,
         units
       ) do
    with true <- is_map(fact),
         true <- fact["schema_version"] == 1,
         true <- fact["ledger_id"] == ledger_id and fact["generation"] == generation,
         true <- fact["parent_ledger_id"] == parent_id,
         true <- fact["parent_generation"] == parent_generation,
         true <- fact["dimension"] == dimension,
         true <- fact["revision"] == 0 and fact["status"] == "open",
         true <- fact["authorized"] == units and fact["available"] == units,
         true <-
           Enum.all?(~w(held consumed delegated retired), fn key -> fact[key] == 0 end) do
      {:ok, fact}
    else
      _ -> {:error, :invalid_ledger_creation_fact}
    end
  end

  defp validate_effect_command_provenance(conn) do
    with {:ok, command_rows} <-
           Database.query(
             conn,
             "SELECT actor_id, canonical_request, disposition FROM root_commands WHERE operation = 'create_effect' ORDER BY seq"
           ),
         {:ok, effect_rows} <- Database.query(conn, "SELECT effect_id FROM root_effects") do
      Enum.reduce_while(effect_rows, :ok, fn [id], :ok ->
        with {:ok, effect} <- load_effect(conn, id),
             [{actor, operation}] <-
               Enum.flat_map(command_rows, fn [actor, bytes, disposition] ->
                 with "accepted" <- disposition,
                      {:ok, %{"request" => %{"operation" => operation}}} <- decode(bytes),
                      ^id <- operation["effect_id"] do
                   [{actor, operation}]
                 else
                   _ -> []
                 end
               end),
             true <- actor == effect.issuer and effect.channel == "protected-gateway",
             {:ok, digest} <-
               Encoding.semantic_digest("pramana-foundry-effect-request-v1", %{
                 "effect_id" => operation["effect_id"],
                 "operation" => operation["operation"],
                 "scope" => operation["scope"],
                 "ticket_id" => operation["ticket_id"],
                 "attempt_id" => operation["attempt_id"],
                 "execution_id" => operation["execution_id"],
                 "request" => operation["request"]
               }),
             true <- digest == effect.request_digest,
             true <- effect.policy_id == operation["policy_id"],
             true <- effect.policy_revision == operation["policy_revision"],
             true <- effect.control_id == operation["control_id"],
             true <- effect.control_revision == operation["control_revision"],
             true <- effect.operation == operation["operation"],
             true <- effect.scope == operation["scope"],
             true <- effect.ticket_id == operation["ticket_id"],
             true <- effect.attempt_id == operation["attempt_id"],
             true <- effect.execution_id == operation["execution_id"],
             true <- effect.request_id == operation["request"]["request_id"],
             true <- effect.role == operation["request"]["role"],
             true <-
               effect.assignment_id ==
                 assignment_id(
                   operation["ticket_id"],
                   operation["attempt_id"],
                   operation["request"]["role"]
                 ),
             true <-
               effect.phase_generation ==
                 Map.get(operation["request"], "phase_generation", 0),
             true <-
               effect.operation_ordinal ==
                 Map.get(operation["request"], "operation_ordinal", 0),
             true <-
               effect.predecessor_effect_id == operation["request"]["predecessor_effect_id"],
             true <- effect.profile == Map.get(operation["request"], "profile", "unspecified"),
             true <- effect.deadline == operation["request"]["deadline"],
             true <- effect.reservation_ids == operation["reservation_ids"],
             {:ok, lease_specs} <- normalize_lease_specs(operation["leases"]),
             true <- effect.lease_specs == lease_specs do
          {:cont, :ok}
        else
          _ -> {:halt, {:error, {:protected_corrupt, "root_effects", id}}}
        end
      end)
    end
  end

  defp validate_claim_command_provenance(conn) do
    with {:ok, command_rows} <-
           Database.query(
             conn,
             "SELECT operation, canonical_request, result FROM root_commands WHERE disposition = 'accepted' AND operation IN ('claim_effect', 'reclaim_claim') ORDER BY seq"
           ),
         {:ok, origins} <- claim_epoch_origins(command_rows),
         {:ok, claim_rows} <- Database.query(conn, "SELECT claim_id FROM root_claims") do
      Enum.reduce_while(claim_rows, :ok, fn [id], :ok ->
        with {:ok, claim} <- load_claim(conn, id),
             %{effect_id: effect_id, writer_epoch: writer_epoch} <- Map.get(origins, id),
             true <- claim.effect_id == effect_id and claim.writer_epoch == writer_epoch do
          {:cont, :ok}
        else
          _ -> {:halt, {:error, {:protected_corrupt, "root_claims", :command_provenance}}}
        end
      end)
    end
  end

  defp claim_epoch_origins(rows) do
    Enum.reduce_while(rows, {:ok, %{}}, fn [type, request_bytes, result_bytes], {:ok, acc} ->
      with {:ok, %{"request" => %{"operation" => operation}}} <- decode(request_bytes),
           ^type <- operation["type"],
           {:ok, result} <- decode(result_bytes),
           claim when is_map(claim) <- get_in(result, ["facts", "claim"]) do
        update_claim_epoch_origin(acc, operation, claim)
      else
        _ -> {:halt, {:error, :invalid_claim_command_provenance}}
      end
    end)
  end

  defp update_claim_epoch_origin(acc, %{"type" => "claim_effect"} = operation, claim) do
    id = operation["claim_id"]

    with false <- Map.has_key?(acc, id),
         true <- claim["claim_id"] == id and claim["effect_id"] == operation["effect_id"],
         true <- claim["writer_epoch"] == operation["writer_epoch"],
         true <- claim["status"] == "claimed" and claim["revision"] == 0 do
      {:cont,
       {:ok,
        Map.put(acc, id, %{
          effect_id: operation["effect_id"],
          writer_epoch: operation["writer_epoch"]
        })}}
    else
      _ -> {:halt, {:error, :invalid_claim_command_provenance}}
    end
  end

  defp update_claim_epoch_origin(acc, %{"type" => "reclaim_claim"} = operation, claim) do
    id = operation["claim_id"]

    with %{writer_epoch: prior} = origin <- Map.get(acc, id),
         true <- prior == operation["prior_writer_epoch"],
         true <- operation["proof"] == "issuer_quiescent",
         true <- operation["new_writer_epoch"] != prior,
         true <- claim["claim_id"] == id,
         true <- claim["effect_id"] == origin.effect_id,
         true <- claim["writer_epoch"] == operation["new_writer_epoch"],
         true <- claim["status"] == "claimed" do
      {:cont, {:ok, Map.put(acc, id, %{origin | writer_epoch: operation["new_writer_epoch"]})}}
    else
      _ -> {:halt, {:error, :invalid_claim_command_provenance}}
    end
  end

  defp validate_typed_transition_replay(conn) do
    with {:ok, rows} <-
           Database.query(
             conn,
             "SELECT operation, disposition, reason_code, canonical_request FROM root_commands ORDER BY seq"
           ),
         {:ok, replay} <- replay_transition_rows(rows),
         :ok <- validate_replay_ledgers(conn, replay.ledgers),
         :ok <- validate_replay_effects(conn, replay.effects),
         :ok <- validate_replay_claims(conn, replay.claims),
         :ok <- validate_replay_reservations(conn, replay.reservations),
         :ok <- validate_replay_closures(conn, replay.closures) do
      :ok
    end
  end

  defp replay_transition_rows(rows) do
    initial = %{
      ledgers: %{},
      effects: %{},
      claims: %{},
      reservations: %{},
      receipts: %{},
      closures: MapSet.new()
    }

    Enum.reduce_while(rows, {:ok, initial}, fn
      [type, disposition, reason, request_bytes], {:ok, replay} ->
        with {:ok, %{"request" => %{"operation" => operation}}} <- decode(request_bytes),
             ^type <- operation["type"],
             {:ok, next} <- replay_transition_operation(replay, operation, disposition, reason) do
          {:cont, {:ok, next}}
        else
          {:error, _reason} = error -> {:halt, error}
          _ -> {:halt, {:error, :invalid_typed_transition_history}}
        end
    end)
  end

  defp replay_transition_operation(replay, _operation, "rejected", reason)
       when reason != "conflicting_receipt",
       do: {:ok, replay}

  defp replay_transition_operation(
         replay,
         %{"type" => "settle_claim", "claim_id" => claim_id},
         "rejected",
         "conflicting_receipt"
       ) do
    with {:ok, claim} <- replay_get(replay.claims, claim_id),
         {:ok, effect} <- replay_get(replay.effects, claim.effect_id) do
      {:ok,
       replay
       |> put_in([:claims, claim_id], replay_status(claim, "reconciliation_required"))
       |> put_in([:effects, claim.effect_id], replay_status(effect, "reconciliation_required"))}
    end
  end

  defp replay_transition_operation(replay, %{"type" => "grant_ledger"} = op, "accepted", _) do
    ledger =
      replay_ledger(op["ledger_id"], op["generation"], nil, nil, op["dimension"], op["units"])

    replay_add(replay, :ledgers, {op["ledger_id"], op["generation"]}, ledger)
  end

  defp replay_transition_operation(replay, %{"type" => "delegate_allocation"} = op, "accepted", _) do
    parent_key = {op["parent_ledger_id"], op["parent_generation"]}
    child_key = {op["child_ledger_id"], op["child_generation"]}

    with {:ok, parent} <- replay_get(replay.ledgers, parent_key),
         false <- Map.has_key?(replay.ledgers, child_key) do
      units = op["units"]

      parent =
        parent
        |> replay_revision()
        |> Map.update!(:available, &(&1 - units))
        |> Map.update!(:delegated, &(&1 + units))

      child =
        replay_ledger(
          op["child_ledger_id"],
          op["child_generation"],
          op["parent_ledger_id"],
          op["parent_generation"],
          parent.dimension,
          units
        )

      {:ok,
       replay
       |> put_in([:ledgers, parent_key], parent)
       |> put_in([:ledgers, child_key], child)}
    else
      _ -> {:error, :invalid_delegate_replay}
    end
  end

  defp replay_transition_operation(replay, %{"type" => "return_allocation"} = op, "accepted", _) do
    child_key = {op["child_ledger_id"], op["child_generation"]}

    with {:ok, child} <- replay_get(replay.ledgers, child_key),
         parent_key <- {child.parent_ledger_id, child.parent_generation},
         {:ok, parent} <- replay_get(replay.ledgers, parent_key) do
      units = op["units"]

      child =
        child
        |> replay_revision()
        |> Map.update!(:authorized, &(&1 - units))
        |> Map.update!(:available, &(&1 - units))

      parent =
        parent
        |> replay_revision()
        |> Map.update!(:delegated, &(&1 - units))
        |> Map.update!(:available, &(&1 + units))

      {:ok,
       replay
       |> put_in([:ledgers, child_key], child)
       |> put_in([:ledgers, parent_key], parent)}
    end
  end

  defp replay_transition_operation(replay, %{"type" => "reserve"} = op, "accepted", _) do
    with {:ok, ledger} <- replay_get(replay.ledgers, {op["ledger_id"], op["generation"]}) do
      reservation = %{
        reservation_id: op["reservation_id"],
        ledger_id: op["ledger_id"],
        generation: op["generation"],
        dimension: ledger.dimension,
        owner_kind: op["owner_kind"],
        owner_id: op["owner_id"],
        units: op["units"],
        revision: 0,
        status: "proposed",
        claim_id: nil
      }

      replay_add(replay, :reservations, reservation.reservation_id, reservation)
    end
  end

  defp replay_transition_operation(
         replay,
         %{"type" => "release_reservation", "reservation_id" => id},
         "accepted",
         _
       ),
       do: replay_release_reservations(replay, [id])

  defp replay_transition_operation(replay, %{"type" => "close_attempt"} = op, "accepted", _) do
    key = {op["ticket_id"], op["attempt_id"]}

    settled? =
      replay.effects
      |> Map.values()
      |> Enum.filter(&({&1.ticket_id, &1.attempt_id} == key))
      |> Enum.all?(&(&1.status in @closed_effect_statuses))

    if settled? and not MapSet.member?(replay.closures, key),
      do: {:ok, %{replay | closures: MapSet.put(replay.closures, key)}},
      else: {:error, :invalid_attempt_closure_replay}
  end

  defp replay_transition_operation(replay, %{"type" => "create_effect"} = op, "accepted", _) do
    with false <- Map.has_key?(replay.effects, op["effect_id"]),
         false <- MapSet.member?(replay.closures, {op["ticket_id"], op["attempt_id"]}),
         {:ok, replay} <- replay_activate_reservations(replay, op["reservation_ids"]) do
      effect = %{
        effect_id: op["effect_id"],
        ticket_id: op["ticket_id"],
        attempt_id: op["attempt_id"],
        control_id: op["control_id"],
        reservation_ids: op["reservation_ids"],
        status: "pending",
        revision: 0
      }

      {:ok, put_in(replay, [:effects, effect.effect_id], effect)}
    else
      _ -> {:error, :invalid_effect_replay}
    end
  end

  defp replay_transition_operation(replay, %{"type" => "claim_effect"} = op, "accepted", _) do
    with {:ok, effect} <- replay_get(replay.effects, op["effect_id"]),
         true <- effect.status == "pending",
         false <- Map.has_key?(replay.claims, op["claim_id"]),
         {:ok, replay} <- replay_bind_reservations(replay, effect.reservation_ids, op["claim_id"]) do
      claim = %{
        claim_id: op["claim_id"],
        effect_id: effect.effect_id,
        writer_epoch: op["writer_epoch"],
        status: "claimed",
        revision: 0
      }

      {:ok,
       replay
       |> put_in([:effects, effect.effect_id], replay_status(effect, "claimed"))
       |> put_in([:claims, claim.claim_id], claim)}
    else
      _ -> {:error, :invalid_claim_replay}
    end
  end

  defp replay_transition_operation(replay, %{"type" => "reclaim_claim"} = op, "accepted", _) do
    with {:ok, claim} <- replay_get(replay.claims, op["claim_id"]),
         true <- claim.status == "claimed" and claim.writer_epoch == op["prior_writer_epoch"] do
      next = claim |> replay_revision() |> Map.put(:writer_epoch, op["new_writer_epoch"])
      {:ok, put_in(replay, [:claims, claim.claim_id], next)}
    else
      _ -> {:error, :invalid_reclaim_replay}
    end
  end

  defp replay_transition_operation(replay, %{"type" => "issue_claim"} = op, "accepted", _) do
    with {:ok, claim} <- replay_get(replay.claims, op["claim_id"]),
         true <- claim.status == "claimed",
         {:ok, effect} <- replay_get(replay.effects, claim.effect_id),
         true <- effect.status == "claimed",
         {:ok, replay} <-
           replay_reservation_statuses(replay, effect.reservation_ids, "issued_unknown") do
      {:ok,
       replay
       |> put_in([:claims, claim.claim_id], replay_status(claim, "issued"))
       |> put_in([:effects, effect.effect_id], replay_status(effect, "issued"))}
    else
      _ -> {:error, :invalid_issue_replay}
    end
  end

  defp replay_transition_operation(replay, %{"type" => "cancel_effect"} = op, "accepted", _),
    do: replay_cancel_effect(replay, op["effect_id"], op["proof"])

  defp replay_transition_operation(replay, %{"type" => "settle_claim"} = op, "accepted", _),
    do: replay_settle_claim(replay, op)

  defp replay_transition_operation(replay, %{"type" => "close_generation"} = op, "accepted", _),
    do: replay_close_subtree(replay, {op["ledger_id"], op["generation"]})

  defp replay_transition_operation(replay, %{"type" => "reset_generation"} = op, "accepted", _) do
    old_key = {op["ledger_id"], op["old_generation"]}

    with {:ok, old} <- replay_get(replay.ledgers, old_key),
         {:ok, replay} <- replay_close_subtree(replay, old_key) do
      fresh =
        replay_ledger(
          op["ledger_id"],
          op["new_generation"],
          op["parent_ledger_id"],
          op["parent_generation"],
          old.dimension,
          op["units"]
        )

      replay = put_in(replay, [:ledgers, {fresh.ledger_id, fresh.generation}], fresh)

      if is_binary(op["parent_ledger_id"]) do
        parent_key = {op["parent_ledger_id"], op["parent_generation"]}

        with {:ok, parent} <- replay_get(replay.ledgers, parent_key) do
          parent =
            parent
            |> replay_revision()
            |> Map.update!(:available, &(&1 - op["units"]))
            |> Map.update!(:delegated, &(&1 + op["units"]))

          {:ok, put_in(replay, [:ledgers, parent_key], parent)}
        end
      else
        {:ok, replay}
      end
    end
  end

  defp replay_transition_operation(replay, %{"type" => "set_control"} = op, "accepted", _) do
    if get_in(op, ["value", "status"]) == "cancel_requested" do
      replay.effects
      |> Enum.filter(fn {_id, effect} -> effect.control_id == op["control_id"] end)
      |> Enum.sort()
      |> Enum.reduce_while({:ok, replay}, fn {id, effect}, {:ok, acc} ->
        case effect.status do
          "pending" -> replay_reduce(replay_cancel_effect(acc, id, "unissued"))
          "claimed" -> replay_reduce(replay_cancel_effect(acc, id, "issuer_quiescent"))
          _ -> {:cont, {:ok, acc}}
        end
      end)
    else
      {:ok, replay}
    end
  end

  defp replay_transition_operation(replay, %{"type" => type}, "accepted", _)
       when type in ["set_policy", "append_inbox", "seal_inbox"],
       do: {:ok, replay}

  defp replay_transition_operation(_replay, _operation, _disposition, _reason),
    do: {:error, :unsupported_typed_transition}

  defp replay_reduce({:ok, replay}), do: {:cont, {:ok, replay}}
  defp replay_reduce(error), do: {:halt, error}

  defp replay_ledger(id, generation, parent, parent_generation, dimension, units) do
    %{
      ledger_id: id,
      generation: generation,
      parent_ledger_id: parent,
      parent_generation: parent_generation,
      dimension: dimension,
      revision: 0,
      status: "open",
      authorized: units,
      available: units,
      held: 0,
      consumed: 0,
      delegated: 0,
      retired: 0
    }
  end

  defp replay_get(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, :missing_replay_authority}
    end
  end

  defp replay_add(replay, kind, key, value) do
    if Map.has_key?(replay[kind], key),
      do: {:error, :duplicate_replay_authority},
      else: {:ok, put_in(replay, [kind, key], value)}
  end

  defp replay_revision(value), do: Map.update!(value, :revision, &(&1 + 1))
  defp replay_status(value, status), do: value |> replay_revision() |> Map.put(:status, status)

  defp replay_activate_reservations(replay, ids) do
    Enum.reduce_while(ids, {:ok, replay}, fn id, {:ok, acc} ->
      with {:ok, reservation} <- replay_get(acc.reservations, id),
           true <- reservation.status == "proposed",
           key <- {reservation.ledger_id, reservation.generation},
           {:ok, ledger} <- replay_get(acc.ledgers, key) do
        reservation = replay_status(reservation, "reserved")

        ledger =
          ledger
          |> replay_revision()
          |> Map.update!(:available, &(&1 - reservation.units))
          |> Map.update!(:held, &(&1 + reservation.units))

        {:cont,
         {:ok,
          acc
          |> put_in([:reservations, id], reservation)
          |> put_in([:ledgers, key], ledger)}}
      else
        _ -> {:halt, {:error, :invalid_reservation_activation_replay}}
      end
    end)
  end

  defp replay_bind_reservations(replay, ids, claim_id) do
    Enum.reduce_while(ids, {:ok, replay}, fn id, {:ok, acc} ->
      with {:ok, reservation} <- replay_get(acc.reservations, id),
           true <- reservation.status == "reserved" and is_nil(reservation.claim_id) do
        next = reservation |> replay_revision() |> Map.put(:claim_id, claim_id)
        {:cont, {:ok, put_in(acc, [:reservations, id], next)}}
      else
        _ -> {:halt, {:error, :invalid_reservation_binding_replay}}
      end
    end)
  end

  defp replay_reservation_statuses(replay, ids, status) do
    Enum.reduce_while(ids, {:ok, replay}, fn id, {:ok, acc} ->
      case replay_get(acc.reservations, id) do
        {:ok, reservation} ->
          {:cont, {:ok, put_in(acc, [:reservations, id], replay_status(reservation, status))}}

        error ->
          {:halt, error}
      end
    end)
  end

  defp replay_release_reservations(replay, ids) do
    Enum.reduce_while(ids, {:ok, replay}, fn id, {:ok, acc} ->
      with {:ok, reservation} <- replay_get(acc.reservations, id),
           key <- {reservation.ledger_id, reservation.generation},
           {:ok, ledger} <- replay_get(acc.ledgers, key) do
        target = if ledger.status == "open", do: "released", else: "retired"
        next_reservation = replay_status(reservation, target)

        next_ledger =
          if reservation.status == "proposed" do
            ledger
          else
            bucket = if ledger.status == "open", do: :available, else: :retired

            ledger
            |> replay_revision()
            |> Map.update!(:held, &(&1 - reservation.units))
            |> Map.update!(bucket, &(&1 + reservation.units))
          end

        {:cont,
         {:ok,
          acc
          |> put_in([:reservations, id], next_reservation)
          |> put_in([:ledgers, key], next_ledger)}}
      else
        error -> {:halt, error}
      end
    end)
  end

  defp replay_cancel_effect(replay, effect_id, "control_ack") do
    with {:ok, _effect} <- replay_get(replay.effects, effect_id), do: {:ok, replay}
  end

  defp replay_cancel_effect(replay, effect_id, proof)
       when proof in ["unissued", "issuer_quiescent"] do
    with {:ok, effect} <- replay_get(replay.effects, effect_id),
         {:ok, replay} <- replay_release_reservations(replay, effect.reservation_ids) do
      replay = put_in(replay, [:effects, effect_id], replay_status(effect, "cancelled"))

      case Enum.find(replay.claims, fn {_id, claim} -> claim.effect_id == effect_id end) do
        nil -> {:ok, replay}
        {id, claim} -> {:ok, put_in(replay, [:claims, id], replay_status(claim, "cancelled"))}
      end
    end
  end

  defp replay_settle_claim(replay, op) do
    with {:ok, claim} <- replay_get(replay.claims, op["claim_id"]),
         {:ok, effect} <- replay_get(replay.effects, claim.effect_id),
         {:ok, digest} <- receipt_digest(op) do
      receipt_key = {op["receipt_id"], op["request_id"], digest}

      if Map.has_key?(replay.receipts, receipt_key) do
        {:ok, replay}
      else
        replay = put_in(replay, [:receipts, receipt_key], op["outcome"])

        cond do
          # stale_unknown_receipt: a later unknown is stored and changes no status.
          op["outcome"] == "unknown" and claim.status != "issued" ->
            {:ok, replay}

          op["outcome"] == "unknown" ->
            {:ok,
             replay
             |> put_in([:claims, claim.claim_id], replay_status(claim, "unknown"))
             |> put_in([:effects, effect.effect_id], replay_status(effect, "unknown"))}

          true ->
            with {:ok, replay} <-
                   replay_settle_reservations(replay, effect.reservation_ids, op["outcome"]) do
              {:ok,
               replay
               |> put_in([:claims, claim.claim_id], replay_status(claim, op["outcome"]))
               |> put_in([:effects, effect.effect_id], replay_status(effect, op["outcome"]))}
            end
        end
      end
    end
  end

  defp replay_settle_reservations(replay, ids, outcome) do
    Enum.reduce_while(ids, {:ok, replay}, fn id, {:ok, acc} ->
      with {:ok, reservation} <- replay_get(acc.reservations, id),
           key <- {reservation.ledger_id, reservation.generation},
           {:ok, ledger} <- replay_get(acc.ledgers, key) do
        {status, bucket} =
          if outcome in ["succeeded", "failed"] do
            {"consumed", :consumed}
          else
            if ledger.status == "open", do: {"released", :available}, else: {"retired", :retired}
          end

        next_reservation = replay_status(reservation, status)

        next_ledger =
          ledger
          |> replay_revision()
          |> Map.update!(:held, &(&1 - reservation.units))
          |> Map.update!(bucket, &(&1 + reservation.units))

        {:cont,
         {:ok,
          acc
          |> put_in([:reservations, id], next_reservation)
          |> put_in([:ledgers, key], next_ledger)}}
      else
        error -> {:halt, error}
      end
    end)
  end

  defp replay_close_subtree(replay, root_key) do
    descendants =
      replay.ledgers
      |> Map.keys()
      |> Enum.filter(&replay_descendant?(replay.ledgers, &1, root_key))
      |> Enum.sort()

    with true <- descendants != [],
         {:ok, replay} <-
           Enum.reduce_while(descendants, {:ok, replay}, fn key, {:ok, acc} ->
             ledger = acc.ledgers[key]

             ids =
               acc.reservations
               |> Enum.filter(fn {_id, reservation} ->
                 {reservation.ledger_id, reservation.generation} == key and
                   reservation.status == "reserved"
               end)
               |> Enum.map(&elem(&1, 0))
               |> Enum.sort()

             result =
               if ledger.status == "open",
                 do: replay_release_reservations(acc, ids),
                 else: {:ok, acc}

             case result do
               {:ok, next} -> {:cont, {:ok, replay_cancel_released_owners(next, ids)}}
               error -> {:halt, error}
             end
           end) do
      replay =
        Enum.reduce(descendants, replay, fn key, acc ->
          ledger = acc.ledgers[key]

          if ledger.status == "open" do
            closed =
              ledger
              |> replay_revision()
              |> Map.put(:status, "closed")
              |> Map.update!(:retired, &(&1 + ledger.available))
              |> Map.put(:available, 0)

            put_in(acc, [:ledgers, key], closed)
          else
            acc
          end
        end)

      {:ok, replay}
    else
      _ -> {:error, :invalid_close_replay}
    end
  end

  defp replay_cancel_released_owners(replay, ids) do
    ids
    |> Enum.map(&replay.reservations[&1].owner_id)
    |> Enum.uniq()
    |> Enum.reduce(replay, fn effect_id, acc ->
      case acc.effects[effect_id] do
        %{status: status} = effect when status in ["pending", "claimed"] ->
          acc = put_in(acc, [:effects, effect_id], replay_status(effect, "cancelled"))

          case Enum.find(acc.claims, fn {_id, claim} -> claim.effect_id == effect_id end) do
            nil -> acc
            {id, claim} -> put_in(acc, [:claims, id], replay_status(claim, "cancelled"))
          end

        _ ->
          acc
      end
    end)
  end

  defp replay_descendant?(_ledgers, key, key), do: true

  defp replay_descendant?(ledgers, key, root) do
    case ledgers[key] do
      %{parent_ledger_id: parent, parent_generation: generation} when is_binary(parent) ->
        replay_descendant?(ledgers, {parent, generation}, root)

      _ ->
        false
    end
  end

  defp validate_replay_ledgers(conn, replay) do
    with {:ok, rows} <-
           Database.query(
             conn,
             "SELECT ledger_id, generation, parent_ledger_id, parent_generation, dimension, revision, status, authorized, available, held, consumed, delegated, retired FROM root_ledgers"
           ) do
      values =
        Map.new(rows, fn row ->
          ledger = ledger_from_row(row)
          {{ledger.ledger_id, ledger.generation}, ledger}
        end)

      if values == replay,
        do: :ok,
        else: {:error, {:protected_corrupt, "root_ledgers", :typed_transition_replay}}
    end
  end

  defp validate_replay_effects(conn, replay) do
    with {:ok, rows} <- Database.query(conn, "SELECT effect_id FROM root_effects") do
      Enum.reduce_while(rows, :ok, fn [id], :ok ->
        with {:ok, current} <- load_effect(conn, id),
             %{status: status, revision: revision} <- replay[id],
             true <- current.status == status and current.revision == revision do
          {:cont, :ok}
        else
          _ -> {:halt, {:error, {:protected_corrupt, "root_effects", :typed_transition_replay}}}
        end
      end)
      |> then(fn result ->
        if result == :ok and length(rows) != map_size(replay),
          do: {:error, {:protected_corrupt, "root_effects", :missing_typed_transition}},
          else: result
      end)
    end
  end

  defp validate_replay_closures(conn, closures) do
    with {:ok, rows} <-
           Database.query(conn, "SELECT ticket_id, attempt_id FROM root_attempt_closures") do
      if MapSet.new(rows, fn [ticket_id, attempt_id] -> {ticket_id, attempt_id} end) == closures,
        do: :ok,
        else: {:error, {:protected_corrupt, "root_attempt_closures", :typed_transition_replay}}
    end
  end

  defp validate_replay_claims(conn, replay) do
    with {:ok, rows} <-
           Database.query(
             conn,
             "SELECT claim_id, effect_id, writer_epoch, status, revision FROM root_claims"
           ) do
      values =
        Map.new(rows, fn row ->
          claim = claim_from_replay_row(row)
          {claim.claim_id, claim}
        end)

      if values == replay,
        do: :ok,
        else: {:error, {:protected_corrupt, "root_claims", :typed_transition_replay}}
    end
  end

  defp claim_from_replay_row([claim_id, effect_id, writer_epoch, status, revision]),
    do: %{
      claim_id: claim_id,
      effect_id: effect_id,
      writer_epoch: writer_epoch,
      status: status,
      revision: revision
    }

  defp validate_replay_reservations(conn, replay) do
    with {:ok, rows} <-
           Database.query(
             conn,
             "SELECT reservation_id, ledger_id, generation, dimension, owner_kind, owner_id, units, revision, status, claim_id FROM root_reservations"
           ) do
      values =
        Map.new(rows, fn row ->
          reservation = reservation_from_row(row)
          {reservation.reservation_id, reservation}
        end)

      if values == replay,
        do: :ok,
        else: {:error, {:protected_corrupt, "root_reservations", :typed_transition_replay}}
    end
  end

  defp validate_current_transition_provenance(conn) do
    with {:ok, rows} <-
           Database.query(
             conn,
             "SELECT seq, operation, disposition, canonical_request, result FROM root_commands ORDER BY seq"
           ),
         {:ok, snapshots} <- transition_snapshots(rows),
         :ok <- validate_current_ledger_snapshots(conn, snapshots.ledgers, rows),
         :ok <- validate_current_effect_snapshots(conn, snapshots.effects, rows),
         :ok <- validate_current_claim_snapshots(conn, snapshots.claims, rows) do
      :ok
    end
  end

  defp transition_snapshots(rows) do
    Enum.reduce_while(rows, {:ok, %{ledgers: %{}, effects: %{}, claims: %{}}}, fn
      [sequence, type, _disposition, _request, result_bytes], {:ok, acc} ->
        with {:ok, result} <- decode(result_bytes),
             {:ok, next} <-
               collect_typed_transition_snapshots(type, result["facts"], sequence, acc) do
          {:cont, {:ok, next}}
        else
          {:error, _reason} = error -> {:halt, error}
          _ -> {:halt, {:error, :invalid_transition_result}}
        end
    end)
  end

  # Results have an explicit operation schema. Only direct fact fields are authority
  # carriers; receipt payloads and other nested diagnostic/artifact maps are opaque.
  defp collect_typed_transition_snapshots(type, facts, sequence, acc) when is_map(facts) do
    schema =
      case type do
        "grant_ledger" ->
          %{"ledger" => {:singular, :ledger}}

        "delegate_allocation" ->
          %{"parent_ledger" => {:singular, :ledger}, "child_ledger" => {:singular, :ledger}}

        "return_allocation" ->
          %{"parent_ledger" => {:singular, :ledger}, "child_ledger" => {:singular, :ledger}}

        "reserve" ->
          %{"ledger" => {:singular, :ledger}, "reservation" => {:singular, :reservation}}

        "release_reservation" ->
          %{"ledger" => {:singular, :ledger}, "reservation" => {:singular, :reservation}}

        "close_generation" ->
          %{"ledgers" => {:plural, :ledger}}

        "reset_generation" ->
          %{
            "closed_generation" => {:singular, :ledger},
            "new_generation" => {:singular, :ledger},
            "parent_ledger" => {:singular, :ledger}
          }

        "create_effect" ->
          %{
            "effect" => {:singular, :effect},
            "reservations" => {:plural, :reservation},
            "ledgers" => {:plural, :ledger}
          }

        "claim_effect" ->
          %{"claim" => {:singular, :claim}, "effect" => {:singular, :effect}}

        "reclaim_claim" ->
          %{"claim" => {:singular, :claim}}

        "issue_claim" ->
          %{"claim" => {:singular, :claim}, "effect" => {:singular, :effect}}

        "cancel_effect" ->
          %{"claim" => {:singular, :claim}, "effect" => {:singular, :effect}}

        "settle_claim" ->
          %{
            "claim" => {:singular, :claim},
            "effect" => {:singular, :effect},
            "ledgers" => {:plural, :ledger}
          }

        _ ->
          %{}
      end

    known = Map.keys(schema)

    ignored =
      ~w(receipt attempted_receipt required_revisions lease_specs takeover transfer_kind control_status outstanding_claim_ids)

    with :ok <- validate_declared_transition_carriers(facts, schema),
         known_carriers <- known |> Enum.flat_map(&direct_transition_carriers(facts[&1])),
         :ok <-
           facts
           |> Map.drop(known ++ ignored)
           |> Map.values()
           |> Enum.flat_map(&direct_transition_carriers/1)
           |> Enum.reduce_while(:ok, fn carrier, :ok ->
             if carrier in known_carriers,
               do: {:cont, :ok},
               else: {:halt, {:error, :conflicting_typed_transition_carrier}}
           end) do
      known
      |> Enum.reduce_while({:ok, acc}, fn key, {:ok, nested} ->
        case collect_declared_transition_snapshots(facts[key], sequence, nested, schema[key]) do
          {:ok, next} -> {:cont, {:ok, next}}
          error -> {:halt, error}
        end
      end)
    end
  end

  defp collect_typed_transition_snapshots(_type, _facts, _sequence, _acc),
    do: {:error, :invalid_transition_facts}

  defp validate_declared_transition_carriers(facts, schema) do
    Enum.reduce_while(schema, :ok, fn {key, declaration}, :ok ->
      case Map.fetch(facts, key) do
        :error ->
          {:cont, :ok}

        {:ok, value} ->
          case validate_declared_transition_carrier(value, declaration) do
            :ok -> {:cont, :ok}
            error -> {:halt, error}
          end
      end
    end)
  end

  defp validate_declared_transition_carrier(value, {:singular, kind}) when is_map(value) do
    if transition_carrier_kind(value) == kind and declared_transition_shape?(value, kind),
      do: :ok,
      else: {:error, :invalid_singular_transition_carrier}
  end

  defp validate_declared_transition_carrier(_value, {:singular, _kind}),
    do: {:error, :invalid_singular_transition_carrier}

  defp validate_declared_transition_carrier(values, {:plural, kind}) when is_list(values) do
    with true <- Enum.all?(values, &(is_map(&1) and transition_carrier_kind(&1) == kind)),
         true <- Enum.all?(values, &declared_transition_shape?(&1, kind)),
         identities <- Enum.map(values, &transition_carrier_identity(&1, kind)),
         true <- Enum.all?(identities, &(not is_nil(&1))),
         true <- length(identities) == length(Enum.uniq(identities)) do
      :ok
    else
      _ -> {:error, :invalid_plural_transition_carrier}
    end
  end

  defp validate_declared_transition_carrier(_value, {:plural, _kind}),
    do: {:error, :invalid_plural_transition_carrier}

  defp declared_transition_shape?(value, :ledger),
    do:
      Map.keys(value) |> Enum.sort() ==
        Enum.sort(
          ~w(schema_version ledger_id generation parent_ledger_id parent_generation dimension revision status authorized available held consumed delegated retired)
        ) and value["schema_version"] == 1

  defp declared_transition_shape?(value, :reservation),
    do:
      Map.keys(value) |> Enum.sort() ==
        Enum.sort(
          ~w(schema_version reservation_id ledger_id generation dimension owner_kind owner_id units revision status claim_id)
        ) and value["schema_version"] == 1

  defp declared_transition_shape?(value, :claim),
    do:
      Map.keys(value) |> Enum.sort() ==
        Enum.sort(~w(schema_version claim_id effect_id writer_epoch status revision)) and
        value["schema_version"] == 1

  defp declared_transition_shape?(value, :effect),
    do:
      Map.keys(value) |> Enum.sort() ==
        Enum.sort(
          ~w(schema_version effect_id request_digest policy_id policy_revision control_id control_revision operation scope ticket_id attempt_id execution_id assignment_id role phase_generation operation_ordinal predecessor_effect_id request_id issuer channel profile deadline status revision reservation_ids lease_specs)
        ) and value["schema_version"] == 1

  defp transition_carrier_kind(%{"ledger_id" => _, "generation" => _, "authorized" => _}),
    do: :ledger

  defp transition_carrier_kind(%{"reservation_id" => _, "ledger_id" => _}), do: :reservation
  defp transition_carrier_kind(%{"claim_id" => _, "effect_id" => _}), do: :claim
  defp transition_carrier_kind(%{"effect_id" => _}), do: :effect
  defp transition_carrier_kind(_value), do: nil

  defp transition_carrier_identity(value, :ledger),
    do: {value["ledger_id"], value["generation"]}

  defp transition_carrier_identity(value, :reservation), do: value["reservation_id"]
  defp transition_carrier_identity(value, :claim), do: value["claim_id"]
  defp transition_carrier_identity(value, :effect), do: value["effect_id"]

  defp direct_transition_carriers(value) when is_map(value) do
    if transition_carrier?(value), do: [value], else: []
  end

  defp direct_transition_carriers(values) when is_list(values),
    do: Enum.filter(values, &transition_carrier?/1)

  defp direct_transition_carriers(_value), do: []

  defp transition_carrier?(value), do: not is_nil(transition_carrier_kind(value))

  defp collect_declared_transition_snapshots(nil, _sequence, acc, _declaration),
    do: {:ok, acc}

  defp collect_declared_transition_snapshots(value, sequence, acc, {:singular, _kind}),
    do: maybe_put_transition_snapshot(value, sequence, acc)

  defp collect_declared_transition_snapshots(values, sequence, acc, {:plural, _kind}) do
    Enum.reduce_while(values, {:ok, acc}, fn value, {:ok, nested} ->
      case maybe_put_transition_snapshot(value, sequence, nested) do
        {:ok, next} -> {:cont, {:ok, next}}
        error -> {:halt, error}
      end
    end)
  end

  defp maybe_put_transition_snapshot(
         %{"ledger_id" => id, "generation" => generation, "authorized" => _units} = fact,
         seq,
         acc
       )
       when is_binary(id) and is_integer(generation),
       do: put_transition_snapshot(acc, :ledgers, {id, generation}, fact, seq)

  defp maybe_put_transition_snapshot(%{"claim_id" => id, "effect_id" => _effect} = fact, seq, acc)
       when is_binary(id),
       do: put_transition_snapshot(acc, :claims, id, fact, seq)

  defp maybe_put_transition_snapshot(%{"effect_id" => id} = fact, seq, acc)
       when is_binary(id),
       do: put_transition_snapshot(acc, :effects, id, fact, seq)

  defp maybe_put_transition_snapshot(_fact, _seq, acc), do: {:ok, acc}

  defp put_transition_snapshot(acc, kind, key, fact, sequence) do
    revision = fact["revision"]
    current = get_in(acc, [kind, key])

    cond do
      not is_integer(revision) or revision < 0 ->
        {:error, :invalid_transition_revision}

      is_nil(current) or revision > current.fact["revision"] ->
        {:ok, put_in(acc, [kind, key], %{sequence: sequence, fact: fact})}

      revision == current.fact["revision"] and fact == current.fact ->
        {:ok, put_in(acc, [kind, key], %{sequence: sequence, fact: fact})}

      true ->
        {:error, {:conflicting_transition_result, kind, key}}
    end
  end

  defp validate_current_ledger_snapshots(conn, snapshots, rows) do
    with {:ok, ledger_rows} <-
           Database.query(
             conn,
             "SELECT ledger_id, generation, parent_ledger_id, parent_generation, dimension, revision, status, authorized, available, held, consumed, delegated, retired FROM root_ledgers"
           ) do
      Enum.reduce_while(ledger_rows, :ok, fn row, :ok ->
        current = public_ledger(ledger_from_row(row))

        case Map.get(snapshots, {current["ledger_id"], current["generation"]}) do
          %{sequence: sequence, fact: expected} ->
            valid =
              current == expected or
                (current["revision"] > expected["revision"] and
                   ledger_immutable_transition_fields(current) ==
                     ledger_immutable_transition_fields(expected) and
                   implicit_authority_transition_after?(conn, rows, sequence, current))

            if valid,
              do: {:cont, :ok},
              else: {:halt, {:error, {:protected_corrupt, "root_ledgers", :transition}}}

          _ ->
            {:halt, {:error, {:protected_corrupt, "root_ledgers", :missing_transition}}}
        end
      end)
    end
  end

  defp ledger_immutable_transition_fields(ledger),
    do:
      Map.take(
        ledger,
        ~w(schema_version ledger_id generation parent_ledger_id parent_generation dimension status authorized)
      )

  defp validate_current_effect_snapshots(conn, snapshots, rows) do
    with {:ok, effect_rows} <- Database.query(conn, "SELECT effect_id FROM root_effects") do
      Enum.reduce_while(effect_rows, :ok, fn [id], :ok ->
        with {:ok, effect} <- load_effect(conn, id),
             current <- public_effect(effect),
             %{sequence: sequence, fact: expected} <- Map.get(snapshots, id),
             true <-
               effect_transition_fields(current) == effect_transition_fields(expected) or
                 implicit_cancelled_snapshot?(conn, rows, sequence, effect, expected) do
          {:cont, :ok}
        else
          _ -> {:halt, {:error, {:protected_corrupt, "root_effects", :transition}}}
        end
      end)
    end
  end

  defp effect_transition_fields(effect),
    do: Map.take(effect, ~w(effect_id status revision))

  defp validate_current_claim_snapshots(conn, snapshots, rows) do
    with {:ok, claim_rows} <- Database.query(conn, "SELECT claim_id FROM root_claims") do
      Enum.reduce_while(claim_rows, :ok, fn [id], :ok ->
        with {:ok, claim} <- load_claim(conn, id),
             current <- public_claim(claim),
             %{sequence: sequence, fact: expected} <- Map.get(snapshots, id),
             true <-
               current == expected or
                 implicit_cancelled_claim_snapshot?(conn, rows, sequence, claim, expected) do
          {:cont, :ok}
        else
          _ -> {:halt, {:error, {:protected_corrupt, "root_claims", :transition}}}
        end
      end)
    end
  end

  defp implicit_cancelled_snapshot?(conn, rows, sequence, effect, expected) do
    effect.status == "cancelled" and effect.revision == expected["revision"] + 1 and
      implicit_authority_transition_after?(conn, rows, sequence, effect)
  end

  defp implicit_cancelled_claim_snapshot?(conn, rows, sequence, claim, expected) do
    with true <- claim.status == "cancelled" and claim.revision == expected["revision"] + 1,
         {:ok, effect} <- load_effect(conn, claim.effect_id) do
      implicit_authority_transition_after?(conn, rows, sequence, effect)
    else
      _ -> false
    end
  end

  defp implicit_authority_transition_after?(conn, rows, sequence, authority) do
    Enum.any?(rows, fn
      [seq, type, "accepted", request_bytes, _result] when seq > sequence ->
        with {:ok, %{"request" => %{"operation" => operation}}} <- decode(request_bytes) do
          case type do
            "set_control" ->
              operation["control_id"] == Map.get(authority, :control_id) and
                get_in(operation, ["value", "status"]) == "cancel_requested"

            type when type in ["close_generation", "reset_generation"] ->
              authority_in_generation?(conn, authority, operation)

            _ ->
              false
          end
        else
          _ -> false
        end

      _ ->
        false
    end)
  end

  defp authority_in_generation?(conn, %{effect_id: effect_id}, operation) do
    case reservations_for_effect(conn, effect_id) do
      {:ok, reservations} ->
        Enum.any?(reservations, &reservation_in_generation?(conn, &1, operation))

      _ ->
        false
    end
  end

  defp authority_in_generation?(conn, ledger, operation) do
    ledger_in_generation?(
      conn,
      ledger["ledger_id"],
      ledger["generation"],
      operation["ledger_id"],
      operation["generation"] || operation["old_generation"]
    )
  end

  defp reservation_in_generation?(conn, reservation, operation),
    do:
      ledger_in_generation?(
        conn,
        reservation.ledger_id,
        reservation.generation,
        operation["ledger_id"],
        operation["generation"] || operation["old_generation"]
      )

  defp ledger_in_generation?(_conn, ledger_id, generation, ledger_id, generation), do: true

  defp ledger_in_generation?(conn, ledger_id, generation, ancestor_id, ancestor_generation) do
    case load_existing_ledger(conn, ledger_id, generation) do
      {:ok, %{parent_ledger_id: parent, parent_generation: parent_generation}}
      when is_binary(parent) ->
        ledger_in_generation?(conn, parent, parent_generation, ancestor_id, ancestor_generation)

      _ ->
        false
    end
  end

  defp validate_reservation_command_provenance(conn) do
    with {:ok, command_rows} <-
           Database.query(
             conn,
             "SELECT canonical_request FROM root_commands WHERE operation = 'reserve' AND disposition = 'accepted' ORDER BY seq"
           ),
         {:ok, origins} <- reservation_origins(command_rows),
         {:ok, reservation_rows} <-
           Database.query(
             conn,
             "SELECT reservation_id, ledger_id, generation, dimension, owner_kind, owner_id, units, revision, status, claim_id FROM root_reservations"
           ) do
      Enum.reduce_while(reservation_rows, :ok, fn row, :ok ->
        reservation = reservation_from_row(row)

        with operation when is_map(operation) <- Map.get(origins, reservation.reservation_id),
             true <- reservation.ledger_id == operation["ledger_id"],
             true <- reservation.generation == operation["generation"],
             true <- reservation.owner_kind == operation["owner_kind"],
             true <- reservation.owner_id == operation["owner_id"],
             true <- reservation.units == operation["units"],
             :ok <- validate_reservation_transition_status(conn, reservation) do
          {:cont, :ok}
        else
          _ -> {:halt, {:error, {:protected_corrupt, "root_reservations", :transition}}}
        end
      end)
    end
  end

  defp reservation_origins(rows) do
    Enum.reduce_while(rows, {:ok, %{}}, fn [bytes], {:ok, acc} ->
      with {:ok, %{"request" => %{"operation" => %{"type" => "reserve"} = operation}}} <-
             decode(bytes),
           id when is_binary(id) <- operation["reservation_id"],
           false <- Map.has_key?(acc, id) do
        {:cont, {:ok, Map.put(acc, id, operation)}}
      else
        _ -> {:halt, {:error, :invalid_reservation_command_provenance}}
      end
    end)
  end

  defp validate_reservation_transition_status(conn, reservation) do
    if reservation.status in ["released", "retired"] and
         reservation_explicitly_released?(conn, reservation.reservation_id) do
      :ok
    else
      validate_reservation_owner_status(conn, reservation)
    end
  end

  defp validate_reservation_owner_status(conn, reservation) do
    case load_effect(conn, reservation.owner_id) do
      {:error, :not_found} ->
        if reservation.status == "proposed" and is_nil(reservation.claim_id),
          do: :ok,
          else: {:error, :invalid_reservation_transition}

      {:ok, effect} ->
        with {:ok, claims} <-
               Database.query(conn, "SELECT claim_id FROM root_claims WHERE effect_id = ?", [
                 effect.effect_id
               ]),
             claim_id <- if(claims == [], do: nil, else: claims |> hd() |> hd()),
             true <- reservation.claim_id == claim_id,
             true <- reservation.status in reservation_statuses(conn, effect, claim_id) do
          :ok
        else
          _ -> {:error, :invalid_reservation_transition}
        end

      _ ->
        {:error, :invalid_reservation_transition}
    end
  end

  defp reservation_explicitly_released?(conn, reservation_id) do
    case Database.query(
           conn,
           "SELECT canonical_request FROM root_commands WHERE operation = 'release_reservation' AND disposition = 'accepted' ORDER BY seq",
           []
         ) do
      {:ok, rows} ->
        Enum.any?(rows, fn [bytes] ->
          case decode(bytes) do
            {:ok, %{"request" => %{"operation" => operation}}} ->
              operation["reservation_id"] == reservation_id and operation["proof"] == "unissued"

            _ ->
              false
          end
        end)

      _ ->
        false
    end
  end

  defp reservation_statuses(_conn, %{status: "pending"}, nil), do: ["reserved"]

  defp reservation_statuses(_conn, %{status: "claimed"}, claim_id) when is_binary(claim_id),
    do: ["reserved"]

  defp reservation_statuses(_conn, %{status: status}, claim_id)
       when status in ["issued", "unknown"] and is_binary(claim_id),
       do: ["issued_unknown"]

  defp reservation_statuses(conn, %{status: "reconciliation_required"}, claim_id)
       when is_binary(claim_id) do
    case receipts_for_claim(conn, claim_id) do
      {:ok, receipts} ->
        cond do
          Enum.any?(receipts, &(&1.outcome in ["succeeded", "failed"])) -> ["consumed"]
          Enum.any?(receipts, &(&1.outcome == "non_started")) -> ["released", "retired"]
          true -> ["issued_unknown"]
        end

      _ ->
        []
    end
  end

  defp reservation_statuses(_conn, %{status: status}, claim_id)
       when status in ["succeeded", "failed"] and is_binary(claim_id),
       do: ["consumed"]

  defp reservation_statuses(_conn, %{status: "non_started"}, claim_id)
       when is_binary(claim_id),
       do: ["released", "retired"]

  defp reservation_statuses(_conn, %{status: "cancelled"}, _claim_id),
    do: ["released", "retired"]

  defp reservation_statuses(_conn, _effect, _claim_id), do: []

  defp validate_effect_authority_relations(conn) do
    with {:ok, rows} <-
           Database.query(conn, "SELECT effect_id FROM root_effects ORDER BY effect_id") do
      Enum.reduce_while(rows, :ok, fn [id], :ok ->
        with {:ok, effect} <- load_effect(conn, id),
             true <-
               effect.assignment_id ==
                 assignment_id(effect.ticket_id, effect.attempt_id, effect.role),
             true <- effect.scope == "ticket:" <> effect.ticket_id,
             {:ok, dimension} <- required_dimension(effect.operation, effect.role),
             {:ok, reservations} <- reservations_for_effect(conn, id),
             true <-
               Enum.map(reservations, & &1.reservation_id) == Enum.sort(effect.reservation_ids),
             true <- Enum.all?(reservations, &(&1.dimension == dimension and &1.owner_id == id)),
             :ok <- validate_effect_claim_owners(conn, effect, reservations) do
          {:cont, :ok}
        else
          _ -> {:halt, {:error, {:protected_corrupt, "root_effects", id}}}
        end
      end)
    end
  end

  defp validate_effect_claim_owners(conn, effect, reservations) do
    with {:ok, claims} <-
           Database.query(conn, "SELECT claim_id FROM root_claims WHERE effect_id = ?", [
             effect.effect_id
           ]),
         true <- length(claims) <= 1,
         claim_id <-
           (case claims do
              [[id]] -> id
              [] -> nil
            end),
         true <- Enum.all?(reservations, &(&1.claim_id == claim_id or is_nil(&1.claim_id))),
         {:ok, leases} <-
           Database.query(
             conn,
             "SELECT lease_id, resource_id FROM root_leases WHERE claim_id = ? ORDER BY lease_id",
             [claim_id || ""]
           ),
         expected_leases <-
           effect.lease_specs
           |> Enum.map(&[&1["lease_id"], &1["resource_id"]])
           |> Enum.sort(),
         true <- leases == [] or leases == expected_leases do
      :ok
    else
      _ -> {:error, :invalid_effect_owner_relation}
    end
  end

  defp validate_receipt_provenance(conn) do
    with {:ok, rows} <-
           Database.query(
             conn,
             "SELECT r.receipt_id, r.claim_id, r.request_id, r.outcome, r.receipt_digest, r.state, e.state FROM root_receipts r JOIN root_claims c ON c.claim_id = r.claim_id JOIN root_effects e ON e.effect_id = c.effect_id ORDER BY r.receipt_id"
           ) do
      Enum.reduce_while(rows, :ok, fn [id, claim, request, outcome, digest, bytes, effect_bytes],
                                      :ok ->
        with {:ok, effect_state} <- decode(effect_bytes),
             true <- request == effect_state["request_id"],
             {:ok, state} <- decode(bytes),
             true <- state["receipt_id"] == id and state["claim_id"] == claim,
             true <- state["request_id"] == request and state["outcome"] == outcome,
             true <- state["receipt_digest"] == digest,
             :ok <- settlement_proof(outcome, state["proof"]),
             {:ok, ^digest} <-
               Encoding.semantic_digest("pramana-foundry-root-receipt-v1", %{
                 "claim_id" => claim,
                 "request_id" => request,
                 "outcome" => outcome,
                 "proof" => state["proof"],
                 "payload" => state["payload"]
               }) do
          {:cont, :ok}
        else
          _ -> {:halt, {:error, {:protected_corrupt, "root_receipts", id}}}
        end
      end)
    end
  end

  defp validate_request_ownership(conn) do
    with {:ok, effect_rows} <- Database.query(conn, "SELECT effect_id FROM root_effects"),
         {:ok, request_ids} <-
           Enum.reduce_while(effect_rows, {:ok, []}, fn [id], {:ok, acc} ->
             case load_effect(conn, id) do
               {:ok, effect} -> {:cont, {:ok, [effect.request_id | acc]}}
               _ -> {:halt, {:error, :invalid_effect_request_owner}}
             end
           end),
         {:ok, conflicts} <-
           Database.query(
             conn,
             "SELECT request_id FROM root_receipts GROUP BY request_id HAVING count(DISTINCT claim_id) != 1"
           ) do
      if length(request_ids) == MapSet.size(MapSet.new(request_ids)) and conflicts == [],
        do: :ok,
        else: {:error, {:protected_corrupt, "root_receipts", :request_ownership}}
    end
  end

  defp validate_state_bindings(conn) do
    with :ok <- validate_reservation_states(conn),
         :ok <- validate_effect_states(conn),
         :ok <- validate_claim_states(conn),
         :ok <- validate_receipt_states(conn),
         :ok <- validate_lease_states(conn) do
      :ok
    end
  end

  defp validate_reservation_states(conn) do
    with {:ok, rows} <-
           Database.query(
             conn,
             "SELECT reservation_id, ledger_id, generation, dimension, owner_kind, owner_id, units, revision, status, claim_id, state FROM root_reservations"
           ) do
      validate_encoded_rows(rows, "root_reservations", fn row ->
        {columns, [bytes]} = Enum.split(row, 10)
        {public_reservation(reservation_from_row(columns)), bytes}
      end)
    end
  end

  defp validate_effect_states(conn) do
    with {:ok, rows} <- Database.query(conn, "SELECT effect_id, state FROM root_effects") do
      validate_encoded_rows(rows, "root_effects", fn [id, bytes] ->
        {:ok, effect} = load_effect(conn, id)
        {public_effect(effect), bytes}
      end)
    end
  end

  defp validate_claim_states(conn) do
    with {:ok, rows} <- Database.query(conn, "SELECT claim_id, state FROM root_claims") do
      validate_encoded_rows(rows, "root_claims", fn [id, bytes] ->
        {:ok, claim} = load_claim(conn, id)
        {public_claim(claim), bytes}
      end)
    end
  end

  defp validate_receipt_states(conn) do
    with {:ok, rows} <-
           Database.query(
             conn,
             "SELECT receipt_id, claim_id, request_id, outcome, receipt_digest, state FROM root_receipts"
           ) do
      validate_encoded_rows(rows, "root_receipts", fn [id, claim, request, outcome, digest, bytes] ->
        {:ok, state} = decode(bytes)

        expected =
          state
          |> Map.put("receipt_id", id)
          |> Map.put("claim_id", claim)
          |> Map.put("request_id", request)
          |> Map.put("outcome", outcome)
          |> Map.put("receipt_digest", digest)

        {expected, bytes}
      end)
    end
  end

  defp validate_lease_states(conn) do
    with {:ok, rows} <-
           Database.query(
             conn,
             "SELECT lease_id, claim_id, resource_id, status, revision, state FROM root_leases"
           ) do
      validate_encoded_rows(rows, "root_leases", fn [id, claim, resource, status, revision, bytes] ->
        {%{
           "schema_version" => 1,
           "lease_id" => id,
           "claim_id" => claim,
           "resource_id" => resource,
           "status" => status,
           "revision" => revision
         }, bytes}
      end)
    end
  end

  defp validate_encoded_rows(rows, table, mapper) do
    Enum.reduce_while(rows, :ok, fn row, :ok ->
      try do
        {expected, bytes} = mapper.(row)

        case encode(expected) do
          {:ok, ^bytes} -> {:cont, :ok}
          _ -> {:halt, {:error, {:protected_corrupt, table, :column_state_mismatch}}}
        end
      rescue
        _ -> {:halt, {:error, {:protected_corrupt, table, :invalid_state_binding}}}
      end
    end)
  end

  defp encode(value), do: Encoding.json(value)

  defp decode(bytes) when is_binary(bytes) do
    try do
      case :json.decode(bytes) do
        value when is_map(value) -> {:ok, normalize_decoded(value)}
        _ -> {:error, :invalid_protected_record}
      end
    rescue
      _ -> {:error, :invalid_protected_record}
    end
  end

  defp decode(_bytes), do: {:error, :invalid_protected_record}

  defp normalize_decoded(:null), do: nil
  defp normalize_decoded(value) when is_list(value), do: Enum.map(value, &normalize_decoded/1)

  defp normalize_decoded(value) when is_map(value),
    do: Map.new(value, fn {key, item} -> {key, normalize_decoded(item)} end)

  defp normalize_decoded(value), do: value

  defp string_map(value) when is_map(value) and not is_struct(value) do
    Enum.reduce_while(value, {:ok, %{}}, fn {key, item}, {:ok, acc} ->
      normalized_key = if is_atom(key), do: Atom.to_string(key), else: key

      if is_binary(normalized_key) and not Map.has_key?(acc, normalized_key) do
        {:cont, {:ok, Map.put(acc, normalized_key, item)}}
      else
        {:halt, {:error, :invalid_or_duplicate_key}}
      end
    end)
  end

  defp string_map(_value), do: {:error, :not_a_map}

  defp exact_keys(map, expected) do
    if Enum.sort(Map.keys(map)) == Enum.sort(expected), do: :ok, else: {:error, :invalid_fields}
  end

  defp identities(map, keys) do
    Enum.reduce_while(keys, :ok, fn key, :ok ->
      case identity(map[key]) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp identity(value) when is_binary(value) and value != "" do
    if String.valid?(value), do: :ok, else: {:error, :invalid_identity}
  end

  defp identity(_value), do: {:error, :invalid_identity}

  defp plain_map?(value), do: is_map(value) and not is_struct(value) and plain_value?(value)

  defp plain_value?(value)
       when is_binary(value) or is_integer(value) or is_boolean(value) or is_nil(value),
       do: true

  defp plain_value?(value) when is_list(value),
    do: proper_list?(value) and Enum.all?(value, &plain_value?/1)

  defp plain_value?(value) when is_map(value) and not is_struct(value),
    do: Enum.all?(value, fn {key, item} -> is_binary(key) and plain_value?(item) end)

  defp plain_value?(_value), do: false

  defp proper_list?(value) do
    _ = length(value)
    true
  rescue
    ArgumentError -> false
  end
end
