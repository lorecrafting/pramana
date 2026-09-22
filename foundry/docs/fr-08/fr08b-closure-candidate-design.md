# `apply/2` closure: candidate design

**Status: superseded on 2026-09-22 — closed, but not by the table below.** The candidate that
landed is a post-condition, not a typed payload table: `advance/2` runs `State.well_formed?/1`
over the committed post-state and refuses with `:malformed_post_state` (kernel property 6,
`require_well_formed/1`). Three lines in one place, closing the 18 pairs the probe sees, the 2
review found, the 51 keys hidden behind 15 types, nested values, two-key corruption, and every
future handler — everything "Not in scope" below lists. The typed table is bounded by what
someone typed; the post-condition is bounded by the validator, which is the definition of
closure. Measured before choosing, over the same 2,736 depth-5 seeds (`bin/closure_cost.exs`):
the extra `well_formed?/1` call on accepted outputs costs 17% of `apply/2`'s total, and the
test harness already asserted this exact post-condition after every accepted transition with
the suite green, so nothing legitimate is refused. The sizing below stands as the record of why
the table would have been ~31 rows; it is not what was built. The IMPLEMENTATION-LOG entry of
the same date has the measurements and what a reviewer should attack.

**Original status: design only. Nothing here is built, and this proposes no launch.** It exists because
the defect's own record ended "How many distinct refusals those pairs need is not enumerated",
and because the answer changes what the candidate is by an order of magnitude. Read
[EVIDENCE-TOOLS.md](../EVIDENCE-TOOLS.md) first; every rule there applies to this, rule 1 hardest.

## The defect, in one sentence

`kernel.ex`'s property 2 is **totality** — every state `well_formed?/1` accepts is one `apply/2`
returns from rather than raises on. Nothing asserts the other half, **closure**: every state
`apply/2` *produces* should be one it would accept as input. A handler that copies a payload value
into state inherits whatever `Event.validate/2` allowed, which is any string, integer, boolean, nil,
proper list or plain map (`event.ex:223-232`). Each such pair bricks the log permanently: the state
is written, and every later event fails `check_state` with `:invalid_state`.

## Size, measured

`bin/closure_probe.exs` at depth 5 — 2,736 seeds, 6,781,980 corruptions, 607,479 accepted,
292,473 accepted-but-malformed, **18 `(type, key)` pairs in 12 event types**, float control 0,
bound 15 of 37 types contributing nothing and hiding 51 keys. Plus `check_recorded.reason_code`
at depth 7 and `check_planned.check_id` found by review: **at least 20**, a bound and not a count.

Run it rather than quoting these. The numbers above are one run's; the probe prints its own bound
every time, and the reason it is in the tree is that four successive hand-carried counts of this
defect were wrong in the same direction.

## Every pair lands on one of four predicates

`State.well_formed?/1` applies exactly one predicate to each destination field:

| predicate | n | pairs |
|---|---|---|
| `optional_identifier?` | 11 | `ticket_admitted.objective_id`, `.reason`; `ticket_blocked.reason`; `ticket_parked.reason`; `artifact_blocked.reason`; `freeze_failed.reason`; `artifact_frozen.candidate_id`, `.sealed_generation`; `attempt_settled.reason_code`; `check_recorded.reason_code` |
| `identifier?` | 6 | `ticket_admitted.spec_revision_id`; `ticket_amended.spec_revision_id`; `objective_created.planning_owner_id`; `pm_proposal_recorded.proposal_id`, `.operation`; and the two below |
| `plain_map?` | 2 | `ticket_admitted.spec`; `ticket_amended.spec` |
| `optional_nonnegative_integer?` | 1 | `stream_sealed.last_accepted_sequence` → `execution["sealed_sequence"]` |

`launch_planned.attempt_id` and `check_planned.check_id` are `identifier?` **and** collection keys,
so they additionally owe `valid_collection?/3`'s key-agreement rule (`value[id_key] == key`). That is
the only pair-specific obligation in the set.

