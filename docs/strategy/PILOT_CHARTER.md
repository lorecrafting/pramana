# Pramāṇa pilot charter

**Status:** operator-approved product direction; implementation remains gated by Foundry G0.
**Decision date:** 2026-09-17
**Source baseline:** `ac80923d4795be84b0f432031ad6e17a330f589f`
**Strategic initiative:** I-P1, preparing I-P2/I-P3 after G0.

[Pramāṇa strategy](PRAMANA.md) · [validation](VALIDATION.md) ·
[acceptance contract](PILOT_ACCEPTANCE.md) · [decision register](DECISIONS.md) · [roadmap](ROADMAP.md)

## Product thesis

Pramāṇa should let a scholar, practitioner or ordinary curious person ask a Dharma or
Buddhist question and receive a useful answer whose important claims can be traced back to
inspectable textual evidence and supporting resources.

The product is not merely search and it is not merely a chatbot. Its core loop is:

**ask → answer → inspect evidence → follow explanation → reuse responsibly**

A user should be able to move from a plain-language answer to the texts behind it. Where
the corpus actually supports the relationships, Pramāṇa should expose a **typed
explanatory graph**, for example:

- **sūtra / discourse → commentary → subcommentary**;
- **śāstra / treatise → commentary → subcommentary**;
- a sūtra and an independent treatise may both bear on the same question without claiming
  that the treatise is a commentary on that sūtra.

This depth is a core product direction because root texts and systematic treatises can be
terse and difficult. Commentaries can make them intelligible, but a commentary remains an
attributed interpretation rather than scripture. Topic relevance must never be promoted
into a `comments_on` edge merely to make a clean lineage diagram. Pramāṇa must preserve
those distinctions instead of flattening every retrieved passage into one
undifferentiated evidence pool.

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
into a claim about what a person should practice or what all Buddhists believe. A question
such as “what should I meditate on?” may be answered as **what named texts/teachers in the
searched scope prescribe or discuss**, with sources and variation, rather than as
personalized spiritual instruction.

## Answer contract

The first useful answer should have progressive depth rather than one giant scholarly
apparatus.

1. **Plain-language answer.** Short enough to orient a normal reader and headed by the
   exact corpus/tradition scope being searched, so “within this bounded Chinese pilot
   scope” cannot silently become “Buddhism says.”
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

The first end-to-end user pilot is **Chinese-first** and uses a bounded CBETA scope:

1. the existing 14-work demand-weighted seed set — the top ten works by the recorded
   directed-citation ranking plus the four Āgamas — resolved again against the exact pilot
   release; and
2. accepted `comments_on` / `subcommentary_of` neighborhoods attached to those seeds,
   including available passage-level commentary alignments.

This supersedes the charter's earlier conditional four-Nikāya Pāli choice. The change is
intentional: broad human-English coverage made Pāli easier, but the product goal was
clarified to make **scripture/treatise/commentary depth a central user value rather than a
future compatibility constraint**.

Why this Chinese scope is the first user-facing pilot:

- the current Chinese corpus has the deepest implemented explanatory graph;
- the four Āgamas preserve broad early-Buddhist discourse coverage;
- the citation-weighted roots concentrate existing retrieval demand and already have a
  generated-English index tranche;
- existing DILA/Soothill-Hodous/Karashima/Mahāvyutpatti resources provide an attested
  Buddhist terminology bridge for English→Chinese query expansion;
- the pilot can translate only retrieved evidence on demand instead of pre-translating
  4,263 works.

The exact seed IDs and relation expansion are pilot-release data, not permanent strategy
constants. They must be materialized and recorded before participant work starts.

### Rights and source-policy condition

Before implementation or participant processing, the exact CBETA sources, glossary
sources and any human rendering used must have an operation-specific rights matrix:

| Operation | Required recorded disposition |
|---|---|
| store/index locally | permitted / prohibited / permission required, with source/version |
| derive embeddings or retrieval features | permitted / prohibited / permission required |
| use for query expansion | permitted / prohibited / permission required |
| send text to a model/provider | permitted / prohibited / permission required, including provider terms |
| display in the reader | permitted scope and attribution requirements |
| quote/copy into an evidence packet | permitted excerpt/export scope or external-link-only |
| retain for consented evaluation | permitted duration and deletion obligation |

