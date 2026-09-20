# Pramāṇa Chinese-first pilot preflight

**Status:** design/preflight only; no pilot execution or provider call is authorized.
**Decision update:** 2026-09-17, superseding the initial four-Nikāya D2 pilot choice.
**Base:** `6887cc15457a0bcb555914874173b6a35488da3f`
**Depends on:** [pilot charter](PILOT_CHARTER.md), Foundry G0/FR-22, reviewed source/lexicon
rights, evaluator availability and separately authorized inference.

## Why the pilot is now Chinese-first

The first charter selected Pāli because it was the easiest current path to human-readable
English. The product goal was then clarified: Pramāṇa's distinctive value is not merely
retrieving a readable root passage, but letting a user ask a Dharma question and descend
through **actual scripture, independent treatises, commentaries and subcommentaries**.

The recorded Chinese substrate is substantially stronger on that dimension:

- 352 treatises, 155 commentaries and 35 subcommentaries are already role-labelled;
- the relation graph contains 269 `comments_on` and 38 `subcommentary_of` edges;
- Chinese passage-level commentary alignment already attaches explanatory works to tens of
  thousands of root lines;
- the existing demand-weighted English-index tranche covers 14 CBETA works: the top ten by
  directed citation weight plus the four Āgamas;
- the repository already holds Chinese Buddhist lexical resources from
  Soothill-Hodous, Karashima and the Mahāvyutpatti, plus source-attested glossary anchors.

The missing product layer is therefore **bilingual retrieval and trustworthy readability**,
not another relation graph and not a whole-canon translation project.

## Bounded first scope

The first Chinese user pilot is bounded to:

1. the existing **14-work demand-weighted CBETA seed set** used by the current Chinese
   English-index experiment; plus
2. works connected to those seeds by accepted typed `comments_on` or
   `subcommentary_of` relations, traversed to a bounded depth; plus
3. passage-level commentary alignments belonging to those accepted relations.

The four Āgamas give broad early-Buddhist question coverage while the citation-weighted
roots provide high-demand Mahāyāna material. The attached commentary neighborhoods supply
the explanatory depth the product is intended to test.

This is an evaluation scope, not a claim that the other CBETA works are lower value.
Natural participant questions may fall outside it; such cases are recorded as unsupported
rather than answered from an undeclared wider corpus.

Before execution, the exact scope must be materialized from the live pilot release and
recorded: seed work IDs, allowed relation edge types, maximum traversal depth, every
expanded work ID, passage-alignment coverage, release identity and scope denominator.
The rights review applies to the **entire expanded scope**, not merely the 14 seeds.
The historical phrase "top ten by directed citation weight" is not an immutable list.

The reviewed materialization procedure is specified in [PILOT_SCOPE](PILOT_SCOPE.md).
The read-only `mix pramana.pilot.scope --release-id <exact-release-id> --out <path>`
command fails closed on release drift. The standalone artifact checker can verify
structure/hash without a database, but **neither command makes `pilot_scope` ready by
itself**: the generated live artifact must still be reviewed and accepted as preflight
evidence.

The quotation/relation/alignment producers now record append-only completion receipts as
specified in [PILOT_DERIVATIONS](PILOT_DERIVATIONS.md). The pilot verifier requires clean,
current receipts for the pilot-required scope and parameters for all four derivations; scoped, dry-run,
report-only, partial, old-implementation, input-stale, output-stale or output-count-mismatched
receipts do not pass.
A quiesced stable-state check (two identical consecutive scope materializations, or
equivalent independently recorded evidence) remains separately required. A historical row
count is not a substitute.

## The bilingual architecture

