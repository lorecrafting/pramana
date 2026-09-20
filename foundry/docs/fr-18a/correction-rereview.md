# FR-18A observation correction narrow rereview — BLOCKER

Independent narrow rereview, 2026-09-20 (Hawaii). **BLOCKER overall.** B2, B3,
B4 and the protected pointer vocabulary are corrected at the exact subject below, but
B1 remains open for a physically corrupt SQLite store. B5 was deliberately not reviewed
or waived; the original unbounded protected-query blocker remains in force.

## Exact subject and scope

- Correction: `ab645ad74715c59c545bf7c06a94fc3263b1252f`, tree
  `1264e3eeb47d1a54b0c9f3d212a122931fe927dc`.
- Parent review: `84848a1b13278d052ee590705a12fb384abbd5c6`, tree
  `af08cda6149b7039075f50ea0ef3f6f22caa62b9`.
- Branch/worktree: `repair/fr18a-honest-observations`,
  `/private/tmp/pramana-fr18a.8plkoi`.

Direct Git inspection reproduced both identities. The exact parent-to-correction diff
contains only:

```text
M foundry/lib/pramana_foundry/observations.ex
M foundry/lib/pramana_foundry/observations/gateway_source.ex
M foundry/lib/pramana_foundry/observations/observation.ex
M foundry/test/pramana_foundry/observations_test.exs
```

No protected-store, Gateway, provider, daemon, activation or deployment path changed.
I reread the original B1–B4 findings, inspected the full correction diff and affected
tests, traced the FR-19A recovery/error path and reran independent live/fake-source
variations. The result below is limited to B1–B4 and pointer vocabulary.

## Rereview verdict

| Item | Verdict | Evidence |
|---|---|---|
| B1 corrupt versus unavailable | **BLOCKER** | Logical authority corruption is fixed, but physical SQLite corruption reopens with a raw binary recovery reason and is still mapped to unavailable. |
| B2 terminal outcome consistency | **PASS** | Live unknown→success, unknown→failure and terminal-success→conflicting-receipt quarantine agree with the protected effect/claim state and retain ordered receipt history. |
| B3 whole-envelope redaction | **PASS** | Live identity and source values plus synthetic nested values and secret-shaped keys are removed from the complete inspected page. |
| B4 malformed-version quality | **PASS** | Every emitted SQL/protected/protocol/event/projection version must be the supported string; malformed versions and malformed execution summaries become corrupt. |
| Pointer vocabulary | **PASS** | `absent`, `unavailable` and `present` map to the matching observation status; the former non-schema `available` spelling is rejected. |
| B5 bounded protected materialization | **NOT REVIEWED; STILL BLOCKING** | Explicitly excluded from this narrow rereview. No statement here changes the original finding. |

## Residual B1 — Physical corruption is still called unavailable

The correction correctly classifies structured recovery reasons such as
`{:authority_corrupt, ...}` and `{:protected_corrupt, ...}`. The original logical-version
probe now returns a corrupt page. Missing stores, dead processes and bad capabilities
remain unavailable without exposing raw reasons.

The independent probe then repeats FR-19A's accepted physical-corruption method: initialize
a disposable store, synchronously overwrite 256 bytes at offset 100, and reopen it. The
Gateway correctly fences in recovery, but its reason is the untyped binary
`"database disk image is malformed"`. `GatewaySource.classify_recovery/1` falls through
to unavailable, producing:

```elixir
%Page{
  status: :unavailable,
  quality: :unavailable,
  error_code: :source_unavailable,
  items: []
}
```

The raw reason does not leak, which is correct, but the classification is dishonest. A
physically corrupt retained store is neither a missing store nor an operationally
unreachable source. This reproduces B1 through the real Gateway startup/recovery path and
FR-19A-style damaged bytes.

Minimal correction: classify SQLite corruption into a stable typed reason before it
reaches the observation adapter, preferably at the Database/Gateway recovery boundary
using engine result codes rather than matching human-readable error strings. Then map
that typed reason to the corrupt envelope and retain unavailable for missing/process/
capability/I/O availability failures. Add the physical byte-corruption reopen case to
the maintained observation tests.