Four predicates, all already defined in `state.ex` and already applied by the validator. This is one
rule over a vocabulary, not twenty rules — rule 4's shape, for the fourth time on this branch.

## Where the change goes

`Event`'s **`@payloads`** is already a per-`(type, key)` table. It names which keys each event type
must carry, exactly, and says nothing about what any of them may contain. Measured over that table:

- **37** event types, **133** `(type, key)` slots
- **15** slots hold a bound protected fact (`authority`, `settlement`, `control`, `generation`),
  already validated by their `TransitionPlan` fact kinds — not this candidate's business
- **118** slots need a type
- but only **31 distinct key names** among them

The distribution is why this is small: `ticket_id` appears 32 times, `attempt_id` 24,
`execution_id` 11. **The type is a property of the key name, not of the pair**, in nearly every
case. So the table to write is ~31 rows, not 118 — a name → predicate map, with a per-`(type, key)`
override only where a name genuinely means two things.

Row-specific *subsets* stay where they are. `ticket_admitted` checks `payload["phase"] in
~w(queued blocked)` inline because that is R4's admission row, not a type. The boundary says
"a ticket phase"; the handler says "this row's two". Nothing moves between the contract and the
validator.

## Refusals

Four atoms, one per predicate, rather than one generic atom or twenty specific ones. Rule 5 pins a
refusal assertion to its exact atom so that `assert {:error, _}` cannot pass on a different guard;
one atom shared by every typed key would defeat that, and twenty would be the thing this design
exists to avoid. Each atom owes a contract citation **per rule**, a guard-reachability entry, and a
sweep site — four of each, not twenty.

## Acceptance

Already exists, and ships with the fix:

1. `bin/closure_probe.exs` reports **accepted-but-malformed: 0** at the same depth and seed count,
   with its bound line unchanged. Necessary, not sufficient.
2. The full suite stays green. This is the control against over-tightening — a type narrower than
   some legitimate event's real payload breaks whatever test drives that event, and nothing else
   would catch it.
3. A red control per rule 1: a fixture whose payload violates each of the four predicates and must
   be refused. Five mechanisms in this subcommit shipped confidently vacuous on their first run;
   the probe going to 0 because the validator now refuses *everything* would look identical to
   success on criterion 1 alone.

Criterion 1 cannot see what the probe cannot see: the 51 keys hidden behind 15 types, values nested
inside a payload map, or two-key corruption. A typed table covers the hidden keys anyway — which is
the argument for typing the table rather than patching the twenty pairs someone found, since a
per-pair fix is bounded by the probe's visibility, and that bound is exactly what made four counts
wrong.

## What a reviewer should attack

- **The 31 names.** Assigning a predicate per key name is a reading pass against every handler's
  destination field. A name that means two things in two events, typed once, is this design's
  characteristic failure — and it is the same shape as the `@payloads` table's own strength.
- **Whether `optional_` is right per key.** Eleven of the twenty want `optional_identifier?`; a key
  typed non-optional that legitimately arrives `nil` breaks a live path.
- **The protected 15.** They are excluded here on the claim that `TransitionPlan` validates them.
  Confirm that rather than inheriting it from this document.
- **The collection-key pair.** `launch_planned.attempt_id` and `check_planned.check_id` need the
  key-agreement rule as well as the type; a type-only fix leaves them broken in a way the probe
  *will* report, so this one is self-checking.
- **Whether the boundary is the right place at all.** The alternative is per-handler validation
  before each copy. It is worse — twenty sites, rule 4 pre-loaded, and no coverage of the hidden
  51 — but the argument should be made rather than assumed.

## Not in scope

Nested payload values, two-key corruption, deep-walk seeds, and `Harness.apply_unchecked/2`'s
quarantine, which stays until the pairs it exists for are refused. Row :467 and R4a.03.f2 are
separate unguarded defects with their own records and are not this candidate's.
