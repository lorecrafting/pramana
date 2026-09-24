# Documentation audit — 2026-09-15

**Audited source:** `75a56c13ebafa0ab7e67f2cf12f47ad84aad2ebc` in `lorecrafting/pramana`.
This is a source/documentation audit, not a new corpus measurement or live-system
acceptance. [Complete original inventory](INVENTORY.md) · [Machine-readable census](inventory.json) ·
[Documentation](../../README.md).

## Scope and evidence levels

The census covers **108 tracked documentation/text files**: 107 Markdown documents
and the reader's `robots.txt`, totaling **34,964 lines** at the audited commit.
It includes root agent files, app READMEs, Pramāṇa references, Foundry operational
references, repair records and role templates. Source modules, tests, Mix projects,
configuration, migrations, scripts and workflows were inspected to check the main
operating and interface claims. Embedded source comments were inspected where they
bear on those claims; this is not a line-by-line audit of every code comment.

Every original document has an inventory row, but **a census is not proof of every
sentence**. Current interface/build/identity claims have source checks. Historical
experiments retain their dated evidence rather than being rerun. Research and
upstream terms/prices are labeled as requiring current external verification.
Foundry repair records were scanned as candidate-specific evidence, not re-accepted.

**Protected, byte-for-byte:** every pre-existing `foundry/` file, `docs/PLAN.md` and
`docs/PRODUCT_STRATEGY.md`. The product strategy received no substantive review or
rewrite. Foundry receives only a new navigation page; its repairs, roles, runtime,
acceptance records and ticket state are unchanged. The shared plan is indexed, not
split, while another implementation session owns active work.

## Corrected documentation defects

