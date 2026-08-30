# CLAUDE.md — Pramāṇa

*pramāṇa* (प्रमाण) — "valid means of knowledge," the Buddhist epistemological
tradition of Dignāga and Dharmakīrti. The name is the thesis: this system exists to
establish **warrant** for a claim about a text, not merely to retrieve one.

Retrieval substrate for the Buddhist canons (and later, East Asian medical texts),
built so that **any** LLM can do citation-grounded scholarship over it.

## The one idea

The corpus is **baked** into an immutable, content-addressed artifact. The LLM is a
swappable reader that never touches the database — it goes through a retrieval API
whose every response is URN-addressed and byte-verifiable.

If you remember nothing else: **the model is not trusted to cite correctly. The
citation guard re-resolves every URN and byte-compares the quoted span.** That check
is deterministic and model-independent.

## Resuming work (new session, no context)

Read **`docs/STATUS.md`** first — 220 lines, and only what is true right now. Then
**`docs/PLAN.md`**, the living task list: what is next, why, and what it is blocked on.
Then this file's invariants, then `docs/ROADMAP.md`.

Four files, four jobs, and the split exists because they were one file of 3,896 lines where
a historical sentence read as a current claim:

| | |
|---|---|
| `docs/STATUS.md` | **what is true now** |
| `docs/PLAN.md` | **what to do next**, and what it is blocked on |
| `docs/RULES.md` | **67 rules** from real defects, cited by number — read before a new pipeline |
| `docs/HISTORY.md` | **what happened**, in order. True of its date, not of today |
| `docs/PROXIES.md` | why every cheap evaluation proxy lied, and what it cost |

**`docs/PLAN.md` must be updated in the same commit as the work it describes.** Finishing
an item, discovering new work, or invalidating an estimate all require an edit. A plan
carrying a stale number is worse than no plan, because the next session will act on it —
and this project has now corrected published claims about its own state four separate
times. It also records what has been **tried and rejected, with evidence**; check that list
before proposing something.

### Which rules apply to what you are about to do

`docs/RULES.md` holds **67 rules, each learned from a real defect here**, and they are cited
by number in code and commits. This file is always in your context and that one is not, so
the triggers live here. **Read the listed rules before starting the activity, not after the
test goes red.**

| about to… | read |
|---|---|
| write or change a **normalizer / ingest** | 1, 2, 3, 23, 27, 28, 29, 45, 46, 48, 50, 51, 52, 53, 55, 56, 59 |
| write a **mix task** or add a CLI option | 4, 8, 57, 66 |
| add a **filter, option or mode** | 4, 5, 6, 26, 36 |
| write an **Ecto query** or touch performance | 9, 14, 15, 19, 21, 25, 34, 38, 39, 40, 67 |
| report a **coverage figure or any ratio** | 22, 31, 44, 54 |
| choose a **threshold**, or build a benchmark | 7, 18, 30, 32, 35, 37, 47, 49, 54, 67, and `docs/PROXIES.md` |
| change a **schema, enum or registry** | 11, 12, 13, 42 |
| **acquire** or cache anything from upstream | 10, 43, 58, 64 |
| **delete** anything, or write `on_conflict` | 9, 20 |
| edit **docs with a script** | 8, and the gotcha above it — eight occurrences and counting |
| **derive a value** from another — a date, a bound, a rollup | 61 |
| **store a hash of inputs** as an id — `bake_id` and anything like it | 64 |
| **instrument** anything, or wrap a request for observation | 65 |
| **check whether something passed** — a gate, a linter, a script | 8, 63 |
| **sample a file, or size a feature before building it** | 62, and `docs/PROXIES.md` |
| **publish a number that confirms what you just concluded** | 62 — re-derive it by another method |
| **fix a constant** — any constant | 41, always |
| **finish any capability** — before calling it done | **60** — a model must be able to reach it |
| make anything **optional**, or a dependency degrade | 17 |
| **generalise** from one case, or reach for a shared helper | 16, 24, 33 |

