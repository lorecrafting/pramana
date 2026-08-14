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

Measured on the current bake:

```
289,179 chunks   266 MB   (103 MB gzipped)
```

That is everything outstanding — 阿含部's 10,138 are already embedded locally and are
excluded automatically. The export carries each chunk's `content_sha256`, which is what
lets import prove the vector still describes the chunk it claims to.

```bash
gzip -k /tmp/pramana_chunks.jsonl     # 103 MB, worth it on a metered link
```

## 1. Rent the box

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

It prints throughput and an ETA. Expect **hundreds of chunks/sec**, so 289k chunks is
roughly 15–35 minutes. Compare with **1.29/s** on the M1 — this is the entire reason to
rent.

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
imported 289179 vector(s)
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
