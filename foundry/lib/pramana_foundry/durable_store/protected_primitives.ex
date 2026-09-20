defmodule PramanaFoundry.DurableStore.ProtectedPrimitives do
  @moduledoc false

  alias PramanaFoundry.DurableStore.{Database, Encoding}

  @dimensions ~w(starts.pm starts.developer starts.reviewer starts.check starts.build operations.integration operations.activation model_requests validations)
  @operation_types ~w(set_policy set_control append_inbox seal_inbox grant_ledger delegate_allocation return_allocation reserve release_reservation close_generation reset_generation create_effect claim_effect issue_claim cancel_effect settle_claim)

  @doc false
  def execute(conn, actor_id, request) do
    with :ok <- identity(actor_id),
         {:ok, request} <- normalize_request(request),
         {:ok, digest} <- request_digest(actor_id, request) do
      case existing_command(conn, request["command_id"], actor_id, digest) do
        {:ok, result} ->
          {:ok, result, :idempotent}

        {:error, :not_found} ->
          Database.transaction(conn, fn ->
            case apply_new(conn, actor_id, request) do
              {:ok, facts} ->
                persist_result(conn, actor_id, request, digest, "accepted", nil, facts)

              {:reject, reason, facts} ->
                persist_result(
                  conn,
                  actor_id,
                  request,
                  digest,
                  "rejected",
                  Atom.to_string(reason),
                  facts
                )

              {:error, _reason} = error ->
                error
            end
          end)
          |> case do
            {:ok, result} -> {:ok, result, :committed}
            {:error, reason} -> {:error, {:storage_unavailable, reason}}
          end

        {:error, _reason} = error ->
          error
      end
    end
  end

  @doc false
  def query(conn, query) do
    with {:ok, query} <- string_map(query),
         1 <- query["schema_version"],
         type when is_binary(type) <- query["type"] do
      case type do
        "inbox" -> inbox_fact(conn, query["execution_id"])
        "policy" -> simple_fact(conn, "root_policies", "policy_id", query["policy_id"])
        "control" -> simple_fact(conn, "root_controls", "control_id", query["control_id"])
        "ledger" -> ledger_fact(conn, query["ledger_id"], query["generation"])
        "effect" -> effect_fact(conn, query["effect_id"])
        "claim" -> claim_fact(conn, query["claim_id"])
        "reservation" -> reservation_fact(conn, query["reservation_id"])
        "receipt" -> receipt_fact(conn, query["receipt_id"])
        "lease" -> lease_fact(conn, query["lease_id"])
        "command" -> command_fact(conn, query["command_id"])
        "pointer" -> pointer_fact(conn, query["pointer_kind"])
        _ -> {:error, :unsupported_protected_query}
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
         :ok <- validate_root_commands(conn),
         :ok <- validate_simple_history(conn),
         :ok <- validate_inboxes(conn),
         :ok <- validate_ledgers(conn),
         :ok <- validate_ledger_tree(conn),
         :ok <- validate_reservations(conn),
         :ok <- validate_effect_relations(conn) do
      :ok
    end
  end

  defp apply_new(conn, actor_id, request) do
    operation = request["operation"]

    with :ok <- complete_read_set(conn, operation, request["expected_revisions"]) do
      operation =
        case operation["type"] do
          type when type in ["append_inbox", "seal_inbox"] ->
            Map.put(operation, "authenticated_actor", actor_id)

          type when type in ["set_policy", "set_control"] ->
            Map.put(operation, "root_command_id", request["command_id"])

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

  defp apply_operation(conn, %{"type" => "set_policy"} = operation) do
    upsert_simple_root(conn, "root_policies", "policy_id", operation["policy_id"], operation)
  end

  defp apply_operation(conn, %{"type" => "set_control"} = operation) do
    upsert_simple_root(conn, "root_controls", "control_id", operation["control_id"], operation)
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

      {:error, reason} when reason in [:inbox_sequence_conflict] ->
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
           status: "reserved",
           claim_id: nil
         },
         next_ledger <- %{
           ledger
           | revision: ledger.revision + 1,
             available: ledger.available - units,
             held: ledger.held + units
         },
         :ok <- update_ledger(conn, ledger, next_ledger),
         :ok <- insert_reservation(conn, reservation) do
      {:ok,
       %{
         "ledger" => public_ledger(next_ledger),
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
         true <- reservation.status in ["reserved", "issued_unknown"],
         :ok <- release_guard(conn, reservation),
         {:ok, ledger} <-
           load_existing_ledger(conn, reservation.ledger_id, reservation.generation),
         target <- if(ledger.status == "open", do: "released", else: "retired"),
         next_reservation <- %{
           reservation
           | revision: reservation.revision + 1,
             status: target
         },
         next_ledger <- release_hold(ledger, reservation.units),
         :ok <- update_reservation(conn, reservation, next_reservation),
         :ok <- update_ledger(conn, ledger, next_ledger) do
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
         {:ok, ledger} <-
           load_existing_ledger(conn, operation["ledger_id"], operation["generation"]),
         "open" <- ledger.status,
         next <- %{
           ledger
           | revision: ledger.revision + 1,
             status: "closed",
             retired: ledger.retired + ledger.available,
             available: 0
         },
         :ok <- update_ledger(conn, ledger, next) do
      {:ok, %{"ledger" => public_ledger(next)}}
    else
      {:error, :not_found} -> {:reject, :ledger_not_found, %{}}
      {:error, _reason} = error -> error
      _ -> {:reject, :generation_already_closed, %{}}
    end
  end

  defp apply_operation(conn, %{"type" => "reset_generation"} = operation) do
    keys =
      ~w(type ledger_id old_generation new_generation parent_ledger_id parent_generation units)

    with :ok <- exact_keys(operation, keys),
         {:ok, old} <-
           load_existing_ledger(conn, operation["ledger_id"], operation["old_generation"]),
         "open" <- old.status,
         true <- old.parent_ledger_id == operation["parent_ledger_id"],
         true <- old.parent_generation == operation["parent_generation"],
         {:ok, parent} <-
           load_existing_ledger(conn, old.parent_ledger_id, old.parent_generation),
         "open" <- parent.status,
         units when is_integer(units) and units >= 0 and units <= parent.available <-
           operation["units"],
         {:ok, :absent} <-
           load_ledger(conn, operation["ledger_id"], operation["new_generation"]),
         :ok <- revoke_unissued_generation(conn, old),
         {:ok, old} <- load_existing_ledger(conn, old.ledger_id, old.generation),
         closed <- %{
           old
           | revision: old.revision + 1,
             status: "closed",
             retired: old.retired + old.available,
             available: 0
         },
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
         :ok <- update_ledger(conn, old, closed),
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
      ~w(type effect_id request operation scope ticket_id attempt_id execution_id policy_id policy_revision control_id control_revision reservation_ids leases)

    with :ok <- exact_keys(operation, keys),
         :ok <-
           identities(
             operation,
             ~w(effect_id operation scope ticket_id attempt_id execution_id policy_id control_id)
           ),
         true <- plain_map?(operation["request"]),
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
         :ok <- semantic_effect_available(conn, operation),
         {:ok, reservations} <- load_effect_reservations(conn, operation),
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
           status: "pending",
           revision: 0,
           reservation_ids: Enum.map(reservations, & &1.reservation_id)
         },
         :ok <- insert_effect(conn, effect),
         :ok <- insert_pending_leases(conn, operation["effect_id"], lease_specs) do
      {:ok,
       %{
         "effect" => public_effect(effect),
         "reservation_ids" => effect.reservation_ids,
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
             :lease_conflict,
             :duplicate_semantic_operation
           ] ->
        {:reject, reason, %{}}

      {:error, _reason} = error ->
        error

      _ ->
        {:reject, :invalid_effect_request, %{}}
    end
  end

  defp apply_operation(conn, %{"type" => "claim_effect"} = operation) do
    with :ok <- exact_keys(operation, ~w(type effect_id claim_id writer_epoch)),
         :ok <- identities(operation, ~w(effect_id claim_id writer_epoch)),
         {:ok, effect} <- load_effect(conn, operation["effect_id"]),
         "pending" <- effect.status,
         {:ok, reservations} <- reservations_for_effect(conn, effect.effect_id),
         true <- reservations != [],
         true <- Enum.all?(reservations, &(&1.status == "reserved" and is_nil(&1.claim_id))),
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
      {:error, :not_found} -> {:reject, :effect_not_found, %{}}
      {:error, _reason} = error -> error
      _ -> {:reject, :claim_not_permitted, %{}}
    end
  end

  defp apply_operation(conn, %{"type" => "issue_claim"} = operation) do
    with :ok <- exact_keys(operation, ~w(type claim_id writer_epoch)),
         {:ok, claim} <- load_claim(conn, operation["claim_id"]),
         "claimed" <- claim.status,
         true <- claim.writer_epoch == operation["writer_epoch"],
         {:ok, effect} <- load_effect(conn, claim.effect_id),
         "claimed" <- effect.status,
         {:ok, policy} <- load_simple(conn, "root_policies", "policy_id", effect.policy_id),
         {:ok, control} <- load_simple(conn, "root_controls", "control_id", effect.control_id),
         true <- policy.revision == effect.policy_revision,
         true <- control.revision == effect.control_revision,
         :ok <- control_active?(control.value),
         {:ok, reservations} <- reservations_for_claim(conn, claim.claim_id),
         true <- reservations != [] and Enum.all?(reservations, &(&1.status == "reserved")),
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
      {:error, :not_found} -> {:reject, :claim_not_found, %{}}
      {:error, :control_not_active} -> {:reject, :control_not_active, %{}}
      {:error, _reason} = error -> error
      _ -> {:reject, :claim_issue_not_permitted, %{}}
    end
  end

  defp apply_operation(conn, %{"type" => "settle_claim"} = operation) do
    keys = ~w(type claim_id receipt_id request_id outcome proof payload)

    with :ok <- exact_keys(operation, keys),
         :ok <- identities(operation, ~w(claim_id receipt_id request_id outcome proof)),
         true <- operation["outcome"] in ~w(succeeded failed non_started unknown),
         true <- operation["proof"] in ~w(delivered issuer_quiescent outcome_unknown),
         true <- plain_value?(operation["payload"]),
         {:ok, claim} <- load_claim(conn, operation["claim_id"]),
         {:ok, effect} <- load_effect(conn, claim.effect_id),
         {:ok, digest} <- receipt_digest(operation),
         {:ok, prior_receipts} <- receipts_for_claim(conn, claim.claim_id) do
      settle_with_receipts(conn, operation, digest, claim, effect, prior_receipts)
    else
      {:error, :not_found} -> {:reject, :claim_not_found, %{}}
      {:error, _reason} = error -> error
      _ -> {:reject, :invalid_claim_settlement, %{}}
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

  defp apply_operation(_conn, _operation), do: {:reject, :unsupported_operation, %{}}

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

      receipts != [] ->
        if operation["outcome"] != "unknown" and
             Enum.all?(receipts, &(&1.outcome == "unknown")) do
          reconciled_settlement(conn, operation, digest, claim, effect)
        else
          quarantine_conflicting_receipt(conn, operation, digest, claim, effect)
        end

      true ->
        first_settlement(conn, operation, digest, claim, effect)
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
      {:reject, :conflicting_receipt,
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

  defp operation_read_keys(_conn, "set_control", op),
    do: {:ok, ["control/" <> to_string(op["control_id"])]}

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

  defp operation_read_keys(_conn, "close_generation", op),
    do: {:ok, [ledger_key(op["ledger_id"], op["generation"])]}

  defp operation_read_keys(_conn, "reset_generation", op),
    do:
      {:ok,
       [
         ledger_key(op["ledger_id"], op["old_generation"]),
         ledger_key(op["ledger_id"], op["new_generation"]),
         ledger_key(op["parent_ledger_id"], op["parent_generation"])
       ]}

  defp operation_read_keys(conn, "create_effect", op) do
    base = [
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

    {:ok,
     Enum.uniq([
       "effect/" <> to_string(op["effect_id"]),
       "claim/" <> to_string(op["claim_id"])
       | reservations
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

  defp operation_read_keys(conn, type, op) when type in ["issue_claim", "settle_claim"] do
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
              ] ++ Enum.map(effect.lease_specs, &("lease/" <> &1["lease_id"]))

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

  defp operation_read_keys(_conn, _type, _op), do: {:ok, []}

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

  defp current_revision(_conn, _key), do: {:error, :invalid_read_set_key}

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
    result = %{
      "schema_version" => 1,
      "command_id" => request["command_id"],
      "disposition" => disposition,
      "reason_code" => reason,
      "facts" => facts
    }

    with {:ok, canonical_request} <-
           encode(%{"actor_id" => actor_id, "schema_version" => 1, "request" => request}),
         {:ok, bytes} <- encode(result),
         {:ok, [[next_seq]]} <-
           Database.query(conn, "SELECT coalesce(max(seq), 0) + 1 FROM root_commands"),
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
         true <- operation["operation"] in operations,
         true <- operation["scope"] in scopes do
      :ok
    else
      {:error, _reason} = error -> error
      _ -> {:error, :effect_not_allowed}
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
               reservation.status == "reserved" and is_nil(reservation.claim_id) ->
          {:cont, {:ok, [reservation | acc]}}

        {:ok, %{status: status}} when status != "reserved" ->
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

  defp semantic_effect_available(conn, operation) do
    with {:ok, rows} <-
           Database.query(
             conn,
             "SELECT effect_id FROM root_effects WHERE execution_id = ? AND operation = ? AND status IN ('pending', 'claimed', 'issued', 'unknown', 'reconciliation_required')",
             [operation["execution_id"], operation["operation"]]
           ) do
      if rows == [], do: :ok, else: {:error, :duplicate_semantic_operation}
    end
  end

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
        "UPDATE root_claims SET status = ?, revision = ?, state = ? WHERE claim_id = ? AND revision = ?",
        [next.status, next.revision, {:blob, bytes}, old.claim_id, old.revision]
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
    with {:ok, rows} <-
           Database.query(
             conn,
             "SELECT receipt_id, claim_id, request_id, outcome, receipt_digest, state FROM root_receipts WHERE claim_id = ? ORDER BY receipt_id",
             [claim_id]
           ) do
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
             "SELECT command_id, actor_id, request_digest, canonical_request, operation, disposition, reason_code, result FROM root_commands ORDER BY seq"
           ) do
      Enum.reduce_while(rows, :ok, fn
        [
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
          "SELECT h.#{id_column}, h.revision, h.prior_revision, h.state, x.revision, x.state FROM #{history_table} h JOIN #{head_table} x ON x.#{id_column} = h.#{id_column} WHERE h.revision = (SELECT max(h2.revision) FROM #{history_table} h2 WHERE h2.#{id_column} = h.#{id_column})"

        case Database.query(conn, sql) do
          {:ok, rows} ->
            if Enum.all?(rows, fn [_id, revision, prior, history, head_revision, head] ->
                 revision == head_revision and history == head and
                   ((revision == 0 and is_nil(prior)) or prior == revision - 1)
               end),
               do: {:cont, :ok},
               else: {:halt, {:error, {:protected_corrupt, history_table, :lineage}}}

          {:error, _reason} = error ->
            {:halt, error}
        end
      end
    )
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

  defp validate_inboxes(conn) do
    with {:ok, heads} <-
           Database.query(
             conn,
             "SELECT execution_id, last_sequence, sealed_sequence FROM authenticated_inboxes"
           ) do
      Enum.reduce_while(heads, :ok, fn [id, last, sealed], :ok ->
        case Database.query(
               conn,
               "SELECT count(*), coalesce(min(sequence), 0), coalesce(max(sequence), 0) FROM authenticated_inbox_items WHERE execution_id = ?",
               [id]
             ) do
          {:ok, [[count, minimum, maximum]]}
          when count == last and
                 ((count == 0 and minimum == 0 and maximum == 0) or
                    (minimum == 1 and maximum == last)) and
                 (is_nil(sealed) or sealed <= last) ->
            {:cont, :ok}

          _ ->
            {:halt, {:error, {:protected_corrupt, "authenticated_inboxes", id}}}
        end
      end)
    end
  end

  defp validate_ledgers(conn) do
    with {:ok, rows} <-
           Database.query(
             conn,
             "SELECT ledger_id, generation, parent_ledger_id, parent_generation, dimension, revision, status, authorized, available, held, consumed, delegated, retired FROM root_ledgers"
           ) do
      Enum.reduce_while(rows, :ok, fn row, :ok ->
        ledger = ledger_from_row(row)

        if conserved?(ledger) and ledger.dimension in @dimensions do
          {:cont, :ok}
        else
          {:halt, {:error, {:protected_corrupt, "root_ledgers", ledger.ledger_id}}}
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
             "SELECT ledger_id, generation, coalesce(sum(CASE WHEN status IN ('reserved', 'issued_unknown') THEN units ELSE 0 END), 0), coalesce(sum(CASE WHEN status = 'consumed' THEN units ELSE 0 END), 0) FROM root_reservations GROUP BY ledger_id, generation"
           ) do
      Enum.reduce_while(rows, :ok, fn [id, generation, held, consumed], :ok ->
        case load_existing_ledger(conn, id, generation) do
          {:ok, ledger} when ledger.held == held and ledger.consumed >= consumed -> {:cont, :ok}
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
