# Project history — chapter 16

> Historical evidence. Statements and commands below describe their recorded context, not current operating instructions.
> [Contents](../HISTORY.md) · [Documentation](../../../docs/README.md) · [Current architecture](../ARCHITECTURE.md)

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
