# Batch inference runbook

**Working directory:** `pramana/` for the commands and source-relative paths below.
Shared policy and the active plan remain at repository `docs/`. Existing corpus,
models and virtualenvs are not moved: see [layout migration](../../docs/LAYOUT_MIGRATION.md).

Run from the Pramāṇa project root (`pramana/`). These commands touch a database, write artifacts
and may lead to paid external compute. Review the source licenses, target database,
artifact paths and spend authorization before proceeding. No GPU job was launched
by the documentation audit.

## 1. Inspect the actual task and workload

Use [the CLI index](CLI.md) and `mix help` for the task's current options. Check the
loaded corpus and model/index state with `mix pramana.doctor`. Corpus size, prior
elapsed time and a provider's old free-credit offer are not a budget for this run.

Keep an export manifest naming the source commit, database/source identity, selected
rows, content hashes, model/adapter, tokenizer/window and expected output format.
Choose a bounded batch and measure it before scaling. Do not send restricted data
to a third party without the necessary permission and handling arrangements.

## 2. Prepare and export vectors

The following example mutates the chosen research database while preparing rows:

```bash
mix pramana.chunk --source cbeta
mix pramana.vectors --source cbeta
mix pramana.embed.export --source cbeta --out /tmp/pramana_chunks.jsonl
```

Chunks and vector rows are separate. An export with zero pending rows is not proof
that the selected collection was fully chunked/vector-prepared. Read the counts and
refusals. Do not force a re-chunk over valuable vectors without reviewing what will
be invalidated. [Transfer implementation](../apps/pramana/lib/pramana/embed/transfer.ex)
owns the round-trip checks.

## 3. Run the selected inference helper

Inspect the relevant helper under [priv/embed](../priv/embed) before launching it:
`embed_gpu.py`, `modal_embed.py`, `modal_train_tibetan.py`,
`modal_probe_adapter.py`, or `modal_translate.py`. They have different purposes and
CLI options. This runbook intentionally does not invent one universal provider command.

For a detached translation tranche, inspect [bin/pramana-tranche](../bin/pramana-tranche).
Its remote-state supervision and resume checks are not permission to start duplicate
jobs. Verify provider-side state, timeout and shutdown behavior with the configured
account, especially after a local client exits. Inspect output identities before resuming;
a matching filename alone is not a matching configuration.

## 4. Validate and import

Count records, inspect the schema, check for missing/duplicate IDs and verify the
model and source-content identities. Keep the original output and manifest for review.
The importer accepts `--in`, `--model` and an optional `--rebuild-index`; read its
[implementation](../apps/pramana/lib/mix/tasks/pramana.embed.import.ex) before use.

```bash
# Substitute the reviewed output file and exact compatible model identifier.
mix pramana.embed.import --in /tmp/pramana_vectors.jsonl --model YOUR_MODEL_ID
```

`--rebuild-index` changes the import/index-maintenance path. It is not universally
faster: corpus size, batch size, memory and concurrent query load determine the tradeoff.
Schedule index-affecting operations deliberately, not from an old timing threshold.

Translation uses separate [export](../apps/pramana/lib/mix/tasks/pramana.translate.export.ex)
and [import](../apps/pramana/lib/mix/tasks/pramana.translate.import.ex) tasks; embedding
output is not a translation artifact. [Translation](TRANSLATION.md) explains the distinction.

## 5. Record and verify

Inspect import accepted/rejected counts. Refresh the retrieval stamp deliberately with
`mix pramana.release.stamp` and inspect `mix pramana.doctor`; a stamp is not a substitute
for content validation or evaluation. Run the relevant [retrieval checks](../../docs/TESTING.md)
with the intended model loaded, preserve the result artifacts, and review any baseline
change separately. Confirm remote jobs/resources have ended according to the provider's
actual billing model.

[Prior runs and performance investigations](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/gpu-runbook-measurements.md)
are retained for comparison. Their old corpus sizes, rebuild times and prices are not
current operating guarantees.

## Historical section bookmarks

These bookmarks open the retained pre-cleanup revision in Git history, not current instructions.
See [retired files](../../docs/RETIRED_FILES.md) for recovery and offline-access limits.

