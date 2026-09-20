# FR-08B root-fact composition diagnosis

Date: 2026-09-20

Author: `/root/fr08b_root_fact_composition`, focused design diagnosis

Status: **bounded interface correction recommended; not implementation acceptance**

## Exact subject and verdict

| Subject | Revision |
|---|---|
| Integrated main inspected | `057f2902580235d844679c43ece571056b60b8a5` |
| Blocked pure-kernel candidate | `a00deccbf4717ed6c3e4835bbdefed457dd6d637` |
| Candidate review inspected | `a8ecf36b7032572ceba27c139c06c5f17d10a604` |
| Candidate worktree | `/private/tmp/pramana-fr08b-kernel.bYbL8q` |

**B4 requires a bounded FR-08A interface correction, followed by FR-08B kernel and
adapter work.** The accepted API handles protected-operation dependencies and
authenticated result carriers, but has no protected-result-to-domain binding mechanism.
The adapter cannot safely infer this missing contract from arbitrary state snapshots.

At the inspected main revision, Gateway normalizes a concrete proposal before its
transaction, stages protected operations, then commits that original proposal unchanged.
`required_bundle_prestate_revisions/3` discovers protected read dependencies; it does
not resolve references in domain events or projections. The infrastructure ordinal is
assigned from authoritative lineage while staging the settlement. The reviewed carrier
checks authenticate the protected result, not any caller copy in the domain proposal.

Source: [Gateway](../../lib/pramana_foundry/durable_store/gateway.ex),
`normalize_atomic_envelope/2` at line 587, `stage_atomic_operations/4` at line 743 and
`commit_accepted_atomic_bundle/7` at line 964;
[ProtectedPrimitives](../../lib/pramana_foundry/durable_store/protected_primitives.ex),
`required_bundle_prestate_revisions/3` at line 122 and
`persist_nonstart_settlement/3` at line 182. Line references throughout bind to the
inspected main revision unless an alternative revision is stated.

The [original composition diagnosis](atomic-composition-diagnosis.md) assigns this
protocol, persistence and protected-fact boundary to FR-08A. The
[first review](atomic-composition-review.md), [rereview](atomic-composition-rereview.md),
[presence blocker](atomic-composition-final-rereview.md) and final
[narrow PASS](atomic-composition-presence-review.md) retain their exact subjects and
limits. That PASS explicitly excludes exhaustive FR-08B lifecycle composition and
does not establish that this new binding surface already exists.

## Recommended closed transition-plan contract

