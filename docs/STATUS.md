# Status

Living handoff document. **Update this at every checkpoint gate.** If you are a new
session with no context, read this first, then `CLAUDE.md`, then `docs/ROADMAP.md`,
then run `TaskList`.

---

## Where we are

**Phase 0 and Phase 1 complete and gated** (tags `phase-0`, `phase-1`). **Phase 2: #15
and #16 done, #14 blocked on acquisition, gate (#17) run but deliberately NOT tagged**
— see the gate findings below.

**The whole Chinese canon is baked, verified, and embedded.** 2,471 works, **4,740,246
segments**, 90.6M characters, pipeline v3, 150 s, zero failures. Both integrity checks
are green over every text: `mix pramana.verify --all` (byte-identical re-normalization
from `raw/`) and `mix pramana.integrity` (nothing printed in the source is missing from
the bake — a different question, see the rules section).

**Semantic search covers 100% of the corpus.** 299,317 chunks embedded with BGE-M3 on a
rented L4: 34 min, ~$0.45, 0 rejected vectors. Hybrid retrieval fuses lexical and
semantic by Reciprocal Rank Fusion. Querying 眾生皆能成佛 — a paraphrase that appears
nowhere as a literal string — returns 故眾生無不成佛 at 0.817 similarity, which the bigram
index structurally cannot do. Lexical alone runs in 26–63 ms; filtered semantic in
0.5–3 s.

**Provenance is populated across the whole Taishō** from the division (部) table: 1,781
Indic works, 555 Chinese, 135 deliberately unattributed (古逸部 Dunhuang), and **57
apocrypha** flagged. Search results arrive in buckets keyed by composition origin and
text role, each labelled in plain language ("Japanese-composed commentary"), so the
distinction cannot be flattened away by a caller.