CBETA's public terms and its own AI-search experiments are evidence relevant to the review,
not automatic authorization for Pramāṇa. DILA glossary licences likewise remain
source-specific. This charter is a product-policy record, not legal advice.

If the bounded Chinese scope cannot satisfy the required rights, bilingual-evaluator or
quality conditions, **D2 reopens**. There is no automatic fallback to Pāli, Tibetan,
generated-only evidence or a broader Chinese corpus.

## Exegetical depth is part of the pilot

Commentary is no longer only a compatibility track. For commentary-eligible user tasks,
the pilot must let the user follow the supported explanatory structure already in the
corpus.

The product must faithfully represent:

- root sūtra/discourse;
- independent śāstra/treatise without inventing a root relation from topical similarity;
- commentary on a root or treatise;
- subcommentary on commentary/treatise;
- multiple competing or sibling commentaries;
- relation method and confidence;
- work-level commentary with no passage-level alignment;
- an aligned passage whose commentary has no human English rendering;
- ambiguous/cyclic/missing endpoints without manufacturing a clean lineage.

Passing structural fixtures proves only that the hierarchy is represented correctly. The
user pilot separately measures whether opening a commentary actually helps or corrects
understanding. It must never claim a causal benefit merely because a commentary link was
available or clicked.

Where no accepted commentary relation exists, Pramāṇa says so; it does not retrieve a
topically similar treatise and label it commentary.

## D3 — preregistered pilot thresholds

### Cohort and task set

Use **6–8 design partners**, including at least:

- 2 scholars/teachers/translators or comparably qualified source evaluators;
- 2 serious practitioners/study leaders;
- 2 ordinary non-specialist readers.

The evaluation pool must include at least **two people competent to read the relevant
Buddhist Chinese/Classical Chinese source passages**. Their source-evaluator role is
recorded separately from their usability-participant role.

Collect at least **24 eligible tasks** before a continue decision, with **at least six
eligible tasks from each user stratum** so the per-stratum floor has a meaningful
denominator. Use natural questions from participants, supplemented only as needed to cover
these classes:

1. a remembered or paraphrased quotation;
2. a doctrinal/practice concept question;
3. a question with several relevant passages rather than one proof-text;
4. an ambiguous or tradition-sensitive interpretation;
5. a missing/unsupported-source case;
6. an evidence-reuse/export task.

At least **six eligible tasks must have an accepted commentary or subcommentary path in the
pilot graph**. Report those tasks separately: whether commentary was opened, whether the
participant says it changed/clarified their understanding, and whether the bilingual
evaluator judges that the commentary was represented faithfully. These observations are
not a causal experiment unless the later protocol explicitly adds a controlled comparison.

A qualified source evaluator reviews every pilot task for source identity/role errors,
query-expansion errors, generated-reading-translation errors and substantive claim support;
ordinary participants' comprehension is measured separately from evaluator agreement.

These numerical floors are preregistered feasibility choices, not established industry
benchmarks. They may be revised while the pilot is still in planning, but once the first
participant task begins, changing a threshold requires declaring the original pilot
inconclusive/failed and starting a new preregistered evaluation rather than moving the
goalposts.

### Pass / iterate / stop

For this feasibility pilot:

- **critical trust floor:** zero known false quotation verification, wrong source role,
  hidden generated-as-human rendering, rights/privacy violation, or fabricated
  commentary relation in the acceptance cases;
- **task success:** at least 75% of eligible tasks overall and at least 60% in each of the
  three user strata;
- **source comprehension:** at least 80% of participants can correctly distinguish, on a
  short post-task check, Chinese source text from generated/human translation, commentary
  from root/treatise, and generated synthesis from textual evidence;
- **evidence reuse:** at least 80% of successful tasks produce an evidence packet that an
  independent reviewer can trace back to the same source passages without hidden context;
- **time to useful evidence:** median at or below 3 minutes and 90th percentile at or
  below 8 minutes from question submission to the participant identifying useful
  inspectable evidence;
- **repeat signal:** during a declared **14-day observation window**, at least half of
  participants voluntarily bring one new natural task. This is a directional feasibility
  signal, not a retention-rate claim.

