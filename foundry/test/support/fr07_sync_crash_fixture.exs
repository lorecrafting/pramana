alias Exqlite.Sqlite3
alias PramanaFoundry.DurableStore.{Database, Gateway}

[path, extension] = System.argv()
capability = make_ref()

projection_key = fn id ->
  "projection/" <>
    Base.url_encode64("kernel-v1", padding: false) <>
    "/" <> Base.url_encode64("ticket-#{id}", padding: false)
end

command = fn id ->
  %{
    "schema_version" => 1,
    "command_id" => id,
    "expected_revisions" => %{projection_key.(id) => "absent"},
    "type" => "legacy_event_append",
    "target_ids" => %{},
    "payload" => %{}
  }
end

bundle = fn id ->
  event_id = "event-#{id}"
  value = %{"status" => "ready"}

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
            "value" => value
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
        value: value
      }
    ],
    intents: [
      %{
        schema_version: 1,
        effect_id: "effect-#{id}",
        request_digest:
          elem(
            PramanaFoundry.DurableStore.Encoding.semantic_digest(
              "pramana-foundry-effect-request-v1",
              %{
                "effect_id" => "effect-#{id}",
                "operation" => %{"operation" => "check"}
              }
            ),
            1
          ),
        status: "pending",
        value: %{"operation" => "check"}
      }
    ]
  }
end

protected = fn id ->
  %{
    writer_epoch: "sync-crash-epoch",
    required_revisions: %{projection_key.(id) => "absent"},
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

:ok = Gateway.initialize(path)
{:ok, gateway} = Gateway.start_link(path: path, protected_capability: capability)

{:ok, _result, :committed} =
  Gateway.transact_verified(
    gateway,
    capability,
    "actor",
    command.("SEED"),
    bundle.("SEED"),
    protected.("SEED")
  )

conn = :sys.get_state(gateway).conn
:ok = Sqlite3.enable_load_extension(conn, true)

{:ok, [[nil]]} =
  Database.query(conn, "SELECT load_extension(?, ?)", [
    extension,
    "sqlite3_fr07syncfault_init"
  ])

:ok = Sqlite3.enable_load_extension(conn, false)
{:ok, [[1]]} = Database.query(conn, "SELECT fr07_sync_arm()")
result =
  Gateway.transact_verified(
    gateway,
    capability,
    "actor",
    command.("SYNC-CRASH"),
    bundle.("SYNC-CRASH"),
    protected.("SYNC-CRASH")
  )
{:ok, [[hits, code, writes, write_sequence, sync_sequence]]} =
  Database.query(
    conn,
    "SELECT fr07_sync_hits(), fr07_sync_code(), fr07_sync_writes(), fr07_write_sequence(), fr07_sync_sequence()"
  )

true = hits == 1 and code == 1034 and writes > 0 and sync_sequence > write_sequence
IO.puts("SYNC_OBS=#{inspect({result, hits, code, writes, write_sequence, sync_sequence})}")
System.halt(73)
