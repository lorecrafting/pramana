# FR-08B subcommit 1 — second fourth-pass review (evidence architecture)

Date: 2026-09-21

Reviewer: GPT Sol, independent session, commissioned as a second pair of eyes **on the
evidence architecture** rather than on the kernel. Brief: judge whether the five mechanisms
are the right ones and whether any can be replaced by something simpler and equally robust.
Endorsement was explicitly named a failed answer.

Candidate inspected: `a319b39..34d6833`. Did not run the mutation sweep or the full suite.

Run alongside [the fourth independent review](fr08b-subcommit1-review4-findings.md), which
reviewed the kernel. The two were independent of each other and of the implementer.

## Verdict

Not evidence-complete. **The problem is not a missing sixth mechanism. The current five are
already too many, and two of them still make stronger claims than their implementation
supports.**

## Where the two reviews independently agreed

Worth more than either alone, since neither reviewer saw the other's work.

1. **The mutation sweep's site inventory is still incomplete.** Both found it. Sol named the
   exact six and the count: 114 sites across 70 distinct texts, not 108/66. Verified.
2. **The stale resume target is a real defect, not a semantics question.** Both reproduced
   it independently from the same seven-event sequence.
3. **The missing mechanism is a semantic invariant oracle over post-states.** Both arrived
   at it from opposite directions — one as the fix for finding 3, one as the answer to
   "what are all five blind to".
4. **Atom-keyed dead-guard detection is the wrong granularity.**

## Sol's three concrete findings

**1. The sweep does not enumerate all guard call sites.** Its scanner is
`~r/<- (require_[a-z_]+\()/`. Six guard calls dispatch directly or in tail position inside
`require_settlement_source/2` — e.g. `"cancelled" -> require_cancel_requested(ticket)` —
and cannot match. Neutralising the outer call measures all six collectively, so one
disposition branch can hide another. **Verified: 114 total, 108 matched, the six exactly as
named.** Fixed, with a red control over every guard shape.

**2. `KernelSearch.declared_reasons/0` is incomplete too.** It scans for literal
`{:error, :atom}`. `kernel.ex:80` declares a reason as
`Event.entity_kind(...) |> ok_or(:unknown_entity_kind)`, which the extractor cannot see.
The test claims to mechanically inventory the declared error set and demonstrably does not.
Another tool-to-report join. **Verified.**

**3. The search had already found a real contract violation and no mechanism called it
one.** The stale-resume state. "The failure was not reachability. It was an absent semantic
invariant oracle."

## Answers to the six questions put to it

### Which mechanism is not paying for itself

- **Clause coverage — delete.** Cheap to compute, expensive epistemically. The unit is
  created by `String.split(~r/;|(?<=\.)\s+/)`, which is punctuation, not semantics. One
  assertion can cover several fragments and one obligation can span two. `@uncited` becomes
  another transcription of the contract. Replace with **explicit semantic clause IDs in
  R4/R4a** (`R4.09.a`) and an `assert_clause/3` that verifies the quotation is still live
  and records the ID as exercised; coverage is then `contract IDs - asserted IDs`, with no
  heuristic. Incidentally: the candidate has **four** `@partial` keys, not the five claimed
  in review prose — a demonstration that derived counts must come from the executable
  artifact. Verified.
- **Atom-keyed dead-guard detection — delete** as a standalone mechanism.
- **Full mutation sweep — demote to periodic calibration.** It has paid for itself
  historically, but an hour per run, five evidence defects, source rewriting and
  output-format parsing make it a poor permanent acceptance pillar.
- **Row coverage and bounded search — keep**, substantially modified.

### Should the guards become data

**No.** The instinct points at the right problem and the proposed cure is too much
architectural change for an evidence problem. It would add an abstraction between
transition and effect, force every predicate into one representation, complicate nested
`with`/`case` handlers, and still not solve the hard join — *does this predicate mean what
the English clause says*. Nor does it enable a solver: arbitrary Elixir closures in a list
are no more symbolically tractable than a `with` chain.

> **Datafy the observations, not the reducer.**

Build test-only guard-site instrumentation from the Elixir AST. Give every `require_*`
invocation a stable identity `{handler, expression_ordinal, normalized_call}`; compile an
instrumented copy where each site reports through a probe while returning its original
value. **One** test/search execution then yields, per site: prefix reached, passed, failed,
error atom, first witness. Because `with` short-circuits, a site returning an error means
every earlier condition passed — which is exactly the question the sweep spends an hour
answering, and is close in spirit to MC/DC's treatment of masked conditions. Ordinary BEAM
coverage cannot provide it: OTP reports at module/function/clause/line granularity, not
per-condition outcome independence.

### Cheap dead-call-site detection

First define "dead". There are three domains:

