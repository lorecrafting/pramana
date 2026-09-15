# Archived GPU_RUNBOOK.md: gpu-runbook-measurements

Dated evidence, not a description of the running system. Entries retain the observations and reversals that motivated later changes.

[Documentation](../README.md) · [Current architecture](../ARCHITECTURE.md) · [Testing](../TESTING.md)

## Chapters

- [A long tranche: detach it, and supervise it by asking Modal](gpu-runbook-measurements/01-a-long-tranche-detach-it-and-supervise-it-by-asking-modal.md)
- [Index build cost at scale, measured 2026-08-27](gpu-runbook-measurements/02-index-build-cost-at-scale-measured-2026-08-27.md)
- [4. Verify](gpu-runbook-measurements/03-4-verify.md)

## Original topic links

These anchors preserve existing bookmarks. Follow the link to read the topic.

| Topic |
|---|
| <a id="archived-gpu_runbookmd-gpu-runbook-measurements"></a>[Archived GPU_RUNBOOK.md: gpu-runbook-measurements](gpu-runbook-measurements/01-a-long-tranche-detach-it-and-supervise-it-by-asking-modal.md#archived-gpu_runbookmd-gpu-runbook-measurements) |
| <a id="runbook-embedding-the-corpus-on-a-rented-gpu"></a>[Runbook: Embedding the Corpus on a Rented GPU](gpu-runbook-measurements/01-a-long-tranche-detach-it-and-supervise-it-by-asking-modal.md#runbook-embedding-the-corpus-on-a-rented-gpu) |
| <a id="a-long-tranche-detach-it-and-supervise-it-by-asking-modal"></a>[A long tranche: detach it, and supervise it by asking Modal](gpu-runbook-measurements/01-a-long-tranche-detach-it-and-supervise-it-by-asking-modal.md#a-long-tranche-detach-it-and-supervise-it-by-asking-modal) |
| <a id="0-what-you-are-shipping"></a>[0. What you are shipping](gpu-runbook-measurements/01-a-long-tranche-detach-it-and-supervise-it-by-asking-modal.md#0-what-you-are-shipping) |
| <a id="1a-recommended-modal-free-within-the-monthly-credit"></a>[1a. Recommended: Modal (free within the monthly credit)](gpu-runbook-measurements/01-a-long-tranche-detach-it-and-supervise-it-by-asking-modal.md#1a-recommended-modal-free-within-the-monthly-credit) |
| <a id="one-time-install-the-cli-in-the-projects-own-venv"></a>[One-time: install the CLI in the project's own venv](gpu-runbook-measurements/01-a-long-tranche-detach-it-and-supervise-it-by-asking-modal.md#one-time-install-the-cli-in-the-projects-own-venv) |
| <a id="run-it"></a>[Run it](gpu-runbook-measurements/01-a-long-tranche-detach-it-and-supervise-it-by-asking-modal.md#run-it) |
| <a id="--detach-and-why-it-is-not-optional"></a>[`--detach`, and why it is not optional](gpu-runbook-measurements/01-a-long-tranche-detach-it-and-supervise-it-by-asking-modal.md#--detach-and-why-it-is-not-optional) |
| <a id="measured-full-corpus-2026-08-14"></a>[Measured, full corpus, 2026-08-14](gpu-runbook-measurements/01-a-long-tranche-detach-it-and-supervise-it-by-asking-modal.md#measured-full-corpus-2026-08-14) |
| <a id="measured-again-2026-08-21-at-617038-vectors"></a>[Measured again, 2026-08-21, at 617,038 vectors](gpu-runbook-measurements/01-a-long-tranche-detach-it-and-supervise-it-by-asking-modal.md#measured-again-2026-08-21-at-617038-vectors) |
| <a id="index-build-cost-at-scale-measured-2026-08-27"></a>[Index build cost at scale, measured 2026-08-27](gpu-runbook-measurements/02-index-build-cost-at-scale-measured-2026-08-27.md#index-build-cost-at-scale-measured-2026-08-27) |
| <a id="fine-tuning-modal_train_tibetanpy"></a>[Fine-tuning: `modal_train_tibetan.py`](gpu-runbook-measurements/02-index-build-cost-at-scale-measured-2026-08-27.md#fine-tuning-modal_train_tibetanpy) |
| <a id="--rebuild-index-was-broken-for-two-phases"></a>[`--rebuild-index` was broken for two phases](gpu-runbook-measurements/02-index-build-cost-at-scale-measured-2026-08-27.md#--rebuild-index-was-broken-for-two-phases) |
| <a id="1b-bis-a-top-up-on-modal-measured-end-to-end--2026-09-03"></a>[1b-bis. A top-up on Modal, measured end to end — 2026-09-03](gpu-runbook-measurements/02-index-build-cost-at-scale-measured-2026-08-27.md#1b-bis-a-top-up-on-modal-measured-end-to-end--2026-09-03) |
| <a id="1c-the-index-is-built-by-a-task-not-by-a-migration"></a>[1c. The index is built by a task, not by a migration](gpu-runbook-measurements/02-index-build-cost-at-scale-measured-2026-08-27.md#1c-the-index-is-built-by-a-task-not-by-a-migration) |
| <a id="1d-re-chunking-discards-vectors--the-builder-now-refuses"></a>[1d. Re-chunking discards vectors — the builder now refuses](gpu-runbook-measurements/02-index-build-cost-at-scale-measured-2026-08-27.md#1d-re-chunking-discards-vectors--the-builder-now-refuses) |
| <a id="1b-alternative-rent-the-box"></a>[1b. Alternative: rent the box](gpu-runbook-measurements/02-index-build-cost-at-scale-measured-2026-08-27.md#1b-alternative-rent-the-box) |
| <a id="2-upload-and-run"></a>[2. Upload and run](gpu-runbook-measurements/02-index-build-cost-at-scale-measured-2026-08-27.md#2-upload-and-run) |
| <a id="3-bring-the-vectors-home"></a>[3. Bring the vectors home](gpu-runbook-measurements/02-index-build-cost-at-scale-measured-2026-08-27.md#3-bring-the-vectors-home) |
| <a id="4-verify"></a>[4. Verify](gpu-runbook-measurements/03-4-verify.md#4-verify) |
| <a id="5-dont-re-embed-by-accident"></a>[5. Don't re-embed by accident](gpu-runbook-measurements/03-4-verify.md#5-dont-re-embed-by-accident) |
| <a id="cost-end-to-end"></a>[Cost, end to end](gpu-runbook-measurements/03-4-verify.md#cost-end-to-end) |
