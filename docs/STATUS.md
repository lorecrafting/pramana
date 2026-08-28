# Status

Living handoff document. **Update this at every checkpoint gate.** If you are a new
session with no context, read this first, then **`docs/PLAN.md`** (the living task list —
what is next and what is blocked), then `CLAUDE.md`, then `docs/ROADMAP.md`.

This file is the **evidence**; `PLAN.md` is the **intent**. Where they disagree, this one
is what was measured — and `PLAN.md` should be corrected to match.

---

## Where we are

**Phases 0, 1, 3 and 4 complete and gated** (tags `phase-0`, `phase-1`, `phase-4`).
**Phase 2: #15 and #16 done, #14 blocked on acquisition, gate (#17) run but deliberately
NOT tagged** — see the gate findings below. Phase 2 is the only unfinished phase behind
us, and it is waiting on an email, not on code.

**The whole Chinese canon is baked, verified, and embedded.** 2,471 works, **4,740,246
segments**, 90.6M characters, 150 s, zero failures. Both integrity checks
are green over every text: `mix pramana.verify --all` (byte-identical re-normalization
from `raw/`) and `mix pramana.integrity` (nothing printed in the source is missing from
the bake — a different question, see the rules section).

**The 嘉興大藏經 (CBETA J) is baked** (B): 285 works, 17.8M characters, zero failures,
provenance from the byline for 116 of them. Two works span volumes — JB271 (31+32) and
JB277 (32+33) — and were assembled before loading, which is the fix made for X's six
working on a collection it was not written against. The corpus is **17,004 texts and
11,519,879 segments**, and CBETA is now 3 collections of 26.

**The 卍續藏 (CBETA X) is baked, verified, and NOT embedded** (B). 1,230 works, 87.6M
characters, provenance from each work's own byline, pipeline **v4**. Six of those works
run across two printed volumes and are assembled before loading; the four defects that
ingest left behind — including a lockfile that had stopped describing the corpus — are
recorded below. Its 1,230 texts are reachable by the lexical arm and invisible to the
semantic one, which `embedding_coverage` now says out loud instead of reporting 100%.

**Semantic search covers 100% of the Taishō.** 299,317 chunks embedded with BGE-M3 on a
rented L4: 34 min, ~$0.45, 0 rejected vectors. (Written when the Taishō was the corpus;
X is baked and unchunked, and the coverage field now reports that rather than 100%.) Hybrid retrieval fuses lexical and
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

