# Layers over source anchors

Translations, pronunciation readings and commentary alignments do not replace the
source text they describe. A local commentary can be a new work; a rendering of an
already-held source belongs in the translation pool instead of duplicating that work.

## Implemented layers

| Layer | Implementation | Current boundary |
|---|---|---|
| Translation pool | [Translations](../apps/pramana/lib/pramana/translations.ex), [schema](../apps/pramana/lib/pramana/corpus/schemas.ex) | Anchored renderings with method, tier, attribution and selection policy; not an immutable per-bake table |
| Reading exceptions and character readings | [Readings](../apps/pramana/lib/pramana/readings.ex) | Exceptions plus stored character readings; recognized scheme names do not imply complete dictionaries for every scheme |
| Tibetan Wylie rendering | [Reading modules](../apps/pramana/lib/pramana/readings) | Separate deterministic transliteration path; not a claim of complete phonetic translation |
| Work/passage commentary relations | [Commentary](../apps/pramana/lib/pramana/commentary.ex), [relations](../apps/pramana/lib/pramana/relations.ex) | Work relations and accepted lemma alignments are distinct evidence |
| Local source ingestion | [Manifest validation](../apps/pramana/lib/pramana/local/manifest.ex) | Required provenance, conservative licensing and declared addressing |

A rendering is addressed as `<source-anchor>#tr:<lang>/<translator-id>`.
A source citation and a human rendering citation answer different questions.
Generated text must not be accepted as canonical source evidence; see
[the invariants](INVARIANTS.md) and [translation contracts](TRANSLATION.md).

## Reading coverage is not a capability list

The reading layer can record several scheme names. Its render path has a distinct
Wylie implementation and otherwise uses lookup-based rendering. A declared scheme
alone does not prove that the necessary exceptions or ordinary readings are populated.
Unknown or explicitly disputed readings must not be converted into confident guesses.
The committed counts and benchmark examples are snapshots, not live coverage figures.

## Local text addressing

Use [ADDING_TEXTS](ADDING_TEXTS.md) for the actual manifest and commands, rather than
older illustrative YAML. The required nested `citation` mapping is not the old
`citation_grammar` sketch. Three declared addressing levels matter: `canonical`,
`edition_page` and `derived`. A printed-page local source should not be downgraded to
derived paragraph IDs merely because it is local.

Validation is a read-only preflight; adding or updating a local source is a mutation.
Keep raw evidence and hashes, use intrinsic anchors where available, and review the
effect of changed source files on existing citations. Do not assume a changed manifest
and a repeated identical import always require or produce different identities.

## Design material that is not a runtime guarantee

[The retained layer design](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/layer-design.md) includes broader reading schemes,
translation quality workflows and candidate-cache ideas. A schema sketch is not an
implemented service. In particular, the current code does not establish a
`translation_candidates` cache/promotion service or enforced separation of all
"index-only" English from reader-visible English.

[Translation](TRANSLATION.md) · [Commentary](COMMENTARY.md) · [Architecture](ARCHITECTURE.md)

## Historical section bookmarks

These bookmarks open the retained pre-cleanup revision in Git history, not current instructions.
See [retired files](RETIRED_FILES.md) for recovery and offline-access limits.

| Earlier section |
|---|
| <a id="layers-translations-readings-and-locally-added-texts"></a>[Layers: Translations, Readings, and Locally-Added Texts](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/layer-design.md#layers-translations-readings-and-locally-added-texts) |
| <a id="1-translation-layers"></a>[1. Translation layers](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/layer-design.md#1-translation-layers) |
| <a id="the-invariant-that-makes-this-safe"></a>[The invariant that makes this safe](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/layer-design.md#the-invariant-that-makes-this-safe) |
| <a id="why-this-also-improves-retrieval"></a>[Why this also improves retrieval](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/layer-design.md#why-this-also-improves-retrieval) |
| <a id="terminology-consistent-translation"></a>[Terminology-consistent translation](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/layer-design.md#terminology-consistent-translation) |
| <a id="2-reading-layers-pinyin-and-friends"></a>[2. Reading layers (pinyin and friends)](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/layer-design.md#2-reading-layers-pinyin-and-friends) |
| <a id="the-trap-generic-pinyin-is-wrong-for-buddhist-texts"></a>[The trap: generic pinyin is wrong for Buddhist texts](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/layer-design.md#the-trap-generic-pinyin-is-wrong-for-buddhist-texts) |
| <a id="storage"></a>[Storage](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/layer-design.md#storage) |
| <a id="3-locally-added-texts-one-off-commentaries"></a>[3. Locally-added texts (one-off commentaries)](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/layer-design.md#3-locally-added-texts-one-off-commentaries) |
| <a id="why-huang-nianzu-is-the-ideal-test-case"></a>[Why Huang Nianzu is the ideal test case](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/layer-design.md#why-huang-nianzu-is-the-ideal-test-case) |
| <a id="how-you-actually-add-one"></a>[How you actually add one](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/layer-design.md#how-you-actually-add-one) |
| <a id="citation-grammar-for-local-texts"></a>[Citation grammar for local texts](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/layer-design.md#citation-grammar-for-local-texts) |
| <a id="roadmap-placement"></a>[Roadmap placement](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/layer-design.md#roadmap-placement) |
