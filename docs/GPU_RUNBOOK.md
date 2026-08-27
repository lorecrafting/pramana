# Runbook: Embedding the Corpus on a Rented GPU

Step-by-step for the full-corpus embedding run. Roughly **$1–3 and under an hour**.

Why rented rather than hosted API, and why not this laptop, is in `docs/EMBEDDING.md`.
The short version: cost is a wash, but a hosted API silently updates models behind a
stable endpoint name, which breaks `bake_id` reproducibility with no hash to pin and no
visible failure.

---

## 0. What you are shipping

**Two steps, and the first one is easy to miss.** Chunking creates `chunks`; the thing
that gets embedded is a `chunk_vectors` row, created empty and filled on import — that is
what makes the sha256 round-trip possible at all, since the row has to exist before there
is anything to re-check against.

```bash
mix pramana.chunk --source cbeta      # segments -> chunks
mix pramana.vectors --source cbeta    # chunks -> empty vector rows
mix pramana.embed.export --out /tmp/pramana_chunks.jsonl
```

Skip the middle step and the export succeeds and reports **`exported 0 chunk(s)`** —
which is indistinguishable from "nothing is outstanding", and is what happened here after
chunking CBETA X: 290,392 chunks existed, none of them had a vector row, and the pending
query looks for vector rows lacking an embedding. `mix pramana.vectors --source cbeta`
built all 290,392 in 29 s and the export then found them.

Measured on the Taishō-only bake (pipeline v3):

```
299,317 chunks   288.5 MB
```

That was the whole corpus **then**. It is not now: CBETA X is baked and unchunked —
1,230 texts, 87.6M characters, so roughly **285k more chunks** at the same 300-character
Literary Chinese window, and by that precedent about **35 minutes and $0.45**. Chunk
before exporting, or the export will faithfully ship a corpus that is missing a
collection. The 阿含部 proof embeddings are gone: the Phase 1 gate's
fidelity fix changed segmentation, and re-chunking replaces chunk rows, so their
vectors went with them. Nothing expensive was lost — this run was always going to
cover everything — but it is why the count is 299,317 rather than the outstanding
289,179 quoted before.

Export is a fresh dump each time and only ever emits chunks that still need a vector,
so re-running after a partial import is safe. Each row carries `content_sha256`, which
is what lets import prove the vector still describes the chunk it claims to.

```bash
gzip -k /tmp/pramana_chunks.jsonl     # ~110 MB, worth it on a metered link
                                      # (the Modal path uploads the plain file)
```

**Watch a `volume put` rather than trusting it.** A 267 MB upload stalled at ~125 MB and
sat there with no error, no timeout and no output — `modal volume put` prints its progress
to a TTY, so a backgrounded run shows nothing at all and a stall is indistinguishable from
slow. `nettop -P -l 1 -x | grep Python.<pid>` gives the byte counter; if it does not move
for a minute, kill it and start again. The retry ran at ~700 KB/s and finished in about
six minutes. Rule 3 below applies here too: make sure the first process is dead before
starting the second.

## 1a. Recommended: Modal (free within the monthly credit)

Per-second billing, a $30/month free credit that covers this job several times over, and
**nothing to forget to destroy** — which is the most expensive failure mode of renting by
the hour. See `docs/CLOUD.md` for why this beats AWS/GCP and instance rental.

### One-time: install the CLI in the project's own venv

Do **not** `pip install modal` globally. `python3` on macOS is Apple's 3.9 from the
Command Line Tools, Homebrew's Python refuses installs outside a venv
(`externally-managed-environment`), and a global install breaks on the next
`brew upgrade`. `priv/embed/.venv/` is already gitignored.

```bash
/opt/homebrew/bin/python3 -m venv priv/embed/.venv
priv/embed/.venv/bin/pip install modal
```

`bin/pramana-modal` wraps that venv, so the path is not something to remember.

```bash
bin/pramana-modal setup      # opens a browser; interactive, run it yourself
```

Verified working: **modal 1.5.4 on Python 3.14.6**. `priv/embed/modal_embed.py` loads
against that client with no deprecation warnings.

### Run it

```bash
bin/pramana-modal volume create pramana-embed
bin/pramana-modal volume put pramana-embed /tmp/pramana_chunks.jsonl /chunks.jsonl

bin/pramana-modal run --detach priv/embed/modal_embed.py   # streams progress back

```

### `--detach`, and why it is not optional

Without it the app is **ephemeral**: it lives only as long as the local client's
heartbeat, and Modal stops it the moment that connection breaks. Measured 2026-08-18 — a
19-minute run over a laptop link died at **121,600 of 170,014 chunks** with
`ConflictError: App state is APP_STATE_STOPPED`, seventeen minutes of GPU time already
spent.

