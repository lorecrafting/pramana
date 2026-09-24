# Research register and dependency policy

[Strategy overview](../PRODUCT_STRATEGY.md) · [Original-section map](RECONCILIATION.md)
**Checked:** 2026-09-21. This register distinguishes source evidence from our
recommendations. A retrieved article or README is not local conformance, a licence
review, a partnership or a benchmark reproduction. Recheck moving upstream sources
at evaluation/adoption; pin actual package/model/data revisions in that work.

## Buddhist sources and stakeholders

| ID | Source and verification | Consequence for the strategy |
|---|---|---|
| E7 | [84000: AI, authority, transmission and ethics](https://84000.co/post/84000-and-ai-authority-transmission-and-ethical-concerns), policy text checked | Human-led translation and approved assistive uses matter. The policy prohibits first-draft canonical translations for publication and independent translation without direct scholarly guidance/review; approved tools and disclosure also matter. Byte verification does not confer institutional approval |
| E8 | [BDRC dataset initiative](https://www.bdrc.io/blog/2026/02/28/bdrc-launches-major-initiative-to-build-open-buddhist-datasets-for-ai/), February 28, 2026; announcement checked | It announces an initiative whose grant runs through summer 2027, not proof of a ready, immutable February dataset matching the old plan. Check actual released artifacts, alignment and terms before ingestion |
| E9 | [MITRA paper](https://arxiv.org/abs/2601.06400) and [MITRA-E model card](https://huggingface.co/buddhist-nlp/gemma-2-mitra-e), checked | A domain embedding candidate, not a predetermined upgrade. Inspect the model's actual interface and evaluate on isolated relevant tasks before selecting dimensions, cloud hardware or full-corpus indexing |
| E10 | [Phophichit and Metzger's publication abstract](https://dr-nadnapang.jimdosite.com/publications/) and [journal entry](https://academic.oup.com/dsh/article-abstract/41/3/1594/8694726); author abstract and journal metadata located, full article not reviewed | The author abstract reports promising Pāli translation results while retaining human interpretive authority; the old blanket negative characterization was too strong. [PaliBench](https://arxiv.org/abs/2605.16881) supports considering multiple faithful human references. Neither is a Pramāṇa benchmark |
| E14 | [Sujato's author-maintained essay index](https://sujato.github.io/meaningless.ai/) confirms the named translation critique; linked discussion could not be read in this audit | Preserve the concern as a stakeholder perspective. Do not infer a current licence, policy decision, endorsement or detailed technical conclusion from the inaccessible discussion |
| E15 | [SuttaCentral licensing](https://suttacentral.net/licensing) and Bhikkhu Sujato's four-Nikāya edition pages, checked 2026-09-17 | SuttaCentral-created material is generally CC0 and individual third-party translations vary, but SuttaCentral also explicitly asks that its content not be used for generative-AI datasets or downstream AI-derived technologies. Do not treat a permissive copyright label as stakeholder approval for an AI-assisted Pramāṇa pilot; clear the actual rendering source before use |
| E16 | [84000 draft Terms of Use](https://www.84000.co/documents/terms-of-use) and [84000 AI position](https://84000.co/documents/84000s-position-on-ai-and-the-machine-translation-of-canonical-literature), checked 2026-09-17 | Published translations are described as CC BY-NC-ND, API/data access requires written agreement, and 84000's AI policy keeps canonical translation human-led. Tibetan rendering availability is therefore not blanket permission for an AI answer product |
| E17 | [CBETA FAQ](https://cbeta.org/en/faq) and CBETA's published AI semantic-search announcements, checked 2026-09-17 | CBETA supports digital use and has publicly experimented with RAG/semantic search, but Taishō/other reuse rights remain source-specific and print/publication rights are not blanket. AI precedent is not equivalent to unrestricted redistribution permission |
| E18 | [CBETA current copyright declaration](https://cbeta.org/copyright) and [CBETA AI semantic-search beta](https://cbeta.org/post/28688), checked 2026-09-17 | CBETA currently limits its database to non-commercial use, generally applies CC BY-NC-SA 4.0 where no exception is stated, and requires reuse/version notices; source editions have exceptions. CBETA itself has publicly tested RAG/OpenAI semantic search over its texts, which establishes stakeholder precedent for AI-assisted retrieval but does not grant Pramāṇa permission for a separate deployment or model-processing route |
| E19 | [DILA Glossaries portal](https://glossaries.dila.edu.tw/), the exact [Soothill-Hodous](https://glossaries.dila.edu.tw/data/soothill-hodous.dila.pdf), [Kumārajīva](https://glossaries.dila.edu.tw/data/kumarajiva.dila.pdf), [Dharmarakṣa](https://glossaries.dila.edu.tw/data/dharmaraksa.dila.pdf), [Lokakṣema](https://glossaries.dila.edu.tw/data/lokaksema.dila.pdf) and [Mahāvyutpatti](https://glossaries.dila.edu.tw/data/mahavyutpatti.dila.pdf) digital editions, plus the [Mahāvyutpatti resource page](https://glossaries.dila.edu.tw/glossaries/MVP?locale=zh-TW), checked 2026-09-17 | Current portal says CC BY-NC-SA 4.0, while each exact digital-edition PDF states CC BY-SA 3.0 and points to the TEI source; Mahāvyutpatti's page separately says DILA believes the historical text is public domain. This is a primary licence-version/layer conflict. Keep the conservative NC pilot posture, preserve per-glossary scope, and require clarification where commercial/provider/public-artifact decisions depend on the difference |
| E20 | [Creative Commons BY-NC-SA 4.0 legal code](https://creativecommons.org/licenses/by-nc-sa/4.0/legalcode) and [BY-SA 3.0 legal code](https://creativecommons.org/licenses/by-sa/3.0/legalcode), checked 2026-09-17 | Both licences permit reuse/adaptation subject to their conditions; BY-NC-SA adds a noncommercial limitation. Neither legal code tells Pramāṇa whether a particular embedding/provider transfer is factually within a licensor's underlying rights or whether a concrete deployment is NonCommercial. Record those as operation-specific judgments rather than deriving them from a single registry boolean |
| E21 | [MITRA translation model card](https://huggingface.co/buddhist-nlp/gemma-2-mitra-it) and [current Gemma Terms](https://ai.google.dev/gemma/terms), checked 2026-09-17 | The historical MITRA translation arm is a Gemma-family derivative; current Gemma terms say Google claims no rights in generated output. That does not remove source-input rights, clear the historical Modal/provider transfer, or make generated index English canonical evidence. Treat the prior tranche as an internal historical artifact until source/model/provider operations are separately cleared |

## Incomplete or unresolved source trails

The original notebook cites a Telegram invite attributed to ~marfin, the handles
`@iiiichigo_chan` and `@thorstone137`, and a `movez.substack.com` homepage without
specific original permalinks/dates. The 14-step Fable essay was located only through a secondary syndication, not a
verified original permalink; its performance comparisons were not checked against
the underlying experiments. These are **idea leads**, not reliable acceptance evidence.
No exact primary evidence for the notebook's 6,290 xpk runs was established here.
Do not repeat that number, a model-specific token-price cliff, or the fixed 8 KB,
sub-millisecond, 100%-fit and zero-additional-cost claims as requirements or forecasts.

Letta/MemGPT, CoALA, Zep/Graphiti and HippoRAG appear as analogies in the old notebook,
not pinned evaluated dependencies. Preserve the functional questions—what to retain,
how to retrieve it, and who can trust it—without adopting their entire architectures.
The original record is retained through Git, with dispositions in the reconciliation.

## Adopt principles; evaluate implementations

The default is to build the minimal domain-specific evidence/authority contract and
reuse mature components where they fit. Do not build a memory SaaS or train a
translation model because an adjacent product exists. Do not reject all external
services as intrinsically unsafe; assess the actual data, authority, cost and
operating requirements. Engineering sources (E1–E6, E11–E13, E22–E42) and the
agent-tooling adoption table moved to [Foundry's research register](https://github.com/lorecrafting/foundry/blob/main/docs/strategy/RESEARCH.md).

| Candidate family | Gate before adoption | Not implied |
|---|---|---|
| Mem0-like retrieval or graph ranking | Relevant held-out recall benefit, provenance and privacy/scope tests; deploy only in the appropriate independent system | Copying one SQL weighting formula reproduces a commercial memory service |
| MITRA-E, OCR and other upstream corpus artifacts | Actual artifact availability, terms, source fidelity, alignment, local retrieval evaluation and bounded spend | A research score or initiative announcement justifies a full production bake |

A candidate graduates from **idea → bounded experiment → reviewed decision →
pinned implementation → acceptance evidence**. Failed or inconclusive results stay
in the record. No adoption changes protected authority or spending without the
separate required operator decision.
