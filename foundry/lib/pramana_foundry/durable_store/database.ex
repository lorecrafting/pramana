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
    status TEXT NOT NULL CHECK (status IN ('pending', 'issued', 'unknown', 'settled', 'cancelled')),
    intent BLOB NOT NULL
  ) STRICT;
  CREATE TABLE ledger_generations (
    generation_id TEXT PRIMARY KEY,
    parent_generation_id TEXT REFERENCES ledger_generations(generation_id),
    schema_version INTEGER NOT NULL CHECK (schema_version = 1),
    allocation INTEGER NOT NULL CHECK (allocation >= 0),
    consumed INTEGER NOT NULL DEFAULT 0 CHECK (consumed >= 0 AND consumed <= allocation)
  ) STRICT;
  CREATE TABLE claims (
    claim_id TEXT PRIMARY KEY,
    effect_id TEXT NOT NULL REFERENCES effects(effect_id),
    writer_epoch TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('active', 'released', 'settled', 'unknown')),
    claim BLOB NOT NULL
  ) STRICT;
  CREATE UNIQUE INDEX one_active_claim_per_effect
    ON claims(effect_id) WHERE status = 'active';
  CREATE TABLE reservations (
    reservation_id TEXT PRIMARY KEY,
    generation_id TEXT NOT NULL REFERENCES ledger_generations(generation_id),
    claim_id TEXT REFERENCES claims(claim_id),
    dimension TEXT NOT NULL,
    units INTEGER NOT NULL CHECK (units >= 0),
    status TEXT NOT NULL CHECK (status IN ('reserved', 'consumed', 'refunded', 'released')),
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
    policy BLOB NOT NULL
  ) STRICT;
  CREATE TABLE control_revisions (
    control_id TEXT PRIMARY KEY,
    command_id TEXT NOT NULL REFERENCES commands(command_id),
    schema_version INTEGER NOT NULL CHECK (schema_version = 1),
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
    with :ok <- File.mkdir_p(Path.dirname(path)),
         {:ok, marker} <- :file.open(String.to_charlist(path), [:write, :binary, :exclusive]),
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
         :ok <-
           execute(conn, "INSERT INTO metadata(key, value) VALUES (?, ?)", ["schema_version", "1"]),
         :ok <-
           execute(conn, "INSERT INTO metadata(key, value) VALUES (?, ?)", [
             "protocol_version",
             "1"
           ]),
         :ok <-
           execute(conn, "INSERT INTO metadata(key, value) VALUES (?, ?)", ["event_version", "1"]),
         :ok <-
           execute(conn, "INSERT INTO metadata(key, value) VALUES (?, ?)", [
             "projection_version",
             "1"
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
           ]),
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
         {:ok, [[1]]} <- query(conn, "PRAGMA foreign_keys"),
         {:ok, [[2]]} <- query(conn, "PRAGMA synchronous"),
         {:ok, [[@schema_version]]} <- query(conn, "PRAGMA user_version"),
         :ok <- validate_metadata(conn) do
      :ok
    else
      {:ok, rows} -> {:error, {:invalid_store, rows}}
      {:error, reason} -> {:error, reason}
    end
  end

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