**The three that keep re-earning themselves**, because reading them once has not been
enough:

- **41 — a rule written after a fix does not sweep for the other instances.** When you fix
  a constant, grep for it. The two-digit CBETA volume was fixed in the bake and left wrong
  in the reader, where it mis-cited 725,650 segments, and then found a third time in
  acquisition.
- **8 — a scripted patch that reports success may have done nothing.** Eight occurrences,
  two of them while writing rules about it. Grep for the new text afterwards.
- **1 — a buffered element that can span a line must be split at that line.** Fixed twice;
  the second time it left 10,590 printed lines with no citation.

Checkpoint tasks are marked ⛔ and are real stops — see `docs/CHECKS.md`.

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
   presentable as an Indian sūtra — this is enforced structurally in the tool
   response shape, not by prompting.
5. **Deterministic before probabilistic.** If an alignment, parallel, or quotation
   link can be found by string/table/structure matching, do that. The LLM handles
   only the residual, and its output is labeled with lower confidence.
6. **Every retrieval change runs against `evals/`.** Recall@k and citation accuracy
   are published numbers, not vibes.
7. **The MCP surface is read-only. Tools read; the CLI writes.** Never add an ingest
   or mutation tool. If a model could write to the corpus, reproducibility from
   `sources.lock.json` is gone, `bake_id` stops determining contents, and prompt
   injection becomes corpus poisoning — local-source text is already untrusted input.
   See `docs/ADDING_TEXTS.md` for the write path and `docs/MCP.md` for the read one.
8. **A machine translation is never citable as source.** Generated text is a layer
   over a source anchor, never a top-level URN, and the citation guard rejects any
   quote resolving to `method != human` presented as canonical. Once the corpus holds
   generated translations of everything, this is the invariant that keeps our own
   model output from being served back as scripture. See `docs/LAYERS.md`.

## Which document to open, by what you are doing

Every document in `docs/` is in this table, and `Docs.RoutingTest` fails the build otherwise. It is the routing layer; without it the answer to "where is
that written down" is a grep, and a grep finds the file that mentions a thing rather than
the file that owns it.

| doing… | open |
|---|---|
| starting a session, orienting | `docs/STATUS.md`, then `docs/PLAN.md` |
| **adding a text source** | `docs/ADDING_TEXTS.md`, `docs/SOURCES.md` — and the normalizer rules above |
| changing **retrieval** | `docs/ARCHITECTURE.md`; run `evals/` — invariant #6 is not optional |
| changing **embeddings** or renting a GPU | `docs/EMBEDDING.md`, `docs/GPU_RUNBOOK.md` |
| touching the **MCP surface** | `docs/MCP.md` — a tool that is not in its table is a tool a model will not find |
| touching the **reader** | `docs/READER.md` |
| **translations** or generated text | `docs/LAYERS.md`, `docs/TRANSLATION.md` — invariant #8 lives here |
| **commentary / parallels / quotations** | `docs/COMMENTARY.md` |
| anything **public or licensed** | `docs/DEPLOY.md`, the licensing posture below, `mix pramana.public.check` |
| a **phase gate**, or "am I done" | `docs/CHECKS.md` |
| local setup, Postgres, toolchain | `docs/DEV_ENV.md`, `docs/ELIXIR.md` |
| **debugging**, or wondering why nothing can tell you what happened | `docs/OBSERVABILITY.md` — audited 2026-08-29, and mostly a plan |
| wondering **why** something is the way it is | `docs/HISTORY.md`; if it was a measurement, `docs/PROXIES.md` |
| changing **how a model reads the corpus** | `docs/AGENT_MODELS.md` — the alternatives to MCP tools, and what none of them fix |
| wondering whether an idea was already tried | `docs/PLAN.md` § "Rejected, with evidence" — **check before proposing** |
| onboarding a person, or explaining the project | `docs/PRIMER.md`, `README.md` |
| renting a GPU, or anything that runs off this machine | `docs/CLOUD.md` |
| asked how this compares to another system | `docs/COMPETITIVE.md` |
| looking for something to build, or parking an idea | `docs/IDEAS.md` — unfiltered, unlike `docs/PLAN.md` |
| the SAT request that Phase 2 is blocked on | `docs/sat-request-email.md` — **sent 2026-08-15, awaiting reply** |

