# Embedding: Where To Run It, and What It Costs

## Measured, not estimated

BGE-M3 (XLM-RoBERTa-large, 568M params, 1024 dims) on an **Apple M1, 8 cores, 16 GB**:

| config | ms/chunk | chunks/s | 阿含部 (10,138) | full corpus (299,317) |
|---|---|---|---|---|
| batch 8, seq 512 | 2627 | 0.38 | 7.4 h | 218 h |
| **batch 16, seq 320** | **1601** | **0.62** | **4.5 h** | **133 h** |
| batch 32, seq 320 | 1949 | 0.51 | 5.5 h | 162 h |

Two things worth keeping:

- **Sequence length matters more than batch size.** Real chunks measure p50 278 / p99
  298 tokens (Chinese runs ~1.05 chars per token), so padding to 512 wasted 40% of the
  compute for nothing. 320 covers p100 with minimal waste.
- **Batch 32 is *slower* than 16.** 16 GB is not enough headroom next to a 3.7 GB
  Postgres, and it starts swapping. Bigger is not automatically better.

So: **the laptop is fine for a division-sized proof and impractical for the whole
canon.** 133 hours is 5.5 days of pinned CPU.

## The corpus, in the units that determine cost

- 299,317 chunks
- 85.9M characters → **~82M tokens** at the measured 1.05 chars/token
- 1024 dims × 4 bytes × 299,317 ≈ **1.2 GB** of vectors (not the 300 GB it would have
  been at segment granularity — see `docs/STATUS.md` on why chunks exist)

## Option A — rent a GPU (recommended)

A 568M-param encoder at ~300 tokens is comfortably in the hundreds of chunks/sec on
any modern GPU. At a deliberately conservative 150–400 chunks/s, the full corpus is
**15–35 minutes of GPU time**; budget 1–2 hours including instance setup, model
download and loading the vectors back.

Approximate on-demand rates at time of writing — **verify before booking, spot markets
move**:

| provider / card | ~$/hr | est. total |
|---|---|---|
| Vast.ai RTX 4090 | 0.25–0.50 | **< $1** |
| RunPod RTX 4090 | 0.34–0.70 | **< $1.50** |
| RunPod / Lambda L4 or A10 | 0.43–0.75 | ~$1.50 |
| Lambda A100 40GB | ~1.29 | ~$2.50 |

**Realistically $1–3 for the entire canon.** Embeddings are re-run only when the model
or the chunking changes, not on every bake, so this is a rare cost rather than a
running one.

## Option B — hosted embedding API

No GPU to manage. At ~82M tokens, and again **verify current pricing**:

| service | ~$/1M tokens | est. total |
|---|---|---|
| OpenAI `text-embedding-3-small` | 0.02 | ~$1.65 |
| Voyage / Jina (small tiers) | ~0.02 | ~$1.65 |
| Cohere embed v3 | ~0.10 | ~$8 |
| OpenAI `text-embedding-3-large` | 0.13 | ~$11 |

Also $2–11. **Cost is not the deciding factor. The two options are within a few
dollars of each other, and both are trivial.**

## The deciding factor is reproducibility

`CLAUDE.md` invariant #3: *if a bake can't be reproduced from `sources.lock.json`, it's
not a bake.* And `bake_id = sha256(lockfile + pipeline_version + config)` is supposed
to mean that two people holding the same id hold the same corpus.

**A hosted embedding API breaks that.** Providers silently update models behind a
stable endpoint name. Two people with identical `bake_id`s would get different vectors,
with nothing to point at and no hash to pin — and the failure is invisible, because
every value returned is a perfectly valid float. It is the same class of problem as
mixing two models' vectors in one index, which is why `chunks.embedding_model` exists.

A self-hosted model with pinned weights is verifiable: the safetensors file has a
hash, and that hash can be folded into `bake_id`.

**Recommendation: rent a GPU and run our own pinned model.** It costs about the same,
takes about as long, and keeps the reproducibility guarantee that the rest of this
project is built around. Use a hosted API only for throwaway experiments, never for a
bake anyone will cite.

## Practical plan

1. **Proof (local, now):** 阿含部, 10,138 chunks, ~4.5 h. Resumable, so it can be
   interrupted freely. Validates the pipeline and the retrieval quality end to end.
2. **Full corpus (rented GPU, later):** ~$1–3. Export chunk text, embed, load vectors
   back — or run the whole app on the instance against a remote Postgres.
3. **Record the model in the bake.** `chunks.embedding_model` already does this per
   row; folding the weights hash into `bake_id` is the remaining step.

## Open question

Whether BGE-M3 is the right model at all, given the cost of its size. A Chinese-specific
model such as `bge-base-zh` (102M params) would be roughly 5× faster and might well
retrieve better *within* Chinese — but the project needs Pāli, Tibetan and Sanskrit
later, and cross-canon retrieval is the differentiator. Revisit after the Phase 4 eval
harness exists, since that is what turns this from an opinion into a measurement.

## Measured: what the 320-token window truncates

`MAX_LENGTH = 320` was chosen for Literary Chinese, where a 300-character chunk is close
to 300 tokens. It is not neutral across the corpus, and the multi-vector work (#40) made
that measurable rather than theoretical:

| vector kind | rows | avg chars | over ~1,280 chars (≈320 tokens) |
|---|---|---|---|
| `source` / lzh | 300,165 | 287 | 5 |
| `source` / pli | 27,589 | 932 | 38 |
| **`translation` / en** | **14,781** | **922** | **3,489 — 23.6%** |

Nearly a quarter of English translation vectors lose their tail. The cause is
straightforward: a chunk's span is fixed by the **source** text, and an English rendering
of a Pāli passage runs longer than the Pāli. Sizing the chunk to the Pāli therefore
undersizes it for the translation.

Three ways out, none taken yet, deliberately:

1. **Shrink Pāli chunks** so their renderings fit — costs a re-chunk and a re-embed.
2. **Raise `MAX_LENGTH` for translation vectors** — BGE-M3 accepts 8,192 tokens; compute
   scales with length, and the run is already compute-bound on an L4.
3. **Leave it.** The first ~1,280 characters is most of any passage, and a truncated
   vector is still a usable one.

Which is right depends on whether truncation measurably hurts retrieval, and that is a
question for the Phase 4 eval harness (#19) rather than for taste. It is recorded here so
the choice is made with the number in front of it — the same reason
`Pramana.Retrieval.Semantic` states plainly that BGE-M3 is unproven on Literary Chinese.
