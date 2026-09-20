# FR-18A bounded effect-query independent review — BLOCKER

Independent review snapshot, 2026-09-20 (Hawaii), reviewer
`/root/fr18a_b5_review`, separate from the implementer. **BLOCKER for FR-18A.**
The new protected relation reader is bounded, but the complete public read still has
unbounded auxiliary materialization. Three additional observation defects concern
settlement reconciliation, settlement field integrity and bounded-response provenance.
No implementation was modified by this review.

## Exact subject and evidence

| Layer | Commit | Tree |
|---|---|---|
| B5 implementation/tests | `6812e5e673aa8d38fc6a68940f89f2d800dd469b` | `884a64628672b8dc2a2909c27f42f9a5d43a81bf` |
| Integrated-schema design correction | `2e801ea66b186f8c6bdbe5156369ae5ac5d6333c` | `ab5b2b6594a71752a3eca0e1e13d7664f0804a99` |
| Rebound FR-08A evidence | `fd774c3b1dbf01c6a9ea8d64c18653b660388c11` | `13ffc27489651349cd51573e50384d64bfbc35f1` |
| Frozen candidate documentation | `2d17717a24c1f5fac691574f503322d6780bb0cd` | `c262cc0f3a84ca1cf91f079db78ccdc168d355a8` |

Branch `repair/fr18a-honest-observations`, worktree
`/private/tmp/pramana-fr18a.8plkoi`. The branch was clean at review start. The last
candidate layer changes only the candidate record and README route. Direct diff
inspection shows the protected-primitives change is additive query code; the legacy
`effect` query and protected mutation helpers remain unchanged. Gateway, Database and
Authority are byte-identical to the integrated atomic base `057f2902580235d844679c43ece571056b60b8a5`.

Read the shared workflow, Elixir conventions, Foundry route, FR-18A criteria, relevant
workflow identity/authority/observation/replay and R4a contracts, prior FR-18A reviews,
the design/candidate, integrated atomic settlement-presence contract and accepted combined
review. Inspected the exact implementation/test diff and its surrounding read, write,
recovery and scalar-validation paths.

## B5a — Auxiliary control and inbox reads remain unbounded

`Observations.read_target/5` first obtains the bounded effect page, then invokes
`read_control/3` and `read_execution/3`. Those still request the legacy `control` and
`inbox` facts. `simple_fact/4` selects and decodes the entire control state blob;
`inbox_fact/2` selects every matching inbox item through `Database.query/3`/`fetch_all`
and decodes every payload before deriving its tiny execution summary. Neither path
receives the page's item or byte budget.

The independent public-query probe uses accepted protected commands to create a
256 KiB control diagnostic and eight 256 KiB inbox observations. With `max_bytes: 8192`
and `limit: 1`, the final public page is within its cap, but an adapter wrapping the
actual Gateway source observes an already materialized control fact larger than
256 KiB and an eight-row inbox fact larger than 2 MiB. No private data is printed.
This is a concrete size demonstration, not a throughput benchmark or timeout claim.

**Minimal correction:** supply bounded scalar control/execution summaries for this
observation route, preferably inside the same effect observation snapshot. Derive the
inbox resolution using bounded SQL scalar queries and deterministic ordering without
loading item payloads. Count the summaries toward the byte budget. Preserve legacy
control/inbox/effect interfaces for their existing consumers. Add a public-path regression
that detects payload and row materialization before the DTO, not just final output size.

## B5b — Valid non-start reconciliation is reported as corruption

The bounded settlement reader requires both current effect and claim status to equal
`non_started` at protected-primitives lines 4041–4042. The public singleton validator
repeats the effect-status restriction. However, the accepted atomic protocol preserves
the immutable infrastructure settlement when a later conflicting receipt moves the
effect/claim to `reconciliation_required`.

The independent probe performs the legitimate accepted non-start bundle and then its
quarantined conflicting receipt, using the same public lifecycle as the maintained atomic
test. The legacy effect query reports `reconciliation_required`, and a real verified
`Gateway.backup/2` succeeds with complete authority validation. The new public observation
nevertheless returns `corrupt/source_corrupt`. This regresses the earlier B2 guarantee
for the newly integrated singleton path; no raw SQL corruption is involved.

