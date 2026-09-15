# Why every proxy lied — chapter 3

> Historical evidence. Statements and commands below describe their recorded context, not current operating instructions.
> [Contents](../PROXIES.md) · [Documentation](../README.md) · [Current architecture](../ARCHITECTURE.md)

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
