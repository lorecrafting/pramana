# Pramāṇa pilot charter

**Status:** operator-approved product direction; implementation remains gated by Foundry G0.
**Decision date:** 2026-09-17
**Source baseline:** `ac80923d4795be84b0f432031ad6e17a330f589f`
**Strategic initiative:** I-P1, preparing I-P2/I-P3 after G0.

[Pramāṇa strategy](PRAMANA.md) · [validation](VALIDATION.md) ·
[decision register](DECISIONS.md) · [roadmap](ROADMAP.md)

## Product thesis

Pramāṇa should let a scholar, practitioner or ordinary curious person ask a Dharma or
Buddhist question and receive a useful answer whose important claims can be traced back to
inspectable textual evidence and supporting resources.

The product is not merely search and it is not merely a chatbot. Its core loop is:

**ask → answer → inspect evidence → follow explanation → reuse responsibly**

A user should be able to move from a plain-language answer to the texts behind it. Where
the corpus actually supports the relationship, Pramāṇa should expose an explanatory chain
such as:

**sūtra / discourse → śāstra or treatise → commentary → subcommentary**

That chain is a core product direction because root texts are often terse and difficult.
Commentaries can make them intelligible, but a commentary remains an attributed
interpretation rather than scripture. Pramāṇa must preserve that distinction instead of
flattening every retrieved passage into one undifferentiated evidence pool.

## D1 — audience and recurring job

The pilot serves three user strata around one shared job rather than building three
separate products:

| User | What they need from the same workflow |
|---|---|
| Scholar / translator / serious researcher | Exact source identity, original-language context, text role, relation method/confidence, alternative renderings and exportable evidence |
| Practitioner / teacher / study leader | A comprehensible answer, trustworthy passages, explanatory context and a path into treatises/commentaries without losing attribution |
| Ordinary curious reader | Plain language, minimal jargon, visible confidence/limits and a clear way to open the actual source rather than being asked to trust the model |

The recurring job is:

> **Ask a real Dharma question, understand an answer, inspect what the texts actually
> support, and leave with sources that can be checked or reused.**

The pilot is not a guru, spiritual director, realization assessor or doctrinal authority.
It may explain documented traditions and disagreements; it must not turn textual retrieval
into a claim about what a person should practice or what all Buddhists believe.

## Answer contract

The first useful answer should have progressive depth rather than one giant scholarly
apparatus.

1. **Plain-language answer.** Short enough to orient a normal reader.
2. **Claim-level evidence.** Important factual/doctrinal claims point to supporting
   passages or are marked as interpretation/insufficiently supported.
3. **Source cards.** Original text, rights-cleared human rendering when available,
   work/edition/address, text role, translator attribution and verification state.
4. **Explanation chain.** When supported, expose related treatises, commentaries and
   subcommentaries with typed edges and relation evidence.
5. **Context and resources.** Open surrounding passage, glossary/terminology, parallels,
   alternate translations or related works without losing the original question.
6. **Evidence packet.** Copy/export the answer's supporting evidence with scope,
   attribution and limitations intact.

A generated answer may synthesize evidence. A generated answer is not itself textual
evidence.

## D2 — first user pilot scope

### Selection

The first end-to-end user pilot will target the **four main Pāli Nikāyas / discourse
collection** rather than the entire Pāli corpus.

Why this is the first user-facing scope:

- the recorded repository has the strongest broad human-English coverage in its Pāli
  material and measured English retrieval is materially more mature than Chinese or
  Tibetan line-level retrieval;
- the four Nikāyas cover a broad range of questions ordinary readers and practitioners
  naturally ask, rather than requiring a specialist text family;
- source Pāli is public-domain canonical material and the current substrate already has
  source addressing, translation anchors, parallels and verification machinery;
- starting with a readable discourse corpus lets the pilot test the actual answer/evidence
  product rather than making translation acquisition the entire experiment.

This is a **conditional selection**, not blanket permission to process every translation
currently imported from SuttaCentral. Current SuttaCentral materials have source-specific
licenses and the project presently asks that its content not be used in generative-AI
datasets or downstream AI-derived technologies. Before implementation or design-partner
processing, the selected human rendering must therefore be cleared from its actual rights
holder/source and recorded in the rendering metadata. If no acceptable rendering source is
available for the chosen task set, the user pilot stops rather than silently using a
restricted translation.

### Why not make the first user pilot Chinese or Tibetan?

