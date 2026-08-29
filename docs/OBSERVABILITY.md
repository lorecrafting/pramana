# Observability — what this system can and cannot tell you about itself

Audited 2026-08-29. **This document is findings and a plan; almost none of it is built.**
Where something exists it says so.

## The one-line summary

The corpus is exhaustively instrumented and **the running system is not**. Every *answer*
carries its provenance, its `bake_id` and the call that produced it; nothing carries a
record that the answer was produced at all.

## What the audit found

| dimension | state |
|---|---|
| Application logging | **7 `Logger` calls across 170 modules**, in 4 files |
| Domain telemetry | **none** — `PramanaWeb.Telemetry` is the generated Phoenix scaffold: `phoenix.*`, `vm.*`, `pramana.repo.*` and nothing of this project's own |
| Metrics reporter | LiveDashboard at `/dev/dashboard`, **dev only**. The `ConsoleReporter` line is still commented out as generated |
| MCP surface | **unobserved.** No timing, no call counts, no error rate, no record that a tool ran |
| Oban / the bake | one `Logger.error` in the worker. **No `Oban.Telemetry` handler.** The pruner discards jobs after 24 h, failures included |
| Citation guard | computes every refusal and **discards it** — `docs/PLAN.md` § A6 |
| Coverage caveats | fire on every search; **nobody counts which** |
| Mix tasks | the real observability surface: `Mix.shell().info` with denominators, `Elapsed.human` in 6 modules. Excellent for a person at a terminal, invisible to anything else |

## What is already good, and worth not breaking

**`replay: {tool, arguments}` plus `bake_id` on every response** is a stronger primitive
than most systems have: it makes a past answer *re-runnable*, not merely logged. Everything
proposed below should be built to preserve that property rather than beside it.

**Mix task output states denominators.** `1,515 of 17,281`, `8 dropped for naming a person
the file does not define`. That habit is why several defects were caught by reading output
rather than by a check.

**The gate reports per-step timing**, and since the staging change it reports every failure
in a stage rather than the first.

## The cost, measured on this project rather than argued

- **The Oban stall.** 41 of 53 jobs failed deterministically and the diagnosis was
  *adding a print statement inside `perform`* — because nothing else could see inside a job.
  The cause was a stale `mix phx.server` from the previous day draining the same queue with
  yesterday's build. **No log, metric or dashboard would have had to be clever to catch
  that**; any record of which VM claimed a job would have done it.
- **Ad-hoc SQL as the session-start ritual.** Establishing basic state — how many texts,
  which sources are acquired, whether the bake id still matches, what has a date — was done
  repeatedly with hand-written `psql` this session alone. That is not a knowledge problem;
  it is a missing command.
- **A stale `bake_id` for weeks.** Acquisition rewrote the lockfile and nothing recomputed
  the id, so every response was stamped for inputs that no longer existed. Now a gate check
  (rule 64) — but it was invisible until someone thought to compare two values by hand.

## Plan, cheapest first

Each item is independently useful; none depends on the next.

### 1. `mix pramana.doctor` — the state a session needs, in one command

Not a monitoring system: a **session-start command** that prints what is currently
rediscovered by hand. Bake id and whether it still matches its inputs; corpus counts by
source and witness; which sources are declared and unacquired; embedding and chunk coverage;
what has dates and authority links; the last gate result if one is recorded.

Highest value per hour of anything here, because it is read-only, needs no design decisions,
and every future session pays the cost of its absence.

### 2. Domain telemetry at five boundaries

`:telemetry.execute/3` at the bake job, retrieval, the guard, an MCP tool call, and
acquisition. Emitting costs nothing when nothing is attached, LiveDashboard picks it up in
dev for free, and it is the substrate for everything in § A6 of `docs/PLAN.md`.

**Name the events for the questions they answer**, not for the functions they sit in:
`[:pramana, :retrieval, :search]` with `%{duration, results}` and metadata carrying
`bake_id`, mode and which retrievers actually ran — because "the semantic arm silently did
not run" is a real failure this project has already had.

### 3. An Oban failure handler

Attach to `[:oban, :job, :exception]`, log the worker, args and reason. Roughly ten lines,
and it is the single item that would have made the stall above a two-minute diagnosis.
Consider raising the pruner's 24 h retention for failed jobs specifically: a bake run
overnight currently loses its own failures before anyone reads them.

### 4. Structured errors on the MCP surface

Seven error paths across seventeen tools, each a hand-written string. A model cannot branch
on prose. A consistent shape — a machine-readable `reason` beside the human sentence —
costs little and makes tool failures analysable rather than merely readable.

### 5. Guard refusals and caveat counts

`docs/PLAN.md` § A6, items 1 and 3. Both signals are already computed and thrown away, and
both become useful the moment (2) exists to carry them.

## What this deliberately does not propose

**No serve-time behaviour that depends on history.** `docs/PLAN.md` § A6 states the
constraint and it binds here too: the moment a response varies with what happened before it,
`replay` stops replaying and the citation-of-a-retrieval property is gone. Observability
observes.

**No external telemetry service.** This is self-hosted and the corpus is licence-encumbered;
query text must not leave the machine by default. A query log is sensitive data before it is
useful data — see § A6 on confidentiality.