## Keeping the documentation true

These are the rules that keep the two tables above worth trusting. Every one was learned the
same way: a document that had quietly stopped being true.

1. **Never write down a number the code computes.** State the shape and name the function.
   `Coverage`'s own moduledoc said "this holds two" through four ingests; the reader doc
   quoted a text count that went stale within two. If you want the number, run the function.
2. **A statement about the past belongs in `docs/HISTORY.md`, or carries its date.** A
   historical sentence in a current-state file reads as a current claim — precisely what
   made `STATUS.md` wrong four times.
3. **A new rule is not finished until a trigger points at it.** Add it to `docs/RULES.md`
   *and* to the trigger table above. `Docs.RoutingTest` fails the build otherwise: a rule
   nobody is routed to fires after the defect rather than before it.

   **The same holds for a mix task, an MCP tool and a document**, and for the same reason.
   `Docs.TasksTest` requires every task to be named somewhere; `MCP.DocumentedTest` requires
   every tool to be in `docs/MCP.md`'s table; `Docs.RoutingTest` requires every file in
   `docs/` to appear in the routing table above. Each check was written after something
   turned out to be unfindable — ten of forty-nine tasks named nowhere, four documents
   unreachable including the one you need before renting a GPU.

   **The shape is always the same: a capability nobody is routed to has not shipped.** If you
   add a fifth kind of thing, add its check in the same commit.
4. **`docs/PLAN.md` changes in the same commit as the work.** Finishing an item,
   discovering work, or invalidating an estimate each require an edit.
5. **When a doc and the code disagree, the code wins — then fix the doc in that commit.**
   Not later, not in a cleanup pass.
6. **Verify a scripted doc edit by grepping for the new text.** A `str.replace` whose anchor
   missed still exits zero and still lets the commit run. Eight occurrences; see rule 8.
7. **Publish the gap, not just the total.** A figure without its denominator is the failure
   this project is most prone to — rules 22, 44 and 54.

## Layout

An umbrella app. `pramana` is pure domain logic with no web dependency.

```
sources.lock.json          pinned upstream snapshots (commit SHAs, sha256, licenses)
raw/                       untouched upstream downloads — gitignored, never edited
apps/
  pramana/                  CORE DOMAIN — no Phoenix dependency
    lib/pramana/
      urn/                 URN parse, resolve, verify — the foundation
      corpus.ex            resolve, context windows, outlines, range URNs
      corpus/              Ecto schemas + Loader
      acquire/             fetchers (cbeta.ex), catalog, bulk archive, lockfile
      normalize/           Saxy streaming TEI/XML -> canonical IR
      segment/             IR -> citable units via native citation grammars
      taisho/divisions.ex  the 部 table: provenance for the Chinese canon
      retrieval/lexical.ex bigram search, phrase/ngram modes, provenance filters
      retrieval/survey.ex  exhaustive counts, not a ranked sample
      guard.ex             post-generation citation verification
      bake/worker.ex       one Oban job per work
      enrich/              (Phase 6) alignment, quotation graph
      index/               (Phase 1 #11) embeddings
      pipeline.ex          Acquirer/Normalizer/Segmenter behaviours + source registry
      bake.ex              pipeline_version, bake_id, recording
      bake/                Oban orchestration
  pramana_web/              Phoenix — MCP endpoint, LiveView reader (`docs/READER.md`)
  pramana_native/           Rustler NIFs: CJK segmentation, suffix-array reuse
priv/embed/                Python sidecar — BGE-M3 inference ONLY (see docs/ELIXIR.md)
evals/                     gold question sets + scoring harness
docs/                      ARCHITECTURE, SOURCES, ROADMAP, COMPETITIVE, ELIXIR, MCP, READER
```

