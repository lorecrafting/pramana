# Embeddings: artifacts, serving and evaluation

The current core uses BGE-M3-compatible dense vectors. Query serving is opt-in;
batch inference/training helpers live in `priv/embed/`. This is an artifact boundary,
not a requirement that every reader model use the same provider.

## What is implemented

[The embedding modules](../apps/pramana/lib/pramana/embed) own local serving and
transfer. [Chunk vectors](../apps/pramana/lib/pramana/corpus/schemas.ex) are separate
from source segments and chunks. The [hybrid retriever](../apps/pramana/lib/pramana/retrieval/hybrid.ex)
fuses lexical and semantic results and can rerank using stored renderings. It reports
fallbacks; a requested semantic path is not proof that one ran.

BGE-M3's sparse and ColBERT capabilities are not evidence that those representations
are used by this repository's current hybrid retrieval. Likewise, a proposed
hypothetical-question representation is not a populated index.

## Artifact round trip

[The GPU runbook](GPU_RUNBOOK.md) describes chunk/vector preparation, export, inference
and import. Exported rows carry content hashes so imports can detect stale text.
`mix pramana.embed.fetch_model` retrieves the expected model artifacts through the
implemented fetch task; inspect its storage assumptions before use.

Do not mix vectors from incompatible model/configuration runs merely because dimensions
match. Record weights or adapter identity, tokenizer, truncation, precision, exported
content identity and importer options. A hosted model name alone may be insufficient
for reproducibility; pinned local weights alone also do not make a full retrieval
release immutable.

## Source identity is not index identity

`bake_id` does not pin all vectors. The implemented release stamp is a separate,
**count-and-identity-based** record, with the limitations in
[architecture](ARCHITECTURE.md#identity-and-replay). Re-embedding or same-count updates
must not be presented as proven identical merely because a stored stamp matches.

Before a model, window or retrieval-default change, evaluate the exact candidate
against the relevant gold cases and baseline. Report language coverage and actual
truncation from the current export, not an estimate inherited from another language.
Do not advance a baseline without reviewing per-case/per-tradition movements.

## Measurements and cost

[Historical measurements](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/embedding-measurements.md) preserve the original
laptop timings, old corpus sizes, truncation observations and vendor estimates.
They are not a forecast for the current dataset. Measure throughput on the actual
candidate and check current billing/transfer terms before launching a batch.

[Testing](TESTING.md) · [Cloud decisions](CLOUD.md) · [Proxy-study history](PROXIES.md)

## Historical section bookmarks

These bookmarks open the retained pre-cleanup revision in Git history, not current instructions.
See [retired files](RETIRED_FILES.md) for recovery and offline-access limits.

| Earlier section |
|---|
| <a id="embedding-where-to-run-it-and-what-it-costs"></a>[Embedding: Where To Run It, and What It Costs](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/embedding-measurements.md#embedding-where-to-run-it-and-what-it-costs) |
| <a id="measured-not-estimated"></a>[Measured, not estimated](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/embedding-measurements.md#measured-not-estimated) |
| <a id="the-corpus-in-the-units-that-determine-cost"></a>[The corpus, in the units that determine cost](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/embedding-measurements.md#the-corpus-in-the-units-that-determine-cost) |
| <a id="option-a--rent-a-gpu-recommended"></a>[Option A — rent a GPU (recommended)](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/embedding-measurements.md#option-a--rent-a-gpu-recommended) |
| <a id="option-b--hosted-embedding-api"></a>[Option B — hosted embedding API](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/embedding-measurements.md#option-b--hosted-embedding-api) |
| <a id="the-deciding-factor-is-reproducibility"></a>[The deciding factor is reproducibility](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/embedding-measurements.md#the-deciding-factor-is-reproducibility) |
| <a id="practical-plan"></a>[Practical plan](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/embedding-measurements.md#practical-plan) |
| <a id="open-question"></a>[Open question](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/embedding-measurements.md#open-question) |
| <a id="measured-what-the-320-token-window-truncates"></a>[Measured: what the 320-token window truncates](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/embedding-measurements.md#measured-what-the-320-token-window-truncates) |
| <a id="the-tasks"></a>[The tasks](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/embedding-measurements.md#the-tasks) |
