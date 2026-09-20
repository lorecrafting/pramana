# FR-08A typed transition replay focused rereview — BLOCKER

Independent focused review, 2026-09-19 (Hawaii). **BLOCKER:** the correction closes
all six prior failures, but conflicting carriers inside an operation's known result
field still pass or fail according to their order. Nested lists in those fields are
also recursively interpreted. No current-authority rollback bypass was reproduced.

## Exact subject and scope

- Core `e31e3d5700506ae3513958ef79134cabf481e684`, tree
  `20aed5781c56f169a1f6f9e2ec76080b11571cd2`.
- Revision-bound gate/report `4c196fb78bbb5f93f279144e05000a13b840d965`, tree
  `0056e38cff64da1eac7620547f2ac4e24b4ee116`.
- Evidence/catalog tip `2af61206a6490a26c1e072a5d1e45968e55320e8`, tree
  `1a21923448fee26341bb9c33c08c71553acd1540`.
- Prior [transition review](fr08a-transition-review.md) at
  `267715d939837205e73c51f3ed8526ed483a759e`.

All three candidate trees were checked directly. Read the shared workflow, Foundry
orientation/strategy summary, FR-08A acceptance, R1/R5 contract, prior transition review,
correction source and maintained probes. This is a focused residual transition review;
F1/F3 were exercised through maintained checks rather than reopened as broad audits.
The subject predates integrated FR-19A. Its combined integration requires a separate
Astra-high review after this gate; this result cannot certify that future tree.

## T3 — Known carrier fields bypass the duplicate-conflict guard

In `protected_primitives.ex:4792`, `collect_typed_transition_snapshots/4` checks
additional, unknown direct fields against the known carriers. It does not apply the
same consistency rule among carriers inside a known field. At `:4858`,
`collect_direct_transition_snapshots/3` recursively traverses lists. At `:4887`,
`put_transition_snapshot/5` accepts an increasing revision and replaces the previous
snapshot, while rejecting a decreasing revision.

Fresh reproduction uses public reserve/create/claim/issue operations, stops the
disposable Gateway, and changes only the accepted issue command's `result` blob:
replace `facts.effect` with `[old_claimed_effect, current_issued_effect]`. The old
snapshot has revision one lower and status `claimed`; the current snapshot is the
unchanged issued result. All command inputs, metadata and protected current rows stay
unchanged. Recovery reports `ready`. Reverse the list and recovery fences. Wrapping
either ordering in one extra list produces the same order-dependent outcome.

The committed [fresh probe](fr08a-typed-replay-review-probes.exs) contains both
orderings and both nesting variants. The two old/current variants fail the required
recovery assertion; the two current/old controls fence. This is the same conflicting
snapshot class as the prior review, moved from the extra `duplicates` field into the
known `effect` field. The candidate's extra-field guard closes the old fixture but
does not satisfy order-independent rejection across typed carrier placements.

Current rows remain correctly derived from requests in this reproduction: it does
not demonstrate a second issuance or a forged current balance. The blocker concerns
the explicit retained-result schema/conflict requirement. A correction should validate
known fields' permitted cardinality/nesting and reject conflicting carriers within one
command regardless of ordering, without recursively interpreting opaque contents.

## Credited behavior and controls

`validate_typed_transition_replay/1` reads ordered command type/disposition/reason and
canonical request, derives lifecycle and accounting increments independently of result
maps, and compares exact current ledger/reservation/claim values plus effect lifecycle
and revisions. Existing effect provenance checks separately bind immutable request facts.
Replay uses one-step increments, not retained result revision jumps.

The unchanged 39-case matrix passes, including all six prior failures: matching forged
issue/current rewind, unsupported matching revision gap, the three shape-like receipt
payloads, and ascending extra-field duplicate snapshots. Maintained 41 cases also pass,
including original rewind/closed-generation/hold corruption and successive valid reclaim.

Fresh controls pass for effect/claim/reservation/ledger current revision ±1 corruption,
missing carrier revision, map-wrapped carrier refusal, identical known-field duplicates,
superseded claim result with impossible issued status, and reordered/invalid command
sequence refusal. Opaque diagnostic/artifact/receipt maps and nested diagnostic lists
are ignored; public receipt payloads containing protected shapes at their root, under
deep artifact keys, or inside nested lists all restart successfully. Prior 39 covers
unknown-to-success/failure/nonstart, duplicate terminal receipts, pending/claimed reset,
late nonstart after close and a lost settlement reply with idempotent recovery.

## Executed verification

Pinned Elixir 1.20.3 / OTP 29.0.5, fresh build and isolated disposable runtime/temp root
`/private/tmp/fr08a-typed-review.cgDx12`, reusing dependency sources only.

| Check | Actual result |
|---|---|
| Fresh `mix compile --warnings-as-errors` | exit 0; 108 project files |
| Maintained acceptance matrix | exit 0; 41 passed |
| Prior transition matrix, unchanged | exit 0; 39 passed |
| DurableStore + repair directories, legacy containment + effect checkpoint, seed 19411 | exit 0; 113 passed |
| Fresh typed replay probes, seed 9302 | exit 2; 44/46 passed, two T3 failures |
| Documentation gate, new evidence explicitly staged | exit 0; 80 passed |
| `git diff --cached --check` | exit 0 |

The fresh script reuses 22 prior final-review cases and adds 24 variations. An initial
42-case run already reproduced the same two failures; four additional schema/sequence
controls were then added, with no failing assertion weakened. Reproduce from `foundry/`:

```sh
sh /private/tmp/fr08a-typed-review.cgDx12/run.sh mix run --no-start --no-compile docs/fr-08/fr08a-typed-replay-review-probes.exs
```

| Artifact | SHA-256 |
|---|---|
| `run.sh` | `dcd611000f608467dc0af4e9cc2a529504c82f7d9215d52023e61eda2303091b` |
| `compile.log` | `cb18f39c1909dbf9a136c5cdc9a3bee40445f9cbb0c463fb030daf6cd9488bc2` |
| `maintained41.log` | `ee21edbf19e8c31efd93b06e6056598165bd0203b3137bd4b0f2a8a032462177` |
| `prior39.log` | `cefdd898952299f77d7acbc29aefd0707f082b5f46f69aba9f31745ac4221d5a` |
| `focused.log` | `3db5ed4d9c6932b51f9bdffd788de11e9a30c9e90a00c3538eb3b6d3634a03ac` |
| `fresh46.log` | `002774678fd41706e18215d047c0e2c257d1698402aa91fef3cbff16b1a7b271` |
| Fresh probe script | `36616af487b5f6cf7697fe6d810b9c4d882f66324ef77d5ca319547bae2090f7` |

No implementation, shared repair plan/log, provider, daemon, push or integration was
changed. No canonical full CI, physical-media recovery, nonempty migration/rollback,
provider behavior, FR-08B domain replay, combined FR-19A integration or activation is
certified. Correct T3 and obtain renewed focused review before treating this gate as
passed. These review-only artifacts do not change the frozen implementation subject.
