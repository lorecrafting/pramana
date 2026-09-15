# Status: recorded corpus snapshot

These generated blocks are retained from the audited source commit `75a56c13ebafa0ab7e67f2cf12f47ad84aad2ebc`.
They were not regenerated against a live database in this documentation audit.
Run the relevant [checks](TESTING.md) against the intended database to establish its state.

[Current architecture](ARCHITECTURE.md) · [Plan navigation](PLAN_INDEX.md) · [Recorded details](status/DETAILS.md)

## The corpus

**The counts below are generated.** `mix pramana.docs.figures` regenerates them from the
corpus and the gate fails when they are stale, because in one week this file and
`docs/PLAN.md` disagreed about the number of MCP tools while the directory settled it, and
`docs/ROADMAP.md` reported 27,254 commentary alignments when there were 72,120. Do not edit
between the markers; edit the corpus, or run the task.

<!-- figures:corpus -->
| | |
|---|---|
| texts | **17,281** |
| segments | **12,581,624** |
| chunks | **980,464** |
| vectors | **1,066,026** |
| renderings | **273,334** |
| glossary entries | **89,649** |
| quotations | **141,073** |
| MCP tools | **19** |
<!-- /figures -->

<!-- figures:relations -->
| | |
|---|---|
| work relations | **389** |
| comments_on | **269** |
| subcommentary_of | **38** |
| parallel_of | **82** |
| commentary alignments | **76,722** |
| root lines with commentary | **57,609** |
<!-- /figures -->

<!-- figures:derived -->
| | |
|---|---|
| commentary alignment | **100 of 184 alignable pair(s) — 77 distinct commentaries, 76,722 line alignments** |
| commentary -> root links | **194 of 3,923 commentarial works reach a root** |
| Tibetan work titles | **3,864 of 4,575 works named** |
<!-- /figures -->

Everything below this point is a person's prose about those numbers, and carries the usual
obligation: a measurement states its date, and a claim about what is *true now* is checked
against `mix pramana.doctor` when either file changes.

| | |
|---|---|
| Chinese (CBETA) | 4,263 works across **16 of 26 collections** — T 2,471 · X 1,230 · J 285 · I 101 · GA 51 · N 38 · F 27 · seven alternative editions 57 · GB 2 · ZS 1 |
| Pāli (SuttaCentral) | 8,442 works, **210,756** English renderings by 6 translators |
| Tibetan (Degé) | 1,195 Kangyur · 3,380 Tengyur, **30,653** English renderings from 84000 |
| English over Chinese | **3,354 human** renderings over **2 of 4,263** CBETA works, plus **28,571 generated** over **14 of 4,263** — 27,956 of them `model:mitra` across the top-10 by directed citation weight and the four Āgamas, new 2026-09-03. That is **27,956 of CBETA's 719,543 chunks — 3.88%**, up from 0.027%. Generated renderings are `tier: t1` and never citable as source (invariant #8) |
| commentary chains | **389 work relations** — 269 `comments_on`, 38 `subcommentary_of`, 82 `parallel_of`; **194 of 3,923 commentarial works reach a root, from 119**. The Tibetan 102 are new 2026-09-02 and are the first non-Chinese links: `toh4210` Pramāṇavārttika ← its vṛttis ← their ṭīkās. The **66 `shared_text`** are new 2026-09-02 and are the first found without a title: 大智度論 → 摩訶般若波羅蜜經. In rows the signals are `title_match` 240, `shared_text` 66, `manifest` 1; in distinct source works 156 / 66 / 1, and the difference is corroboration rather than duplication |
| commentary alignment | **76,722 lemmas over 100 pairs** — Chinese 74,644 over 83, **Tibetan 2,078 over 17, new 2026-09-03 and the first outside Chinese**. Forward order 86.7% over accepted pairs against 65.1% over the rest |
| Tibetan work titles | **3,864 of 4,575** named — the Kangyur's 1,189 from 84000, the Tengyur's 2,675 promoted out of `works.meta` on 2026-09-02. 711 have no title block in the edition |
| English renderings, all canons | **273,334** — 244,763 human by 8 translators, **28,571 generated** by 4 model arms (`tier: t1`, never citable as source) |
| glossary entries | **89,649** — 56,382 from 84000/Mahāvyutpatti plus **33,267** from DILA (Soothill-Hodous, Karashima ×3, Mahāvyutpatti), new 2026-09-02 |
| glossary anchors | **29,890** citations resolved against the bake — 25,504 to a line held (85.3%), **4,345 attested absences**, 41 unresolved |
| translators compared | Kumārajīva against Dharmarakṣa on the same sūtra: **601 shared Sanskrit headwords, 126 agreed, 475 diverged** — attested by Karashima, not inferred from n-grams |
| pipeline | **v5** · `verify --all`, `integrity` and `coherence` all green over every text |


## Recorded implementation and measurement details

| Topic |
|---|
| <a id="english-first-and-one-canon-is-not-reachable-that-way-yet"></a>[English-first, and one canon is not reachable that way yet](status/DETAILS.md#english-first-and-one-canon-is-not-reachable-that-way-yet) |
| <a id="what-it-can-do"></a>[What it can do](status/DETAILS.md#what-it-can-do) |
| <a id="the-boundary-of-the-claim"></a>[The boundary of the claim](status/DETAILS.md#the-boundary-of-the-claim) |
| <a id="what-it-deliberately-says-it-cannot-do"></a>[What it deliberately says it cannot do](status/DETAILS.md#what-it-deliberately-says-it-cannot-do) |
| <a id="v1-is-met-as-written-and-as-scoped"></a>[v1 is met, as written and as scoped](status/DETAILS.md#v1-is-met-as-written-and-as-scoped) |
| <a id="phases"></a>[Phases](status/DETAILS.md#phases) |
| <a id="the-public-artefact"></a>[The public artefact](status/DETAILS.md#the-public-artefact) |
| <a id="open-questions"></a>[Open questions](status/DETAILS.md#open-questions) |
| <a id="metrics"></a>[Metrics](status/DETAILS.md#metrics) |

## Earlier section bookmarks

| Earlier section |
|---|
| <a id="status"></a>[Status](status/DETAILS.md) |
| <a id="where-we-are"></a>[Where we are](status/DETAILS.md) |