## Stack

**Elixir 1.20.3 / OTP 29.0.5 · Phoenix 1.8.11 · Ecto · PostgreSQL 18 + pgvector (HNSW)
+ pg_bigm · Oban · Saxy · Req · Rustler.** Toolchain versions are pinned
exactly in `mise.toml` — run `mise trust` in this directory or the global config
silently wins. See `docs/ELIXIR.md` for the rationale and the three deliberate
exceptions, and `docs/DEV_ENV.md` for why Postgres runs natively rather than in a
container.

Elixir is the default for everything and is a genuinely good fit here — the bake is a
massively concurrent, fault-tolerant, backpressured file-processing job, which is
what BEAM is for, and Elixir binaries are UTF-8 native, which matters for CJK.

**Three narrow exceptions, and only these:**

1. **Rustler NIF** — CJK word segmentation (`jieba-rs`). In-process, no sidecar.
2. **Rust port binary** — suffix-array text-reuse detection over 250M+ chars. Batch,
   memory-hungry, would block BEAM schedulers. Kept outside the VM entirely.
3. **Python sidecar (`priv/embed`)** — BGE-M3 inference, and nothing else. Behind a
   deliberately tiny interface (`{texts, mode} -> vectors`) so it stays replaceable.
   It was scoped to include Tibetan `botok` segmentation and never needed to: the
   lexical layer windows syllables on the tsheg the edition itself prints, which cannot
   mis-segment a transliterated name the way a dictionary tokenizer does. That
   dependency was never taken, and four documents went on describing it — including this
   one, which is the file a new session treats as binding.

Do not let the Python sidecar grow. It does tensor math.
Every other decision — orchestration, retries, normalization, provenance, retrieval —
lives in Elixir. If you're tempted to add logic to the sidecar, that's a signal you're
putting domain logic in the wrong place.

**One database.** Text, segments, embeddings, and FTS all live in Postgres so that
provenance filters and vector search compose in a single query. Do not add
Elasticsearch or a separate vector store without a benchmark showing it's needed.

## Licensing posture — read before touching data

We are **open-source, self-hosted**. Code is Apache-2.0. **We publish the pipeline,
not the corpus.** Each user bakes their own copy from upstream.

- CBETA — non-commercial, header must remain intact
- SAT — CC BY-SA 4.0
- SuttaCentral `bilara-data` — CC0
- 84000 — check per-text terms
- BDRC — restrictive; images, not text

Each source row carries its license, and the API can be configured to exclude
license classes. Never commit corpus text to git. A public demo, if one ever ships,
serves the CC0/CC-BY subset only.

## Working conventions

- Classical Chinese has no whitespace — never use whitespace tokenization or
  `pg_trgm` on it (trigrams cannot serve the two-character queries that dominate).
  Use `pg_bigm`. And do **not** reach for jieba tokens as a retrieval fallback: it
  shatters Buddhist transliterations into single characters. Character n-grams are the
  fallback. See `docs/ELIXIR.md`. CJK bugs from Latin-script assumptions are the
  most common failure mode in this codebase. `String.split/1` on a Chinese passage is
  always a bug; so is `String.length/1` used as a proxy for word count.
- Parse TEI with **Saxy in streaming mode**, never by loading a whole document. Some
  CBETA files are large, and a bake touches thousands of them concurrently.
- Bake stages are **Oban jobs, idempotent and keyed by content hash**. Re-running a
  bake must re-embed only what changed. One malformed file fails one job, never the
  bake.
- CBETA gaiji (`<g ref="#CB01234"/>`, ~30k rare glyphs) must go through the gaiji
  mapping table. Dropping them silently corrupts search — there is a test for this.
- CBETA punctuation is modern editorial addition, not in the witness. Keep it, flag it.
  `Pramana.Punctuation` is the single definition of what counts as editorial — strip it when
  comparing two passages to each other, and **never when querying the index**, which holds
  what the editor printed. Getting that backwards made a recall probe report 0.0%.