**Minimal correction:** distinguish the immutable non-start receipt/settlement provenance
from current reconciliatory effect/claim status. Validate the supported conflict transition
and report current outcome `unknown/reconciliation_required` with the historical settlement
retained. Keep impossible transitions corrupt. Correct the design's blanket requirement
that a present historical settlement implies current `non_started`, and cover both direct
protected and public reads after this accepted conflict sequence.

## B5c — Settlement fields are not bound to authoritative values

`bounded_infrastructure_settlement/2` correctly joins effect, claim and receipt identities
and checks non-start receipt semantics and required presence. For role, work owner,
generation, predecessor, failure class and ordinal, it only checks nonempty/type/range.
It does not perform the field agreement enforced by the integrated recovery validator.

Six independent disposable fixtures each change one singleton scalar after an accepted
atomic non-start: role to `pm`, work owner to a different owner, generation to 9,
predecessor to a different effect, failure class to another value, or ordinal to 900.
Every public query returns `ok/canonical` carrying that wrong value. These probes use
the same live-store corruption boundary as the candidate's required-absence test. They
do not claim that an unprivileged caller can write SQL or that coherent administrator
replacement of all authority must be detected.

**Minimal correction:** within the same bounded snapshot, compare all emitted singleton
fields with bounded authoritative effect/receipt/accepted-operation scalars and the
validated ordinal/lineage evidence. Do not restore full state/proof/payload decoding.
Retain required-absence and unexpected-carrier rejection. Add one-field mismatch cases
alongside the existing row-deletion case, including the valid conflict case above.

## B5d — Bounded-response source and nested versions bypass validation

`Observations.canonical_effect/2` at lines 243–302 never reads the new page's `source`.
It also does not check nested effect/relation schema versions before assigning canonical
quality. A controlled adapter variation delegates snapshots and ordinary facts to the
real Gateway and changes only the bounded result. Missing source, another repository,
wrong protected frontier, wrong effect revision, effect schema 999 and relation schema
999 all yield `ok/canonical`. The page is labeled with the unchanged snapshot's source;
one variant even emits relation schema 999 as canonical.

The production Gateway reader normally produces coherent fields, which limits current
exposure. This is still the same malformed-source contract covered by original B4: an
adapter mismatch cannot be relabeled as canonical root evidence. The candidate's new
synthetic redaction fixture already has mutually inconsistent snapshot and page sources,
so its green result does not exercise source correlation.

**Minimal correction:** validate the bounded response schema and source shape, correlate
its installation/repository/frontier to the surrounding snapshot and its effect revision
to the header, and validate supported nested versions and page/cursor consistency before
copying the result into a canonical envelope. Preserve whole-envelope redaction after
correlation. Add one-field source/version negative cases for the new response format.

## Behaviors preserved and checked

- The new request is capability-bound and exact-effect-only. Static allowlists accept
  no SQL/table/filter input. Independent extra/missing-field and wrong-type/version/
  section/negative/excessive-offset cases refuse; cross-source and post-append cursors
  refuse in the maintained matrix.
- The query's transaction encloses source, effect, singleton and all relation sections.
  SQL text prefixes cap selected strings at 257 bytes; static relation SQL uses
  `LIMIT remaining + 1`, stable ordering and `Database.fold/5`. No state/proof/raw payload
  enters the new protected page. An external append cannot tear its read transaction.
- Independent 53-relation traversal with a 50-item cap returns 50 then 3 distinct,
  correctly ordered relations. Maintained cases cover the claims→reservations→leases
  boundary and receipt-bearing settlement pages. Clean reopen and verified backup
  continuation, epoch changes and another source are covered by rerun maintained tests.
- An independent byte-cap sweep from 1024 through 8192 bytes in 64-byte increments
  includes oversized, byte-truncated and complete results. Every successful result's
  measured external-term size equals its declared size and stays within its requested cap;
  the non-start singleton is included. This is bounded fixture evidence, not exhaustive
  coverage of every scalar-length/section combination.
