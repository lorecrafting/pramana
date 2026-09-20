# Primer: What This System Is, How It Works, and What Everything Is Called — chapter 5

> Learning chapter. Corpus figures are recorded examples, not a live inventory; current contracts are in the architecture guide.
> [Contents](../PRIMER.md) · [Documentation](../../../docs/README.md) · [Current architecture](../ARCHITECTURE.md)

## 16. Licensing, and why it is a column

The project's posture is: **we publish the pipeline, not the corpus.** Different sources
come with genuinely different terms, and those terms have to be enforceable by a query —
not remembered by a person.

| source | licence | may we republish? |
|---|---|---|
| CBETA | non-commercial | **no** |
| SuttaCentral Pāli root | Public Domain Mark | yes |
| SuttaCentral translations | mostly CC0, one CC BY-SA 3.0 | yes, with obligations |
| locally-added modern commentary | in copyright | **no** |

So `license_class` and `redistributable` are structured columns, and any public surface
sets `redistributable_only: true` once and then *cannot* serve restricted content by
accident.

Three lessons already learned here, each the hard way:

- **A source's own LICENSE file is not the licence.** bilara-data's LICENSE.md says CC0
  throughout; its own publication metadata records Public Domain Mark for the Pāli root
  text and CC BY-SA 3.0 for one translation. Licence belongs to the *publication*.
- **What we believe and what we will act on are two columns.** Where a rendering's exact
  publication cannot be identified, the licence is inferred from its siblings — good
  enough to hold and search under, not good enough to republish on. `license_class` says
  the first; `redistributable` says the second.
- **A declared filter that does nothing is worse than no filter.** `license_class` was
  recorded and displayed from the start, which made it *look* enforced, while nothing
  could actually filter on it. Every declared filter now has a test proving it changes the
  result set.

---

## 17. The integrity machinery

### The bake

A **bake identity** hashes source-input records, the pipeline version and bake configuration.
It does not freeze translation rows, vectors or retrieval defaults. The loader maintains
one current set of source rows; it does not preserve independently queryable old bakes.