Failure of the critical trust floor is a stop/fix condition regardless of average task
success. A weak result in only one audience stratum must remain visible rather than being
hidden by the pooled average.

### Effort and cost cap

This charter authorizes **no new cash spend** and no new provider/billing route. A later
implementation/pilot ticket must name the approved inference route and its budget before
execution.

Initial product-build/pilot iteration is capped at **40 operator hours** after G0.
Operator hours include implementation, setup, support, evaluation review and rework; they
exclude participant time. Reaching that cap without satisfying the preregistered thresholds
requires an explicit continue, reframe or stop decision rather than another infrastructure
round.

## D4 — Chinese source and generated English layers

For this Chinese-first pilot:

- the **Chinese witness is the authoritative textual evidence**;
- a rights-cleared human English rendering, where available, is shown as an attributed
  translation rather than as the source;
- when no suitable human rendering exists, a bounded **generated reading translation is
  allowed and expected** so ordinary readers can inspect the selected evidence;
- generated reading translations are visibly labelled as generated/unreviewed unless a
  qualified reviewer has actually reviewed that exact rendering;
- every generated reading is bound to the Chinese URN/content hash and carries its
  model/provider, prompt/rubric and terminology inputs;
- generated translation is never citable as the canonical witness and cannot receive a
  source-verification badge merely because the Chinese bytes verified;
- generated index/search English remains a separate retrieval layer and does not become
  reader evidence;
- the final answer/explanation is a third layer and must never masquerade as a translation.

For technical Buddhist terms, expose the Chinese term and relevant glossary evidence on
demand. Where reviewed lexicons disagree or a term is historically scope-specific, preserve
the alternatives rather than forcing one canonical English equivalent.

Automatic terminology checks, model agreement or back-translation may diagnose problems;
they do not certify fidelity. Translation quality for the pilot requires qualified
Buddhist-Chinese review.

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
- human-rendering attribution/version where used;
- generated-reading identity and explicit generated/unreviewed status where used;
- the Chinese source hash/URN that each rendering is attached to;
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

1. user enters an English Dharma question;
2. scope is visibly fixed to the recorded Chinese pilot release;
3. query planning produces inspectable attested Chinese terms plus bounded model-proposed
   candidates without overwriting the original English question;
4. independent lexical/semantic/English-index arms retrieve candidate Chinese passages and
   report which arm found each result;
5. the user opens a verified Chinese source/treatise passage and its context;
6. accepted commentary/subcommentary relations expand from that evidence where available;
7. selected Chinese passages receive bounded terminology-constrained English reading
   translations, clearly labelled as generated when no human rendering is used;
8. a bounded synthesis answers in plain English while distinguishing "source says",
   "treatise argues", "commentary explains" and model synthesis;
9. the user can inspect terminology, source role, relation evidence and original Chinese;
10. the user exports an evidence packet that keeps those distinctions intact.

Reuse the current reader, MCP, verification, retrieval, translation, relation, glossary
and commentary substrates. Do not create a second research-agent framework, graph database,
whole-canon translation store or new source authority for this slice.

## Product principles carried beyond the pilot

The Chinese-first pilot is a bounded route to the intended broader Pramāṇa product:

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

- the selected Chinese source/lexicon/model-processing rights matrix cannot be cleared for
  the intended non-commercial pilot operations;
- qualified Buddhist-Chinese evaluators cannot be recruited;
- normal users cannot understand source/translation/commentary distinctions;
- useful evidence cannot be found for enough natural questions;
- English→Chinese query expansion repeatedly retrieves the wrong concept;
- generated reading translations produce critical doctrinal/semantic errors at an
  unacceptable rate;
- generated synthesis repeatedly outruns what the retrieved passages support;
- evidence packets cannot be made useful without violating source/translation terms;
- the product provides no meaningful advantage over participants' current
  archive-plus-search or model-assisted workflow;
- the 40-hour iteration cap is reached without a credible path to the preregistered floor.

The answer to a failed pilot is not automatically “add more corpora” or “use a larger
model.” Diagnose whether the failure is demand, rights, retrieval, readability,
interpretation, UX or trust before choosing the next investment.