```text
English question
       │
       ├── preserve original question verbatim
       │
       ▼
concept / entity analysis
       │
       ├── attested Buddhist lexicon expansion ───────┐
       ├── bounded Chinese paraphrase candidates      │
       ├── Sanskrit/Pāli name-term anchors            │
       └── original English query                     │
                                                      ▼
                                      independent retrieval arms
                               ┌────────────┼───────────────┐
                               │            │               │
                         Chinese lexical  Chinese       English /
                         phrase + ngram   semantic      multilingual
                               │            │           semantic
                               └────────────┼───────────────┘
                                            │
                              existing English-index arm
                              where coverage already exists
                                            │
                                            ▼
                                    deterministic fusion
                                            │
                                            ▼
                              verified Chinese passages
                                            │
                           ┌────────────────┴──────────────┐
                           │                               │
                    source/treatise hit             relation expansion
                           │                  comments_on / subcommentary_of
                           │                               │
                           └────────────────┬──────────────┘
                                            ▼
                              selected Chinese evidence
                                            │
                         terminology-constrained on-demand
                               English reading translation
                                            │
                                            ▼
                         claim-linked English synthesis/UI
```

No one translation step owns the user's intent. Every retrieval arm reports which query
form and mechanism produced the hit.

## Query expansion is not sentence translation

A literal English→Chinese sentence translation is too brittle for Buddhist retrieval.
Technical terms have historical renderings, translator-specific usage and near-neighbours
that must not be flattened into synonyms.

The query planner should extract concepts and produce candidates with a provenance-bearing
relation type. **A reverse dictionary hit is not automatically an equivalence claim.**

| Relation | Meaning | Retrieval treatment |
|---|---|---|
| `explicit_equivalent` | the reviewed source explicitly presents the cross-language forms as equivalents | highest-weight lexical + semantic |
| `attested_gloss` | Chinese headword has an English/Sanskrit gloss matching the query concept | high-value candidate, but not displayed as a synonym without review |
| `historical_rendering` | attested rendering used by a named translator/text family | high weight only in its supported scope; lower outside it |
| `orthographic_variant` | character/edition variant | equivalent only for character matching; original form preserved |
| `transliteration` | Indic name/term represented phonetically in Chinese | high-value lexical candidate |
| `broader_narrower` | reviewed taxonomic relationship | separate lower-weight expansion |
| `related` | doctrinally associated but not equivalent | recall-only arm; never presented as a synonym |
| `model_proposed` | model-suggested Chinese formulation lacking reviewed lexical attestation | bounded recall arm only |

English→Chinese lookup therefore works conservatively: search the lexicon's English,
Sanskrit and definition fields for candidate Chinese headwords, retain each glossary's
source/work scope, and record *why* the candidate matched. A model may propose additional
Chinese forms, but matching a retrieved passage does not retroactively turn that proposal
into an attested lexical equivalence.

Example: an English question about "Buddha-nature" may produce 佛性 and 如來藏 as
separate relevant candidates with their own provenance; the system must not claim those
terms are interchangeable merely because both retrieve useful material.

The original English question is always retained beside the expansion plan.

## Lexicon stack

Use existing pinned resources before asking a model to invent terminology:

### General Chinese Buddhist vocabulary

**Soothill-Hodous** supplies broad Chinese→English Buddhist terminology. It is old and
sometimes doctrinally dated, so it is candidate-generation evidence rather than a
contemporary doctrinal authority.

### Translator/text-specific evidence

The three **Karashima** glossaries are especially valuable because they describe usage in
specific translated works rather than pretending one Chinese string has one universal
meaning. Their existing `work_id` scopes must survive query planning.

### Cross-lingual anchor

The **Mahāvyutpatti** supplies Sanskrit/Chinese/Tibetan correspondences. It is useful when
the user knows an Indic term or when English ambiguity can be narrowed through a Sanskrit
anchor.

### Character and spelling variants

Reuse the existing query-side variant expansion. The corpus itself is not normalized;
which form an edition prints remains evidence.

### Optional model expansion

A model may propose additional Chinese paraphrases only after deterministic candidates are
assembled. Model candidates are labelled `model_proposed`, bounded in number and never
promoted to attested equivalence merely because retrieval succeeds.

No live Digital Dictionary of Buddhism or other access-controlled dictionary is required
for the pilot. Such sources need separate permission/interface review before becoming a
dependency.

## Retrieval arms

### Arm A — attested Chinese lexical retrieval