| Earlier section |
|---|
| <a id="runbook-embedding-the-corpus-on-a-rented-gpu"></a>[Runbook: Embedding the Corpus on a Rented GPU](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/gpu-runbook-measurements.md#runbook-embedding-the-corpus-on-a-rented-gpu) |
| <a id="a-long-tranche-detach-it-and-supervise-it-by-asking-modal"></a>[A long tranche: detach it, and supervise it by asking Modal](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/gpu-runbook-measurements.md#a-long-tranche-detach-it-and-supervise-it-by-asking-modal) |
| <a id="0-what-you-are-shipping"></a>[0. What you are shipping](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/gpu-runbook-measurements.md#0-what-you-are-shipping) |
| <a id="1a-recommended-modal-free-within-the-monthly-credit"></a>[1a. Recommended: Modal (free within the monthly credit)](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/gpu-runbook-measurements.md#1a-recommended-modal-free-within-the-monthly-credit) |
| <a id="one-time-install-the-cli-in-the-projects-own-venv"></a>[One-time: install the CLI in the project's own venv](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/gpu-runbook-measurements.md#one-time-install-the-cli-in-the-projects-own-venv) |
| <a id="run-it"></a>[Run it](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/gpu-runbook-measurements.md#run-it) |
| <a id="--detach-and-why-it-is-not-optional"></a>[`--detach`, and why it is not optional](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/gpu-runbook-measurements.md#--detach-and-why-it-is-not-optional) |
| <a id="measured-full-corpus-2026-08-14"></a>[Measured, full corpus, 2026-08-14](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/gpu-runbook-measurements.md#measured-full-corpus-2026-08-14) |
| <a id="measured-again-2026-08-21-at-617038-vectors"></a>[Measured again, 2026-08-21, at 617,038 vectors](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/gpu-runbook-measurements.md#measured-again-2026-08-21-at-617038-vectors) |
| <a id="index-build-cost-at-scale-measured-2026-08-27"></a>[Index build cost at scale, measured 2026-08-27](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/gpu-runbook-measurements.md#index-build-cost-at-scale-measured-2026-08-27) |
| <a id="fine-tuning-modal_train_tibetanpy"></a>[Fine-tuning: `modal_train_tibetan.py`](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/gpu-runbook-measurements.md#fine-tuning-modal_train_tibetanpy) |
| <a id="--rebuild-index-was-broken-for-two-phases"></a>[`--rebuild-index` was broken for two phases](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/gpu-runbook-measurements.md#--rebuild-index-was-broken-for-two-phases) |
| <a id="1b-bis-a-top-up-on-modal-measured-end-to-end--2026-09-03"></a>[1b-bis. A top-up on Modal, measured end to end — 2026-09-03](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/gpu-runbook-measurements.md#1b-bis-a-top-up-on-modal-measured-end-to-end--2026-09-03) |
| <a id="1c-the-index-is-built-by-a-task-not-by-a-migration"></a>[1c. The index is built by a task, not by a migration](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/gpu-runbook-measurements.md#1c-the-index-is-built-by-a-task-not-by-a-migration) |
| <a id="1d-re-chunking-discards-vectors--the-builder-now-refuses"></a>[1d. Re-chunking discards vectors — the builder now refuses](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/gpu-runbook-measurements.md#1d-re-chunking-discards-vectors--the-builder-now-refuses) |
| <a id="1b-alternative-rent-the-box"></a>[1b. Alternative: rent the box](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/gpu-runbook-measurements.md#1b-alternative-rent-the-box) |
| <a id="2-upload-and-run"></a>[2. Upload and run](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/gpu-runbook-measurements.md#2-upload-and-run) |
| <a id="3-bring-the-vectors-home"></a>[3. Bring the vectors home](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/gpu-runbook-measurements.md#3-bring-the-vectors-home) |
| <a id="4-verify"></a>[4. Verify](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/gpu-runbook-measurements.md#4-verify) |
| <a id="5-dont-re-embed-by-accident"></a>[5. Don't re-embed by accident](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/gpu-runbook-measurements.md#5-dont-re-embed-by-accident) |
| <a id="cost-end-to-end"></a>[Cost, end to end](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/gpu-runbook-measurements.md#cost-end-to-end) |
