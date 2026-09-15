# Primer: What This System Is, How It Works, and What Everything Is Called

A guided introduction, divided into small chapters. Start at chapter 1, or use the topic links; agents should not preload this tutorial.

[Documentation](README.md) · [Current architecture](ARCHITECTURE.md) · [Testing](TESTING.md)

## Chapters

- [Table of contents](primer/01-table-of-contents.md)
- [4. The pipeline, end to end](primer/02-4-the-pipeline-end-to-end.md)
- [Vectors, from scratch](primer/03-vectors-from-scratch.md)
- [Addressing levels](primer/04-addressing-levels.md)
- [16. Licensing, and why it is a column](primer/05-16-licensing-and-why-it-is-a-column.md)
- [PostgreSQL and its extensions](primer/06-postgresql-and-its-extensions.md)

## Original topic links

These anchors preserve existing bookmarks. Follow the link to read the topic.

| Topic |
|---|
| <a id="primer-what-this-system-is-how-it-works-and-what-everything-is-called"></a>[Primer: What This System Is, How It Works, and What Everything Is Called](primer/01-table-of-contents.md#primer-what-this-system-is-how-it-works-and-what-everything-is-called) |
| <a id="table-of-contents"></a>[Table of contents](primer/01-table-of-contents.md#table-of-contents) |
| <a id="1-the-one-sentence-version"></a>[1. The one-sentence version](primer/01-table-of-contents.md#1-the-one-sentence-version) |
| <a id="2-the-problem-this-exists-to-solve"></a>[2. The problem this exists to solve](primer/01-table-of-contents.md#2-the-problem-this-exists-to-solve) |
| <a id="21-why-not-just-use-chatgpt"></a>[2.1 Why not just use ChatGPT?](primer/01-table-of-contents.md#21-why-not-just-use-chatgpt) |
| <a id="22-the-two-failure-modes"></a>[2.2 The two failure modes](primer/01-table-of-contents.md#22-the-two-failure-modes) |
| <a id="23-the-response"></a>[2.3 The response](primer/01-table-of-contents.md#23-the-response) |
| <a id="3-the-corpus-what-texts-are-we-talking-about"></a>[3. The corpus: what texts are we talking about](primer/01-table-of-contents.md#3-the-corpus-what-texts-are-we-talking-about) |
| <a id="31-the-chinese-canon-and-the-taishō"></a>[3.1 The Chinese canon and the Taishō](primer/01-table-of-contents.md#31-the-chinese-canon-and-the-taishō) |
| <a id="32-cbeta"></a>[3.2 CBETA](primer/01-table-of-contents.md#32-cbeta) |
| <a id="33-sat-and-the-gap"></a>[3.3 SAT, and the gap](primer/01-table-of-contents.md#33-sat-and-the-gap) |
| <a id="34-the-pāli-canon-and-suttacentral"></a>[3.4 The Pāli canon and SuttaCentral](primer/01-table-of-contents.md#34-the-pāli-canon-and-suttacentral) |
| <a id="35-current-size"></a>[3.5 Current size](primer/01-table-of-contents.md#35-current-size) |
| <a id="4-the-pipeline-end-to-end"></a>[4. The pipeline, end to end](primer/02-4-the-pipeline-end-to-end.md#4-the-pipeline-end-to-end) |
| <a id="5-stage-1--acquire"></a>[5. Stage 1 — Acquire](primer/02-4-the-pipeline-end-to-end.md#5-stage-1--acquire) |
| <a id="what-ingesting-means"></a>[What "ingesting" means](primer/02-4-the-pipeline-end-to-end.md#what-ingesting-means) |
| <a id="pinning-and-why"></a>[Pinning, and why](primer/02-4-the-pipeline-end-to-end.md#pinning-and-why) |
| <a id="sparse-checkout"></a>[Sparse checkout](primer/02-4-the-pipeline-end-to-end.md#sparse-checkout) |
| <a id="6-stage-2--normalize"></a>[6. Stage 2 — Normalize](primer/02-4-the-pipeline-end-to-end.md#6-stage-2--normalize) |
| <a id="the-problem"></a>[The problem](primer/02-4-the-pipeline-end-to-end.md#the-problem) |
| <a id="the-ir"></a>[The IR](primer/02-4-the-pipeline-end-to-end.md#the-ir) |
| <a id="things-that-make-this-harder-than-it-sounds"></a>[Things that make this harder than it sounds](primer/02-4-the-pipeline-end-to-end.md#things-that-make-this-harder-than-it-sounds) |
| <a id="7-stage-3--segment"></a>[7. Stage 3 — Segment](primer/02-4-the-pipeline-end-to-end.md#7-stage-3--segment) |
| <a id="what-a-segment-is"></a>[What a segment is](primer/02-4-the-pipeline-end-to-end.md#what-a-segment-is) |
| <a id="the-rule-that-matters-most"></a>[The rule that matters most](primer/02-4-the-pipeline-end-to-end.md#the-rule-that-matters-most) |
| <a id="8-stage-4--chunk"></a>[8. Stage 4 — Chunk](primer/02-4-the-pipeline-end-to-end.md#8-stage-4--chunk) |
| <a id="what-chunking-means"></a>[What "chunking" means](primer/02-4-the-pipeline-end-to-end.md#what-chunking-means) |
| <a id="why-segments-are-the-wrong-unit-for-search"></a>[Why segments are the wrong unit for search](primer/02-4-the-pipeline-end-to-end.md#why-segments-are-the-wrong-unit-for-search) |
| <a id="the-property-that-keeps-chunks-honest"></a>[The property that keeps chunks honest](primer/02-4-the-pipeline-end-to-end.md#the-property-that-keeps-chunks-honest) |
| <a id="a-size-is-a-per-script-decision"></a>[A size is a per-script decision](primer/02-4-the-pipeline-end-to-end.md#a-size-is-a-per-script-decision) |
| <a id="9-stage-5--embed"></a>[9. Stage 5 — Embed](primer/02-4-the-pipeline-end-to-end.md#9-stage-5--embed) |
| <a id="vectors-from-scratch"></a>[Vectors, from scratch](primer/03-vectors-from-scratch.md#vectors-from-scratch) |
| <a id="the-model"></a>[The model](primer/03-vectors-from-scratch.md#the-model) |
| <a id="why-a-gpu-and-the-exportimport-round-trip"></a>[Why a GPU, and the export/import round trip](primer/03-vectors-from-scratch.md#why-a-gpu-and-the-exportimport-round-trip) |
| <a id="multi-vector-embeddings-in-progress-40"></a>[Multi-vector embeddings (in progress, #40)](primer/03-vectors-from-scratch.md#multi-vector-embeddings-in-progress-40) |
| <a id="10-stage-6--retrieve"></a>[10. Stage 6 — Retrieve](primer/03-vectors-from-scratch.md#10-stage-6--retrieve) |
| <a id="101-lexical-search--matching-characters"></a>[10.1 Lexical search — matching characters](primer/03-vectors-from-scratch.md#101-lexical-search--matching-characters) |
| <a id="102-semantic-search--matching-meaning"></a>[10.2 Semantic search — matching meaning](primer/03-vectors-from-scratch.md#102-semantic-search--matching-meaning) |
| <a id="103-hybrid--using-both"></a>[10.3 Hybrid — using both](primer/03-vectors-from-scratch.md#103-hybrid--using-both) |
| <a id="11-stage-7--resolve-and-verify"></a>[11. Stage 7 — Resolve and verify](primer/03-vectors-from-scratch.md#11-stage-7--resolve-and-verify) |
| <a id="resolve"></a>[Resolve](primer/03-vectors-from-scratch.md#resolve) |
| <a id="the-citation-guard"></a>[The citation guard](primer/03-vectors-from-scratch.md#the-citation-guard) |
| <a id="one-level-up-verifying-a-whole-report"></a>[One level up: verifying a whole report](primer/03-vectors-from-scratch.md#one-level-up-verifying-a-whole-report) |
| <a id="12-addressing-the-urn-scheme"></a>[12. Addressing: the URN scheme](primer/03-vectors-from-scratch.md#12-addressing-the-urn-scheme) |
| <a id="why-translations-are-a-fragment"></a>[Why translations are a fragment](primer/03-vectors-from-scratch.md#why-translations-are-a-fragment) |
| <a id="addressing-levels"></a>[Addressing levels](primer/04-addressing-levels.md#addressing-levels) |
| <a id="13-provenance-who-made-this-text-and-when"></a>[13. Provenance: who made this text and when](primer/04-addressing-levels.md#13-provenance-who-made-this-text-and-when) |
| <a id="131-a-byline-is-not-a-person"></a>[13.1 A byline is not a person](primer/04-addressing-levels.md#131-a-byline-is-not-a-person) |
| <a id="132-what-an-identity-buys-dates-lineage-place"></a>[13.2 What an identity buys: dates, lineage, place](primer/04-addressing-levels.md#132-what-an-identity-buys-dates-lineage-place) |
| <a id="14-layers-translations-and-readings"></a>[14. Layers: translations and readings](primer/04-addressing-levels.md#14-layers-translations-and-readings) |
| <a id="141-the-translation-pool"></a>[14.1 The translation pool](primer/04-addressing-levels.md#141-the-translation-pool) |
| <a id="142-the-reading-layer"></a>[14.2 The reading layer](primer/04-addressing-levels.md#142-the-reading-layer) |
| <a id="15-parallels-the-same-discourse-in-two-languages"></a>[15. Parallels: the same discourse in two languages](primer/04-addressing-levels.md#15-parallels-the-same-discourse-in-two-languages) |
| <a id="16-licensing-and-why-it-is-a-column"></a>[16. Licensing, and why it is a column](primer/05-16-licensing-and-why-it-is-a-column.md#16-licensing-and-why-it-is-a-column) |
| <a id="17-the-integrity-machinery"></a>[17. The integrity machinery](primer/05-16-licensing-and-why-it-is-a-column.md#17-the-integrity-machinery) |
| <a id="the-bake"></a>[The bake](primer/05-16-licensing-and-why-it-is-a-column.md#the-bake) |
| <a id="two-different-checks-and-the-distinction-between-them"></a>[Two different checks, and the distinction between them](primer/05-16-licensing-and-why-it-is-a-column.md#two-different-checks-and-the-distinction-between-them) |
| <a id="the-gate-ci-for-a-dataset-not-just-for-code"></a>[The gate: CI for a dataset, not just for code](primer/05-16-licensing-and-why-it-is-a-column.md#the-gate-ci-for-a-dataset-not-just-for-code) |
| <a id="test-coverage-and-the-ratchet"></a>[Test coverage, and the ratchet](primer/05-16-licensing-and-why-it-is-a-column.md#test-coverage-and-the-ratchet) |
| <a id="the-invariants"></a>[The invariants](primer/05-16-licensing-and-why-it-is-a-column.md#the-invariants) |
| <a id="18-the-technology-stack"></a>[18. The technology stack](primer/05-16-licensing-and-why-it-is-a-column.md#18-the-technology-stack) |
| <a id="elixir-and-the-beam"></a>[Elixir and the BEAM](primer/05-16-licensing-and-why-it-is-a-column.md#elixir-and-the-beam) |
| <a id="postgresql-and-its-extensions"></a>[PostgreSQL and its extensions](primer/06-postgresql-and-its-extensions.md#postgresql-and-its-extensions) |
| <a id="mcp"></a>[MCP](primer/06-postgresql-and-its-extensions.md#mcp) |
| <a id="modal"></a>[Modal](primer/06-postgresql-and-its-extensions.md#modal) |
| <a id="19-how-to-actually-run-things"></a>[19. How to actually run things](primer/06-postgresql-and-its-extensions.md#19-how-to-actually-run-things) |
| <a id="20-glossary"></a>[20. Glossary](primer/06-postgresql-and-its-extensions.md#20-glossary) |
| <a id="21-where-to-read-next"></a>[21. Where to read next](primer/06-postgresql-and-its-extensions.md#21-where-to-read-next) |