What made that cheap rather than expensive is that **the job streams its output to the
volume as it goes**. 1.2 GiB of vectors were sitting there, the last line parsed cleanly,
and the pipeline is resumable by construction: import what came back, re-export (which
only ever emits chunks that still need a vector), and run the remainder. The loss was
about twelve minutes, not a run.

```bash
bin/pramana-modal volume get pramana-embed /vectors.jsonl /tmp/pramana_vectors.jsonl
mix pramana.embed.import --in /tmp/pramana_vectors.jsonl
```

### Measured, full corpus, 2026-08-14

| stage | |
|---|---|
| image build (pip + baking the weights in) | 86 s, once |
| embed 299,317 chunks on an L4 | **34.1 min at 147.4 chunks/s** |
| upload 288.5 MB / download 3.0 GB | 67 s / 82 s |
| **GPU cost** | **~$0.45**, inside the free credit |

**147 chunks/s is the honest number**, and it is below the "hundreds of chunks/sec" this
runbook used to promise. BGE-M3 is 568M parameters at `max_length=320`, so an L4 is
compute-bound here rather than starved — a bigger card would help, more batching would
not. It is still **114× the 1.29 chunks/s** measured on the M1, which is the whole
argument for renting.

**The import is the slow step, not the embedding**, and the HNSW index is why. Measured
on the same corpus:

| import path | total |
|---|---|
| per-row UPDATE, index maintained incrementally (original) | **88 min** |
| batched UPDATE + `--rebuild-index` | **38.7 min** — 3 min loading, **35.8 min rebuilding the index** |

So storing 299,317 vectors still costs more than computing them (34 min on the GPU), and
`--rebuild-index` buys **2.3×**, not the order of magnitude the row-write rate suggests:
batched writes run at ~1,800 rows/s against ~66/s, but that speedup is almost entirely
eaten by the one-off rebuild.

Two honest caveats:

- **The contributions of batching and of dropping the index were not isolated.** They
  shipped together; 2.3× is the combined, end-to-end figure, which is what you actually
  get.
- **`--rebuild-index` costs ~36 min regardless of how many rows you import.** It wins for
  a full-corpus load and loses badly for a small top-up. That is why it is opt-in.

Budget **~40 minutes** for a full-corpus import and run it in the background.

### Measured again, 2026-08-21, at 617,038 vectors

The corpus doubled (the Tengyur landed) and a Tibetan LoRA adapter was adopted, which
forces a full re-embed. The numbers held, and three of them are rules rather than trivia.

| stage | |
|---|---|
| embed 617,038 chunks on an L4 | **70.0 min at 146.9 chunks/s** |
| the same with the adapter merged in | **no measurable cost** — 144 vs a historical 147 |
| download 6.65 GB | ~4 min |
| import with the index **dropped** | **69 s** for 67,371 rows |
| index rebuild, table not bloated | **15 min 47 s** |

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

## 4. Verify

Import re-checks every row's `content_sha256` and reports rejections by category. A
clean run reads:

```
imported 299317 vector(s)
  hash mismatches (rejected): 0
  wrong dimensions (rejected): 0
  unknown chunk ids (rejected): 0
```

**Hash mismatches are not a warning to skim past.** They mean the corpus was re-baked
between export and import, so those vectors describe text that is no longer at those
chunks. They are rejected rather than written, because writing them would attach a
plausible vector to the wrong passage and nothing about the result would look wrong —
it is still 1024 valid floats. Re-export and re-embed the affected chunks.

Then rebuild the index and check coverage:

```bash
mix ecto.migrate                       # HNSW covers new rows incrementally
mix run -e 'IO.inspect(Pramana.Retrieval.Semantic.coverage())'
```

## 5. Don't re-embed by accident

Embedding is idempotent: a chunk with a vector from the **current** model is skipped.
Two things do invalidate vectors and are worth naming, because both are silent:

- **Changing the model.** `chunks.embedding_model` records which model produced each
  vector, and mixing two models in one index corrupts ranking without failing.
- **Changing chunking** (`--max-chars`, boundary rules). New chunks are new rows with
  new hashes; the old vectors describe text that no longer exists.

Either means a full re-run, so decide on both before spending the GPU hour.

## Cost, end to end

| item | |
|---|---|
| GPU, 1 hour on-demand 4090 | $0.35–0.70 |
| bandwidth | usually included |
| **total** | **well under $2** |

Embeddings are re-run only when the model or chunking changes, not per bake — a rare
cost, not a running one.
