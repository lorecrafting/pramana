# Runbook: Embedding the Corpus on a Rented GPU

Step-by-step for the full-corpus embedding run. Roughly **$1–3 and under an hour**.

Why rented rather than hosted API, and why not this laptop, is in `docs/EMBEDDING.md`.
The short version: cost is a wash, but a hosted API silently updates models behind a
stable endpoint name, which breaks `bake_id` reproducibility with no hash to pin and no
visible failure.

---

## 0. What you are shipping

```bash
mix pramana.embed.export --out /tmp/pramana_chunks.jsonl
```

Measured on the current bake (pipeline v3):

```
299,317 chunks   288.5 MB
```

That is the whole corpus. The 阿含部 proof embeddings are gone: the Phase 1 gate's
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

bin/pramana-modal run priv/embed/modal_embed.py    # streams progress back

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

**The import is the slow step, not the embedding.** Each row writes a 1024-dim vector
with HNSW index maintenance, so budget roughly an hour and run it in the background.

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