Run exact/phrase retrieval over high-confidence Chinese terms first, then existing
dictionary-free Chinese n-gram fallback. This is the most interpretable arm.

Do **not** use jieba as the Buddhist-query fallback; the current repository already records
that modern segmentation damages transliterated Buddhist vocabulary.

### Arm B — Chinese semantic retrieval

Construct short Chinese concept/paraphrase candidates and search Chinese source embeddings.
Keep each generated query and its provenance in the result receipt.

### Arm C — original-English multilingual semantic retrieval

Search source embeddings from the original English question where the existing multilingual
embedding model supports it. This arm protects against a bad Chinese query translation.

### Arm D — existing English rendering/index retrieval

Use current human/generated English index coverage where present. This is another retrieval
signal, not English source evidence.

### Fusion

Fuse arms deterministically using the existing retrieval framework or a small evaluated
extension of it. Preserve per-arm ranks, candidate provenance and query identities so a
result can say why it was found.

Expansion multiplicity must not become evidence strength:

- repeated candidates that normalize to the same retrieval query contribute once;
- several `related` or `model_proposed` candidates cannot outvote one precise
  `explicit_equivalent` / attested lexical hit merely by their count;
- weak expansion classes have bounded candidate counts and their own fusion contribution;
- per-arm results remain inspectable so ablation can show which arm rescued or harmed a
  task;
- a hit from `related` or `model_proposed` expansion may retrieve useful source
  evidence, but the expansion itself is never displayed as a verified synonym.

Do not simply concatenate translated Chinese terms into one giant OR query: weak related
terms would be allowed to outvote precise terms and the existing lexical planner can cross
its selectivity cliff on large predicate sets.

## From a hit to explanatory depth

After retrieval identifies a root/treatise passage or work:

1. classify the work role already stored in provenance;
2. expand only accepted typed `comments_on` / `subcommentary_of` relationships;
3. prefer existing passage-level commentary alignments when they target the hit;
4. show unaligned work-level commentary as "commentary on this work", not
   "commentary on this passage";
5. preserve relation method/confidence and missing/ambiguous endpoints;
6. never create a relation from topical similarity.

A treatise can independently answer the same topic as a sūtra without being presented as
its commentary.

## English readability: translate evidence, not the canon

The first pilot should **not pre-translate CBETA**.

Translate only bounded retrieved evidence that the user opens or that a synthesis needs:

- a small source context window;
- selected treatise passage(s);
- selected commentary/subcommentary passage(s).

For every generated reading translation:

- treat source/commentary/glossary bytes as **untrusted data**, never as prompt/control
  instructions; structured input boundaries may not allow corpus text to change provider,
  tool, budget or policy settings;
- keep and display the Chinese source;
- bind the generation to the source URN/content hash;
- record model/provider identity, prompt/rubric version and glossary inputs;
- label it clearly as **generated reading translation — not reviewed source evidence**;
- preserve technical terms when no reviewed English equivalent is available;
- permit the user to reveal the Chinese term and glossary evidence for important terms;
- never allow a quotation from generated English to verify as if it were the Chinese
  canonical witness.

Where a rights-cleared human rendering exists, present it separately and attribute it.

### Two English layers

Keep these distinct:

1. **reading translation** — close rendering intended to let a non-Chinese reader inspect
   the retrieved passage;
2. **answer/explanation** — plain-language synthesis that may combine several passages and
   commentarial interpretations.

The explanation must never be used as the translation of a source passage.

## Translation terminology packet

Before translating a selected passage:

1. identify glossary headwords actually present in that Chinese passage;
2. prefer work-scoped Karashima evidence when the work matches;
3. add general Soothill-Hodous / Mahāvyutpatti candidates;
4. preserve conflicting candidates rather than silently choosing one;
5. tell the translation model which terms are constrained, which are alternatives and
   which must remain untranslated/transliterated;
6. return the chosen rendering plus a term-decision record.

Glossary pinning is a consistency control, not proof that the translation is faithful.

## Rights preflight