**What is NOT here, and says so:** Taishō volumes 56–84 — the Japanese-composed
sectarian corpus. CBETA excludes them and only SAT publishes them, and SAT has no bulk
download (#14). Until that is resolved `Pramana.Coverage` states the gap in every survey
response, because otherwise an absence of Japanese results reads as the tradition being
silent.

The end-to-end path works: acquire → normalize → segment → chunk → embed → resolve →
verify, with an MCP server on top exposing five tools and two resources. A model can
fetch an exact passage by URN and the guard byte-compares its quote.

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

Phase 1 is complete and gated (**#13**), and the full-corpus embedding run has landed.

**Phase 2:** #15 (structural provenance) and #16 (local-source manifest path) are done —
the Huang Nianzu commentary is in the corpus, page-anchored and licence-gated. #37
(batched embedding import) is done. The gate (#17) has been run; the tag is withheld
until #14 resolves.

**#14 is blocked and needs a human.** SAT publishes no bulk download, so obtaining
Taishō 56–84 starts with an email to `sat at l.u-tokyo.ac.jp` — a draft is in
`docs/sat-request-email.md`, not sent.

**#32**, **#34**, **#36** and **#37** are all done. Nothing in Phase 2 remains except
**#14**, which is waiting on SAT's reply. **Phase 3** (#18, SuttaCentral Pāli) is the
next substantial work and brings the first redistributable content.

**Phase 3 matters more than its number suggests:** SuttaCentral `bilara-data` is CC0 and
would be the **first redistributable content in the corpus**. Until then the public
surface has nothing to serve — see gate finding 2.

**Still unmeasured:** recall@k and citation accuracy. There is no gold set until #19
(Phase 4), so every claim about retrieval quality here rests on spot-checks, not a
metric.

### Phase 1 gate findings (#13)

The gate did its job — it found more than it confirmed.

| check | result |
|---|---|
| format / compile --warnings-as-errors / credo --strict | clean |
| dialyzer | 0 errors |
| `mix deps.audit` | no known vulnerabilities |
| `mix hex.outdated` | 2 pinned back: `phoenix_live_view` 1.1.33→1.2.9, `phoenix_live_dashboard` 0.8.7→0.9.0. Both LiveView, unused until Phase 8; upgrade deliberately there |
| `mix pramana.verify --all` | 2,471 texts, 4,740,246 segments, byte-identical from `raw/`, 2m37s |
| `mix pramana.integrity` | every `<lb/>`, every printed line, every gaiji accounted for |
| `mix test --cover` | **failed at first** — see below |

**Fidelity (the big one).** `verify` proved reproducibility and could not prove
completeness: 10,590 printed lines had no URN, including 473 rare characters and
266,547 characters of interlinear note text. Two defects, both fixed, pipeline v1 → v3.
`mix pramana.integrity` now guards it. This is recorded at length under *Surprises*
because the general lesson — a deterministic pipeline drops the same thing every run,
so self-comparison cannot detect loss — applies to every source added from here on.

**Architecture review**, against `CLAUDE.md`'s seven invariants:

- **One violation, introduced in this phase and fixed:** the `pramana://inventory` MCP
  resource built its own Ecto queries, so `pramana_web` was reading the database
  directly. Moved to `Pramana.Inventory`. `docs/CHECKS.md`'s wording for this audit was
  also inverted and has been corrected.
- Tools returning quotable text all carry `urn` + offsets + `sha256`. `get_outline` and
  `survey_corpus` return structure and counts only, so the rule does not bind them —
  but `get_outline` was not naming its `bake_id` and now does.
- No generated translation is reachable as a top-level URN (no translation layer exists
  yet — Phase 3).
- No network access anywhere in the bake path outside `Pramana.Acquire`.
- MCP surface is read-only; no ingest or mutation tool exists.

**Coverage.** Failed against Mix's default 90%. The uncovered modules were CLI shells
over already-covered domain functions (`pramana.embed.import` 0% / `Embed.Transfer`
100%), OTP callbacks, and Phoenix scaffolding unused until Phase 8. Configured
deliberate exclusions, then wrote the tests the exclusions did *not* excuse —
`Pramana.Inventory`, `survey_corpus` and `get_outline` had almost none. Now a ratchet:
**pramana 79%, pramana_web 82%**, never to be lowered to make a run pass.

**Not done at this gate:** evals (#19, Phase 4 — there is no gold set yet, so recall@k
and citation accuracy remain unmeasured) and the full-corpus embedding run.

### Phase 2 gate findings (#17) — **NOT TAGGED**

**The tag is deliberately withheld.** #14 (SAT ingest) is blocked on acquisition, so
Phase 2 has an open task by definition, and stamping a gate green over a known gap is
how gates stop meaning anything. **Condition to tag `phase-2`:** #14 resolves, or it is
formally moved to a later phase.

Everything else was run, and it found three real things.

| check | result |
|---|---|
| format / compile --warnings-as-errors | clean |
| credo --strict | **5 issues**, all from the #16 verify/integrity changes — fixed |
| dialyzer | 0 errors |
| deps.audit | no known vulnerabilities |
| hex.outdated | 2 pinned back (both LiveView, unused until Phase 8) |
| test --cover | 357 + 56 + 7, ratchet held |
| verify --all / integrity | green over 2,472 texts |

**1. The licence filter did not exist.** #16's exit criterion required the local text to
be "excluded under a CC0-only licence filter". `license_class` was recorded on every
source and displayed in every result, which made it *look* enforced — but **no retriever
could filter on it**, so "we publish the pipeline, not the corpus" was a promise kept by
hand. Now `redistributable_only:` and `license_class:` filter in Lexical, Semantic and
Survey, with tests. #16 had been marked complete against a criterion no code met.

**2. The public corpus is currently EMPTY.** With the filter in place,
`redistributable_only: true` returns **0 hits across all 4.7M segments** — CBETA is
`nc`/not-redistributable, the Huang Nianzu commentary is `restricted`. The Phase 8
public demo has nothing it could serve today. First redistributable content is
SuttaCentral `bilara-data` (CC0) in Phase 3. Worth knowing now, not at Phase 8.

**3. `credo` was not clean at the #16 commit**, which claimed it was — the
verify/integrity changes landed after the credo run. Run the checks *last*, not
mid-change.

**Architecture review** — all seven invariants hold. `pramana_web` touches `Repo` in 0
files; no MCP tool mutates; **0 corpus files tracked by git** (`raw/` and
`sources/local/*/text/` both ignored); no generated translation exists yet; the bake
reads only from pinned sources.

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
| **RRF, not score blending** | Lexical scores are occurrence counts; semantic scores are cosine similarities. They share no scale, and normalising them means picking a weighting that is a guess dressed as arithmetic. RRF uses only *rank*, so it is robust precisely because it discards the incomparable part. |
| **A query serving is separate from the indexing serving** | A serving compiled for batch 16 pads a single query to 16 rows and does 16× the work — measured at 10.6 s per query, versus 0.3–0.5 s at batch 1. Throughput config and latency config are not the same config. |
| **Unknown search options RAISE** | `division:` was silently dropped by the lexical retriever while the semantic one honoured it, so hybrid results were contaminated with works from outside the requested division *and still looked filtered*. Silently ignoring an unknown option is how that happened. |
| **Embed CHUNKS, never segments** | A segment is one printed line averaging **18.2 characters**, broken typographically: in T0262 the name 阿若憍陳如 splits across lines as `…阿若憍`/`陳如…`, so embedding it embeds half a name. Chunks are ~300-char windows — semantically coherent, and 15.8× fewer rows, which is the difference between embedding the corpus in an afternoon and in a week. |
| **`text_role` means FUNCTION, not arrival** | A Chinese translation of an Indian sūtra was `translation`, which describes how it arrived — and `composition_origin` already answers that. `root` (scripture), `treatise` (論), `catalogue`, `history` describe what a text *is*. This makes `origin = 'indic' AND role = 'root'` say what it means. |
| **Provenance is assigned during the BAKE, not by a later pass** | The loader replaces work attributes on conflict, so a bake computing weaker provenance than a backfill would silently erase it on the next re-bake. One source of truth (the division table), applied in the pipeline, makes a re-bake converge. There is a test. |
| **`pg_bigm` over `pg_trgm`/tsvector** | `pg_trgm` indexes trigrams, so the two-character queries that dominate Chinese cannot use the index at all. tsvector needs a tokenizer Postgres lacks. Bigrams accelerate `LIKE '%…%'` and are vocabulary-independent — they find 阿㝹樓馱 that no lexicon knows. Builds from source against Homebrew PG 18.4 in under a minute. |
| `.credo.exs` from `gen.config`, patched | A hand-written config silently **replaced** the default check set (3 checks instead of 69). Never hand-roll it. |

## Open questions

- **BGE-M3 multi-vector in Nx** — port the two linear heads and drop the sidecar, or
  keep a bake-time sidecar? Decide in Phase 1 once dense works. *(Task #11)*
- **Tibetan `botok`** has no Elixir/Rust equivalent, so the sidecar survives until at
  least Phase 5 regardless — bake-time only.

## Rules that generalize

**Read this section before writing a new source pipeline.** Everything here was learned
from a specific bug, but each one states a rule that will apply again — most of them to
Phase 2's SAT normalizer, which is the next thing anyone writes.

1. **Any buffered element that can span a line boundary must be split at that
   boundary.** The line is the citable unit, not the element. This bug has now been
   fixed *twice* in the same file — `<lem>` spanning `<lb/>`, then `<note>` spanning
   `<lb/>` — and the second cost 10,590 uncitable printed lines. When adding an element
   that accumulates text, the question is not "does it usually fit on one line" but
   "what happens when it does not".
2. **Reproducibility is not fidelity.** A check that re-runs the pipeline and compares
   proves determinism only: content dropped on every run is absent from both sides and
   the check passes. Fidelity has to be measured against the *source*. Hence
   `mix pramana.integrity` alongside `mix pramana.verify`.
3. **A line is only droppable if nothing was printed on it.** Text, an interlinear note,
   a variant reading and a rare character are all printed content, and each needs an
   address.
4. **Never silently ignore an unknown option** — raise. A filter that is accepted and
   dropped produces results that look filtered and are not.
5. **Every declared filter must have a test proving it changes the result set.** Both
   filter bugs so far passed their existing tests.
6. **Filtering an ANN index post-hoc truncates silently.** Any query combining a vector
   ordering with a selective `WHERE` needs pgvector's iterative scan, or it returns too
   few rows with no error. Expect this to recur every time the corpus grows.
7. **Defects that only appear at scale will not appear in the proof run.** The quadratic
   ordinal, the ANN truncation, and the note-splitting loss were all invisible on one
   text or one division. Re-run the integrity and filter checks after every corpus
   growth, not just after code changes.
8. **A scripted patch that reports success may have done nothing.** This has now bitten
   five times. Always grep for the new text afterwards; never trust an unconditional
   "patched" message. Prefer a real edit over a Python string replace.

---

## One-off gotchas

Environment and tooling quirks. Each cost real time; recorded so they cost it only once.

- **`String.to_existing_atom/1` made a tool crash by load order.** The search tool's
  guard admitted `"phrase"`, then the conversion raised because `:phrase` enters the
  atom table only when `Pramana.Retrieval.Lexical` loads — which happens *later* in the
  same function. So `mode: "phrase"` as the **first** search in a fresh VM raised
  ArgumentError while the identical call after any hybrid search succeeded, and every
  test passed because something always ran hybrid first. The atom table is global
  mutable state; map string→atom explicitly instead. (Same family as the
  `function_exported?/3` entry below.)
- **A scripted patch that fails still lets the commit run — SIXTH occurrence.** The
  Phase 2 gate findings were written by a Python `str.replace`, the anchor did not match,
  the script raised, and `git commit` in the same `&&` chain still succeeded because the
  heredoc was a separate command. The commit message described a doc section that did not
  exist. **Use the Edit tool for docs.** If a script must be used, grep for the new text
  afterwards and treat a missing match as a failed step.
- **The variant-character problem was not where the task assumed.** #32 was written
  expecting the *corpus* to mix orthographic forms. It does not: CBETA writes 說 412,524
  times and 説 zero, 眾生 132,626 times and 众生 zero. The gap is between the **reader's
  keyboard and the corpus** — someone typing simplified or Japanese forms gets *zero*
  results, silently. Same fix, completely different framing, and worth measuring before
  building next time.
- **Unihan's `kSemanticVariant` is not an orthographic-variant field.** It means
  "characters sharing a meaning" and includes genuinely different words, so expanding a
  search across its 2,151 pairs would return passages using another word. Use
  `kSimplifiedVariant` / `kTraditionalVariant` / `kZVariant`. The cost is that 眞/真 is
  filed under the excluded field and is not expanded — documented, not overlooked.
- **A keyword match inside a negation classified 元曉 as Japanese.** Its glossary note
  reads *"Korean (Silla), **not Japanese**"*, and matching the bare word "Japanese"
  found it inside the phrase saying it is not. Two names were misclassified in the real
  import. Negations are now stripped before matching — but the general point is that a
  note saying what something is **not** is evidence about what it is not, and naive
  keyword matching reads it backwards. The source project made the identical mistake
  with the identical name before correcting it.
- **"A decision recorded is not a decision applied."** Borrowed verbatim from
  `scripts_check.py` in `~/dev/huangnianzu-translation`, which found a rule sitting in
  its glossary for *months* asserting a rendering that had already been swept out of
  the prose — invisible because the checker only inspected the translations, never the
  file every batch is told to treat as canonical. The same shape as this project's
  "every declared filter must actually filter", and worth checking for wherever a rule
  is written in one place and enforced in another.
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
- **A deep link into CBETA Online or SAT cannot be validated by fetching it.** Both are
  single-page apps that resolve content in the browser: a real path and complete
  nonsense both return HTTP 200 with a **byte-identical body** (1,018,537 bytes for
  SAT, either way). So `reader.verified` is permanently `false` and stated in the
  payload — a link checker here would be theatre. Formats are confirmed against
  indexed pages instead, and the CBETA linehead is cross-checked against CBETA's own
  TEI file naming for all 2,471 works.
- **Filtering an ANN index post-hoc silently returns too few rows, or none.** Postgres
  plans a filtered vector query as an HNSW index scan *followed by* the join and the
  provenance filter. HNSW yields only `ef_search` candidates (40 by default), so
  narrowing them to a division holding 3.4% of the corpus discards nearly all: a request
  for 10 results in 阿含部 returned **5**, tighter filters returned **none** — with the
  matching text present, embedded and correct. An empty result reads as *"the canon does
  not say this"* when the truth is *"the index never looked there"*, and it strikes
  exactly the provenance filters that are this project's differentiator. Fixed with
  pgvector 0.8's `hnsw.iterative_scan = relaxed_order` on filtered queries only (~3×
  latency, correct answers). **This only appears at scale** — it was invisible across the
  entire 10,138-chunk 阿含部 proof and surfaced within minutes of the corpus reaching
  299,317.
- **Storing the vectors cost more than computing them.** `Transfer.import/2` issues one
  UPDATE per row, each triggering incremental HNSW maintenance: 34 min on an L4 to embed
  299,317 chunks, **88 min** to write them. Task #37.
- **Reproducibility is not fidelity, and `verify` only proved the first.**
  `mix pramana.verify` re-normalizes from `raw/` and byte-compares, so content the
  pipeline drops on *every* run is absent from both sides and the check passes. 10,590
  printed lines, 473 gaiji and 266,547 characters of note text were unreachable in a
  corpus that verified clean. `mix pramana.integrity` counts the bake against the raw
  XML instead; run both at a gate.
- **A `<note>` spanning `<lb/>` was attributed to the line where it CLOSES**, leaving
  intermediate lines with no text and no note — so they looked blank and were dropped.
  Identical in shape to the `<lem>`-spans-`<lb/>` defect fixed earlier. **Any buffered
  element that can cross a line boundary must be split at that boundary**, because the
  line is the citable unit. Check this for every new element that accumulates text.
- **`verify --sample N` is per TEXT, not a corpus total** — `--sample 1000` over 2,471
  texts checks ~1.2M segments, not 1,000.
- **Oban retains finished jobs, so `bake_all`'s counter summed every previous run** and
  reported "works baked: 4941" for a 2,471-work corpus. A wrong number that looks
  plausible. Finished bake jobs are cleared at enqueue now.
- **Coverage `threshold` nests under `summary:`.** `test_coverage: [threshold: n]` is
  silently ignored and Mix keeps applying its own default of 90 — the config appears to
  work because `ignore_modules` at the same level *is* honoured.
- **Excluding a project's only module from coverage crashes `mix test --cover`**
  (`Enum.EmptyError` in `Enum.max/1`). Use `summary: [threshold: 0]` instead.
- **`reference` is a built-in Elixir type and cannot be redefined**, so `@type
  reference :: …` is a compile error, not a warning.
- **`use Anubis.Server.Component` GENERATES `name/0` from its options**, and unlike
  `uri`/`mime_type` it is **not** `defoverridable`. A hand-written `def name` in the
  module body compiles clean and loses to the option default (`nil` when `:uri` is also
  omitted), so the resource lists as a nameless entry. Pass `uri:` and `name:` as
  options. `description/0` is the opposite — optional, never generated, define it.
- **Registering an MCP component does not advertise it.** `capabilities: [:tools]` left
  both resources registered and unreachable: no client calls `resources/list`, so
  nothing errors and nothing is served. Capabilities and `component/1` are two lists
  that must agree.
- **`[env] MIX_ENV = "dev"` in `mise.toml` broke `mix test`.** `mix test` sets
  `MIX_ENV=test` only when it is *not already set*, so pinning it — even to the value
  that is already the default — ran the suite against the dev repo, which has no SQL
  sandbox pool. Removed; do not put `MIX_ENV` there.
- **`mise` shims are not on PATH in non-interactive shells.** `mise current` reported
  the pinned 1.20.3 while `elixir --version` was 1.19.5, so a session's builds and PLT
  drifted off the pinned toolchain without any warning. Prefix with `mise exec --`, and
  check `elixir --version` rather than `mise current`.
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
| #11 semantic (阿含部) | 284 | — | — | query 0.3–0.5 s; embed 1.29 chunks/s | 10,138 embedded |
| **#33 MCP resources + reader links** | **318** | — | — | hybrid search is now the MCP default | 10,138 embedded |
| **#13 Phase 1 gate** | **342** | — | verify --all + integrity green | **150 s / 2,471 works** | **4,740,246** |
| **#11 embeddings, full corpus** | **354** | — | — | embed 34 min / import 88 min | **299,317 chunks, 100% embedded** |
| **#15 provenance shape** | **377** | — | 3 origins in 3 labelled buckets | — | 299,317 chunks |
| **#17 Phase 2 gate** | **420** | — | licence filter now enforceable | import 88 → 38.7 min | 2,472 texts, 4,741,094 |
| **#36 work relations** | **444** | — | 89 commentary→root links | — | 2,472 texts |
| **#32 variant characters** | **465** | — | 众生 0 → 5 hits when expanded | — | 6,447 variant classes |
| **#34 glossary seed** | **483** | — | 10 rejected renderings, 1 unverified reading | — | 376 pinned terms |
| **#18a parallels** | **511** | — | sa1 → sn22.51 from curated data | import 29 s | 407,176 parallels, 3,064 anchors |
