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

Read **`docs/STATUS.md`** first — it says where we are, what was decided and why, and
what surprised us. Then this file's invariants, then `docs/ROADMAP.md`. Then run
`TaskList`; tasks carry their own context and point back to the relevant docs.

**Before writing a new source pipeline, read `docs/STATUS.md` § "Rules that
generalize".** Eight rules, each learned from a real defect, and most of them apply
directly to the next normalizer. Two have already been rediscovered the hard way — the
same buffered-element-spans-a-line bug was fixed twice, and the second time it left
10,590 printed lines with no citation.

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
      bake/                Oban/Broadway orchestration
  pramana_web/              Phoenix — HTTP API, MCP endpoint, LiveView reader (later)
  pramana_native/           Rustler NIFs: CJK segmentation, suffix-array reuse
priv/embed/                Python sidecar — embeddings + Tibetan botok ONLY
evals/                     gold question sets + scoring harness
docs/                      ARCHITECTURE, SOURCES, ROADMAP, COMPETITIVE, ELIXIR, MCP
```

## Stack

**Elixir 1.20.3 / OTP 29.0.5 · Phoenix 1.8.11 · Ecto · PostgreSQL 18 + pgvector (HNSW)
+ pg_bigm · Oban · Broadway · Saxy · Req · Rustler.** Toolchain versions are pinned
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
3. **Python sidecar (`priv/embed`)** — BGE-M3 multi-vector inference and Tibetan
   `botok` segmentation. Behind a deliberately tiny HTTP interface
   (`POST /embed {texts, mode} -> vectors`) so it stays replaceable.

Do not let the Python sidecar grow. It does tensor math and Tibetan tokenization.
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
- Preserve `<lb/>`, `<juan>`, `<lg>/<l>`, and `<app>/<lem>/<rdg>` through
  normalization — line breaks are load-bearing for citation, and the apparatus is a
  feature we ship.
- Prefer adding a source-specific normalizer over branching inside a shared one.
- **Adding a source means implementing three `Pramana.Pipeline` behaviours plus one
  registry entry — nothing else.** If you find yourself editing `mix pramana.bake` or an
  existing source in order to add a new one, the contract is wrong; fix the contract.
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

Use the `dev` bake config (a few hundred works) while iterating. A full bake is hours
and significant embedding cost — don't run one to test a normalizer.
