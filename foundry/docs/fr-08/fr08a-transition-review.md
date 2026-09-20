# FR-08A residual F2 transition review — BLOCKER

Independent focused rereview, 2026-09-19 (Hawaii). **BLOCKER.** The four prior
unchanged-command failures now fence recovery. The replacement recovery logic still
trusts result-shaped maps without deriving their legal meaning from the authenticated
operation, and treats arbitrary observation payloads as protected authority.

## Exact subject

- Candidate `4a37754bf06b7d750d19765de7ff70b0c843147f`, tree
  `23f6393eba01b8271792f7f75b53662031afb43f`.
- Core `35ebb1d6d2d9a1661686f9f14e17c0dbeb0d2de0`, tree
  `2ed0b1ebf0e3aaa34ad404c62cb805b696679930`.
- Rebound evidence `0582f198118525090ed03858285a24d2378de085`, tree
  `425a793c6a08bf0807124d52bf2eaf2123f44a49`.
- Prior acceptance review at `7489193e468d12766207af5e3a4ca7723616d236`.

All three subject trees were checked directly. This review read the shared workflow,
Foundry orientation, strategy summary, FR-08A acceptance and F07/F16 routing, relevant
R1/R5 recovery/settlement contract, prior acceptance review, core correction diff and
affected recovery/live settlement paths. Scope is residual F2; F1/F3 controls were
rerun through the maintained scripts, not independently reopened as broad investigations.
This candidate predates integrated FR-19A Gateway changes. No result here applies to
the later combined integration; that requires a separately constructed and reviewed tree.

## T1 — An issued authorization can still be rewound by matching result carriers

`protected_primitives.ex:4135` walks commands ordered by sequence but discards their
operation, disposition and canonical request when collecting snapshots. At `:4188`,
any increasing revision is accepted; no issue transition is reconstructed. Current
effect status/revision and complete claim facts are then compared with these snapshots.
`validate_root_commands/1` binds result envelope metadata, not the semantic facts.

Fresh reproduction: publicly reserve, admit, claim and issue one launch. Stop its
disposable Gateway. Rewind effect/claim statuses to `claimed` and reservation status
to `reserved` in columns and canonical states, retaining their revisions. Change only
the accepted `issue_claim` result's claim/effect status fields to `claimed`. Every
command sequence, ID, actor, request digest, canonical request, operation, disposition
and reason remains byte-for-byte unchanged, verified by the probe. Recovery reports
`ready`; a public second `issue_claim` returns `accepted`, status `issued`, for the
same claim and request. No settlement occurred.

Unlike the four prior probes, this fixture intentionally alters retained result facts.
It tests logical provenance against retained authenticated inputs, not resistance to
an administrator replacing every input. An accepted issue operation cannot legally
produce the supplied claimed result. Binding current carriers to that result does
not close F2's transition-derivation obligation.

A supporting probe raises the last issue result's effect revision and matching
effect row/state by ten. Recovery also reports ready, with no intervening transitions.
This is direct evidence that increasing revision numbers are accepted as history.

## T2 — Valid opaque receipt payloads prevent recovery

`collect_transition_snapshots/3` recursively traverses every map/list in result facts,
including `receipt.payload`. The recognizers at `:4170`–`:4184` infer authority solely
from keys such as `effect_id`, `claim_id`, `ledger_id` and `authorized`.

Three independent public-only histories admit and issue a launch, then successfully
settle it with an authenticated receipt containing a diagnostic map in its payload:

- effect-shaped: `effect_id=e`, `revision=99`, `status=diagnostic`;
- claim-shaped: the above plus `claim_id=cl-e`;
- ledger-shaped: `ledger_id=root`, `generation=0`, `authorized=20`, `revision=99`.

Each settlement is accepted. Each restart enters recovery with the respective
`root_effects`, `root_claims` or `root_ledgers` transition corruption error. These
fixtures contain no SQLite mutation and require no corrupted history. Observation
payload data is mistakenly promoted to authoritative state during recovery.

The collector is also sensitive to nested carrier ordering: inserting both the old
claimed effect snapshot and new issued snapshot in one issue result permits restart
in old/new order but refuses new/old order. Same-revision conflicting duplicates fence;
identical duplicates pass. These diagnostic variations support replacing shape-based
recursive collection with operation-specific, schema-bounded transition validation.

