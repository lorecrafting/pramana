# Pramāṇa — Project Guide

*pramāṇa* (प्रमाण) — "valid means of knowledge," the Buddhist epistemological
tradition of Dignāga and Dharmakīrti. The name is the thesis: this system exists to
establish **warrant** for a claim about a text, not merely to retrieve one.

**This is the canonical project reference for every agent.** Read the resuming-work
section first, then route to the specific doc for what you are about to do.

---

## The one idea

The corpus is **baked** into an immutable, content-addressed artifact. The LLM is a
swappable reader that never touches the database — it goes through a retrieval API
whose every response is URN-addressed and byte-verifiable.

If you remember nothing else: **the model is not trusted to cite correctly. The
citation guard re-resolves every URN and byte-compares the quoted span.** That check
is deterministic and model-independent.

**English-first for an English-speaking reader, and that is the strategy rather than a
feature.** The reader asks in English; the canons stay in their own languages; every
answer is anchored to the original with its provenance.

---

## Resuming work (new session, no context)

1. **`docs/STATUS.md`** — 220 lines, what is true right now
2. **`docs/PLAN.md`** — living task list: what is next, why, what blocks it. Updated in same commit as the work it describes.
3. **Non-negotiable invariants** (below) — read before acting
4. **`docs/ROADMAP.md`** — phase structure and completion status
5. **`docs/RULES.md`** — 81 rules learned from real defects, cited by number

The split exists because they were one file of 3,896 lines where a historical sentence
read as a current claim.

| | |
|---|---|
| `docs/STATUS.md` | **what is true now** |
| `docs/PLAN.md` | **what to do next**, and what it is blocked on |
| `docs/CODE_CONVENTIONS.md` | **coding rules** — Phoenix, Elixir, Ecto, LiveView, forms |
| `docs/RULES.md` | **81 rules** from real defects, cited by number |
| `docs/HISTORY.md` | **what happened**, in order. True of its date, not of today |
| `docs/PROXIES.md` | why every cheap evaluation proxy lied, and what it cost |

### Key tasks for every session

- `mix pramana.doctor` — check bake state, loaded sources, and missing gaps
- `mix pramana.gate` — run the full evaluation gate (ratchets baseline)
- `mix pramana.coherence` — check cross-axis data coherence
- `mix pramana.recall` — measure retrieval against quotations and parallels

---

## Non-negotiable invariants

Violating any of these is a bug, not a tradeoff.

1. **No unattributed text ever leaves the API.** Every returned span carries
   `urn`, `char_start`, `char_end`, `sha256`, and its full provenance record.
2. **Never invent citation IDs.** Adopt each tradition's existing citation grammar
   (Taishō page/register/line, SuttaCentral segment IDs, Derge folio/side/line) and
   wrap it in a URN. Scholars must be able to check us against a print edition.
3. **`raw/` is append-only and never edited.** Every fix happens in a normalizer with
   a test. If a bake can't be reproduced from `sources.lock.json`, it's not a bake.
4. **Provenance is multi-axis, never a single `source` string.** See
   `docs/ARCHITECTURE.md`. A Japanese Kamakura-era commentary must never be
   presentable as an Indian sūtra — enforced structurally in the tool response shape,
   not by prompting.
5. **Deterministic before probabilistic.** If an alignment, parallel, or quotation
   link can be found by string/table/structure matching, do that. The LLM handles
   only the residual, and its output is labeled with lower confidence.
6. **Every retrieval change runs against `evals/`.** Recall@k and citation accuracy
   are published numbers, not vibes.
7. **The MCP surface is read-only. Tools read; the CLI writes.** Never add an ingest
   or mutation tool. If a model could write to the corpus, reproducibility from
   `sources.lock.json` is gone.
8. **A machine translation is never citable as source.** Generated text is a layer
   over a source anchor, never a top-level URN, and the citation guard rejects any
   quote resolving to `method != human` presented as canonical.

---

## Which document to open, by what you are doing

### Main project (Pramana retrieval pipeline)