The version-2 release stamp hashes stable translation content/provenance and the actual
stored vector bytes, so same-count rendering or embedding changes move the relevant
component id. Read [identity and replay](../ARCHITECTURE.md#identity-and-replay) before
treating a matching ID as an immutable replay guarantee: code/defaults and historical row
snapshots remain outside the stamp. A proposed query-time candidate cache is not an
implemented service merely because a tier or schema sketch names it.

### Two different checks, and the distinction between them

This is one of the most useful ideas in the project.

**`mix pramana.verify`** re-runs the pipeline from `raw/` and byte-compares the result
against what is stored. It proves **reproducibility**: the bake is a deterministic
function of pinned inputs.

**`mix pramana.integrity`** counts what is in the *source files* against what is in the
database — every `<lb/>` marker, every gaiji. It proves **completeness**: nothing printed
was lost.

> **Reproducibility is not fidelity.** If the pipeline drops something on every run, it is
> absent from both sides of `verify` and the check passes happily. Only counting against
> the source catches loss.

Both are required at a phase gate, and both are green over the whole corpus. This document
deliberately quotes no text or segment count: the last one written here went stale within
two ingests, and `Pramana.Inventory.snapshot/0` computes it.

### The gate: CI for a dataset, not just for code

Ordinary CI answers *does the code work*. Here the deliverable is a dataset of millions of
segments, so there is a second question — *is the data still what it claims to be* — and it
needs different checks entirely.

`mix pramana.gate` is all of them as one command, **ordered cheapest-first and halting at
the first failure**, so a formatting error costs two seconds rather than being discovered
after the eval run.

It runs in **stages**, because most of the ordering in a checklist is an artefact of the
order somebody typed it in rather than a real dependency: `credo` does not read `dialyzer`'s
output, and `integrity` does not read `verify`'s. Only three orderings here are real —
`format` alone first because it is two seconds and fails often; `compile` alone next because
everything after it assumes built beams *and* because concurrent `mix` invocations in one
`MIX_ENV` contend on the build lock; and `evals` alone last, because an eval run **is** the
measurement and contention invalidates its timings. Everything between those fans out.
A stage runs every one of its steps even after one fails, and reports them all, so three
broken cheap checks are seen in one pass rather than across three runs.

**Code checks — about a minute in total:**

| step | what it answers |
|---|---|
| `format --check-formatted` | costs nothing, fails often, so it goes first |
| `compile --warnings-as-errors --force` | warnings are failures. `--force` because incremental compilation will not re-emit a warning in a file it did not rebuild |
| `credo --strict` | style and consistency linting |
| `deps.audit` | known CVEs in dependencies |
| `test --cover` | the suite, plus the coverage ratchet described below |
| `dialyzer` | static analysis of the BEAM: unreachable clauses, impossible patterns. It found a defensive `parse_date(nil)` clause that could never match, because `Regex.run/2` yields `""` for a capture group that did not participate, never `nil` |

**Data checks — most of an hour:**

| step | what it answers |
|---|---|
| lockfile | every file `sources.lock.json` records still exists in `raw/` with a matching sha256 — for **every** source, not the one just touched |
| `verify --all` | re-normalize every text from `raw/` and byte-compare: the pipeline is **deterministic** |
| `integrity` | count against the *source files*: nothing printed was **lost** |
| `coherence` | do independently derived facts about one work **agree**? |
| `evals --gate` | 1,472 gold retrieval questions scored against a committed `evals/baseline.json` |

Steps 8 and 9 are the pair described above, and running only the first is how a real defect
survived a passing gate. **`coherence` is the third question, and it exists because the other
two cannot see a rule applied outside its domain**: 122 works were labelled
`composition_origin: japanese` that are Ming and Qing Chinese compositions, and `verify` and
`integrity` were both green over them — correctly, because they were faithfully and
reproducibly *mislabelled*. Catching that needed a second, independently sourced fact about
the same work: the author's birthplace. Every check there is a rate with a floor and a
minimum population, because upstream data legitimately disagrees with itself and a check
demanding 100% goes permanently red. The lockfile check is there because *both* of them work from paths
recorded at ingest, and stay green when the lockfile itself is wrong — where "wrong"
includes incomplete, which is exactly how the Taishō's 2,471 file records went missing while
every check stayed green.

**Why one command.** `docs/CHECKS.md` specified this as a list a person had to remember. The
CBETA X ingest shipped with `verify` green and `integrity` never executed — and integrity
had been failing on 1,228 texts the whole time. Nobody skipped it on purpose; it was one
more command at the end of a long day.

`--from <step>` resumes after a fix without repaying for the steps that passed, and
`--quick` omits verify, integrity and evals, but still includes database-dependent
lockfile/coherence/figure checks. It is not a database-free lint command.

### Test coverage, and the ratchet

**Coverage** is the fraction of your code that runs at least once while the test suite
executes. Elixir measures it with `mix test --cover`: it instruments every module, runs the
tests, and reports the percentage of lines each module executed. 100% would mean no line
went untouched.

Coverage is a **negative** signal, and it is worth being precise about why. High coverage
does not mean the code is correct — a test that calls a function and asserts nothing still
marks every line as covered. But *low* coverage is conclusive: those lines have never run
in any test, so nothing at all is known about them. It tells you where you are blind, not
where you are safe.

A **ratchet** is what turns that measurement into a standard. You record a minimum in
`mix.exs`:

```elixir
test_coverage: [
  summary: [threshold: 83],
  ignore_modules: [~r/^Mix\.Tasks\./, ...]
]
```

Mix fails the run when coverage falls below it. The rule attached to it is one-directional:
**raise it when coverage rises; never lower it to make a run pass.** That asymmetry is the
whole mechanism. Coverage can only go up, one gate at a time, and no individual commit can
buy itself an exception. `pramana_web` climbed 82 → 91 → 92 → 93 that way, one gate each.

`ignore_modules` matters as much as the number. 90% is Mix's default and this umbrella
cannot honestly hold it: CLI shells over already-covered domain functions, OTP application
callbacks, and NIF stubs whose Elixir bodies are *replaced by Rust at load time* and can
never execute. Excluding those and defending a real number beats a threshold nobody can
meet — a standard people cannot reach is one they learn to route around.

Two traps, both of which this project fell into:

**The option nests.** `test_coverage: [threshold: n]` is silently ignored; it must be
`test_coverage: [summary: [threshold: n]]`. Written the wrong way it looks configured and
Mix goes on applying its own default.

**A threshold nothing runs is a comment.** `docs/CHECKS.md` called a coverage regression a
gate failure from the beginning, and the ratchet was raised at four real gates. But when
`mix pramana.gate` became the way the suite is run, its test step was plain `mix test` — no
`--cover`. Over the following phases `pramana_web` fell from **93% to 77.5%** while
`mix.exs` went on recording 93, and every gate passed. Two shipped MCP tools turned out to
have no test at all.

The fix, on 2026-08-28, was three parts, and the shape of it generalises: the gate now runs
`mix test --cover`; the untested tools were tested (9.5% → 100%, 31.3% → 100%); and **the
thresholds were reset to what is actually true** so that they can fail. The restoration
targets stay recorded in `docs/PLAN.md`. Resetting downward looks like exactly the thing the
rule forbids, and the distinction is worth holding onto: lowering a number *you are
currently meeting* is gaming the ratchet, while recording a number you are *not* meeting, so
that it can be enforced tomorrow, is the opposite. An unenforceable 93 protected nothing for
months; an enforced 81 makes the next regression impossible.

Phase 2's gate was run and the tag **deliberately withheld**, because one of its tasks is
blocked on SAT. Recording that honestly is worth more than a green tag.

### The invariants

The stable eight constraints live in [the shared invariants](../INVARIANTS.md).
This abbreviated learning summary is not a second authoritative policy:

1. **No unattributed text ever leaves the API.** Every returned span carries its URN,
   hashes, offsets and full provenance.
2. **Never invent citation IDs.** Adopt each tradition's existing citation grammar.
3. **`raw/` is append-only and never edited.** Fixes happen in a normalizer, where they
   are visible in review.
4. **Provenance is multi-axis, never a single `source` string.**
5. **Deterministic before probabilistic.** Where curated scholarship exists — a parallel,
   an alignment, a quotation — use it rather than an embedding's guess.
6. **Every retrieval change runs against `evals/`.** Recall and citation accuracy are
   measured, not asserted.
7. **The MCP surface is read-only.** Tools read; the command line writes. A model can
   never modify the corpus it cites.
8. **A machine translation is never citable as source.**

Alongside these sits the rule that defines the guard: *the model is not trusted to cite
correctly — the citation guard re-resolves every URN and byte-compares the quoted span.*

---

## 18. The technology stack

### Elixir and the BEAM

**Elixir** is a functional programming language running on the **BEAM**, the virtual
machine built for Erlang telephone switches. Chosen here because the work is naturally
concurrent (thousands of files to parse, batches to embed) and the BEAM is very good at
running many independent tasks that must not take each other down when one fails.

You will see these repeatedly:

| thing | what it is |
|---|---|
| **Phoenix** | the web framework — serves the MCP endpoint |
| **Ecto** | the database layer: schemas, queries, migrations |
| **Mix** | the build tool; `mix something` runs a task |
| **Oban** | background job queue, backed by Postgres — used for the bake |
| **umbrella app** | one repository holding several applications (`pramana`, `pramana_web`, `pramana_native`) |

An **umbrella** keeps the core domain logic (`pramana`) independent of the web layer
(`pramana_web`) — so the corpus is usable without a web server, and the web layer cannot
smuggle domain rules into itself.
