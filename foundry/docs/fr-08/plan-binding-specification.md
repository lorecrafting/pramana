# FR-08A protected-result/domain-plan binding — implementation specification

Date: 2026-09-20

Status: **implementation specification; no acceptance, no integrated behavior**

Author: Claude Opus 5, implementation owner for this correction.

Governing design: [the root-fact composition diagnosis](fr08b-root-fact-composition-diagnosis.md),
whose recommended closed transition-plan contract this specification implements without
widening. Governing acceptance stays with [FR-08A](../REPAIR-PLAN.md) and the
[workflow contract's](../WORKFLOW-CONTRACT.md) R3 authority split, atomic command
protocol, R4a settlement and R5 conservation.

## Exact base

| Subject | Revision |
|---|---|
| Base `main` | `3f06a5a2b3b138dd2e45b3cbfea5261435e7d515` |
| Blocked FR-08B kernel candidate | `a00deccbf4717ed6c3e4835bbdefed457dd6d637` |
| Preserved FR-08B in-flight kernel work | `059546b5c58ab8fac311cc5617196d978e134fd2` |

## Confirmed defect at this base

`commit_accepted_atomic_bundle/6` binds `proposal = envelope["proposal"]` and commits that
precomputed value unchanged. `operation_results` — which already carries the authoritative
protected facts produced during staging, including
`result["facts"]["infrastructure_settlement"]` and its assigned `ordinal` — reaches
`atomic_result/5` for the durable record and `persist_atomic_records/7` for history, but
never reaches the domain proposal that actually commits.

Sources at this base: [Gateway](../../lib/pramana_foundry/durable_store/gateway.ex)
`do_atomic_bundle/5` line 571, `normalize_atomic_envelope/2` line 588,
`stage_atomic_operations/4` line 743, `maybe_persist_nonstart/3` line 936,
`atomic_operation_result/4` line 951, `commit_accepted_atomic_bundle/6` line 964 and
`persist_atomic_records/7` line 1133;
[ProtectedPrimitives](../../lib/pramana_foundry/durable_store/protected_primitives.ex)
ordinal assignment at line 212 and `validate_nonstart_predecessor/6` at line 300.

A domain transition therefore cannot depend on a fact the protected layer derives inside
the same transaction, which is what R4a settlement requires. This is the interface
correction the diagnosis assigns to FR-08A, not new FR-08B lifecycle scope.

## Module boundary

A new trusted module `PramanaFoundry.DurableStore.TransitionPlan` owns the codec. It is
protected-side code and deliberately does **not** call, load or depend on
`PramanaFoundry.Workflow.Kernel.Plan`. The kernel's copy is the candidate-side producer of
conforming plans; this one is the authoritative validator and binder. Two independent
implementations of one closed codec is the intended arrangement, because Gateway must
never execute candidate code to decide what commits.

`ProtectedPrimitives` gains only the discriminator derivation, because that requires
authoritative policy and settlement reads. `Gateway` gains the wiring. No workflow
reducer, Coordinator, adapter, FR-08B path, pointer producer or activation path changes.

## Hardening the candidate-side contract does not provide

The candidate-side `Plan.bind/3` substitutes any `%{"binding" => name}` marker found
anywhere in a template event, and treats `destination_slot` as declarative metadata that
its own `sub/2` never enforces. A candidate could therefore declare
`launch_settled.settlement` and place the authoritative settlement into an unrelated
field of an unrelated event.

**The trusted binder must enforce the declared slot.** For each binding, the marker for
that name must occur exactly once across the selected alternative's events, at exactly the
declared `<event_type>.<field>` position, and nowhere else. Zero occurrences, more than
one, or an occurrence at any other position rejects the plan. Unreferenced bindings and
markers naming an undeclared binding also reject. This rule is part of the codec, not an
implementation detail.

## Authoritative output derivation

Outputs are derived from staged `operation_results`, never from caller-supplied copies.
For a binding naming `operation_ordinal` *n* and `output_kind` *k*, the binder locates the
staged result with that ordinal, requires `execution_status == "committed"` and
`operation_kind == "protected"`, requires the operation type to be the one that produces
*k*, and extracts the typed fact from `result["facts"]`. The extracted value is then
shape-validated against *k* before substitution. A reference to a later, absent, rejected,
quarantined, rolled-back or wrong-kind result rejects.

`nonstart_settlement_v1` extracts the whole authoritative settlement including its
`ordinal`; a caller copy never satisfies the binding.

## Discriminator derivation

The discriminator is a new protected output derived by `ProtectedPrimitives` from the
authoritative settlement and the effect's policy, not by the adapter and not from the
envelope. Its closed vocabulary for this correction is
`below_infrastructure_limit` and `infrastructure_limit_reached`, compared as
authoritative settlement `ordinal` against the effect's policy
`infrastructure_attempt_limits[role]`.

Note for implementation: at this base `infrastructure_attempt_limits` exists only in test
fixture policy values and has **no evaluation anywhere in `lib/`**. This correction must
therefore introduce that authoritative policy read, and its absence, wrong type or
non-positive value must fail closed rather than default to a permissive branch.

The discriminator is a safety observation. It authorizes no effect, and later dispatch
still obtains a fresh claim under current root admission.

## Prestate, persistence and replay

Per the diagnosis: check the union of all domain dependencies, every alternative's
dependencies, protected transitive reads and absence predicates against transaction
prestate before any mutation, keeping staged dependencies distinct from prestate
expectations. Authenticate and hash the complete *unresolved* plan. Persist the original
plan, the exact protected outcomes, the selected discriminator and the resolved concrete
carriers as distinct typed records, never interchangeable copies. Revalidate each resolved
carrier against the original plan and attributable protected history on lookup, reopen,
replay and backup validation, including equality with the independently reconstructed
settlement. Preserve v1/v2 bytes and histories and fail closed on partial or unsupported
version states.

`expected_revisions` remains required semantic command data preserved unchanged through
kernel and adapter; the blocked kernel's allowed-key set must accept it rather than have
the adapter strip it.

## Prerequisite: the durable event vocabulary does not admit lifecycle events

Discovered while implementing subcommit 1, at base `3f06a5a`. Recorded here because it
constrains this correction and directly affects the FR-08B kernel owner.

`RecordCodec.normalize(:event, _)` requires `map["type"]` to be in `@event_types`
(`record_codec.ex` line 22, enforced at line 81). That vocabulary has nine members:
`legacy_event`, `ticket_created`, `ticket_enqueued`, `ticket_steered`, `ticket_paused`,
`ticket_resumed`, `ticket_cancelled`, `effect_requested`, `receipt_recorded`.

The FR-08B kernel's closed event vocabulary at preserved revision `059546b` has
twenty-seven members. **The two sets intersect in exactly one name, `ticket_resumed`.**
Twenty-six kernel event types are refused outright by the durable codec.

Consequences:

- No bound proposal carrying a lifecycle event can be committed today. A plan that
  passes every `TransitionPlan` check still fails `RecordCodec.normalize_bundle/1` with
  `:invalid_event`. `transition_plan_test.exs` pins this as executable evidence.
- This is not only a binding problem. It means the blocked FR-08B kernel's events cannot
  be persisted by the durable store at all, independently of how they are produced. The
  B1 finding in the FR-08B kernel blocker review said the candidate's event contract was
  incompatible with the codec; this quantifies that incompatibility. That review lives on
  branch `repair/fr08b-pure-kernel` at `a8ecf36b7032572ceba27c139c06c5f17d10a604` and is
  not yet on `main`, so it is cited by revision rather than linked.
- `normalize_candidate/1` is shared by the v1 `transact` path (`gateway.ex` lines 518 and
  550) and the v2 atomic path (line 598). Appending names to `@event_types` would
  therefore widen the v1 vocabulary as a side effect. The diagnosis already requires
  a *deliberately versioned* codec extension rather than an append, and this sharing is
  the concrete reason.

**Subcommit 0** therefore precedes the rest of this correction: a versioned extension
admitting the lifecycle vocabulary on the v2 bundle path while leaving the v1 accepted
set byte-for-byte unchanged, failing closed on unsupported or partial version states, and
preserving existing v1/v2 histories. Its exact vocabulary must be agreed with the FR-08B
kernel owner rather than inferred from the preserved work-in-progress, because that
revision is unreviewed and mid-correction. Until it lands, the binding path is
structurally complete but cannot commit a lifecycle transition end to end.

## Subcommit plan

The correction is split into attributable subcommits under one candidate freeze, each
independently reviewable, with every FR-08A obligation retained:

0. Versioned durable event vocabulary extension for the v2 bundle path, preserving the
   v1 accepted set exactly. See the prerequisite section above. Blocked pending agreement
   with the FR-08B kernel owner on the exact vocabulary.
1. `TransitionPlan` codec: closed schema validation and slot-enforced substitution, with
   its own tests. No Gateway wiring. **Landed at `24b8431`.**
2. Authoritative output derivation from staged results, with wrong-kind, wrong-ordinal and
   non-committed rejection tests.
3. Protected discriminator derivation including the new authoritative policy read and its
   fail-closed cases.
4. Gateway wiring: envelope plan key, complete prestate union, resolve-then-commit, and
   the typed persistence records.
5. Replay, reopen, backup-validation and idempotency revalidation.

Focused checks run per subcommit; the full model-free suite runs at candidate freeze and
again after integration. The candidate then requires a fresh independent critical review
of authority, persistence and replay before integration. Reviewer identity for that review
will be Claude Fable 5.1, recorded as the evidence identity actually used.

## Explicit non-goals

No expression language, template evaluator, JSON paths, callbacks, SQL or arbitrary root
updates. No candidate execution inside Gateway. No workflow scheduling moved into the
protected root. Root does not implement developer, reviewer or PM transition tables. This
correction does not implement FR-08B's role reducer or its every-ingress migration, and
waives no FR-08B acceptance obligation.