[Chinese pilot rights and data-flow boundaries](CHINESE_PILOT_RIGHTS.md) is the reviewed
operation-level authority for this preflight. It covers, separately, local storage/search,
derived retrieval artifacts, English→Chinese expansion, cloud/provider transfer,
local-model processing, reader display, evidence packets, evaluation retention, public
redistribution and commercial implications for:

- the CBETA Taishō Category A witness used by the intended seed;
- Soothill-Hodous;
- each of the three exact Karashima digital editions;
- the DILA Mahāvyutpatti digital edition;
- Charles Patton's scpub20/scpub35 human English layer; and
- the existing generated-English MITRA tranche over CBETA.

The review found a primary-source conflict the earlier preflight did not capture. Each of
the five exact DILA digital-edition PDFs states CC BY-SA 3.0, while the current DILA portal
states CC BY-NC-SA 4.0. The pilot therefore keeps the existing conservative NC posture and
does not silently select the more permissive notice. Local deterministic lexicon use is
supported under the restrictive common denominator; external-model glossary transfer and
commercial reliance remain blocked pending clarification.

CBETA's current database terms establish a non-commercial Category A baseline for Taishō,
plus notice/version obligations, but the complete expanded pilot scope is not frozen and
the model-derived/cloud operations are not thereby cleared. CBETA's own RAG/OpenAI
experiment remains implementation precedent, **not permission for Pramāṇa's provider
route**.

SuttaCentral's exact Patton publications are CC0, while SuttaCentral separately asks that
its content not be used for generative-AI datasets or downstream AI-derived technologies.
The pilot records that as a stakeholder norm rather than rewriting the CC0 copyright
position: attributed human-reader display may remain available, while new AI-derived use
of Patton text requires stakeholder review.

The execution rule is fail-closed: **permitted** authorizes only the named operation and
conditions; **prohibited**, **permission required**, and **unclear / unresolved** all stop
that operation. No blocked resource is silently replaced with another corpus or glossary.

Accordingly, `cbeta_rights`, `lexicon_rights` and `provider_terms` remain blocked in
[pilot_preflight.json](pilot_preflight.json), now with precise reasons and this review as
evidence. Provider review must cover not only source/glossary bytes but also any participant
question/task content an external route would receive, including retention/training,
human-review and deletion terms plus the conditional participant-transfer consent.
No provider/model/spend authority is granted here.

## Evaluation and rehearsal contract

The exact v1 acceptance rules are frozen in
[Chinese pilot acceptance and rehearsal contract](PILOT_ACCEPTANCE.md), with machine-readable
values in [`pilot_acceptance.json`](pilot_acceptance.json).

That contract now owns:

- per-task query/candidate/retrieval/relation/model/byte/time/retry/spend ceilings;
- evaluator-approved recall@1/5/10 and per-arm/fused retrieval reporting;
- provenance-aware query-expansion classification;
- the six-dimension generated-reading-translation rubric and pass rule;
- claim-support classes;
- the fifteen critical failure classes whose occurrence overrides aggregate scores; and
- the required R01–R16 rehearsal slots and pass conditions.

The charter still owns the 6–8 participant design, ≥24 natural tasks, per-stratum task
floors, comprehension/evidence-reuse/time/repeat-use thresholds and 40 operator-hour cap.
The acceptance contract does not replace those participant outcomes.

The frozen execution ceiling currently authorizes **US$0 cash spend**. It therefore does
not select or authorize a provider; any later nonzero route requires a reviewed contract
revision plus the independent inference/provider gates.

The acceptance contract freezes policy, not implementation. Later code must demonstrate
that limits refuse **before** exceeding them; reporting an excess after the fact is not
enforcement.

The rehearsal contract is frozen but **has not run**. Exact R01–R16 work IDs/URNs must be
instantiated only after the pilot release/scope is frozen. Rehearsal cases never enter the
24-task participant denominator.

Accordingly:

- `execution_bounds`, `evaluation_rubric` and `critical_taxonomy` may be recorded
  ready as frozen specification gates;
- `rehearsal_trust` remains blocked until R01–R16 execute with zero unresolved critical
  failures **and** the separately authorized inference route passes its frozen source-bound
  translation-quality sample;
