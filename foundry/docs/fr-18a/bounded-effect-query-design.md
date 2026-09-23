# FR-18A bounded effect query design

> **Current status, 2026-09-22.** Implemented since this was written: the `bounded_effect_*` functions in `durable_store/protected_primitives.ex`, and the [B5 correction rereview](b5-correction-rereview.md) is PASS. The body below is the dated design record and is not updated.

Status: **design only; B5 remains blocking.** This record defines the smallest
protected read interface needed to correct B5 from the
[independent review](independent-review.md#b5--the-declared-public-bounds-sit-after-an-unbounded-protected-materialization).
It does not implement or accept the interface, change the protected write protocol,
enable an observation producer, or establish an FR-18A PASS.

The design was checked against accepted `main`
`656c2307f5d28b60648f0f75114580f15302fb71`. At that revision,
`ProtectedPrimitives.effect_fact/2` loads every claim, receipt and effect-owned
reservation before the public observation layer applies its limits. The existing
`Gateway.protected_query/3` capability boundary is retained.

## Typed protected request

Add one allowlisted query type to `ProtectedPrimitives.query/2`:

```elixir
%{
  "schema_version" => 1,
  "type" => "effect_observation_page",
  "effect_id" => exact_effect_id,
  "limit" => 1..50,
  "max_bytes" => bounded_integer,
  "cursor" => nil | typed_cursor
}
```

The caller must possess the existing protected capability and name exactly one effect.
The request cannot enumerate effects and cannot supply SQL, table names, column names,
sort expressions or an arbitrary filter. `limit` and `max_bytes` are validated both
against hard protected maxima and against the remaining public page budget.

The cursor is a versioned map:

```elixir
%{
  "schema_version" => 1,
  "query_type" => "effect_observation_page",
  "scope_digest" => semantic_digest_of_effect_identity,
  "source_digest" => semantic_digest_of_installation_and_repository,
  "protected_sequence" => non_negative_integer,
  "effect_revision" => non_negative_integer,
  "section" => "claims" | "receipts" | "reservations" | "leases",
  "offset" => non_negative_integer
}
```

Digests bind the cursor without copying potentially secret-shaped identities into the
public result. They are scope checks, not new authorization: every continuation still
passes the existing capability check and exact effect identity. Cursor validation
rejects missing or extra fields, unsupported versions, wrong types or vocabulary,
negative or excessive offsets, a different effect, and a different store identity.

## Typed protected response

A successful query returns:

```elixir
%{
  "schema_version" => 1,
  "type" => "effect_observation_page",
  "source" => %{
    "installation_id" => installation_id,
    "repository_id" => repository_id,
    "last_protected_command_sequence" => protected_sequence,
    "effect_revision" => effect_revision
  },
  "effect" => %{
    "effect_id" => effect_id,
    "ticket_id" => ticket_id,
    "attempt_id" => attempt_id,
    "execution_id" => execution_id,
    "control_id" => control_id,
    "policy_id" => policy_id,
    "operation" => operation,
    "scope" => scope,
    "status" => status,
    "revision" => effect_revision
  },
  "control" => %{
    "schema_version" => 1,
    "control_id" => control_id,
    "revision" => non_negative_integer,
    "status" => "active" | "cancel_requested"
  },
  "execution" => %{
    "schema_version" => 1,
    "execution_id" => execution_id,
    "status" => "absent" | "open" | "result" | "exit" |
      "sealed_without_result_or_exit",
    "revision" => non_negative_integer,
    "last_sequence" => non_negative_integer,
    "sealed_sequence" => nil | non_negative_integer,
    "sequence" => optional_resolution_sequence
  },
  "relations" => [
    %{"kind" => "claim", ...},
    %{"kind" => "receipt", ...},
    %{"kind" => "reservation", ...},
    %{"kind" => "lease", ...}
  ],
  "infrastructure_settlement" => nil | %{
    "schema_version" => 1,
    "effect_id" => effect_id,
    "claim_id" => claim_id,
    "receipt_id" => receipt_id,
    "role" => role,
    "work_owner" => work_owner,
    "infrastructure_generation" => generation,
    "predecessor_effect_id" => predecessor_effect_id,
    "failure_class" => failure_class,
    "ordinal" => positive_ordinal
  },
  "settlement" => %{
    "schema_version" => 1,
    "status" => authoritative_effect_status,
    "receipt_history" => "complete" | "unknown"
  },
  "page" => %{
    "item_count" => item_count,
    "size_bytes" => encoded_size,
    "truncated" => boolean,
    "truncated_reason" => nil | "item_limit" | "byte_limit",
    "next_cursor" => typed_cursor | nil
  }
}
```

Every relation and summary is a discriminated, allowlisted scalar DTO. The control
summary extracts only its status and revision through fixed SQL. The execution summary
uses fixed scalar inbox metadata plus ordered aggregate sequence selection; it never
selects an inbox item blob. The query never returns protected `state` blobs, effect
request bodies, receipt payload or proof, generic rows, or SQL identifiers.

The atomic-core integration at `057f2902580235d844679c43ece571056b60b8a5` added the
authoritative singleton `root_infrastructure_settlements` table after the original B5
design was frozen. The optional `infrastructure_settlement` above corrects that stale
assumption. It is selected by exact effect identity in the same read snapshot, from
allowlisted scalar columns only, and its encoded bytes count toward the page cap. It is a
header, not a fifth paginated relation: the schema permits at most one row per effect.

When present, its effect, claim and receipt identities must join to the observed effect,
and the immutable receipt must have `non_started` semantics. Current effect and claim
status may either both be `non_started`, or both be `reconciliation_required` when a
later durable quarantined conflicting receipt proves that supported transition. The
latter reports current outcome `unknown/reconciliation_required` while retaining the
historical settlement. Role, work owner, generation and predecessor must match bounded
authoritative effect-state scalars; failure class must match the bounded receipt scalar;
all singleton fields must match the accepted atomic-operation result; and ordinal must
match its exact predecessor lineage. Required absence, an unexpected carrier, an
unsupported transition or any scalar mismatch is corrupt. No state/result blob is
materialized into the runtime or returned.

The `settlement` summary remains the bounded current effect outcome, with receipt
traversal recorded only as provenance. Until the receipt section is exhausted,
`receipt_history` is `unknown`; paging must not manufacture a complete settlement
history. Terminal protected effect state remains authoritative when earlier receipts
record an `unknown` result.

## Materialization and consistency invariants

1. The effect header, control/execution summaries, settlement and all relation sections
   are read in one read transaction, giving
   the call one SQLite snapshot even if another connection can write concurrently.
2. Relation order is fixed: claims, receipts, reservations, then leases. Each section
   has static parameterized SQL, deterministic ordering and `LIMIT remaining + 1`.
3. `Database.fold/5` consumes at most that bounded result and stops again before either
   the item or byte budget is crossed. No call to `fetch_all` may precede these bounds.
4. SQL selects byte lengths and bounded prefixes for every emitted text value. Control
   and accepted-operation values use fixed JSON scalar extraction; inbox resolution uses
   fixed aggregates. A value outside
   the observation contract is not fully copied into the BEAM or returned to the caller.
5. The encoded protected DTO size is checked before appending each relation. A returned
   page is never larger than its requested byte cap. If an ordinary next row would cross
   the cap, the page stops before it. If one row cannot fit an otherwise empty page, the
   result is `unavailable/oversized_row` rather than an oversized or partial row.
   The singleton infrastructure-settlement header is subject to the same bounded-prefix
   and encoded-size checks before any relation is read.
6. The protected sequence and effect revision are captured with the page. Continuation
   succeeds only when both still match. Any protected append between pages, including an
   unrelated append, conservatively makes the cursor stale, preventing gaps or duplicates.
7. Section offsets reveal no protected key. Because a cursor is accepted only at the
   same protected frontier, offset ordering is stable across pages. It also survives a
   clean reopen or verified backup with the same installation, repository, sequence and
   effect revision. Writer epoch is reported separately and does not invalidate unchanged
   content.
8. The public observation layer correlates raw protected facts first, then recursively
   redacts the complete result envelope: fact, identity, source, nested keys and cursor.
   The final public size check includes any redaction expansion.

The accepted schema already indexes receipts by `(claim_id, receipt_id)`. It does not
provide complete observation indexes for historical claims by effect, reservations by
effect owner, or leases by claim. That can increase SQLite scan cost, but the SQL limit
and iterator stop still bound rows materialized into the runtime and public DTO. New
indexes would require a separately owned protected-schema migration; they are an optional
performance follow-up, not permission to mix schema or write-protocol work into B5.

## Result and error semantics

| Condition | Protected result | Public observation meaning |
|---|---|---|
| Exact effect does not exist | `{:error, :not_found}` | healthy absence |
| Returned prefix fits limits | successful canonical page | `truncated` may be true with a continuation |
| Receipt section is incomplete | successful page | settlement receipt history is explicitly `unknown` |
| Source/effect changes after page one | `{:error, :stale_protected_cursor}` | unavailable; restart pagination |
| Supported fact cannot fit the contract | `{:error, :protected_observation_oversized}` | unavailable; never healthy empty or corrupt |
| Missing/dead/unauthorized/ordinary I/O source | existing availability error | unavailable |
| Malformed request or cursor | `{:error, :invalid_protected_query}` | invalid/corrupt caller input, with no echoed value |
| Impossible protected row/status/version shape | typed protected corruption | corrupt |
| Retained SQLite/authority corruption | existing recovery corruption | corrupt |

An empty relation list is healthy only when the relevant section is proven exhausted.
Unavailable, corrupt and unknown states never collapse into an empty canonical result.

## Implementation change points after ownership release

- `foundry/lib/pramana_foundry/durable_store/protected_primitives.ex`
  - extend `query/2` with the new type;
  - add private `effect_observation_page/2`, strict request/cursor validation, source
    frontier capture, four bounded section readers, bounded row decoding and the size
    accumulator and exact singleton infrastructure-settlement reader;
  - leave `execute/**`, all mutation helpers and the legacy `"effect"` query unchanged.
- `foundry/lib/pramana_foundry/observations.ex`
  - make `read_target/3` use the bounded protected query;
  - update `validate_query/1`, `canonical_effect/2` and `build_page/6` for continuation,
    truncation and explicit unknown/unavailable mappings;
  - correlate before recursively redacting the final envelope.
- `foundry/lib/pramana_foundry/observations/query.ex` and
  `foundry/lib/pramana_foundry/observations/page.ex`
  - replace the bare public offset with a tagged cursor that can represent both target
    position and an in-effect continuation.
- `foundry/lib/pramana_foundry/observations/gateway_source.ex`
  - map stale cursors and oversized supported facts to unavailable while retaining the
    existing corruption classifications.

No change is required in `gateway.ex`: `Gateway.protected_query/3` and its capability
check remain the sole route. B5 must not modify Authority, Database, workflow reducers,
Coordinator, State, Tick, FR-08B files, pointer producers or the protected write protocol.

## Acceptance matrix

Add focused tests to `durable_store/protected_primitives_test.exs` for:

- wrong capability, missing/blank/oversized identity, and exact-effect enforcement;
- boundary and boundary-plus-one for claims, receipts, reservations and leases;
- one combined item cap across sections and exact byte-cap boundaries;
- an oversized scalar row that returns no raw value and does not allocate its full state;
- malformed, extra-field, cross-effect and cross-source cursors;
- unchanged continuation with deterministic ordering and no overlap or gap;
- any protected append between pages returning stale/unavailable.
- present, absent, required-but-missing and mismatched infrastructure-settlement carriers,
  including every singleton field, non-start correlation, the valid later-conflict
  transition and header byte accounting.

Add public tests to `observations_test.exs` for:

- end-to-end truncation before public materialization, plus a usable continuation;
- a large control state and multiple large inbox items, proving the public adapter only
  materializes the bounded effect page and never calls the legacy materializers;
- complete versus incomplete receipt provenance and authoritative terminal settlement;
- healthy absence distinct from unknown, unavailable and corrupt;
- secret-shaped identities and values in every emitted relation/source region, nested
  keys, live protected facts and continuation data, asserting against the serialized
  complete page;
- final public item and byte caps after redaction.
- malformed/cross-source page provenance, nested effect/relation/control/execution/
  settlement versions, page size/count and cursor frontier correlation.

Add lifecycle composition tests to
`durable_store/fr08a_fr19a_integration_test.exs` for clean reopen and verified-backup
continuation, writer-epoch change without content change, post-reopen mutation staleness,
and retained physical/structured corruption.

## Rebase and ownership constraint

The protected-core atomic correction is integrated at
`057f2902580235d844679c43ece571056b60b8a5`, and the coordinator released only this
read-query slice. The implementation must be additive atop that exact correction. It
must not transplant an earlier `ProtectedPrimitives` file or revise the atomic writer's
transaction, result or recovery protocol. The integrated infrastructure-settlement
carrier is consumed through allowlisted scalar reads and validated without changing its
write path. The full protected atomicity/recovery matrix remains mandatory. Until this
implementation is independently reviewed, B5 and FR-18A remain blocked.