The recorded Chinese corpus has the richest existing explanatory graph: hundreds of
treatise/commentary/subcommentary roles, 269 `comments_on`, 38
`subcommentary_of`, and extensive passage-level alignments. But human English is
currently far too thin for an ordinary English-speaking reader; generated English is a
discovery aid, not source evidence.

The Tibetan substrate already contains 102 non-Chinese commentary relations and the first
17 Tibetan passage-level commentary alignments, including a
Pramāṇavārttika → vṛtti → ṭīkā chain. It also has human 84000 renderings for part of
the Kangyur. But current Tengyur/commentary English coverage is absent in the recorded
snapshot, line-level translation anchors are coarse, and 84000's current terms/policy
require careful permission/partnership handling and human-led translation use.

Choosing Pāli first therefore tests accessibility and evidence quality. It does **not**
mean commentary is optional or that Pāli-specific assumptions may enter the generic data
model.

## Commentary-depth compatibility track

The first pilot has one user-facing canon, but every I-P2/I-P3 design must remain capable
of the richer evidence hierarchy already present elsewhere.

Before the first product slice is considered structurally acceptable, fixtures from the
existing Chinese and Tibetan relation graphs must prove that the UI/API can represent:

- root sūtra/discourse;
- independent śāstra/treatise;
- commentary on a root or treatise;
- subcommentary on commentary/treatise;
- multiple competing/sibling commentaries;
- relation method and confidence;
- a relation with no passage-level alignment;
- an aligned passage whose commentary language has no approved English rendering;
- ambiguous/cyclic/missing endpoints without manufacturing a clean lineage.

These are **compatibility fixtures**, not a second user pilot and not automatic cross-canon
synthesis. They prevent an easy Pāli pilot from optimizing the product into a flat
root-text search engine.

A later commentary-first user cohort should be chosen only after a commentary-rich text
family also has rights-cleared readable renderings or qualified readers who can evaluate
the source language directly.

## D3 — preregistered pilot thresholds

### Cohort and task set

Use **6–8 design partners**, including at least:

- 2 scholars/teachers/translators or comparably qualified source evaluators;
- 2 serious practitioners/study leaders;
- 2 ordinary non-specialist readers.

Collect at least **24 eligible tasks** before a continue decision. Use natural questions
from participants, supplemented only as needed to cover these classes:

1. a remembered or paraphrased quotation;
2. a doctrinal/practice concept question;
3. a question with several relevant passages rather than one proof-text;
4. an ambiguous or tradition-sensitive interpretation;
5. a missing/unsupported-source case;
6. an evidence-reuse/export task.

The commentary-depth compatibility fixtures are evaluated separately and do not inflate
the user-task denominator.

### Pass / iterate / stop

For this feasibility pilot:

- **critical trust floor:** zero known false quotation verification, wrong source role,
  hidden generated-as-human rendering, rights/privacy violation, or fabricated
  commentary relation in the acceptance cases;
- **task success:** at least 75% of eligible tasks overall and at least 60% in each of the
  three user strata;
- **source comprehension:** at least 80% of participants can correctly distinguish, on a
  short post-task check, root/source text from translation, commentary and generated
  synthesis;
- **evidence reuse:** at least 80% of successful tasks produce an evidence packet that an
  independent reviewer can trace back to the same source passages without hidden context;
- **time to useful evidence:** median at or below 3 minutes and 90th percentile at or
  below 8 minutes from question submission to the participant identifying useful
  inspectable evidence;
- **repeat signal:** at least half of participants voluntarily bring one new natural task
  during the observation window. This is a directional feasibility signal, not a
  retention-rate claim.

Failure of the critical trust floor is a stop/fix condition regardless of average task
success. A weak result in only one audience stratum must remain visible rather than being
hidden by the pooled average.

### Effort and cost cap

This charter authorizes **no new cash spend** and no new provider/billing route. A later
implementation/pilot ticket must name the approved inference route and its budget before
execution.

Initial product-build/pilot iteration is capped at **40 operator hours** after G0. Reaching
that cap without satisfying the preregistered thresholds requires an explicit continue,
reframe or stop decision rather than another infrastructure round.

## D4 — human and generated language

For the first user pilot:

- displayed textual evidence uses the original witness plus a **rights-cleared,
  attributed human rendering** where one is available;
- generated synthesis may explain or compare the evidence, but every substantive claim
  must retain its source links and support type;
- generated translation is **not** accepted as the reader's source translation and is
  never citable as the canonical witness;
