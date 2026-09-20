defmodule PramanaFoundry.DurableStore.Database do
  @moduledoc false

  alias Exqlite.Sqlite3

  @schema_version 1
  @protocol_version 1
  @event_version 1
  @projection_version 1

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
    event BLOB NOT NULL
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
  CREATE INDEX effects_command_idx ON effects(command_id);
  CREATE INDEX reservations_generation_idx ON reservations(generation_id);
  """

  def schema_version, do: @schema_version

  def initialize(path, opts \\ []) do
    with {:ok, marker} <- :file.open(String.to_charlist(path), [:write, :binary, :exclusive]),
         :ok <- :file.close(marker),
         {:ok, conn} <- Sqlite3.open(path, mode: :readwrite),
         result <- initialize_connection(conn, opts),
         :ok <- Sqlite3.close(conn) do
      result
    else
      {:error, :eexist} -> {:error, :already_initialized}
      {:error, reason} -> {:error, reason}
    end
  end

  def open(path) do
    case Sqlite3.open(path, mode: :readwrite) do
      {:ok, conn} ->
        case with :ok <- configure(conn), do: validate(conn) do
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

  defp commit(conn, value) do
    case Sqlite3.execute(conn, "COMMIT") do
      :ok -> {:ok, value}
      {:error, reason} -> rollback(conn, {:error, {:commit_failed, reason}})
    end
  end

  defp fold_rows(conn, statement, acc, fun) do
    case Sqlite3.step(conn, statement) do
      {:row, row} -> fold_rows(conn, statement, fun.(row, acc), fun)
      :done -> {:ok, acc}
      :busy -> {:error, :database_busy}
      {:error, reason} -> {:error, reason}
      other -> {:error, {:unexpected_sql_result, other}}
    end
  end

  defp rollback(conn, result) do
    _ = Sqlite3.execute(conn, "ROLLBACK")
    result
  end

  defp initialize_connection(conn, opts) do
    installation_id = Keyword.get_lazy(opts, :installation_id, &random_id/0)
    repository_id = Keyword.get(opts, :repository_id, "unbound")

    with :ok <- configure(conn),
         :ok <- Sqlite3.execute(conn, @schema),
         :ok <- Sqlite3.execute(conn, "PRAGMA user_version = #{@schema_version}"),
         :ok <- execute(conn, "INSERT INTO metadata(key, value) VALUES (?, ?)", ["schema_version", "1"]),
         :ok <- execute(conn, "INSERT INTO metadata(key, value) VALUES (?, ?)", ["protocol_version", "1"]),
         :ok <- execute(conn, "INSERT INTO metadata(key, value) VALUES (?, ?)", ["event_version", "1"]),
         :ok <- execute(conn, "INSERT INTO metadata(key, value) VALUES (?, ?)", ["projection_version", "1"]),
         :ok <- execute(conn, "INSERT INTO metadata(key, value) VALUES (?, ?)", ["installation_id", installation_id]),
         :ok <- execute(conn, "INSERT INTO metadata(key, value) VALUES (?, ?)", ["repository_id", repository_id]),
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

  defp validate(conn) do
    with {:ok, [["ok"]]} <- query(conn, "PRAGMA quick_check"),
         {:ok, []} <- query(conn, "PRAGMA foreign_key_check"),
         {:ok, [[1]]} <- query(conn, "PRAGMA foreign_keys"),
         {:ok, [[2]]} <- query(conn, "PRAGMA synchronous"),
         {:ok, [[@schema_version]]} <- query(conn, "PRAGMA user_version"),
         :ok <- validate_metadata(conn),
         :ok <- validate_event_sequence(conn),
         :ok <- validate_bodies(conn),
         :ok <- validate_relational_bodies(conn) do
      :ok
    else
      {:ok, rows} -> {:error, {:authority_corrupt, "sqlite", "physical", rows}}
      {:error, {:authority_corrupt, _table, _identity, _reason} = reason} -> {:error, reason}
      {:error, {:storage_unavailable, _reason} = reason} -> {:error, reason}
      {:error, reason} -> {:error, {:storage_unavailable, reason}}
    end
  end

  defp validate_event_sequence(conn) do
    case query(conn, "SELECT count(*), coalesce(min(seq), 0), coalesce(max(seq), 0) FROM events") do
      {:ok, [[0, 0, 0]]} -> :ok
      {:ok, [[count, 1, count]]} -> :ok
      {:ok, rows} -> {:error, {:invalid_event_sequence, rows}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_bodies(conn) do
    body_columns = [
      {"inputs", "canonical_request", :command_request},
      {"command_results", "result", :versioned},
      {"events", "event", :versioned},
      {"projections", "projection", :json},
      {"effects", "intent", :json},
      {"claims", "claim", :json},
      {"reservations", "reservation", :json},
      {"receipts", "receipt", :json},
      {"leases", "lease", :json},
      {"policy_revisions", "policy", :json},
      {"control_revisions", "control", :json},
      {"artifact_references", "reference", :json},
      {"import_runs", "manifest", :versioned}
    ]

    Enum.reduce_while(body_columns, :ok, fn {table, column, kind}, :ok ->
      case query(conn, "SELECT rowid, #{column} FROM #{table} ORDER BY rowid") do
        {:ok, rows} -> validate_body_rows(table, rows, kind)
        {:error, reason} -> {:error, reason}
      end
      |> case do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp validate_body_rows(table, rows, kind) do
    Enum.reduce_while(rows, :ok, fn [rowid, bytes], :ok ->
      case decode_body(bytes, kind) do
        :ok -> {:cont, :ok}
        {:error, reason} ->
          {:halt, {:error, {:authority_corrupt, table, rowid, reason}}}
      end
    end)
  end

  defp validate_relational_bodies(conn) do
    with :ok <- validate_result_rows(conn),
         :ok <- validate_event_rows(conn),
         :ok <- validate_projection_rows(conn),
         :ok <- validate_effect_rows(conn) do
      :ok
    end
  end

  defp validate_result_rows(conn) do
    validate_bound_rows(
      conn,
      "command_results",
      "SELECT rowid, schema_version, disposition, reason_code, committed_seq, result FROM command_results ORDER BY rowid",
      fn [schema, disposition, reason, committed_seq, bytes] ->
        with {:ok, value} <- decode_object(bytes),
             true <- Map.keys(value) |> Enum.sort() == ~w(committed_seq disposition reason_code schema_version),
             true <- value["schema_version"] == schema and schema == 1,
             true <- value["disposition"] == disposition and disposition in ["accepted", "rejected", "blocked"],
             true <- value["reason_code"] == reason,
             true <- is_nil(reason) or (is_binary(reason) and reason != ""),
             true <- value["committed_seq"] == committed_seq and is_integer(committed_seq) and committed_seq >= 0 do
          :ok
        else
          _ -> {:error, :result_binding_mismatch}
        end
      end
    )
  end

  defp validate_event_rows(conn) do
    validate_bound_rows(
      conn,
      "events",
      "SELECT rowid, event_id, schema_version, event_type, event FROM events ORDER BY rowid",
      fn [event_id, schema, event_type, bytes] ->
        with {:ok, value} <- decode_object(bytes),
             true <- Map.keys(value) |> Enum.sort() == ~w(event_id payload schema_version type),
             true <- value["event_id"] == event_id,
             true <- value["schema_version"] == schema and schema == 1,
             true <- value["type"] == event_type,
             true <- is_map(value["payload"]) do
          :ok
        else
          _ -> {:error, :event_binding_mismatch}
        end
      end
    )
  end

  defp validate_projection_rows(conn) do
    validate_bound_rows(
      conn,
      "projections",
      "SELECT rowid, namespace, entity_id, schema_version, revision, last_event_id, projection FROM projections ORDER BY rowid",
      fn [namespace, entity_id, schema, revision, last_event_id, bytes] ->
        with {:ok, value} <- decode_object(bytes),
             true <- Map.keys(value) |> Enum.sort() == ~w(entity_id expected_revision last_event_id namespace revision schema_version value),
             true <- value["namespace"] == namespace and value["entity_id"] == entity_id,
             true <- value["schema_version"] == schema and schema == 1,
             true <- value["revision"] == revision and value["expected_revision"] == revision - 1,
             true <- value["last_event_id"] == last_event_id,
             true <- is_map(value["value"]) do
          :ok
        else
          _ -> {:error, :projection_binding_mismatch}
        end
      end
    )
  end

  defp validate_effect_rows(conn) do
    validate_bound_rows(
      conn,
      "effects",
      "SELECT rowid, effect_id, schema_version, request_digest, status, intent FROM effects ORDER BY rowid",
      fn [effect_id, schema, digest, status, bytes] ->
        with {:ok, value} <- decode_object(bytes),
             true <- Map.keys(value) |> Enum.sort() == ~w(effect_id request_digest schema_version status value),
             true <- value["effect_id"] == effect_id,
             true <- value["schema_version"] == schema and schema == 1,
             true <- value["request_digest"] == digest,
             true <- value["status"] == status and status == "pending",
             true <- is_map(value["value"]) do
          :ok
        else
          _ -> {:error, :effect_binding_mismatch}
        end
      end
    )
  end

  defp validate_bound_rows(conn, table, sql, validator) do
    with {:ok, rows} <- query(conn, sql) do
      Enum.reduce_while(rows, :ok, fn [rowid | values], :ok ->
        case validator.(values) do
          :ok -> {:cont, :ok}
          {:error, reason} ->
            {:halt, {:error, {:authority_corrupt, table, rowid, reason}}}
        end
      end)
    end
  end

  defp decode_object(bytes) do
    value = bytes |> :json.decode() |> decoded_nulls()
    if is_map(value), do: {:ok, value}, else: {:error, :not_an_object}
  rescue
    _ -> {:error, :malformed_json}
  end

  defp decoded_nulls(:null), do: nil
  defp decoded_nulls(value) when is_list(value), do: Enum.map(value, &decoded_nulls/1)
  defp decoded_nulls(value) when is_map(value), do: Map.new(value, fn {key, item} -> {key, decoded_nulls(item)} end)
  defp decoded_nulls(value), do: value

  defp decode_body(bytes, kind) when is_binary(bytes) do
    value = :json.decode(bytes)

    cond do
      not is_map(value) -> {:error, :not_an_object}
      kind == :versioned and value["schema_version"] != 1 -> {:error, :unsupported_version}
      kind == :command_request and value["domain"] != "pramana-foundry-command-v1" ->
        {:error, :invalid_command_domain}
      kind == :command_request and value["schema_version"] != 1 ->
        {:error, :unsupported_version}
      true -> :ok
    end
  rescue
    _ -> {:error, :malformed_json}
  catch
    _, _ -> {:error, :malformed_json}
  end

  defp decode_body(_bytes, _kind), do: {:error, :not_binary}

  defp validate_metadata(conn) do
    expected = %{
      "schema_version" => Integer.to_string(@schema_version),
      "protocol_version" => Integer.to_string(@protocol_version),
      "event_version" => Integer.to_string(@event_version),
      "projection_version" => Integer.to_string(@projection_version)
    }

    with {:ok, rows} <- query(conn, "SELECT key, value FROM metadata") do
      actual = Map.new(rows, fn [key, value] -> {key, value} end)

      case Enum.find(expected, fn {key, value} -> Map.get(actual, key) != value end) do
        nil -> :ok
        {key, value} -> {:error, {:unsupported_metadata, key, Map.get(actual, key), value}}
      end
    end
  end

  defp random_id do
    16 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
  end
end