- Required singleton absence, healthy optional absence, physical and structured corruption,
  wrong capability/dead source, absent/unavailable/present pointers, ordinary reconciled
  success/failure/conflict, whole-envelope representative-secret redaction, top-level
  source versions and execution-summary shape all retain their maintained passing cases.
  B5b and B5d identify the uncovered new paths, not a failure of every earlier correction.

## Executed checks and provenance

Fresh isolated build `/private/tmp/fr18a-b5-review.ueT8jy/build`; dependencies from the
candidate CI's locked isolated directory
`/private/tmp/pramana-foundry-ci-z85oT0SyFFAndueM16ZsCG8K/deps`. Non-login shell, explicit
PATH to repository-pinned Elixir 1.20.3 and Erlang 29.0.5, `TMPDIR=/private/tmp`,
`MIX_ENV=test`, `COORDINATOR_TICK=0`. No toolchain installation or global modification.

| Check | Result |
|---|---|
| Fresh compilation and independent [review probes](b5-review-probes.exs), seed 18055 | Exit 0; 25 passed: 13 inherited atomic cases and 12 review cases |
| Observations, protected primitives, atomic bundle, critical corrections, FR-08A/FR-19A integration and revision-bound boundary tests, seed 18056 | Exit 0; 50 passed |
| Rebound FR-08A source/loaded-BEAM binding, deterministic frozen report and altered-loaded-code refusal | Passed within the 50-case matrix; all seven probes ready for the named implementation |
| Candidate CI artifact hashes and exact clean pre/post source identity | Matched |
| Staged documentation gate and whitespace check | Exit 0; 80 passed / passed |

The review probes assert the defects currently reproduced as well as positive controls;
their zero exit status is not an FR-18A acceptance result. One intermediate new probe
incorrectly used a reservation's claim ID as its row identity and failed 1/25; correcting
that review-only assertion to use the reservation ID produced the final successful run.
The initial documentation check did not include the untracked report in its Git file
inventory and reported its README link missing; staging the three review paths yielded
the successful 80-case check above.

Independently inspected the canonical candidate manifest
`/private/tmp/fr18a-b5-ci-fd774c3/provenance.json`: exact clean evidence commit/tree above
both before and after, policy-matching Elixir 1.20.3 / OTP 29.0.5 / ERTS 17.0.5, all
dependency/compile/format/test/inventory/escript stages passed, exit 0. The manifest stores
a test-output hash rather than counts; 643 passed, 13 skipped and one optional exclusion
are attributed to the candidate record. No fresh full CI is claimed by this review.

Verified hashes:

```text
eb9b2245d675cf2fb86906915e20308b4d70dc337f1f143457494f791af3c378  provenance.json
6deec271a67375ee1a1971f47a50e9b1d805b3fff0f1c8a3d8b55c78f5dbd09a  pramana_foundry
4f0dd34f26ec1efe00e12f052aaa25804e45e82569eabbc432322abb42ccbb90  protected_primitives.ex
```

The loaded protected-primitives MD5 `870e4c17641ab3dce71bf92241c14349` is checked by
the rerun binding test. The documented unnecessary local mise reinstall remains an
implementation-session incident; the exact final manifest, not assumptions about the
shell's default binaries, establishes the credited toolchain.

## Disposition and limits

Correct B5a–B5d, update the design where it contradicts the valid reconciliation lifecycle,
refreeze and obtain an independent rereview. FR-18A remains blocked. FR-18B producer/board/
usage wiring, FR-09/15a harness and OS isolation, FR-17 pointer production/activation,
FR-19B maintenance expansion and FR-22 full lifecycle remain deferred. Missing observation
indexes are a performance suggestion, not permission to change the protected schema here.

No provider, live daemon, global toolchain mutation, push, integration, activation or
deployment was performed. Fixture SQL writes and accepted fixture commands affect only
owned disposable stores. This review changes only its report/probe and documentation route.
