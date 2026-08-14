# Status

Living handoff document. **Update this at every checkpoint gate.** If you are a new
session with no context, read this first, then `CLAUDE.md`, then `docs/ROADMAP.md`,
then run `TaskList`.

---

## Where we are

**Phase 0 complete and gated** (tag `phase-0`). **Phase 1 in progress:** #9, #10, #12,
#31 and #35 done; #11, #32, #33 remain.

**Provenance is populated across the whole Taishō** from the division (部) table:
1,781 Indic works, 555 Chinese, 135 deliberately unattributed (古逸部 Dunhuang), and
**57 apocrypha** flagged. The differentiating query now works on real data — searching
一切眾生皆有佛性 returns Indic root scripture, Chinese commentary, or the apocryphal
T2883 法王經 depending on the filter.

**The full Taishō is baked.** 2,471 works, **4,729,656 segments**, 90.6M characters,
zero failures, 190 s. `mix pramana.verify`: all 2,471 texts re-normalize from `raw/`
byte-identically. Lexical search runs in **26–63 ms** across 4.7M segments. Database
3.7 GB (segments 3.5 GB, bigram index 1.3 GB).

Lexical search works: `pg_bigm` bigram index, phrase-then-n-gram fallback, provenance
filters composing as SQL, and a `search` MCP tool returning results **grouped by origin
and role**. Queries run in 5–40 ms over 5,341 segments.

Reading affordances work too (task #31): context windows, outlines from `<cb:mulu>`, and
range-URN resolution. Adopted after reviewing tripitaka-mcp.com — see
`docs/COMPETITIVE.md` for what was taken and what was rejected. Tasks **#32** (variant
characters), **#33** (MCP resources + reader links) and **#34** (ingest the
huangnianzu-translation glossary) came out of the same review.

The end-to-end path works: acquire → normalize → segment → load → resolve → verify,
with an MCP server on top. A model can fetch an exact Lotus Sūtra passage by URN and
the guard byte-compares its quote.

### Verified, not just built

| Claim | Evidence |
|---|---|
| Nothing lost in normalization | 5374 lines == 5374 body `<lb>`; 941 attached + 4 unanchored == 945 == raw `<app>` |
| Citations are unique | all 5374 line anchors distinct; all URNs parse |
| Spans are byte-verifiable | all 5341 segments' byte offsets slice their exact content out of the body |
| The bake is reproducible | `mix pramana.verify --all`: body re-normalized from `raw/` is **byte-identical** to stored |
| The guard actually catches things | fabricated URN refused; 譯→說 single-character alteration caught, over the wire |

### Gate results (at tag `phase-0`; test count has grown since)

- `mix format --check-formatted` clean
- `mix compile --warnings-as-errors` clean
- **148 tests** passing (128 domain / 13 web / 7 native). Now **175**.
- `mix credo --strict` — 69 checks, 0 issues
- **`mix dialyzer` — 0 errors**
- `mix deps.audit` — no vulnerabilities
- `mix pramana.verify --all` — 1 text, 5341 segments, byte-identical
- Architecture review: all seven invariants hold (see below)

### Architecture review, Phase 0

- **#1** `pramana_web` touches `Repo` in **0 files** — the web layer goes through the
  domain. Every MCP response is `Response.json` or `Response.error`, never prose.
- **#2** URNs are built from each tradition's own citation grammar; no invented IDs.
- **#3** `raw/` is gitignored and nothing from it is committed; `mix pramana.bake`
  verifies `raw/` against the lockfile *before* trusting a byte of it.
- **#4** Provenance is CHECK-constrained columns (`composition_origin_known`,
  `text_role_known`), indexed, never a single source string.
- **#5** Deterministic throughout Phase 0; no LLM in the pipeline yet.
- **#6** No retrieval yet, so no evals yet. Phase 4 owns this.
- **#7** Wired in `Guard.citable_as_source/1` and tested via `check_span/3` with a
  synthetic span, so it is not retrofitted in Phase 3.
- No `priv/embed` sidecar exists yet — correct for Phase 0.

---

## Next

Task **#9** — full CBETA ingest via Broadway + Oban. This is the big one: ~1.18 GB
upstream, thousands of TEI files, real concurrency and resumability.

