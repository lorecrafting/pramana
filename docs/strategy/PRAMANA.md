# Pramāṇa: the research product

[Strategy overview](../PRODUCT_STRATEGY.md) · [Pilot charter](PILOT_CHARTER.md) · [Pilot preflight](PILOT_PREFLIGHT.md) · [Roadmap](ROADMAP.md)
**Status:** proposed product choices, not an inventory of completed features.

## Customer and job

The initial pilot deliberately spans **scholars/researchers, serious practitioners or
study leaders, and ordinary curious readers** around one common job:

**ask a real Dharma question, understand an answer, inspect what the texts actually
support, and leave with sources that can be checked or reused.**

The product should progressively disclose depth rather than force one audience's interface
on the others. Scholars need exact provenance and relation evidence; practitioners need
trustworthy explanatory context; ordinary readers need plain language and a clear path to
the source. The pilot reports each stratum separately so a good result for experts cannot
hide a product that ordinary readers cannot use.

Do not make full philological apparatus or general spiritual advice prerequisites for the
first useful workflow. The product is a research aid, not a guru, clinical service or
adjudicator of a person's practice or realization.

The preregistered task classes are owned by
[the pilot charter](PILOT_CHARTER.md#cohort-and-task-set): remembered quotation,
doctrinal/practice question, multi-passage synthesis, ambiguous interpretation,
missing/unsupported-source case and evidence reuse. The separate Chinese/Tibetan
compatibility track tests root/treatise/commentary distinctions that the first Pāli user
scope cannot adequately exercise. Compare each participant's user tasks with their current
process, including existing archives and ordinary model-assisted search.

## Scope: narrow the experience, retain the substrate

Recommend a **single selected canon or collection for each initial workflow**.
Show that scope before retrieval and retain it throughout the session. A preference
for a lineage can guide the choice but is not equivalent to a corpus language,
composition origin or text role. A Tibetan corpus is not synonymous with Vajrayāna;
Chinese-language material is not one school's doctrine.

Choose the pilot scope at G1 using real tasks and the recorded corpus limitations:

| Candidate | Reason to investigate | Required check before selection |
|---|---|---|
| A Pāli collection | A relatively direct path from original passages to existing human English renderings in the recorded snapshot | Task coverage, attribution, export permissions and actual retrieval success |
| A Tibetan collection | Fit for an Indo-Tibetan study cohort and commentary-oriented work | English access, missing witnesses/titles, translation alignment and a qualified evaluator |
| A Chinese collection | Potentially valuable English-discovery gap and rich commentarial material | Whether selected tasks are findable and readable without presenting generated glosses as authoritative translations |

Those were selection hypotheses. D2 was revised on 2026-09-17 after the product goal
was clarified: **commentary/treatise depth is a central first-pilot value**, not only future
compatibility. The initial user pilot is now a bounded Chinese CBETA scope built from the
live equivalents of the recorded 14 demand-weighted seed works plus accepted
commentary/subcommentary neighborhoods. [The pilot charter](PILOT_CHARTER.md) and
[preflight](PILOT_PREFLIGHT.md) own the exact scope, bilingual architecture, thresholds and
stop rules.

English accessibility is supplied by multi-arm English→Chinese retrieval and bounded
on-demand reading translation; the Chinese witness remains the textual evidence. The
selection is contingent on operation-specific CBETA/lexicon/model-processing rights and
qualified Buddhist-Chinese evaluation. If those prerequisites cannot be satisfied, D2
reopens explicitly; there is no automatic Pāli/Tibetan/broader-Chinese fallback.

[STATUS](../../pramana/docs/STATUS.md) is a dated snapshot, not the live database. The
pilot must rematerialize its exact seed IDs and relations from the accepted release rather
than treating historical ranking prose as an immutable list.

Retain supported search, parallels and comparisons across the current corpus.
Automatic multi-canon synthesis is a later experience with its own evaluation,
not a deletion of existing APIs or a new promise that every comparison works.

## One complete workflow

**Scope → find → inspect → assess → reuse.** Reuse the existing search, passage,
work and check surfaces. The [reader reference](../../pramana/docs/READER.md) and [MCP reference](../../pramana/docs/MCP.md)
own implemented routes; the [architecture](../../pramana/docs/ARCHITECTURE.md) owns their limits.

1. **Scope and find.** Accept a question, terms or a quotation. Display active
   collections, retrieval mode and meaningful coverage gaps. A zero result means
   no result under the stated search, not that the tradition has no teaching.
2. **Inspect.** Open the source in context without losing the question. Display
   original text, selected human rendering, source coordinates, attribution and
   text role. Use a responsive inspector rather than requiring a wide dual-pane
   layout on every device. Expand from the citation to a meaningful passage.
3. **Assess.** Distinguish direct quotation, paraphrase and interpretive synthesis.
   A synthesis claim must point to its supporting passage and explain the kind of
   support. Show disagreement or insufficient evidence instead of forcing a verdict.
4. **Reuse.** Export an evidence packet: question/scope, source identifiers, exact
   quoted text and context reference, rendering attribution, verification method,
   relevant state identity, limitations and permitted citation format. Begin with
   dependable copy/export; add format variants in response to actual demand.

Synthesis may be a thin optional layer over this workflow. First validate that the
retrieved evidence is useful. Do not build an autonomous research-agent framework
before source discovery and the evidence packet work. Unchecked streaming text
must not receive a verified badge; buffer checked units or label them pending.

## Trust contract: five separate questions

| Question | Evidence needed | What not to imply |
|---|---|---|
| Does this quotation occur at this address? | Resolved source, recognized quoted span, matching bytes and verifier result | That every assertion surrounding it is true |
| What work, edition and role is it? | Catalogue/provenance records, method and uncertainty | That metadata is infallible or every work is correctly classified |
| Is this a faithful English rendering? | Named human translation or explicit generated-layer status; competent review where required | That byte matching can validate translation quality |
| Does this passage support this interpretation? | Context, an explicit claim-evidence relationship and qualified assessment | That a source badge proves entailment or doctrinal consensus |
| How broad was the search? | Loaded/searchable scope, missing sources, retrieval mode and evaluation | That top-k results or no match establish exhaustive absence |

The existing guard does **not** solve all five questions. An existence-only check
is not a verified quotation. An output with no recognized citations is not wholly
verified. [Architecture](../../pramana/docs/ARCHITECTURE.md#citation-verification-precisely) describes
current checking; I-P2 supplies the proposed presentation and acceptance contract.

Replace “85% canonical” and “unattested/spurious” scores with precise states such
as **quotation matched**, **address resolved only**, **commentarial source**,
**interpretation requires review**, or **no support found in this searched scope**.
Commentarial status is provenance, not a lower truth grade. A historical quotation
can be cited correctly while the speaker's claim remains contested.

## Human scholarship, generated layers and reuse

Prefer clearly attributed human renderings in the pilot. Human authorship alone
does not imply peer review, agreement or flawless translation. Keep source text,
human renderings, machine aids and user notes separate in both display and storage.
A generated search gloss may help discovery without becoming publishable scripture
or an approved reading translation. Initial partner deployments should be able to
operate without generated reading aids; any later opt-in needs explicit labeling
and the partner's rules. [Translation](../../pramana/docs/TRANSLATION.md) distinguishes implemented
behavior from proposed purpose-based controls.

Source licensing, display, export, model processing and hosting permissions must
be checked for the actual editions and renderings. A source's availability is not
permission for every use, and source-policy compliance is not partner endorsement.
84000's published policy is a stakeholder constraint for relevant collaboration,
not a policy we can declare satisfied by a hash. See [E7–E10](RESEARCH.md#buddhist-sources-and-stakeholders).

Private notebooks and uploaded work require access control, deletion/export choices,
retention and provider-disclosure rules before persistent storage. Research telemetry
should record minimal task events by default, not private spiritual questions or
full texts for training. A retained evidence digest does not require retaining
unnecessary personal content indefinitely.

## Depth only when it helps the task

The commentary/lineage inspector is a promising differentiator: show root text,
commentary and subcommentary with typed, attributable relationships. Reuse existing
relations, alignments and quotation data before introducing a new graph store.
Text reuse alone does not prove direction of influence, and role labels alone do
not establish chronology. Display candidate versus supported edges, ambiguous
matches, missing endpoints, traversal bounds and cycles. Never manufacture a
complete lineage to make a diagram attractive.

Terminology popovers, variants, facsimiles and translator comparisons belong inside
this inspector, not in separate launch-sized products. OCR agreement with stored
text is not fidelity to the printed image; image/edition linkage needs its own
quality check. Collaboration, large-scale OCR and automatic cross-canon synthesis
remain expansion options with named gates in the roadmap.

## Differentiation and distribution

Position Pramāṇa as a careful evidence workspace that complements archives,
translation projects and models. Do not claim to be the only English search tool
or that a particular publication has no reliable citations. Validate advantage by
observing research time, errors and repeat use, not by attacking alternatives.

Begin with a small, permission-aware design-partner pilot and genuinely reusable
source packets. Share examples only with consent and valid attribution. Public
search and citation checking can support discovery, but viral fact-check cards are
not a business model. Retain the self-hosted/open-source direction from the existing
phase record; distribution and sustainability choices require the separate checks
in [Validation](VALIDATION.md#sustainability-and-distribution).