| Finding | Source evidence | Documentation treatment |
|---|---|---|
| Agent entry point had become a 360-line reference, with provider-specific entry files duplicating routing. | Original `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`; prior routing tests required the oversized shape. | Small shared router; import-only provider shims; task-scoped workflow, invariant, rule and test guides. No invented universal DeepSeek auto-loader. |
| The two independent systems were mixed in onboarding and tests. | [Root Mix project](../../../pramana/mix.exs), [Foundry Mix project](https://github.com/lorecrafting/pramana/blob/e1e4b3bf2c666f5d84652758afee446a0b21ebe1/foundry/mix.exs), [Foundry CI runner](https://github.com/lorecrafting/pramana/blob/e1e4b3bf2c666f5d84652758afee446a0b21ebe1/foundry/ci/run.exs). | Separate system routes and prerequisites. Foundry-only work does not acquire the research corpus or start its services. |
| MCP and reader counts/routes were stale; the web app README was scaffold text. | [MCP registration](../../../pramana/apps/pramana_web/lib/pramana_web/mcp/server.ex), [router](../../../pramana/apps/pramana_web/lib/pramana_web/router.ex). | Document all 19 registered tools, two resources and six reader routes; retain the existing bidirectional tool-table test. |
| `bake_id` was described as an immutable identity of all retrieval state; release tracking was simultaneously described as future work. | [Bake](../../../pramana/apps/pramana/lib/pramana/bake.ex), [Release](../../../pramana/apps/pramana/lib/pramana/release.ex), [Reply](../../../pramana/apps/pramana_web/lib/pramana_web/mcp/reply.ex). | Separate source-input identity, mutable loaded state and implemented but coarse release stamps. Do not promise frozen replay. |
| Citation checking was described as whole-span equality or making fabrication impossible. | [Guard](../../../pramana/apps/pramana/lib/pramana/guard.ex). | Explain trimmed byte-substring verification, existence-only checks, parser coverage and the absence of entailment proof. |
| Translation-pool design was presented as if every proposed cache, tier and purpose boundary existed. | [Translations](../../../pramana/apps/pramana/lib/pramana/translations.ex), [Translation schema](../../../pramana/apps/pramana/lib/pramana/corpus/schemas.ex), [transfer importer](../../../pramana/apps/pramana/lib/pramana/embed/transfer.ex). | Distinguish implemented selection/upsert behavior from T2 candidate-cache and index-only policy proposals. Human and generated renderings remain separately attributed. |
| Setup and test advice named a nonexistent framework-generation task and understated the quick gate's dependencies. | [Core Mix aliases](../../../pramana/apps/pramana/mix.exs), [gate](../../../pramana/apps/pramana/lib/mix/tasks/pramana.gate.ex), [figures task](../../../pramana/apps/pramana/lib/mix/tasks/pramana.docs.figures.ex). | Remove the fictional generator; document the actual alias location, explicit evaluation acceptance and database-dependent gate. Add genuinely model-free docs checks. |
| Native/Python boundaries and instrumentation were described inconsistently with implementation. | [Core dependencies](../../../pramana/apps/pramana/mix.exs), [quotation port](../../../pramana/native/quotations), [Python companion scripts](../../../pramana/priv/embed), [domain telemetry](../../../pramana/apps/pramana/lib/pramana/telemetry.ex). | Correct Phoenix PubSub versus web dependency, JSONL quotation boundary and existing telemetry. Preserve old audits as historical evidence. |
| Deployment and GPU notes blended dated prices, old commands and current safety guarantees. | [Runtime configuration](../../../pramana/config/runtime.exs), [Dockerfile](../../../pramana/Dockerfile), [task index](../../../pramana/docs/CLI.md), [public deployment guide](../../../pramana/docs/DEPLOY.md). | Separate current procedure from dated operator records; no fixed price recommendations, no claim that removing Mix makes a database read-only. |
| Long files mixed instructions, proposals, measurements and chronology. | Original primer, history, proxies, rules, checks, harness and status. | Split on topic boundaries, retain original heading anchors as forwarding links, preserve stable numbered rules, and keep generated figures at scanner-compatible top-level paths. |

## Implementation issues documented, not repaired

These are follow-up candidates, not permission to take over the active repair queue.

| Issue | Why it matters | Evidence / suggested verification |
|---|---|---|
| Release IDs summarize counts and model/translator identities, rather than hashing all indexed/rendered content. | Same-count content edits may be invisible; equal stamps do not prove equal answers. | Inspect `Pramana.Release.facts/0` and digest construction; add same-count mutation cases before strengthening any replay guarantee. |
| Release drift comparison omits the current source bake identity. | A source change can escape the derived-facts comparison. | Inspect `Pramana.Release.drift/0`; test source-only drift. |
| Error replies do not have the same release stamp as successful MCP replies. | A universal response-envelope claim is false. | Compare `PramanaWeb.MCP.Reply.error` and successful envelopes. Decide the desired API contract before changing it. |
| Guard recognition and diagnostic labels can be overinterpreted. | Zero recognized citations or existence-only checks are not verified quotations; absence from the loaded corpus is not proof of fabrication. | Test parser coverage, counts and diagnostics separately from semantic correctness. |
| The Rust toolchain is selected as floating `stable` in build configuration despite a pinning comment. | A source pin alone does not establish reproducible native builds. | Reconcile CI/Docker/toolchain policy in a separate build change. |
| Corpus figures and operational status remain recorded snapshots. | Git docs cannot demonstrate the current contents or health of an operator's local database. | Rerun authorized corpus/evaluation/figure checks in the intended environment; do not manufacture updated numbers in this PR. |
| Existing Foundry documents contain candidate-specific and legacy claims under active repair. | A green model-free build is not evidence of provider conformance, safe promotion or activation. | The unchanged Foundry repair plan, audit, ticket attestations and acceptance boundaries own this work. |

## Organization and context cost

`AGENTS.md` is a bookmark and routing contract, not a condensed copy of every guide.
`CLAUDE.md` and `GEMINI.md` import that router. Provider-independent requirements live
under `docs/agents/`; Pramāṇa invariants live under `docs/pramana/`; Foundry keeps its
own execution contracts. A model provider does not determine a CLI harness's file
loading behavior or authorize a subscription/billing route.

Humans enter through `docs/README.md`; `docs/CATALOG.md` is a complete lookup index,
not mandatory prompt context. Larger references have topic indexes and bounded
chapters. Historical and design records are labeled and linked to current guidance.
The largest protected repair/strategy/plan files remain intentionally unsplit.

Original rule numbers are retained. Long-guide heading fragments forward to their
new chapter locations. Existing historical content is not silently deleted because
it contradicts a later outcome. Old operating text retained in `docs/records/` is
explicitly **not** current procedure.

This reduces entry-point bytes and unnecessary loading. It does not claim a measured
token, latency or cost reduction across different providers/tokenizers. Archiving
superseded guides can increase total repository documentation while reducing the
amount required for an individual task.

## Validation contract and limits

The PR adds [standalone checks](../../../bin/check_docs.exs) and a
[documentation workflow](../../../.github/workflows/docs.yml). These check routing
budgets, transitive reachability of tracked Markdown files, relative inline links,
ATX/explicit heading fragments, stable rule coverage, task-module discovery and the
MCP tool table without starting an application or contacting a provider.

The link checker is not a full Markdown renderer or an external-link availability
check. One narrow exception is retained for the unchanged historical Foundry audit's
link to removed `pramana_diagnose.py`; it is named explicitly in the test and must be
removed if that reference is repaired. It is not an exemption for all Foundry links.

The migration checks protected-file hashes and stages an explicit path list. Generated
figure blocks stay in the files recognized by `Pramana.Docs.Figures`; they are not
recomputed without a corpus. Whitespace, source-to-doc checks and test results belong
to the candidate commit's CI evidence, not to this static prose.

**Not run or claimed by this audit:** full umbrella compilation/tests, database
migrations, retrieval/coverage benchmarks, corpus integrity/fidelity gates, GPU jobs,
provider sessions, Foundry promotion/activation, deployment, upstream licensing or
current vendor-price verification. Run the appropriate checks in
[TESTING](../../TESTING.md) before treating those properties as accepted.
