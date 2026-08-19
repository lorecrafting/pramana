# Status

Living handoff document. **Update this at every checkpoint gate.** If you are a new
session with no context, read this first, then `CLAUDE.md`, then `docs/ROADMAP.md`,
then run `TaskList`.

---

## Where we are

**Phases 0, 1, 3 and 4 complete and gated** (tags `phase-0`, `phase-1`, `phase-4`).
**Phase 2: #15 and #16 done, #14 blocked on acquisition, gate (#17) run but deliberately
NOT tagged** — see the gate findings below. Phase 2 is the only unfinished phase behind
us, and it is waiting on an email, not on code.

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

**Semantic search covers three traditions** (#21). 471,844 vectors: 300,165 Literary
Chinese, 70,160 Tibetan, 44,719 Pāli, 55,135 English renderings and 1,665 parallel
glosses. The Tibetan has an English layer for the same reason the Pāli does — 84000's
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

- **The Tengyur is absent, and nothing says so.** `Pramana.Coverage` states the Taishō
  56–84 gap because an empty result and an unloaded corpus are indistinguishable from the
  result alone. The same is now true of Tibetan commentary: this corpus holds the Kangyur
  (1,195 works) and none of the ~3,600-work Tengyur, so "no Tibetan commentary on this"
  is a claim the system is not entitled to make. Coverage needs a Tibetan clause.
- **Only a twentieth of the Kangyur is translated.** 84000 has published 385 of ~1,169
  Tōhoku numbers; 717 of the 1,195 works here have no title and no English at all. The
  84000 catalogue covers every Tōhoku number and would title them without inventing
  anything — a separate acquisition.
- **Tibetan word segmentation.** Lexical search over Tibetan works on substrings today.
  `botok` in the Python sidecar is the intended syllable/particle segmenter
  (`CLAUDE.md`), and nothing uses it yet.
- **Mahāvyutpatti** as Skt–Tib–Chi glossary anchors, and **BDRC metadata + IIIF image
  links** (catalogue only, no OCR), both untouched.

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
| **#38 Pāli root text** | **539** | — | verify --all + integrity green on 10,914 texts | ingest 53 s / 8,442 works | **10,914 texts, 5,185,767 segments** |
| **#39 translation pool + readings** | **582** | — | a generated rendering is rejected as source | translations ingest 4,996 files | **210,756 renderings, 8 translators, 4,601 shared anchors; 22 reading exceptions** |
| **#40 multi-vector + comparison tools** | **629** | — | an English query reaches a Pāli passage and cites the Pāli | chunk 84 s; embed 43,218 in ~5 min | **342,535 vectors: 300,165 source/lzh, 27,589 source/pli, 14,781 translation/en** |
| **#19 eval harness** | **651** | **65.3% @10** (zh 98.7 / pa 37.5) | **100%** verify + reject + provenance | evals 200 cases in 12 min | overall **87.0%**, 0 stale |
| **#21 Derge Kangyur ingest** | **870** | — | verify --source derge green on 1,195 texts; integrity closes to 69 bytes | ingest 4m35s / 103 volumes; verify 75 s | **12,109 texts, 5,647,069 segments; 1,195 Tibetan works, 75 spanning volumes** |
| **#21 84000 join** | **882** | — | an English folio resolves to the seven Tibetan lines it renders | ingest 36 s / 385 files | **30,653 renderings, 472 works, 478 titled; 7 volume groups refused** |
| **#21 Tibetan measured, three ways** | **909** | **retrieval@10 69.3%** (zh 97.1 / pa 55.0 / **bo 35.0**) | **100%** verify + reject + provenance | evals 249 cases in 15 min | overall **79.5%**, 0 stale; topical bo 0% — 95% of the Kangyur has no English layer |
