# Archived GPU_RUNBOOK.md: gpu-runbook-measurements — chapter 2

> Historical evidence. Statements and commands below describe their recorded context, not current operating instructions.
> [Contents](../gpu-runbook-measurements.md) · [Documentation](../../README.md) · [Current architecture](../../ARCHITECTURE.md)

### Index build cost at scale, measured 2026-08-27

| vectors | `maintenance_work_mem` | build |
|---|---|---|
| 617,038 | 4 GB | 15m47s |
| 907,430 | 6 GB | 25m12s |
| 966,931 | 6 GB | 28m06s |

Roughly linear, and **the memory has to grow with the graph** — the rule of thumb is
~1.5 GB per 300k vectors at 1024 dimensions. Undersizing does not merely run slower: the
build falls back to disk and *degrades* as the graph grows, which is why 187k of 299,317
tuples took 17 minutes at PostgreSQL's 64 MB default and was still slowing.

Budget half an hour per import at this size, and run it in the background. It is the
single most expensive step in the whole pipeline — more than computing the vectors on the
GPU, which took 34.6 min for 290k and 7.7 min for 59k.

**Rule 1: drop the HNSW index before ANY bulk write.** Not just imports. Measured on
three different operation types in one day:

| operation | index live | index dropped |
|---|---|---|
| import 67,371 vectors | **over 40 min** | **69 s** |
| rebuild afterwards | **2 h 44 min** | 15 min 47 s |
| backfill migration over 617,038 rows | **>600 s, did not finish** | **36.8 s** |

The rebuild figure is the trap: importing through a live index does not merely run slow,
it **bloats the table**, so the rebuild you were going to do anyway then takes ten times
longer. Correctness is never at risk. Hours are.

**Rule 2: validate a downloaded vector file before importing it.** Count the records and
parse the last line. A truncated download of 67,371 vectors had a perfectly valid last
line, correct 1024 dimensions and a plausible 725 MB size — and was **3,257 records
short**. Importing it would have left ~5% of Pāli under the previous configuration,
invisibly. Every surface check said fine; only the count caught it.

**Rule 3: never run two downloads against one path.** Doing so produced line counts that
*fell* between reads (64,114 then 37,578) and bytes-per-line at twice the true value —
readings that described no real file. A clean single download of that file took **21
seconds**. If a download looks slow, check for a second writer before retrying.

### Fine-tuning: `modal_train_tibetan.py`

A LoRA run against `modal_embed.py`'s own configuration. Two things must not drift, and
neither fails loudly if it does:

- **Pooling, normalisation and `MAX_LENGTH`** are copied verbatim from `modal_embed.py`.
  A vector's meaning comes from how token states are reduced, not only from the weights.
- **`Pramana.Embed`'s `@model` must change in the same commit.** Adapted vectors are not
  comparable with stock ones; the name is the only thing that separates them. Renaming it
  flips every stored vector to outstanding, which is the correct and desired consequence —
  adopting a different model means re-embedding the corpus, not mixing two in one index.

The adapter is `merge_and_unload`-ed into the base weights at fp32 before the fp16 cast,
so inference runs the same code path at the same speed as the stock model.

**Evaluate before adopting.** `modal_probe_adapter.py` compares base against adapted on
identical text. Use `disable_adapter()` for the "before" measurement:
`PeftModel.from_pretrained` injects the adapter **in place**, so holding a before- and an
after-reference compares one model with itself and prints identical numbers that look like
a perfectly preserved model.

And measure **discrimination, not dispersion**. Mean pairwise cosine falls for a model
that has genuinely separated its space and equally for one that has scattered it — a
random projection scores beautifully and retrieves nothing. The usable test needs no
translations: adjacent chunks of one work are related, a chunk from elsewhere is not, and
the **gap** between them is the quality signal.

### `--rebuild-index` was broken for two phases

`mix pramana.embed.import --rebuild-index` kept its own copy of the index DDL, and #40
moved vectors out of `chunks` into `chunk_vectors` without updating it. So it dropped
`chunks_embedding_hnsw_index` — which had not existed since that migration, a silent
no-op that left the real index live and the import slow — and then rebuilt against
`chunks.embedding`, a column that was equally gone. **The flag documented here as buying
2.3× was buying nothing**, and the only symptom was an import that took as long as it had
before.

It now delegates to `mix pramana.embed.index`, which is the one place that knows the index
name, its table, and that the build has to hold `maintenance_work_mem` on its own
connection. Measured after the fix: **122,688 vectors imported in 1m42s** with the index
dropped.

## 1b-bis. A top-up on Modal, measured end to end — 2026-09-03

The E1 MITRA tranche, and the numbers a future top-up should be sized against rather than
inheriting the full-corpus ones:

| step | measured |
|---|---|
| export rows missing a vector | 27,751 of 27,956 (205 already embedded) · 43.7 MB |
| embed on an L4 | **3.7 min at 126.8 chunks/s** |
| download and line-count | 27,751 lines · 299 MB |
| import through a **live** HNSW index | ~10 min at ~3,000 rows/min · **0 rejected** |