| Doing… | Open |
|---|---|
| starting a session, orienting | `docs/STATUS.md`, then `docs/PLAN.md` |
| **understanding what's in this repo** | `AGENTS.md` § "Repo architecture" — umbrella vs foundry, Rust, Python, why each exists |
| **adding a text source** | `docs/ADDING_TEXTS.md`, `docs/SOURCES.md` |
| **writing new Phoenix/Elixir code** | `docs/CODE_CONVENTIONS.md` — framework rules, form patterns, LiveView streams, Ecto |
| changing **retrieval** | `docs/ARCHITECTURE.md`; run `evals/` |
| changing **embeddings** or renting a GPU | `docs/EMBEDDING.md`, `docs/GPU_RUNBOOK.md` |
| touching the **MCP surface** | `docs/MCP.md` |
| touching the **reader** | `docs/READER.md` |
| **translations** or generated text | `docs/LAYERS.md`, `docs/TRANSLATION.md` |
| **commentary / parallels / quotations** | `docs/COMMENTARY.md` |
| anything **public or licensed** | `docs/DEPLOY.md`, `mix pramana.public.check` |
| a **phase gate**, or "am I done" | `docs/CHECKS.md` |
| local setup, Postgres, toolchain | `docs/DEV_ENV.md`, `docs/ELIXIR.md` |
| **debugging**, or wondering why nothing can tell you what happened | `docs/OBSERVABILITY.md` |
| wondering **why** something is the way it is | `docs/HISTORY.md`; if measurement, `docs/PROXIES.md` |
| changing **how a model reads the corpus** | `docs/AGENT_MODELS.md` |
| wondering whether an idea was already tried | `docs/PLAN.md` § "Rejected, with evidence" |
| onboarding a person, or explaining the project | `docs/PRIMER.md`, `README.md` |
| renting a GPU | `docs/CLOUD.md` |
| asked how this compares to another system | `docs/COMPETITIVE.md` |
| looking for something to build | `docs/IDEAS.md` |
| planning work that depends on event sourcing | `docs/HARNESS.md` — harness engineering, verifier feedback, multi-agent retrieval |
| the SAT request that Phase 2 is blocked on | `docs/sat-request-email.md` |

### Foundry (agentic workflow / self-healing system)

| Doing… | Open |
|---|---|
| understanding the foundry subproject | `foundry/README.md` |
| telemetry, health probes, system metrics | `foundry/docs/OBSERVABILITY.md` |
| migration from Python supervisor | `foundry/docs/MIGRATION.md` |
| implementation tickets | `foundry/docs/MIGRATION-TICKETS.md` |

---

## Project layout

```
sources.lock.json          pinned upstream snapshots (commit SHAs, sha256, licenses)
raw/                       untouched upstream downloads — gitignored, never edited
docs/                      all project documentation (27 files)
evals/                     gold question sets + scoring harness
bin/                       utility scripts (pramana-tranche, pramana-mcp, …)
foundry/                   standalone agentic workflow system (see below)
apps/
  pramana/                 CORE DOMAIN — no Phoenix dependency
    lib/pramana/
      urn/                 URN parse, resolve, verify — the foundation
      corpus/              Ecto schemas + loader
      acquire/             fetchers, catalog, bulk archive, lockfile
      normalize/           Saxy streaming TEI/XML -> canonical IR
      segment/             IR -> citable units via native citation grammars
      retrieval/           lexical, semantic, hybrid, survey, rerank
      bake/                Oban orchestration, workers, pipeline version
      guard.ex             post-generation citation verification
      enrich/              alignment, quotation graph
      docs/                figure generation, doc sync
  pramana_web/             Phoenix — MCP endpoint, LiveView reader
  pramana_native/          Rustler NIFs: CJK segmentation (jieba-rs)
priv/embed/                Python sidecar — model inference ONLY
```

### Foundry subproject (`foundry/`)

A standalone Mix project for autonomous agent orchestration, self-healing, and
workflow automation. **Deliberately decoupled from the umbrella** — its sole
dependency is `owl` for terminal rendering. It has zero coupling to Postgres, the
corpus, `priv/embed/`, or any umbrella app (`pramana`, `pramana_web`,
`pramana_native`).

**Why not umbrella it?** Foundry-only work (agent dispatch, health probes, kanban
board) should need nothing but Elixir + OWL. Umbrella membership would pull the
full toolchain — Postgres, Rust/jieba-rs, Python sidecar — for every compile,
losing the fast 2-second dev loop. If they ever need to share a schema, a shared
`pramana_core` Hex/git dep costs less than coupling the build. See § "Repo
architecture" below.

