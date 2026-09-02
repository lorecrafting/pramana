# Why every proxy lied

**The most expensive lesson in this repository, and the one most likely to be repeated.**
A Tibetan LoRA improved every cheap measurement — 3.4× on in-batch top-1, 2× on held-out
MRR, **19× on discrimination** — and scored **0%** on the gold set it was built to improve.

It has its own file because it is a self-contained case study about *evaluation
methodology*, not a rule and not an incident report, and because three modules cite it by
name when explaining why they refuse a shortcut.

---

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

### Four numbers for one field, three of them mine — 2026-08-28

Sizing DILA's place authority before building it, `<geo>` coverage was measured and
published four times. The file did not change.

| measured over | pattern used | value |
|---|---|---|
| 8,510 entries (a 4 MB `Range:` request) | `<geo>` | 99.4% |
| all 59,335 entries | `<geo>` | 2.3% |
| the 284 places this bake cites | `<geo>` | **0.0%** |
| the same 284 | `<geo` | **100.0%** |

**The tag is `<geo cert="high">`.** A pattern matching `<geo>` finds the bare form, which is
what the head of the file uses, and silently reports absence everywhere else. It did not
error. It returned a plausible number.

Two failures, and the second is the one that cost the time.

**A prefix of an id-ordered file is a stratum, not a sample.** DILA assigns `PL` ids
thematically: the early ones are the Indian and Central Asian countries of Xuanzang's
travelogue, geocoded and glossed in English by someone; the tail is Chinese districts. A
`head -c 4000000` on 31 MB looked like a 9% sample. English placeName really is rare — 24
in that prefix, 1.2% file-wide, 4.9% among the places this corpus cites — so that half of
the first correction stood. The `<geo>` half did not.

**The number that confirms your correction is the one to re-derive.** 0.0% arrived while a
paragraph retracting the earlier 99.4% was already being written, and it agreed. That
agreement is exactly why it went out unchecked. Opening three actual records and reading
them — a minute of work — showed `<geo cert="high">` immediately, and is the second method
that should have been used before publishing the first.

**What it cost.** No code, because this was sizing. Three separate retractions in
`docs/PLAN.md`, which are kept rather than collapsed into the final number, and a feature
nearly designed away from coordinates that are present on **every place this bake cites**.


### A recall probe that reported 0.0% twice — 2026-08-29

`Pramana.Recall` measures retrieval against ground truth the corpus already holds: 141,073
verbatim quotations, each a statement that one passage occurs in two named works. If a search
for that passage surfaces only one of them, that is a recall failure nobody had to label.

It reported **0.0% recall over 120 pairs** on the first run and again on the second. Both
times the retriever was fine and the probe was wrong, and both times the number was
*plausible* — a broken measurement does not raise.

**A segment is the unit the index matches within.** A quotation spans lines, and the `\n` in
its stored text are real segment boundaries, so the concatenated passage cannot be found
inside any one segment. This is the same fact `Pramana.Guard`'s `:spans_line_boundary`
diagnosis exists for — written two items earlier in the same session, and walked into anyway.

**Punctuation must not be stripped when querying the index.** Everywhere else in this project
stripping CBETA's editorial punctuation is correct, because it is the editor's and not the
witness's. The index holds what the editor printed, so a stripped query matches nothing.
Stripping is right when comparing two passages to each other and wrong when asking the corpus
a question — the distinction is *what is on the other side of the comparison*.

The corrected figure, over 2,000 pairs with a fixed seed:

    decided     1,891      both works  1,891      recall 100.0%
    undecided     109      (result set filled the cap — absence is not evidence)

**What that number is worth, and what it is not.** It says lexical phrase retrieval reliably
finds both ends of an exact repeated passage, which bounds where retrieval failures can live:
not in exact matching. It says nothing about semantic or cross-lingual retrieval, which is
where `topical/chinese` has been 0% since it was first measured. A probe that confirms the
strong axis is worth having and is not evidence about the weak one.


### The cross-lingual number, and the control that nearly buried it — 2026-08-29

`topical/chinese` has been 0% of twelve gold cases since it was first scored. Twelve cases
cannot be steered on, so the axis was not stuck: it was unmeasured. SuttaCentral's curated
parallels are 10,493 Pāli↔Chinese relevance judgements made by scholars, sitting unused.

    control (same language)   26/125 decided   20.8%
    cross-lingual              2/496 decided    0.4%
    cross vs same                               1.9% of same-language recall

**The control is what makes the number mean anything, and it was nearly discarded.** The
first version of the probe called any control below 50% a broken run — a floor picked from
nothing, which is the mistake this document exists to record. Measured, same-language
paraphrase retrieval is ~21%, and that is very likely the real ceiling for the task: a
parallel records that two discourses *correspond*, not that they share words, and finding one
inside the top hundred of 12.5 million segments is genuinely hard.

