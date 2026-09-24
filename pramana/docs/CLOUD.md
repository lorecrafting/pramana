# Choosing compute

Separate corpus batch work, application/database hosting, and model-provider usage.
They have different workloads, costs and trust boundaries. The repository does not
require choosing the same vendor for all three.

| Work | What to establish before provisioning |
|---|---|
| Embedding / translation batches | Current row/token counts, model/artifact compatibility, measured throughput, source-data transfer rights, storage and egress, spend limit, timeout and cleanup |
| Research app and database | Dataset size, memory and connection budget, durable storage, extensions, backups/restore, networking and permitted data exposure |
| Model-backed research | Harness/tool compatibility, data handling, quality measured on the task, token/subscription billing terms |

Pramāṇa can serve lexical queries without GPU inference. Semantic query embedding
has a CPU-serving path; whether it meets a deployment's latency and memory targets is
a measurement, not a promise. Batch inference helpers under `priv/embed/` include
Modal workflows, but using them does not make the core research API provider-specific.

Self-hosting a reader is not inherently incompatible with a swappable model boundary.
Hosted APIs and self-hosted models each need compatible tool behavior, provenance
handling and the same post-generation verification. Choose on measured requirements,
not an unconditional "never self-host" rule.

No prices or free credits are asserted here. Verify current rates, quotas, billing
routes and termination behavior **before** authorizing spend. A free-credit allowance
is not a durable architecture property. A source lockfile is not a complete database
or operator-state backup.

[Embedding workflow](EMBEDDING.md) · [GPU runbook](GPU_RUNBOOK.md) · [Deployment](DEPLOY.md)

[The 2026-08-14 pricing comparison](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/cloud-pricing-2026-08-14.md) is retained
as historical research only; its prices and vendor rankings were not refreshed in this audit.

## Historical section bookmarks

These bookmarks open the retained pre-cleanup revision in Git history, not current instructions.
See [retired files](../../docs/RETIRED_FILES.md) for recovery and offline-access limits.

| Earlier section |
|---|
| <a id="cloud-what-to-rent-for-which-job"></a>[Cloud: What To Rent, For Which Job](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/cloud-pricing-2026-08-14.md#cloud-what-to-rent-for-which-job) |
| <a id="first-these-are-three-different-jobs-with-three-different-answers"></a>[First: these are three different jobs, with three different answers](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/cloud-pricing-2026-08-14.md#first-these-are-three-different-jobs-with-three-different-answers) |
| <a id="job-a--batch-embedding-289179-chunks-once"></a>[Job A — batch embedding: 289,179 chunks, once](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/cloud-pricing-2026-08-14.md#job-a--batch-embedding-289179-chunks-once) |
| <a id="why-aws-and-gcp-lose-this-one"></a>[Why AWS and GCP lose this one](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/cloud-pricing-2026-08-14.md#why-aws-and-gcp-lose-this-one) |
| <a id="recommendation-for-job-a-modal"></a>[Recommendation for job A: Modal](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/cloud-pricing-2026-08-14.md#recommendation-for-job-a-modal) |
| <a id="job-b--hosting-the-app-later-if-it-goes-public"></a>[Job B — hosting the app (later, if it goes public)](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/cloud-pricing-2026-08-14.md#job-b--hosting-the-app-later-if-it-goes-public) |
| <a id="job-c--llm-inference-for-the-research-agent-phase-7"></a>[Job C — LLM inference for the research agent (Phase 7)](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/cloud-pricing-2026-08-14.md#job-c--llm-inference-for-the-research-agent-phase-7) |
| <a id="cli-control-since-you-asked"></a>[CLI control, since you asked](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/cloud-pricing-2026-08-14.md#cli-control-since-you-asked) |
| <a id="bottom-line"></a>[Bottom line](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/cloud-pricing-2026-08-14.md#bottom-line) |
