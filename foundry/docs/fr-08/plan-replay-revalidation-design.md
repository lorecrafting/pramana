# FR-08A subcommit 5 — replay and reopen revalidation design

Date: 2026-09-20

Status: **design note; no implementation, no acceptance**

Author: Claude Opus 5. Completes the [plan-binding specification](plan-binding-specification.md).

## Exact base

`main` at `b4044e3`, plus subcommit 4 frozen at `a95b6b5` and under review.

## What subcommit 4 leaves undone

Subcommit 4 resolves a plan and commits the result. It does not revalidate that result
afterwards. The governing diagnosis requires, on lookup, reopen, replay and backup
validation, that each resolved carrier be revalidated against the original plan and the
attributable protected history — with exact operation identity, type, ordinal and required
settlement presence, plus equality with the independently reconstructed settlement, and it
warns that comparing only two copied fields repeats the historical carrier defect.

Independent review of subcommit 4 enumerated precisely what is missing or weak. This
design responds to that list rather than restating the diagnosis.

## What is persisted today, and what that permits

Confirmed at `a95b6b5`:

- The **original plan** is durable only inside `atomic_bundles.canonical_envelope`, an
  opaque canonical JSON blob. Recoverable, but not a separately typed record.
- The **selected discriminator** is now a first-class field of the durable v2 result.
- The **resolved carriers** are the committed events and projections.
- The **staged protected outcomes** are `durable_operations` rows.

So revalidation is possible without re-deriving anything: the plan, the discriminator and
the outcomes are all recoverable. That is the property subcommit 4 had to preserve and
does. **Re-deriving the discriminator is not an option** and must never be attempted:
`infrastructure_discriminator/3` reads the current policy row and fails closed once that
policy is revised, so recomputation would turn a valid historical commit into a corruption
report. Revalidation compares against the recorded value; it does not recompute it.

## The revalidation rule

For a plan-bearing bundle, reconstruct the binding rather than trusting the carriers:

1. Decode the original plan from the canonical envelope and validate its schema. A stored
   envelope whose plan no longer validates is corruption, not a version skew.
2. Take the **recorded** `selected_discriminator` and require it to name an alternative
   the plan actually declares. A recorded value naming no alternative is corruption.
3. Re-derive the outputs from the persisted `durable_operations` rows using the same
   `derive_outputs/2` the commit path used — same code, not a parallel reimplementation,
   so the two cannot drift.
4. Re-run `TransitionPlan.bind/3` against the original plan, the recorded discriminator
   and those persisted outcomes, and require the result to equal the committed carriers
   exactly. This is the check that makes the whole binding attributable: it proves the
   committed events could only have come from that plan, those protected results and that
   discriminator.
5. Require the settlement in the rebound carrier to equal the independently reconstructed
   settlement from `root_infrastructure_settlements`, including its ordinal — not a
   two-field comparison.

Step 4 subsumes most field-level checks by construction, which is why it is preferred over
enumerating comparisons that would need extending every time a slot is added.

## Gaps the review found, and their disposition here

**`staged_settlement_fact/1` scans globally.** It searches every staged result for an
`infrastructure_settlement` and requires exactly one, ignoring the ordinal the binding
names. This fails closed today, but would wrongly refuse a legitimate bundle settling two
independent role launches atomically. **Correct it in this subcommit**: resolve the
settlement through the binding's declared `operation_ordinal`, the same way
`derive_output/2` already does. The discriminator must describe the settlement its plan
actually binds, not whichever one happens to be unique.

**`plan["domain_reads"]` and `expected_domain_revision` are never consulted.** They are
schema-validated and then ignored. The diagnosis requires checking the union of all domain
dependencies, every alternative's dependencies, protected transitive reads and absence
predicates against transaction prestate before any mutation. With one purely
protected-derived discriminator no exploit exists today, which is why review recorded it
as a gap rather than a blocker. **This subcommit must either consult them or delete them.**
A validated field that nothing reads is worse than absent: it implies a guarantee that is
not enforced. The preferred resolution is to consult them, because FR-08B will need
domain-state-dependent alternatives and the field is already specified.

**`plan["protected_operations"]` is not cross-checked against the envelope's real
operations.** `derive_output/2` validates against the actual staged result's type, which
is the load-bearing check, so this is decorative rather than unsound. **Cross-check it
anyway**, because a plan that describes different operations from the ones the envelope
stages is incoherent and should be refused at normalization, not tolerated because a later
check happens to catch the consequence.

## Where revalidation runs

- **Lookup and idempotent retry.** `existing_atomic_bundle/4` returns a stored result. It
  must revalidate before returning, so a corrupted stored bundle cannot be replayed to a
  caller as an authentic result.
- **Reopen.** Startup authority validation already walks `atomic_bundles`; the plan rule
  joins it.
- **Backup validation.** `Gateway.backup/2` reconstructs and refuses to publish unless the
  reconstruction matches live authority. Plan-bound bundles join that comparison.

## Acceptance

- A plan-bound bundle round-trips lookup, reopen and verified backup unchanged.
- Mutating any committed carrier, the recorded discriminator, a persisted protected
  outcome, or the stored plan is detected as corruption on each of those three paths,
  each tested separately rather than inferred from one.
- A settlement whose ordinal differs from the reconstructed authoritative settlement is
  detected, since this is the historical carrier defect the diagnosis names.
- Revalidation never recomputes the discriminator, proven by a test that revises the
  policy after commit and still round-trips.
- Proposal-bearing bundles and existing histories are untouched on every path.
- A bundle settling two independent launches binds the settlement its ordinal names.

## Limits

This completes FR-08A's binding correction. It does not implement FR-08B's reducer, does
not extend the lifecycle event vocabulary beyond what the slots require, and claims no
lifecycle behavior. FR-08B remains additionally blocked on its own B1–B3 corrections.