- Preserve `<lb/>`, `<juan>`, `<lg>/<l>`, and `<app>/<lem>/<rdg>` through
  normalization — line breaks are load-bearing for citation, and the apparatus is a
  feature we ship.
- Prefer adding a source-specific normalizer over branching inside a shared one.
- **Adding a source takes one of two shapes, and the source's own file layout decides
  which.** What holds either way: a new source **edits no existing source and adds
  nothing to `mix pramana.bake`**, and it always adds a `Pramana.Sources` entry, because
  that is where the licence and the tradition are declared.
  - **One file per work** → implement the three `Pramana.Pipeline` behaviours and add a
    `Pipeline.@sources` entry. `mix pramana.bake` then dispatches to it and runs one Oban
    job per work. CBETA is this, and is currently the only member.
  - **Anything else** → a dedicated `mix pramana.<source>.ingest` calling the normalizer
    and `Corpus.Loader` directly. SuttaCentral, Derge and 84000 are all this, and the
    behaviour could not express them: `Normalizer.normalize/2` returns `{:ok, IR.t()}`,
    one work per input, while `Bilara.normalize_file/2` returns `{:ok, [IR.t()]}`
    (`an1.1-10` is ten suttas) and `Derge.normalize_file/2` returns
    `{:ok, [IR.t()], still_open}` — a Derge work spans volumes and must be assembled
    across them in printed order, which per-work jobs cannot do.

  This bullet used to say "three behaviours plus one registry entry — nothing else", and
  `docs/ADDING_TEXTS.md` named bilara and 84000 as examples of it. Three of the four text
  sources here have never worked that way. When SAT (#14) lands it is Taishō, one file per
  work, so it is the first branch — and it is already registered in `Pramana.Sources`.
- **Bump `Pramana.Bake.pipeline_version` when normalization or segmentation output
  changes**, not for refactors. When in doubt, bump: two different corpora sharing a
  `bake_id` is far worse than a spurious new one.

## Commands

```bash
mise trust && mise install             # pinned Erlang/Elixir
brew services start postgresql@18      # native; see docs/DEV_ENV.md
mix deps.get
mix ecto.setup                         # create + migrate
mix pramana.acquire --source cbeta
mix pramana.bake --config dev           # small subset for iteration
mix test
mix format && mix credo --strict
mix phx.server                         # HTTP API + MCP endpoint on :4000
mix pramana.mcp.stdio                   # stdio MCP server for local Claude Code
mix pramana.evals                       # retrieval + citation scores
```

**Start a session with `mix pramana.doctor`.** It prints what is otherwise rediscovered with
hand-written SQL — which bake this is and whether it still describes its inputs, what is
loaded, what is declared and never acquired, what is missing.

```bash
mix pramana.doctor                      # the state of this checkout, in one command
mix pramana.gate                        # every mechanical check; --quick for the code half
mix pramana.coherence                   # do independently derived facts about one work agree?
mix pramana.recall --seed 0.42          # retrieval against the corpus's own quotations
mix pramana.recall --parallels          # ...and against curated cross-lingual parallels
mix pramana.provenance                  # re-derive composition_origin / text_role
mix pramana.authority.import            # DILA people and places into reference tables
mix pramana.authority.link              # bylines -> people, and works -> date bounds
```

Use the `dev` bake config (a few hundred works) while iterating. A full bake is hours
and significant embedding cost — don't run one to test a normalizer.

**A measurement task takes `--seed`, and a figure quoted without one is an anecdote**: the
sample changes every run, so no number can be compared with the number before it.
`mix pramana.recall` and `mix pramana.verify --sample` are the two tasks that sample, and
both seed through `Pramana.Sampling.seeded/2`. **A seed applied outside that helper does
nothing at all** — `setseed` and the query it seeds land on different pooled connections,
which is rule 67 and is why every seeded figure this project published was an unseeded draw.
