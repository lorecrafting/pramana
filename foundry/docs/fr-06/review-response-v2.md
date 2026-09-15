# FR-06 response to independent review — version 2

2026-09-12. Responds to [independent review v1](../FR-06-DESIGN-REVIEW.md), which is
preserved unchanged. **Proposed resolutions; independent re-review required. FR-07
remains blocked.** This is a design revision, not implementation acceptance or a new
audit. The agreed product/authority contract in REPAIR-PLAN is unchanged byte for byte.

## Input provenance

The pre-revision manifest's workflow contract, storage script and results matched their
recorded SHA-256 values. REPAIR-PLAN differed at its review-status passages, as the review
explicitly documented. All other inputs in the review's recorded hash inventory matched
except the similarly documented Foundry status update in docs/PLAN.md.

Reversing **only** those status edits in memory reproduced the exact reviewed hashes:

| Input | Current at start of v2 | Reconstructed pre-review hash |
|---|---|---|
| foundry/docs/REPAIR-PLAN.md | b049e1f3e8408f91a47928f5cbafb090ca2d8cb6d5532dde5353f08786f2eef0 | d493019f7f57c4bc8b132cbe211fc8fd72d92fb4e50d0336c7d8beac475045a2 |
| docs/PLAN.md | 174d8e3c4a2549cd25804f4f779f26f6189c78b0c5296944dbc4d5f708ebf628 | 03d38d0065954c2eccaa84c1a47789363809b12ae591dda58651d9ab5c48fee9 |

Thus the mismatch is accounted for, not unexplained proposal drift. Historical reviewed
hashes remain in the original review; the updated [manifest](manifest.json) covers the
v2 inputs, including this response and verification notes. It intentionally omits its
own hash to avoid a self-reference. Inputs are working-tree bytes, not a new commit.

## R1 — accepted; explicit claim/issue ordering proposed

