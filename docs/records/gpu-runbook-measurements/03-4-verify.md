# Archived GPU_RUNBOOK.md: gpu-runbook-measurements — chapter 3

> Historical evidence. Statements and commands below describe their recorded context, not current operating instructions.
> [Contents](../gpu-runbook-measurements.md) · [Documentation](../../README.md) · [Current architecture](../../ARCHITECTURE.md)

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