## B2 — PASS

The correction validates effect/claim/receipt status shapes and makes the authoritative
protected effect status govern the public outcome. Receipt history remains provenance.
Independent live sequences established:

- `unknown` followed by `succeeded` reports `succeeded` with history
  `unknown, succeeded`;
- `unknown` followed by `failed` reports `failed` with history `unknown, failed`;
- a conflicting terminal receipt moves the protected effect and claim to
  `reconciliation_required`, and the observation reports an unknown reconciliation state
  rather than preserving the old success as current truth.

No raw receipt payload entered the DTO. These are real protected commands and queries,
not manufactured fake facts.

## B3 — PASS

Redaction now applies after observation construction to both identity and fact maps, then
to page source metadata. The live probe uses distinct representative secret shapes in
ticket identity, installation identity, repository identity and writer epoch; none remain
in the inspected page. A separate fake-source variation places a secret-shaped value
under a nested secret-shaped map key in an emitted field. The result contains only
`[REDACTED_KEY]` and `[REDACTED]`.

The public error envelopes still contain no source or items, so raw recovery reasons do
not cross the boundary. Redacting secret-shaped identities necessarily hides their exact
text, but ordinary canonical IDs remain unchanged and correlated.

## B4 — PASS

The source now requires all five emitted version identities—SQL schema, protected schema,
protocol, event and projection—to equal supported version `"1"`, includes all five in
the output and in before/after stability comparison, and refuses nil/unsupported values
as corrupt. Execution summaries now validate revision and sequence bounds, sealed/open
consistency and the protected resolution vocabulary before receiving canonical quality.

The independent probe mutates each version separately and observes only a corrupt page.
The focused suite additionally covers malformed execution revision, sequences and status.

## Pointer vocabulary — PASS, production still deferred to FR-17

The observation layer now uses the protected table's exact `absent`, `unavailable` and
`present` vocabulary. Each yields its corresponding item status, and `available` is
rejected as corrupt. This closes the interface mismatch identified in the first review.
It does not manufacture pointer producers or positive activation evidence: the current
live protected store still validates only its three seeded absent slots, and FR-17 still
owns real pointer production and activation receipts.

## Reproducibility and checks

The committed [narrow rereview probe](fr18a-correction-rereview-probes.exs) uses only
disposable local databases and synthetic values. From `foundry/`:

```sh
MIX_ENV=test \
MIX_BUILD_PATH=/private/tmp/fr18a-rereview-build \
MIX_DEPS_PATH=/Users/raymondluong/dev/pramana/foundry/deps \
COORDINATOR_TICK=0 \
mix run --no-start --no-compile \
  docs/fr-18a/fr18a-correction-rereview-probes.exs
```

Observed result: exit 0, with the explicit result
`B2-B4/pointers pass; physical-corruption B1 remains`.

The focused maintained matrix was run independently:

```sh
MIX_ENV=test \
MIX_BUILD_PATH=/private/tmp/fr18a-rereview-build \
MIX_DEPS_PATH=/Users/raymondluong/dev/pramana/foundry/deps \
COORDINATOR_TICK=0 \
mix test test/pramana_foundry/observations_test.exs \
  test/pramana_foundry/durable_store/protected_primitives_test.exs \
  test/pramana_foundry/durable_store/fr08a_critical_corrections_test.exs \
  test/pramana_foundry/durable_store/fr08a_fr19a_integration_test.exs \
  --seed 18241
```

Observed result: exit 0; 27 passed. The reviewer host still exposes Homebrew Elixir
1.20.4 / OTP 29 / ERTS 17.0.6 rather than the repository's exact patch-level pins, so no
full-CI result is claimed for the correction. No provider, daemon, credential, mutation,
deployment, activation or external effect ran.

**Disposition:** B2–B4 and pointer vocabulary pass this narrow rereview. Correct and
refreeze B1 with the physical-corruption regression, then request another narrow review.
B5 independently remains an explicit blocker pending a bounded protected query and must
not be inferred closed from any result in this report.