Had the floor stood, a working measurement would have been thrown away as a fault, and the
project would still be quoting 0% of twelve.

**Read the ratio, not the rate.** 0.4% alone is moved by the corpus, the cap and the
difficulty of paraphrase retrieval. Against the identical task in one language it isolates
the language barrier: it costs 98% of the achievable recall. That is a checkable claim; "weak
cross-lingual retrieval" is not.

**Cost of getting here.** Three wrong readings before this one. `--mode lexical` silently ran
hybrid, because `:lexical` is not a mode and an unrecognised name falls back to `:hybrid` by
design — 3.6 s per query, mistaken for a slow lexical path. Phrase mode then reported 0.0%
cross-lingual with a 10% control, which the control correctly refused to publish. Only the
third run, with the serving loaded and the floor corrected, produced a figure worth writing
down.

## The quotation graph as a demand proxy — contaminated twice, 2026-09-02

Sizing E1's translation spend needs to know how concentrated demand is: if a few hundred
works absorb most retrieval, translating them buys most of the benefit. The quotation
graph — 141,073 verbatim reuses — looks like the obvious measure of which works the canon
itself leans on.

**First reading, and it was wrong: "the top 50 works are 82.3% of all quotations."**

That number is one text quoting itself. T0220b and T0220c are sections of the
大般若波羅蜜多經 and account for **87,659 of 141,073 quotations — 62% of the graph** —
and 66,841 of T0220b's point at T0220a, another section of the same sūtra. The Large
Prajñāpāramitā is famously repetitive; the detector is finding that repetition, correctly,
and it is not citation.

Measured across the whole graph: **92,545 of 141,073 pairs, 65.6%, join works sharing a
five-character id prefix** — the same work split into CBETA sections.

**Corrected to cross-work pairs only**, the graph is 48,528 quotations and the
concentration is real but weaker: top 50 works 53.3%, top 100 **66.1%**, top 200 78.4%.
The ranking becomes recognisable, which is the check that matters — 順正理論, 法苑珠林,
妙法蓮華經, 摩訶般若波羅蜜經, both Āgamas, 大般涅槃經, 大方廣佛華嚴經.

**A second contamination remains, smaller and named rather than corrected.** T2157
貞元新定釋教目錄, T2148 and T2153 眾經目錄 are **catalogues**: they enumerate texts, so
they quote hundreds of works and rank near the top while nobody reads them for doctrine.
Citation weight is a proxy for what the tradition cites, and the tradition includes its
own librarians.

**And the deeper limit, which no correction reaches.** This measures what the canon cites,
not what a modern English-speaking reader asks. They plainly correlate — the Lotus and the
Āgamas are on both lists — and they are not the same thing, and there is no data here that
measures the second. A figure derived from this should be read as "what the tradition
leans on", never as "what users want".

**The habit, again.** The first number was checked by looking at the ranking it produced,
which took thirty seconds and would have been skipped if the number had looked
unremarkable. It looked *excellent* — 82.3% is the answer you want when you are hoping
demand is concentrated — and that is exactly the condition under which this project has
been wrong before.

## The dense-gloss test that queried itself — 2026-09-02

`docs/TRANSLATION.md` asks whether index-tier English needs to be prose, since nobody
reads it. A dense gloss — content words only — would be about half the tokens, and at
~73,000 chunks that is real money.

**The first test said prose won 150 pairs to nothing.** It queried with the very text it
was scoring: `embed(t)` against `embed(t)`, cosine 1.0 by construction. That is not a
result, it is an identity — and it read as a clean, decisive negative, which is exactly
the shape rule 62 warns about.

**Fixed by using a second translator's rendering of the same chunk as the query.** 574
chunks carry two independent human renderings; one asks, the other answers. Corrected:

    mean margin over best distractor    prose 0.0989   dense 0.0549
    beats every distractor              prose  99.3%   dense  86.7%
    dense >= prose                                     4.7% of pairs
    length                              657 chars ->   348 (53.0%)

The conclusion survives and is now earned: **prose retrieves substantially better.** Half
the tokens costs nearly half the margin and 12.6 points of "would be retrieved at all",
and recovering that needs roughly double the coverage — more than the 47% saved.

**What this does NOT rule out.** It tested *mechanically stripped prose*, not a
purpose-written gloss. A model asked for "the terms, names and doctrinal vocabulary of
this passage" would write something different, and probably better, than a stop-word
filter produces. The cheap version of the idea is dead; the idea has not been tested.

And the embedder is a variable: BGE-M3 is trained on natural language, so stripping
function words moves the text off-distribution. A different model might not care.