**Revised passages:** [Durable claims and recovery](../WORKFLOW-CONTRACT.md#r1), especially
the effect-state table, the `issued` boundary, ordering table, cancellation acknowledgment
and takeover paragraphs; [integration reconciliation](../WORKFLOW-CONTRACT.md#integration).

The objection holds: a pre-action check cannot prevent an already checked worker from
running after cancel. V2 makes claim/issue/cancel/revocation/takeover short serialized
transactions in the protected gateway. A pending intent grants no authority. A claimed
operation can still be revoked. A durably issued operation authorizes one exact bounded
action; cancellation committed afterward acknowledges an outstanding action, not its
cessation. Duplicate effect IDs and different IDs for the same semantic operation cannot
create a second delivery. Retries must name a settled predecessor and prove quiescence.

**Protocol argument:** Let I be issued commit and C cancellation commit. If C precedes I,
I's control precondition fails and no worker may act. If I precedes C, C records I in its
outstanding set and returns cancel_requested; success or failure later settles I. There
is no promised third case where cancel reports all work stopped while an issued worker
is still permitted to act. An old ref after takeover is insufficient because the old
issuer could still execute CAS. V2 requires issuer/channel quiescence plus actual ref
inspection before declaring non-start or permitting another claim.

**Disposition/limits:** Addressed in design, not closed by self-review. This deliberately
allows an issued action to finish after cancellation acknowledgment and makes that limit
visible. Exhaustive interleavings, stale owner enforcement and actual Git/launcher/release
behavior remain FR-10/14/15/15a/17; late claim settlement and budget effects are also FR-08/16.
No new process, Git or broker probe was run in this revision.

## R2 — accepted; reusable authentication removed from arbitrary-tool authority

**Revised passages:** [Authenticated harness separated from arbitrary tools](../WORKFLOW-CONTRACT.md#r2),
including gateway request checks, fixed OMP/tool bridge configuration, same-slot denial
argument and unsupported-capability outcome; [request reservations](../WORKFLOW-CONTRACT.md#r5).

The review's own-account bypass is valid even without cross-worker credential theft.
V2 uses a protected authentication gateway, a pinned trusted OMP harness and a separately
isolated arbitrary-tool worker. Only the gateway holds reusable subscription auth. It
accepts fixed semantic provider requests for a durably claimed request/reservation,
fixes billing/profile/model fields and disallows unrestricted proxying or hidden retries.
The harness's private execution capability never enters model-visible tool context.
Tools run through an inert remote bridge, cannot load code into the trusted harness,
and cannot reach reusable auth, its socket, process memory or direct provider egress.
Herdr attaches presentation without transferring operator/harness authority.

**Protocol argument:** A tool-launched second OMP/curl has neither reusable auth nor the
harness capability or permitted provider network path. Asking the authorized harness for
more model work still requires a fresh gateway request claim with available allocation.
Changing request fields cannot select another billing channel because the gateway derives
them from the immutable authorized execution. This is an enforcement responsibility and
boundary, not a model prompt telling an agent not to bypass it.

**Disposition/limits:** Addressed in design; installed OMP support is unknown. FR-15a must
prove actual OS/socket/process/network denial and same-slot bypass resistance; FR-09 must
prove gateway routing, isolated tools, disabled extension discovery, request accounting and
a bounded authorized subscription smoke in that environment. The prior help inspection
and storage spike establish none of this. If OMP cannot support the adapter contract,
execution remains blocked for a bounded integration decision; no credential copying,
paid fallback, replacement harness or governing-policy exception is pre-authorized.

## R3 — accepted; autonomous kernel repair restored in the proposal

**Revised passages:** [Autonomously repairable kernel, protected verifier](../WORKFLOW-CONTRACT.md#r3),
the ownership/upgrade table, verifier predicates and counterexample; [activation write-set
and root artifact exclusions](../WORKFLOW-CONTRACT.md#integration). FR-15a/17/20/22 now
explicitly distinguish the kernel from the protected root.

V1's exclusion was an unsupported narrowing, not a necessary consequence of policy
protection. V2 selects the review's recommended direction within the existing contract:
ordinary lifecycle/replay/scheduler/recovery kernel repairs may activate autonomously;
policy/gate/credential/activation authority remains with a fixed, operator-installed root.
The updatable kernel runs outside the root process and sends bounded transaction proposals.
The root owns durable writes and independently verifies protected facts. Kernel projections
cannot mint budget grants, substitute review/check receipts or update accepted refs.

**Protocol argument:** A replacement kernel can correctly change how a failed developer
attempt is replayed and then be activated through the normal reviewed-build path. A
kernel that falsely projects `integrated` or infinite remaining budget still cannot get
a ref update or extra model request: the root reads actual Git/receipts and its own ledger.
Including altered verifier binaries in a source candidate does not install them; the
routine artifact install allowlist excludes the root and its policy/check configuration.
The root needs safety predicates, not a duplicate of the full lifecycle reducer.

**Disposition/limits:** Addressed in design, subject to independent assessment of whether
that interface is both small enough and sufficient. No operator decision to narrow the
product is requested or presumed. FR-17 must activate an actual kernel repair with root
hashes/policy fixed and reject forged authority requests; FR-20/22 must exercise this path.
If implementation cannot separate these concerns, reopen R3 with the concrete alternatives
in the contract: factor the verifier further, or seek explicit operator agreement for
an enumerated permanent kernel exclusion. The latter is not an available silent fallback.
Safety against all arbitrary program bugs is not proven by this protocol argument.

## R4 — accepted; legal states, result precedence and cleanup specified

**Revised passages:** [Legal lifecycle and controls](../WORKFLOW-CONTRACT.md#r4), including
entity vocabularies, sealed-inbox rule, from-state/guard table, successful-result cleanup,
check classification, drain/stop and non-session cancellation rules.

V2 names ticket phases, attempt phases/dispositions, execution closure/result facts, check
states and orthogonal controls; unlisted commands reject and obsolete observations cannot
mutate a newer owner. Successful attempts end at verified integration, distinct from
successful developer execution. A frozen valid candidate survives an abnormal developer
exit. If exit is observed first, seal the authenticated inbox and process its earlier
artifacts before deciding no valid result exists; unknown stream completeness blocks.
The kernel requests developer close and invalidates productive timers immediately after
valid freeze, not after review. Unknown cleanup retains the slot/lease.

Actual check assertion failure requests a fresh correction; infrastructure failure/timeout
retries the same candidate within check budget, with no fabricated approval. Reviewer
correction under drain becomes blocked queued work. Stop can finish once issued work and
cleanup settle while leaving that durable blocked correction; it cannot claim completion
with an unknown live worker. Cancellation finalization covers builds, checks, imports,
Git and release operations, preserving actual integration/deployment outcomes.

**Protocol argument:** Frozen candidate then abnormal exit applies the cleanup row, not
the no-valid-result failure row. Sealed input with a valid earlier artifact converges to
the same result after validation. Correction under drain cannot launch a developer and
does not prevent stop merely because the correction exists. Issued Git success during
cancel finalizes as integrated plus cancelled-after-integration, never nonexistent work.
These guards choose outcomes previously left to downstream implementers.

**Disposition/limits:** Addressed in design. FR-08/11/12/13/14/17/18 retain real reducer,
producer/consumer, capacity-one, stale timer, check failure and non-session cancellation
acceptance. Stream sealing is a required broker/inbox contract, not a measured OMP feature;
if completeness cannot be established, remain unknown rather than inventing delivery.

## R5 — accepted; explicit units and conserved generations proposed

**Revised passages:** [Budget ledger](../WORKFLOW-CONTRACT.md#r5), integer dimensions,
objective/child allocation, conservation equations, reservation ownership/settlement,
reset and late-receipt paragraphs; reservation row in identities.

V2 budgets starts by role, validation actions, model requests and integration/activation
operations. Provider token/currency observations remain distinct from these enforceable
units. Each execution/check/action/request has its own reservation. Tickets get allocation
by transfer from their objective, not a fresh copy of the objective's allowance. Unknown
issuance keeps held units unavailable; proved start consumes, proved non-start releases.
Consumed units do not refund on a later failed outcome. Correction/rebase/profile changes
and PM decomposition cannot create credits. Reset creates an explicit operator-granted
or transferred generation; it never zeroes history or transfers outstanding holds.

**Protocol argument (illustrative units, not measured limits):** An objective with ten
available developer starts can delegate six to child A and four to child B; a further
one-unit allocation fails. A's two held starts yield four available plus two held; no
second ticket can spend those holds. If A's generation closes while one start is unknown,
its late non-start moves that old hold to retired, not new-generation availability.
A late confirmed start consumes the old hold. Duplicate receipts leave either settlement
unchanged. At every step authorized equals available+held+consumed+delegated+retired;
across descendants delegated is excluded to prevent counting allocation twice.

**Disposition/limits:** Addressed in design, not a proved implementation. FR-07/08/11/12/15/16
must test conserved transactions, partial failures, parent/child transfers, conflicting/
duplicate receipts, stale generations, retries and global caps. Cleanup/rollback have a
separate bounded root recovery allocation; exhausting it reports recovery_required rather
than granting infinite authority. No numerical limits, entitlement or provider capability
have been changed or measured here.

## Smaller clarifications and routing

| Review point | Exact revised passage / ticket | Disposition |
|---|---|---|
| Canonical request bytes | Contract [command encoding](../WORKFLOW-CONTRACT.md#interfaces) | Restricted JSON value types, key/escape/integer rules, actor/domain tag, duplicate-key rejection; artifact bytes remain raw |
| Multi-entity concurrency | Same section | Complete expected_revisions read/write map including protected policy/ledgers/resources; verifier supplies mandatory read set |
| Lost-reply idempotency | Same section | Authenticated same-ID lookup precedes current revision validation; semantic rejection persists a result, no domain mutation |
| Pure decision inputs | Same section | Time/IDs/observations supplied explicitly and persisted; one domain apply for live/replay |
| Isolation ticket drift | Contract R2; FR-15a/09/15 | FR-15a owns early host/root isolation; FR-09 installed harness; FR-15 later PM/steering; FR-15a now depends on FR-07/08 |
| Check-worker capacity | Contract R4; FR-11/12 | Checks/builds consume slots; developer cleanup precedes checks/review; drain correction is durable blocked work |
| Freeze/copy safety | Contract integration; FR-13/17 | Controller-custodied digest-verified immutable objects, no root candidate hooks; concurrent-writer tests retained |
| Rollback ranges | Contract integration; FR-17 | All candidate-written versions must be in rollback/root-supported allowlist, not merely overlapping declarations |
| Storage evidence strength | Contract evidence/compatibility; verification; FR-07/19 | Provisional maintenance choice, no comparative performance claim; precise spike limits and remaining full fault cases retained |

The audit matrix still contains F01–F24 once each, with unchanged obligation text and
expanded owners where v2 adds work. Existing ticket acceptance paragraphs remain intact;
v2 refinements add expected outcomes. FR-05 containment is restored by FR-13/14/17, not
by this document. FR-20 proposal plumbing can precede deployment, but its full repair
activation depends on FR-17 and FR-22 acceptance; no runtime-only completion claim.

## Remaining decisions and re-review handoff

No unresolved operator **product/policy** choice is required for this selected revision.
The original authority/spending rules and autonomous kernel capability remain. Conditional
implementation feasibility is unresolved: installed OMP/tool/auth separation, actual host
isolation, sufficiency of the verifier API, selected binding/fault behavior and compatible
activation must still pass their owning acceptance tests. Failure requires an explicit
bounded design exception, not an automatic waiver. R1–R5 remain awaiting independent
closure; this author does not certify them.

Changed files are WORKFLOW-CONTRACT, REPAIR-PLAN, the Foundry entry of docs/PLAN,
verification.md, manifest.json and this response. Historical review/audit, original
storage code/results, production source and unrelated edits were preserved. Commands,
results and evidence limits are in [verification.md](verification.md). No storage rerun
was needed: bytes and stated evidence did not change, and no new storage claim is made.

Independent re-review should first verify every [manifest](manifest.json) entry, then read
the unchanged v1 review, v2 contract, this response, refined tickets and verification.
Evaluate protocol counterexamples for each R1–R5 plus smaller clarifications. Record a
new review against those exact hashes; preserve v1 as history. Keep FR-07 blocked until
that reviewer resolves design blockers. Stop after design re-review, before implementation.