## Credited correction and controls

The unchanged maintained acceptance script passes **41 tests**, including all four
prior failures: issued rewind in the same epoch and across takeover, closed generation
reopening, and issued hold reduction 4→1 without settlement. It also retains two
successive valid reclaims, stale takeover rejection, deep ancestry/F1 and deadline/F3.

Source inspection confirms reservation IDs are uniquely bound to accepted reserve
inputs, with ledger/generation/owner/units checked, and current status derived from
effect, claim and retained receipts. Existing relation checks supply dimension binding.
This closes the exact prior hold-forgery case, but cannot compensate for T1's forged
effect/claim lifecycle. The implicit-cancel exceptions require later accepted control
cancel or a matching generation/ancestor close/reset; fresh pending/claimed reset
controls restart successfully. These checks were inspected and exercised, not claimed
as an exhaustive proof of all implicit balance transitions.

New positive controls pass for unknown→success/failure/proved-nonstart, duplicate
terminal receipt, pending and claimed reset cancellation, late nonstart after close,
and lost settlement reply followed by same-ID restart retry with exactly one consumed
unit. A repeated fresh close command is correctly rejected as already closed.
Missing issue facts, conflicting same-revision carriers and new/old regressive
carriers fence. The old/new case above and a matching +10 revision gap remain accepted.

## Executed checks and reproducibility

Pinned Elixir 1.20.3 / OTP 29.0.5; fresh build and isolated runtime/temp roots under
`/private/tmp/fr08a-transition-review.e9tElo/`, reusing existing dependency sources.
No provider, daemon, integration, push, shared plan or implementation file was changed.

| Check | Actual outcome |
|---|---|
| `mix compile --warnings-as-errors`, fresh build | exit 0; 108 project files |
| Maintained `fr08a-acceptance-review-probes.exs` | exit 0; 41 passed |
| DurableStore + repair directories, legacy containment + effect checkpoint, seed 9411 | exit 0; 112 passed |
| [Fresh transition probes](fr08a-transition-review-probes.exs), seed 9302 | exit 2; 33/39 passed, six required-behavior failures described above |
| Documentation gate | exit 0; 80 passed |
| `git diff --check` | exit 0 |

The fresh script reuses the unchanged 22-case final-review artifact and appends 17
independent variations. The first exploratory run used an invalid unknown proof and
expected repeated close acceptance; those fixture assumptions were corrected to the
actual contract (`outcome_unknown`, durable already-closed rejection). No implementation
assertion for the six final failures was weakened. The final script/log hashes below
identify the final run; earlier exploratory logs are not acceptance evidence.

From candidate `foundry/` after compiling with the recorded environment:

```sh
sh /private/tmp/fr08a-transition-review.e9tElo/run.sh mix run --no-start --no-compile docs/fr-08/fr08a-transition-review-probes.exs
```

| Artifact | SHA-256 |
|---|---|
| `run.sh` | `6c79516edeeb3394d527458202612fc5258e1477fd7638c89b4239a23288e569` |
| `compile.log` | `cb18f39c1909dbf9a136c5cdc9a3bee40445f9cbb0c463fb030daf6cd9488bc2` |
| `maintained41.log` | `f82fc006cd76cbb814db0ccc1515c9b0028d5a9b0ecb96a8a4ad3aa580e16103` |
| `focused.log` | `f9184f034b636ad99f3cbe58aecf414450b87055136ac2d7d9d6edd930f4c1ba` |
| `variations-final.log` | `272538111de1c4d4c240b6902c469bdf88ebad7bd4117f88155d7cc4dff663ce` |
| committed transition probe | `6d2a3dcb22db8a95bf7d772d70ada0b85f547a1341208f9cdf59e3304a50db1e` |

No canonical full CI, physical-media recovery, nonempty migration/rollback, provider
behavior, FR-08B domain replay, FR-19A combined integration or activation is certified.
The scoped blockers require correction and renewed independent review before FR-08A
acceptance. Review-only files do not change the frozen implementation subject.