```
W = states accepted by State.valid?/1
R = states reachable by replay from State.new()
B = states reached by this bounded proposer
B ⊂ R ⊂ W
```

Mechanism 3 measures **B**, its prose claims **R**, and "dead code" sounds like **W**.
**The four "genuinely unreachable" guards are not unreachable over `W`** — Sol gives a
structurally valid input for each that makes it fire. They are replay-unreachable under the
current transition relation, which is a different and weaker statement.

The cheap mechanism: for every site require one pass witness and one first-failure witness,
**or an explicit redundancy/unreachability proof**. Persist the shortest witness as an
ordinary deterministic regression test. "No failure witness found" must mean **unwitnessed**
— never "unreachable". Then classify: redundant with a central invariant → move the
invariant, delete the site; protects structurally valid but replay-impossible input → keep
as a boundary check and construct the state directly; neither → label unproven.

### On the six reachability claims

Not accepted as proofs. Seeding fixes depth starvation, not completeness.

**Do not fix the proposer circularity by generating the proposer from the same R4 rows that
supply the oracle** — that increases common-mode failure. Separate them: the **contract**
supplies the oracle; the **implementation and schema** supply the input grammar
(`Event.types/0`, payload keys, state enums, fresh/wrong IDs, protected-fact shapes).

For real unreachability the affordable tool is an **inductive semantic invariant**, not
symbolic execution: `I(State.new())`; `I(s) ∧ apply(s,e)=s' ⇒ I(s')`; and at site G,
`I(s) ∧ prefix-guards-pass ⇒ G cannot fail`. History then disappears from the argument.
Example: establish `ticket.phase == exhausted ⇒ active_attempt_id == nil` and
`ticket_reset`'s `require_no_active_attempt` is provably redundant — delete it.

Explicitly warned off: a hand-written Z3 encoding merely moves the `proposer ↔ kernel` join
to `SMT model ↔ kernel`; CutEr is under heavy development and supports OTP 20–22.3. PropEr
is useful as a witness finder and shrinker, never as proof.

Additional obligation: the search's canonicalisation needs a **congruence test** — two
states with the same canonical key must have the same accept/refuse behaviour for the same
proposal, and accepted successors must canonicalise identically. No counterexample found;
this is the proof obligation that justifies the quotient.

### What all five are blind to

> **Relational post-state correctness / monotonic evidence custody.**

The suite asks "was X admitted or refused" and rarely "are the facts in the resulting state
mutually coherent". `State.valid?/1` is a well-formedness validator, not an invariant layer.
Consider splitting `State.well_formed?/1` from `State.invariant?/1`. Run the invariant after
**every** accepted transition and over every explored state. This catches a class the
mutation sweep **fundamentally cannot**: the sweep mutates conditions, and a transition can
have every guard perfectly tested and still write the wrong phase, fail to clear stale
metadata, overwrite evidence, or retain a pointer it should clear.

### Are five mechanisms over-engineered

Yes. Reduce to **two**:

| Current | Disposition |
|---|---|
| 1. Row coverage | **Keep, strengthen** — semantic clause IDs, citation inline with the assertion it justifies. Absorbs #4 |
| 2. Bounded search | **Keep** — rename to bounded *exploration*; add semantic invariants and guard-outcome tracing; never use absence as proof |
| 3. Dead-guard atom detection | **Delete** — wrong granularity, incomplete static inventory |
| 4. Clause fragmentation coverage | **Delete** — arbitrary unit, redundant with a strengthened #1 |
| 5. Full mutation sweep | **Demote to calibration**, after fixing site inventory and removing repository writes |

And: **every mechanism gets a deliberate red control.** The site enumerator's own fixture
should contain a normal `with` guard, a multiline guard, two identical calls, a nested guard
and a tail call, asserting all are found individually. *"If that test had existed, today's
108/114 gap could not have produced another clean report."*

### An active hazard in the sweep

The script ended with `File.write!(target, original)`, restoring a file it never modifies.
Concretely: sweep reads `kernel.ex`; a legitimate process edits it; the sweep finishes and
silently overwrites that edit. Hash and **fail** if it changed; never "restore" a file the
tool was not supposed to touch. Also: stop using formatter prose as the verdict protocol —
use exit status or a machine-readable reporter; that coupling has been paid for twice.

## Disposition in this candidate

Fixed: the site inventory (114, with the red control), the clobber hazard, and the semantic
invariant oracle with its own red control.

Open, and recorded rather than silently deferred: `declared_reasons/0`; semantic clause IDs
replacing clause fragmentation; guard-site instrumentation replacing the sweep as an
acceptance pillar; the inductive-invariant treatment of the six unwitnessed guards; the
canonicalisation congruence test; and the `well_formed?`/`invariant?` split.

## The sentence worth keeping

> **Stop proving guards by absence of counterexamples. Prove domain invariants, and make
> redundant guards disappear.**
