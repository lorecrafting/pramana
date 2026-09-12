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

**`mix pramana.release.stamp`** records what the retrieval state was at a moment; `mix
pramana.doctor` reports whether the recorded stamp still matches the live corpus. See
`Pramana.Release`.

**▸ BUILT 2026-08-29**, and building it found a defect in something else.

`Inventory.snapshot/0` takes **9.8 seconds**, against ~300 ms for every coverage figure it
reports combined. The cost is one field: `chars` sums `length(body)` across 548 million
characters, which makes Postgres detoast every text in the corpus. **The reader's
`/inventory` page pays that on every load** — a ten-second page whose slowness is entirely
one number nobody asked for at that moment.

**▸ FIXED 2026-08-29.** `texts.char_count` is written with the body, in the same transaction,
so it cannot drift — a column rather than a cache, because there is no moment at which the
body exists and the count does not. `mix pramana.texts.count_chars` backfills a bake that
predates it, in batches, in SQL.

    Inventory.snapshot/0    9,819 ms -> 1,319 ms
    chars                   548,047,059, unchanged

`char_length` in Postgres and `String.length/1` in Elixir return the same number, so a
backfilled row and a freshly loaded one agree — pinned by a test, because the failure would be
a total that is quietly three times too large and still looks like a plausible corpus size.

### 2. Domain telemetry at five boundaries — ▸ BUILT 2026-08-29

`Pramana.Telemetry` emits five events and `PramanaWeb.Telemetry` now reports them, so the
dashboard shows this project rather than only Phoenix:

    [:pramana, :retrieval, :search]   duration, results   mode, retrievers, outcome
    [:pramana, :guard, :check]        duration            verdict, layer
    [:pramana, :mcp, :tool]           calls               tool
    [:pramana, :bake, :work]          duration, segments  outcome, reason
    [:pramana, :acquire, :fetch]      duration, bytes     source, outcome, reason

**`bake_id` rides on every one**, because a measurement that cannot name the corpus it
describes is not comparable with the next. An explicitly supplied one is never overwritten:
a caller replaying an older bake is reporting about that one.

Two honest limits. The MCP event is a **count, not a duration** — every tool builds its
response through `Reply.json/3`, which runs after the work, and timing properly needs a hook
around `execute/2` that the server does not expose. Which tools are reached for, and how
often, was previously zero and is most of the value. And `retrievers` is metadata rather than
a tag, because "the semantic arm silently did not run" is a failure about *which arms
executed*, which a `mode` tag would have reported as `hybrid` throughout.

### 3. An Oban failure handler — ▸ BUILT 2026-08-29

`Pramana.Telemetry` attaches to `[:oban, :job, :exception]` at boot and logs the worker,
args, attempt, queue, duration, reason **and node** — the last because the stall that
motivated this was a second VM draining the same queue with yesterday's build, and nothing
else in the record would have told them apart.

It reports and returns. A telemetry handler that retried or discarded would be a control
path hiding in an observation path, and Oban owns that policy.

Successes are not logged: a bake is tens of thousands of jobs and a line each buries the one
line that matters.

**And the pruner now keeps seven days rather than one.** A job that exhausts its attempts is
`discarded`, which the pruner treats like any other terminal state — so at 24 h an overnight
bake lost its own failures before anyone read them. Oban's pruner takes a single `max_age`,
so keeping failures longer keeps successes longer too; `oban_jobs` rows are small and that is
a trade worth making in one direction only.

### 4. Structured errors on the MCP surface — ▸ BUILT 2026-08-29

**Nineteen** error paths across seventeen tools, each a hand-written string — the audit
undercounted by looking only at single-line call sites. Every one now goes through
`Reply.error/4` and returns JSON in the same shape a result uses: a stable snake_case
`reason` to branch on, the sentence to read, and `bake_id` and `replay` beside them, because
*"no passage exists at this URN"* is a fact about a particular corpus.

### 5. Guard refusals and caveat counts — ▸ BUILT 2026-08-29

Both were computed and thrown away. Both are counters now, reported by verdict and by kind:
citation refusals answer *where is the corpus hard to cite*, and which caveat fires answers
*what should we acquire next* — on evidence rather than intuition.

**Counters, not a stored log, and that is a decision rather than a stage.** Persisting
refusals or queries is a question about privacy and retention before it is a feature: a
scholar's queries reveal unpublished research direction, and § A6 says the retention policy
comes before the first row. A counter answers most of the question and stores nothing.

Making the caveats countable meant splitting `Coverage.caveat/0` — it joined three gaps into
one sentence, so nothing could count *which* fired. `Coverage.caveats/0` returns the kinds;
both now share one computation, because the first version asked for the kinds and then asked
again for the prose, paying twice for three database answers on a path that runs on every
search.

## What this deliberately does not propose

**No serve-time behaviour that depends on history.** `docs/PLAN.md` § A6 states the
constraint and it binds here too: the moment a response varies with what happened before it,
`replay` stops replaying and the citation-of-a-retrieval property is gone. Observability
observes.

**No external telemetry service.** This is self-hosted and the corpus is licence-encumbered;
query text must not leave the machine by default. A query log is sensitive data before it is
useful data — see § A6 on confidentiality.