Note the deliberate reordering: #10 (lexical search) was done **before** #9, so
segmentation and ranking could be shaken out against one fast text rather than
debugged during hours-long full bakes. Then #11 (embeddings) and #12 (provenance
population + survey_corpus), then the Phase 1 gate (#13).

**#12 matters more than its position suggests.** Provenance is currently NULL for
T0262, so every search result groups as `uncatalogued` and the origin/role filters —
the project's differentiator — cannot be positively demonstrated on real data. They
are tested against fixtures, but the real corpus needs catalogue data.

---

## Decisions taken

| Decision | Rationale |
|---|---|
| Name: **Pramāṇa** | "Valid means of knowledge." The name is the thesis; survives the medical-text expansion, which `dharma-*` would not. |
| Open-source, self-hosted | We publish the **pipeline, not the corpus**. Keeps CBETA's non-commercial clause and BDRC's restrictions out of our distribution. |
| All four traditions in v1 | Tibetan is the acknowledged long pole and the designated thing to cut if the schedule slips. |
| One Postgres | The predicate-plus-vector query is the most important query in the system. |
| MCP + HTTP API first, UI last | Makes the Phase 8 reader a renderer rather than a second implementation. |
| Elixir/Phoenix, 3 exceptions | See `docs/ELIXIR.md`. |
| Native Postgres, not Docker | The bake reads hundreds of thousands of small files; container FS on macOS is the slow path. `docs/DEV_ENV.md`. |
| **MCP library: `anubis_mcp`** | `hermes_mcp`'s last release was 2025-08-14 (a year stale); `anubis_mcp` 2.0.0 shipped 2026-08-07 with ~7× the daily downloads. The fork is maintained; hand-rolling JSON-RPC is no longer warranted. |
| **Segments carry char AND byte offsets** | Char offsets are for clients (multi-byte CJK); byte offsets are for the server (`binary_part/3` is O(1) vs `String.slice/3` O(n)). Verifying T0262 went 18.5s → 1.7s, and the guard resolves spans on every answer. |
| **Embeddings: dense in Bumblebee is viable** | BGE-M3 declares `architectures: ["XLMRobertaModel"]` and Bumblebee maps `XLMRobertaModel => Bumblebee.Text.Roberta`. Its sparse/ColBERT heads are two loose `.pt` linear layers, not part of the HF model — so they are portable to Nx, which could remove Python entirely. Ladder in `docs/ELIXIR.md`. |
| **Lexical fallback: character n-grams, not jieba tokens** | jieba is trained on modern Chinese and shatters Buddhist transliterations into single characters (耆闍崛山 → 4 tokens; 般若波羅蜜多心經 → `["般若","波","羅","蜜","多心","經"]`, inventing "多心"). OR-matching those returns noise. n-grams need no dictionary. jieba is kept for the Phase 6 reading layer (多音字 disambiguation is context-dependent) and the later modern-Chinese corpus. |
| **`text_role` means FUNCTION, not arrival** | A Chinese translation of an Indian sūtra was `translation`, which describes how it arrived — and `composition_origin` already answers that. `root` (scripture), `treatise` (論), `catalogue`, `history` describe what a text *is*. This makes `origin = 'indic' AND role = 'root'` say what it means. |
| **Provenance is assigned during the BAKE, not by a later pass** | The loader replaces work attributes on conflict, so a bake computing weaker provenance than a backfill would silently erase it on the next re-bake. One source of truth (the division table), applied in the pipeline, makes a re-bake converge. There is a test. |
| **`pg_bigm` over `pg_trgm`/tsvector** | `pg_trgm` indexes trigrams, so the two-character queries that dominate Chinese cannot use the index at all. tsvector needs a tokenizer Postgres lacks. Bigrams accelerate `LIKE '%…%'` and are vocabulary-independent — they find 阿㝹樓馱 that no lexicon knows. Builds from source against Homebrew PG 18.4 in under a minute. |
| `.credo.exs` from `gen.config`, patched | A hand-written config silently **replaced** the default check set (3 checks instead of 69). Never hand-roll it. |

## Open questions

- **BGE-M3 multi-vector in Nx** — port the two linear heads and drop the sidecar, or
  keep a bake-time sidecar? Decide in Phase 1 once dense works. *(Task #11)*
- **Tibetan `botok`** has no Elixir/Rust equivalent, so the sidecar survives until at
  least Phase 5 regardless — bake-time only.

## Surprises and gotchas

Each of these cost real time; they are recorded so they cost it only once.

- **`mise trust` is path-keyed.** An early `mise install` silently no-op'd because the
  project config was untrusted, and the global config won. Renaming the project
  directory invalidated the trust again.
- **In an umbrella, `File.cwd!()` is not the umbrella root** — mix runs each child app
  from its own directory. `config :pramana, :project_root` is pinned at compile time
  via `Path.expand("..", __DIR__)` instead.
- **CBETA keeps its apparatus in `<back>`**, not inline, keyed to `<anchor>` positions
  in the body. Assuming inline `<app>` yields empty lemmas.
- **`<lb/>` also appears inside `<back>` lemmas** (which reproduce body text). Treating
  those as line boundaries invented 35 phantom lines with **duplicate anchors** —
  non-unique URNs. `<lb/>` handling is body-only.
- **`<lem>` spans `<lb/>`.** Buffering lemma text and flushing at `</lem>` attributes
  the whole lemma to whichever line closed it.
- **A second URN regex silently disabled the guard.** The quote-pairing pattern's
  character class omitted `:`, so it captured `pramana:cbeta.T` and never matched a
  real URN; every citation fell through to existence-checking and altered quotes
  passed. There is now one `@urn_source`. The test that missed it asserted only `ok?`,
  which is true either way — hence `verified_quotes` in the result.
- **Elixir map typespecs are exact.** An undeclared key in `Corpus.span()` made the
  spec unsatisfiable, and dialyzer narrowed `resolve/1` to its error branch and
  reported every downstream `verdict == :ok` as impossible. Same class of bug in
  `URN.t()`'s `raw` field.
- **Ecto schemas do not define `t/0`**, and Mix/ExUnit are absent from dialyzer's
  default PLT (`plt_add_apps: [:mix, :ex_unit]`).
- **`phx_new` is 1.8.9 while `phoenix` is 1.8.11** — they version separately.
- **Homebrew Postgres uses your OS username**, not `postgres/postgres`.
- **`length(acc)` inside a reduce is quadratic, and only scale reveals it.** The
  segmenter recomputed each ordinal that way. On T0220a (大般若波羅蜜多經, 600 fascicles,
  92,192 segments) that meant ~4.2 billion traversals: 89 s of segmenting against 1.4 s
  of parsing. It presented as a *database* timeout, and no amount of pool tuning would
  have fixed it. Carrying the counter: 89.4 s → 2.3 s. **Measure before tuning.**
- **Oban 2.23 needs migration v14** (v12 errors at boot), and its
  `Oban.Testing.perform_job/2` signature changed — call the worker directly instead.
- **`function_exported?/3` is false for a module that is merely not loaded**, so a test
  using it passes or fails by load order unless you `Code.ensure_loaded!` first.
- **A scripted patch that errors leaves docs untouched while the commit still runs.**
  This bit three times. Always verify the file, and never trust an unconditional
  "patched" message.
- **`mix format` rewrites `field :x, opts` to `field(:x, opts)`.** A scripted patch
  matching the unparenthesised form silently no-ops afterwards. This bit once: the MCP
  input schema kept its old shape while `execute/2` gained new params, so the tool
  accepted the arguments in a direct call and **silently ignored them over MCP**. If a
  patch script prints success unconditionally, it is lying — verify the file.

## Metrics

| Gate | Tests | Recall@10 | Citation accuracy | Bake time | Segments |
|---|---|---|---|---|---|
| phase-0 | 148 | — | — | 62 ms (T0262 normalize) | 5,341 |
| task-10 | 175 | — | — | lexical query 5–40 ms | 5,341 |
| task-31 | 190 | — | — | outline 40 entries | 5,341 |
| **#9 full Taishō** | **227** | — | — | **190 s / 2,471 works** | **4,729,656** |
| #12 provenance | 257 | — | — | survey 88 ms exhaustive | 4,729,656 |