**126.8 chunks/s, not the 147 the full-corpus run measured.** English prose fills the
320-token window more completely than the corpus average, so a tranche of *renderings*
embeds slower per chunk than a tranche of source text. Re-derive from the population you
are about to run, which is rule 76.

**NAME THE VOLUME FILES AFTER THE RUN. Do not reuse `chunks.jsonl` / `vectors.jsonl`.**
Both already exist on the `pramana-embed` volume from the full-corpus run, and
`modal volume put` refuses to overwrite — which is the *helpful* failure. The dangerous
one is forcing past it: if the embed step then fails or is skipped,
`modal volume get /vectors.jsonl` hands back the **previous run's 980k source vectors**,
and `mix pramana.embed.import` accepts them happily. Every hash matches, nothing is
rejected, the summary reads clean, and the tranche you meant to embed is still unembedded.
`modal_embed.py` takes `--input-name` and `--output-name` precisely so each run can own its
filenames; use them.

**`--rebuild-index` is not automatic at this size.** Runbook Rule 1 below says drop the
index before any bulk write, and it is right at 67k+ rows. At **27,751** it is roughly
break-even: the live import cost ~10 minutes, while dropping would make the load ~30
seconds and then charge ~15 minutes for the rebuild regardless of row count — with
semantic search unindexed throughout. Below ~50k rows, prefer the live import and keep
search online.

## 1c. The index is built by a task, not by a migration

`mix pramana.embed.index` creates the HNSW index; `--rebuild` drops and recreates it,
`--drop` removes it before a large import. It is a task rather than a migration because
drop-and-rebuild is an operational sequence: a migration would build the index once on
every restore, and then it would be rebuilt again after the next import for no benefit.

**Size `maintenance_work_mem` to the graph.** This is not a tuning knob. An HNSW build
that does not fit falls back to building *on disk*, and it does not merely run slower —
it **degrades as the graph grows**. Measured while building over 299,317 vectors at
PostgreSQL's 64 MB default:

| elapsed | tuples done | rate |
|---|---|---|
| 17 min | 187,211 | ~11k/min average |
| 20 min | 193,264 | **~2k/min and falling** |

Extrapolating, that build was heading past an hour and getting worse. The task defaults
to `4GB`; roughly `rows × dimensions × 4 bytes` plus links is the figure to beat, so
~1.5 GB per 300k vectors at 1024 dimensions.

## 1d. Re-chunking discards vectors — the builder now refuses

`chunk_vectors` cascades from `chunks`, and `mix pramana.chunk` deletes a text's chunks
before rebuilding them. So a plain re-chunk **throws away every embedding for that text**,
reports success, and leaves nothing to indicate what happened.

`Pramana.Chunk.Builder` therefore refuses to rebuild a text whose chunks carry embedded
vectors unless `force: true` is passed, and `mix pramana.chunk` reports how many texts it
left alone. Chunking the newly-ingested Pāli now leaves the 2,471 embedded Chinese works
untouched instead of silently costing 34 minutes of GPU time.

Skip to step 4 to verify. The rest of this runbook is the SSH-to-a-rented-box
alternative, if you would rather have a plain machine.

## 1b. Alternative: rent the box

Prices as of writing — **check before booking, these move weekly and Vast.ai spot moves
by the minute**:

| provider | card | ~$/hr |
|---|---|---|
| [Vast.ai](https://vast.ai) | RTX 4090 (on-demand) | 0.35–0.50 |
| [RunPod](https://www.runpod.io/gpu-models/rtx-4090) Community | RTX 4090 | from 0.34 |
| RunPod Secure | RTX 4090 | 0.69 |
| RunPod | A100 PCIe 80GB | 1.39 |

**A 4090 is the right card here.** BGE-M3 is 568M parameters — about 1.1 GB in fp16, so
24 GB is ample, and an A100 buys memory you will not use. Take **on-demand, not
interruptible**: the job is under an hour, and losing it halfway to reclaim a few cents
is a bad trade.

Pick a template with PyTorch and CUDA preinstalled to skip a long install.

## 2. Upload and run

```bash
scp /tmp/pramana_chunks.jsonl.gz  root@<host>:/workspace/
scp priv/embed/embed_gpu.py       root@<host>:/workspace/

ssh root@<host>
cd /workspace && gunzip pramana_chunks.jsonl.gz
pip install torch transformers          # skip if the template has them

python embed_gpu.py \
  --in  pramana_chunks.jsonl \
  --out pramana_vectors.jsonl \
  --batch-size 64
```

It prints throughput and an ETA. Compare with **1.29/s** on the M1 — this is the entire
reason to rent.

If VRAM is tight, drop `--batch-size` to 32. The script picks CUDA automatically and
warns loudly if it lands on CPU, which would be as slow as the laptop.

## 3. Bring the vectors home

The output is larger than the input — 1024 floats per chunk:

```bash
ssh root@<host> "gzip -c /workspace/pramana_vectors.jsonl" > /tmp/pramana_vectors.jsonl.gz
gunzip /tmp/pramana_vectors.jsonl.gz

mix pramana.embed.import --in /tmp/pramana_vectors.jsonl
```

**Then destroy the instance.** Billing runs on wall-clock, not GPU utilisation.
