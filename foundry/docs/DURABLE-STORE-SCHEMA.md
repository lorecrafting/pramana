# Durable store schema reference

**Generated from [`lib/pramana_foundry/durable_store/database.ex`](../lib/pramana_foundry/durable_store/database.ex). Do not edit by hand.**
`PramanaFoundry.SchemaReferenceTest` fails if this file and the schema disagree.

Regenerate with:

```sh
cd foundry
mix run --no-start -e 'File.write!(PramanaFoundry.SchemaReference.doc_path(), PramanaFoundry.SchemaReference.render())'
```

This reference describes the schema as declared. It is not evidence that any table is
populated, that a migration has run against a given store, or that any behavior is
activated. [The durable store overview](DURABLE-STORE.md) describes intent; this
describes the declarations.

## Reading the constraints

Only some columns are constrained by the schema itself. A vocabulary enforced solely
in Elixir does not appear here, and a `TEXT` column with no `CHECK` accepts any string
at the storage layer whatever the application validates. `STRICT` tables reject values
of the wrong storage class; SQLite cannot alter a `CHECK` in place, so changing one
requires rebuilding its table.

## `metadata`

`STRICT`

```sql
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
```

## `inputs`

`STRICT`

```sql
  input_id TEXT PRIMARY KEY,
  actor_id TEXT NOT NULL,
  request_digest TEXT NOT NULL,
  canonical_request BLOB NOT NULL,
  protocol_version INTEGER NOT NULL CHECK (protocol_version = 1),
  UNIQUE(actor_id, request_digest)
```

## `commands`

`STRICT`

```sql
  command_id TEXT PRIMARY KEY,
  input_id TEXT NOT NULL REFERENCES inputs(input_id),
  actor_id TEXT NOT NULL,
  request_digest TEXT NOT NULL,
  command_type TEXT NOT NULL,
  protocol_version INTEGER NOT NULL CHECK (protocol_version = 1),
  UNIQUE(command_id, actor_id, request_digest)
```

## `command_results`

`STRICT`

```sql
  command_id TEXT PRIMARY KEY REFERENCES commands(command_id),
  schema_version INTEGER NOT NULL CHECK (schema_version = 1),
  disposition TEXT NOT NULL CHECK (disposition IN ('accepted', 'rejected', 'blocked')),
  reason_code TEXT,
  result BLOB NOT NULL,
  committed_seq INTEGER NOT NULL
```

## `events`

`STRICT`

```sql
  seq INTEGER PRIMARY KEY AUTOINCREMENT,
  event_id TEXT NOT NULL UNIQUE,
  command_id TEXT NOT NULL REFERENCES commands(command_id),
  schema_version INTEGER NOT NULL CHECK (schema_version = 1),
  event_type TEXT NOT NULL,
  projection_namespace TEXT,
  projection_entity_id TEXT,
  event BLOB NOT NULL,
  CHECK ((projection_namespace IS NULL) = (projection_entity_id IS NULL))
```

## `projections`

`STRICT`

```sql
  namespace TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  schema_version INTEGER NOT NULL CHECK (schema_version = 1),
  revision INTEGER NOT NULL CHECK (revision >= 0),
  last_event_id TEXT REFERENCES events(event_id),
  projection BLOB NOT NULL,
  PRIMARY KEY(namespace, entity_id)
```

## `effects`

`STRICT`

```sql
  effect_id TEXT PRIMARY KEY,
  command_id TEXT NOT NULL REFERENCES commands(command_id),
  schema_version INTEGER NOT NULL CHECK (schema_version = 1),
  request_digest TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('pending', 'claimed', 'issued', 'unknown', 'succeeded', 'failed', 'non_started', 'cancelled')),
  intent BLOB NOT NULL
```

## `ledger_generations`

`STRICT`

```sql
  generation_id TEXT PRIMARY KEY,
  parent_generation_id TEXT REFERENCES ledger_generations(generation_id),
  schema_version INTEGER NOT NULL CHECK (schema_version = 1),
  revision INTEGER NOT NULL DEFAULT 0 CHECK (revision >= 0),
  allocation INTEGER NOT NULL CHECK (allocation >= 0),
  consumed INTEGER NOT NULL DEFAULT 0 CHECK (consumed >= 0 AND consumed <= allocation)
```

## `claims`

`STRICT`

```sql
  claim_id TEXT PRIMARY KEY,
  effect_id TEXT NOT NULL REFERENCES effects(effect_id),
  writer_epoch TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('pending', 'claimed', 'issued', 'unknown', 'succeeded', 'failed', 'non_started', 'cancelled')),
  claim BLOB NOT NULL
```

## `reservations`

`STRICT`

```sql
  reservation_id TEXT PRIMARY KEY,
  generation_id TEXT NOT NULL REFERENCES ledger_generations(generation_id),
  claim_id TEXT REFERENCES claims(claim_id),
  dimension TEXT NOT NULL,
  units INTEGER NOT NULL CHECK (units >= 0),
  status TEXT NOT NULL CHECK (status IN ('available', 'reserved', 'consumed', 'refunded', 'released')),
  reservation BLOB NOT NULL
```

## `receipts`

`STRICT`

```sql
  receipt_id TEXT PRIMARY KEY,
  effect_id TEXT NOT NULL REFERENCES effects(effect_id),
  request_id TEXT NOT NULL UNIQUE,
  schema_version INTEGER NOT NULL CHECK (schema_version = 1),
  receipt BLOB NOT NULL
```

## `leases`

`STRICT`

```sql
  lease_id TEXT PRIMARY KEY,
  claim_id TEXT NOT NULL REFERENCES claims(claim_id),
  schema_version INTEGER NOT NULL CHECK (schema_version = 1),
  lease BLOB NOT NULL
```

## `policy_revisions`

`STRICT`

```sql
  policy_revision_id TEXT PRIMARY KEY,
  command_id TEXT NOT NULL REFERENCES commands(command_id),
  schema_version INTEGER NOT NULL CHECK (schema_version = 1),
  revision INTEGER NOT NULL CHECK (revision >= 0),
  policy BLOB NOT NULL
```

## `control_revisions`

`STRICT`

```sql
  control_id TEXT PRIMARY KEY,
  command_id TEXT NOT NULL REFERENCES commands(command_id),
  schema_version INTEGER NOT NULL CHECK (schema_version = 1),
  revision INTEGER NOT NULL CHECK (revision >= 0),
  control BLOB NOT NULL
```

## `artifact_references`

`STRICT`

```sql
  artifact_id TEXT PRIMARY KEY,
  command_id TEXT NOT NULL REFERENCES commands(command_id),
  schema_version INTEGER NOT NULL CHECK (schema_version = 1),
  digest TEXT NOT NULL,
  reference BLOB NOT NULL
```

## `import_runs`

`STRICT`

```sql
  source_digest TEXT PRIMARY KEY,
  source_path TEXT NOT NULL,
  archived_path TEXT NOT NULL,
  source_bytes INTEGER NOT NULL,
  line_count INTEGER NOT NULL,
  valid_count INTEGER NOT NULL,
  invalid_count INTEGER NOT NULL,
  manifest BLOB NOT NULL
```

## `legacy_records`

`STRICT`

```sql
  source_digest TEXT NOT NULL REFERENCES import_runs(source_digest),
  line_number INTEGER NOT NULL,
  byte_start INTEGER NOT NULL,
  byte_end INTEGER NOT NULL,
  record_digest TEXT NOT NULL,
  valid INTEGER NOT NULL CHECK (valid IN (0, 1)),
  error TEXT,
  raw_record BLOB NOT NULL,
  PRIMARY KEY(source_digest, line_number)
```