```
foundry/
  mix.exs                  standalone OTP app + escript
  README.md                overview, runtime deps, configuration
  docs/
    OBSERVABILITY.md        telemetry records, health probe, system metrics, CLI diag
    MIGRATION.md            destination architecture from Python supervisor
    MIGRATION-TICKETS.md    eight-ticket implementation sequence
  lib/pramana_foundry/
    agent_server.ex         GenServer per agent (launch, timeout, handoff)
    coordinator.ex          central state machine with health probe
    coordinator/tick.ex     queue processing via DynamicSupervisor
    improver.ex             self-healing loop (14 classifiers, PM proposals)
    hardening_pm.ex         PM for IMPRV-* hardening tickets
    system_metrics.ex       VM and per-process metrics collection
    consolidated_log.ex     merged view of all structured logs
    telemetry/              record validation, store, observation, forecast
    herdr/                  typed adapter for the Herdr agent CLI
    effects/                checkpointed launch, prompt, process lifecycle
    board/                  terminal kanban dashboard
    cli.ex                  CLI commands: health, agents, metrics, logs, board
  test/                     235 tests
```

---

## Repo architecture: umbrella vs standalone

This repo holds **two independent Elixir projects** plus Rust and Python companions.
Understanding their boundaries saves confusion on first open.

```
┌──────────────────────────────────────────┐
│  Umbrella  (apps/)                       │
│  mix.exs → apps_path: "apps"            │
│                                          │
│  apps/pramana/          core domain      │
│  apps/pramana_web/      Phoenix MCP/UI   │
│  apps/pramana_native/   Rustler jieba    │
│                                          │
│  Needs: Postgres 18 + pgvector,          │
│         Rust toolchain, Python sidecar   │
│  Release: ships both apps together       │
└──────────────────────────────────────────┘

┌──────────────────────────────────────────┐
│  Foundry  (foundry/)                      │
│  standalone OTP app + escript            │
│  zero corpus deps                        │
│                                          │
│  Deps: owl (terminal rendering)          │
│  Needs: nothing but Elixir               │
│  CLI: `pramana_foundry health|board|…`   │
└──────────────────────────────────────────┘
```

**The foundry is decoupled by design** (see § Foundry subproject above). It does
not share code with the umbrella; if it ever needs to, use a shared Hex/git dep
rather than umbrella coupling.

Two more non-Elixir components live in the repo (detailed in `docs/ELIXIR.md` §
"Three deliberate exceptions"):

| Component | Where | What | Needed? |
|---|---|---|---|
| **Rustler NIF** | `apps/pramana_native/` | CJK word segmentation (`jieba-rs`). Runs in-process at bake and query time | **Yes** — must be in the BEAM for performance; no Elixir equivalent |
| **Rust port binary** | `native/quotations/` | Suffix-array text-reuse detection for the quotation graph. Multi-GB working set | **Yes** — too large for the BEAM; runs as a bake stage |
| **Python sidecar** | `priv/embed/` | Model inference: BGE-M3 embeddings + generative translation | **Yes** — no viable BEAM alternative for the ML. Does tensor math only, never touches the database or corpus directly |

---

## Stack

**Elixir 1.20.3 / OTP 29.0.5 · Phoenix 1.8.11 · Ecto · PostgreSQL 18 + pgvector
(HNSW) + pg_bigm · Oban · Saxy · Req · Rustler.** Toolchain versions are pinned
exactly in `mise.toml`.

**Foundry stack:** Elixir 1.20+, OWL (terminal rendering), Herdr CLI (Python agent
launcher), DynamicSupervisor + GenServer for agent lifecycle.

### Three deliberate exceptions (from `docs/ELIXIR.md`)

The Rust and Python components are documented in the table at § "Repo architecture"
above. `docs/ELIXIR.md` has the full rationale for each, including the ladder to
remove Python entirely.

## Rules trigger table

`docs/RULES.md` holds **81 rules, each learned from a real defect here**, cited by
number in code and commits. Read the listed rules before starting the activity.