- `retrieval_baseline` remains blocked until at least 30 evaluator-confirmed supported
  held-out cases (including at least 8 commentary-eligible cases) are measured against the
  accepted release and meet the frozen recall@10 floors.

## Participant protocol

The participant consent, study-record, retention/deletion, withdrawal,
current-alternative, evaluator-separation and denominator rules are frozen in
[Chinese pilot participant protocol](PILOT_PARTICIPANTS.md), with exact values in
[`pilot_participants.json`](pilot_participants.json).

This makes the `participant_protocol` gate ready **as a protocol specification only**.
No participant has been recruited or consented, and no study data has been collected.
Actual participant execution remains blocked by every other mandatory preflight gate.

## Fail-closed readiness gate

The pilot is not ready until every mandatory condition has explicit evidence:

1. **Foundry G0 / FR-22 complete** for implementation execution.
2. **Exact pilot release/scope pinned**, including seed work IDs and relation expansion.
3. **CBETA rights matrix reviewed** for every intended operation.
4. **Lexicon rights matrix reviewed** for each glossary used.
5. **Inference route and spending authorized** separately.
6. **Per-task execution bounds frozen**: maximum deterministic/model query candidates,
   model calls, passages and source bytes/tokens translated, timeout, retry count and
   authorized spend. Hidden retries are forbidden and duplicate source hashes must not be
   translated repeatedly within one task.
7. **Provider data-use terms reviewed** for sending selected source/glossary text **and**
   participant question/task content, with route-specific participant-transfer consent
   where an external provider receives that content.
8. **Bilingual evaluator coverage identified**.
9. **Participant protocol/consent/retention procedure fixed** in
   [PILOT_PARTICIPANTS](PILOT_PARTICIPANTS.md), including current-alternative intake,
   denominator rules and withdrawal behavior.
10. **Retrieval baseline fixed** against the accepted release and frozen held-out thresholds.
11. **Translation/query evaluation rubric frozen**, including text-role-separated
    translation reporting.
12. **Critical failure taxonomy frozen**.
13. **No known unresolved critical trust defect** in rehearsal cases.

A blocked gate is a valid preflight result. It must not be rewritten to `ready` merely
because implementation could technically start.

## Readiness manifest and commands

The current machine-readable record is
[`pilot_preflight.json`](pilot_preflight.json). It is intentionally blocked.

From the Git root:

```bash
elixir bin/check_pilot_preflight.exs --validate
elixir bin/check_pilot_preflight.exs --ready --subject <exact-candidate-git-sha>
```

`--validate` answers only whether the manifest has the complete mandatory gate set,
well-formed states and local evidence references. A valid blocked manifest is success.

`--ready` is stricter: every mandatory gate must be `ready`, every ready gate must carry
evidence, no blocking reason may remain, and `subject_revision` must equal the exact
candidate revision supplied with `--subject`. That commit must exist **and be an ancestor
of the current evidence checkout**, so evidence on one branch cannot claim an unrelated
candidate. The explicit subject avoids an impossible self-reference in which a committed
manifest would need to contain its own commit SHA. It fails while the pilot is legitimately
blocked.

Neither command proves that a rights opinion, evaluator decision or provider authorization
is substantively correct. Those remain human/reviewed evidence. The command prevents
missing/stale bookkeeping from being mistaken for readiness; it does not manufacture the
underlying decisions.

## Post-G0 implementation sequence

Once the readiness gate is genuinely satisfied:

1. implement a pure, inspectable query-expansion plan object;
2. run existing retrieval arms without synthesis and evaluate;
3. add deterministic fusion with per-arm receipts;
4. add typed relation expansion;
5. add bounded on-demand reading translation with terminology packet;
6. add claim-linked synthesis;
7. add progressive source/commentary inspector;
8. add evidence-packet export;
9. run rehearsal acceptance;
10. begin the preregistered participant pilot.

Do not build a general translation service, autonomous research-agent framework or new
graph database as a prerequisite.