**The Pāli canon is in, and with it the first redistributable content** (#38): 8,442
works, 444,673 segments under SuttaCentral's own segment ids. The corpus is now 10,914
texts and 5,185,767 segments across two traditions, and 24,717 curated parallels resolve
at both ends, so SA 1 (Chinese) and SN 22.12 (Pāli) are quotable side by side.

**The Derge Kangyur is in** (#21): 1,195 Tibetan works, 461,302 lines, addressed by the
edition's own reference system — `pramana:derge.D:toh8@14.1b.1` is volume 14, folio 1
verso, line 1. The corpus is now **12,109 texts and 5,647,069 segments across three
traditions**. 75 works run across more than one volume and are assembled before loading,
because the loader replaces a text's segments rather than appending to them. Every text
re-derives from `raw/` byte-identically, and the whole edition reconciles against an
independent byte count to 69 bytes — volume 1's title page, which belongs to no Tōhoku
number. What is NOT here yet: work titles and the English translations. Both come from
84000, whose 396 published Kangyur translations are downloaded and not yet ingested.

**The Degé Tengyur is in** (#21): **3,380 works, 891,169 lines** across 213 volumes of
Indian commentarial literature — Nāgārjuna, Vasubandhu, Dharmakīrti, Candrakīrti — under
the same anchor grammar as the Kangyur: `pramana:derge-tengyur.D:toh4090@140.26b.1` is
where Vasubandhu's Abhidharmakośabhāṣya opens, volume 140, folio 26 recto, line 1. The
corpus is now **15,489 texts and 6,538,238 segments**. Every one of the 3,380 re-derives
from `raw/` byte-identically. The two canons are separate sources because they are
separately published prints with different licences and different editorial hands, and
`Pramana.Coverage.tibetan/0` counts both: the caveat that said the commentators were
absent is gone, and the only remaining coverage gap is Taishō 56–84.

**Semantic search covers three traditions** (#21). **617,038 vectors, 100% of the chunks
that exist — but 92.6% of the corpus's texts**, because CBETA X is baked and unchunked:
300,165 Literary Chinese, **215,354 Tibetan**, 44,719 Pāli, 55,135 English renderings and
1,665 parallel glosses. Tibetan is now the largest non-Chinese layer, and every Tengyur
vector is labelled `bo` rather than falling through to the `lzh` default.
The Tibetan has an English layer for the same reason the Pāli does — 84000's
renderings become `translation/en` vectors on Derge chunks — so an English question can
reach a Tibetan passage and still cite the Tibetan.

**84000's English is attached to the Tibetan** (#21): 30,653 folio-level renderings
across 472 works, and 478 of the 1,195 Kangyur works now carry titles in English,
Sanskrit, Tibetan and Wylie. `pramana:derge.D:toh113@51.100a.1-51.100a.7#tr:en/84000` is
a range anchor, because 84000 cites folios where we cite lines, and it resolves to the
seven Tibetan lines that folio holds.

**Translations are a pool, not a winner** (#39). 210,756 English renderings by 8
translators, keyed onto source anchors; 4,601 anchors carry more than one. Callers supply
a selection policy — prefer a tier, pin a translator, or `compare` for the whole pool —
and are always told how many renderings were withheld. A rendering has no top-level URN:
it is addressed as `<anchor>#tr:en/sujato`, so stripping the fragment always leaves a
citable source, and the guard rejects any non-human rendering quoted as scripture.
The reading layer (pinyin and friends) stores **only exceptions**, seeded from the
glossary: 元曉 → *Wŏnhyo*, 道隱 → *Dōin*, and 12 forms recorded as "not read the ordinary
way" with no reading invented for them.

**Semantic search is multi-vector** (#40). Vectors moved out of `chunks` into
`chunk_vectors`, so a chunk carries several: the passage itself, and the same span in a
translator's English. 342,535 vectors — 300,165 Chinese, 27,589 Pāli, 14,781 English
renderings. An English query can now reach a Pāli passage **through its rendering** while
the result still resolves to, and cites, the Pāli; every hit reports `matched_via`, so a
caller can tell a hit found through English from one found in the original. Chunk size is
per-script — 300 characters of Literary Chinese, 1,200 of romanised Pāli — because one
number silently under-chunks the alphabetic corpus. (The Pāli figure was later measured
against the tokenizer and corrected to 700; see #21 below.)

`compare_versions` and `define_from_canon` ship with it: the same passage beside its
renderings and curated parallels, and the canon's own definitional formulae (云何為X,
Katamañca X) so a definition can be quoted rather than composed.

The end-to-end path works: acquire → normalize → segment → chunk → embed → resolve →
verify, with an MCP server on top exposing nine tools and two resources. A model can
fetch an exact passage by URN, ask for translations alongside it, and the guard
byte-compares its quote.

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

**Now measured** (#19). `mix pramana.evals` scores a 200-case gold set whose expected
answers come from curated parallels, published translation anchors, the Taishō division
table and the canon's own definitional formulae — never from a model. Published in the
README: **overall 87.0%**, quote verification and rejection **100%**, provenance **100%**,
retrieval@10 **65.3%** (Chinese 97.1%, Pāli cross-lingual **37.5%**), and topical
**55.0%** — which #42 then split into the finding that matters, below.

The Pāli figure is the weak axis and is published as such. Two things it taught:
**semantic search was silently not running** for any caller that omitted `:serving`
(fixed — the running serving now decides), and **over half the Pāli gold cases quote text
that occurs in several places**, because this literature is formulaic by design.

### What Phase 5 still needs

The Kangyur is in, joined to its English, chunked and embedded. What the phase exit
("three-way retrieval with correct provenance") still wants:

- **The Tengyur has 2,675 of its 3,380 names, read out of the works themselves** — 2,629
  Tibetan titles and 46 Sanskrit-only; see below. The 705 that do not name themselves are
  left unnamed. No English titles
  exist for any of them, because 84000 has not translated the Tengyur.
- **Only a twentieth of the Kangyur is translated.** 84000 has published 385 of ~1,169
  Tōhoku numbers, so most works have no English. They now all have *titles* — see the
  catalogue section below — but a title is not a translation, and topical retrieval into
  Tibetan is 0% because of it.
- **Tibetan lexical search now windows syllables** — see the section below. The old
  grapheme windows were producing `་པ་`, which matches 89.6% of the corpus.
- **The embedder, not the corpus, now bounds Tibetan retrieval.** Measured below: BGE-M3's
  mean pairwise cosine for Tibetan is 0.9727 against 0.84 for Pāli, so ranking within
  Tibetan is weak by construction. Tibetan's own problem is RECALL, not order — half its
  gold never enters a 200-candidate pool — so a reranker cannot reach it and the
  fine-tuned embedder is the lever *for Tibetan*.

  **This bullet demoted the reranker for the whole system on that evidence, and that was
  wrong.** Pāli is 150 of the retrieval cases against Tibetan's 64, and Pāli fails the
  opposite way: its gold is retrieved 84% of the time and merely mis-ranked, so a
  reranker is worth **+44 cases** there against +9 in Tibetan. See *The reranker verdict
  was right about Tibetan and wrong about the system*. Rerank for Pāli, embed for
  Tibetan.
- **Tibetan word segmentation.** ~~`botok` in the Python sidecar is the intended
  syllable/particle segmenter.~~ **Withdrawn.** The lexical layer windows syllables on the
  tsheg the edition prints, which supersedes it for the same reason jieba was refused for
  Chinese — see *Tibetan n-grams were mostly one particle*. `botok` was never added; only
  the documentation kept it alive.
- **Mahāvyutpatti** proper is now loaded as text — Toh 4346, 1,554 lines from volume 204,
  ingested with the Tengyur — but as an untitled Tengyur work, not a parsed lexicon.
  The 84000
  half of that bullet is **done**: 865 three-way Skt–Tib–Chi anchors, below. BDRC metadata
  and IIIF image links are **done** too.

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

**2. The public corpus was EMPTY at this gate — and is not any more.** With the filter in
place, `redistributable_only: true` returned **0 hits across all 4.7M segments**: CBETA is
`nc`/not-redistributable and the Huang Nianzu commentary is `restricted`, which was
everything the corpus then held. The Phase 8 public demo had nothing it could serve.

**Superseded, and by a wide margin.** Phases 3 and 5 landed three public-domain sources,
and the filter now returns real results — measured 2026-08-24:

| | |
|---|---|
| redistributable texts | **13,017** (`sc` 8,442 · `derge-tengyur` 3,380 · `derge` 1,195) |
| redistributable segments | **1,797,144** — 27.5% of the corpus |
| embedded vectors over them | **315,208** |

A search under `redistributable_only: true` returns Pāli passages normally. So the Phase 8
public demo has a fully-baked, fully-embedded, two-tradition corpus available to it, and
the constraint recorded here — "nothing it could serve" — is no longer the blocker. What
remains restricted is the Chinese canon (CBETA `nc`) and the one local commentary.

**3. `credo` was not clean at the #16 commit**, which claimed it was — the
verify/integrity changes landed after the credo run. Run the checks *last*, not
mid-change.

**Architecture review** — all seven invariants hold. `pramana_web` touches `Repo` in 0
files; no MCP tool mutates; **0 corpus files tracked by git** (`raw/` and
`sources/local/*/text/` both ignored); no generated translation exists yet; the bake
reads only from pinned sources.

---


### Phase 3+4 gate findings (#20) — tagged `phase-4`

Everything passed, and the review found one real invariant drift.

| check | result |
|---|---|
| format / compile --warnings-as-errors / credo --strict | clean |
| dialyzer, whole umbrella | **0 errors, and no ignore file exists** — none has ever been needed |
| `mix deps.audit` | no known vulnerabilities |
| `mix hex.outdated` | 2 behind, both LiveView, both blocked by constraints and deliberately deferred to Phase 8 |
| `mix test --cover` | **662 tests**; 84.1% / 92.7% / 25% |
| `mix pramana.verify --all` | 10,914 texts, 5,185,767 segments, byte-identical, **242s** |
| `mix pramana.integrity` | every `<lb/>`, printed line and gaiji accounted for, **159s** |
| `mix pramana.evals` | 200 cases, 0 stale, **87.0%** overall |

**Invariant drift found and fixed: a pooled translation carried no hash.** The same
rendering returned `content_sha256` when resolved by URN and no hash at all when listed
in a `compare_versions` pool — so whether a caller could verify the text depended on
which call it happened to make. Invariant #1 says no unattributed text leaves the API;
`sha256` is now on both paths, with a test asserting they agree.

The other four audits were clean:

- **`pramana_web` touches the database in 0 files.** The boundary that drifted once, via
  an MCP resource building its own aggregation, has held since.
- **No domain logic in `priv/embed`.** The sidecar knows ids, text and hashes; it has
  never seen a URN.
- **No rendering is reachable as a top-level URN.** `pramana:sc.ms:mn1@1.1` resolves to
  the Pāli; only `…#tr:en/sujato` resolves to the English, and 0 text rows are
  addressable as renderings.
- **The bake is still reproducible from `sources.lock.json` alone** — which is what
  `verify --all` proves over all three traditions.

### The T56–84 catalogue is blocked too (#41)

The plan was to ingest the *catalogue* for Taishō 56–84 — work numbers, titles, authors —
since bibliographic facts are not the text and carry none of the licensing risk that
blocks #14. **There is no source for it.** Checked at this gate:

- SAT publishes no bulk metadata, API or downloadable index — only a browse interface.
- **CBETA's own catalogue stops at volume 55** as well, for the same reason its texts do.
- No openly-licensed machine-readable Taishō catalogue covering 56–84 was findable.

Two things were deliberately **not** done. Scraping SAT's browse interface, because we
have an access request pending with them and going around it is both discourteous and
pointless if they say yes. And hand-transcribing ~547 entries from a printed catalogue,
because a mistyped title is a fabricated bibliographic fact, which is the category of
error this project exists to refuse.

**What was delivered instead**, from data already held: `Pramana.Coverage` now reports
the gap in **work numbers** rather than only volumes, using the Taishō's own division
table —

    T2185–T2700  續經疏部 (Japanese sub-commentaries)  516 work numbers  japanese/commentary
    T2701–T2731  悉曇部 (Siddhaṃ script)                31 work numbers  japanese/treatise

"Volumes 56–84 are missing" requires a reader to already know which volumes those are.
"T2185–T2731, 547 Japanese-composed works, not held" is a statement they can act on, and
it needed no acquisition and no guessing.

### What the topical questions found (#42) — cross-lingual into Chinese is 0%

The #20 gate asked whether 37.5% was acceptable and answered: not yet a number worth
optimising, because the harness measured *pinpoint the anchor whose translation I quoted*
while users ask topical questions. #42 added 40 hand-written topical questions with
term-verified ground truth, and the answer turned out to be more specific than expected.

    topical / chinese-native   100.0%  (12/12)  mean rank 1.25
    topical / pali              62.5%  (10/16)  English query, has translation vectors
    topical / chinese            0.0%  (0/12)   English query, NO translation vectors

**Same twelve questions, same corpus; only the query language differs.** Chinese
retrieval is not broken — cross-lingual retrieval *into* Chinese is. Ask in Chinese and
the corpus answers perfectly at rank 1.25; ask the identical question in English and it
answers not at all.

This is a missing-layer problem rather than a tuning problem, and the contrast proves it:
Phase 3 gave Pāli chunks an English rendering to match against, which is exactly why the
English→Pāli row works. The Chinese canon has no English translation in this corpus, so
an English query has to cross inside BGE-M3's own multilingual space —
`Pramana.Retrieval.Semantic` has carried the admission that this was unproven on Literary
Chinese since Phase 1. It is now measured, and it does not work.

So the highest-value retrieval work is **an English gloss layer for Chinese chunks**
(#43), ahead of any parameter tuning. The two earlier hypotheses — chunk granularity and
the 320-token truncation — are demoted to secondary; they may not be the binding
constraint at all.

**Two errors in the previously published table, corrected here.** The README's
"↳ Chinese 98.7% (75 cases)" under *Retrieval* was a by-tradition row that silently
included the 40 provenance cases, so its sub-rows did not sum to their parent; the real
figure is 97.1% over 35 Chinese retrieval cases. And the 100%/0% split above was
invisible in both margins of the report — it only appeared once case type was crossed
with tradition, which the scorecard now always does.

### The free gloss experiment (#43, stage A) — and why stage B should not proceed as planned

Before spending tokens, invariant #5 says use the deterministic data. We hold 24,717
curated Chinese↔Pāli parallels and 210,756 human English renderings of the Pāli, which
covers **1,616 of 10,138 阿含部 chunks** with English a person actually wrote. Attached as
a fourth vector kind — `parallel_gloss`, never `translation`, because it renders a
*parallel text* and not the passage — for **zero token cost** and about a cent of GPU.

    topical / chinese         0.0%  ->  33.3%    English query into the Chinese canon
    topical / chinese-native  100%  ->  100%     rank improved 1.25 -> 1.08
    topical / pali           62.5%  ->  50.0%    regressed
    topical overall          55.0%  ->  60.0%

**A third of the Chinese cross-lingual failures were fixed for free.** The English layer
was the missing piece, as #42 predicted.

**The Pāli drop is mostly a gold-set artifact, and the residue is real interference.**
Inspected directly: "What are the four noble truths?" now returns T0099 — the Saṁyukta
Āgama, the Chinese parallel of exactly the right Pāli material — interleaved with the
Pāli. Those Chinese hits are *correct answers to the question*. The case scores them as
misses only because it demands a Pāli term, so the system got better and the metric
punished it.

But the mechanism underneath is real: **English vectors from different traditions compete
in one space.** 1,665 gloss vectors were enough to displace Pāli answers. Stage B would
add ~300,000 of them against 14,781 Pāli translation vectors — a 20:1 imbalance that
would likely bury the Pāli entirely.

So **stage B does not proceed as scoped.** Two things must come first:

1. **A tradition-agnostic topical score.** A user asking "what are the four noble truths"
   is well served by either canon; the gold set currently measures per-tradition
   reachability and calls the other tradition wrong. Both numbers are worth having, but
   they must be labelled as the different questions they are.
2. **A balancing story for retrieval.** Whether that is per-tradition quotas, a diversity
   term in fusion, or simply surfacing both — undecided, and it needs measurement rather
   than a guess.

Cost estimate for stage B, kept for when it is unblocked: 10,138 阿含部 chunks, 2,896,481
Chinese characters, ~3.0M input and ~1.1M output tokens, **~$9 on Haiku, ~$26 on Sonnet**;
the whole canon is 29.6x that (~$260 / ~$770). Embedding is negligible beside generation.
The char-to-token ratio for Literary Chinese is an assumption that should be measured on a
sample before committing.

### The plain HNSW scan was returning worse answers, not wrong ones (#43)

Found while fixing a bug I introduced. Making `vector_kinds` default to a list meant every
query carried a `WHERE kind IN (...)`, but `filtered?/1` did not know about it — so
searches took the plain index scan and post-filtered, the exact truncation rule 6 warns
about. Pāli pinpoint retrieval fell 37.5% -> 30.0%.

The fix was to route **every** query through the iterative scan, which removed the
`@filter_keys` list entirely: there is no longer a set of "options that narrow the
candidates" to keep in step with `apply_filters/2`, so the thing that had to be remembered
is gone.

And it turned out the plain scan had been costing recall all along:

    overall            81.7%  ->  83.3%
    retrieval / pali   37.5%  ->  42.5%
    topical / pali     62.5%  ->  75.0%

The old comment said "unfiltered: the plain index scan is correct and ~3x faster, so leave
it alone". It was right about correctness and wrong about quality — with `ef_search` at
its default the plain scan explores less of the graph and returns *worse* neighbours, not
invalid ones. Nothing failed; the answers were just further down. Cost of the change: 252s
-> 890s for 240 eval cases, about 3.5x.

**The general lesson: a fast path justified by "there is no filter here" is still a
quality decision, and quality decisions need a measurement.** This one sat unmeasured
from Phase 1 until an eval harness existed to catch it.

### Bake cost review (#20)

What a full rebuild costs now, with three traditions and 5.19M segments:

| stage | time |
|---|---|
| CBETA normalize + segment (2,471 works) | 150 s |
| Pāli ingest (8,442 works) | 53 s |
| Translations into the pool (4,996 files) | ~60 s |
| Parallels import (407,176 relations) | 29 s |
| Chunking, whole corpus | 84 s |
| Vector rows (source + translation) | 70 s |
| **Embedding, 342,535 vectors on an L4** | **~40 min, ~$0.50** |
| Vector import (no index present) | 29 s |
| HNSW build, 342,535 vectors @ 6 GB | 395 s |
| `verify --all` | 242 s |
| `integrity` | 159 s |
| **Total wall clock** | **~55 min**, of which 40 is GPU |

Database: **26 GB**.

**Token cost of a bake: zero.** Nothing in the pipeline calls a language model —
normalization, segmentation, chunking, alignment and provenance are all deterministic,
and the only model involved computes embeddings. That is not frugality, it is the
architecture: a bake whose contents depended on a model's output could not be
reproduced from `sources.lock.json`, and `bake_id` would be a fiction.

The first LLM tokens enter at Phase 7, and they enter as a **layer** — generated
translations in the pool, marked, never citable as source.

### The apparatus shipped, and witness ids are not what they look like (#45)

`compare_witnesses` now answers "how does this line differ across the witnesses" over the
**572,701 segments** that carry an apparatus — 消 → 銷 in 【宋】【元】【明】, 至 → 志 in
【宋】. The data had been captured since Phase 0 and reachable only as an opaque blob.

**The attribution was the hard part, and assuming would have been badly wrong.** A
`<rdg wit="#wit1">` names a witness declared in *that file's own header*. Measured across
all 2,471 CBETA files:

    wit1   38 distinct meanings — 宋 in 832 files, 明 in 375, 甲 in 322, 原 in 149
    wit2   33 distinct meanings
    only 4 of 23 ids mean one thing everywhere

A global lookup table — the obvious implementation, and the one a quick sample of four
files would have supported, since `wit1` was 宋 in all four — would have reported Ming
variants as Song ones in roughly a thousand works, in the tradition's own sigla, with
nothing about the output looking wrong.

So each text carries its own map, imported by `mix pramana.witnesses.import` from its own
pinned file. That task deliberately does **not** re-bake: re-normalizing would delete and
rebuild segments, cascading to 344,200 embeddings and 40 minutes of GPU, so it updates
`texts.meta` in place and stays checkable against `raw/`.

Two distinctions kept that a simpler shape would have lost: an unresolvable id returns
`witness: nil` with the raw id preserved rather than a guess, and an **omission** ("this
witness has nothing here") stays distinct from a **substitution** ("reads something
else") — different claims about a manuscript.

### Tradition balancing: the measurement is the deliverable, round-robin is not (#44)

Two halves. The measurement half worked and changes how this project reports itself; the
retrieval half was tried and **rejected on evidence**.

**Measurement.** Topical cases now carry a `topic` slug linking the same question asked of
different canons, so two genuinely different questions can both be answered:

    per-tradition reachability   "can an English query reach the PĀLI witness of this?"
    answered from any tradition  "did the reader get a good answer from anywhere?"

The second is what a reader cares about, and it was not computable before. It is
**81.8% (9 of 11 topics)** at the shipped default — against per-tradition figures of
0% (Chinese) and 68.8% (Pāli). Reporting only the per-tradition numbers understated the
system badly, because answering correctly from the other canon counted as a failure.

**Retrieval.** Round-robin interleaving by tradition was implemented and measured:

    default                   chinese 0.0%   pali 68.8%   answered 81.8%
    + parallel glosses        chinese 33.3%  pali 50.0%   —
    + glosses + balancing     chinese 33.3%  pali 50.0%   answered 63.6%

It moved neither tradition's rate and made the user-facing number **worse**. Pāli mean
rank went 3.18 -> 5.13: interleaving inserts the other tradition between correct answers,
so a hit at rank 3 lands at rank 5 and some fall out of the top ten entirely. Guaranteeing
representation costs ranking, and for a question whose answer genuinely lives in one canon
that is pure loss.

The option survives (`balance: :tradition`, default off) because it is measured and might
suit a caller who explicitly wants breadth. It is not the mechanism.

**What this actually resolves.** The blocking worry was "we cannot add English layers for
another tradition without silently hurting the ones we have". True, and the fix is not a
ranking trick:

- **the layers stay opt-in**, so nothing taxes the default path
- **the caller says what it wants** — a reader after the Chinese witness asks for it, and
  `compare_versions` already shows several traditions side by side rather than making them
  fight for ten slots
- **`answered from any tradition` is the number to optimise**, and it now exists

On that basis #21 (Tibetan) and #26 (translation engine) are unblocked, with a documented
constraint rather than a solved problem: any new English layer must be measured against
answered-from-any-tradition before it becomes a default, and the parallel-gloss layer is
evidence that "it helps one tradition" is not sufficient.

### The eval gate was going to cry wolf (#44)

Two runs of an identical build differed by **one case** in each of `retrieval`
(68.0% / 66.7%) and `topical` (60.0% / 57.5%). Nothing between them touched retrieval.
Approximate nearest-neighbour search with `relaxed_order` simply does not return a fixed
ordering, and at 40-75 cases per type one flip is 1.3-2.5 percentage points.

The gate compared rates and failed on any decrease, so it would have reported a
regression on roughly every other clean run. A benchmark gate that cries wolf gets
ignored, and an ignored gate is worse than none — so the threshold is now in **cases**,
not percentage points: one may flip, two is real.

The cost is that a genuine one-case improvement will not ratchet. That is the right trade:
a gate exists to catch a system getting worse.

**The README claimed "pass rates have been stable"** across runs. That was wrong and is
corrected there. It was written after two runs that happened to agree.

### The Derge normalizer (#21) — a third of the edition, silently

103 volume files in, 1,196 Tōhoku works out: **461,414 citable lines, 77.5M characters
of Tibetan**, in 15 seconds. The citation anchor comes straight from the markup, as it
should — `data-orig-n="1b"` is the folio and `<milestone unit="line" n="3"/>` the line —
so a passage is addressed `1b.3`, which is how Tibetanists cite.

**The first version dropped 146,962 lines and looked fine.** A work is delimited by a
`<milestone unit="text" toh="N"/>` marker, and I treated text before the first marker as
front matter, which is true of volume 1 and false everywhere else: the Vinaya runs to
volume 13 and the Prajñāpāramitā across a dozen more, and **26 of the 103 files contain
no marker at all**. Their entire contents vanished. Nothing errored, the work count was
plausible, and the only visible symptom was a mean line length of 169.7 characters where
a Derge line is nearer 80 — two lines' worth of text under one anchor.

The number that exposed it was one I already had: 460,539 line milestones counted
straight out of the XML, against 313,577 lines emitted. **A count taken from the source
before parsing is worth more than any number the parser reports about itself**, because
the parser's numbers are all downstream of the same wrong assumption.

`normalize_file/2` now takes the work in progress and returns the work still open, and
volumes must be fed in order. 461,414 lines, matching the milestone count.

Three more things the edition itself made necessary:

- **Folio numbers restart at `1a` in every volume**, so the anchor is
  `volume.folio.line` — `2.5b.3`. Without the volume, a work spanning one addresses two
  different lines as `1b.1`, and 26 works span volumes.
- **Volume 103 is the dkar chag**, the catalogue. Eight `toh` markers sit there on titles
  in a running list — Toh 539 is `ཕྱག་དང་།`, "homage, and" — and splitting on them yields
  eight works a few words long that collide with the real text. Median characters between
  markers: **24 in volume 103, 7,804 everywhere else.** It is normalized as one work,
  which it genuinely is.
- **Three anchors in 461,414 lines are printed twice.** Dropping the second loses text;
  merging makes two passages one. They keep the printed anchor with `+2` appended, which
  is visibly not a folio reference — a reader who sees it learns the edition is ambiguous
  there rather than receiving a citation that looks clean and resolves wrongly.

### The Derge ingest (#21) — the edition is the unit, and the header is not the book

**The Kangyur is in: 1,195 works, 461,302 lines, 12,109 texts and 5,647,069 segments
across three traditions.** `mix pramana.derge.ingest` walks the 103 volumes in printed
order in 4m35s; `mix pramana.verify --source derge` re-derives every one of the 1,195
texts from `raw/` byte-identically in 75s. URNs read `pramana:derge.D:toh8@14.1b.1`.

**The numbers in the section above were wrong, and this section's are checked.** The
normalizer's own report said 1,196 works and 461,414 lines. Ingest says 1,195 and
461,302, and the difference is not a regression — it is 102 lines of Esukhia's
distributor note (see below) plus one work that only ever existed as a double count.

Four things this stage settled:

- **A volume is not the unit of loading, and the loader will not tell you.**
  `Loader.load/2` is idempotent by replacing a text's segments, so a work loaded once per
  volume keeps its **last** volume and silently discards the rest — twelve volumes of
  Vinaya, in a text that reports a plausible length and resolves every URN it contains.
  Works are assembled across volumes in `Derge.Edition` and loaded once. 75 of the 1,195
  span more than one volume; Toh 8 spans thirteen.
- **`<teiHeader>` was being read as scripture.** Every volume's `<publicationStmt>`
  carries a 416-byte distributor note, and the normalizer buffered all character data
  regardless of where it sat. In a volume that opens with a work already running — 102 of
  the 103 — that note flushed into the work as its first line, with a URN that resolves.
  Nothing errored: it is text, in a text, with an anchor. The only tell was the anchor
  itself, `2..`, because no folio had been read when it was emitted.
- **What found it was a count that shares none of the parser's assumptions.** Not line
  counts — those agreed. `Derge.Audit` adds up the non-whitespace bytes of character data
  inside `<text>` and knows nothing about folios, markers or works: **290,863,399 in the
  edition against 290,863,330 in the bake, and the 69-byte difference is volume 1's title
  page**, which belongs to no Tōhoku number and is dropped on purpose. That reconciliation
  now runs in `mix pramana.integrity`, per volume, and the rule it enforces is that **only
  the first volume may drop anything** — a later volume dropping its preamble is the exact
  shape of the 146,962-line bug.
- **Four leaves in the edition are inserted rather than numbered** and are labelled
  `33xa`, `93xb`, `354xa`, `355xb`. 65,975 folios take the regular form and exactly 8 do
  not, which is the kind of thing worth counting before writing the pattern that parses it.

Provenance is `indic` / `root` / **`probable`**, not `certain`: the Kangyur's claim to
Indic origin is a claim about where the collection places a text, and it is wrong for a
few (the *mdzangs blun* was assembled from Chinese). Per-work correction is what the 84000
catalogue join is for. The dkar chag is loaded as what it is — `tibetan` / `catalogue` /
`certain`. Titles are absent by design: this etext titles volumes, not works, and 84000
publishes a title for every Toh number in four languages.

### The 84000 join (#21) — 30,653 English folios anchored to Tibetan lines

84000's published Kangyur translations are in, keyed onto the Derge text they translate:
**30,653 renderings across 472 works**, and **478 of the 1,195 Tibetan works now have
titles** in English, Sanskrit, Tibetan and Wylie. An anchor reads
`pramana:derge.D:toh113@51.100a.1-51.100a.7#tr:en/84000`, and it resolves: the English
"His subtle body is adorned by the thirty-two signs" comes back beside
`སུམ་ཅུ་རྩ་གཉིས་མཚན་རྣམས་ཀྱིས། །ཕྲ་བའི་སྐུ་ནི་ལེགས་པར་བརྒྱན།`, line for line.

**The anchor is a range because the two editions cite at different grains.** Ours are
lines, 84000's are folios, so a folio's English renders about seven of our lines and is
stored against the range of exactly those. Anchoring it to the folio's first line would
have been a smaller change and a false claim.

Four things this cost, all of them the same lesson — *the file describes its own location
three times and the three disagree*:

- **`<biblScope>` is prose, `<location>` is arithmetic, and the folio reference in the
  body is the folio.** For Toh 883 the prose says volume 100, the page arithmetic says
  folio 122a, and the reference says 123a. Our Derge etext has it at volume 101, folio
  123a — so the volume comes from `<location>` and the folio from the reference, and
  nothing is computed. Only checking all three against the Tibetan we already had could
  have told us that.
- **A partial match is the dangerous case, not a total mismatch.** 84000 numbers Toh 11's
  folios from the work's own beginning in its second volume — `F.92.b` where the Degé
  prints `1a` — and **428 of those 610 numbers exist in that volume of that work**. They
  anchor. They resolve, they byte-verify, and they attach English to a passage it does
  not translate. So a volume's spans are accepted or refused **together**, on a 95%
  threshold: 490 of the 503 volume-groups land completely, and the rest divide sharply
  into 99.4%/99.6% (84000 citing one folio past the end of ours) and 70%/67%/0%.
- **One translation can render two places in the canon at once.** A dhāraṇī printed twice
  in the Kangyur is translated once, with both editions' folio boundaries marked in one
  interleaved flow — `F.1.b`, `F.123.a`, `F.2.a`, `F.123.b`. Each `<bibl>` gets the whole
  translation cut at its own boundaries, which is why 385 files produced 478 work-level
  attachments.
- **A mirror keeps renamed files.** 11 Tōhoku numbers arrived twice because 84000 renames
  a file when a translation is revised (`the_gandhavyuha_sutra` → `the_stem_array`), and
  7 of those pairs differ in the text. The `<edition>` version decides, compared as
  numbers: `v 1.0.30` is newer than `v 1.0.7` and older than `v 1.1.1`, and string
  ordering gets both comparisons wrong.

Not stored, and counted rather than guessed at: 3 folio references that fit no location,
3 folios absent from our text, 7 refused volume groups, and 4 Tōhoku numbers that are
Tengyur texts this corpus does not hold.

**A folio-anchored rendering is reachable from a line.** `Translations.covering/2` finds
renderings whose anchor *contains* a span, and `select/2` falls back to it when nothing
matches exactly — so asking for `@51.100a.3` returns the folio's English, labelled
`covers: :containing_range` and carrying its own wider `anchor_urn`. Containment is by
**segment ordinal**, recorded on the rendering at ingest, because whether `51.100a.3` lies
inside `51.100a.1-51.100a.7` is a fact about Derge folios while ordinals mean the same
thing in every source. The exact-match path is unchanged: a Pāli rendering anchored to
its own segment id still matches exactly and carries no `covers`.

### Chunk sizes are a tokenizer question (#21) — and the Pāli was answering it wrong

Chunking the Tibetan meant choosing a chunk size for it, and the note in the last session
said to measure rather than guess. Measuring found that **the Pāli size had been wrong
since #40, and invisibly so**.

The embedder runs BGE-M3 at `max_length=320` with `truncation=True`. A chunk over that is
embedded **from its opening only**: the text stays whole in the database, the vector
silently describes a prefix, and every count in the system still agrees. Measured over
real chunks of each script with the actual tokenizer:

| script | chars | tok p50 | tok p95 | over 320 |
|---|---|---|---|---|
| Literary Chinese | 300 | 277 | 291 | 0.0% |
| Pāli | **1,200** | 461 | 535 | **76.2%** |
| Pāli | 700 | 258 | 307 | 0.5% |
| Tibetan | 1,200 | 206 | 266 | 0.3% |
| Tibetan | 1,400 | 242 | 309 | 3.2% |

**Three quarters of the Pāli vectors described about the first two thirds of their
chunk.** Pāli recall@10 is 37.5% against Chinese at 98.7% (#19), and this is a plausible
mechanical contributor — the vectors were built from truncated text while the eval scored
against the whole. Sizes are now the largest whose 95th percentile fits the window: Pāli
700, Tibetan 1,200. Tibetan costs 0.151 tokens per character against Pāli's 0.425, which
is why the same window holds so much more of it.

**Re-chunking the Pāli then hit a defect that had been there all along.** SuttaCentral
numbers a merged section `53-55.1`, so the hyphen is inside the locator as well as being
the character this grammar joins two locators with. `URN.parse/1` split it, and the chunk
builder — which built its range URN from *parsed* locators — emitted `mn12@53-53`: an
address naming a segment that does not exist, identical for every chunk in the section,
and a unique-index violation the moment two landed in one insert. **412 chunks in the
corpus were addressed that way and none of them resolved.** Range URNs are now built from
the raw locator text, and `Pramana.Corpus` resolves a range it cannot split by looking the
URN up as a stored chunk — identity answering what arithmetic cannot.

Two more things the re-chunk forced:

- **`mix pramana.chunk --source`.** `--force` discards the vectors of every text it
  touches, and the corpus holds 299,317 Chinese vectors that cost GPU time. "Re-chunk the
  Pāli" must be sayable without putting those in the blast radius; narrowing a destructive
  operation is not a convenience. (Found the hard way: a `--force` run without it had
  already discarded 527 Pāli vectors before failing.)
- **Translation vectors could not see a range-anchored rendering.** The builder joined
  `translations.anchor_urn` to `segments.urn` by equality, and all 30,653 84000 renderings
  are anchored to folio ranges — so Tibetan would have had no English route into it at
  all. The join now also accepts renderings carrying `ordinal_start`/`ordinal_end`, and
  coverage is counted over the chunk's own segments so two overlapping folios cannot claim
  more of it than it has.

### What the Tibetan measured (#21) — and the two hypotheses it refuted

The Kangyur is embedded and the evals now cover three traditions. **The gold set could
not see Tibetan at all until it was fixed**, and that is the finding worth keeping:

- `mix pramana.evals.derive` joined `translations.anchor_urn` to `segments.urn` by
  equality — the **third** place that join has been wrong — so it found none of the
  30,653 range-anchored 84000 renderings and generated zero Tibetan cases, while
  hardcoding `tradition: "pali"` on everything it did generate. Tibetan would have been
  reported as *not measured* rather than measured and weak, which is the more dangerous
  of the two.
- Cases are now sampled **per tradition** (20 Pāli, 20 Tibetan, 35 Chinese), the tradition
  comes from the data, and a case is admitted only if its anchor resolves.
- Rule 18 arrived from the other side. Where the Pāli's SOURCE repeats verbatim, the
  Tibetan's TRANSLATION does: "Homage to all buddhas and bodhisattvas. Thus did I hear at
  one time." is the published English of **102 separate anchors**, over Tibetan that is not
  byte-identical because each names its own sūtra. Identical renderings now count as one
  equivalence class.
- Nine Tibetan topical cases, with the terms adjudicated by the corpus rather than
  asserted: of twelve proposed, three were rejected as too common to measure
  (ཤེས་རབ་ཀྱི་ཕ་རོལ་ཏུ་ཕྱིན་པ at 19,099 segments, སྟོང་པ་ཉིད at 20,500,
  མྱ་ངན་ལས་འདས་པ at 4,242) and **none as absent**.

**The numbers**, 249 cases, overall 79.5% (the run written as the new baseline; a
second run of the same build put topical/pali at 62.5%, which is the one-case wobble the
README already documents):

| | | |
|---|---|---|
| retrieval / chinese | 97.1% (34/35) | unchanged |
| retrieval / pali | 55.0% (11/20) | new sample |
| **retrieval / tibetan** | **35.0% (7/20)** | first measurement |
| topical / chinese-native | 100% (12/12) | unchanged |
| topical / pali | 56.3% (9/16) | was 75% |
| topical / chinese | 0.0% (0/12) | unchanged — no English layer |
| **topical / tibetan** | **0.0% (0/9)** | first measurement |
| quote verify / reject / provenance / absence | 100% | unchanged |

**Topical Tibetan is 0% for a structural reason, not a retrieval one.** 84000 has
published 385 of ~1,169 Tōhoku numbers, so **95% of the Kangyur has no English vector at
all** and an English topical question can only reach the twentieth of it that does. It is
the same shape as the Chinese 0%, with a different cause: Chinese has no English layer,
Tibetan has one over a twentieth of the text.

**Two hypotheses for the Pāli topical drop, both refuted by measurement.**

1. *The Tibetan English layer displaces Pāli.* This is what #44 predicted and what the
   first English demonstration looked like. Measured over the 16 topical/pali queries:
   **Tibetan occupies 1 of 160 result slots.** It is not displacing anything. (The same
   experiment confirms the English layer is what makes English→Pāli work at all: with
   `vector_kinds: ["source"]` the rate collapses to 1/16.)
2. *The smaller Pāli chunk returns a window too narrow to contain the term.* Scoring
   containment over the chunk **± 3 segments** — the passage a reader would actually see —
   gives **10/16 either way**. The retriever is not landing near the term and being cut
   off; it is not landing there.

What remains is the chunk size itself: 700 characters covers less ground than 1,200, and a
broad topical question is answered by breadth. That is a real trade — **anchor-precise
retrieval up, topical recall down** — and it is not an argument for reverting, because
1,200 was never honestly embedded: 76% of those vectors described two thirds of their
chunk. The honest alternative is to raise the embedder's 320-token limit for the alphabetic
scripts and keep the wider window, paying for it in GPU time. Untested.

**Under #44's rule the Tibetan layer stays a default**: it was measured against
answered-from-any-tradition before shipping, and the drop there (9/11 → 8/11 topics) is
attributable to the Pāli chunk change, not to Tibetan taking slots.

### The Kangyur has its names (#21) — and the metadata is CC0 where the text is not

**1,189 of 1,195 Kangyur works now carry a title**, up from 478, in English, Sanskrit and
Tibetan, with a Wylie transliteration and a BDRC identifier. From 84000's RDF export:
1,254 records covering 1,160 Tōhoku numbers, translated or not.

**The licence is not the one on the repository.** `data-rdf`'s README says CC BY-NC-ND —
the terms for the translations — while every record's own `adm:license` says `LicenseCC0`
with the label "Metadata related to the translations by 84000, provided under the CC0
License". Both are true of different things: the prose of a translation is restricted, the
fact that Toh 113 is called *Saddharmapuṇḍarīka* is not. Recorded as its own source,
`84000-rdf`, because it is its own publication — the same rule bilara-data forced, where
the repository claimed CC0 and the publication file said Public Domain Mark and CC BY-SA.
**This is the first CC0 content in the corpus.**

**Four descriptions of one text, each holding a different title.** A record describes the
abstract Indic work, the Tibetan translation, the Degé printing of it, and 84000's
English — so the Tibetan title is taken from the Degé printing, which is the edition this
corpus holds, and the Sanskrit from the Indic work. Reading any `skos:prefLabel` with the
right language tag would have attributed the printing's title to the Sanskrit original,
and a translator's name — which is also a `prefLabel` — to the sūtra.

A published title is never overwritten: where a translation exists, its own title page is
the better authority and was already stored, so the catalogue fills only what was empty
and records which source each title came from.

**The Wylie is computed, and checking it against 84000's own found two bugs.** The RDF
carries no transliteration, so `Pramana.Readings.Wylie` produces one from the Tibetan and
it is stored under a separate key — a claim by this code must be distinguishable from a
claim by the editors. 476 works have both, which makes an independent check possible:

    before   452 / 476 agree   (94.9%)
    after    454 / 476 agree   (95.4%)

Two real defects, both in constructions that are everywhere in Tibetan:

- **`བའི` came out `b'i`, not `ba'i`.** The rule "an explicit vowel sits on the root" is
  right for བདེ → `bde` and wrong for an *a-chung* suffix carrying the genitive: the བ
  keeps its implicit *a* and the འ takes the ི. That is most of the particles in the
  language — པའི, མའི, པའོ — and it was wrong in every one.
- **`ཤཱཀྱ` came out `shAkya` only after** recognising that a non-root stack carrying a
  SUBJOINED letter is a syllable of its own rather than a suffix; a suffix is always a
  single letter.

The 22 remaining differences are characterised rather than chased: about half are
genuinely different titles (the catalogue and the translation's title page name the text
differently, e.g. `spyan ras gzigs yum` against `spyan ras gzigs dbang phyug gi yum`), one
is 84000 storing Tibetan script in a Wylie field, and the rest are Sanskrit conjunct
notation (`kul+le` against `kulle`) and the `dags`/`dgas` prefix-root ambiguity, which
cannot be resolved without a lexicon. Six works stay untitled: five sub-parts of Toh 845
and one lettered variant, where the etext divides more finely than the catalogue.

Each record also carries the BDRC id of the Degé printing (`MW22084_0113`) — the handle a
IIIF manifest is addressed by, which is the catalogue half of the Phase 5 BDRC item, with
no OCR involved.

### The woodblock page, linked (#21) — and why the arithmetic had to go

A Derge passage now comes back with the photograph of the leaf it was printed on.
**64,828 of the corpus's 65,778 folio anchors — 98.6% — resolve to a BDRC page image**,
served over IIIF, attributed, and never copied or read. `get_passage` carries it as
`page_image`; a folio with no scan gets nothing rather than a neighbour.

**The mapping is BDRC's, and reading it replaced an inference that looked right.** The
obvious construction is arithmetic: two cataloguing cards, then folio *n* recto at leaf-side
2n−1, image name `<group><NNNN>.jpg`. It was built that way first, and the audit that
checked it against all 103 volumes said: 74 fit, **29 claim more leaf-sides than the scan
contains**. Volume 7 settles it — the etext prints folios 1a–287b, BDRC's canvas labels run
1a–287b, and there are **536 canvases where contiguous sides would need 574**. Sides are
missing from the middle of the scan, and nothing computable from a filename could know
which. A single omitted leaf silently shifts every page after it, so the reader is shown a
leaf that is *almost* the right one — the failure this project exists to prevent, arriving
as a photograph.

BDRC publishes the answer: every canvas is labelled with its folio (`1a`, `img. 3`, `1na/`,
`par grangs _3`). So the manifests are fetched and the labels read, which is invariant #2
applied to pictures — adopt the edition's own reference system, never invent one. The
proof it mattered is one line: `51.100a` is image **202**, and the arithmetic said 201.

Also settled here:

- **The volume-to-image-group mapping is derived, not assumed.** The group is in the
  etext's own directory name (`UT4CZ5369-I1KG9127`) and BDRC's record for that group
  confirms it says *"Volume 1 of bka' 'gyur (sde dge)"*. The ids do run consecutively from
  9127, and that is a coincidence of issue order rather than a fact to rely on.
- **The Degé restarts foliation inside a volume.** Volume 31 holds two texts numbered
  1–206 and 1–91, so `31.1b` names two different leaves and is disambiguated only by the
  work in the URN. Two volumes are like this. It does not affect the image lookup now that
  labels are read rather than counted, but it means a bare "D vol 31, f. 1b" is ambiguous
  in this edition.
- **The licence is the scan's, not the metadata's.** What is stored is BDRC's manifest —
  what exists and what it is called. The images stay at BDRC, are linked with attribution,
  and are never redistributed or read.

### The translators' own glossaries (#21) — Skt–Tib–Chi anchors, attested

Phase 5's last bullet asked for Mahāvyutpatti and 84000 glossary entries as Skt–Tib–Chi
anchors. The 84000 half was already in `raw/`: every translation ships with the
translator's glossary, and there are **58,820 entries across the published Kangyur**.

**56,382 stored: 41,253 with Sanskrit, 55,807 with Tibetan, 1,105 with Chinese, 41,480
with a definition — 16,741 distinct Sanskrit terms and 25,524 Tibetan.** Of those, **865
carry all three languages**: `dharma` / `ཆོས།` / `法`, `bodhisattva` / `བྱང་ཆུབ་སེམས་དཔའ།` /
`菩薩摩訶薩`, made by the people who did the translating rather than assembled by matching
strings.

**They work as anchors.** Sampled 60 of the three-way entries against the corpus itself:
the Chinese term occurs in the Taishō for 59 and the Tibetan in the Kangyur for 60 — **59
reachable in both canons at once**. The miss was a proper name the Chinese transliterates
differently, which is the expected shape of the failure.

**Most of the Sanskrit is a reconstruction, and the table says so per term.** 84000 marks
each form: Tibetan `attestedSource` 23,252, Sanskrit `sourceUnspecified` 22,442, Sanskrit
`attestedSource` only 575 in the sampled files (2,783 across the whole ingest). `yūpa`
beside `མཆོད་སྡོང་།` is a scholar's inference about a lost Indic original, not a quotation
from one, and storing the two identically would flatten that into a claim the edition does
not make — the same failure `composition_origin` prevents one layer up. `attested_only:
true` narrows a query to what a witness says, and the attestation is on every row returned
so a caller who never asks still cannot mistake one for the other.

**2,756 Sanskrit terms are rendered by more than one Tibetan**, and nothing here picks a
winner. `parivrājaka` appears as `ཀུན་ཏུ་རྒྱུ་བ།`, `ཀུན་དུ་རྒྱུ།` and — in one text —
transliterated rather than translated, `པ་རི་པ་ར་ཙ་ཀ`. `TermAnchors.renderings/2` returns the
set with how many texts chose each, which is the refusal `Pramana.Translations` makes about
whole passages, one word down. It is also Phase 6's translator-divergence measurement
arriving early and for free.

Stored apart from `glossary_terms` on purpose: that table is a **policy** (376 hand-pinned
renderings for one Chinese commentary, answering *what should this be called*), this one is
**evidence** (*what did this translator call it, in this text*). Merging them would put a
decision and an observation in one row and lose which was which.

**What is still missing:** the Mahāvyutpatti proper. It is Toh 4346 — in the Tengyur, which
this corpus does not hold — so the imperial lexicon itself waits on that acquisition.

### The reading dictionary (#24) — the Buddhist readings were already in Unicode

The task was scoped as "a general pinyin library gets Buddhist vocabulary wrong, so build
a dictionary of the exceptions." That framing turned out to be half right in a way worth
recording.

Unihan's `kMandarin` — the field a per-character library reads — gives **佛 as *fú***.
佛 occurs 533,670 times in the canon and is *fó*; the *fú* reading exists because 佛 is
common in 仿佛 *fǎngfú*, and kMandarin records the commonest reading, not the right one.
So the single most frequent character in Buddhist Chinese is misread half a million times
by any method that reads characters one at a time.

But `kHanyuPinyin` lists 葉 as `yè, shè`. `kXHC1983` lists 若 as `rě`. 般 is `bān, bō`.
**The Buddhist readings are in Unicode already** — spread across four fields nobody
consults. Nothing needed inventing. What needed recording is *which attested reading
applies to which form*, which is exactly what an exception table is, and it turned the
integrity rule into something checkable: **every syllable of every asserted reading must
appear in that character's attested set**, or it does not ship. The hand-curated file is
checked the same way, and an unattested syllable fails the build rather than entering the
corpus as a fact.

Result: 9,543 exceptions over a 44,348-character base, from two independent sources that
agree on 96.8% of compounds. On a 46-form test set covering 1,751,507 corpus occurrences,
per-character scores **50%**, the dictionary **100%**, breaking none of the 23 controls.

**Half the test set is forms the naive method gets right.** A set of only hard cases
would show that the dictionary fires, not that it fires in the right places — and a
dictionary that "corrected" 菩薩 or 涅槃 would be worse than none.

Four filters, each added because the unfiltered output contained that mistake:

1. **Polyphone ambiguity** (1,168 characters skipped). 說 is *shuō*, *shuì* and *yuè*;
   picking one without context is the guessing this table replaces. 佛 survives only
   because its other reading is glossed "used in 仿佛" — a fact about one word, not about
   the character.
2. **Neutral-tone erosion** (2,957 rejected). CC-CEDICT records modern *spoken* Mandarin,
   where 知識 is *zhī shi*. Twentieth-century speech is not evidence about a
   seventh-century text.
3. **Cross-source attestation** (401 rejected). The filter that makes the result
   trustworthy rather than merely sourced: two independent authorities have to agree.
4. **Corpus occurrence** — measured, not enforced. 3,172 of 9,543 forms occur in CBETA,
   covering 1,927,240 occurrences. Scoping the artifact to today's corpus would make it
   wrong the moment a corpus is added.

**And the parameter limit for the fourth time.** `Pramana.Batch` was extracted after the
second and documented after the third, and `Readings.store/1` still blew up — because it
had no batching at all and had simply never been handed enough rows to notice. Offering
`chunk/1` leaves every call site free to forget. `Batch.insert_all/4` takes the same
arguments as `Repo.insert_all/3` and cannot be called without batching; every unbounded
write path now goes through it, including two that were latent (`Parallels.store_anchors`
unbatched, `Parallels.store` with a hardcoded 5,000). **A shared helper only helps if
using it is easier than not.**

One more, on shape of work rather than data: the corpus-occurrence check was first
written as `LIKE '%form%'` per form against the pg_bigm index. It measured **1.3 seconds
each** — because proving a form is *absent* is the expensive case — which is 3.6 hours for
13,000 forms. One streaming pass over the corpus answers the same question in 2m11s.
Index-per-item beats a scan only when the items are few.

### The Tengyur (#21) — the release that says nothing about works

The Tengyur has an official TEI release and it is unusable for this. Counted across all
212 files:

| | line milestones | work milestones |
|---|---|---|
| Kangyur TEI | 460,539 | **1,208** (`unit="text"`) |
| Tengyur TEI | 888,576 | **0** |

Every Tengyur milestone is `unit="line"`, and each file holds exactly **one** `<tei:div>` —
the whole volume as one undifferentiated block. The encoding knows where every line break
falls and nothing at all about where one work ends and the next begins. Its own header says
it was generated from the plain text by a script; the script did not carry the work markers
across.

That is not merely incomplete, it is unciteable. A URN here is
`pramana:<source>.<witness>:<work>@<locator>` and the work is a required component, so a
line-only encoding yields an address with no building: 891,169 lines of real Tibetan,
every citation resolving, none of them able to name what it quotes. The plain text carries
**3,380 `{D…}` markers, 3,380 distinct** — exactly one per work — so that is what
`Pramana.Normalize.DergeTengyur` reads. Checked before writing a line of the normalizer,
not after.

Three things the format forced:

- **The volume number is in the filename**, `079_རྒྱུད་འགྲེལ།_ཚུ.txt`, because the plain text
  has no title page to print it on. `mix pramana.verify` therefore needs a per-format rule
  for where a volume's number lives: the Kangyur's TEI is asked, the Tengyur's path is
  parsed. Taking it from the *order* of the recorded paths would have reproduced a text
  whose anchors agree with themselves and with nothing printed.
- **What the woodblock prints is what enters the text.** The editors' modern spellings
  `{མི་,མེ་}`, suggested corrections `(བཟད་,བཟང་)` and Pedurma note marks `#` are all
  recorded as apparatus beside the printed reading, never in place of it. A normalizer
  that silently accepted the corrections would produce a text no edition contains, and
  every citation into it would still resolve — the exact failure mode this project exists
  to prevent.
- **Volume 213 is 0 bytes.** It is the དཀར་ཆག, the catalogue volume, published empty in
  this release. The walk halted on it, correctly: a volume that yields no works is how a
  broken normalizer looks. The fix distinguishes an empty *file* (counted as `empty`,
  skipped) from a volume with bytes that yields nothing (still halts). Making the walk
  tolerant of both would have hidden the failure it was written to catch.

**The lockfile verified nothing, and said it was fine.** All 213 Tengyur entries recorded
absolute paths on one machine — `/Users/…/raw/tengyur/text/001_….txt` — so
`Lockfile.verify("derge-tengyur")` failed on every one of them while the Kangyur's 103
passed. The ingest code was already right and even carries a comment predicting this:
`Path.relative_to/2` returns the path **unchanged** when the prefix does not match, "which
produces a lockfile that looks right and verifies nothing." The cause was the layout.
`Lockfile.verify/1` resolves each recorded path against `raw/<source_id>/`, and this
source alone sat at `raw/tengyur/` while its id is `derge-tengyur`, so the prefix never
matched and every path passed through untouched. Moving the raw to `raw/derge-tengyur/`
fixes it, but the recorded `source_file` on each text moves with it, so the re-ingest is
required rather than cosmetic — and it is the re-ingest that proves the point: 3,380
works and 891,169 segments again, and the 52,371 already-computed vectors re-imported
with **0 hash mismatches**, which is independent evidence that the chunk content did not
move when the files did.

The general rule, now that it has cost two runs: a check that resolves paths by convention
must have the convention enforced where the path is *written*, because the failure mode is
a green checkmark. Nothing errored. `verify` passed, `integrity` passed, the bake was
byte-identical — and the provenance record pointed at one laptop.

**And it was not the only one.** The fix prompted a check that runs `Lockfile.verify/1`
over *every* source rather than the one just touched — now step 3 of the data-integrity
gate in `docs/CHECKS.md` — and it caught the **Pāli canon failing on all 7,288 files**.
Different cause, identical consequence: `pramana.sc.ingest` recorded paths relative to the
checkout root, `raw/sc/bilara-data`, so every path lost its `bilara-data/` prefix and
resolved to `:enoent`. The provenance record for 8,442 works had verified nothing since
#38 and nothing said so. Six of the eight sources were clean (`84000` 406, `84000-rdf`
1254, `bdrc-derge` 103, `cbeta` 2471, `derge` 103, `derge-tengyur` 213); `sat` is
correctly `:not_locked`, never having been acquired. **Check the sources you did not
touch** — the defect lives in how a path was written, and it is invisible from the side
that reads it back on the same machine.

**And `integrity` immediately earned it — it caught a defect `verify` could not.** The
first Tengyur bake passed `verify` byte-identically and FAILED `integrity`: `toh4100`
(raw 5583, bake 5582) and `toh4150` (raw 1873, bake 1872), each missing exactly one line.
Where one work ends and the next begins mid-line the page reads `[222b.1]#{D4101}#༄༅༅།…`,
so splitting on the marker hands the ENDING work a fragment containing only the `#`.
`extract/1` strips that into an apparatus entry, leaving `text: ""`, and `emit/5` kept the
line because its apparatus was not empty. Three components then disagreed about one
boundary artifact: the normalizer promised a line, the loader refused it (a segment with
no content is not citable), and `integrity` reported the difference. The mark annotates
the printed line, which belongs to the work that STARTS on it and is recorded there, so a
fragment with no printed text is no longer emitted at all. After the fix the ingest reports
`lines: 891169, segments: 891169` — previously 891171 against 891169, exactly the two
phantom lines.

This is the whole argument for running both checks, made concrete: a pipeline that drops
the same content every run drops it identically on both sides of a re-normalization
comparison, and `verify` passes. Reproducibility is not fidelity.

**`integrity` is weaker here than for the Kangyur, and says so.** The Kangyur gets an
independent byte census: a separate counter walks the TEI `<text>` element and totals
character data without knowing anything about folios, which is what catches content the
normalizer drops silently. Plain text has no such envelope — its markup *is* its text — so
no second, independent count of it exists. The Tengyur is covered by per-work
addressability and by byte-identical re-derivation instead. Reproducibility and fidelity
are different questions (`docs/CHECKS.md`), and for this half of the edition the second is
answered less strongly. Documented rather than papered over.

The Tengyur is loaded as `treatise`, not `root` — provenance is per collection, and
calling Vasubandhu the Buddha's word by inheriting the Kangyur's text role would be a
category error the citation would carry forever.

Two per-source settings had to move with it, neither of which fails loudly. Chunk size is
`1_200` for both halves because they are the same script; a source missing from
`@max_chars_by_source` takes the **Chinese 300**, a fifth of the window, and would have
under-chunked 891,169 segments without an error. Language is `"bo"`; a source missing from
`@lang_by_source` takes the **`lzh` default**, and that field is what `matched_via`
reports, so every Tibetan vector would have named the wrong language. Both are now
asserted in tests, because the defect class here is silent correctness, not breakage.

### Pāli takes 193 of 200 slots, and that is why two topical rows are 0% (#19)

`topical/chinese` and `topical/tibetan` both score **0%**, and the obvious reading — the
corpus cannot answer — is wrong for Tibetan. Asked "What are the four noble truths?", the
semantic arm returns:

| depth | sources | first Tibetan |
|---|---|---|
| k=30 | `sc.ms` 30 | — |
| k=200 | `sc.ms` **193**, `cbeta.T` 5, `derge.D` 2 | **rank 142** |

The Tibetan passages exist and are eligible: **250 chunks** contain འཕགས་པའི་བདེན་པ་བཞི *and*
carry an English rendering vector (276 for dependent origination, 229 for the five
aggregates, 446 for bodhicitta). They are retrievable — just buried under a canon whose
English is a more direct statement of the same doctrine. All 55,135 English rendering
vectors compete in one space.

That explains the topical picture as one mechanism rather than three problems:
Pāli 56.3% wins its own cases; Tibetan 0% loses the same competition; Chinese 0% has no
English layer and never competes (#12).

**`balance: :tradition` does not fix it — measured.** With balancing the top 10 was one
Chinese and nine Pāli, still zero Tibetan. `balance` interleaves the traditions *present in
the retrieved pool*, and at `depth = limit * 3 = 30` that pool is 100% Pāli. It is a
ranking remedy for a retrieval problem — **it operates one stage too late.** The module's
own moduledoc calls balancing "the right behaviour for a topical question", which is true
of the intent and not achieved by the implementation. The fix is to retrieve per tradition
and merge, so every canon is represented *before* ranking.

**A correction this produced.** An earlier probe reported "30 of 41 misses absent from top
500". `Semantic` has `@max_limit 200`, so `limit: 500` silently returned 200 — the figure
was absence from top **200**. The conclusion stands; the label was wrong.

### Per-tradition retrieval, decided on the full set (#19) — it stays opt-in

The open question from the previous session: `per_tradition: true` was implemented and
committed opt-in, and the decision — whether topical queries should default to it —
needed the gold set. **1,400 cases, 3h09m, 0 stale**, against `evals/baseline.json`:

| | baseline | per_tradition | |
|---|---|---|---|
| retrieval / chinese | 97.8% (227/232) | 97.8% (227/232) | unchanged |
| **retrieval / pali** | 53.3% (80/150) | **42.7% (64/150)** | **−16 cases** |
| **retrieval / tibetan** | 31.3% (20/64) | **21.9% (14/64)** | **−6 cases** |
| topical / chinese | 0.0% (0/12) | 0.0% (0/12) | unchanged |
| topical / chinese-native | 100% (12/12) | 100% (12/12) | unchanged |
| topical / pali | 56.3% (9/16) | 37.5% (6/16) | −3 cases |
| **topical / tibetan** | **0.0% (0/9)** | **22.2% (2/9)** | **+2 cases** |
| **answered from any canon** | **72.7% (8/11)** | **54.5% (6/11)** | **−2 topics** |

**It buys 2 topical cases for 22 pinpoint ones, and makes the user-facing number worse.**
So it stays opt-in. The moduledoc had asserted it was "wrong for find-the-passage-I-quoted,
where the tradition is not in doubt"; that is now a measurement rather than a claim, and
the trade is about 11:1 against.

**The row that teaches something new is `retrieval/tibetan`, 31.3% → 21.9%.** Per-tradition
retrieval *guarantees* Tibetan a third of every result set, and Tibetan pinpoint retrieval
got **worse**. Giving a canon more slots can only help if its internal ranking can use
them — and #10 measured Tibetan's mean pairwise cosine at 0.9727, so within-Tibetan ranking
is near-random. The slots get filled with near-ties, and correct answers that were scraping
into the top ten on the strength of cross-tradition competition fall out. This is the
embedder bound showing up from a new direction: not as a ceiling on what Tibetan can reach,
but as a *cost* to giving Tibetan more room.

**`retrieval/chinese` is unchanged to the case**, 227/232 both ways. Chinese never faced
competition it could lose, so isolating it changes nothing — the same reason `topical/chinese`
stays 0/12 with guaranteed slots. For Chinese the monopoly was never the binding constraint;
the missing English layer is (#12, #43). The 0%/0% pair in the topical rows had two different
causes all along, and this separates them.

**Do not quote the overall 89.5% → 87.9%.** Both runs score the same 1,400 cases, so it is
comparable — but it is dominated by the 901 guard and provenance cases at 100%, which this
change cannot touch. The per-tradition rows are the measurement; the aggregate only dilutes
them.

**`evals/baseline.json` was NOT updated.** An experiment is not the ratchet, and writing a
non-default configuration into the baseline would silently redefine what every future gate
compares against.

Three defects found while getting to this number, all of which would have corrupted it:

- **`per_tradition` was unreachable from everything that ships.** `Semantic` accepted the
  option and `Hybrid` did not know about it, so `Hybrid.search(q, per_tradition: true)`
  raised from `Lexical.validate_opts!/1`. Every caller — the MCP tools, the eval harness —
  goes through `Hybrid`. The feature was measurable only by a probe calling `Semantic`
  directly, which is exactly how it had been measured.
- **The first run I did returned topical numbers identical to baseline on all four rows,
  and I nearly reported them.** They were baseline's numbers; the flag had not taken
  effect. What caught it was the identicality being too clean for a change a probe had
  already shown moves results. *A configuration flag that changes nothing is a claim about
  the flag, and it should be checked against the mechanism before it is believed.*
- **`mix pramana.evals --only topical` reported "ran 1400 case(s) ... 3.5 cases/s"** for a
  run that scored 49 — it counted the loaded gold set, not the scored one. Every rate this
  project has published from that line was wrong by the ratio of the two.

### Retrieval depth is worth +7 cases and costs 5.4x (#10) — measured, not adopted

The probe above suggested fusion depth was worth real recall. It is, across every
tradition, and the price is the reason it is not simply switched on. All 446 `retrieval`
cases, depth 60 (the shipped default, `limit * 3`) against depth 200:

| | depth 60 | depth 200 | |
|---|---|---|---|
| retrieval / chinese | 97.8% (227/232) | **98.3% (228/232)** | +1 |
| retrieval / pali | 53.3% (80/150) | **54.7% (82/150)** | +2 |
| retrieval / tibetan | 31.3% (20/64) | **37.5% (24/64)** | **+4** |
| **overall** | 73.3% (327/446) | **74.9% (334/446)** | **+7** |
| **wall clock** | **~50 min** | **4h25m** | **5.4x** |

**Nothing regressed**, which is what the pre-registered rule required, and Tibetan's 24/64
has now been produced three independent times — the depth-200 probe, an isolated Tibetan
arm, and this full run. Read the per-row gains carefully though: **only Tibetan's +4 clears
the one-case ANN wobble on its own.** Pāli's +2 and Chinese's +1 are inside it and should
not be quoted as established; the aggregate +7 is what carries.

**The cost is the finding.** 35.6 s per case against ~6.6 s, which is *more expensive than
per-tradition retrieval* (22.7 s/case) despite running one scan instead of three. The
lexical arm is why: at depth 200 it pulls 200 segments out of a 4.7M-segment bigram index
and maps every one to its containing chunk, and the 232 Chinese definitional-formula cases
hit that hardest. As a default it would take the 1,400-case gate from about an hour to
about five, on a check meant to run at every phase gate.

So depth ships as an **option**, not a new default. The middle was then measured, over the
same 64 Tibetan cases:

| depth | retrieval / tibetan | mean rank |
|---|---|---|
| 60 (default) | 31.3% (20/64) | 3.1 |
| **120** | **39.1% (25/64)** | 3.2 |
| 200 | 37.5% (24/64) | 3.0 |

**The whole gain arrives at depth 120.** 25 against 24 is one case, inside the ANN wobble,
so 120 and 200 are indistinguishable on recall and the extra 80 candidates buy nothing.

**The first wall clocks were cache weather, and an ABBA run replaced them.** Depth 120 had
timed at 13m12s against depth 200's 11m21s — backwards, since 120 does strictly less work.
Those arms ran hours apart, and this session already measured cache state moving
`coverage/1` by 5x. So the arms were re-run **back to back in one session, in ABBA order**
(60, 120, 120, 60) to cancel drift:

| arm | depth | recall | scoring time |
|---|---|---|---|
| 1 | 60 | 20/64 | 7m24s |
| 2 | 120 | 25/64 | 11m01s |
| 3 | 120 | **crashed** | — |
| 4 | 60 | 20/64 | 7m32s |

The two depth-60 arms agree to **1.8%**, which is what a usable cost baseline looks like
and what the earlier 5m16s figure was not. **Depth 120 costs 1.47x**, nothing like depth
200's 5.4x, and it carries the whole recall gain.

**And it is still not the default, because one arm in two died:**

    ** (DBConnection.ConnectionError) client timed out because it queued and checked out
       the connection for longer than 120000ms
       lib/pramana/retrieval/lexical.ex:296: Pramana.Retrieval.Lexical.run/4

A single **lexical** query exceeded the 120-second pool timeout and took the whole run with
it. Three things follow, and the last two matter more than the depth question:

- **A default that occasionally kills a multi-hour gate is not a default.** Depth 120
  sits on the edge of the timeout and which side it lands on depends on cache state.
- **The cost of depth is in the BIGRAM index, not in HNSW.** Every intuition here had been
  that depth buys vector-scan time; `lexical.ex:296` says otherwise, and it explains why
  the 232 Chinese definitional-formula cases dominated the 4h25m run. Tuning the vector
  side would have optimised the wrong half.
- **A lexical query can take over two minutes**, which is a live risk on the MCP surface
  and has nothing to do with evals. It is its own defect and its own task.

**This section previously ended "Both halves are now fixed". That was wrong**, and it was
written the same morning the `texts.body` fix landed, on the assumption that the 32x
speedup removed the timeout. It did not. A four-arm ABBA re-run afterwards timed out again
on the same line, and the real cause turned out to be the n-gram fallback — see *The
two-minute lexical query was 135 OR'd LIKEs* below. The claim is corrected rather than
deleted because the mistake is the instructive part: **a speedup measured on one workload
was assumed to fix a timeout observed on another**, and the two workloads were Chinese
phrase queries and English n-gram fallbacks, which share a line number and nothing else.

The same timeout is what killed the depth-200 arm hours earlier; that death was invisible
because a `grep` in the pipeline swallowed the error while the loop still exited 0. The
progress heartbeat added the same day earned itself immediately — the log shows
`10/64 · 1m12s` and `20/64 · 2m24s` before the crash, so the failure point is known rather
than guessed.

**A process note that cost hours.** This run produced no output for 4h25m, so "how far
along is it" was unanswerable and three ETAs were wrong — all extrapolated from a Tibetan
arm that turned out to be the *cheap* tradition. The gold files also load alphabetically,
so the expensive Chinese cases run first, which makes any linear projection from early
elapsed time wrong in the same direction. `mix pramana.evals` now prints a progress
heartbeat for exactly this reason.

### The slow lexical query was `texts.body`, and it was 32x (#10)

`lexical.ex:296` in the crash stacktrace was `Repo.all`, and what it was fetching was the
whole corpus body, repeatedly. The query joined `texts` and preloaded through the join:

    |> join(:inner, [s], t in Text, on: t.id == s.text_id)
    |> preload([_s, t], text: {t, [:work, :witness, :source]})

A join-preload ships **every** column of the joined row, `texts.body` included — the
entire normalized work — **once per matched segment**, and the query over-fetches
`limit * 5` rows before ranking in Elixir. Bodies average **27,218 characters** and the
largest is **13,279,028**, so a 20-result search pulled 100 bodies through shared
buffers to read a title and a licence class off each. **Nothing in the result path reads
`body`**: `Corpus.span_from_segment/1` wants `work`, `witness_id`, `source_id`,
`source.license_class`, `volume` and `meta`, and `Corpus.body/1` fetches the body itself
when offsets need verifying.

The fix is a separate preload query selecting every `texts` column except `body`, which
also loads each DISTINCT text once instead of once per row.

Measured against the full dev corpus (15,489 texts, 6.5M segments), five Chinese
formulae, each warmed then timed 5x, minimum taken — and run **ABBA** because this
session had already been burned by cache weather:

| query | join-preload | separate preload |
|---|---|---|
| 一切有為法 | 278 ms | 13 ms |
| 四聖諦 | 542 ms | 7 ms |
| 無明緣行 | 285 ms | 10 ms |
| 如是我聞 | 147 ms | 10 ms |
| 般若波羅蜜多 | 151 ms | 4 ms |
| **total** | **1403 ms** | **44 ms** |

The repeat arms landed at 1491 ms and 47 ms — 6% and 7% apart, so the 32x is real and not
weather. This is warm-cache; the 120-second timeout was a cold one.

Two things this teaches:

- **`preload` through a join is not free, and its cost is invisible at the call site.**
  The one-line idiomatic form is the expensive one, and it gets more expensive the
  larger the widest column in the joined table is. `select: struct(t, [...])` in a
  separate preload query is the cheap form — and it must be `struct/2`, not a `%Text{}`
  literal, which loses the binding and makes Ecto refuse the query outright.
- **A column list in a `select` is a drift surface.** A new `texts` column not added to
  it reads as `nil` with no error anywhere. The test asserts the emitted SQL names every
  `Text.__schema__(:fields)` entry except `body`, so adding a column and forgetting this
  list fails a test instead of silently blanking a field.

### One case may not kill the run (#10)

The same crash exposed a second defect, and this one is a rule the project already holds
everywhere else: *one malformed file fails one job, never the bake* (`CLAUDE.md`). The
evals harness did not honour it. `score_case/2` had no rescue, so a single
`DBConnection.ConnectionError` propagated out of `Enum.map` and took **4h25m of scoring
with it**, discarding every case already completed. It happened twice, and the first time
a `grep` in the pipeline swallowed the error while the loop still exited 0.

A crashed case is now its own outcome, `{:error, detail}`, and the loop continues.
The scoring rules follow from what an error actually is:

- **Not a miss.** A query that timed out is not the retriever failing to find the
  passage. Counting it as one publishes a recall regression that never happened.
- **Not stale either.** Stale means the gold set aged; an error means *we* broke. They
  are excluded from the denominator for the same reason and printed separately because
  the reader needs to know which one it is.
- **Never silent.** Errors get their own header line, their own section, a `[n ERRORED]`
  suffix on every affected row, and an `"errors"` key in `Score.to_map/1` so a JSON
  artefact carries the fact too. A rate over zero scored cases still prints as "no cases
  scored", not 0.0%.
- **`--gate` refuses to run at all** when any case errored. Errored cases are missing
  hits, so the ratchet would either report a regression that did not happen or — with no
  baseline on disk — *install* the under-measured run as the baseline every future run is
  compared against.

The last point is the one worth generalizing: making a long run fault-tolerant is only
half the job. The other half is making sure the shrunken denominator cannot be read as a
result.

### The two-minute lexical query was 135 OR'd LIKEs (#10)

The `texts.body` fix was 32x and did **not** fix the timeout. A four-arm ABBA re-run after
it died on the same line, so the cause was measured properly instead of assumed.

It is not the phrase stage. `:auto` runs the phrase first and falls back to n-grams when
the phrase returns nothing — which for a cross-lingual English query is *always*, since an
English sentence never appears verbatim in Tibetan source text. `ngrams/2` then windowed by
**grapheme at width 3** for anything not Tibetan, so a 145-character English sentence became
**135 distinct trigrams**, OR'd into one `WHERE`. `EXPLAIN` on the full corpus:

| stage | plan | est. cost |
|---|---|---|
| phrase — 1 pattern, 145 chars | Bitmap Index Scan on `segments_content_bigm_index` | 4,698 |
| ngram — 135 trigram patterns | **Seq Scan on segments**, 6,538,238 rows | 3,043,842 |

Past a tipping point the planner abandons pg_bigm and scans the whole table, testing one
substring per predicate per row. `LIMIT depth * 5` with no `ORDER BY` is what made it
*intermittent* rather than merely slow: the scan stops when it fills the limit, so runtime
depends on where matches fall in heap order. Depth 60 filled 300 in time; depth 120
sometimes failed to fill 600 inside the 120 s pool timeout.

**The cliff is selectivity, not a predicate count** — measured, having first assumed
otherwise. On one query the index survived 24 predicates; on another it was abandoned at
**10**. The difference is short common words, which is why the fix is one rule and not two:

- drop words under 3 characters — the exact analogue of the `@particles` list that already
  drops 之, 於, 者 from Chinese as "grammatical particles, not content". `to`, `at`, `in`,
  `on`, `by` are the same thing, and length says so without a dictionary.
- keep the **longest 20**. Length is a dictionary-free proxy for rarity, and rarity is what
  keeps the planner on the index. Longest-first held the index to 24 predicates on the
  query where first-20-in-order flipped at 10.

Verified over every alphabetic query in the gold set: **252 queries, 252 BitmapOr plans,
zero sequential scans.**

**This is the third instance of one defect.** The module already refuses jieba for Chinese
because "a single common character appears on nearly every line", and refuses grapheme
windows for Tibetan because `་པ་` matched 89.6% of segments. Latin script has the identical
pathology and nothing caught it, because `tibetan?/1` was the only script test and
everything else fell through to trigrams. The windows were simultaneously **useless** — a
Latin trigram is a fragment of no linguistic standing, and can only match the Latin-script
(Pāli) part of the corpus, so on a Tibetan question the whole lexical arm entered the
fusion as noise — and **expensive**, because 135 of them defeat the index.

**A known residue, left deliberately.** `the` is exactly at the length floor and survives.
It is the same shape as `་པ་`: a predicate that votes for nearly every Latin-script line.
Min-3 plus longest-20 is what was *measured* to keep all 252 gold queries on the index;
whether also dropping function words improves recall is an eval question, and `@particles`
is the precedent for fixing it if the eval says so.

### What the fix did to the depth question (#10)

The same four-arm ABBA, before and after. Two runs of four arms each, back to back, one
session per run:

| arm | depth | before | after |
|---|---|---|---|
| 1 | 60 | 20/64, 455 s | 20/64, 453 s |
| 2 | 120 | 25/64, 682 s | 25/64, 675 s |
| 3 | 120 | **24/62, 940 s, 2 ERRORED** | **25/64, 672 s, clean** |
| 4 | 60 | 20/64, 456 s | 20/64, 388 s |

**Arm 3 is the whole result.** It crashed the first session, lost 1 case the second, lost 2
the third, and ran clean the fourth. The two depth-120 arms now agree to **0.4%** where the
same pair previously differed by **38%** — the variance left with the timeout, which is
what a fix to an intermittent early-exit scan should look like.

Depth 120's recall gain is now reproduced a **fifth** time: +5 cases, 20 → 25, well clear
of the documented one-case ANN wobble.

**The cost ratio is 1.5–1.7x, and deliberately not quoted more precisely than that.** This
run's own control loosened: the bracketing depth-60 arms came in at 453 s and 388 s, 15%
apart, against 0.2% in the pre-fix run. Taking the depth-60 mean gives 1.60x; taking arm 1
alone gives 1.48x. The ABBA exists to expose exactly this, and the honest reading is a
range. Nothing above depends on it — both recall figures reproduced exactly, and arm 3
running clean is categorical rather than a timing claim.

**Depth 60 moved by nothing — same 20/64, same 453 s.** That is the right result twice
over: depth 60 never hit the timeout, so its runtime should not change, and the trigram
noise the fix removed was contributing no hits to lose.

### The n-gram fix, validated outside the language that motivated it (#10)

The fix changes the fallback for **every** alphabetic query, so validating it on Tibetan
alone and shipping would have been rule 37 again — a fix measured on one workload and
credited against another. Run at the shipped default depth, so the n-gram change is
isolated from the depth question:

| | baseline | after |
|---|---|---|
| retrieval / pali (150 cases) | 53.3% (80/150) | 54.0% (81/150) |
| topical / pali | 56.3% (9/16) | 56.3% (9/16) |
| topical / chinese | 0.0% (0/12) | 0.0% (0/12) |
| topical / chinese-native | 100% (12/12) | 100% (12/12) |
| topical / tibetan | 0.0% (0/9) | 0.0% (0/9) |
| **answered from any tradition** | **72.7% (8/11)** | **72.7% (8/11)** |

**Nothing moved.** The single Pāli case is inside the documented one-case wobble and is not
claimed as an improvement; what it supports is the absence of a regression on the largest
affected category. The word unit cost the Pāli nothing, so the morphological fuzziness the
trigrams provided was not carrying those cases.

`topical/chinese` staying at 0% was **predicted before the run**, and the prediction is
worth as much as the number: those failures are a missing English layer over the Chinese
canon (#43), not a lexical-fallback problem, and a fallback fix cannot create a layer. Had
that row moved, the standing explanation for the 0% would have been wrong.

Under #44's rule — any change must be measured against answered-from-any-tradition before
becoming a default — the fix qualifies: 72.7%, unchanged.

### Depth is per ARM: the gain is semantic, the cost is lexical (#10)

Depth 120 was measured at **~4x** on the full 446-case retrieval set, not the 1.5–1.7x the
Tibetan-only ABBA implied — rule 37 rediscovered by projecting a ratio from one workload
onto another, twice in one session. That killed depth 120 as a global default. But the
cost and the benefit turned out to live in *different retrievers*, which the single `depth`
knob could not express.

Three arms over the 64 Tibetan cases, **prediction written down before the run**:

| arm | config | predicted | actual | time |
|---|---|---|---|---|
| 1 | both 60 (control) | 20/64 | **20/64** | 298 s |
| 2 | semantic 120, lexical 60 | 25/64 | **25/64** | 465 s |
| 3 | lexical 120, semantic 60 | 20/64 | **20/64** | 303 s |

**Semantic depth carries the entire gain; lexical depth carries none of it.** And lexical
depth is nearly free *here* — 303 s against a 298 s control — because a Tibetan gold query
is English, so the lexical arm has little to return however deep it looks.

The asymmetry has a mechanism on both sides:

- **The cost is lexical, and it is Chinese.** A definitional-formula query matches thousands
  of segments, so `limit * 5` over-fetch at depth 120 pulls 600 segments out of the bigram
  index and maps every one to its containing chunk — per-segment work scaling directly with
  depth, over the 232 Chinese cases that dominate the run.
- **The benefit is semantic, and it is Tibetan.** BGE-M3 packs Tibetan into a narrow cone
  (0.9727 mean pairwise cosine), so its candidates are near-ties and the right chunk sits
  deeper in the ranking. Looking further down is exactly what helps.

So `semantic_depth` and `lexical_depth` override `depth` per arm, both defaulting to it.

**The Tibetan probe's 1.56x did not transfer either.** On the full retrieval set,
semantic-120 with lexical pinned at 60 tracks **~2.3x** — better than global depth 120's
~4x, and nowhere near the cheap win the Tibetan arm implied. Deepening the *semantic* arm
is not free on Chinese: an iterative HNSW scan over 617,038 vectors asked for 120
candidates instead of 60 costs real time, and that lands on all 232 Chinese cases whether
or not they benefit. **Three times in one session a ratio measured on one workload failed
to transfer to another**, the third time after rule 37 had already been written down. The
rule is evidently easier to state than to obey; what actually catches it is running the
other workload.

So the trade is **2.3x across 446 cases to gain +5 cases that exist only in the 64 Tibetan
ones**.

**Decision rule, pre-registered before the full-set numbers were seen** — because three
wrong predictions in one session is exactly the condition under which a criterion invented
afterwards becomes a rationalisation:

- **Ship as default** only if `retrieval/tibetan` ≥ 24/64 **and** `retrieval/chinese` ≥
  226/232 **and** `retrieval/pali` ≥ 80/150. The tolerances are one case each, which is the
  documented ANN wobble; two is a real regression under the project's own gate rule.
- **Refuse** on any category down two or more, regardless of what Tibetan does. Chinese and
  Pāli are 382 of the 446 cases, so a genuine regression there outweighs +5.
- **Cost is not a veto for the retrieval default, but it is for the gate.** 2.3x on a
  1,400-case check meant to run at every phase gate is not acceptable. If this ships, the
  gate and the product run different depths — and that tension must be recorded rather than
  quietly resolved, because a gate that does not measure what ships is measuring the wrong
  thing.

**The rule was met on all three criteria, and it ships.** 446 cases, 0 errors, 1h50m:

| | old default | semantic 120 / lexical 60 | criterion |
|---|---|---|---|
| retrieval / chinese | 227/232 | **227/232** | ≥ 226 ✓ |
| retrieval / pali | 81/150 | **82/150** | ≥ 80 ✓ |
| retrieval / tibetan | 20/64 | **25/64** | ≥ 24 ✓ |
| **overall** | 328/446 (73.5%) | **334/446 (74.9%)** | |

Chinese did not move by a single case, which is the result that mattered most: it is 232 of
the 446, and a regression there would have outweighed the Tibetan gain outright. The Pāli
+1 is inside the wobble and is not claimed.

**334/446 is exactly what depth 200 scored** (74.9%, recorded above) — at **1h50m against
its 4h25m**. Depth 200's entire price was being paid by an arm contributing none of its
gain. That is the finding worth keeping from the whole depth investigation: *the question
"how deep should we look" had no single answer because it was two questions*, and three
sessions of ABBA arms went into tuning one knob that turned out to be two.

Shipped as `@lexical_multiplier 3` / `@semantic_multiplier 6` in `Hybrid`. An explicit
`depth:` still sets both arms, so nothing that passes one number changes meaning.

**Both consequences are now resolved, by a full run rather than an extrapolation.**

**The baseline is regenerated: 1,400 cases, 90.0% (1260/1400), 0 errored, 0 stale.** Run at
the shipped default with no experiment flags, so it measures what ships. The category diff
against the old baseline is the cleanest possible result:

| | old | new | |
|---|---|---|---|
| retrieval | 327/446 | **334/446** | **+7** |
| provenance | 300/300 | 300/300 | — |
| quote_verify | 300/300 | 300/300 | — |
| quote_reject | 301/301 | 301/301 | — |
| absence | 4/4 | 4/4 | — |
| topical | 21/49 | 21/49 | — |
| **overall** | **89.5%** | **90.0%** | |

**Retrieval is the only category that moved**, which is what a retrieval-depth change should
look like and is not guaranteed — #43 measured 1,665 gloss vectors displacing Pāli answers,
so a change rippling into another category is a real failure mode. The per-tradition figures
(chinese 227/232, pali 82/150, tibetan 25/64) reproduce the standalone 446-case run
**exactly**, from a separate execution.

**89.5% → 90.0% is a real +7 cases, unlike the last time this number rose.** When the set
grew 249 → 1,400 the average went 79.5% → 89.4% while nothing improved, because the mix
changed. Here the denominator is identical and only retrieval moved.

**The gate cost, measured rather than projected — and the honest figure is a range.** The
446 retrieval cases took **~2h23m** inside this run against **1h50m** for the same cases
standalone two hours earlier, and ~50 min at the old default. So the multiplier is somewhere
between **2.2x and 2.9x**, and the spread is not depth: the machine measurably slowed across
a six-hour session of continuous eval runs, with the Chinese block drifting from 24.9 s/case
to ~39 s/case. The full set now runs **3h08m** wall clock; the previously recorded "62
minutes" was CPU time and is not comparable.

That left a question that looked like a policy choice: a 3h gate is not something anyone runs
at every checkpoint, and running it shallower than the product means it stops measuring the
product.

**It was not a policy choice. It was a bug**, found within the hour — 38 of every 41 seconds
of a search were `texts.body` being shipped for nothing. See *A search took 41 seconds*
below. **The full gate now runs in 18m13s against 3h08m, a 10.3x speedup**, verified by an
actual `--gate` run: 1,400 cases, 90.0%, every row identical to baseline, `gate OK`.

Recorded here because the instinct to solve a cost problem with a sampling policy was wrong,
and would have permanently degraded the instrument to avoid profiling a query.

### A search took 41 seconds, and 38 of them were `texts.body` again (#10)

The whole day's work on the lexical arm was optimising **0.03%** of the query. Profiled
after the depth work, five Chinese gold queries, warmed:

| | before |
|---|---|
| lexical arm | **14 ms** |
| semantic arm | **41,142 ms** |

A 41-second search is a product defect before it is a gate problem — an MCP caller waits
that long for one `search` call. Splitting it further: the query embedding is **555 ms**
and the database is **~38 s**, while the equivalent ANN query in `psql` runs in **357 ms**.
So it was never HNSW, never `ef_search`, and never the iterative scan.

**It was `texts.body`, in the three places the morning's fix did not touch.** Captured from
Repo telemetry, the semantic path emitted:

- **the ANN select**, which selected the whole `Text` struct — `body` included — for every
  candidate row, and this query over-fetches `limit * @vector_overfetch`;
- **an N+1 of ~120 queries**, one per result, each ~200–300 ms, each a
  `preload([s, t], text: {t, ...})` through a join in `Corpus.between/4` — and each one
  dragging a whole work to build a range span.

120 × ~250 ms is the missing 30 seconds.

**Four call sites, one defect, and the rule did not prevent it.** Rule 34 was written this
morning after fixing exactly this in `Retrieval.Lexical`, and by the afternoon the same
pattern was still live in `Corpus.between/4`, `Corpus.context/2`, `Corpus.fetch_span/1` and
`Semantic.single_search/2`. Writing the rule down did not sweep for other instances, and
nothing made the next author's `preload: [text: {t, ...}]` look wrong.

So it is a **shared function** now — `Text.preload_without_body/0` and
`Text.fields_without_body/0` — for the reason `Pramana.Batch` exists: the 65,535-parameter
limit was hit, written up as rule 14, and then hit again in a fresh call site. A rule in a
document does not survive being reimplemented; a function does.

**And the field list is now derived, not written.** The morning's fix listed every `texts`
column explicitly and its own comment admitted the list was "a drift surface" — a column
added later and not listed would read as `nil` with no error. `__schema__(:fields) --
[:body]` cannot go stale, so the drift surface is gone rather than merely tested.

Measured after, same five queries:

| | before | after | |
|---|---|---|---|
| semantic arm | 41,142 ms | **3,395 ms** | **12.1x** |
| hybrid search | 41,169 ms | **2,242 ms** | **18.4x** |

**And the gold set says it changed nothing but the clock.** All 446 retrieval cases:

| | before | after |
|---|---|---|
| overall | 334/446 (74.9%) | **334/446 (74.9%)** |
| chinese | 227/232, mean rank 1.98 | **227/232, mean rank 1.98** |
| pali | 82/150, mean rank 3.09 | **82/150, mean rank 3.09** |
| tibetan | 25/64, mean rank 3.24 | **25/64, mean rank 3.24** |
| **wall clock** | **2h23m** | **17m22s** |

Mean ranks agreeing to two decimals is stronger evidence than the hit counts: not merely
the same passages found, but in the same order. `evals/baseline.json` therefore stays valid
— nothing it records moved.

**This retires the gate tension recorded above, by 10.3x.** Verified with a real `--gate`
run rather than projected: **1,400 cases in 18m13s against 3h08m**, 90.0%, every row
identical to baseline including mean ranks, `gate OK — no case type regressed`.

| | before | after |
|---|---|---|
| the 901 non-retrieval cases | ~28 min | **8 s** |
| the 446 retrieval cases | 2h23m | ~17 min |
| **full gate** | **3h08m** | **18m13s** |

**The non-retrieval half is the part nobody predicted, including twice by me.** I sized this
first at "~50 minutes" and then at "~21 minutes", both too pessimistic, because both times I
sized only the retrieval half I had been staring at. `provenance`, `citation_guard`,
`quote_verify` and `quote_reject` all resolve URNs through `Corpus.fetch_span/1` — one of
the four body sites — so 901 cases went from ~28 minutes to **8 seconds**. The same
estimation error as every other one today, in the flattering direction for once: **size the
whole thing, not the half you were looking at.**

A gate at 18 minutes is a different instrument from a gate at three hours: it can run on
every change rather than at phase boundaries. The tension was never depth against cost; it
was 38 seconds per search of pure waste, and no policy would have been the right answer.

**The lesson is about where the day went.** Every measurement was sound and every
conclusion followed from its evidence — the ABBA arms, the arm-attribution probe, the
pre-registered criteria. But the whole investigation optimised the lexical arm, which was
**0.03%** of the query, and the 41-second semantic arm sat unprofiled underneath all of it
because a *timeout stack trace pointed at `lexical.ex`*. The stack trace named the arm that
happened to hold the connection when the pool gave up, not the arm consuming the time.
**Profile the whole operation before optimising the part an error message names.**

### Translate the QUERY, not the canon (#43) — 0% to 91.7%, and term choice is worth 50 points

Stage B was scoped as generating English for ~300,000 Chinese chunks (~$260–770, plus
re-embedding, plus a 20:1 English-vector imbalance that #43 measured as likely to bury the
Pāli). The cheaper question was never asked: **`topical/chinese` and
`topical/chinese-native` are the same twelve questions in two languages**, scoring 0% and
100%. The passages are indexed and findable. Only the query is in the wrong language.

Two arms over those twelve, scored by the real harness with `expect_contains` **unchanged**
— only the query rewritten:

| arm | score | mean rank |
|---|---|---|
| English (shipped default) | **0.0%** (0/12) | — |
| **A — the term a translator would pick** | **91.7%** (11/12) | **1.0** |
| **B — a defensible synonym** | **41.7%** (5/12) | 2.8 |
| hand-written Chinese (gold) | 100% (12/12) | 1.25 |

**Translating the query recovers nearly everything, for no corpus change at all** — no
generated text stored, no new vectors, so the imbalance that blocked stage B never arises
and invariant #8 is not even engaged, because nothing generated is persisted. A
well-termed Chinese query returns at **mean rank 1.0**, better than the curator's own.

**And the whole risk is term choice, now quantified at ~50 points.** Arm B substituted
equally legitimate renderings and lost seven cases: 八聖道分 for 八正道, 四念住 for 四念處,
七菩提分 for 七覺支, 六處 for 六入處, 四等心 for 四無量心, 三十七菩提分法 for 三十七道品,
空定 for 空三昧. Each is real Buddhist Chinese; each is a register the *corpus does not
print here*, and lexical matching against a term the edition never uses returns nothing.

Two things make this trustworthy rather than a lucky sample:

- **The single Arm A miss was pre-registered.** Before scoring, the ambiguity note for
  top-021 read "緣起 vs 十二因緣 — the gold term is the latter". 緣起 was the one term where
  the natural translation and the canon's phrase diverge, and it is the one case that
  failed. The failure mode was predicted, not discovered.
- **Arm B's hit on top-021 is the inversion.** There the "alternative" happened to *be*
  the gold term, and it passed. The arms are measuring term choice, not query phrasing.

**This reverses the priority between the two candidate mechanisms.** Glossary term mapping
was assessed as too weak to matter — 84000's `glossary_entries` recovers only 2 of 12 gold
doctrinal terms as a *retrieval* method. But as a *constraint on translation* it is the
difference between 91.7% and 41.7%. `docs/TRANSLATION.md` already specifies the shape:
glossary-pinned translation with a visible term-mapping chain. It is not an enhancement to
query translation; it is the part that works.

**Caveats, because twelve cases is twelve cases.** One case is 8.3 points here, so Arm A
against Arm B is decisive while 91.7% against the gold's 100% is not. `topical/*` cannot
grow without more curated terms (it rejects terms too common to measure), so this axis
stays statistically thin by construction — the finding to bank is the *ordering* of the
arms, not their exact rates.

**What it would cost architecturally**, and the reason this is a decision rather than a
merge: it puts a model in the query path, which today has none. Search would stop being a
pure function of `bake_id` — the same question could return different passages on different
days — and it adds ~0.5–1 s to a search now running at 2.2 s. Neither touches the bake,
reproducibility of the corpus, or what is citable. A translation cache keyed by query hash
(ROADMAP anticipates one for Phase 7) makes the determinism objection largely go away.

### The glossary arm: the mechanism works, the term source does not (#43)

Built on the finding above — translate the query, and use a glossary rather than a model
because a glossary can expand to *every* attested register where a model must gamble on
one. `Pramana.Retrieval.Terms` maps English doctrinal vocabulary to Chinese from 84000's
1,105 English↔Chinese glossary pairs, and `Hybrid` fuses it as a **third arm**, so the
existing arms are untouched and nothing that works for Pāli or Tibetan can regress by
construction.

It works, on exactly the queries it can see. "What are the four noble truths?" expands to
`["四聖諦"]` and goes from **miss to rank 3**. And then the gold set:

| | before | with the arm |
|---|---|---|
| topical / chinese | 0.0% (0/12) | **16.7% (2/12)** |
| topical / pali | 56.3% (9/16) | 50.0% (8/16) |
| **answered from any tradition** | **72.7% (8/11)** | **63.6% (7/11)** |

**Two of twelve — which is the number this document already recorded and I argued myself
out of.** Sizing #12 established that "`glossary_entries` (84000) recovers 2 of 12 gold
doctrinal terms". Reading the glossary dump directly, I saw 四聖諦 and 四念處 alongside many
near-misses and called it "richer than 2 of 12 implied". It was not: the near-misses —
八聖道分 for 八正道, 菩提分法 for 七覺支, 四念住 for 四念處 — are **the wrong register for this
corpus**, which is precisely the 50-point failure mode measured in the arm B experiment an
hour earlier. The evidence to predict 2/12 was already in hand and was not applied.

**So it stays opt-in and off** (`expand_terms: true`). Under #44's standing rule a change
must be measured against answered-from-any-tradition before becoming a default, and this
one moves it the wrong way. The Pāli and topic losses are single cases, inside the
documented wobble, so the honest reading is not "it regresses" but "**+2 of 12 does not
justify a third arm diluting RRF**".

**The bottleneck is the term source, not the design.** 84000's glossary is oriented to the
Tibetan canon, and its Chinese equivalents come from translation traditions CBETA does not
print. A term list built *from this corpus* — every attested rendering, with occurrence
counts, adjudicated the way the topical gold terms already are — would plug into the same
arm unchanged.

**And a limit worth stating plainly, because it bounds the whole approach.** A glossary
fires on vocabulary. Measured directly:

    "What are the four noble truths?"                            -> ["四聖諦"], rank 3
    "What are the 4 things the buddha said when he was
     enlightened"                                                -> [], miss
    "what did the buddha realise under the bodhi tree"           -> [], miss

Both paraphrases return **8 of 8 Pāli results and no Chinese** — and the semantic arm
answers them *correctly* from the Pāli, with `Cattāri ariyasaccāni` at rank 4 on the first.
So a reader asking a paraphrase is not empty-handed today; they simply never receive the
Chinese witness. That is what `answered from any tradition` measures, and it is why the
three mechanisms are complementary rather than competing:

| | paraphrase | reaches Chinese |
|---|---|---|
| semantic arm | yes | **no** (0%, no English layer) |
| glossary arm | **no** (fires on vocabulary) | yes |
| LLM query translation | yes | yes, if term-pinned |

`docs/TRANSLATION.md` already specifies the combination — glossary-pinned translation with
a visible term-mapping chain. The measurements now say why neither half suffices alone: the
model supplies paraphrase understanding, the glossary supplies term fidelity, and the
glossary this corpus needs is one it has not got yet.

### `hnsw.ef_search` tracking the row limit does nothing — tried, measured, reverted

Looked like an obvious defect. `ef_search` was never set, so it sat at pgvector's default
of **40**, while the ANN query's SQL limit is `limit * @vector_overfetch` — after the
semantic arm moved to `limit * 6` that is **480 rows requested from a graph exploring 40**,
a 12x mismatch against pgvector's own guidance that `ef_search` be at least the limit. And
#43 had already recorded this exact class of failure: "the plain scan had been costing
recall all along — nothing failed; the answers were just further down."

A single-probe check seemed to support it: top-120 at `ef_search` 40 against 200 shared
**112 of 120** candidates with an identical top 10, so the difference lay in the tail — and
the depth work had just shown the tail is where Tibetan's +5 cases came from.

**All 446 retrieval cases, and nothing moved at all:**

| | baseline | ef_search = row limit |
|---|---|---|
| overall | 334/446 | **334/446** |
| chinese | 227/232, mean rank 1.98 | **227/232, mean rank 1.98** |
| pali | 82/150, mean rank 3.09 | **82/150, mean rank 3.09** |
| tibetan | 25/64, mean rank 3.24 | **25/64, mean rank 3.24** |
| wall clock | 17m22s | 18m17s (**+5.3%**) |

Mean ranks identical to two decimals: not one scored case changed position.

**Why, and it was reasonable to work out beforehand:** the iterative scan already
compensates. `relaxed_order` with `max_scan_tuples = 200,000` keeps pulling candidates
until the limit is satisfied, which is exactly what a larger `ef_search` would otherwise
buy. The two knobs address the same shortfall, and this codebase already turned the other
one on. The 112/120 overlap was evidence *for* that reading — the scan recovers the tail —
and it was read instead as "the tail matters", which was true and beside the point.

**Reverted.** No gain, 5% cost, and a knob with no measured motivation is a future
maintainer's puzzle. Recorded here so the next person who notices `ef_search` at its
default does not spend the afternoon on it: **it is not a bug, it is subsumed by the
iterative scan.** If `iterative_scan` is ever turned off, this becomes live again.

### The reranker needs no model, and it is worth +46 cases (#10)

Once the Pāli diagnosis said "ranking, not recall", the obvious next step was a
cross-encoder. It was not needed. **The `retrieval` cases quote a published translation,
and we store that translation** — so comparing the query directly against each candidate's
rendering separates them far more sharply than a chunk embedding does, at zero inference
cost. Invariant #5 again: deterministic before probabilistic, and here the deterministic
answer is also the better one.

`Pramana.Retrieval.Rerank` scores bag-of-words **containment** — how much of the query
appears in the candidate's rendering — over `limit * 5` fused candidates, then cuts to
`limit`. Reranking only the top `limit` could never reach the mis-ranked gold, which sits
at a median rank of 37.

| | baseline | **shipped** |
|---|---|---|
| retrieval overall | 334/446 (74.9%) | **380/446 (85.2%)** |
| retrieval / chinese | 227/232, rank 1.98 | **227/232, rank 1.98** |
| retrieval / pali | 82/150, rank 3.09 | **122/150, rank 1.51** |
| retrieval / tibetan | 25/64, rank 3.24 | **31/64, rank 1.32** |
| topical overall | 21/49 (42.9%) | **26/49 (53.1%)** |
| topical / tibetan | 0/9 | **2/9** — first non-zero ever recorded |
| **answered from any tradition** | **72.7%** | **81.8%** |

Nothing regressed, so it ships as the default under #44's rule. `rerank: false` opts out.

**Two predictions were registered before the run; one held and one was wrong in the
useful direction.** Chinese flat was the falsifier — no English renderings exist over the
Chinese canon, so every candidate scores 0 and the order must return untouched. It did,
exactly. Topical was predicted flat-or-worse on the reasoning that a topical query matches
no stored rendering; it rose by 5, because containment measures how much of the *query*
appears in a rendering, and a doctrinal question's content words do appear there. **This is
not only a quote-matcher — it is an English lexical signal over renderings**, which is why
it helps real questions and not merely the anchor-pinpointing the gold set is built from.

**The caveat that has to travel with the +40 Pāli.** Those gold cases are DERIVED from
translation anchors: the query *is* the rendering of the expected passage. A
query-to-rendering matcher therefore solves them close to the way they were constructed,
and the metric flatters the mechanism. #20 already recorded that this case type measures
"pinpoint the anchor whose translation I quoted" while users ask topical questions. The
capability is real — *"I have this English quote, where is it from?"* is ordinary
scholarship, and the citation guard's workflow begins there — but **+40 on `retrieval/pali`
must never be quoted as a general retrieval improvement**. The honest general number is
`answered from any tradition`, 72.7% → 81.8%.

### The first version silently reordered the canons, and only the per-tradition rows caught it

Shipped as an aggregate it looked clean: 370/446, **+36**. Per tradition it was
`chinese 227/232, pali 122/150, tibetan 21/64` — Tibetan **down 4**, twice the documented
ANN wobble.

The cause was a join, and it is the fourth time this exact join has been written wrong
here. Measured:

    derge.D   30,653 range-anchored        0 exact-anchored
    sc.ms          0 range-anchored  210,756 exact-anchored

84000 anchors a rendering to a folio **range**; SuttaCentral anchors one to a **segment
id**. A join written on `anchor_urn = segment.urn` therefore scores **100% of Pāli and 0%
of Tibetan** — and it did not merely fail to help Tibetan. Tibetan queries retrieve Pāli
candidates too, and only those were scorable, so **the reranker promoted the Pāli above the
correct Tibetan answer**. Completing the join took Tibetan from 21 to **31** — past its
25-case baseline, because now it is scored rather than displaced.

**The lesson is about the scorecard, not the join.** A +36 aggregate would have shipped a
mechanism that quietly ranked one canon above another as an artifact of which anchor form
the author happened to have in mind. For a project whose fourth invariant is that a
Japanese commentary must never be presentable as an Indian sūtra, silently reordering the
traditions is the more serious defect, and the aggregate could not see it. **Cross every
headline number with tradition before believing it** — which is exactly what #42 concluded
when `topical/chinese` 0% and `chinese-native` 100% were invisible in both margins.

### The reranker verdict was right about Tibetan and wrong about the system (#10)

The section below concluded "Tibetan's problem is RECALL, not order" and demoted the
reranker on that basis. The measurement was sound and the generalisation was not: it was
taken over 64 Tibetan cases and applied to a retrieval metric that is **150 Pāli cases**.
Pāli had never been probed. It is now, and it fails the opposite way.

| | **Pāli (150)** | Tibetan (64) |
|---|---|---|
| gold at rank ≤ 10 | 82 (54.7%) | 24 (37.5%) |
| **gold at rank 11–200** | **44 (29.3%)** | 9 (14.1%) |
| gold absent from 200 | **24 (16.0%)** | 31 (48.4%) |

**Tibetan cannot be reranked and Pāli can.** Half of Tibetan's gold never enters a
200-candidate pool, so no reordering reaches it. Pāli's gold is retrieved **84% of the
time** and simply sits too low: mis-ranked gold sits at 11, 11, 12, 13, 13, 13, 14, 15,
15, 16, 17, 20, 21, 24 … median **37**, and 30 of the 44 are at rank 62 or better.

**A perfect reranker takes `retrieval/pali` from 82/150 to at most 126/150** — **+44
cases**, against +9 for Tibetan. Overall retrieval would go 334/446 → up to 378/446. That
is the largest single gain available anywhere in the system, and it needs **no training**:
a cross-encoder over the top 50–100 is an off-the-shelf model.

**Why the earlier conclusion inverted the priority.** Tibetan is the weakest language, so
it drew the attention; but it is 64 cases against Pāli's 150, and the thing that helps it
(a better embedder — recall) is the expensive, uncertain option that already failed once as
a LoRA. The thing that helps Pāli (a reranker — ordering) is cheap and untried. The
sentence "a reranker first, then a Tibetan-fine-tuned embedder" was reversed on Tibetan
evidence, and reversing it back is correct for the corpus as a whole: **rerank for Pāli,
embed for Tibetan, and they are different problems needing different tools.**

This is the fourth instance today of a ratio or conclusion measured on one workload and
applied to another (rule 37), and the first where the error was in a *published
conclusion* rather than an estimate.

### What a reranker could actually fix (#10) — 14%, and half the misses are unreachable

The standing plan was "a reranker first, then a Tibetan-fine-tuned embedder". Before
building one, the cheap question: **a reranker reorders the candidate pool and cannot
introduce a passage retrieval never returned — so is the right answer in the pool?**
All 64 `retrieval/tibetan` cases, probed to depth 200:

| | cases | |
|---|---|---|
| gold at rank ≤ 10 | 24 (37.5%) | already a hit |
| gold at rank 11–200 | **9 (14.1%)** | **everything a reranker could fix** |
| gold absent from 200 | **31 (48.4%)** | **recall failure — no reranker helps** |

Mis-ranked gold sits at ranks 12, 14, 14, 17, 28, 30, 48, 177, 194 — median 28, and two
of the nine are barely in the pool at all.

**A perfect reranker takes `retrieval/tibetan` from 37.5% to at most 51.6% at this depth,
and cannot touch the other half.** That is a real gain and a bounded one, and it is not
where the constraint is: **nearly half of Tibetan retrieval never surfaces the right
passage in two hundred candidates.** Recall is the problem, so the fine-tuned embedder —
which changes what gets retrieved — is the higher-value work, and the order in the bullet
above was backwards. #10 already established that a Tibetan LoRA must be judged on the
gold set rather than on proxies; this says which metric it has to move.

**An unexpected second reading, NOT yet a claim.** The eval scores these same 64 cases at
**31.3% (20/64)** using `limit: 20`, which makes Hybrid's over-fetch depth 60. This probe's
own top ten, at depth 200, holds **24**. Same cases, same `covers?/2` rule, +4 cases from
retrieval depth alone. That is above the documented one-case ANN wobble but not far enough
above it to bank, and it is consistent with #43's finding that a wider scan returns better
neighbours rather than merely more of them. It needs a gold-set run at a configurable
depth before anyone believes it — the #10 rule applies to encouraging probes too, and this
is one.

### The gold set was too blunt to decide with (#14) — 249 → 1,400 cases

Two questions in one session came out undecidable, both for the same reason:

- **The 320-vs-512 window.** 6.3% of Pāli chunks were truncated. Against 20 Pāli cases
  that is an expected effect of **~1.26 cases**. The eval could not resolve it, so the
  question was settled on principle rather than measurement.
- **The Tibetan LoRA.** `retrieval/tibetan` moved 7/20 → 8/20 on one index rebuild and
  7/20 → 5/20 on another, **with nothing changed that could touch Tibetan**. HNSW is
  approximate, and Tibetan sits at 0.9727 mean pairwise cosine, so its candidates are
  near-ties that resolve arbitrarily. On 20 cases a ±2 swing is ±10%.

And the LoRA established that for a retrieval change the gold set **is** the decision, not
confirmation of one made on proxies. An instrument that decides has to be able to.

`mix pramana.evals.derive --per-type 300` — the mechanism already existed, capped at 40:

| type/tradition | before | after |
|---|---|---|
| retrieval/pali | 20 | **150** |
| retrieval/tibetan | 20 | **64** |
| retrieval/chinese | 35 | 232 |
| citation_guard | 81 | 601 |
| provenance | 40 | 300 |
| **topical (all four)** | **49** | **49** |
| **total** | **249** | **1,400** |

That 6.3% effect now implies ~9.5 Pāli cases instead of 1.26, and the ±2 Tibetan rebuild
swing falls from 10% of the metric to 3.1%. **Not padded**: the 64 Tibetan cases span
**65 distinct works**, one case per work, so they measure the language rather than a
handful of texts.

**`topical/*` did not grow and cannot.** Its cases come from a curated doctrinal-term list
that rejects terms as *too common to measure* — སྟོང་པ་ཉིད occurs in 20,500 segments, so
"was it found" carries no information. `topical/tibetan` stays at 9 and `topical/chinese`
at 12. Those are the hardest and most valuable questions in the set — a real question
rather than a translator's own words — and they remain statistically undecidable. Growing
them needs more curated terms that are specific enough to test, which is scholarship, not
a parameter.

**The new baseline, and what it shows.** 1,400 cases, **89.4% (1252/1400)**:

| | old (n) | new (n) |
|---|---|---|
| retrieval/pali | 55.0% (20) | **53.3% (150)** |
| retrieval/tibetan | 35.0% (20) | **31.3% (64)** |
| retrieval/chinese | 97.1% (35) | 97.8% (232) |
| provenance/chinese | 100% (40) | 100% (299) |
| topical/* | unchanged | unchanged |

The old figures were **noisy estimates**. Pāli's true rate is nearer 53% than 55%, and
Tibetan's nearer 31% than 35% — both old numbers sat inside their own sampling error,
which is exactly the condition that made #10 and #11 undecidable.

**89.4% is NOT an improvement on 79.5%.** The mix changed: near-perfect categories
(citation_guard, provenance) went from 121 of 249 cases (49%) to 901 of 1,400 (64%), so the
average rose while nothing got better. The two numbers measure different sets and must
never be compared. Any published figure needs the case count beside it.

**The runtime is 62 minutes of CPU, and the wall clock is unknown.** The first run read
8h20m wall, but **the laptop slept during it**, so that figure is an artifact rather than a
measurement and is not a basis for planning. CPU time is the number that survives a
suspend: 62 minutes, against ~5 minutes wall for the old 249 cases.

Two costs sit outside that CPU figure. The semantic cases went 75 → 446, each a query
embedding plus a filtered HNSW search over 617,038 vectors. And every search also runs
`Semantic.coverage/1`, a `SELECT count(*) ... DISTINCT ON` measured at **~1.1 s**, which is
database time and appears in neither the CPU total nor anyone's intuition — it lives inside
a correctness feature, so nobody looks at it. Across 1,400 cases that alone is ~26 minutes.
This line used to end "Worth caching: the figure depends on the corpus and the filters, not
on the query text." **`semantic.ex` argues the opposite at the call site, and it is right:**
the number exists so an empty result cannot be mistaken for a small canon, and a stale
cache reports a corpus fuller than it is — while embedding state changes *without* a
re-bake, so `bake_id` is not even a sound cache key. The ~1.1 s is real and still worth
attacking; the semi-join already took it from 1,224 ms to 921 ms. Caching is the wrong
attack, and two documents disagreeing about it is how a correctness feature gets optimised
away by whoever reads only one of them.

(Two earlier estimates here were wrong and are corrected: 45 minutes, extrapolated from the
case-count ratio, and 8h20m, taken from a wall clock across a sleeping machine.)

### A Tibetan LoRA that every proxy said worked, and the eval said did not (#10)

Trained on the 30,607 folio pairs below: LoRA on attention projections only, 2.36M of
570M parameters (0.41%), InfoNCE over in-batch negatives, 2 epochs on an L4 for ~$0.80.
Pooling, normalisation and `MAX_LENGTH` copied verbatim from `modal_embed.py` — a vector's
meaning comes from how token states are reduced, so training with one and serving with
another produces a worthless adapter and nothing fails.

**The base model could not match a Tibetan folio to its own translation.** On 500 held-out
pairs, at batch 24 where chance is 0.042:

| | top-1 | MRR |
|---|---|---|
| base | **0.044** (= chance) | 0.162 |
| adapted | **0.148** | 0.327 |

**And the discriminative test says the same, harder.** Adjacent chunks of one work are
related text; a chunk from elsewhere is not. The gap between them:

| | base | adapted | |
|---|---|---|---|
| bo | **+0.0098** | **+0.1883** | 19× |
| pli | +0.0693 | +0.1405 | 2.0× |
| lzh | +0.0845 | +0.1903 | 2.3× |

The base rated an adjacent Tibetan chunk at 0.984 and an unrelated one at 0.974 — a **1%
gap**. That is the 0.9727 clustering finding in the terms that matter. Chinese and Pāli did
not merely survive training on Tibetan; they roughly doubled, which is consistent with
in-batch negatives teaching dispersion generally.

**It took three probes to earn those numbers, and the first two were wrong.**

1. **Mean pairwise cosine only** — every language "improved" (bo 0.974→0.556, pli
   0.838→0.651, lzh 0.804→0.656). But that measures **dispersion, not discrimination**: a
   random projection would score beautifully and retrieve nothing. That all three moved
   nearly equally, when only Tibetan was trained, was the tell.
2. **Discrimination, silently broken** — `PeftModel.from_pretrained` injects the adapter
   into the base **in place**, so holding a "before" and an "after" reference compares one
   model with itself. It printed three confident `KEPT` verdicts with `rel`, `unrel` and
   gap identical **to four decimal places**. Only the impossible precision gave it away.
3. **Fixed with `disable_adapter()`** — the table above.

The margin metric reported during training (−0.0247 → −0.0479) moved the *wrong* way while
top-1 tripled. Contrastive training at temperature 0.05 sharpens the model, so when it is
wrong it is now more confidently wrong, and a **mean** margin conflates sharpening with
correctness. Top-1 and MRR are the trustworthy figures; the margin was mis-specified and a
median would have been the right choice.

Adopting the adapter means re-embedding **everything** — a fine-tuned model is a different
model, and mixing two in one index is what `embedding_model` exists to prevent. Renaming
`@model` to `BAAI/bge-m3+pramana-tibetan-lora-v1` flipped all 617,038 vectors to
outstanding automatically, which is the guard working unprompted. The adapter is
`merge_and_unload`-ed into the base weights at fp32 before the fp16 cast, so inference runs
the same code path as the stock model and costs the same: **144 chunks/s against a
historical 147**.

**And then it failed, completely.** On the gold set, against the real corpus:

| | adapted | baseline |
|---|---|---|
| **overall** | **70.7%** (176/249) | 79.5% (198/249) |
| **retrieval/tibetan** | **0.0%** (0/20) | 35.0% (7/20) |
| **retrieval/pali** | **5.0%** (1/20) | 55.0% (11/20) |
| topical/pali | 31.3% (5/16) | 56.3% (9/16) |
| topical/chinese-native | 91.7% (11/12) | 100.0% (12/12) |
| retrieval/chinese | 97.1% (34/35) | 97.1% (34/35) |

**Tibetan went to zero.** The language the adapter was trained for lost every case it had
been winning. Reverted to stock and the corpus re-embedded.

## Why every proxy lied

This is the finding worth keeping, and it cost ~$2.60 to buy:

| measurement | verdict | scope |
|---|---|---|
| in-batch top-1 | 0.044 → 0.148 (3.4×) | 24 candidates |
| held-out MRR | 0.162 → 0.327 (2×) | 24 candidates |
| discrimination gap, `bo` | +0.0098 → **+0.1883 (19×)** | adjacent vs random chunk |
| **gold-set retrieval** | **35% → 0%** | **617,038 competitors** |

A **19× improvement in separating related from unrelated passages produced zero correct
retrievals.** The proxies measured pair-matching among two dozen candidates and local
geometry between neighbouring chunks. Retrieval ranks against six hundred thousand.
Training with in-batch negatives at temperature 0.05 taught the model to separate small
sets while destroying the global structure corpus-scale ranking depends on — the classic
shape of optimising the training objective rather than the task.

The damage was not uniform, and the pattern is diagnostic: `retrieval/chinese` held at
97.1% while Tibetan and Pāli collapsed. Chinese eval cases lean on lexical and
phrase-anchored matching; the languages that fell are the ones whose cases actually depend
on the vector space.

**Three probes were built to avoid exactly this, and none of them caught it.** The first
measured dispersion rather than discrimination (a random projection scores well and
retrieves nothing). The second compared the adapted model with itself, because
`PeftModel.from_pretrained` injects in place — it printed identical numbers to four
decimals and three confident `KEPT` verdicts. The third was correct, honest, and still
predicted the opposite of what happened. **No proxy available here can substitute for
running the eval against the real index.** That is now the rule: for a retrieval change,
the gold set is not confirmation of a decision already made on proxies — it *is* the
decision.

**Rollback confirmed.** Re-embedded with the stock model and re-scored: **78.7%
(196/249)** against the 79.5% baseline, with **seven of the eight categories
bit-identical** — provenance/chinese 40/40, retrieval/chinese 34/35, retrieval/pali 11/20,
topical/pali 9/16, topical/chinese-native 12/12, and both zero categories unchanged. Only
`retrieval/tibetan` differs, 5/20 against 7/20.

Two cases, and it is almost certainly **HNSW rebuild noise rather than an incomplete
restore**. The index is approximate, so a rebuild produces a different graph, and there is
a precedent from this same session: during the 512-window experiment `retrieval/tibetan`
moved 7/20 → 8/20 from a rebuild alone, with no change that could touch Tibetan. It moved
by one then and by two now.

That instability is itself a finding, and it points back at the same defect: **Tibetan
retrieval is unstable under index rebuild BECAUSE its vectors are the worst-separated in
the corpus.** At 0.9727 mean pairwise cosine the candidates are near-ties, and near-ties
resolve arbitrarily under approximate search. The 20-case gold set cannot distinguish a
±2 swing from a real change, which is the same statistical thinness that made the
320-vs-512 window question unresolvable.

What is kept: the adapter, `modal_train_tibetan.py`, `modal_probe_adapter.py`, and the
30,607-pair training set. What is discarded: the vectors. A future attempt should train
against corpus-scale negatives — mined from the index rather than from the batch — and
should treat any proxy gain as a hypothesis until the gold set agrees.

The architectural work the episode forced is kept too, and was worth having independently:
`Pramana.Embed` now separates what a vector **records** from where its weights **load
from**, and `build_serving/1` raises rather than embedding queries with weights that
disagree with the documents. Without it the eval above would have run stock queries against
adapted vectors and produced a number worth believing and entirely meaningless.

### The Tibetan training set is built, from data already here (#21)

BGE-M3 barely separates Tibetan (0.9727 mean pairwise cosine, below) and a cross-encoder
reranker scored it at *exactly chance*, so the embedder itself has to learn the language.
`mix pramana.tibetan.pairs` exports the training set — **30,607 pairs across 471 works**,
46 rejected — with no acquisition and no GPU.

**Folio-level, not chunk-level, and a measurement decided it.** 32,483 chunks carry both a
`source/bo` and a `translation/en` vector and look like ready-made pairs. They are not
used, because the English *overshoots*: a chunk's translation vector concatenates every
rendering overlapping the chunk, so it describes Tibetan outside the chunk's own span.

| pairing | bo median | en median | en/bo |
|---|---|---|---|
| chunk-level | 1,411 | 3,297 | **2.32** |
| folio-level | 1,515 | 1,721 | **1.14** |

That 2.32 is not English verbosity, it is over-inclusion. 84000 renders folio by folio, so
a folio's rendering corresponds to exactly the lines on it; chunk pairs additionally admit
up to half the Tibetan unrendered, since translation vectors are built at
`@min_coverage 0.5`. Folios are uniform physical units too (bo p90 1,630 against median
1,515), which is why the folio ratio band is so tight.

**Provenance is checked, not asserted.** Every pair carries the anchor it came from. On a
60-pair sample, **60/60 anchors resolve and 60/60 resolved spans contain the pair's own
Tibetan** — a training set whose provenance cannot be audited is the same problem as a
citation that cannot be verified. Spot-check of a pair at
`pramana:derge.D:toh127@55.155a.1-55.155a.7`: རྫུ་འཕྲུལ / "miraculous powers",
བྱང་ཆུབ་སེམས་དཔའ་སེམས་དཔའ་ཆེན་པོ / "bodhisattva mahāsattvas" — genuinely parallel.

**Hard negatives are deliberately not mined into the file.** They belong with the training
run, which knows its batch size and sampling strategy; baking them in fixes a choice that
should stay tunable. `work_id` and `anchor` are emitted so the obvious source —
same-work, nearby-folio Tibetan, the confusions that actually matter — is available.

One gap noted while doing this: `Pramana.Chunk.Vectors` computes a translation vector's
`coverage` and filters on it at 0.5, but does not persist it. Every existing pair is
therefore ≥50% covered by construction, and a 0.5 pair cannot be told from a 1.0 one.

### Tibetan n-grams were mostly one particle (#21) — the unit was wrong

`:ngram` is the recall fallback when a phrase finds nothing, and it windows the query by
**grapheme**, width 3. For Chinese that is right: a character is a morpheme, so `波羅蜜`
is pāramitā. A Tibetan grapheme is a *letter stack*, so the same rule cuts across the
tsheg. Windowing `སྟོང་པ་ཉིད` (śūnyatā) gave:

| window | segments matched (of 1,352,471) |
|---|---|
| `སྟོང་` | 82,903 (6.1%) |
| `ང་པ` | 267,757 (19.8%) |
| **`་པ་`** | **1,211,774 (89.6%)** |
| `པ་ཉི` | 149,136 (11.0%) |
| `་ཉིད` | 414,497 (30.6%) |

`་པ་` is the particle པ between two separators, and it is in **nine of every ten Tibetan
lines** — while the term itself is in 2.63%. Ranking counts how many distinct query terms
a passage contains, so the junk outvoted the signal.

Now the window is the **syllable**, width 2: `["སྟོང་པ", "པ་ཉིད"]` — 3.7% and 10.8%. The
worst window went from 89.6% to 10.8%, and the mean from 31.4% to 7.3%.

**No dictionary, deliberately.** This module already refuses jieba as the Chinese fallback
because it shatters transliterated Sanskrit and "a single common character appears on
nearly every line". `botok` is the same class of tool and this corpus is full of Tibetan
transliterations — `པྲ་ཛྙཱ་ཝརྨ` (Prajñāvarman) sits in a colophon. The tsheg is a
delimiter *the edition prints*, so splitting on it cannot mis-segment a name it was never
taught: `པྲ་ཛྙཱ་ཝརྨ` windows to `["པྲ་ཛྙཱ", "ཛྙཱ་ཝརྨ"]`. Windows also never cross a shad,
because the window is rejoined with a tsheg and searched as a substring — spanning a
clause break would fabricate a string the edition does not print.

That supersedes the plan to run `botok` in the Python sidecar, which would have repeated
for Tibetan the mistake already documented for Chinese.

### The Pāli chunk-size fix left 6.3% still truncated (#21)

Embedding runs with `truncation=True, max_length=320`. Pāli chunks were once 1,200
characters, at which **76.2%** exceeded the window — their vectors described a prefix
while the full text sat in the database, invisible in every count — and that was fixed by
shrinking Pāli to 700. Measured now with bge-m3's own tokenizer, 800 chunks per source:

| source | median | p95 | max | over 320 |
|---|---|---|---|---|
| cbeta | 279 | 292 | 298 | 0 (0.0%) |
| **sc (Pāli)** | 271 | **325** | **455** | **50 (6.3%)** |
| derge | 195 | 237 | 306 | 0 (0.0%) |
| derge-tengyur | 196 | 244 | 330 | 1 (0.1%) |

**The fix reduced the defect; it did not close it.** Pāli's p95 sits *above* the window, so
6.3% of its vectors still describe a prefix. Chinese and both Tibetan collections are
clean, which makes this Pāli-specific and rules out a corpus-wide re-embed.

Two remedies pull opposite ways: shrink Pāli chunks again (but the Pāli *topical* drop was
attributed to chunks being too small), or raise the window. The window was the option
never tested, so it was tested — `sc` only, 67,371 vectors at `max_length=512`, chunk
sizes untouched, imported with 0 rejections. Truncation went **50/800 → 0/800**. The cost
is measured too: **114.6 chunks/s at 512 against ~170 at 320, a 33% throughput loss**, and
it applies at query time as well since the query passes through the same window.

**Scored, and the answer is to keep 320.** With the index rebuilt over the 512 vectors:

| | now | baseline |
|---|---|---|
| retrieval/pali | **11/20** | **11/20** |
| topical/pali | **9/16** | **9/16** |
| retrieval/tibetan | 8/20 | 7/20 |

The window change moved the language it was meant to fix by **exactly nothing**. The one
overall gain (198→199) came from **Tibetan, whose vectors were never touched** — either
HNSW graph variation from the rebuild or Pāli vectors no longer displacing a Tibetan hit
in the shared ranking. Attributing it to the window would be a false causal claim from a
single flipped case in an approximate index.

**But "no change" is not "no benefit", and the reason is arithmetic.** 6.3% of chunks
truncated against **20 Pāli retrieval cases** is an expected effect of **~1.26 cases**.
This eval set cannot resolve that. The experiment was underpowered by construction, which
is a finding about the gold set — it needs Pāli cases that turn on the tail of a long
chunk — not a verdict on the window.

So the decision rests on principle, not the scorecard: two window configurations in one
index, with nothing in the schema able to tell them apart, is the defect filed as the
window/model gap below. Reverted to 320 — `sc` re-embedded and re-imported, 67,371
vectors, 0 rejected — and the 6.3% truncation is now a **measured and accepted**
limitation rather than an unexamined one. Revisit only with an eval that can see it, and
as a corpus-wide change rather than per-source.

**That gap is now closed.** `chunk_vectors.embedding_max_length` records the window each
vector was produced with, and the number comes from the **producer** — the GPU script
emits the `MAX_LENGTH` it actually used, and the importer stores that. Writing the Elixir
constant instead would have meant that changing `MAX_LENGTH` in the Python without
touching Elixir recorded a confident lie, which is worse than recording nothing. Three
guards go with it: a file mixing two windows is **refused outright** rather than
half-applied; a missing window stores `nil`, because unknown must stay unknown rather than
be guessed; and `Embed.pending_query/1` now treats a window mismatch as outstanding
exactly as it already treats a model mismatch. All 617,038 existing vectors backfilled to
320, `pending_count` 0.

The backfill itself demonstrated the runbook rule a third time: the migration exceeded
**600 s without finishing** through a live HNSW index, and completed in **36.8 s** with the
index dropped. Import, index build, backfill — same rule, three operation types.

**The gap as it stood before that fix.** `Pramana.Embed` treats a vector as
outstanding when its `embedding_model` differs, because "mixing vectors from two models in
one index silently corrupts search — every value is a valid float, so nothing would fail
loudly." The same is true of the **window**, and the schema does not record it: after this
run Pāli is at 512 and everything else at 320, with nothing able to tell them apart. It is
milder than mixing models (same model, same space) but it is the same class of silent
inconsistency, so it is filed rather than left to be discovered.

### Phase 5 data-integrity gate — all three checks green

Run after the Tengyur landed and after the phantom-line fix (`ccee8c7`):

1. **`mix pramana.verify`, whole corpus** — **OK, 15,489 texts, 30,723 segments**, body
   re-normalized from `raw/` and byte-identical for every one — including the Tengyur from
   its relocated `raw/derge-tengyur/` paths. A Tengyur-only run at `--sample 5` also
   passed (3,380 texts, 16,544 segments).
2. **`mix pramana.integrity`** — **OK, 15,489 texts.**

       source anchors:              6,573,295
       IR lines:                    6,573,295   (every anchor produced a line)
       lines with printed content:  6,538,238
       segments in the bake:        6,538,238   (every one is addressable)
       genuinely blank, skipped:       35,057
       gaiji reachable in segments:   128,393
       stranded on dropped lines:           0
       Derge byte census: 290,863,399 in the edition, 290,863,330 in the bake,
         difference 69 — volume 1's title page, which belongs to no Tōhoku number

   `lines with printed content` now equals `segments in the bake` exactly. That equality
   is what the phantom line was breaking.
3. **`Lockfile.verify/1` over every source** — all seven acquired sources OK (`84000` 406,
   `84000-rdf` 1254, `bdrc-derge` 103, `cbeta` 2471, `derge` 103, `derge-tengyur` 213,
   `sc` 7288); `sat` correctly `:not_locked`, never having been acquired.

Coverage reports 1,194 Kangyur and 3,380 Tengyur works, `tengyur_missing: false`, and the
only surviving caveat is Taishō 56–84.

4. **`mix pramana.evals`** — 79.5% (198/249), **identical to baseline in every category**.

   | | now | baseline |
   |---|---|---|
   | provenance/chinese | 100.0% | 100.0% |
   | retrieval/chinese | 97.1% | 97.1% |
   | retrieval/pali | 55.0% | 55.0% |
   | retrieval/tibetan | 35.0% | 35.0% |
   | topical/chinese-native | 100.0% | 100.0% |
   | topical/pali | 56.3% | 56.3% |
   | topical/chinese | 0.0% | 0.0% |
   | topical/tibetan | 0.0% | 0.0% |

   **Adding a third of the corpus diluted nothing.** 3,380 works and 145,194 vectors
   entered the index and no category moved — not guaranteed, given #43 measured 1,665
   gloss vectors displacing Pāli answers.

   **And the syllable n-gram change shows no end-to-end gain.** Its selectivity
   improvement is real and measured, but `:ngram` is the fallback *after* `:phrase` and
   these gold cases resolve or fail at the phrase stage, so the eval set never exercises
   the path that changed. That is a gap in the gold set — there are no Tibetan cases that
   reach the fallback — and not evidence the change was worthless. It is honestly an
   improvement to a mechanism, not yet a demonstrated retrieval win.

   The baseline independently corroborates two findings measured from scratch this
   session: Tibetan is the weakest language in the corpus (35% / 0%), matching the 0.9727
   embedding clustering; and `topical/chinese` is 0% against `topical/chinese-native` at
   100%, which is the same fact the reranker probe hit as `lzh: no aligned pairs` — an
   English question into Chinese has no English target to land on.

**No English->Chinese Buddhist term source exists in this repo**, checked three ways
while sizing #12: `glossary_entries` (84000) recovers 2 of 12 gold doctrinal terms and is
~97% harvested already (1,131 glosses carry Chinese, of 62,192; the database holds 1,105);
`glossary_terms` is 376 rows of Pure Land bibliography from `local-huang-nianzu-jie` and
holds 0 of 12; and only 165 of 2,471 Chinese works (6.7%) have a parallel to an
English-translated Pāli work. That is an acquisition problem, not a code one.

**Drop the HNSW index before any bulk vector import.** Measured twice on the same
67,371-vector import: **69 seconds** with the index dropped, **over 40 minutes** with it
live — and the rebuild afterwards took **2h44m** instead of ~23 minutes, because the mass
update through a live index bloats the table and the rebuild then grinds through it
alongside autovacuum. Correctness is never at risk; hours are.

**Validate a downloaded vector file before importing it.** Count the records and parse the
last line. A truncated download of this Pāli set had a perfectly valid last line, correct
1024 dimensions and a plausible 725 MB size, and was **3,257 records short** — importing it
would have left ~5% of Pāli stranded at the old window, invisibly, because the schema
cannot record which window produced a vector. Never run two downloads against one path
either: doing so produced line counts that *fell* between reads (64,114 → 37,578) and
bytes-per-line at twice the true value. A clean single download of this file takes **21
seconds**.

**Run these with the machine to themselves.** Four concurrent jobs exhausted the Postgres
connection limit during this session and the Tengyur pair took over two hours each under
contention, against ~90 minutes alone.

### The Tengyur names itself (#21) — no catalogue acquired

84000 catalogued the Kangyur and not the commentaries, so 3,380 works loaded addressable
only by Tōhoku number. The obvious fix was to acquire a catalogue — rKTs, BDRC, Adarsha —
with a new source, a new licence axis and a new lockfile entry behind it.

It was not needed. A translated Indian treatise opens by naming itself in both languages:

    ༄༅༅། །རྒྱ་གར་སྐད་དུ། བུདྡྷ་སྱ་སྟོ་ཏྲ་ནཱ་མ། བོད་སྐད་དུ། སངས་རྒྱས་ཀྱི་བསྟོད་པ་ཞེས་བྱ་བ།

*"In the Indian language: Buddhastotra-nāma. In Tibetan: …"* `mix pramana.tengyur.titles`
reads that formula and named **2,675 of 3,380 works** in 14 seconds: 2,629 (77.8%) with a
Tibetan title and 46 more — tantric works like toh1219, *Hevajra-maṇḍala-karma-krama-vidhi*
— that print only the Sanskrit, whose `title_original` therefore stays nil while the
Sanskrit is recorded in meta. 2,593 carry the Sanskrit alongside the Tibetan. The tally
counts those two claims separately, because reporting them together would say a work has a
Tibetan title when that field is empty. Spot-checks: toh4090 is
`chos mngon pa'i mdzod kyi bshad pa` — the **Abhidharmakośabhāṣya**; toh3824 is
`dbu ma rtsa ba'i tshig le'ur byas pa shes rab ces bya ba`, Nāgārjuna's
**Mūlamadhyamakakārikā**.

**This is better provenance than a catalogue, not merely cheaper.** A catalogue title is a
modern editor's identification. This is the title the edition itself prints, in the
translators' words, inside a public-domain corpus already byte-verified against `raw/` —
`source` attestation, the strongest class this project recognises. It is recorded as
`title_source: "derge-tengyur:incipit"` so it can never be confused with a catalogue's
reading, and the Sanskrit is stored as `title_sa_bo_script` because what the page shows is
Sanskrit *transliterated into Tibetan letters*, not Devanāgarī and not romanised Sanskrit.

**The 705 that do not name themselves get no title.** Toh 4346, the Mahāvyutpatti, is one
of them — it is a lexicon rather than a translated treatise, so it never uses the formula.
Guessing a title from the opening words would name every work and misname hundreds. No
English title is written for any Tengyur work either, because none is known; inventing one
is the same failure as inventing a citation id.

### BGE-M3 barely discriminates Tibetan (#21) — measured, and it bounds retrieval

The Tengyur is retrievable: a Tibetan query returns Tengyur and Kangyur works interleaved,
correctly labelled `source/bo`. But the scores looked wrong — ten *different* works at
0.97–1.0 — so the spread was measured directly, 20,000 random pairs per language:

| language | mean pairwise cosine | min | max |
|---|---|---|---|
| **bo** | **0.9727** | 0.786 | 0.998 |
| pli | 0.8397 | 0.689 | 0.944 |
| lzh | 0.8039 | 0.687 | 0.927 |

**A 0.98 between two random Tibetan chunks is normal.** The model packs Tibetan into a
narrow cone, so a 0.98 "hit" in Tibetan carries far less information than the same number
in Chinese, and ranking within Tibetan is weak even though recall is fine. This is not a
chunking or indexing defect — it is what BGE-M3 knows, and it bounds how good Tibetan
semantic search can get no matter how much of the canon is loaded.

It also names the highest-value model work in the project, and it is **not** a generative
model: fine-tuning the *embedder* on Tibetan. The training data already exists here —
30,653 folio-level 84000 renderings are aligned bo↔en pairs, plus 865 three-way
Skt–Tib–Chi anchors and the translators' glossaries. A better embedder changes what is
*found* and touches nothing about what is *citable*, so it costs none of the guarantees.
Cheaper first move: a cross-encoder reranker over the top 50, which needs no training at
all.

### The quotation graph (#22) — 141,073 verbatim reuses

A standalone Rust binary scans `texts.body` for runs of identical characters occurring in
two different works. **85.9M characters in about a minute**, 1.5 GB resident, and the
graph now holds **141,073 reuses across 1,301 works** — median 38 characters, longest
**746**.

The top results are exactly what a philologist would predict, which is the point: T2157
(貞元新定釋教目錄, 800 CE) reproducing T2154 (開元釋教錄, 730 CE) at 746 characters, and the
眾經目錄 catalogues sharing long blocks. Later Buddhist catalogues were compiled from
earlier ones, and the scan finds it without being told.

**Neither end is marked as the source.** Identical characters say nothing about who quoted
whom — that is a conclusion about dates and transmission — so the schema has an `a` end
and a `b` end, and every response says so. A tool that labelled one "source" would be
adding a claim the evidence cannot carry.

Two design decisions worth keeping:

- **Seed-and-extend, not a suffix array.** A suffix array would fit (2-3 GB) and give
  maximal matches directly. Seeds were chosen because they make the two decisions that
  actually matter explicit and tunable: the minimum length worth calling a quotation, and
  the frequency above which a string is boilerplate. That second knob is not optional
  here — 如是我聞 opens nearly every sūtra, and a method that cannot dismiss it drowns.
- **Emit only from the left edge of a match.** Every seed inside a shared passage would
  otherwise rediscover it, reporting one 200-character quotation as 189 of them.

**And a rule that was written down and then broken anyway.** `Pramana.Batch` now exists
because the Postgres 65,535-parameter limit was hit twice: a fixed 5,000 rows worked at
13 columns and failed at 18 in `Translations`, the lesson was recorded as rule 14, and
then a fresh 5,000 was written into `Quotations` for a 17-column table and failed
identically. A rule in a document does not survive being reimplemented; a shared function
does. Both call sites now derive the batch from the row width.

The full scan also exposed a resolver that loaded all 4.74M segments into memory to map
offsets — fine on a 155-work division, killed on the canon, *after* the scanner had
already done its job correctly, which made it look as though the scan had failed. It is
batched now.

### Task audit, 2026-08-16

Re-read every open task against what Phases 3-4 actually measured. Five changes.

**#44 created, and it blocks three things.** Tradition balancing: English vectors from
every tradition compete in one vector space with nothing keeping each reachable. Measured,
not suspected — 1,665 gloss vectors displaced Pāli answers. It now blocks **#21**
(Tibetan), **#26** (translation engine) and **#43 stage B**, because each of them adds
English vectors for another tradition and would compound a known defect.

**#21 Tibetan moved behind #44.** This is a reordering of the roadmap. Adding a third
tradition before the balancing mechanism exists means debugging interference across three
corpora instead of two, and the eval harness would report a decline it could not
attribute. #44 is small next to a canon ingest.

**#23 has an unmet prerequisite.** Translator fingerprinting is built on 異譯本 — alternate
Chinese translations of the same Indic original — and *nothing populates them*. The
relation vocabulary has a `parallel_of` slot and the corpus holds 90 `comments_on` and
nothing else. `Pramana.Compare` already documents this. Step 0 is asserting those
relations from catalogue metadata; the task now says so.

**#45 created: ship the apparatus as a tool.** `docs/COMPETITIVE.md` claims variant
readings as a differentiator, and **572,701 segments carry apparatus data** — but no tool
answers "how does this line differ across witnesses". A reader can only receive an
apparatus blob attached to a passage they already fetched. The claim was half-true and the
competitive doc now says so. This is deterministic, needs no acquisition, no tokens and no
vector space, so it is unaffected by #44 and can proceed in parallel — which makes it the
best thing to do while the balancing question is open.

**#41 dissolves into #14.** Three tasks are blocked on the same SAT reply. #41 (the
catalogue) has no separate source and would arrive with the text if access is granted;
#17 is a gate, not work. #14 is the only actionable item, and it is an email.

### The X ingest's six silent defects (B) — 2026-08-26

X landed at 1,230 texts with `verify OK` over 3,701 CBETA texts, and six things were
wrong underneath it. Four were invisible while the Taishō was the only CBETA collection
held, and **not one of those could fail a check that existed at the time.** The last two
are what `mix pramana.integrity` had to say, and the ingest had run `verify` only: the
check was crying wolf over 1,228 texts, and underneath that noise it was right about one.

**1. `embedding_coverage` reported 100.0% over a corpus 38% of which had no vector at
all.** X was baked and never chunked, and `Semantic.coverage/1` counted chunks:

    total: 560,238   embedded: 560,238   percent: 100.0
    unchunked: 1,230 texts, 4,068,303 segments

A text with no chunks is absent from the numerator AND the denominator, so it cancels out
of the ratio perfectly. The field exists so that partial data is never mistaken for a
small canon, and it was hiding a third of the canon. It now reports `reachable_percent`
(text-level), `unchunked_texts`, and a `note` in the shape `Pramana.Coverage` uses, so a
model cannot skim past it. **Counted over texts, not segments, deliberately**: the
segment-level query is 2.8 s against 96 ms and `Hybrid.run/2` calls coverage once per
search.

**2. Six works kept one of their two volumes — and WHICH one was decided by job
scheduling.** X0240, X0367, X0714, X0822, X1568 and X1571 each reuse one work number
across two volume files; `bake_all` ran one job per file and `Loader.load/2` replaces a
work's segments. The corpus had kept volume 8 of X0240 and volume 82 of X1571 — the first
and the second. **Two bakes of one `sources.lock.json` could therefore differ while
reporting one `bake_id`,** which is the only thing a `bake_id` is for.

The open design question — whether the anchors need rewriting — is answered, and the
answer is no. Measured across all six pairs:

    juan continues across the volume break   X08n0240 ends juan 44, X09n0240 opens juan 45
    juan+anchor collisions, all six pairs    0
    page-anchor collisions, X1571 alone      22,616

The URN carries the juan (`X0240_044@p0896b11`), so assembling changes no identifier and
creates no duplicate: 216,041 segments across the six, 216,041 distinct URNs. X1571 is
the one work where the *printed* locator is ambiguous — its two volumes repeat 22,616
page/register/line anchors, because page numbering restarts at each volume — so each
assembled line now carries `meta["volume"]`. **2,233,055 characters recovered.**

**3. Acquiring X deleted the Taishō from the lockfile.** `Lockfile.put_source/1` writes a
source entry whole, and CBETA is acquired one collection at a time:

    sources.lock.json, cbeta:  1,236 files, all X
    corpus, cbeta:             3,701 texts, T and X

**A corpus of 3,701 CBETA texts had a lockfile that could reproduce 1,230 of them.** That
is invariant 3 — *if a bake can't be reproduced from `sources.lock.json`, it's not a
bake* — and nothing anywhere reported it. `raw/` still held all 3,707 files; `verify`
re-derives from the file each text names on disk, so it passed; acquisition printed
success. `bake_id` had been computed over a lockfile describing a third of the corpus.
`Lockfile.merge_source/1` merges by path. A pin that has MOVED is decided by what the new
fetch covers: if it includes every path already locked the source really was re-acquired
and the entry is replaced, and if it does not the merge is refused — one entry listing
files fetched at two commits states something untrue about every one of them. The entry was repaired from the last commit that still held the T records — same
pin, `2b8ab8d5` — and re-hashed against `raw/`: **3,707 files, `{:ok, 3707}`**.

**4. A killed bake left its queue behind.** `bake_all` purged `completed` and `discarded`
jobs only, so the next run enqueued a second copy of everything still `available`: 1,468
jobs for 1,230 works. That is where the nine statement timeouts blamed on contention came
from, and it presents as a slow machine.

**5. The fidelity check had been crying wolf over 1,228 X texts.** It counts `<lb ` in
the raw body and compares against IR lines, and after the two-lineation fix roughly half
of every X file's `<lb/>` belong to the 卍續藏經 reprint and are correctly skipped:

    X0001: lb_lost — raw 46, bake 25       X0008: lb_lost — raw 16814, bake 8423

**The bake was right and the check was wrong**, which is the worse way round — a fidelity
check that cries wolf is a check that gets ignored, and this one had never been run since
X landed. The normalizer had counted the skips the whole time (`skipped_lb`, commented
"so that filtering everything away is a loud failure rather than an empty text") and then
discarded the number when it built the IR. It is now `IR.foreign_lb`, and the check
reconciles instead of comparing: every `<lb/>` in a CBETA body is either a line or a
skip. Over all 3,701 CBETA texts —

    raw <lb>     13,156,723
    IR lines      8,989,044
    foreign lb    4,167,679
    unaccounted           0   (0 texts mismatched)

**6. Underneath the noise, one real line.** With the reconciliation in place integrity had
exactly one complaint left — `X0575: line_unaddressable — raw 1756, bake 1755` — and it
was correct. The segmenter's blank test read `text: "", notes: [], apparatus: []` and
**omitted gaiji**, while `integrity`'s own definition of a printed line included them. A
line whose whole printed content is one rare glyph has empty `text`, because gaiji are
recorded as a mapping rather than substituted into the body, so it matched "nothing was
printed here" exactly.

That is the **third** time a not-blank line has been dropped here — note-only lines
(pipeline v2, 5,213 lines), `<note>` spanning `<lb/>` (v3, 10,590 lines), and now this.
The scale is different and the shape is identical: a definition of "blank" that lists the
kinds of content someone remembered. Corpus-wide it is **one line — X0575 0966b12, 䦚
(CB12059)** — and the Taishō has none, which is why the gate never saw it. Rare characters
are exactly the content a reader cannot reconstruct from anything else.

**The check that catches 2 and 3 now exists, and it is the general one.**
`mix pramana.integrity` gained a fourth check: a census taken from the lockfile **before
any parsing** — files → works → texts loaded. Checks 1–3 all begin at a text row, and
from inside a row a work that lost half of itself looks perfect. It reads
`cbeta: 3,707 file(s) -> 3,701 work(s) -> 3,701 loaded`, and it will fail the same way for
the next source whose works do not map one-to-one onto files, which is most of them.

`pipeline_version` → **4**. Dev pool timeout 120s → 300s: assembled X1571 is one
transaction of 74,570 lines against T1912's 26,000, and that file's own rule says a
timeout there is a capacity problem, never a data problem.

### The reader, first two screens (C) — 2026-08-26

`/` is a LiveView search and `/passage?urn=…` a LiveView passage view, both renderers
over the same domain functions the MCP surface calls. The Phase 8 note that the reader
should be "a renderer over an API that already returns spans, URNs and offsets" held —
but only after **three things were moved out of the MCP layer into the domain**, which is
the scope guard doing its job:

| moved | why it could not stay in a surface |
|---|---|
| `Provenance.group/1` | the reader and the tool would have described one bucket differently |
| `Retrieval.search/2`, `Retrieval.mode/1` | two surfaces routing `"semantic"` differently is one corpus answering a question two ways |
| `Lexical.known_opts/0` | so a dispatcher can drop `:coverage` before a phrase search — `Lexical` RAISES on unknown options, deliberately |

**The atom-table bug was walked into from the second surface.** `String.to_existing_atom("phrase")`
in the new LiveView raised on the first phrase search in a fresh VM and worked on every
one after, exactly as recorded for the MCP tool a phase ago — `:phrase` enters the atom
table only when `Retrieval.Lexical` loads. The literal map now lives in
`Pramana.Retrieval` where both surfaces reach it, with a regression test that runs a
lexical mode as its first search.

**What the page insists on, because each is an invariant that a UI can quietly drop:**
results bucketed by composition origin and role with each bucket named in words (#4);
URN and sha256 on every hit (#1, #2); both silences — what is not ingested and what is
not indexed — stated above the results, along with which retrievers actually ran.

Verified against the real corpus: searching 如是我聞 in phrase mode returns X passages with
byline provenance, a local source correctly flagged `edition_page anchor — not checkable
against a printed page`, and `pramana:cbeta.X:X0575_001@p0966b12` renders in context —
where the line two below it, `䦚通顯道甚深功德寶卷上`, shows what that recovered rare
character was doing: it is the first character of the work's own title.

### Versions on the page, and the collections gap (C) — 2026-08-27

The passage page renders `Compare.versions/2`: the whole translation pool, parallels, and
work-level alternates. SN 6.4 shows Sujato's English beside three parallels that reach
into the Chinese canon from one Pāli line — `T0100_006@p0412b07`, `T0099_044@p0324b03`,
`ja405@1.1` — which is the cross-canon claim this project exists to make, made visible.

Two things the page had to be taught **not** to say. A section with nothing in it is not
rendered at all, because a "Parallels" heading over an empty list asserts *we looked and
there are none*; `Compare.versions/2` returns `nil` rather than an empty structure for
exactly this reason, and the first version of this page rendered the explanatory note
under passages with no versions at all. And parallels pointing at texts not in the bake
are counted rather than dropped — T0099 has 1,958 recorded, 1,661 resolvable, and the 297
unopenable ones are stated, because a parallel we cannot show still tells a reader it
exists.

**`Coverage.cbeta/0`** closes the gap the X ingest opened. CBETA publishes **26
collections**; this bake holds two, and 24 collections / 1,298 works were absent with
nothing saying so — the Taishō 56–84 failure one level up, and invisible for two phases
because while the Taishō was the only collection loaded, "the Chinese canon" and "what we
have" were near enough the same sentence.

Counts are measured, from one git-tree call over the pinned repository at `2b8ab8d5` —
5,005 works, the same call `acquire_all` makes. **Most entries carry no name, deliberately.**
Each CBETA file states its own collection in `<sourceDesc>` (T: 大正新脩大藏經, X:
卍新纂大日本續藏經), and for a collection we have not acquired there is no such statement on
disk. Expanding `YP` or `GA` into a plausible canon name would produce exactly what this
project refuses: a reader unable to tell a sourced fact from a guess. A code and a work
count are facts; the name arrives with the files.

One existing test had to narrow rather than pass: *"issues no caveat, because there is
nothing to warn about"* asserted `caveat() == nil` for a corpus holding all 85 Taishō
volumes. That corpus still holds 1 of 26 collections, which IS something to warn about, so
the assertion now says what it was actually claiming — no *Taishō* warning.

### The work browser and the named apparatus (C) — 2026-08-27

`/works/:work_id` renders `Corpus.outline/1` and leads with provenance. The reasoning is
the one already written into that function: an outline is usually the FIRST thing anyone
sees about a text, so it is where a text gets misjudged, and without origin and role a
Japanese sectarian commentary and a Kumārajīva translation are indistinguishable — same
shape, same 品 headings, same juan count. T0099 renders 50 juan, 1,455 sections, 3,500
lines with variants, and its four candidate 異譯本 with shared-passage counts.

**The apparatus is served through `Apparatus.at/1`, which names witnesses from the text's
own header.** T0099_001@p0001a18 shows 【大】/【宋】/【元】. And the inline version on
neighbouring lines was rendering `meta["apparatus"]` directly, raw `wit="#wit1"` included —
caught in review, because `wit1` means 38 different things across the canon (宋 in 832
files, 明 in 375, 甲 in 322) and that module's own docs say a caller "must never be handed
`#wit1` as though it were a sigil". Neighbours now report that a variant exists; the named
form belongs to the line in focus, where the header has been consulted.

`Apparatus.count_for_work/1` was added to the domain rather than written as a query in the
view — a surface counting `meta ? 'apparatus'` for itself is a second definition of what
an apparatus is, and the fourth thing this reader has pushed back into the domain.

### `mix pramana.vectors` is the step between chunking and embedding — 2026-08-27

Chunking CBETA X produced 290,392 chunks in 98 s, and `mix pramana.embed.export` then
reported **`exported 0 chunk(s)`**.

Not a bug — a missing step, and one the runbook did not name. Chunking creates `chunks`;
the unit that gets embedded is a `chunk_vectors` row, created EMPTY and filled on import.
That ordering is what makes the sha256 round-trip possible at all: the row has to exist
before there is anything to re-check a returned vector against. `Embed.pending_query/1`
therefore looks for vector rows lacking an embedding, and a chunk with no vector row is
invisible to it.

**The failure reads as success.** `exported 0 chunk(s)` is exactly what a fully-embedded
corpus prints. `mix pramana.vectors --source cbeta` built all 290,392 rows in 29 s and the
export found them immediately. `docs/GPU_RUNBOOK.md` now names all three steps.

Also recorded there: **a `modal volume put` can stall silently.** 267 MB stopped at ~125 MB
with no error, no timeout and no output — the CLI prints progress to a TTY, so a
backgrounded run shows nothing and a stall looks exactly like a slow link. The byte counter
in `nettop -P -l 1 -x` is what distinguished them; the retry ran at ~700 KB/s and finished
in six minutes.

### Semantic search cannot say "I have nothing" (#19) — 2026-08-27

CBETA X embedded, the corpus re-gated, and `absence` fell from **100% to 25%**. Three of
the four cases were stale rather than failing; the fourth found something real.

**The three stale ones were testing a filter through the corpus's contents.** abs-001/2/3
were written as `expect_empty: true` under `origin: ["japanese"]`, premised on a sentence
that was true at the time — *this corpus holds no Japanese-composed work*. CBETA X brought
**145 of them**, and 唱題 now correctly returns X0967 教觀撮要論. The cases flipped to
failing on an ingest that made the corpus MORE complete, which is a test measuring the
wrong thing.

They now use `expect_origin: ["japanese"]`: every hit must carry the origin the query
asked for. That keeps exactly the teeth the cases were written for — abs-003's note says
"a filter that silently does nothing returns THOUSANDS of hits here" — and survives any
future ingest, because it tests the filter rather than the inventory.

**The fourth is a real limitation, and it had been invisible.** 本門戒體 is a Tendai
doctrine no text in this bake discusses:

    lexical (phrase, origin: japanese)   0 hits
    hybrid                               5 hits, retrievers: ["semantic"]
      X1164 淨土十要      將涉無生之龍津…
      X0956 山家義苑      …今此戒體，初心便可發之…      (戒體, not 本門戒體)
      X1244 百丈清規證義記  …當依佛語。以戒為師…

The lexical arm refuses correctly. **The semantic arm cannot refuse at all** — it returns
its k nearest neighbours regardless of how far away they are, and there is no distance at
which it declines. Nothing here is an answer; they are the closest Japanese-composed chunks
in the space.

**This case passed for two phases for a reason unrelated to the system working.** The
origin filter yielded an empty candidate pool because no Japanese-composed work existed, so
there was nothing to rank and "empty" came for free. X gave the filter something to admit
and the pretence ended.

`Pramana.Evals`'s own comment on this case type reads "This is the case type that most
projects have no answer for at all." Neither did this one; it looked like it did. For a
project named after the study of valid knowledge, a retrieval layer that cannot express
ignorance is the sharpest gap on the board — see `docs/PLAN.md` for the item.

The baseline records `absence` at 75%, not 100%. That is the honest number, and the ratchet
still catches a further drop.

### What the ignorance probe measured, and the hypothesis it killed — 2026-08-27

48 queries, before any code: 40 with known answers (20 Chinese definitional, 20
English→Pāli/Tibetan) and 8 with none.

    top-1 similarity      min      max
      answerable         0.7188   0.9223     Chinese 0.72–0.80, English 0.76–0.92
      unanswerable       0.6042   0.7423
    gap (top1 - top10)
      answerable         0.0077   0.0957
      unanswerable       0.0055   0.0358     6 of 8 INSIDE the answerable range

**The prediction registered before the run was wrong, and it was wrong in an instructive
direction.** It said a global absolute threshold could not work (BGE-M3's scale is
per-language — 0.9727 mean pairwise cosine in Tibetan against 0.84 in Pāli) and that the
signal would live in the *shape* of the neighbourhood, since "measure discrimination, not
dispersion" is what the Tibetan adapter probe taught.

Half right. The scale IS per-language — English queries sit a whole band above Chinese
ones, which is visible in the table. But the gap does not separate at all: `photosynthesis
in C4 plants` spreads wider than 13 of 20 answerable Chinese queries. **A lesson that was
correct for judging an embedder did not transfer to judging a query**, and the only way to
find that out was to measure it rather than reason from the earlier finding.

**The absolute number does separate, and is still not shippable as a gate.** 0.75 is the
lowest cut admitting none of the unanswerable set, and it refuses 4 of 40 answerable
queries — 10%, ~45 of 446 retrieval cases, to gain 1 absence case. Refused on cost, and
recorded in the rejected table so nobody re-derives it.

So the system REPORTS: `semantic_confidence` carries the top similarity and a band on
every hybrid response, in the MCP payload and above the reader's results, in the same
shape as `retrievers` and `embedding_coverage` — state the fact, let the caller weigh it.
`nil` when the semantic arm did not run, because "no model was loaded" and "the model
found nothing close" are different facts and only the second is about the corpus.

**The second signal was then measured, and it is one-way.** `lexical_support` alone is
useless — zero for every English→Tibetan query, so it detects the query's script rather
than the corpus's ignorance. Combined with the band, over 56 queries through the shipped
path: fires for **6 of 10 unanswerable** and **0 of 46 answerable**, paraphrases included.
Reliable when it appears, silent otherwise. Four unanswerable queries escape — three by
incidental n-gram overlap, and 如何申報所得稅 (*how do I file income tax*) because the
semantic arm puts it in `strong` outright, which is the sharpest possible argument against
ever promoting the band to a gate.

**The first version of that measurement was wrong, and wrong in the flattering direction.**
It called `Lexical.search/2` in phrase mode instead of going through `Retrieval.search/2`,
and reported 8 of 8 rather than 6 of 10 — because the hybrid's lexical arm falls back to
character n-grams and the component does not. 眾生皆能成佛 scores 0 phrase hits and 28
n-gram ones. **Three separate proxies flattered a signal in a single day**: the gap
statistic, the subset sweep's runtime, and this. Rule 47 is about registering predictions;
this is its companion — measure the path that ships, not the piece you can call quickly.

**abs-001 stays red, deliberately.** Reporting is not refusing. Closing it means
suppressing results, and suppression costs ~45 retrieval cases at the only threshold that
separates.

### The stubborn `retrieval/chinese` misses are a gold-set problem — 2026-08-27

The backlog carried "`retrieval/chinese` has 5 stubborn misses out of 232 and has not
moved all year. Cheap to diagnose now that a search is 2.2 s; nobody has looked." Looked.
After X the count is 9, and they split into two unrelated groups.

**Seven are X displacement**, which is expected and legitimate: X is overwhelmingly
commentarial and a commentary quoting a definitional formula is a genuine lexical match
for it. Of the top ten hits, X holds 6, 7, 8, 6, 6, 4 and 2 respectively.

**Two have no X in their top ten at all** — def-062 and def-082, and these are the
original stubborn ones. Both return a **correct answer the gold set did not ask for**:

    def-062  云何為一法   expects T0765_001@p0667a27
      rank 3  T0125_001@p0552c20   「云何為一法？所謂念法，當善修行…」

    def-082  云何為十一   expects T0125_046@p0794a18
      rank 3  T0125_046@p0795a26   「云何為十一？所謂阿練若：乞食，一處坐…」

def-062 finds the Ekottarika Āgama defining 一法 in the canon's own formula, at rank 3,
and is scored a miss because the case pins the 本事經 instead. def-082 finds the same
formula defining 十一 **in the same work and the same fascicle**, about a page from the
pinned line, and is scored a miss for that.

**These are enumerative formulae.** 云何為一法 and 云何為十一 recur throughout the Āgamas by
construction — the texts are lists — so there is no single correct answer to pin, and no
ranking change can make the system prefer one occurrence of a recurring formula over
another equally correct one.

**So `retrieval/chinese` has a ceiling below 100% that is not the system's fault**, and
tuning aimed at those cases is chasing something unwinnable. That is a second, independent
reason the configuration sweep was the wrong thing to spend five hours on.

**Deliberately not fixed here.** The harness already supports several accepted answers —
`expect_urns` is a list — so widening these cases is a one-line change. It is not made,
because widening a gold case makes a number go up, and that is indistinguishable in shape
from explaining away a regression. The absence cases were corrected today for a premise
falsified by an ingest, which is a different thing from a case that is valid but narrow.
This one is a judgement about what the eval should measure and it belongs to a human.

### The gate over 17,004 texts — 2026-08-27

`mix pramana.gate --from verify`, after J:

    verify --all     17,004 texts, 11,519,879 segments, 26m05s
                     body re-normalized from raw/ and byte-identical for every text

    integrity        13m39s
      source anchors            15,789,259
      IR lines                  11,621,580
      another edition's lines    4,167,679   (skipped, not lost)
      lines with printed content 11,519,879
      segments in the bake       11,519,879   (every one addressable)
      gaiji in raw body            231,631
      gaiji reachable in segments  222,763   (repeats collapsed per line)
      stranded on dropped lines          0

      cbeta: 3,994 file(s) -> 3,986 work(s) -> 3,986 loaded
        8 works span volumes: JB271, JB277, X0240, X0367, X0714, X0822, X1568, X1571

**That census line is the one worth reading.** This morning it read 1,236 files against
1,230 works and six works had each silently lost a volume. It now reconciles across two
collections and eight spanning works, and the two J works it names — JB271 and JB277 —
were caught *before* the bake by a check that did not exist twelve hours ago.

`verify --all` at this scale is 26 minutes, which is the expensive half of the gate and
the half worth paying for: the sampled run checks 1,000 segments per text, and only the
full one can prove the sentence it prints.

### J changed nothing, and the prediction that it would was wrong — 2026-08-27

Registered before the run: *"`retrieval/chinese` drops again, because J is almost entirely
commentarial and definitional formulae now match still more commentaries quoting them."*

    overall            93.1%   ->  93.1%
    retrieval/chinese  96.1%   ->  96.1%   (223/232)
    every other row    unchanged

**Identical. The gate passed.** So the X displacement was not the general law it looked
like — *more commentary makes Chinese retrieval worse* is not what happened.

What actually happened with X is narrower and more interesting. X is **1,230 works of
exegesis on the same sūtras**, quoting the same 云何為X formulae the definitional gold
cases search for, so it competed directly for those slots. J is 285 works of Ming and Qing
Chan material — a different genre asking different questions — and it barely touches those
formulae. Volume was never the mechanism; **genre overlap with the gold set was.**

That matters for what comes next. It means the answer to X's displacement is not "filter
every definitional query by role" applied globally, and it means the next collection's
effect on retrieval is predictable from what KIND of text it is rather than from how much
of it there is. B (大藏經補編) and ZW (藏外佛教文獻) are next by size and are both
miscellanies; N (漢譯南傳大藏經) is a Chinese rendering of the Pāli canon and would compete
with the Āgama material directly.

Caveat stated: J was baked and **not chunked or embedded** for this run, so it participated
in the lexical arm only. The post-embedding run measures the semantic half separately,
which is why the two were kept apart.

### HNSW is not stable under insertion, and Tibetan is where that shows — 2026-08-27

J embedded, index rebuilt over 966,931 vectors, gate re-run:

    overall             93.1% -> 93.4%   +3 cases
    retrieval/chinese   96.1% -> 96.6%   +1
    retrieval/tibetan   46.9% -> 50.0%   +2      <- not attributable to J

**The Tibetan gain is not being claimed.** 285 Chinese works cannot answer a Tibetan gold
question — those cases expect Tibetan URNs — so J did not supply the two new hits. Two
mechanisms can, and neither is J being useful:

1. **An HNSW rebuild is not deterministic.** The graph is built with randomisation, so
   the same vectors reindexed give slightly different approximate neighbourhoods.
2. **Adding vectors reorders results for queries that have nothing to do with them.**
   59,501 new Chinese vectors change the graph globally, and approximate search is
   approximate for everyone in it.

Tibetan is the tradition most exposed to both, and the reason is already measured:
**BGE-M3 packs Tibetan at 0.9727 mean pairwise cosine** against 0.84 for Pāli. Its
candidates are near-ties by construction, so a small perturbation of the graph reorders
them where Chinese and Pāli hold their positions.

**This invalidates the noise floor as previously stated.** The 1-case figure came from
running the identical configuration twice **against the same index**. It measures query
nondeterminism and nothing else. Any change that involves an index rebuild — every import,
every re-embed, every chunk-size experiment — carries a second and larger source of
variance that has never been measured.

**The experiment that would settle it:** rebuild the index over unchanged data and re-run
the gate. About 55 minutes, unattended, and it is worth more than the configuration sweep,
because until it is done every future claim of the form *"this change improved Tibetan by
two cases"* is unfalsifiable.

The baseline is updated to 93.4%, which is the true state of this bake. The Tibetan row is
recorded with this caveat attached rather than as a gain.

### The alternative editions are 23% volume-spanning, and one runs to four volumes

74 files acquired in a single download — the whole CBETA tarball is ~2 GB and fetching
seven collections separately would have downloaded it seven times for less material than
one Taishō volume. Read from disk before baking:

    K  10 files   9 works   高麗大藏經（新文豐版）    唐 玄奘譯
    A  12 files   9 works   趙城金藏               唐 慧菀述
    P  20 files  13 works   永樂北藏               宋 宗永集 元 清茂續集
    L  26 files  21 works   乾隆大藏經（新文豐版）    隋 智顗說、灌頂記 唐 湛然釋
    U   3 files   2 works   洪武南藏               唐 義忠述
    S   2 files   2 works   宋藏遺珍（新文豐版）      唐 詮明集
    M   1 file    1 work    卍正藏經（新文豐版）      宋 蘊聞錄

**13 of 57 works span volumes — 23%, against 0.5% in X and 0.7% in J.** That is not an
anomaly, it is what these collections are: CBETA has digitised a *selection* from each
edition, and what gets selected is the large multi-fascicle work. Every one of them would
have lost a volume under the pre-2026-08-27 loader.

**Three of them span more than two volumes, which `IR.concat/1` has never seen.** P1612
runs across three, and **L1557 across four**. The URN assumption was re-checked on the raw
files rather than assumed to generalise:

    L1557   4 volumes   104,959 lines   juan 1->17, 17->34, 34->51, 51->80
              anchor-only collisions  78,080
              juan+anchor collisions       0

Page numbering restarts at each volume, so the bare anchor collides seventy-eight thousand
times; the juan disambiguates every one. Note the boundaries **overlap** — volume 130 ends
in juan 17 and volume 131 begins in juan 17 — so the rule is not "each volume holds whole
fascicles" but "juan is monotonic and may straddle a boundary", and the absence of
collisions inside a shared juan is measured rather than argued.

`config/dev.exs` pool timeout 300s -> 600s in advance: L1557 assembles to 104,959 lines in
one transaction, 1.4x the X1571 load that forced 120s -> 300s. Raised from a measurement
taken before the bake instead of from a failure during it.

### The index rebuild moves the gate by six cases, over unchanged data — 2026-08-27

The experiment that had to be run, and the answer is worse than the guess. HNSW index
rebuilt over **completely unchanged data** — same corpus, same 966,931 vectors, same code,
byte-identical inputs — and the full 1,400-case gate re-run:

    overall             93.4% -> 92.9%    -6 cases
    retrieval/tibetan   50.0% -> 43.8%    -4 cases
    retrieval/pali      81.3% -> 80.7%    -1
    retrieval/chinese   96.6% -> 96.1%    -1

**Nothing changed except the graph.** An HNSW build is randomised, so reindexing the same
vectors yields different approximate neighbourhoods, and Tibetan absorbs most of it for a
reason already on record: BGE-M3 packs Tibetan at **0.9727 mean pairwise cosine** against
0.84 for Pāli, so its candidates are near-ties by construction and reorder under any
perturbation while the other traditions mostly hold position.

**What this retires.** The noise floor was published this morning as **1 case**, measured
by running the identical configuration twice against the identical index. That number is
correct and it measures only query nondeterminism. Across a rebuild the floor is **at
least 4 cases on `retrieval/tibetan` and 6 overall** — four to six times larger.

**What it does and does not invalidate**, stated precisely because the difference matters:

| kind of change | rebuilds the index? | floor |
|---|---|---|
| configuration — depth, rerank, `rrf_k`, balance | no | ~1 case |
| corpus or embedding — import, re-embed, chunk size | **yes** | ≥4 Tibetan, ≥6 overall |

So the configuration findings stand: per-arm depth, the reranker's +46, `balance:
:tradition`, `hnsw.ef_search` — none of those rebuilt the index. **The Tibetan claims
attached to corpus changes do not.** Today's own "J improved Tibetan by 2 cases" was
already refused on reasoning; it is now refuted by measurement, and refuted in the
direction of being smaller than the noise rather than larger.

It also means `retrieval/tibetan`'s recorded history — 48.4%, 46.9%, 50.0%, 43.8% — is one
number with a ±4-case band around it, not a trend.

**What was changed as a result.** `mix pramana.evals.compare --rebuilt` uses 4, measured,
and the proportional guard moved from 5% to 10% of a row because 4 cases on a 64-case row
is 6.25% and a 5% cap would have called a measured non-event a regression. The threshold
is set by the measurement rather than by a round number, and if a later probe measures a
wider swing it moves again.

**Still owed:** one rebuild is one sample. Four is a floor on the floor, not the floor, and
three or four rebuilds would give a real distribution. Until then, treat a Tibetan movement
under five cases across any corpus change as carrying no information.

### The alternative editions are not alternative witnesses — 2026-08-27

Stated twice today, written into `docs/PLAN.md` and a commit message: acquiring K, A, P,
L, U, S and M would turn the **572,701 segments carrying a variant apparatus** into
passages a reader could open, because those readings name 【宋】【元】【明】【麗】 editions
the corpus did not hold.

**Measured after baking: of 57 works, 2 share a title with anything in T, X or J.**

CBETA does not publish a parallel Koryŏ *text* of the Taishō's works. Its K is a selection
of what is **distinctive to** that edition — 高麗國新雕大藏校正別錄, the Koryŏ's own
collation record; 御製秘藏詮 and 御製逍遙詠, Song imperial compositions preserved there;
新集藏經音義隨函錄, a phonetic glossary. A is Song catalogue records (大中祥符法寶錄,
景祐新修法寶錄) and 趙城金藏 survivals. L is largely Ming-Qing Chan recorded sayings.

The error was reasoning from the *name* of a collection to its *contents*, which is the
same mistake as reading a two-letter code as a canon name — refused three hours earlier in
`Cbeta.Collections` for exactly this reason, and then made anyway one level up. A
collection called "the Qianlong Canon" containing 21 works is not the Qianlong Canon; it is
what CBETA chose to digitise from it.

**What this leaves open.** The apparatus gap is real and is not closable from CBETA:
opening a 【麗】 reading needs the Koryŏ text of *that Taishō work*, which is the Tripiṭaka
Koreana project — a new source with its own licence and citation grammar, not a collection
flag. Recorded as such rather than quietly dropped.

**What survives.** 57 works of rare material, much of it digitised nowhere else, and the
first exercise of `IR.concat/1` four volumes deep (L1557, 1,329,342 characters).

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
- ~~**Tibetan `botok`** has no Elixir/Rust equivalent, so the sidecar survives until at
  least Phase 5 regardless.~~ **Closed 2026-08-27, and it was never open in code.** Nothing
  imports `botok`; the syllable-window approach superseded it and four documents went on
  describing the dependency anyway — including `CLAUDE.md`, which a new session treats as
  binding and which was therefore standing invitation to add Python nobody needed. The
  sidecar's only remaining justification is the multi-vector question above.

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
9. **`on_conflict: :nothing` on a reference row makes it write-once.** Correcting
   bilara-data's licence from CC0 to Public Domain Mark in `Pramana.Sources` and
   re-ingesting all 8,442 works left the `sources` row still saying `cc0`, because the
   row already existed. `redistributable_only` filters by joining that row, so the
   registry was right and the thing making decisions was wrong. Any table that mirrors a
   declaration in code must replace on conflict, and a test must assert the row equals
   the registry after a load.
10. **A source's own LICENSE file is not the licence.** bilara-data's LICENSE.md says
    CC0 throughout; its `_publication.json` records Public Domain Mark for the Pāli root
    text and CC BY-SA 3.0 for the Patna Dhammapada. Licence belongs to the publication,
    never to the repository — check per publication before ingesting.
11. **A check constraint on an enumerated column is a contract with the registry.**
    Adding `public-domain` to `Pramana.Sources` without adding it to
    `license_class_known` made every insert fail. That is the constraint working: a
    licence class nothing enumerates is one no query can reason about. Extend the
    constraint in the same change as the registry.
12. **A test that hardcodes a value the registry owns will fight the registry.** Three
    licence-filter tests asserted `"cc0"` for a source and broke when the licence was
    corrected — inviting a "fix" that restores the wrong licence. Derive such values
    from the source of truth (`Sources.fetch!/1`) so the test checks the *behaviour*.
13. **When a column mirrors a claim someone else made, carry how confident you are
    separately from the claim.** bilara-data's publication ids do not always map onto
    the works they cover — `pli-tv-vi` is the whole Vinaya, not a prefix of
    `pli-tv-bu-vb-pj1` — so 66,199 renderings had no directly matching publication.
    `license_class` (what we believe) and `redistributable` (what we will act on) being
    two columns is what let those be held and searched under an inferred CC0 while
    staying unpublishable until confirmed. One column would have forced a choice between
    losing them and overclaiming.
14. **`insert_all` binds one parameter per column per row, so batch size is a function
    of row width.** A fixed 5,000 worked at 13 columns and exceeded Postgres's 65,535
    limit at 18. Derive the batch from `map_size(row)`; a constant reintroduces the
    failure the next time a column is added.
15. **A grouped query is not an aggregate.** `Repo.one` over `group_by … having count > 1`
    works while every group is unique and raises the moment a second row appears — which
    is exactly when the number becomes interesting. Count over a subquery.
16. **A convention can be the opposite of what it looks like — check before projecting
    it.** The glossary populates `pinyin` precisely when the target-language reading
    could *not* be established, and leaves it empty when it could (the reading then being
    in `canonical_english`). Reading it the obvious way recorded 元曉 as *Yuánxiǎo* under
    McCune-Reischauer, marked verified: the exact error the glossary exists to prevent,
    laundered into structured data. When importing from a curated source, verify what its
    empty fields mean.
17. **An optional dependency that silently halves a system is worse than a required
    one.** `Hybrid.search/2` ran semantic retrieval only when the caller passed
    `:serving`, so any caller that forgot got lexical-only results with the model loaded
    and idle in the same VM — no error, just worse answers. The MCP tool remembered; the
    eval harness did not, and scored 0/40 on retrieval that works. If a component can be
    absent, the presence of the thing itself should decide, not a caller's memory.
18. **A benchmark's first job is to be wrong in ways you can see.** Half the Pāli gold
    cases quoted text occurring in up to 15 places, and scoring against one arbitrary
    copy measured luck rather than retrieval — it would have published 27.5% where 37.5%
    was true. When ground truth might not be unique, expect the whole equivalence class.
19. **A session-level `SET` does not survive a connection pool.** `Repo.query!("SET
    maintenance_work_mem …")` followed by `Repo.query!("CREATE INDEX …")` checks out two
    connections: the setting applies to one that then goes idle, and the build runs at
    the default. Nothing errors — the index is built correctly, just an order of
    magnitude slower, which reads as "HNSW is slow" rather than as a bug. Measured on
    342,535 vectors: **~62k tuples/min inside one transaction, ~1.6k across two
    connections — 38×.** Any setting a statement depends on must share its transaction.
20. **A cascading delete can destroy work that cost money to produce.** `chunk_vectors`
    cascades from `chunks`, and re-chunking deletes a text's chunks before rebuilding
    them — so `mix pramana.chunk` would have thrown away 299,317 GPU-computed embeddings
    and reported success. The builder now refuses to rebuild a text whose chunks carry
    embedded vectors unless forced, and reports what it left alone. Before adding
    `ON DELETE CASCADE`, ask what the child rows cost to recreate.
21. **Positional query bindings break silently when a join is added in front of them.**
    The provenance filters read `[_c, _t, w]` — correct while the query was
    chunk-text-work, and pointing at the wrong table the moment a vector join went first.
    A filter reading the wrong column returns a plausible result set and raises nothing.
    Named bindings (`[work: w]`) cannot drift; use them anywhere a query is composed.
22. **A coverage figure's denominator is a claim about the corpus, not about the table
    you happen to be counting.** Moving vectors into their own table quietly changed
    "how much of the corpus is searchable" into "how many vector rows exist", so a
    chunked-but-unembedded corpus reported `total: 0` — "nothing to search" rather than
    "nothing embedded yet" — and a corpus with translation vectors for 2% of its chunks
    would have reported 100%. The denominator stays the corpus.
23. **A file is a packaging unit; the work is a citation unit.** `an1.1-10_root-pli-ms.json`
    holds ten suttas. Taking the work id from the filename collapsed ten distinct `1.0`
    segments onto one address — caught only by a unique constraint. Derive the work id
    from what the source *cites*, and where works do not map one-to-one onto files,
    record the file on the text (`meta["source_file"]`): without it `mix pramana.verify`
    cannot find the bytes to re-derive from, and a check that cannot run is not a check.
24. **A shared helper only helps if using it is easier than not.** The Postgres
    parameter limit was hit a fourth time after `Pramana.Batch` existed and after the
    lesson was written down twice, because `Batch.chunk/1` still left every call site
    free to forget — and an unbatched write path looks fine until the data grows.
    `Batch.insert_all/4` takes the same arguments as `Repo.insert_all/3` and cannot be
    called without batching. Wrap the dangerous call; do not offer a helper beside it.
25. **Proving absence is the expensive case for an index.** Checking 13,000 dictionary
    forms against the corpus with `LIKE '%form%'` measured 1.3 seconds *each* — the
    pg_bigm index is fast when a form is common and slow when it is missing, which is
    most of them. One streaming pass answered the same question in 2m11s. Index-per-item
    beats a scan only when the items are few.
26. **A `with` whose `else` discards everything turns a shape bug into an empty
    result.** A CC-CEDICT line matcher destructured four elements from a five-element
    `Regex.run` result; the catch-all clause swallowed every line and the build reported
    "0 entries" rather than raising. Where a fall-through means "skip this row", make the
    skip conditions explicit enough that a malformed *pattern* cannot masquerade as
    malformed *data*.
27. **Character data outside the text element is the library talking, not the book.** The
    Derge normalizer buffered every character event, so each volume's 416-byte
    `<publicationStmt>` distributor note became the first citable line of whatever work
    was running into that volume — 102 of 103 volumes, addressed by a URN that resolves.
    A normalizer's default should be to ignore text, and to buffer only where it has
    established it is inside the body.
28. **An idempotent loader makes assembly the caller's problem.** `Loader.load/2`
    replaces a text's segments rather than appending, which is what makes a re-run safe —
    and what makes loading a multi-file work once per file keep only the last file. The
    failure is silent in both directions: no error, and a text whose length looks
    plausible. Whenever the source's packaging unit is smaller than the citation unit,
    assemble first and load once.
29. **The closing check counts bytes, not units the parser defined.** Line counts,
    work counts and character counts are all downstream of how the parser decided to
    split things, so they agree with a wrong split. Non-whitespace bytes of character
    data inside `<text>`, counted by something that knows nothing else, closed the Derge
    edition to 69 bytes out of 290,863,399 — and named the 69 as the one thing dropped on
    purpose. If a fidelity check cannot state the difference exactly and explain it, it is
    not closed.
30. **A chunk size is a claim about a tokenizer, and an untested one fails silently.**
    The embedder truncates at 320 tokens, so a chunk that tokenizes longer is embedded
    from its opening while its text stays whole — no error, no count out of place, just a
    vector describing a prefix. 76.2% of Pāli chunks were in that state for two phases.
    Measure the size against the actual tokenizer, per script, and pin the numbers in a
    test.
31. **A benchmark that cannot see a tradition reports it as absent, not as bad.** The
    eval deriver's translation-anchor join was equality on a segment URN, so Tibetan —
    whose renderings are anchored to folio RANGES — produced zero cases, and the
    scorecard simply had no Tibetan row. A missing row reads as "not built yet"; a bad
    row reads as "built and weak". Before trusting a per-tradition number, check that
    the instrument can produce a case for that tradition at all.
32. **Refute the obvious explanation before acting on it.** Adding a third English layer
    coincided with a Pāli topical drop, and #44 had predicted exactly that mechanism —
    tradition competition. Measuring it took one script and refuted it: Tibetan held 1 of
    160 result slots. The second hypothesis, that the smaller chunk cut the term out of
    the returned window, died the same way — scoring over the chunk ± 3 segments gave the
    same 10/16. Two plausible stories, both wrong, and the cost of believing either would
    have been a redesign.
33. **A partial match between two editions is more dangerous than none.** 84000 numbers
    Toh 11's folios from the work's own start in its second volume, and 428 of those 610
    numbers exist in that volume of that work — so they anchor, resolve, byte-verify, and
    attach English to a passage it does not translate. A total mismatch is visible; a
    70% match looks like data quality. Where two numbering systems are being joined,
    accept or refuse a whole group, and pick the threshold from the measured distribution
    rather than from taste.
34. **`preload` through a join ships every column of the joined row, once per row.**
    Retrieval's `preload([_s, t], text: {t, [...]})` fetched `texts.body` — the entire
    normalized work, up to 13.3M characters — once per matched segment, to read a title
    and a licence class. Removing it made lexical search **32x faster** (1403 ms → 44 ms
    over five formulae, ABBA-verified). The idiomatic one-line form is the expensive one,
    it costs more the wider the joined table's widest column is, and the call site shows
    nothing. Use a separate preload query with `select: struct(t, [...])` — `struct/2`,
    not a `%Text{}` literal, which loses the binding and makes Ecto refuse the query — and
    test that the emitted SQL still names every schema field, because a column added later
    and not listed reads as `nil` with no error anywhere.
35. **Making a long run fault-tolerant is half the job; the other half is making sure the
    shrunken denominator cannot be read as a result.** One timed-out query took a 4h25m
    eval run with it, so `score_case/2` now rescues. But a rescued case is not a miss (that
    publishes a regression that did not happen) and not stale (that blames the gold set for
    our outage) — it is its own outcome, out of the denominator, printed loudly, carried in
    the JSON, and `--gate` refuses to run at all when any case errored, because missing
    hits would either trip the ratchet or *install* an under-measured run as the baseline.
    Whenever a loop learns to survive a failure, ask what the summary now claims.
36. **A tokenization rule is a rule about ONE script, and the `else` branch is where the
    next script goes to die.** This defect has now appeared three times in one module:
    jieba shattering Buddhist transliterations in Chinese, grapheme windows producing
    `་པ་` in 89.6% of Tibetan segments, and grapheme trigrams turning a 145-character
    English sentence into 135 predicates of `%the%` and `%er %`. Each time the unit was
    right for the script it was designed for and meaningless for the one that fell through
    to it. When a function branches on script, every branch must name the script it serves;
    `if tibetan?(q), do: syllables, else: graphemes` silently claimed Latin, Devanāgarī and
    everything else for a CJK tool.
37. **A speedup measured on one workload does not fix a timeout observed on another, even
    at the same line number.** `lexical.ex` was made 32x faster on Chinese phrase queries
    and the depth-120 timeout was declared fixed on that basis. It was not: the timeout was
    English n-gram fallbacks, which share the line and nothing else. The ABBA re-run that
    caught it cost 45 minutes; the claim had already been committed and written into
    STATUS. **Before crediting a fix with removing a failure, reproduce the failure.**
38. **`LIMIT` without `ORDER BY` turns a bad plan into an intermittent one.** A sequential
    scan under a limit stops as soon as it fills, so its runtime depends on where matches
    happen to fall in heap order — the same query is fast, slow, or fatal depending on the
    limit and the data layout. That is why this bug presented as "one arm in two dies" for
    three sessions rather than as a query that is simply slow, and why it was attributed to
    cache weather. An intermittent timeout under a limit is a plan problem until proven
    otherwise.
39. **When a planner abandons an index, the threshold is selectivity, not a count.** OR'd
    `LIKE` predicates dropped off `pg_bigm` at 25 on one query and at 10 on another; what
    differed was how common the terms were. A cap chosen from one query's cliff would have
    been wrong for the next. Cap by *rarity* (length is a free proxy) and verify with
    `EXPLAIN` across the whole gold set — 252 queries took seconds and turned a guess into
    a measurement.
40. **Profile the whole operation before optimising the part an error message names.** A
    `DBConnection` timeout stack trace pointed at `lexical.ex`, and a full day went into
    the lexical arm — a real 32x fix, a real n-gram defect, all of it sound. The lexical
    arm was **14 ms of a 41,169 ms search**. The stack trace named whichever arm held the
    connection when the pool gave up, not the one consuming the time; the semantic arm sat
    unprofiled underneath the entire investigation. One `:timer.tc` around each arm would
    have reordered the whole day, and it cost two minutes to run.
41. **A rule written after a fix does not sweep for the other instances.** Rule 34 was
    written the morning `texts.body` was removed from `Retrieval.Lexical`. By that
    afternoon the identical `preload([s, t], text: {t, ...})` was still live in three other
    call sites and a fourth as a `select`, one of them inside an N+1 running 120 times per
    search — together 38 of a search's 41 seconds. **When a defect is found, grep for its
    shape before writing the rule**, and prefer a shared function to a rule: `Pramana.Batch`
    exists because rule 14 was re-broken the same way, and `Text.preload_without_body/0`
    now exists for this one.
42. **A hand-maintained column list is a defect with a test, not a fix.** The first version
    of that preload listed every `texts` column explicitly, with a comment admitting the
    list was a drift surface and a test to catch drift. `__schema__(:fields) -- [:body]`
    needs neither: subtraction cannot go stale. When a test exists only to catch a list
    going out of date, ask whether the list should be derived instead.

43. **A source acquired in parts must MERGE into its lockfile entry, never replace it.**
    `put_source/1` is right for a source fetched in one pass and silently destructive for
    one fetched a collection at a time: acquiring CBETA's X dropped the Taishō's 2,471
    file records, and a corpus of 3,701 texts was left with a lockfile that could
    reproduce 1,230. Nothing failed — `raw/` was intact, `verify` re-derives from the file
    a text names rather than from the lockfile, and acquisition reported success. **When a
    write replaces a record that more than one run contributes to, the second run is a
    silent delete.**
44. **Every coverage ratio needs a denominator that can see rows that do not exist.**
    `embedding_coverage` counted chunks, and 1,230 texts with no chunks vanished from both
    halves of the fraction and reported 100.0%. A ratio computed over the artefacts of a
    stage is blind to everything that never reached that stage — which is exactly what a
    coverage number is supposed to expose. Count the corpus, not the pipeline's output.
45. **Take one census from the SOURCE, before parsing, for every ingest.** Files on disk
    against works loaded — 1,236 against 1,230 — is what found six works keeping half of
    themselves, after `verify` had passed over all 3,701 CBETA texts. Every other check in
    this project starts from a row that exists; none of them can see a row that should.
    This is rule 2 (*reproducibility is not fidelity*) in its cheapest possible form, and
    it is now check 4 in `mix pramana.integrity`.
46. **A number a check derives from raw markup must be derived by the SAME rule the
    pipeline uses.** `integrity` counted every `<lb/>` in the body; the normalizer counts
    only the ones belonging to this edition's lineation. After the two-lineation fix the
    two rules disagreed by half, and the check reported 1,228 correct X texts as having
    lost half their lines. The normalizer had the reconciling number all along and threw
    it away — **when a pipeline stage deliberately discards input, it must EXPORT the
    count**, or every downstream fidelity check has to re-implement the rule and will
    eventually re-implement it wrong. And a check that cries wolf is worse than a missing
    one: this failure sat unnoticed because the ingest ran `verify` and not `integrity`.
47. **A lesson learned from one measurement does not transfer to a different one without
    being re-measured.** "Measure discrimination, not dispersion" was correct and hard-won
    for judging whether a fine-tuned embedder had improved. Applied to judging whether a
    QUERY has an answer, the same statistic separates nothing — 6 of 8 unanswerable
    queries sit inside the answerable range. The registered prediction was wrong and the
    probe took twenty minutes; reasoning from the earlier finding would have shipped a
    signal that does not work. **Register the prediction, then measure anyway.**
48. **"Blank" must be defined once, as the ABSENCE of every kind of content, never as a
    list of the kinds someone remembered.** Three lines-dropped defects here, three
    versions of the same list: text-only (v2 dropped note-only lines), then text+notes
    (v3), then text+notes+apparatus — which dropped a line whose only content was a rare
    character. Each list was written by someone who knew about the kinds of content that
    existed *at the time*. `Pramana.Normalize.IR.Line` knows all of them; the predicate
    belongs there, derived, not restated at each call site (see rule 42).
49. **Measure the instrument's variance before attributing a delta to your change.** The
    noise floor was published as one case, measured by running the identical configuration
    twice against the identical index. Rebuilding the HNSW index over **completely
    unchanged data** then moved the gate by **six cases, four of them `retrieval/tibetan`**
    — four to six times larger, and invisible until someone ran the null experiment. Every
    import, re-embed and chunk-size change rebuilds the index. A metric whose noise you
    have not measured cannot support the claim you want to make with it, and the null
    experiment costs one run.
50. **Carry what you were given; never parse it apart and rebuild it.** `A/A091/A091n1057.xml`
    was parsed into the integer 91 and formatted back with two-digit padding, producing
    `A/A91/...`, which does not exist — because the padding width belongs to the edition
    (T, X, J, K, S, M use two; A, P, L, U use three) and the string already knew it. Two
    works failed to bake, and `verify` and `integrity` would have failed on them
    identically, because all three rebuilt the same path from the same parts. The lockfile
    records the path; the bake now carries it. This is the same shape as inferring a
    lockfile's raw root from a source id, and as inferring `addressing` from a source id
    before that: **an identifier reconstructed from its components is a guess wearing the
    costume of a fact.**
51. **A collection's NAME is not its contents, and neither is its size.** Seven CBETA
    collections were acquired on the argument that they are other witnesses to works
    already held, which would have turned 572,701 recorded variant readings into passages
    a reader could open. Of 57 works, **2** share a title with anything in T, X or J:
    CBETA publishes what is *distinctive to* each edition — the Koryŏ's own collation
    record, Song imperial compositions, phonetic glossaries — not a parallel text of the
    Taishō's works. A collection called "the Qianlong Canon" holding 21 works is not the
    Qianlong Canon. The refusal to expand a two-letter code into a canon name, three hours
    earlier and in the same module, was the identical rule one level down; **check what a
    source contains before designing around what it is called.**
52. **A volume is not the unit of loading, and this is the second source it has bitten.**
    Recorded for Derge, where 75 of 1,195 works span volumes; found again in CBETA X,
    where six do. The Taishō hid it for two phases because CBETA gives its split works
    distinct ids (`T0220a`, `T0220b`) while X reuses the number. Before baking a new
    source, **group the file list by work id and look at the groups of size > 1** — it is
    one line, and the failure it prevents is a text that resolves, verifies, and is half
    missing.

53. **A format that is "obviously" uniform across an edition is a table, and the table is
    the publisher's, not yours.** `Reader.linehead/1` padded CBETA volume numbers to two
    digits, because for two phases every volume held was two digits. Four of the ten
    collections now held use three — `A1057` is in `A091` — so 725,650 segments, 7.1% of
    the CBETA corpus, emitted a citation string CBETA's own reader cannot find. It could
    not raise: a wrong linehead is a plausible string that fails silently in someone
    else's search box, which is the failure this project treats as worse than an error.
    The same constant had already bitten `WorkList` as an `:enoent` (rule 50) and been
    fixed *there only* — rule 41 again, and now on its own recorded rule.

    **Check the artefact a reader sees, not the metadata field describing it.** The widths
    here were taken from the `id` attribute CBETA's website puts on the line. CBETA's
    catalogue API disagrees with CBETA's website: `works?work=M1540` reports volume
    `M059`, the rendered line is `M59n1540_p0789b01`, and a table built from the catalogue
    would have been silently wrong about a whole collection. This is the same shape as a
    text's own byline beating the 部 volume table for provenance — prefer the edition's
    own output over a description of it.

    **And a citation format needs a coordinate, so never feed it a range.** The other half
    of the same bug was `Corpus.provenance/1` supplying `text.volume`, which for a
    volume-spanning work is `"130-133"`. The 18 such works cited as
    `130-133n1557_p0003a01`. `IR.concat/1` had stamped every line with its own printed
    volume since the X assembly fix; the answer was recorded and never asked for. **When a
    field can be a range, the code that addresses one line must take the line's value, not
    the work's.**

54. **Normalise by the thing doing the measuring, not by the thing being measured.** The
    first gate for commentary alignment was *what fraction of the root does this commentary
    quote*, which puts the denominator on the other object and therefore ranks by that
    object's size. T1742 quotes T0278 at a density of 69.2 with 82.4% forward order, and
    covers **0.3%** of it — below what unrelated pairs score. Any root-coverage threshold
    strict enough to exclude the null band discards it. The working measure is spans per
    10,000 characters of the **commentary**, which does not shrink as its target grows.
    Before trusting a ratio, check it against the largest and smallest instance you have.

    And **a threshold calibrated against a thin tail is calibrated against nothing.** The
    floor was set to 25 against 40 null pairs — commentaries paired with roots they do not
    explain — whose p90 was 10.8, which looked like enormous margin. Tripling the null set
    to 120 moved the observed *maximum* from under 11 to **28.4**, and 25 turned out to
    admit three of them. The floor is now 30, the lowest value rejecting all 120.

    Two habits follow. **Quote the null maximum, never its p90**, because a gate's job is
    to reject the worst case and a percentile is chosen to ignore it. And when the margin
    still looks thin, **enlarge the null set rather than reason about the margin** — it
    cost one more run and it was the run that found the error.

55. **Whitespace you introduced is yours, never the edition's — do not match on it.**
    `texts.body` joins printed lines with newlines. An 8-character window taken raw over
    that can be two newlines and six characters, and a quotation running across a printed
    line break — which most do, the break being typographic — fragments into one match per
    line. Lemmas were stored beginning `\n\n`. Match over the text with whitespace removed
    and map the offsets back. Classical Chinese prints no whitespace at all, so **any**
    whitespace in a CJK body is an artefact of our own storage; this is the same root fact
    as "never use whitespace tokenization", arriving at a different layer.

56. **When a record says which files it governs, match on that — not on an identifier that
    usually correlates.** SuttaCentral publications were resolved by `text_uid` prefix,
    which works because `mn` covers `mn1` and fails because `pli-tv-vi` — the whole Vinaya
    Piṭaka — is not a prefix of `pli-tv-bu-vb-pj1`. **66,199 rows of CC0 public-domain text
    sat marked not-redistributable for two phases** as a result. The same records carry
    `source_url`, pointing at the directory the publication publishes; matching on that
    resolves 4,784 of 4,996 files exactly. Before inferring, check whether the data already
    states the thing you are about to infer.

    **And a conservative default hides its own errors.** Storing `redistributable: false`
    when unsure is right, and it is indistinguishable from a correct answer — no test
    fails, no query errors, the text is simply absent from anything public. The only way it
    surfaces is by counting what the caution costs, which is what `mix pramana.public.check`
    now exists to do. **Any policy of "when unsure, withhold" needs a report of what is
    being withheld**, or it silently becomes the answer.

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
- **A deep link into CBETA Online, SuttaCentral or SAT cannot be validated by fetching
  it.** All three are single-page apps that resolve content in the browser: a real path
  and complete nonsense both return HTTP 200 with a **byte-identical body** (1,018,537
  bytes for SAT, either way). So `reader.verified` is permanently `false` and stated in
  the payload — a link checker there would be theatre.

  **84000 is the exception, and it is worth knowing which publishers are which.** It is
  server-rendered: `read.84000.co/translation/toh308.html` returns *"Questions Regarding
  Death and Transmigration"* while `toh9999.html` returns a page titled *"Toh 9999"*. So
  its links *could* be checked. `verified: false` stays the floor everywhere anyway,
  because a per-publisher truth claim is one nobody will keep current.

  For the SPAs, formats are measured against each publisher's own **JSON API or rendered
  markup** instead of its HTML status code: 40 of 40 SuttaCentral uids resolve, and every
  CBETA volume token is reproduced from `sources.lock.json` and cross-checked against the
  `id` CBETA puts on the line in the HTML its site serves.
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
| **#38 Pāli root text** | **539** | — | verify --all + integrity green on 10,914 texts | ingest 53 s / 8,442 works | **10,914 texts, 5,185,767 segments** |
| **#39 translation pool + readings** | **582** | — | a generated rendering is rejected as source | translations ingest 4,996 files | **210,756 renderings, 8 translators, 4,601 shared anchors; 22 reading exceptions** |
| **#40 multi-vector + comparison tools** | **629** | — | an English query reaches a Pāli passage and cites the Pāli | chunk 84 s; embed 43,218 in ~5 min | **342,535 vectors: 300,165 source/lzh, 27,589 source/pli, 14,781 translation/en** |
| **#19 eval harness** | **651** | **65.3% @10** (zh **97.1** / pa 37.5) | **100%** verify + reject + provenance | evals 200 cases in 12 min | overall **87.0%**, 0 stale |
| **#21 Derge Kangyur ingest** | **870** | — | verify --source derge green on 1,195 texts; integrity closes to 69 bytes | ingest 4m35s / 103 volumes; verify 75 s | **12,109 texts, 5,647,069 segments; 1,195 Tibetan works, 75 spanning volumes** |
| **#21 84000 join** | **882** | — | an English folio resolves to the seven Tibetan lines it renders | ingest 36 s / 385 files | **30,653 renderings, 472 works, 478 titled; 7 volume groups refused** |
| **#21 Tibetan measured, three ways** | **909** | **retrieval@10 69.3%** (zh 97.1 / pa 55.0 / **bo 35.0**) | **100%** verify + reject + provenance | evals 249 cases in 15 min | overall **79.5%**, 0 stale; topical bo 0% — 95% of the Kangyur has no English layer |
| **#21 term anchors** | **952** | — | 59 of 60 three-way anchors reachable in both canons | glossary ingest 27 s / 396 files | **56,382 entries, 16,741 Skt / 25,524 Tib terms, 865 three-way; 2,756 divergent** |
| **#19 per_tradition decided** | **995** | **68.4% @10** under per_tradition (zh 97.8 / pa 42.7 / bo 21.9) vs **73.3%** default | **100%** verify + reject + provenance | full set **3h09m**; `--only topical` 5m22s | 1,400 cases, 0 stale; **opt-in confirmed** — 22 pinpoint cases lost for 2 topical; answered-from-any-canon 72.7% → 54.5% |
| **#10 the 41-second search** | **1042** | **retrieval@10 74.9%** (zh 97.8 / pa 54.7 / **bo 39.1**) | **100%** verify + reject + provenance | **full gate 3h08m -> 18m13s**; one search 41.1s -> 2.2s | 1,400 cases, **90.0%**, 0 stale, 0 errored; `texts.body` removed from 4 call sites |

The `zh 98.7` in the `#19` row above was **corrected to 97.1** on 2026-08-22. It was a
by-tradition figure that silently included the 40 provenance cases, so its sub-rows did
not sum to their parent — the same error the README carried and had fixed in b22949a,
left standing here. Recall@10 rows in this table mix case types by design; read them with
the case counts in `evals/baseline.json` beside them.
