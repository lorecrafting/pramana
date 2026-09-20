defmodule PramanaFoundry.DurableStore.AuthorityTest do
  use ExUnit.Case, async: false

  alias PramanaFoundry.DurableStore.{
    Authority,
    Database,
    Encoding,
    Gateway,
    LegacyImport,
    RecordCodec
  }

  setup do
    root = Path.join(System.tmp_dir!(), "fr07-authority-#{System.unique_integer([:positive])}")
    File.mkdir!(root)
    path = Path.join(root, "authority.sqlite3")

    assert :ok =
             Gateway.initialize(path,
               installation_id: "installation",
               repository_id: "repository"
             )

    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, path: path}
  end

  test "a command missing its result fences direct read, retry, reopen and backup", ctx do
    gateway = start_supervised!({Gateway, path: ctx.path})

    assert {:ok, _result, :committed} =
             Gateway.transact(gateway, "actor", command("A"), bundle("A"))

    conn = :sys.get_state(gateway).conn
    assert :ok = Database.execute(conn, "DELETE FROM command_results WHERE command_id = 'A'")

    assert {:error,
            {:recovery_mode, {:authority_corrupt, "commands", "A", :required_relation_missing}}} =
             Gateway.command(gateway, "A")

    assert {:error, {:recovery_mode, _reason}} =
             Gateway.transact(gateway, "actor", command("B"), bundle("B"))

    assert :ok = stop_supervised(Gateway)
    reopened = start_supervised!({Gateway, path: ctx.path})

    assert %{mode: :recovery, reason: {:authority_corrupt, _table, _identity, _reason}} =
             Gateway.status(reopened)
  end

  test "result sequence beyond retained events fences source backup", ctx do
    gateway = start_supervised!({Gateway, path: ctx.path})

    assert {:ok, _result, :committed} =
             Gateway.transact(gateway, "actor", command("A"), bundle("A"))

    conn = :sys.get_state(gateway).conn

    {:ok, durable} =
      RecordCodec.materialize_result(%{schema_version: 1, disposition: "accepted"}, 999)

    {:ok, bytes} = RecordCodec.encode(:result, durable)

    assert :ok =
             Database.execute(
               conn,
               "UPDATE command_results SET committed_seq=999, result=? WHERE command_id='A'",
               [{:blob, bytes}]
             )

    assert {:error,
            {:authority_corrupt, "command_results", "A", :invalid_sequence_or_disposition}} =
             Gateway.backup(gateway, Path.join(ctx.root, "bad.sqlite3"))

    assert %{mode: :recovery} = Gateway.status(gateway)
  end

  test "historic eventless watermarks remain valid while foreign event blocks do not", ctx do
    gateway = start_supervised!({Gateway, path: ctx.path})

    assert {:ok, _result, :committed} =
             Gateway.transact(gateway, "actor", command("A"), bundle("A"))

    stale = put_in(command("STALE")["expected_revisions"][projection_key("A")], 99)

    assert {:ok, %{"committed_seq" => 1, "disposition" => "rejected"}, :rejected} =
             Gateway.transact(gateway, "actor", stale, bundle("STALE"))

    assert {:ok, _result, :committed} =
             Gateway.transact(gateway, "actor", command("B"), bundle("B"))

    assert :ok = stop_supervised(Gateway)
    reopened = start_supervised!({Gateway, path: ctx.path})
    assert %{mode: :ready} = Gateway.status(reopened)
    assert {:ok, %{"committed_seq" => 1}} = Gateway.command(reopened, "STALE")

    conn = :sys.get_state(reopened).conn

    {:ok, durable} =
      RecordCodec.materialize_result(%{schema_version: 1, disposition: "accepted"}, 2)

    {:ok, bytes} = RecordCodec.encode(:result, durable)

    assert :ok =
             Database.execute(
               conn,
               "UPDATE command_results SET committed_seq=2, result=? WHERE command_id='A'",
               [{:blob, bytes}]
             )

    assert {:error, {:recovery_mode, {:authority_corrupt, "command_results", "A", _reason}}} =
             Gateway.command(reopened, "A")
  end

  test "sqlite_sequence admits only the exact events high-water row", ctx do
    gateway = start_supervised!({Gateway, path: ctx.path})

    assert {:ok, _result, :committed} =
             Gateway.transact(gateway, "actor", command("A"), bundle("A"))

    conn = :sys.get_state(gateway).conn

    assert :ok =
             Database.execute(conn, "INSERT INTO sqlite_sequence(name, seq) VALUES ('other', 0)")

    assert {:error,
            {:recovery_mode, {:authority_corrupt, "sqlite_sequence", "events", :invalid_sequence}}} =
             Gateway.command(gateway, "A")
  end

  test "a prior projection carrier corruption fences a later live CAS", ctx do
    gateway = start_supervised!({Gateway, path: ctx.path})

    assert {:ok, _result, :committed} =
             Gateway.transact(gateway, "actor", command("A"), bundle("A"))

    update_command = put_in(command("B")["expected_revisions"], %{projection_key("A") => 0})

    update_event =
      bundle("B").events
      |> hd()
      |> put_in([:payload, "projection", "entity_id"], "ticket-A")
      |> put_in([:payload, "projection", "revision"], 1)

    update_projection =
      bundle("B").projections
      |> hd()
      |> Map.merge(%{entity_id: "ticket-A", expected_revision: 0, revision: 1})

    update_bundle = %{bundle("B") | events: [update_event], projections: [update_projection]}

    assert {:ok, _result, :committed} =
             Gateway.transact(gateway, "actor", update_command, update_bundle)

    conn = :sys.get_state(gateway).conn

    {:ok, [[event_bytes]]} =
      Database.query(conn, "SELECT event FROM events WHERE event_id='event-A'")

    {:ok, event} = RecordCodec.decode(:event, event_bytes)
    damaged = put_in(event["payload"]["projection"]["revision"], 5)
    {:ok, damaged_bytes} = RecordCodec.encode(:event, damaged)

    assert :ok =
             Database.execute(conn, "UPDATE events SET event=? WHERE event_id='event-A'", [
               {:blob, damaged_bytes}
             ])

    assert {:error, {:recovery_mode, {:authority_corrupt, "projections", _identity, _reason}}} =
             Gateway.command(gateway, "A")
  end

  test "candidate result validation is total over arbitrary terms", ctx do
    gateway = start_supervised!({Gateway, path: ctx.path})

    malformed = [
      nil,
      true,
      1,
      "binary",
      [],
      {},
      %URI{scheme: "x"},
      [1 | 2],
      %{},
      %{schema_version: 1}
    ]

    malformed
    |> Enum.with_index()
    |> Enum.each(fn {result, index} ->
      proposal = Map.put(bundle("BAD-#{index}"), :result, result)

      assert {:error, _reason} =
               Gateway.transact(gateway, "actor", command("BAD-#{index}"), proposal)

      assert Process.alive?(gateway)
      assert %{mode: :ready} = Gateway.status(gateway)
    end)

    assert {:ok, counts} = Gateway.counts(gateway)
    assert Enum.all?(counts, fn {_table, count} -> count == 0 end)
  end

  test "protected admission rejects improper collections without crashing", ctx do
    capability = make_ref()
    gateway = start_supervised!({Gateway, path: ctx.path, protected_capability: capability})

    for field <- [:ledger_generations, :effect_authorizations] do
      facts = Map.put(protected("BAD-#{field}"), field, [nil | :improper])

      assert {:error, _reason} =
               Gateway.transact_verified(
                 gateway,
                 capability,
                 "actor",
                 command("BAD-#{field}"),
                 protected_bundle("BAD-#{field}"),
                 facts
               )

      assert Process.alive?(gateway)
      assert %{mode: :ready} = Gateway.status(gateway)
    end
  end

  test "a zero-available root generation requires no invented reservation", ctx do
    capability = make_ref()
    gateway = start_supervised!({Gateway, path: ctx.path, protected_capability: capability})

    facts = %{
      writer_epoch: "epoch",
      required_revisions: %{projection_key("ZERO") => "absent"},
      ledger_generations: [
        %{
          schema_version: 1,
          generation_id: "generation-ZERO",
          parent_generation_id: nil,
          allocation: 0,
          consumed: 0
        }
      ],
      effect_authorizations: []
    }

    assert {:ok, _result, :committed} =
             Gateway.transact_verified(
               gateway,
               capability,
               "actor",
               command("ZERO"),
               bundle("ZERO"),
               facts
             )

    conn = :sys.get_state(gateway).conn

    assert {:ok, [[0, 0]]} =
             Database.query(
               conn,
               "SELECT (SELECT count(*) FROM reservations), (SELECT consumed FROM ledger_generations WHERE generation_id='generation-ZERO')"
             )
  end

  test "a semantically unsupported ledger row cannot satisfy a live revision read", ctx do
    capability = make_ref()
    gateway = start_supervised!({Gateway, path: ctx.path, protected_capability: capability})

    assert {:ok, _result, :committed} =
             Gateway.transact_verified(
               gateway,
               capability,
               "actor",
               command("A"),
               protected_bundle("A"),
               protected("A")
             )

    conn = :sys.get_state(gateway).conn

    assert :ok =
             Database.execute(
               conn,
               "INSERT INTO ledger_generations(generation_id, parent_generation_id, schema_version, revision, allocation, consumed) VALUES ('child', 'generation-A', 1, 0, 1, 0)"
             )

    key = "ledger/" <> Base.url_encode64("child", padding: false)
    b = put_in(command("B")["expected_revisions"][key], 0)

    assert {:error,
            {:authority_corrupt, "ledger_generations", "child", :unsupported_ledger_generation}} =
             Gateway.transact(gateway, "actor", b, bundle("B"))

    assert %{mode: :recovery} = Gateway.status(gateway)
  end

  test "a second reservation on a retained claim cannot hide behind another generation", ctx do
    capability = make_ref()
    gateway = start_supervised!({Gateway, path: ctx.path, protected_capability: capability})

    assert {:ok, _result, :committed} =
             Gateway.transact_verified(
               gateway,
               capability,
               "actor",
               command("A"),
               protected_bundle("A"),
               protected("A")
             )

    conn = :sys.get_state(gateway).conn

    assert :ok =
             Database.execute(
               conn,
               "INSERT INTO ledger_generations VALUES ('generation-2', NULL, 1, 0, 1, 0)"
             )

    second = %{
      schema_version: 1,
      reservation_id: "reservation-2",
      generation_id: "generation-2",
      claim_id: "claim-A",
      dimension: "starts.developer",
      units: 1,
      status: "reserved",
      value: %{"verified" => true}
    }

    {:ok, bytes} = RecordCodec.encode(:reservation, second)

    assert :ok =
             Database.execute(
               conn,
               "INSERT INTO reservations VALUES ('reservation-2', 'generation-2', 'claim-A', 'starts.developer', 1, 'reserved', ?)",
               [{:blob, bytes}]
             )

    ledger_key = "ledger/" <> Base.url_encode64("generation-A", padding: false)
    b = put_in(command("B")["expected_revisions"][ledger_key], 0)

    assert {:error,
            {:authority_corrupt, "reservations", "reservation-A", :required_relation_missing}} =
             Gateway.transact(gateway, "actor", b, bundle("B"))

    assert %{mode: :recovery} = Gateway.status(gateway)
  end

  test "an import manifest never certifies missing retained bytes", ctx do
    source = Path.join(ctx.root, "legacy.jsonl")
    archive = Path.join(ctx.root, "archive")
    File.write!(source, valid_legacy_line())
    assert {:ok, manifest} = LegacyImport.run(ctx.path, source, archive)

    assert {:ok, conn} = Database.open(ctx.path)
    assert :ok = Database.execute(conn, "DELETE FROM legacy_records")
    assert :ok = Database.close(conn)

    assert {:error, {:authority_corrupt, "legacy_records", digest, :import_evidence_mismatch}} =
             LegacyImport.run(ctx.path, source, archive)

    assert digest == manifest["source_digest"]
  end

  test "backup cannot occupy any owner database journal path", ctx do
    gateway = start_supervised!({Gateway, path: ctx.path})
    target = ctx.path <> ".owner.sqlite3-journal"
    assert {:error, :store_path_collision} = Gateway.backup(gateway, target)
    refute File.exists?(target)
    assert %{mode: :ready} = Gateway.status(gateway)
  end

  test "the complete store namespace and prospective backup sidecars are reserved", ctx do
    gateway = start_supervised!({Gateway, path: ctx.path})

    for target <- PramanaFoundry.DurableStore.PathIdentity.store_namespace(ctx.path) do
      existed = File.exists?(target)
      assert {:error, _reason} = Gateway.backup(gateway, target)
      assert File.exists?(target) == existed
      assert %{mode: :ready} = Gateway.status(gateway)
    end

    backup = Path.join(ctx.root, "prospective.sqlite3")
    journal = backup <> "-journal"
    File.write!(journal, "foreign")

    assert {:error, {:prospective_sidecar_exists, ^journal}} = Gateway.backup(gateway, backup)
    refute File.exists?(backup)
    assert File.read!(journal) == "foreign"

    source = Path.join(ctx.root, "namespace-source.jsonl")
    File.write!(source, valid_legacy_line())
    archive_root = ctx.path <> "-journal"
    assert {:error, :store_path_collision} = LegacyImport.run(ctx.path, source, archive_root)
    refute File.exists?(archive_root)
  end

  test "mismatched retained owner recovery evidence refuses ownership", ctx do
    archive = ctx.path <> ".owner.unclean.recovered." <> String.duplicate("0", 64)
    File.write!(archive, "not owned evidence")
    gateway = start_supervised!({Gateway, path: ctx.path})

    assert %{mode: :recovery, reason: {:store_owner_unavailable, _reason}} =
             Gateway.status(gateway)

    assert File.read!(archive) == "not owned evidence"
  end

  test "a prospective store refuses every preexisting recovered-marker family member", ctx do
    target = Path.join(ctx.root, "new.sqlite3")
    recovered = target <> ".owner.unclean.recovered." <> String.duplicate("a", 64)
    File.write!(recovered, "foreign")
    assert {:error, {:prospective_sidecar_exists, ^recovered}} = Gateway.initialize(target)
    refute File.exists?(target)
    assert File.read!(recovered) == "foreign"
  end

  test "raw database initialization cannot delete prospective SQLite sidecars", ctx do
    for suffix <- ["-wal", "-shm", "-journal"] do
      target = Path.join(ctx.root, "raw-init-#{String.trim_leading(suffix, "-")}.sqlite3")
      sidecar = target <> suffix
      File.write!(sidecar, "foreign")

      assert {:error, {:prospective_sidecar_exists, ^sidecar}} = Database.initialize(target)
      refute File.exists?(target)
      assert File.read!(sidecar) == "foreign"
    end
  end

  test "unsupported reserved table rows and unknown sequence entries fence reopen", ctx do
    gateway = start_supervised!({Gateway, path: ctx.path})

    assert {:ok, _result, :committed} =
             Gateway.transact(gateway, "actor", command("RESERVED"), protected_bundle("RESERVED"))

    assert :ok = stop_supervised(Gateway)
    assert {:ok, conn} = Database.open(ctx.path)

    assert :ok =
             Database.execute(
               conn,
               "INSERT INTO receipts(receipt_id, effect_id, request_id, schema_version, receipt) VALUES ('r', 'effect-RESERVED', 'q', 1, ?)",
               [{:blob, ~s({"schema_version":1})}]
             )

    assert :ok = Database.close(conn)
    gateway = start_supervised!({Gateway, path: ctx.path})

    assert %{
             mode: :recovery,
             reason: {:authority_corrupt, "receipts", "retained", :unsupported_retained_authority}
           } = Gateway.status(gateway)
  end

  test "every unsupported authority table fences startup", ctx do
    inserts = [
      {"receipts", "INSERT INTO receipts VALUES ('receipt', 'effect-A', 'request', 1, ?)",
       [{:blob, "{}"}]},
      {"leases", "INSERT INTO leases VALUES ('lease', 'claim-A', 1, ?)", [{:blob, "{}"}]},
      {"policy_revisions", "INSERT INTO policy_revisions VALUES ('policy', 'A', 1, 0, ?)",
       [{:blob, "{}"}]},
      {"control_revisions", "INSERT INTO control_revisions VALUES ('control', 'A', 1, 0, ?)",
       [{:blob, "{}"}]},
      {"artifact_references",
       "INSERT INTO artifact_references VALUES ('artifact', 'A', 1, 'digest', ?)",
       [{:blob, "{}"}]}
    ]

    for {{table, sql, params}, index} <- Enum.with_index(inserts) do
      path = Path.join(ctx.root, "unsupported-#{index}.sqlite3")
      assert :ok = Gateway.initialize(path)
      capability = make_ref()

      gateway =
        start_supervised!(
          {Gateway, path: path, protected_capability: capability},
          id: {:unsupported_seed, index}
        )

      assert {:ok, _result, :committed} =
               Gateway.transact_verified(
                 gateway,
                 capability,
                 "actor",
                 command("A"),
                 protected_bundle("A"),
                 protected("A")
               )

      assert :ok = stop_supervised({:unsupported_seed, index})
      {:ok, conn} = Database.open(path)
      assert :ok = Database.execute(conn, sql, params)
      assert :ok = Database.close(conn)

      reopened = start_supervised!({Gateway, path: path}, id: {:unsupported_reopen, index})

      assert %{mode: :recovery, reason: {:authority_corrupt, ^table, "retained", _reason}} =
               Gateway.status(reopened)
    end
  end

  test "a genuine historical projection cannot replace the final retained carrier", ctx do
    gateway = start_supervised!({Gateway, path: ctx.path})

    assert {:ok, _result, :committed} =
             Gateway.transact(gateway, "actor", command("A"), bundle("A"))

    conn = :sys.get_state(gateway).conn
    assert {:ok, [[historic]]} = Database.query(conn, "SELECT projection FROM projections")

    update_command = put_in(command("B")["expected_revisions"], %{projection_key("A") => 0})

    update_event =
      bundle("B").events
      |> hd()
      |> put_in([:payload, "projection", "entity_id"], "ticket-A")
      |> put_in([:payload, "projection", "revision"], 1)

    update_projection =
      bundle("B").projections
      |> hd()
      |> Map.merge(%{entity_id: "ticket-A", expected_revision: 0, revision: 1})

    assert {:ok, _result, :committed} =
             Gateway.transact(gateway, "actor", update_command, %{
               bundle("B")
               | events: [update_event],
                 projections: [update_projection]
             })

    assert :ok =
             Database.execute(
               conn,
               "UPDATE projections SET revision=0, last_event_id='event-A', projection=?",
               [{:blob, historic}]
             )

    assert {:error, {:authority_corrupt, "projections", _identity, _reason}} =
             Authority.read(conn, {:revision, {:projection, "kernel-v1", "ticket-A"}})

    assert {:error, {:recovery_mode, {:authority_corrupt, "projections", _identity, _reason}}} =
             Gateway.command(gateway, "B")
  end

  test "scoped projection and ledger reads require complete command ownership", ctx do
    for family <- [:projection, :ledger] do
      path = Path.join(ctx.root, "owner-#{family}.sqlite3")
      assert :ok = Gateway.initialize(path)
      capability = make_ref()

      gateway =
        start_supervised!(
          {Gateway, path: path, protected_capability: capability},
          id: {:owner_closure, family}
        )

      assert {:ok, _result, :committed} =
               Gateway.transact_verified(
                 gateway,
                 capability,
                 "actor",
                 command("A"),
                 protected_bundle("A"),
                 protected("A")
               )

      conn = :sys.get_state(gateway).conn
      assert :ok = Database.execute(conn, "DELETE FROM command_results WHERE command_id='A'")

      key =
        if family == :projection,
          do: projection_key("A"),
          else: "ledger/" <> Base.url_encode64("generation-A", padding: false)

      dependent = put_in(command("B")["expected_revisions"], %{key => 0})

      assert {:error, {:authority_corrupt, _table, _identity, :required_relation_missing}} =
               Gateway.transact(gateway, "actor", dependent, %{
                 schema_version: 1,
                 result: %{schema_version: 1, disposition: "accepted"}
               })

      assert %{mode: :recovery} = Gateway.status(gateway)
    end
  end

  test "global reads reject orphan effects before backup publication", ctx do
    capability = make_ref()
    gateway = start_supervised!({Gateway, path: ctx.path, protected_capability: capability})

    assert {:ok, _result, :committed} =
             Gateway.transact_verified(
               gateway,
               capability,
               "actor",
               command("A"),
               protected_bundle("A"),
               protected("A")
             )

    conn = :sys.get_state(gateway).conn
    assert :ok = Database.execute(conn, "PRAGMA foreign_keys=OFF")
    assert :ok = Database.execute(conn, "UPDATE effects SET command_id='missing'")
    assert :ok = Database.execute(conn, "PRAGMA foreign_keys=ON")

    assert {:error, {:authority_corrupt, "sqlite", "physical", _rows}} =
             Authority.read(conn, :all)

    backup = Path.join(ctx.root, "orphan-backup.sqlite3")

    assert {:error, {:authority_corrupt, "sqlite", "physical", _rows}} =
             Gateway.backup(gateway, backup)

    refute File.exists?(backup)
    assert %{mode: :recovery} = Gateway.status(gateway)
  end

  test "malformed protected facts and command lookups are total and nonfencing", ctx do
    capability = make_ref()
    gateway = start_supervised!({Gateway, path: ctx.path, protected_capability: capability})

    malformed = [
      %{protected("A") | required_revisions: %URI{scheme: "x"}},
      %{protected("A") | required_revisions: %{<<255>> => "absent"}},
      %{protected("A") | writer_epoch: <<255>>},
      put_in(protected("A"), [:effect_authorizations, Access.at(0), :claim_id], <<255>>)
    ]

    Enum.each(malformed, fn facts ->
      assert {:error, _reason} =
               Gateway.transact_verified(
                 gateway,
                 capability,
                 "actor",
                 command("A"),
                 protected_bundle("A"),
                 facts
               )

      assert Process.alive?(gateway)
      assert %{mode: :ready} = Gateway.status(gateway)
    end)

    for command_id <- ["", <<255>>, %URI{scheme: "x"}] do
      assert {:error, :invalid_command_id} = Gateway.command(gateway, command_id)
      assert %{mode: :ready} = Gateway.status(gateway)
    end

    assert {:ok, counts} = Gateway.counts(gateway)
    assert Enum.all?(counts, fn {_table, count} -> count == 0 end)
  end

  test "archive staging adopts only exact evidence and preserves foreign bytes", ctx do
    source = Path.join(ctx.root, "source.jsonl")
    archive = Path.join(ctx.root, "archive")
    bytes = "{}\n"
    File.write!(source, bytes)
    File.mkdir!(archive)
    digest = Encoding.digest(bytes)
    temp = Path.join(archive, digest <> ".jsonl.tmp-" <> String.slice(digest, 0, 16))
    File.write!(temp, "PRESERVE PREEXISTING EVIDENCE")

    assert {:error, {:archive_staging_occupied, ^temp}} =
             LegacyImport.run(ctx.path, source, archive)

    assert File.read!(temp) == "PRESERVE PREEXISTING EVIDENCE"
    refute File.exists?(Path.join(archive, digest <> ".jsonl"))

    {:ok, conn} = Database.open(ctx.path)

    assert {:ok, [[0, 0]]} =
             Database.query(
               conn,
               "SELECT (SELECT count(*) FROM import_runs), (SELECT count(*) FROM legacy_records)"
             )

    assert :ok = Database.close(conn)
    File.rm!(temp)
    File.write!(temp, bytes)

    assert {:ok, %{"source_digest" => ^digest}} = LegacyImport.run(ctx.path, source, archive)
    refute File.exists?(temp)
    assert File.read!(Path.join(archive, digest <> ".jsonl")) == bytes
  end

  test "schema validation checks exact uniqueness keys and partial predicates", ctx do
    corruptions = [
      "CREATE INDEX one_active_claim_per_effect ON claims(writer_epoch)",
      "CREATE UNIQUE INDEX one_active_claim_per_effect ON claims(effect_id) WHERE status IN ('pending', 'claimed')"
    ]

    for {replacement, index} <- Enum.with_index(corruptions) do
      path = Path.join(ctx.root, "schema-#{index}.sqlite3")
      assert :ok = Gateway.initialize(path)
      gateway = start_supervised!({Gateway, path: path}, id: {:schema_contract, index})
      conn = :sys.get_state(gateway).conn
      assert :ok = Database.execute(conn, "DROP INDEX one_active_claim_per_effect")
      assert :ok = Database.execute(conn, replacement)

      assert {:error, {:authority_corrupt, "sqlite_schema", "inventory", :schema_mismatch}} =
               Authority.read(conn, :all)

      backup = Path.join(ctx.root, "schema-backup-#{index}.sqlite3")

      assert {:error, {:authority_corrupt, "sqlite_schema", "inventory", :schema_mismatch}} =
               Gateway.backup(gateway, backup)

      refute File.exists?(backup)
      assert %{mode: :recovery} = Gateway.status(gateway)
    end

    path = Path.join(ctx.root, "schema-foreign-key.sqlite3")
    assert :ok = Gateway.initialize(path)
    gateway = start_supervised!({Gateway, path: path}, id: :schema_foreign_key)
    conn = :sys.get_state(gateway).conn
    assert :ok = Database.execute(conn, "DROP TABLE command_results")

    assert :ok =
             Database.execute(
               conn,
               "CREATE TABLE command_results (command_id TEXT PRIMARY KEY, schema_version INTEGER NOT NULL CHECK (schema_version = 1), disposition TEXT NOT NULL CHECK (disposition IN ('accepted', 'rejected', 'blocked')), reason_code TEXT, result BLOB NOT NULL, committed_seq INTEGER NOT NULL) STRICT"
             )

    assert {:error, {:authority_corrupt, "sqlite_schema", "inventory", :schema_mismatch}} =
             Authority.read(conn, :all)

    backup = Path.join(ctx.root, "schema-foreign-key-backup.sqlite3")

    assert {:error, {:authority_corrupt, "sqlite_schema", "inventory", :schema_mismatch}} =
             Gateway.backup(gateway, backup)

    refute File.exists?(backup)
  end

  test "scoped projection validation does not retain or decode unrelated history", ctx do
    gateway = start_supervised!({Gateway, path: ctx.path})

    assert {:ok, _result, :committed} =
             Gateway.transact(gateway, "actor", command("A"), bundle("A"))

    assert {:ok, _result, :committed} =
             Gateway.transact(gateway, "actor", command("B"), bundle("B"))

    conn = :sys.get_state(gateway).conn

    assert {:ok, plan} =
             Database.query(
               conn,
               "EXPLAIN QUERY PLAN SELECT schema_version, event_id, command_id, event_type, event FROM events WHERE projection_namespace = ? AND projection_entity_id = ? ORDER BY seq",
               ["kernel-v1", "ticket-A"]
             )

    assert Enum.any?(plan, fn [_id, _parent, _unused, detail] ->
             detail =~ "events_projection_idx"
           end)

    assert :ok =
             Database.execute(conn, "UPDATE events SET event=x'00' WHERE event_id='event-B'")

    assert {:ok, %{revision: 0}} =
             Authority.read(conn, {:revision, {:projection, "kernel-v1", "ticket-A"}})

    assert {:ok, %{"disposition" => "accepted"}} = Gateway.command(gateway, "A")

    assert {:error, {:authority_corrupt, "events", "event-B", _reason}} =
             Authority.read(conn, :all)
  end

  defp command(id) do
    %{
      "schema_version" => 1,
      "command_id" => id,
      "expected_revisions" => %{projection_key(id) => "absent"},
      "type" => "legacy_event_append",
      "target_ids" => %{},
      "payload" => %{}
    }
  end

  defp bundle(id) do
    event_id = "event-#{id}"

    %{
      schema_version: 1,
      result: %{schema_version: 1, disposition: "accepted"},
      events: [
        %{
          schema_version: 1,
          event_id: event_id,
          type: "legacy_event",
          payload: %{
            "projection" => %{
              "namespace" => "kernel-v1",
              "entity_id" => "ticket-#{id}",
              "revision" => 0,
              "value" => %{"status" => "ready"}
            }
          }
        }
      ],
      projections: [
        %{
          schema_version: 1,
          namespace: "kernel-v1",
          entity_id: "ticket-#{id}",
          expected_revision: -1,
          revision: 0,
          last_event_id: event_id,
          value: %{"status" => "ready"}
        }
      ]
    }
  end

  defp protected_bundle(id) do
    intent = %{
      schema_version: 1,
      effect_id: "effect-#{id}",
      request_digest: effect_digest(id),
      status: "pending",
      value: %{"operation" => "check"}
    }

    Map.put(bundle(id), :intents, [intent])
  end

  defp protected(id) do
    %{
      writer_epoch: "epoch",
      required_revisions: %{projection_key(id) => "absent"},
      ledger_generations: [
        %{
          schema_version: 1,
          generation_id: "generation-#{id}",
          parent_generation_id: nil,
          allocation: 1,
          consumed: 0
        }
      ],
      effect_authorizations: [
        %{
          effect_id: "effect-#{id}",
          claim_id: "claim-#{id}",
          generation_id: "generation-#{id}",
          reservation_id: "reservation-#{id}",
          dimension: "starts.developer",
          units: 1
        }
      ]
    }
  end

  defp projection_key(id),
    do:
      "projection/" <>
        Base.url_encode64("kernel-v1", padding: false) <>
        "/" <> Base.url_encode64("ticket-#{id}", padding: false)

  defp effect_digest(id) do
    {:ok, digest} =
      Encoding.semantic_digest(
        "pramana-foundry-effect-request-v1",
        %{"effect_id" => "effect-#{id}", "operation" => %{"operation" => "check"}}
      )

    digest
  end

  defp valid_legacy_line do
    ~s({"event_id":"legacy","event_type":"ticket_created","event_version":1,"payload":{},"recorded_at":"2026-01-01T00:00:00Z","schema_version":1,"source":"legacy"}\n)
  end
end
