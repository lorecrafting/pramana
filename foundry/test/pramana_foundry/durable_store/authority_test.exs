defmodule PramanaFoundry.DurableStore.AuthorityTest do
  use ExUnit.Case, async: false

  alias PramanaFoundry.DurableStore.{Database, Encoding, Gateway, LegacyImport, RecordCodec}

  setup do
    root = Path.join(System.tmp_dir!(), "fr07-authority-#{System.unique_integer([:positive])}")
    File.mkdir!(root)
    path = Path.join(root, "authority.sqlite3")
    assert :ok = Gateway.initialize(path, installation_id: "installation", repository_id: "repository")
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, path: path}
  end

  test "a command missing its result fences direct read, retry, reopen and backup", ctx do
    gateway = start_supervised!({Gateway, path: ctx.path})
    assert {:ok, _result, :committed} = Gateway.transact(gateway, "actor", command("A"), bundle("A"))
    conn = :sys.get_state(gateway).conn
    assert :ok = Database.execute(conn, "DELETE FROM command_results WHERE command_id = 'A'")

    assert {:error, {:recovery_mode, {:authority_corrupt, "commands", "A", :required_relation_missing}}} =
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
    assert {:ok, _result, :committed} = Gateway.transact(gateway, "actor", command("A"), bundle("A"))
    conn = :sys.get_state(gateway).conn
    {:ok, durable} = RecordCodec.materialize_result(%{schema_version: 1, disposition: "accepted"}, 999)
    {:ok, bytes} = RecordCodec.encode(:result, durable)

    assert :ok =
             Database.execute(
               conn,
               "UPDATE command_results SET committed_seq=999, result=? WHERE command_id='A'",
               [{:blob, bytes}]
             )

    assert {:error, {:authority_corrupt, "command_results", "A", :invalid_sequence_or_disposition}} =
             Gateway.backup(gateway, Path.join(ctx.root, "bad.sqlite3"))

    assert %{mode: :recovery} = Gateway.status(gateway)
  end

  test "historic eventless watermarks remain valid while foreign event blocks do not", ctx do
    gateway = start_supervised!({Gateway, path: ctx.path})
    assert {:ok, _result, :committed} = Gateway.transact(gateway, "actor", command("A"), bundle("A"))

    stale = put_in(command("STALE")["expected_revisions"][projection_key("A")], 99)
    assert {:ok, %{"committed_seq" => 1, "disposition" => "rejected"}, :rejected} =
             Gateway.transact(gateway, "actor", stale, bundle("STALE"))

    assert {:ok, _result, :committed} = Gateway.transact(gateway, "actor", command("B"), bundle("B"))
    assert :ok = stop_supervised(Gateway)
    reopened = start_supervised!({Gateway, path: ctx.path})
    assert %{mode: :ready} = Gateway.status(reopened)
    assert {:ok, %{"committed_seq" => 1}} = Gateway.command(reopened, "STALE")

    conn = :sys.get_state(reopened).conn
    {:ok, durable} = RecordCodec.materialize_result(%{schema_version: 1, disposition: "accepted"}, 2)
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
    assert {:ok, conn} = Database.open(ctx.path)
    assert :ok = Database.execute(conn, "INSERT INTO sqlite_sequence(name, seq) VALUES ('other', 0)")
    assert :ok = Database.close(conn)
    gateway = start_supervised!({Gateway, path: ctx.path})
    assert %{mode: :recovery, reason: {:authority_corrupt, "sqlite_sequence", "events", :invalid_sequence}} = Gateway.status(gateway)
  end

  test "candidate result validation is total over arbitrary terms", ctx do
    gateway = start_supervised!({Gateway, path: ctx.path})

    malformed = [nil, true, 1, "binary", [], {}, %URI{scheme: "x"}, [1 | 2], %{}, %{schema_version: 1}]

    malformed
    |> Enum.with_index()
    |> Enum.each(fn {result, index} ->
      proposal = Map.put(bundle("BAD-#{index}"), :result, result)
      assert {:error, _reason} = Gateway.transact(gateway, "actor", command("BAD-#{index}"), proposal)
      assert Process.alive?(gateway)
      assert %{mode: :ready} = Gateway.status(gateway)
    end)

    assert {:ok, counts} = Gateway.counts(gateway)
    assert Enum.all?(counts, fn {_table, count} -> count == 0 end)
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

    assert {:error, {:authority_corrupt, "ledger_generations", "child", :unsupported_ledger_generation}} =
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
    assert %{mode: :recovery, reason: {:store_owner_unavailable, _reason}} = Gateway.status(gateway)
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
    assert %{mode: :recovery, reason: {:authority_corrupt, "receipts", "retained", :unsupported_retained_authority}} = Gateway.status(gateway)
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
