# FR-08A plan-binding correction — partial candidate record

Date: 2026-09-20

Status: **frozen partial candidate awaiting independent critical review; nothing
integrated, no acceptance claimed**

Implementer: Claude Opus 5. Governing design is
[the root-fact composition diagnosis](fr08b-root-fact-composition-diagnosis.md); the
implementation contract is [the plan-binding specification](plan-binding-specification.md).

## Exact subject

| Layer | Commit | Tree |
|---|---|---|
| Base `main` | `3f06a5a2b3b138dd2e45b3cbfea5261435e7d515` | — |
| Specification | `6df99cfec1d02ee01e5c04ea2b9c9c8e5b7b23d3` | — |
| Subcommit 1 — trusted codec | `24b8431` | `b4d88834d97a395a7d10694999bced3dbb93c397` |
| Prerequisite record | `c83ec2a` | — |
| Subcommit 2 — authoritative outputs | `aa0debe` | `618e0a27d00d880dcaf1115a790c85ad2f529143` |
| Subcommit 3 — protected discriminator | `d1b190d` | `202cb8afad06daaa20033d25fd524b1b6f1fb1c0` |

Branch `repair/fr08a-plan-binding`, worktree `/private/tmp/pramana-fr08a-binding`.

## What this candidate is, and is not

**It is** the settled, testable half of the correction: the closed plan codec, the
authoritative output derivation and the protected discriminator. All three are
self-contained, additive and independently reviewable.

**It is not** the end-to-end binding. No Gateway wiring exists, `commit_accepted_atomic_bundle/6`
still commits `envelope["proposal"]` unchanged, and no existing path changes behavior.
A bound lifecycle transition cannot yet commit. Subcommits 0, 4 and 5 remain outstanding.

## Why the remaining subcommits are blocked

Subcommit 0 — the versioned durable event vocabulary extension — is a prerequisite for
any end-to-end binding, and it is blocked on a decision that is not this implementer's to
make alone. `RecordCodec` accepts nine event types; the FR-08B kernel's closed vocabulary
has twenty-seven; they intersect in exactly one name. The exact extended vocabulary must
be agreed with the FR-08B kernel owner, because the only candidate vocabulary today lives
in unreviewed, mid-correction work preserved at `059546b`. `normalize_candidate/1` is
shared by the v1 and v2 paths, so the extension must be deliberately versioned rather than
appended. The full finding is in the specification's prerequisite section.

Subcommits 4 and 5 (Gateway wiring, then replay and idempotency revalidation) depend on
subcommit 0.

## Review focus requested

1. **Authority.** Can any path here let a caller-supplied value reach a domain carrier in
   place of an authoritative protected fact? `derive_outputs/2` is the only producer of
   substitution values and reads only staged results.
2. **Slot enforcement.** `markers_occupy_declared_slots/2` permits a bound fact at exactly
   three positions. Is that set correct and complete against the codec's event/projection
   carrier duality, and is the path enumeration in `marker_positions/3` exhaustive?
3. **Fail-closed behavior.** `infrastructure_discriminator/3` must never select the
   permissive branch under uncertainty.
4. **Non-interference.** Nothing may change the behavior of any existing v1 or v2 path.

## Checks

| Check | Result |
|---|---|
| `transition_plan_test.exs` | 39 passed |
| `atomic_bundle_test.exs`, seed 20929 | 21 passed |
| Durable store and observations suites, seed 20928 (at subcommit 1) | 174 passed |
| Warnings-as-errors compilation | passed |
| Formatting | passed |
| Documentation gate | 80 passed |

Canonical CI at the frozen candidate is recorded in the implementation log entry that
accompanies this record.

## Limits

No provider, daemon, credential, activation or deployment was used. No workflow reducer,
Coordinator, adapter, FR-08B path, pointer producer or activation path changed. This
record establishes no FR-08A acceptance, no FR-08B progress and no lifecycle behavior.