This is a proposed versioned extension, not a description of implemented behavior.
It preserves [R3's authority split](../WORKFLOW-CONTRACT.md#r3), the atomic command
protocol, [R4a settlement](../WORKFLOW-CONTRACT.md#launch-non-start-recovery--r4a)
and [R5 conservation](../WORKFLOW-CONTRACT.md#budget-ledger--r5).

1. Outside protected authority, pure `decide(state, canonical_command, inputs)`
   produces ordered protected operations and a closed domain transition plan. Every
   reference names an earlier operation ordinal and an enumerated output kind, such
   as `nonstart_settlement_v1`. The protocol accepts no JSON paths, expressions,
   callbacks, SQL, arbitrary root updates or candidate reducer names.
2. The protected codec defines exact source kinds and destination slots. For example,
   an accepted `settle_claim/non_started` output can fill a named settlement slot in
   its matching non-start event and corresponding projection. Gateway verifies the
   operation, effect/claim/receipt, role, work owner, generation and predecessor
   identities, then copies the entire authoritative typed settlement, including its
   ordinal. Caller-provided fact copies do not satisfy this binding. References to
   later, absent, rejected, quarantined or wrong-kind results reject.
3. Scalar substitution alone is insufficient: the ordinal changes queue versus block
   behavior. Where a staged fact changes a decision, the plan contains a bounded set
   of candidate-authored alternatives indexed by fixed protected discriminators, such
   as `below_infrastructure_limit` and `infrastructure_limit_reached`. Protected code
   derives that discriminator from the authoritative settlement and policy; Gateway
   selects its matching alternative. The discriminator is a new protected output.
   Its exact closed vocabulary, policy reads and boundary comparison must be specified
   in the correction, not inferred by the adapter. Missing, duplicated, ambiguous or
   unsupported alternatives reject; there is no expression language or default branch.
4. Role-specific phases, reasons, custody and control consequences remain kernel
   decisions. Root performs only fixed fact derivation, alternative selection and
   substitution. Facts that remain unchanged during the transaction are explicit
   protected observations covered by prestate CAS. If a supported operation changes
   a decision-relevant control, allocation or generation fact, that fact needs its
   own explicitly enumerated output/selector contract; it cannot become an unbound
   observation. Root does not implement developer/reviewer/PM transition tables.
5. Check the union of all domain dependencies, every alternative's dependencies,
   protected transitive reads and absence predicates against transaction prestate
   before any mutation. Include policy/control, current allocation/generation,
   settlement lineage/count and predecessor. Keep staged dependencies distinct from
   prestate expectations. Stage protected operations, bind/select the plan, validate
   the resulting concrete carrier and event/projection correspondence, and commit
   once. No protected success may survive a rejected domain component.
6. Keep one domain `apply`. Candidate-side template production and concrete live/replay
   application share the same transition rules. Opaque fact slots may only be copied
   into codec-designated fields; all fact-dependent branching must already be exposed
   as alternatives. Require the substitution law in kernel/adapter acceptance tests:
   binding a planned projection equals applying its concretely bound event to the
   same prestate. Gateway performs mechanical codec validation and projection CAS,
   never candidate execution. This law is a kernel correctness obligation, not a
   claim that root proves arbitrary candidate lifecycle code correct.

The finite discriminator is a protected safety observation; it does not authorize an
effect. Later dispatch still obtains a fresh claim and passes current root admission.
The correction must specify its actual output schema and coverage before implementation
is called adapter-ready. It must not move workflow scheduling into the protected root.

## Alternatives and why field mapping is not enough

A fixed trusted mapping from protected-result fields into versioned domain-event fields
is the appropriate binding primitive. It does not alone solve decisions whose selected
projection depends on the value being mapped; the finite alternatives above are needed
for that case. A general template evaluator or expression interpreter is unnecessary.

Pure prepare/finalize is acceptable as candidate-side organization of this same closed
plan. Running candidate finalize in Gateway violates R3. Committing protected settlement
before external finalize violates R4a atomicity. Keeping a writer transaction open for
an untrusted callback/round trip is not part of this recommendation.

An authoritative speculative preview followed by complete CAS and exact rederivation
could be designed safely, but adds another protocol and retry surface. Similarly,
caller-predicted facts become safe only if root independently derives and compares their
complete typed identity/value before commit. Neither check exists for domain copies in
the accepted API. Requiring the adapter to predict an ordinal is not the recommended
boundary; the proposed references carry no predicted authoritative value.

## Persistence, authentication, retry and replay

Authenticate and hash the complete unresolved plan: canonical command, actor, explicit
inputs, ordered operations, bindings and all alternatives. Persist that original request,
exact protected outcomes, selected discriminators, resolved concrete domain carriers and
complete command result in the one authoritative Gateway transaction. The original plan
and resolved proposal are distinct typed records, not interchangeable copies.

On lookup, reopen, replay and backup validation, revalidate each resolved carrier against
the original plan and attributable protected history. Require exact operation identity,
type, ordinal and required settlement presence, plus equality with the independently
reconstructed settlement. Comparing only two copied fields repeats the historical
carrier defect. The new protocol must preserve v1/v2 bytes and histories and fail closed
on unsupported or partial version states.

Same actor, command ID and complete semantic digest returns the original complete result
before current CAS, including after a lost reply and restart. Changed plans or read sets
under that ID conflict. An early failure records the complete typed rejected history
without retaining rolled-back provisional facts. A new command carrying a duplicate
receipt retrieves the existing immutable settlement and cannot apply a second domain
transition; the current typed `duplicate_receipt` rejection can remain. Conflicting
receipts retain protected reconciliation/quarantine behavior.

Source: [Gateway](../../lib/pramana_foundry/durable_store/gateway.ex),
`do_atomic_bundle/5` at line 571, duplicate handling in staging at line 743 and
`persist_atomic_records/7` beginning at line 1133;
[protected history validation](../../lib/pramana_foundry/durable_store/protected_primitives.ex),
`validate_bundle_operations/4` at line 4206, settlement validation at line 4436 and
`valid_bundle_domain_row?/3` at line 4545. The existing domain-row validator binds the
stored request to the original proposal; it needs an explicit rule for resolved plans.

## Canonical commands and event/projection correspondence

`expected_revisions` remains required semantic command data, preserved unchanged through
kernel and adapter. The kernel/ingress accounts for every domain read, and Gateway owns
authoritative comparison. Protected-operation read sets remain explicitly typed and
separately checked; they do not silently replace command reads. A complete prestate
contract spans both sets without confusing their current key formats. The blocked
kernel must accept the canonical field rather than requiring the adapter to strip it.

Source: [RecordCodec](../../lib/pramana_foundry/durable_store/record_codec.ex),
command schema at line 18, command validation at line 227 and revision keys at line 305;
[Gateway CAS](../../lib/pramana_foundry/durable_store/gateway.ex) at line 1734. In the
blocked candidate, `foundry/lib/pramana_foundry/workflow/kernel.ex:1233` rejects the
canonical command because its exact allowed-key set omits `expected_revisions`.

The current codec requires one projection-bearing event per ordered projection write:
unique event/last-event identity, equal namespace/entity/revision/value and consecutive
revision. Preserve this bijection after binding, including exact equality of bound facts
in both carriers. Multi-entity transitions need an explicit ordered group of typed events
or a deliberately versioned codec extension. An adapter cannot invent event semantics,
revision guards or correspondence from arbitrary `changes` snapshots.

Source: [RecordCodec projection plan and reconstruction](../../lib/pramana_foundry/durable_store/record_codec.ex),
lines 505–629. The pure candidate's incompatible event/snapshot contract is in
`foundry/lib/pramana_foundry/workflow/kernel.ex:1260` at candidate `a00decc`.

## Required developer, reviewer and PM trace

| Role | One atomic settlement and domain result |
|---|---|
| Developer | Close execution, release the original start hold once, bind one ordinal; retain the same active attempt and immutable lineage; queue with `resume_phase: developing`, or block/exhaust under the specified current controls and allocation. Release checkout custody only on the required proof. |
| Reviewer | Close only the reviewer execution; retain the same attempt, frozen candidate and checks; restore awaiting-review ownership or its prescribed infrastructure/budget disposition. Preserve candidate/check custody. |
| PM | Close execution; retain the objective/planning owner; queue or block without inventing a proposal, admitting a ticket or granting allocation. |

Cross each role with pause, drain, cancel, infrastructure-limit exhaustion, allocation
exhaustion, policy revocation and ledger-generation change. Cancellation settles the
non-start and does not retry. Drain blocks developer/PM replacements while retaining
their owners; reviewer eligibility follows its existing rule. Old-generation refunds
settle their original generation and do not finance a new retry implicitly.

Restart after settlement but before redispatch reconstructs one owner, one ordinal and
no live settled execution, without replaying the settled launch. Unknown possible start
retains holds/resources and forbids replacement. Pre-intent denial creates no execution,
reservation or ordinal. Later retry uses new execution/effect/reservation identity and
the terminal predecessor under current authority.

These obligations come from [R4a](../WORKFLOW-CONTRACT.md#launch-non-start-recovery--r4a),
[FR-08B acceptance](../REPAIR-PLAN.md#fr-08b--unify-all-command-transitions-and-replay)
and the [ingress acceptance matrices](fr08b-ingress-inventory.md).
The present [atomic fixtures](../../test/pramana_foundry/durable_store/atomic_bundle_test.exs),
role loop at line 66 and generic proposal at line 723, write the same queued projection.
They establish bounded atomic storage behavior, not these actual role lifecycle traces.

## Ownership, affected modules and acceptance work

FR-08A owns the new protocol/codec, protected outputs and discriminators, complete prestate
verification, fixed binding, authenticated persistence, retry and recovery validation.
FR-08B owns canonical pure commands/events, guarded `decide/apply`, alternative production,
role custody and control dispositions, the mechanical adapter and every-ingress migration.
This factors the safety API under R3; it does not adopt a protected lifecycle reducer or
change either ticket's recorded status in this diagnosis.

Affected implementation paths, relative to `foundry/`:

- `lib/pramana_foundry/durable_store/gateway.ex`, `protected_primitives.ex`,
  `record_codec.ex` and `kernel.ex`; `database.ex` if new durable schema is needed.
- Candidate `lib/pramana_foundry/workflow/kernel.ex` and `workflow/kernel/state.ex`,
  plus the future mechanical adapter, whose path is not yet implemented or prescribed.

Affected tests include `test/pramana_foundry/durable_store/atomic_bundle_test.exs`,
`record_codec_test.exs`, `protected_primitives_test.exs`, relevant protected replay/recovery
matrices, candidate `test/pramana_foundry/workflow/kernel_test.exs` and adapter integration
tests. Required additions cover typed source/slot rejection, discriminator completeness,
the substitution law, all-alternative prestate/absence CAS, exact retry, duplicate receipt,
reopen/backup binding equality and the role/control/generation traces above. Existing
atomic rollback and version-history checks must remain valid for the new route.

B4's binding correction does not fix B1 total guarded semantic replay, B2 custody/closure
and retained history, B3 role/control/generation semantics, or B5 executable matrix
coverage. Those remain independent pure-kernel corrections. The review is durably
identified as `a8ecf36b7032572ceba27c139c06c5f17d10a604` at
`foundry/docs/fr-08/fr08b-pure-kernel-review.md`; it is absent from the inspected main
tree and can be read with `git show` from that exact object. This document does not
silently integrate the blocked branch or turn its happy-path results into acceptance.

## Evidence and limits

This diagnosis used read-only source and contract inspection. No runtime test, fault,
corruption or mutation experiment was run. It establishes the absent binding path and
proposes its bounded replacement; the proposed protocol still needs an exact candidate,
maintained tests and independent authority/persistence/replay review before integration.

The documentation follow-up changes only this record and the Foundry index. Validation
is the repository documentation gate and Git whitespace/diff checks; these cannot prove
runtime correctness, actual isolation, provider conformance, loaded release behavior,
activation or FR-22 acceptance. No shared status document, runtime, provider, daemon,
deployment or execution authority is changed.
