defmodule PramanaFoundry.DurableStore.UnifiedContractTest do
  use ExUnit.Case, async: false

  alias PramanaFoundry.DurableStore.{Database, Gateway, LegacyImport}

  setup do
    root = Path.join(System.tmp_dir!(), "fr07-unified-#{System.unique_integer([:positive])}")
    File.mkdir!(root)
    path = Path.join(root, "authority.sqlite3")
    assert :ok = Gateway.initialize(path)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, path: path}
  end

  test "acknowledged omitted reason survives every result and reconstruction phase", ctx do
    gateway = start_supervised!({Gateway, path: ctx.path})
    command = command("OMITTED")
    bundle = bundle("OMITTED")

    assert {:ok, result, :committed} = Gateway.transact(gateway, "actor", command, bundle)
    assert result["reason_code"] == nil
    assert {:ok, ^result} = Gateway.command(gateway, "OMITTED")
    assert {:ok, ^result, :idempotent} = Gateway.transact(gateway, "actor", command, %{})

    backup = Path.join(ctx.root, "backup.sqlite3")
    assert {:ok, %{reconstruction: %{projection_count: 1}}} = Gateway.backup(gateway, backup)
    assert :ok = stop_supervised(Gateway)

    reopened = start_supervised!({Gateway, path: ctx.path})
    assert %{mode: :ready} = Gateway.status(reopened)
    assert {:ok, ^result} = Gateway.command(reopened, "OMITTED")
  end

  test "event-only projection mutation is refused without any SQL rows", ctx do
    gateway = start_supervised!({Gateway, path: ctx.path})
    proposal = %{bundle("MISSING") | projections: []}
    assert {:error, :projection_write_missing} = Gateway.transact(gateway, "actor", command("MISSING"), proposal)
    assert {:ok, counts} = Gateway.counts(gateway)
    assert Enum.all?(counts, fn {_table, count} -> count == 0 end)
  end

  test "two ordered transitions for one entity consume one initial authoritative read", ctx do
    gateway = start_supervised!({Gateway, path: ctx.path})
    first = bundle("MULTI")
    first_event = hd(first.events)
    first_projection = hd(first.projections)

    second_event =
      put_in(first_event, [:event_id], "event-MULTI-2")
      |> put_in([:payload, "projection", "revision"], 1)
      |> put_in([:payload, "projection", "value"], %{"status" => "done"})

    second_projection =
      %{first_projection | expected_revision: 0, revision: 1, last_event_id: "event-MULTI-2"}
      |> put_in([:value], %{"status" => "done"})

    proposal = %{first | events: [first_event, second_event], projections: [first_projection, second_projection]}

    assert {:ok, %{"committed_seq" => 2}, :committed} =
             Gateway.transact(gateway, "actor", command("MULTI"), proposal)

    assert {:ok, %{"events" => 2, "projections" => 1}} = Gateway.counts(gateway)

    assert {:ok, %{reconstruction: %{projection_count: 1}}} =
             Gateway.backup(gateway, Path.join(ctx.root, "multi.sqlite3"))
  end

  test "parent symlink and dotdot aliases never reach gateway or importer", ctx do
    other = Path.join(ctx.root, "other")
    File.mkdir!(other)
    link = Path.join(ctx.root, "link")
    File.ln_s!(other, link)
    alias_path = link <> "/../authority.sqlite3"

    alias_gateway = start_supervised!({Gateway, path: alias_path}, id: :alias_gateway)
    assert %{mode: :recovery, reason: :noncanonical_database_path} = Gateway.status(alias_gateway)

    source = Path.join(ctx.root, "legacy.jsonl")
    archive = Path.join(ctx.root, "archive")
    File.write!(source, "{}\n")
    assert {:error, :noncanonical_database_path} = LegacyImport.run(alias_path, source, archive)
    assert {:error, :noncanonical_database_path} = Gateway.initialize(alias_path)
    assert {:error, :noncanonical_database_path} = Gateway.migrate(alias_path)

    original = start_supervised!({Gateway, path: ctx.path}, id: :original_gateway)
    assert %{mode: :ready} = Gateway.status(original)

    assert {:error, :noncanonical_database_path} =
             Gateway.backup(original, link <> "/../backup.sqlite3")

    assert %{mode: :ready} = Gateway.status(original)
  end

  test "unsupported retained child ledger semantics fence startup", ctx do
    assert {:ok, conn} = Database.open(ctx.path)

    assert :ok =
             Database.execute(
               conn,
               "INSERT INTO ledger_generations(generation_id, parent_generation_id, schema_version, revision, allocation, consumed) VALUES ('root', NULL, 1, 0, 1, 0)"
             )

    assert :ok =
             Database.execute(
               conn,
               "INSERT INTO ledger_generations(generation_id, parent_generation_id, schema_version, revision, allocation, consumed) VALUES ('child', 'root', 1, 0, 1, 0)"
             )

    assert :ok = Database.close(conn)
    gateway = start_supervised!({Gateway, path: ctx.path})

    assert %{
             mode: :recovery,
             reason:
               {:authority_corrupt, "ledger_generations", "child",
                :unsupported_ledger_generation}
           } = Gateway.status(gateway)

    assert {:error, {:recovery_mode, _reason}} = Gateway.counts(gateway)
  end

  test "canonical command body and relational command columns cannot diverge", ctx do
    gateway = start_supervised!({Gateway, path: ctx.path})

    assert {:ok, _result, :committed} =
             Gateway.transact(gateway, "actor", command("COMMAND-BIND"), bundle("COMMAND-BIND"))

    conn = :sys.get_state(gateway).conn

    assert :ok =
             Database.execute(
               conn,
               "UPDATE commands SET command_type = 'pause' WHERE command_id = 'COMMAND-BIND'"
             )

    assert :ok = stop_supervised(Gateway)
    reopened = start_supervised!({Gateway, path: ctx.path})

    assert %{mode: :recovery, reason: {:authority_corrupt, "inputs", _rowid, :relational_binding_mismatch}} =
             Gateway.status(reopened)
  end

  defp command(id) do
    %{
      "schema_version" => 1,
      "command_id" => id,
      "expected_revisions" => %{projection_key(id) => "absent"},
      "type" => "legacy_event_append",
      "target_ids" => %{"ticket_id" => id},
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

  defp projection_key(id) do
    "projection/" <>
      Base.url_encode64("kernel-v1", padding: false) <>
      "/" <> Base.url_encode64("ticket-#{id}", padding: false)
  end
end