- generated index/search English may be evaluated separately for retrieval, but it does
  not become reader evidence;
- if a commentary has no approved readable rendering, the product may still show the
  relation, title, source text and metadata, but must say that the commentary is not
  readable in the pilot rather than fabricating an authoritative English gloss.

An optional clearly labelled AI reading aid can be reconsidered after the first pilot with
qualified review. It is off by default here.

## D5 — evidence packet, privacy and retention

The initial pilot does not require a persistent notebook or account history.

By default:

- the full question, generated answer and private notes are not retained server-side after
  the task session;
- minimal telemetry may retain a random task ID, audience stratum, timing, selected scope,
  source IDs, outcome and failure category, but not the full spiritual/research question;
- consented study participants may explicitly opt in to retention of full task records for
  evaluation, with a stated deletion date;
- user notes remain separate from canonical source/rendering tables;
- evidence export is user-controlled and local.

An evidence packet should contain, as rights permit:

- question and explicit corpus scope;
- answer claims with support type;
- original source identifiers and exact addresses;
- quoted source text where redistribution permits;
- human-rendering attribution/version or an external pointer when copying is restricted;
- text role and commentary-chain relation method/confidence;
- verification result and release/source identity;
- known coverage gaps and interpretive limitations.

No packet should copy a translation excerpt merely because the application can technically
retrieve it.

## D6 — capacity allocation

Until Foundry G0/FR-22 is complete:

- Foundry repair work remains the engineering critical path;
- Pramāṇa work is limited to discovery, chartering, rights/evaluator preparation and other
  non-operational planning that does not bypass G0.

After G0, initial work-in-progress is capped at:

- **one Pramāṇa product slice**, plus
- **at most one bounded Foundry improvement** tied to a measured delivery bottleneck.

Do not start the second-repository Foundry portability pilot during this first Pramāṇa
user pilot. Reallocate only after an explicit gate review.

## D7 — replay promise

The first pilot does **not** promise exact historical replay.

It promises an inspectable receipt containing the source/release identity used for the
answer. When those bytes/renderings are still available, the user can reopen or recheck
them. When they have drifted or become unavailable, Pramāṇa says so explicitly rather than
claiming to reconstruct the past.

Exact historical replay becomes a product requirement only if observed users demonstrate
a need that justifies the retention, rights and operating burden.

## Post-G0 first vertical slice

The first eligible product slice after G0 should be deliberately narrow:

1. user enters a Dharma question;
2. scope is visibly fixed to the pilot Pāli discourse collection;
3. retrieval returns candidate passages and coverage/absence information;
4. a bounded synthesis produces a plain-language answer with claim-level evidence links;
5. user opens a source card with Pāli, approved human rendering, attribution and context;
6. user can inspect related passages/parallels/resources;
7. the same evidence model can display a typed commentary/treatise chain in compatibility
   fixtures without flattening roles;
8. user exports the evidence packet.

Reuse the current reader, MCP, verification, translation, relation and commentary
substrates. Do not create a second research-agent framework, graph database or source
store for this slice.

## Product principles carried beyond the pilot

Even though the first user pilot is Pāli, the intended Pramāṇa product is broader:

- ask in ordinary language; descend into scholarship only as desired;
- answer with actual evidence, not merely plausible prose;
- preserve the difference between scripture, treatise, commentary and generated
  explanation;
- let commentarial traditions add understanding without making later interpretation look
  like the root text;
- expose multiple explanations and disagreement when the sources support them;
- make absence scope-aware: “not found here” is not “Buddhism does not teach this”;
- keep cross-canon synthesis explicit and later, never accidental;
- prefer a smaller trustworthy corpus over a larger unreadable or rights-unclear one.

## Stop/reframe conditions

Reframe or stop the pilot if any of the following holds:

- no rights-cleared human English rendering can be used for the selected task set;
- qualified evaluators cannot be recruited;
- normal users cannot understand source/translation/commentary distinctions;
- useful evidence cannot be found for enough natural questions;
- generated synthesis repeatedly outruns what the retrieved passages support;
- evidence packets cannot be made useful without violating source/translation terms;
- the product provides no meaningful advantage over participants' current
  archive-plus-search or model-assisted workflow;
- the 40-hour iteration cap is reached without a credible path to the preregistered floor.

The answer to a failed pilot is not automatically “add more corpora” or “use a larger
model.” Diagnose whether the failure is demand, rights, retrieval, readability,
interpretation, UX or trust before choosing the next investment.
