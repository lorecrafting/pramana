# Translation: implemented pool and proposed workflows

**Working directory:** `pramana/` for the commands and source-relative paths below.
Shared policy and the active plan remain at repository `docs/`. Existing corpus,
models and virtualenvs are not moved: see [layout migration](../../docs/LAYOUT_MIGRATION.md).

There is no single winning translation in the data model. The implemented pool keeps
renderings anchored to source passages and lets callers supply a selection policy.
This document separates that implementation from the larger
[translation design and experiments](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/translation-design-and-experiments.md).

## What the pool stores

[The schema](../apps/pramana/lib/pramana/corpus/schemas.ex) records `anchor_urn`, language,
translator identity, tier, method, text/hash, model/prompt/glossary metadata, review
state, license fields and attribution. [Translations](../apps/pramana/lib/pramana/translations.ex)
owns the validated selection policy and presentation.

Policies include language, translator/model, tier preference, comparison mode,
redistributability and minimum review state. `mode: :compare` exposes the selected
pool; a single selection can report alternatives rather than hiding their existence.
Re-importing the **same** anchor/language/translator key can update it; adding a
**different** translator key adds another rendering. The table is not immutable per bake.

`t0`, `t1` and `t2` are recognized tier values. That does not establish an implemented
query-time translation service. The proposed T2 cache/promotion table
`translation_candidates` is absent from current Ecto schemas and migrations do not
create it. Do not document the proposed cache hit behavior as a shipped guarantee.

## Source versus rendering

A rendering URN is a fragment over its source anchor. Presentation labels translations
`citable_as_source: false`. The source language remains separate from renderings in
passage responses. A human translation can be checked and attributed **as a translation**;
that does not make it the original-language witness. Generated text must not be accepted
as canonical source evidence.

The guard verifies recognized quotations or citation existence, not translation
faithfulness or entailment. A quoted passage can be genuine while its paraphrase is wrong.
Null review/quality fields do not count as successful quality checks.

## Batch export and import

The [export task](../apps/pramana/lib/mix/tasks/pramana.translate.export.ex),
[import task](../apps/pramana/lib/mix/tasks/pramana.translate.import.ex) and
[transfer implementation](../apps/pramana/lib/pramana/translate/transfer.ex) define
the supported round trip. Review flags with `mix help` before running a paid batch.

```bash
mix pramana.translate.export --covered-by patton --limit 300 --out /tmp/bakeoff.jsonl
# Run the reviewed inference workflow with explicit provider/spend authorization.
mix pramana.translate.import --in /tmp/renderings.jsonl --translator-id model:EXACT_RUN_ID
```

The import checks a returned row's chunk identity/content hash and reports mismatched
or empty rows. Imported generated renderings are `tier: "t1"`, `method: "llm"`,
`review_state: "raw"`; the current path assigns non-redistributable license metadata.
A round-trip hash checks attachment to source text, not accuracy of the translation.
An operator must verify model identity, actual output metadata and applicable rights.

The current importer records prompt/config metadata supplied by the artifact. Do not
infer that every glossary, sampling setting or output byte is pinned by `bake_id`.
[Release stamps](ARCHITECTURE.md#identity-and-replay) have additional limitations.

## Index English versus reader English

These are useful **design purposes**, with different evaluation requirements.
The existing translation schema has no enforced `purpose` column separating them,
and presentation may serve selected generated renderings. The prior statement that
index English is "never" shown is not an implemented isolation guarantee.

Likewise, `glossary_compliance` and `consensus_score` fields do not prove that an
end-to-end scoring/promotion workflow is populated or enforced. Define and test that
workflow before relying on it. Model agreement alone is not evidence of correctness.

[Layers](LAYERS.md) · [GPU runbook](GPU_RUNBOOK.md) · [Testing](../../docs/TESTING.md)

## Historical section bookmarks

These bookmarks open the retained pre-cleanup revision in Git history, not current instructions.
See [retired files](../../docs/RETIRED_FILES.md) for recovery and offline-access limits.

| Earlier section |
|---|
| <a id="translation-baked-layers-on-the-fly-and-model-multiplicity"></a>[Translation: Baked Layers, On-the-Fly, and Model Multiplicity](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/translation-design-and-experiments.md#translation-baked-layers-on-the-fly-and-model-multiplicity) |
| <a id="the-reframe"></a>[The reframe](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/translation-design-and-experiments.md#the-reframe) |
| <a id="three-tiers"></a>[Three tiers](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/translation-design-and-experiments.md#three-tiers) |
| <a id="two-purposes-and-the-bar-is-different--decided-2026-09-02"></a>[Two PURPOSES, and the bar is different — decided 2026-09-02](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/translation-design-and-experiments.md#two-purposes-and-the-bar-is-different--decided-2026-09-02) |
| <a id="index-english-does-not-have-to-be-readable-and-may-not-want-to-be-prose"></a>[Index English does not have to be readable, and may not want to be prose](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/translation-design-and-experiments.md#index-english-does-not-have-to-be-readable-and-may-not-want-to-be-prose) |
| <a id="reader-english-is-a-different-obligation"></a>[Reader English is a different obligation](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/translation-design-and-experiments.md#reader-english-is-a-different-obligation) |
| <a id="what-this-system-guarantees-and-what-it-does-not"></a>[What this system guarantees, and what it does not](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/translation-design-and-experiments.md#what-this-system-guarantees-and-what-it-does-not) |
| <a id="the-translation-layer-is-meant-to-be-replaced-and-the-pool-already-allows-it"></a>[The translation layer is meant to be replaced, and the pool already allows it](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/translation-design-and-experiments.md#the-translation-layer-is-meant-to-be-replaced-and-the-pool-already-allows-it) |
| <a id="why-ephemeral-output-does-not-go-straight-into-the-bake"></a>[Why ephemeral output does not go straight into the bake](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/translation-design-and-experiments.md#why-ephemeral-output-does-not-go-straight-into-the-bake) |
| <a id="getting-text-to-a-model-and-back--export--import-built-2026-09-02"></a>[Getting text to a model and back — `export` / `import`, built 2026-09-02](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/translation-design-and-experiments.md#getting-text-to-a-model-and-back--export--import-built-2026-09-02) |
| <a id="the-promotion-pipeline"></a>[The promotion pipeline](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/translation-design-and-experiments.md#the-promotion-pipeline) |
| <a id="divergence-as-a-feature-not-a-problem"></a>[Divergence as a feature, not a problem](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/translation-design-and-experiments.md#divergence-as-a-feature-not-a-problem) |
| <a id="selection-policy-at-the-api"></a>[Selection policy at the API](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/translation-design-and-experiments.md#selection-policy-at-the-api) |
| <a id="cost-and-latency"></a>[Cost and latency](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/translation-design-and-experiments.md#cost-and-latency) |
| <a id="four-levers-and-the-order-to-reach-for-them"></a>[Four levers, and the order to reach for them](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/translation-design-and-experiments.md#four-levers-and-the-order-to-reach-for-them) |
| <a id="the-decoupling-contract-holds"></a>[The decoupling contract holds](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/translation-design-and-experiments.md#the-decoupling-contract-holds) |
| <a id="prior-art-we-already-own"></a>[Prior art we already own](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/translation-design-and-experiments.md#prior-art-we-already-own) |
| <a id="roadmap-placement"></a>[Roadmap placement](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/translation-design-and-experiments.md#roadmap-placement) |
