defmodule PramanaFoundry.DurableStore.Database do
  @moduledoc false

  alias Exqlite.Sqlite3
  alias PramanaFoundry.DurableStore.{Authority, PathIdentity}

  @schema_version 1

  # FR-08A evolves the protected authority schema independently from the v1 domain
  # command/event protocol.  The migration is additive so accepted FR-07 history is
  # never rewritten merely to gain protected lifecycle primitives.
  @protected_schema_version 2

  @atomic_bundle_schema """
  CREATE TABLE IF NOT EXISTS atomic_bundles (
    command_id TEXT PRIMARY KEY REFERENCES commands(command_id),
    actor_id TEXT NOT NULL,
    request_digest TEXT NOT NULL,
    schema_version INTEGER NOT NULL CHECK (schema_version = 2),
    disposition TEXT NOT NULL CHECK (disposition IN ('accepted', 'rejected', 'quarantined')),
    reason_code TEXT,
    canonical_envelope BLOB NOT NULL,
    result BLOB NOT NULL,
    UNIQUE(command_id, actor_id, request_digest)
  ) STRICT;
  CREATE TABLE IF NOT EXISTS durable_operations (
    owner_kind TEXT NOT NULL CHECK (owner_kind IN ('domain_v1', 'protected_v1', 'bundle_v2')),
    owner_id TEXT NOT NULL,
    ordinal INTEGER NOT NULL CHECK (ordinal >= 0),
    operation_kind TEXT NOT NULL CHECK (operation_kind IN ('domain', 'protected')),
    operation_type TEXT NOT NULL,
    request BLOB NOT NULL,
    result BLOB NOT NULL,
    PRIMARY KEY(owner_kind, owner_id, ordinal)
  ) STRICT;
  CREATE TABLE IF NOT EXISTS root_infrastructure_settlements (
    effect_id TEXT PRIMARY KEY REFERENCES root_effects(effect_id),
    claim_id TEXT NOT NULL UNIQUE REFERENCES root_claims(claim_id),
    receipt_id TEXT NOT NULL UNIQUE REFERENCES root_receipts(receipt_id),
    role TEXT NOT NULL,
    work_owner TEXT NOT NULL,
    infrastructure_generation INTEGER NOT NULL CHECK (infrastructure_generation >= 0),
    predecessor_effect_id TEXT,
    failure_class TEXT NOT NULL,
    ordinal INTEGER NOT NULL CHECK (ordinal > 0),
    state BLOB NOT NULL
  ) STRICT;
  """

  @protected_schema """
  CREATE TABLE IF NOT EXISTS root_commands (
    seq INTEGER PRIMARY KEY,
    command_id TEXT NOT NULL UNIQUE,
    actor_id TEXT NOT NULL,
    request_digest TEXT NOT NULL,
    canonical_request BLOB NOT NULL,
    schema_version INTEGER NOT NULL CHECK (schema_version = 1),
    operation TEXT NOT NULL,
    disposition TEXT NOT NULL CHECK (disposition IN ('accepted', 'rejected')),
    reason_code TEXT,
    result BLOB NOT NULL,
    UNIQUE(command_id, actor_id, request_digest)
  ) STRICT;
  CREATE TABLE IF NOT EXISTS authenticated_inboxes (
    execution_id TEXT PRIMARY KEY,
    actor_id TEXT NOT NULL,
    revision INTEGER NOT NULL CHECK (revision >= 0),
    last_sequence INTEGER NOT NULL CHECK (last_sequence >= 0),
    sealed_sequence INTEGER CHECK (sealed_sequence IS NULL OR sealed_sequence >= 0),
    state BLOB NOT NULL,
    CHECK (sealed_sequence IS NULL OR sealed_sequence <= last_sequence)
  ) STRICT;
  CREATE TABLE IF NOT EXISTS authenticated_inbox_items (
    execution_id TEXT NOT NULL REFERENCES authenticated_inboxes(execution_id),
    sequence INTEGER NOT NULL CHECK (sequence > 0),
    item_kind TEXT NOT NULL CHECK (item_kind IN ('result', 'exit', 'observation')),
    disposition TEXT NOT NULL CHECK (disposition IN ('accepted', 'late')),
    item_digest TEXT NOT NULL,
    item BLOB NOT NULL,
    PRIMARY KEY(execution_id, sequence),
    UNIQUE(execution_id, item_digest)
  ) STRICT;
  CREATE TABLE IF NOT EXISTS root_policies (
    policy_id TEXT PRIMARY KEY,
    revision INTEGER NOT NULL CHECK (revision >= 0),
    state BLOB NOT NULL
  ) STRICT;
  CREATE TABLE IF NOT EXISTS root_policy_history (
    policy_id TEXT NOT NULL,
    revision INTEGER NOT NULL CHECK (revision >= 0),
    prior_revision INTEGER,
    command_id TEXT NOT NULL REFERENCES root_commands(command_id) DEFERRABLE INITIALLY DEFERRED,
    state BLOB NOT NULL,
    PRIMARY KEY(policy_id, revision),
    CHECK ((revision = 0 AND prior_revision IS NULL) OR prior_revision = revision - 1)
  ) STRICT;
  CREATE TABLE IF NOT EXISTS root_controls (
    control_id TEXT PRIMARY KEY,
    revision INTEGER NOT NULL CHECK (revision >= 0),
    state BLOB NOT NULL
  ) STRICT;
  CREATE TABLE IF NOT EXISTS root_control_history (
    control_id TEXT NOT NULL,
    revision INTEGER NOT NULL CHECK (revision >= 0),
    prior_revision INTEGER,
    command_id TEXT NOT NULL REFERENCES root_commands(command_id) DEFERRABLE INITIALLY DEFERRED,
    state BLOB NOT NULL,
    PRIMARY KEY(control_id, revision),
    CHECK ((revision = 0 AND prior_revision IS NULL) OR prior_revision = revision - 1)
  ) STRICT;
  CREATE TABLE IF NOT EXISTS root_ledgers (
    ledger_id TEXT NOT NULL,
    generation INTEGER NOT NULL CHECK (generation >= 0),
    parent_ledger_id TEXT,
    parent_generation INTEGER,
    dimension TEXT NOT NULL,
    revision INTEGER NOT NULL CHECK (revision >= 0),
    status TEXT NOT NULL CHECK (status IN ('open', 'closed')),
    authorized INTEGER NOT NULL CHECK (authorized >= 0),
    available INTEGER NOT NULL CHECK (available >= 0),
    held INTEGER NOT NULL CHECK (held >= 0),
    consumed INTEGER NOT NULL CHECK (consumed >= 0),
    delegated INTEGER NOT NULL CHECK (delegated >= 0),
    retired INTEGER NOT NULL CHECK (retired >= 0),
    state BLOB NOT NULL,
    PRIMARY KEY(ledger_id, generation),
    UNIQUE(ledger_id, generation, dimension),
    FOREIGN KEY(parent_ledger_id, parent_generation, dimension)
      REFERENCES root_ledgers(ledger_id, generation, dimension),
    CHECK ((parent_ledger_id IS NULL) = (parent_generation IS NULL)),
    CHECK (authorized = available + held + consumed + delegated + retired)
  ) STRICT;
  CREATE TABLE IF NOT EXISTS root_reservations (
    reservation_id TEXT PRIMARY KEY,
    ledger_id TEXT NOT NULL,
    generation INTEGER NOT NULL,
    dimension TEXT NOT NULL,
    owner_kind TEXT NOT NULL,
    owner_id TEXT NOT NULL,
    units INTEGER NOT NULL CHECK (units > 0),
    revision INTEGER NOT NULL CHECK (revision >= 0),
    status TEXT NOT NULL CHECK (status IN ('proposed', 'reserved', 'issued_unknown', 'consumed', 'released', 'retired')),
    claim_id TEXT,
    state BLOB NOT NULL,
    FOREIGN KEY(ledger_id, generation, dimension) REFERENCES root_ledgers(ledger_id, generation, dimension),
    FOREIGN KEY(claim_id) REFERENCES root_claims(claim_id)
  ) STRICT;
  CREATE TABLE IF NOT EXISTS root_effects (
    effect_id TEXT PRIMARY KEY,
    request_digest TEXT NOT NULL,
    policy_id TEXT NOT NULL REFERENCES root_policies(policy_id),
    policy_revision INTEGER NOT NULL CHECK (policy_revision >= 0),
    control_id TEXT NOT NULL REFERENCES root_controls(control_id),
    control_revision INTEGER NOT NULL CHECK (control_revision >= 0),
    operation TEXT NOT NULL,
    scope TEXT NOT NULL,
    ticket_id TEXT NOT NULL,
    attempt_id TEXT NOT NULL,
    execution_id TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('pending', 'claimed', 'issued', 'unknown', 'succeeded', 'failed', 'non_started', 'cancelled', 'reconciliation_required')),
    revision INTEGER NOT NULL CHECK (revision >= 0),
    state BLOB NOT NULL
  ) STRICT;
  CREATE TABLE IF NOT EXISTS root_claims (
    claim_id TEXT PRIMARY KEY,
    effect_id TEXT NOT NULL REFERENCES root_effects(effect_id),
    writer_epoch TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('claimed', 'issued', 'unknown', 'succeeded', 'failed', 'non_started', 'cancelled', 'reconciliation_required')),
    revision INTEGER NOT NULL CHECK (revision >= 0),
    state BLOB NOT NULL
  ) STRICT;
  CREATE UNIQUE INDEX IF NOT EXISTS root_one_live_claim_per_effect
    ON root_claims(effect_id)
    WHERE status IN ('claimed', 'issued', 'unknown');
  CREATE TABLE IF NOT EXISTS root_receipts (
    receipt_id TEXT PRIMARY KEY,
    claim_id TEXT NOT NULL REFERENCES root_claims(claim_id),
    request_id TEXT NOT NULL,
    outcome TEXT NOT NULL CHECK (outcome IN ('succeeded', 'failed', 'non_started', 'unknown')),
    receipt_digest TEXT NOT NULL,
    state BLOB NOT NULL,
    UNIQUE(claim_id, receipt_digest)
  ) STRICT;
  CREATE TABLE IF NOT EXISTS root_leases (
    lease_id TEXT PRIMARY KEY,
    claim_id TEXT NOT NULL REFERENCES root_claims(claim_id),
    resource_id TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('held', 'released', 'retained')),
    revision INTEGER NOT NULL CHECK (revision >= 0),
    state BLOB NOT NULL
  ) STRICT;
  CREATE UNIQUE INDEX IF NOT EXISTS root_one_active_lease_per_resource
    ON root_leases(resource_id)
    WHERE status IN ('held', 'retained');
  CREATE TABLE IF NOT EXISTS root_pointers (
    pointer_kind TEXT PRIMARY KEY CHECK (pointer_kind IN ('accepted_source', 'selected_deployment', 'healthy_build')),
    producer_status TEXT NOT NULL CHECK (producer_status IN ('absent', 'unavailable', 'present')),
    revision INTEGER NOT NULL CHECK (revision >= 0),
    state BLOB NOT NULL
  ) STRICT;
  CREATE INDEX IF NOT EXISTS root_reservations_ledger_idx
    ON root_reservations(ledger_id, generation, reservation_id);
  CREATE INDEX IF NOT EXISTS root_reservations_claim_idx
    ON root_reservations(claim_id, reservation_id);
  CREATE INDEX IF NOT EXISTS root_receipts_claim_idx
    ON root_receipts(claim_id, receipt_id);
  CREATE INDEX IF NOT EXISTS authenticated_inbox_items_order_idx
    ON authenticated_inbox_items(execution_id, sequence);
  #{@atomic_bundle_schema}
  """

  @schema """
  CREATE TABLE metadata (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
  ) STRICT;
  CREATE TABLE inputs (
    input_id TEXT PRIMARY KEY,
    actor_id TEXT NOT NULL,
    request_digest TEXT NOT NULL,
    canonical_request BLOB NOT NULL,
    protocol_version INTEGER NOT NULL CHECK (protocol_version = 1),
    UNIQUE(actor_id, request_digest)
  ) STRICT;
  CREATE TABLE commands (
    command_id TEXT PRIMARY KEY,
    input_id TEXT NOT NULL REFERENCES inputs(input_id),
    actor_id TEXT NOT NULL,
    request_digest TEXT NOT NULL,
    command_type TEXT NOT NULL,
    protocol_version INTEGER NOT NULL CHECK (protocol_version = 1),
    UNIQUE(command_id, actor_id, request_digest)
  ) STRICT;
  CREATE TABLE command_results (
    command_id TEXT PRIMARY KEY REFERENCES commands(command_id),
    schema_version INTEGER NOT NULL CHECK (schema_version = 1),
    disposition TEXT NOT NULL CHECK (disposition IN ('accepted', 'rejected', 'blocked')),
    reason_code TEXT,
    result BLOB NOT NULL,
    committed_seq INTEGER NOT NULL
  ) STRICT;
  CREATE TABLE events (
    seq INTEGER PRIMARY KEY AUTOINCREMENT,
    event_id TEXT NOT NULL UNIQUE,
    command_id TEXT NOT NULL REFERENCES commands(command_id),
    schema_version INTEGER NOT NULL CHECK (schema_version = 1),
    event_type TEXT NOT NULL,
    projection_namespace TEXT,
    projection_entity_id TEXT,
    event BLOB NOT NULL,
    CHECK ((projection_namespace IS NULL) = (projection_entity_id IS NULL))
  ) STRICT;
  CREATE TABLE projections (
    namespace TEXT NOT NULL,
    entity_id TEXT NOT NULL,
    schema_version INTEGER NOT NULL CHECK (schema_version = 1),
    revision INTEGER NOT NULL CHECK (revision >= 0),
    last_event_id TEXT REFERENCES events(event_id),
    projection BLOB NOT NULL,
    PRIMARY KEY(namespace, entity_id)
  ) STRICT;
  CREATE TABLE effects (
    effect_id TEXT PRIMARY KEY,
    command_id TEXT NOT NULL REFERENCES commands(command_id),
    schema_version INTEGER NOT NULL CHECK (schema_version = 1),
    request_digest TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('pending', 'claimed', 'issued', 'unknown', 'succeeded', 'failed', 'non_started', 'cancelled')),
    intent BLOB NOT NULL
  ) STRICT;
  CREATE TABLE ledger_generations (
    generation_id TEXT PRIMARY KEY,
    parent_generation_id TEXT REFERENCES ledger_generations(generation_id),
    schema_version INTEGER NOT NULL CHECK (schema_version = 1),
    revision INTEGER NOT NULL DEFAULT 0 CHECK (revision >= 0),
    allocation INTEGER NOT NULL CHECK (allocation >= 0),
    consumed INTEGER NOT NULL DEFAULT 0 CHECK (consumed >= 0 AND consumed <= allocation)
  ) STRICT;
  CREATE TABLE claims (
    claim_id TEXT PRIMARY KEY,
    effect_id TEXT NOT NULL REFERENCES effects(effect_id),
    writer_epoch TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('pending', 'claimed', 'issued', 'unknown', 'succeeded', 'failed', 'non_started', 'cancelled')),
    claim BLOB NOT NULL
  ) STRICT;
  CREATE UNIQUE INDEX one_active_claim_per_effect
    ON claims(effect_id) WHERE status IN ('pending', 'claimed', 'issued', 'unknown');
  CREATE TABLE reservations (
    reservation_id TEXT PRIMARY KEY,
    generation_id TEXT NOT NULL REFERENCES ledger_generations(generation_id),
    claim_id TEXT REFERENCES claims(claim_id),
    dimension TEXT NOT NULL,
    units INTEGER NOT NULL CHECK (units >= 0),
    status TEXT NOT NULL CHECK (status IN ('available', 'reserved', 'consumed', 'refunded', 'released')),
    reservation BLOB NOT NULL
  ) STRICT;
  CREATE TABLE receipts (
    receipt_id TEXT PRIMARY KEY,
    effect_id TEXT NOT NULL REFERENCES effects(effect_id),
    request_id TEXT NOT NULL UNIQUE,
    schema_version INTEGER NOT NULL CHECK (schema_version = 1),
    receipt BLOB NOT NULL
  ) STRICT;
  CREATE TABLE leases (
    lease_id TEXT PRIMARY KEY,
    claim_id TEXT NOT NULL REFERENCES claims(claim_id),
    schema_version INTEGER NOT NULL CHECK (schema_version = 1),
    lease BLOB NOT NULL
  ) STRICT;
  CREATE TABLE policy_revisions (
    policy_revision_id TEXT PRIMARY KEY,
    command_id TEXT NOT NULL REFERENCES commands(command_id),
    schema_version INTEGER NOT NULL CHECK (schema_version = 1),
    revision INTEGER NOT NULL CHECK (revision >= 0),
    policy BLOB NOT NULL
  ) STRICT;
  CREATE TABLE control_revisions (
    control_id TEXT PRIMARY KEY,
    command_id TEXT NOT NULL REFERENCES commands(command_id),
    schema_version INTEGER NOT NULL CHECK (schema_version = 1),
    revision INTEGER NOT NULL CHECK (revision >= 0),
    control BLOB NOT NULL
  ) STRICT;
  CREATE TABLE artifact_references (
    artifact_id TEXT PRIMARY KEY,
    command_id TEXT NOT NULL REFERENCES commands(command_id),
    schema_version INTEGER NOT NULL CHECK (schema_version = 1),
    digest TEXT NOT NULL,
    reference BLOB NOT NULL
  ) STRICT;
  CREATE TABLE import_runs (
    source_digest TEXT PRIMARY KEY,
    source_path TEXT NOT NULL,
    archived_path TEXT NOT NULL,
    source_bytes INTEGER NOT NULL,
    line_count INTEGER NOT NULL,
    valid_count INTEGER NOT NULL,
    invalid_count INTEGER NOT NULL,
    manifest BLOB NOT NULL
  ) STRICT;
  CREATE TABLE legacy_records (
    source_digest TEXT NOT NULL REFERENCES import_runs(source_digest),
    line_number INTEGER NOT NULL,
    byte_start INTEGER NOT NULL,
    byte_end INTEGER NOT NULL,
    record_digest TEXT NOT NULL,
    valid INTEGER NOT NULL CHECK (valid IN (0, 1)),
    error TEXT,
    raw_record BLOB NOT NULL,
    PRIMARY KEY(source_digest, line_number)
  ) STRICT;
  CREATE INDEX events_command_idx ON events(command_id, seq);
  CREATE INDEX events_projection_idx ON events(projection_namespace, projection_entity_id, seq)
    WHERE projection_namespace IS NOT NULL;
  CREATE INDEX effects_command_idx ON effects(command_id);
  CREATE INDEX reservations_generation_idx ON reservations(generation_id);
  #{@protected_schema}
  """

  def schema_version, do: @schema_version
  def protected_schema_version, do: @protected_schema_version

  def expected_schema_contract do
    case Sqlite3.open(":memory:") do
      {:ok, reference} ->
        try do
          with :ok <- Sqlite3.execute(reference, @schema), do: schema_contract(reference)
        after
          _ = Sqlite3.close(reference)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def schema_contract(conn) do
    with {:ok, objects} <-
           query(
             conn,
             "SELECT type, name, tbl_name, sql FROM sqlite_schema WHERE type IN ('table', 'index') ORDER BY type, name"
           ),
         tables <- for(["table", name, _owner, _sql] <- objects, do: name),
         {:ok, table_contracts} <- schema_table_contracts(conn, tables) do
      {:ok, %{objects: objects, tables: table_contracts}}
    end
  end

  def initialize(path_or_identity, opts \\ [])

  def initialize(%PathIdentity{mode: :new} = identity, opts) do
    with :ok <- PathIdentity.validate_new_database(identity) do
      do_initialize(identity, opts)
    end
  end

  def initialize(path, opts) when is_binary(path) do
    with {:ok, identity} <- PathIdentity.new(path), do: initialize(identity, opts)
  end

  def initialize_owned(
        %{
          __struct__: PramanaFoundry.DurableStore.Owner,
          identity: %PathIdentity{mode: :new} = identity,
          conn: owner_conn
        },
        opts
      ) do
    with {:ok, :transaction} <- Sqlite3.transaction_status(owner_conn),
         :ok <- PathIdentity.revalidate(identity) do
      do_initialize(identity, opts)
    else
      _ -> {:error, :invalid_store_owner}
    end
  end

  defp do_initialize(identity, opts) do
    path = identity.path

    with :ok <- PathIdentity.revalidate(identity),
         {:ok, marker} <- :file.open(String.to_charlist(path), [:write, :binary, :exclusive]),
         :ok <- :file.close(marker),
         {:ok, conn} <- Sqlite3.open(path, mode: :readwrite),
         result <- initialize_connection(conn, opts),
         :ok <- Sqlite3.close(conn),
         {:ok, _created} <- PathIdentity.existing(path) do
      result
    else
      {:error, :eexist} -> {:error, :already_initialized}
      {:error, reason} -> {:error, reason}
    end
  end

  def open(%PathIdentity{mode: :existing} = identity) do
    path = identity.path

    with :ok <- PathIdentity.revalidate(identity) do
      open_identity(identity, path)
    end
  end

  def open(path) when is_binary(path) do
    with {:ok, identity} <- PathIdentity.existing(path), do: open(identity)
  end

  defp open_identity(identity, path) do
    case Sqlite3.open(path, mode: :readwrite) do
      {:ok, conn} ->
        validation =
          with :ok <- PathIdentity.revalidate(identity),
               :ok <- configure(conn),
               :ok <- validate(conn),
               :ok <- PathIdentity.revalidate(identity) do
            :ok
          end

        case validation do
          :ok ->
            {:ok, conn}

          {:error, reason} ->
            _ = Sqlite3.close(conn)
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def close(nil), do: :ok
  def close(conn), do: Sqlite3.close(conn)

  def execute(conn, sql, params \\ []) do
    with {:ok, statement} <- Sqlite3.prepare(conn, sql) do
      try do
        with :ok <- Sqlite3.bind(statement, params), :done <- Sqlite3.step(conn, statement) do
          :ok
        else
          {:error, reason} -> {:error, reason}
          other -> {:error, {:unexpected_sql_result, other}}
        end
      after
        Sqlite3.release(conn, statement)
      end
    end
  end

  def query(conn, sql, params \\ []) do
    with {:ok, statement} <- Sqlite3.prepare(conn, sql) do
      try do
        with :ok <- Sqlite3.bind(statement, params) do
          Sqlite3.fetch_all(conn, statement)
        end
      after
        Sqlite3.release(conn, statement)
      end
    end
  end

  def fold(conn, sql, params, initial, fun) when is_function(fun, 2) do
    with {:ok, statement} <- Sqlite3.prepare(conn, sql) do
      try do
        with :ok <- Sqlite3.bind(statement, params) do
          fold_rows(conn, statement, initial, fun)
        end
      after
        Sqlite3.release(conn, statement)
      end
    end
  end

  def transaction(conn, fun) when is_function(fun, 0) do
    with :ok <- Sqlite3.execute(conn, "BEGIN IMMEDIATE") do
      try do
        case fun.() do
          {:ok, value} -> commit(conn, value)
          :ok -> commit(conn, :ok)
          {:error, _reason} = error -> rollback(conn, error)
        end
      rescue
        exception -> rollback(conn, {:error, {:exception, exception}})
      catch
        kind, reason -> rollback(conn, {:error, {kind, reason}})
      end
    end
  end

  def record_v1_migration(conn) do
    transaction(conn, fn ->
      with :ok <-
             execute(
               conn,
               "INSERT INTO metadata(key, value) VALUES ('migration_v1', 'complete') ON CONFLICT(key) DO UPDATE SET value = excluded.value"
             ),
           {:ok, _checked} <- Authority.read(conn, :all) do
        :ok
      end
    end)
  end

  def migrate_protected_owned(%{
        __struct__: PramanaFoundry.DurableStore.Owner,
        identity: %PathIdentity{mode: :existing} = identity
      }) do
    case Sqlite3.open(identity.path, mode: :readwrite) do
      {:ok, conn} ->
        try do
          with :ok <- PathIdentity.revalidate(identity),
               :ok <- configure(conn),
               {:ok, migration_state} <- protected_migration_state(conn),
               :ok <- apply_protected_migration(conn, migration_state),
               :ok <- PathIdentity.revalidate(identity) do
            :ok
          end
        after
          _ = Sqlite3.close(conn)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def migrate_protected_owned(_owner), do: {:error, :invalid_store_owner}

  defp apply_protected_migration(conn, :current) do
    with {:ok, _checked} <- Authority.read(conn, :all), do: :ok
  end

  defp apply_protected_migration(conn, :protected_v1) do
    with {:ok, :ok} <-
           transaction(conn, fn ->
             with :ok <- Sqlite3.execute(conn, @atomic_bundle_schema),
                  :ok <- backfill_v1_operations(conn),
                  :ok <-
                    execute(
                      conn,
                      "UPDATE metadata SET value = ? WHERE key = 'protected_schema_version'",
                      [Integer.to_string(@protected_schema_version)]
                    ),
                  :ok <-
                    execute(
                      conn,
                      "INSERT INTO metadata(key, value) VALUES ('migration_atomic_bundle_v2', 'complete')"
                    ),
                  {:ok, _checked} <- Authority.read(conn, :all) do
               :ok
             end
           end) do
      :ok
    end
  end

  defp apply_protected_migration(conn, :accepted_v1_without_protected) do
    with {:ok, :ok} <-
           transaction(conn, fn ->
             with :ok <- Sqlite3.execute(conn, @protected_schema),
                  :ok <- seed_root_pointers(conn),
                  :ok <- backfill_v1_operations(conn),
                  :ok <-
                    execute(
                      conn,
                      "INSERT INTO metadata(key, value) VALUES ('protected_schema_version', ?)",
                      [Integer.to_string(@protected_schema_version)]
                    ),
                  :ok <-
                    execute(
                      conn,
                      "INSERT INTO metadata(key, value) VALUES ('migration_fr08a_v1', 'complete')"
                    ),
                  :ok <-
                    execute(
                      conn,
                      "INSERT INTO metadata(key, value) VALUES ('migration_atomic_bundle_v2', 'complete')"
                    ),
                  {:ok, _checked} <- Authority.read(conn, :all) do
               :ok
             end
           end) do
      :ok
    end
  end

  defp apply_protected_migration(_conn, {:unsupported, reason}),
    do: {:error, {:unsupported_protected_migration, reason}}

  defp protected_migration_state(conn) do
    with {:ok, metadata_rows} <-
           query(
             conn,
             "SELECT key, value FROM metadata WHERE key IN ('schema_version', 'protected_schema_version', 'migration_fr08a_v1', 'migration_atomic_bundle_v2')"
           ),
         metadata <- Map.new(metadata_rows, fn [key, value] -> {key, value} end),
         {:ok, table_rows} <-
           query(
             conn,
             "SELECT name FROM sqlite_master WHERE type = 'table' AND (name LIKE 'root_%' OR name LIKE 'authenticated_inbox%') ORDER BY name"
           ),
         tables <- Enum.map(table_rows, &hd/1) do
      cond do
        metadata["schema_version"] != Integer.to_string(@schema_version) ->
          {:ok, {:unsupported, :outer_schema_version}}

        metadata["protected_schema_version"] == Integer.to_string(@protected_schema_version) and
          metadata["migration_fr08a_v1"] == "complete" and
            metadata["migration_atomic_bundle_v2"] == "complete" ->
          {:ok, :current}

        metadata["protected_schema_version"] == "1" and
          metadata["migration_fr08a_v1"] == "complete" and
            is_nil(metadata["migration_atomic_bundle_v2"]) ->
          {:ok, :protected_v1}

        is_nil(metadata["protected_schema_version"]) and
          is_nil(metadata["migration_fr08a_v1"]) and tables == [] ->
          {:ok, :accepted_v1_without_protected}

        true ->
          {:ok, {:unsupported, :partial_or_future_protected_state}}
      end
    end
  end

  defp commit(conn, value) do
    case Sqlite3.execute(conn, "COMMIT") do
      :ok -> {:ok, value}
      {:error, reason} -> rollback(conn, {:error, {:commit_failed, reason}})
    end
  end

  defp fold_rows(conn, statement, acc, fun) do
    case Sqlite3.step(conn, statement) do
      {:row, row} ->
        case fun.(row, acc) do
          {:cont, next} -> fold_rows(conn, statement, next, fun)
          {:halt, result} -> result
          next -> fold_rows(conn, statement, next, fun)
        end

      :done ->
        {:ok, acc}

      :busy ->
        {:error, :database_busy}

      {:error, reason} ->
        {:error, reason}

      other ->
        {:error, {:unexpected_sql_result, other}}
    end
  end

  defp rollback(conn, result) do
    case Sqlite3.execute(conn, "ROLLBACK") do
      :ok -> result
      {:error, reason} -> {:error, {:storage_unavailable, {:rollback_failed, reason, result}}}
    end
  end

  defp initialize_connection(conn, opts) do
    installation_id = Keyword.get_lazy(opts, :installation_id, &random_id/0)
    repository_id = Keyword.get(opts, :repository_id, "unbound")

    with :ok <- configure(conn),
         {:ok, :ok} <-
           transaction(conn, fn ->
             with :ok <- Sqlite3.execute(conn, @schema),
                  :ok <- seed_root_pointers(conn),
                  :ok <- Sqlite3.execute(conn, "PRAGMA user_version = #{@schema_version}"),
                  :ok <-
                    execute(conn, "INSERT INTO metadata(key, value) VALUES (?, ?)", [
                      "schema_version",
                      "1"
                    ]),
                  :ok <-
                    execute(conn, "INSERT INTO metadata(key, value) VALUES (?, ?)", [
                      "protocol_version",
                      "1"
                    ]),
                  :ok <-
                    execute(conn, "INSERT INTO metadata(key, value) VALUES (?, ?)", [
                      "event_version",
                      "1"
                    ]),
                  :ok <-
                    execute(conn, "INSERT INTO metadata(key, value) VALUES (?, ?)", [
                      "projection_version",
                      "1"
                    ]),
                  :ok <-
                    execute(conn, "INSERT INTO metadata(key, value) VALUES (?, ?)", [
                      "protected_schema_version",
                      Integer.to_string(@protected_schema_version)
                    ]),
                  :ok <-
                    execute(conn, "INSERT INTO metadata(key, value) VALUES (?, ?)", [
                      "migration_fr08a_v1",
                      "complete"
                    ]),
                  :ok <-
                    execute(conn, "INSERT INTO metadata(key, value) VALUES (?, ?)", [
                      "migration_atomic_bundle_v2",
                      "complete"
                    ]),
                  :ok <-
                    execute(conn, "INSERT INTO metadata(key, value) VALUES (?, ?)", [
                      "installation_id",
                      installation_id
                    ]),
                  :ok <-
                    execute(conn, "INSERT INTO metadata(key, value) VALUES (?, ?)", [
                      "repository_id",
                      repository_id
                    ]) do
               :ok
             end
           end),
         :ok <- validate(conn) do
      :ok
    end
  end

  defp configure(conn) do
    with {:ok, [["wal"]]} <- query(conn, "PRAGMA journal_mode = WAL"),
         :ok <- Sqlite3.execute(conn, "PRAGMA synchronous = FULL"),
         :ok <- Sqlite3.execute(conn, "PRAGMA foreign_keys = ON"),
         :ok <- Sqlite3.execute(conn, "PRAGMA trusted_schema = OFF"),
         :ok <- Sqlite3.execute(conn, "PRAGMA busy_timeout = 0") do
      :ok
    else
      {:ok, value} -> {:error, {:wal_unavailable, value}}
      {:error, reason} -> {:error, reason}
    end
  end

  def validate(conn) do
    with {:ok, [["ok"]]} <- query(conn, "PRAGMA quick_check"),
         {:ok, []} <- query(conn, "PRAGMA foreign_key_check"),
         {:ok, [[1]]} <- query(conn, "PRAGMA foreign_keys"),
         {:ok, [[2]]} <- query(conn, "PRAGMA synchronous"),
         {:ok, [[@schema_version]]} <- query(conn, "PRAGMA user_version"),
         {:ok, _view} <- Authority.read(conn, :all) do
      :ok
    else
      {:ok, rows} -> {:error, {:authority_corrupt, "sqlite", "physical", rows}}
      {:error, {:authority_corrupt, _table, _identity, _reason} = reason} -> {:error, reason}
      {:error, {:storage_unavailable, _reason} = reason} -> {:error, reason}
      {:error, reason} -> {:error, {:storage_unavailable, reason}}
    end
  end

  defp random_id do
    16 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
  end

  defp backfill_v1_operations(conn) do
    with :ok <-
           execute(
             conn,
             "INSERT INTO durable_operations(owner_kind, owner_id, ordinal, operation_kind, operation_type, request, result) " <>
               "SELECT 'domain_v1', c.command_id, 0, 'domain', c.command_type, i.canonical_request, r.result " <>
               "FROM commands c JOIN inputs i ON i.input_id = c.input_id JOIN command_results r ON r.command_id = c.command_id " <>
               "WHERE true " <>
               "ON CONFLICT(owner_kind, owner_id, ordinal) DO NOTHING"
           ),
         :ok <-
           execute(
             conn,
             "INSERT INTO durable_operations(owner_kind, owner_id, ordinal, operation_kind, operation_type, request, result) " <>
               "SELECT 'protected_v1', command_id, 0, 'protected', operation, canonical_request, result FROM root_commands " <>
               "WHERE true " <>
               "ON CONFLICT(owner_kind, owner_id, ordinal) DO NOTHING"
           ) do
      :ok
    end
  end

  defp seed_root_pointers(conn) do
    Enum.reduce_while(
      ~w(accepted_source selected_deployment healthy_build),
      :ok,
      fn kind, :ok ->
        state = %{
          "schema_version" => 1,
          "pointer_kind" => kind,
          "producer_status" => "absent",
          "revision" => 0,
          "value" => nil
        }

        with {:ok, bytes} <- PramanaFoundry.DurableStore.Encoding.json(state),
             :ok <-
               execute(
                 conn,
                 "INSERT INTO root_pointers(pointer_kind, producer_status, revision, state) VALUES (?, 'absent', 0, ?) ON CONFLICT(pointer_kind) DO NOTHING",
                 [kind, {:blob, bytes}]
               ) do
          {:cont, :ok}
        else
          {:error, _reason} = error -> {:halt, error}
        end
      end
    )
  end

  defp schema_table_contracts(conn, tables) do
    Enum.reduce_while(tables, {:ok, %{}}, fn table, {:ok, acc} ->
      quoted = quote_pragma_identifier(table)

      with {:ok, columns} <- query(conn, "PRAGMA table_xinfo(#{quoted})"),
           {:ok, table_list} <- query(conn, "PRAGMA table_list(#{quoted})"),
           {:ok, foreign_keys} <- query(conn, "PRAGMA foreign_key_list(#{quoted})"),
           {:ok, indexes} <- query(conn, "PRAGMA index_list(#{quoted})"),
           {:ok, index_contracts} <- schema_index_contracts(conn, indexes) do
        contract = %{
          columns: columns,
          table_list: table_list,
          foreign_keys: foreign_keys,
          indexes: indexes,
          index_columns: index_contracts
        }

        {:cont, {:ok, Map.put(acc, table, contract)}}
      else
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp schema_index_contracts(conn, indexes) do
    Enum.reduce_while(indexes, {:ok, %{}}, fn [_seq, name | _rest], {:ok, acc} ->
      case query(conn, "PRAGMA index_xinfo(#{quote_pragma_identifier(name)})") do
        {:ok, rows} -> {:cont, {:ok, Map.put(acc, name, rows)}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp quote_pragma_identifier(value), do: "'" <> String.replace(value, "'", "''") <> "'"
end