| about to… | read |
|---|---|
| write or change a **normalizer / ingest** | 1, 2, 3, 23, 27, 28, 29, 45, 46, 48, 50, 51, 52, 53, 55, 56, 59, 71 |
| write a **mix task** or add a CLI option | 4, 8, 57, 66 |
| add a **filter, option or mode** | 4, 5, 6, 26, 36, **75** |
| write an **Ecto query** or touch performance | 9, 14, 15, 19, 21, 25, 34, 38, 39, 40, 67 |
| **compare, split or match a URN** | 68 |
| report a **coverage figure or any ratio** | 22, 31, 44, 54, 69, 74, **77**, **80** |
| **rank or weight by a graph** | 72, 73 |
| choose a **threshold**, or build a benchmark | 7, 18, 30, 32, 35, 37, 47, 49, 54, 67, **74**, **78** |
| **re-run a measurement** | **82** |
| **compare arms**, or quote a ceiling | **84** |
| **make something faster** | 40, 47, **70**, **76** |
| change a **schema, enum or registry** | 11, 12, 13, 42 |
| **acquire** or cache anything from upstream | 10, 43, 58, 64 |
| **delete** anything, or write `on_conflict` | 9, 20, 71 |
| **concatenate rows** into one string | 71 |
| edit **docs with a script** | 8 |
| **commit**, when another session may be working the same branch | **81** |
| **derive a value** from another | 61 |
| **store a hash of inputs** as an id | 64 |
| **instrument** anything | 65 |
| **check whether something passed** | 8, 63 |
| **sample a file, or size a feature before building it** | 62 |
| **publish a number that confirms what you just concluded** | 62 |
| **fix a constant** — any constant | 41, always |
| **add a new layer, source or vector kind** | **83** |
| **finish any capability** | **60**, **79** |
| make anything **optional**, or a dependency degrade | 17 |
| **generalise** from one case | 16, 24, 33 |

### The four that keep re-earning themselves

- **41** — a rule written after a fix does not sweep for the other instances. Cited in 16 files.
- **8** — a scripted patch that reports success may have done nothing. Eight occurrences.
- **1** — a buffered element that can span a line must be split at that line.
- **68** — a URN comparison is a parser. Join on columns that cannot be ranges.

---

## Keeping the documentation true

1. **Never write down a number the code computes** — generate it. Corpus counts live in
   `<!-- figures:key -->` blocks; `mix pramana.docs.figures --write` regenerates them.
   Measurements (Retrieval@10 is 74.9%) must never go in a generated block — the test is:
   *would a second run of the same command change it?*
2. **A statement about the past belongs in `docs/HISTORY.md`, or carries its date.**
3. **A new rule is not finished until a trigger points at it.** Add it to `docs/RULES.md`
   *and* to the trigger table above.
4. **`docs/PLAN.md` changes in the same commit as the work.**
5. **When a doc and the code disagree, the code wins — then fix the doc in that commit.**
6. **Verify a scripted doc edit by grepping for the new text.**
7. **Publish the gap, not just the total.**
8. **A claim about what is POSSIBLE must say whether it was measured.** Mark untested as untested.

---

## Framework conventions

**IF WRITING CODE, READ `docs/CODE_CONVENTIONS.md`.** It contains framework-specific
conventions for Phoenix v1.8, Elixir, Ecto, LiveView, JS/CSS, and forms — rules
every new file must follow.

This file is derived from `mix phx.new` scaffolding and can be regenerated:

```bash
mix pramana.docs.framework  # regenerates docs/CODE_CONVENTIONS.md from source
```

Key rules that apply everywhere:
- No `String.to_atom/1` on user input
- No index-based access on lists (`mylist[i]` invalid — use `Enum.at/2`)
- Never nest multiple modules in the same file
- Always use `start_supervised!/1` in tests
- Avoid `Process.sleep/1` in tests — use `Process.monitor/1` and `assert_receive`
- Use `stream/3` for collections in LiveViews
- Use `<.input>` component for forms, never pass a changeset directly to `<.form>`

---

## Foundry: observability quick-reference

The foundry writes three structured JSONL logs to `foundry/local/state/current/`:

| Log | File | Content |
|---|---|---|
| Coordinator log | `coordinator.jsonl` | Lifecycle events (tick, agent launch/completed/crash) |
| Telemetry log | `telemetry.jsonl` | Structured command records with durations |
| Findings log | `findings.jsonl` | Improver findings + `metrics_snapshot` events |

CLI diagnostics (`pramana_foundry` escript):
```bash
pramana_foundry health           # JSON health report
pramana_foundry agents           # List running agents with metrics
pramana_foundry metrics          # System metrics overview
pramana_foundry logs tail N      # Consolidated log tail
pramana_foundry board            # Terminal kanban dashboard
```

See `foundry/docs/OBSERVABILITY.md` for the full reference.