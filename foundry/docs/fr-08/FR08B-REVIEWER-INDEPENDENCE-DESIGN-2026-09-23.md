# FR-08B: the reviewer-independence predicate as a Core check

**Date:** 2026-09-23. **Type:** design. **Status:** protected item approved by the operator
([amendment](../REPAIR-PLAN.md#reviewer-independence-amendment)); lands with
[subcommit 3](FR08B-SUBCOMMIT3-DESIGN-2026-09-23.md). Taken at `8596c04a`.

**Requirement.** A review counts only if its execution shares no principal or authority
lineage with the execution that produced the exact candidate. Role labels, sessions and
models do not create independence. Until FR-15aB, Core compares *recorded* principals.

## Decisions

**(a) Where Core refuses.** At the two operations that record a principal against an
execution, both in `durable_store/protected_primitives.ex`. `create_effect` records the
effect `issuer`, the authenticated actor that `settle_claim` must match. The first
`append_inbox` for an execution pins the inbox `actor_id`, which every later append and the
seal must match. No other operation records a principal, so these two cover every principal
an execution can have. `claim_effect` and `issue_claim` record none and need no check.

**(b) How it is imposed without the controller asking (rule 7).** The operator policy
carries `independent_of_roles`, a map from a role to the roles whose executions it must be
independent of, for example `{"reviewer": ["developer"]}`. Core reads it from the effect's
policy. The role names are policy data, so no role word enters Core (rule 3). The scope is
the effect's `(ticket_id, attempt_id)`: one attempt freezes one candidate (R4.11), and the
reviewer launches in that attempt (R4.15). Core compares against **every** effect of the
named roles in the attempt, so there is no field for a controller to omit or to point at a
harmless effect. The relation is checked in both directions, so a producing effect created
after the review is refused too.

**(c) Authority lineage, concretely.** A side's principal set is the `issuer` of every
effect in the attempt that holds one of that side's roles, plus the inbox `actor_id` of each
such effect's execution. A predecessor chain stays inside one assignment
(`ticket:attempt:role`, `predecessor_current?/2`), so the set already holds every
predecessor's principal: a retry inherits its whole chain. The admitted state has the two
sets disjoint, with the new principal included. Control and ledgers are excluded. They are
operator authority shared by every execution of a ticket, not a principal of either side.

**(d) Refusal atom.** `principal_not_independent`, a `rejected` disposition that commits
nothing. A malformed `independent_of_roles` value is refused with the same atom, so the
check fails closed.

## Alternatives rejected

- *The reviewer effect names its source effect* (`independent_of_effect_id`). A controller
  can omit it or name an unrelated effect, and rule 7 forbids resting on that.
- *Hard-code the role pair in Core.* This violates rule 3, and a second workflow could not
  use it.
- *Check at acceptance (FR-13).* That is later than the point where the principal is
  recorded. FR-13 consumes the predicate rather than re-deriving it.

## Limits

- A policy with no `independent_of_roles` key imposes no requirement, so the operator must
  set it. This is the same trust placed in every other policy key.
- Principals are compared as recorded identities. Proving that they are OS-isolated is
  FR-15aB's job.
- The scope is one attempt. A correction attempt's fresh producer is compared only with its
  own attempt's reviewer.

## What the kernel's reviewer `decide/3` must do

It never requests the check. It must launch the reviewer under the same ticket and attempt
as the candidate's producer, with a principal different from the producer's. It must treat
a `principal_not_independent` rejection as a pre-intent denial, with no event (R4a).
