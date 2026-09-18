# Chinese pilot rights and data-flow boundaries

**Reviewed:** 2026-09-17  
**Status:** preflight evidence, not legal advice and not provider authorization.  
**Pilot:** Chinese-first bounded CBETA pilot described by [PILOT_CHARTER](PILOT_CHARTER.md)
and [PILOT_PREFLIGHT](PILOT_PREFLIGHT.md).

This document answers a narrow product-policy question: for each resource the proposed
Chinese pilot actually touches, what operations are supported by current primary evidence,
what is blocked, and what must be clarified before bytes cross a new boundary?

The answer is deliberately fail-closed. A resource being public on the web, already
downloaded, previously embedded, or previously sent through an AI workflow is not an
authorization for a new operation.

## Interpretation contract

The rights state vocabulary is exact:

- **permitted** — the reviewed primary evidence supports this operation for the stated
  pilot purpose and conditions. It does not grant spending or inference authority.
- **prohibited** — the reviewed terms expressly disallow the operation under the proposed
  conditions.
- **permission required** — the reviewed evidence expressly requires a separate permission
  or the Pramāṇa product policy requires an affirmative clearance before the operation.
- **unclear / unresolved** — current evidence does not decide the operation, is internally
  conflicting, or the exact resource scope is not frozen. This is **not** weak permission.

For execution, **permission required and unclear / unresolved both mean STOP**. Only an
explicitly permitted operation may run. No implementer may reinterpret either blocked
state as "probably permitted", and a failed source does not authorize silent substitution
of another corpus, dictionary, model, or provider.

Three layers must stay separate:

1. **copyright/licence evidence** — what the reviewed terms actually say;
2. **stakeholder request or norm** — an upstream request that can be stricter than the
   copyright licence without silently becoming the licence;
3. **Pramāṇa product policy** — our deliberately conservative runtime/export choice.

This review is architecture and product-policy evidence, not a legal opinion.

## Exact repository inventory

The current repository does not have one operation-aware rights authority.

- Pramāṇa's source registry records CBETA as source id **cbeta** with
  LicenseRef-CBETA-NC, commercial_use false and redistributable false.
- The five DILA glossary files are collapsed into one source id,
  **dila-glossaries**, with one conservative CC-BY-NC-SA-4.0 record. Individual rows
  preserve the glossary id in metadata, but the source record cannot express the
  resource-specific licence history below.
- The SuttaCentral Chinese alignment importer attaches Charles Patton's human English
  renderings to CBETA anchors. The exact publications relevant to the present bounded
  Chinese layer are **scpub20** (Saṃyukta Āgama / T0099 coverage) and **scpub35**
  (Madhyama Āgama / T0026 coverage), each published as CC0 in bilara-data's
  publication metadata.
- The existing generated-English Chinese tranche is a separate historical layer:
  27,956 generated renderings over the recorded 14-work demand-weighted tranche. The
  export path sent selected CBETA chunk content to a generation host and the importer
  stored returned English as tier t1, method llm, raw/non-canonical renderings. This
  history is evidence about data flow, not permission to repeat it.

The live pilot scope is not frozen yet. The intended seed is the live equivalent of the
recorded 14-work CBETA tranche plus accepted comments_on/subcommentary_of neighborhoods.
Every expanded work must therefore be mapped back to an exact source/edition before this
review can clear the complete pilot scope.

## Primary evidence reviewed

Checked 2026-09-17:

| Resource | Primary/current evidence | What it establishes |
|---|---|---|
| CBETA database | [CBETA copyright declaration](https://cbeta.org/copyright) | Database use is non-profit/non-commercial; redistribution, quotation and reprocessed release require the notice/version information and generally should not alter substantive content; default licence is CC BY-NC-SA 4.0 except listed exceptions; Taishō vols. 1–85 are Category A |
| Taishō rights through CBETA | [CBETA FAQ](https://cbeta.org/en/faq) | CBETA says its Taishō authorization is for digital distribution, not print, and advises checking the original publisher/rightsholder for other reuse |
| CBETA AI precedent | [CBETA AI semantic-search beta](https://cbeta.org/post/28688) | DILA/CBETA publicly used vector search, RAG and OpenAI API over CBETA. This is implementation precedent, **not a licence grant to Pramāṇa** |
| DILA portal | [DILA Glossaries](https://glossaries.dila.edu.tw/) | Current portal says its content is CC BY-NC-SA 4.0 |
| Soothill-Hodous exact digital edition | [DILA PDF](https://glossaries.dila.edu.tw/data/soothill-hodous.dila.pdf) | The exact digital edition identifies its TEI source and states CC BY-SA 3.0 |
| Karashima: Kumārajīva | [DILA PDF](https://glossaries.dila.edu.tw/data/kumarajiva.dila.pdf) | The exact digital edition states CC BY-SA 3.0 |
| Karashima: Dharmarakṣa | [DILA PDF](https://glossaries.dila.edu.tw/data/dharmaraksa.dila.pdf) | The exact digital edition states CC BY-SA 3.0 |
| Karashima: Lokakṣema | [DILA PDF](https://glossaries.dila.edu.tw/data/lokaksema.dila.pdf) | The exact digital edition states CC BY-SA 3.0 |
| Mahāvyutpatti | [DILA page](https://glossaries.dila.edu.tw/glossaries/MVP?locale=zh-TW) and [DILA PDF](https://glossaries.dila.edu.tw/data/mahavyutpatti.dila.pdf) | DILA says it believes the historical text is public domain; the exact digital edition states CC BY-SA 3.0 |
| CC BY-NC-SA 4.0 | [Creative Commons legal code](https://creativecommons.org/licenses/by-nc-sa/4.0/legalcode) | Noncommercial reproduction/sharing and adaptation are licensed subject to attribution/share-alike conditions; the licence does not settle rights the licensor did not have |
| CC BY-SA 3.0 | [Creative Commons legal code](https://creativecommons.org/licenses/by-sa/3.0/legalcode) | Reuse/adaptation is licensed with attribution/share-alike obligations and no NC element |
| Patton human English | bilara-data published branch, publication records scpub20 and scpub35; [SuttaCentral licensing](https://suttacentral.net/licensing) | The two exact publications are CC0. SuttaCentral separately asks that its content not be used for generative-AI datasets or downstream AI-derived technologies |
| Existing MITRA English | repository transfer/import code; [MITRA model card](https://huggingface.co/buddhist-nlp/gemma-2-mitra-it); [current Gemma Terms](https://ai.google.dev/gemma/terms) | MITRA is a Gemma-2 derivative/model family; current Gemma terms say Google claims no rights in generated output. That does not erase rights in the CBETA input or authorize the historical provider route |

### DILA has a real version conflict, not a "secondary source" problem

The previous repository prose said the current portal's CC BY-NC-SA 4.0 should govern
because a secondary source reported BY-SA 3.0. Primary evidence now falsifies that
description: the exact Soothill-Hodous, three Karashima and Mahāvyutpatti digital-edition
PDFs themselves state **CC BY-SA 3.0**, while the current portal states **CC BY-NC-SA
4.0**.

This review does not choose the more permissive notice and does not claim the newer portal
notice revoked an older licence. For pilot policy, locally held glossary bytes are treated
under the **more restrictive current NC baseline**, while the licence-version conflict
must be clarified before any operation whose answer depends on whether commercial use is
allowed or before a public artifact is designed around the more permissive terms.

Mahāvyutpatti has another layer: DILA says the historical text is believed public domain,
but the pilot actually ingests DILA's digital/TEI edition. Public-domain status of the
underlying vocabulary does not automatically place DILA's markup, corrections, packaging
or other editorial contribution in the public domain.

## Operation-specific rights matrix

These tables record the **copyright/licence evidence state**. Product-policy overrides
follow immediately after them. "External source/rendering text" means source or rendering
bytes supplied to a cloud/provider model; "external glossary text" means DILA
entry/definition/equivalence bytes supplied in prompts, context, files or provider stores.

### Operations 1–6

| resource | 1 local storage | 2 local index/search | 3 embeddings / derived retrieval artifacts | 4 English→Chinese query expansion | 5 external source/rendering text | 6 external glossary text |
|---|---|---|---|---|---|---|
| **CBETA Taishō Category A** | permitted, NC + notice/version | permitted, NC | **unclear / unresolved** | permitted locally, NC; no equivalence claim created | **unclear / unresolved** | not applicable |
| **DILA Soothill-Hodous** | permitted, treat as NC | permitted, treat as NC | permitted locally, treat as NC | permitted locally with glossary provenance | not applicable | **unclear / unresolved** |
| **DILA Karashima / Kumārajīva** | permitted, treat as NC | permitted, treat as NC | permitted locally, treat as NC | permitted in T0262 scope with provenance | not applicable | **unclear / unresolved** |
| **DILA Karashima / Dharmarakṣa** | permitted, treat as NC | permitted, treat as NC | permitted locally, treat as NC | permitted in T0263 scope with provenance | not applicable | **unclear / unresolved** |
| **DILA Karashima / Lokakṣema** | permitted, treat as NC | permitted, treat as NC | permitted locally, treat as NC | permitted in T0224 scope with provenance | not applicable | **unclear / unresolved** |
| **DILA Mahāvyutpatti digital edition** | permitted, treat as NC | permitted, treat as NC | permitted locally, treat as NC | permitted locally with Sanskrit/Chinese provenance | not applicable | **unclear / unresolved** |
| **Patton scpub20/scpub35 human English** | permitted (CC0) | permitted (CC0) | permitted by copyright | permitted by copyright | permitted by copyright | not applicable |
| **existing generated MITRA English over CBETA** | **unclear / unresolved** | **unclear / unresolved** | **unclear / unresolved** | **unclear / unresolved** | **unclear / unresolved** | not applicable |

Why CBETA embeddings/model-derived artifacts remain unresolved: CBETA's current page both
places Category A material under an NC-SA baseline and separately tells users to contact
original rightsholders for uses outside the site's licence scope, giving adaptation as an
example. The pilot must not decide on its own that every embedding, generated reading
translation or synthesis operation falls cleanly inside the authorization granted to
CBETA for the underlying Taishō edition. CBETA's own RAG experiment proves technical and
stakeholder precedent, not Pramāṇa's rights.

Why DILA local derived artifacts are permitted while cloud transfer is unresolved: both
the older resource-specific BY-SA 3.0 notice and the current portal's BY-NC-SA 4.0 permit
reuse/adaptation; the restrictive common denominator is noncommercial use plus
attribution/share-alike when material is shared. Sending material to an external provider
adds separate provider licences, retention/training behavior and a fact-specific NC
question that the DILA notices do not answer.

Why the Patton copyright cells are permissive but the pilot still restricts AI use:
scpub20/scpub35 are explicitly CC0. SuttaCentral's current AI request is therefore recorded
as a **stakeholder norm**, not silently converted into a copyright restriction.

### Operations 7–12

| resource | 7 local-model processing | 8 reader display | 9 quote/copy into evidence packet | 10 evaluation retention | 11 redistribution/public artifact | 12 commercial implication |
|---|---|---|---|---|---|---|
| **CBETA Taishō Category A** | **unclear / unresolved** for generation/translation; ordinary local search permitted | permitted, NC + CBETA notice/version | permitted for bounded NC excerpts with notice/version; preserve Chinese verbatim | permitted locally, NC | permitted only under applicable NC/reuse conditions; exact reprocessed artifact must be reviewed | **prohibited** absent separate permission |
| **DILA Soothill-Hodous** | permitted locally, treat as NC | permitted, attribution/licence | permitted, attribution/licence | permitted locally, treat as NC | permitted NC under restrictive common denominator, attribution/SA | **unclear / unresolved** because specific BY-SA 3.0 and current portal BY-NC-SA 4.0 differ |
| **DILA Karashima / Kumārajīva** | permitted locally, treat as NC | permitted, attribution/licence | permitted, attribution/licence + T0262 scope | permitted locally, treat as NC | permitted NC under restrictive common denominator, attribution/SA | **unclear / unresolved** |
| **DILA Karashima / Dharmarakṣa** | permitted locally, treat as NC | permitted, attribution/licence | permitted, attribution/licence + T0263 scope | permitted locally, treat as NC | permitted NC under restrictive common denominator, attribution/SA | **unclear / unresolved** |
| **DILA Karashima / Lokakṣema** | permitted locally, treat as NC | permitted, attribution/licence | permitted, attribution/licence + T0224 scope | permitted locally, treat as NC | permitted NC under restrictive common denominator, attribution/SA | **unclear / unresolved** |
| **DILA Mahāvyutpatti digital edition** | permitted locally, treat as NC | permitted, attribution/licence | permitted, attribution/licence | permitted locally, treat as NC | permitted NC under restrictive common denominator, attribution/SA | **unclear / unresolved** for the DILA digital edition |
| **Patton scpub20/scpub35 human English** | permitted by copyright | permitted as attributed human rendering | permitted as attributed translation, not Chinese source | permitted by copyright | permitted by copyright (CC0) | permitted by copyright |
| **existing generated MITRA English over CBETA** | **unclear / unresolved** | **unclear / unresolved** as a rights question; never source evidence | **unclear / unresolved** as redistribution; **prohibited** as canonical source evidence | **unclear / unresolved** beyond existing internal historical artifacts | **unclear / unresolved** | **unclear / unresolved**; CBETA input is NC and output rights do not cure that |

"Permitted" here is not a recommendation to expose full entries or source passages. It
states the reviewed licence baseline. The pilot policy below is intentionally narrower.

## Stakeholder/project norms kept separate from copyright

### CBETA

CBETA's 2025 semantic-search beta used vectorised CBETA text, RAG and OpenAI API. That is
strong evidence that AI-assisted retrieval is not categorically alien to the project. It
does **not** say that Pramāṇa may reuse the same bytes, provider route, embeddings or
generated translations without its own rights review.

### DILA

The current portal says CC BY-NC-SA 4.0, while each exact pilot digital edition reviewed
above carries an older CC BY-SA 3.0 notice. The three Karashima portal descriptions also
say DILA digitised the works with the author's permission. This review does not infer the
scope of unpublished author agreements. It relies only on published notices and blocks
the operations for which their conflict matters.

### SuttaCentral / Patton

The exact Patton publications are CC0, but SuttaCentral's current licensing page politely
requests that its content not be scraped or used for generative-AI datasets or downstream
AI-derived technologies. Pramāṇa will respect that request for **new AI-derived use** of
the Patton renderings unless SuttaCentral/translator clearance is obtained. Existing
historical vectors do not become new authorization.

## Pramāṇa conservative pilot policy

The pilot policy is narrower than the maximum licence reading:

- **CBETA remains the authoritative textual witness.** No generated English becomes
  canonical evidence.
- **Do not send CBETA source bytes to an external/cloud model** until the exact pilot scope,
  CBETA/rightsholder operation clearance, provider terms and inference authority are all
  independently cleared.
- **Do not send DILA glossary/lexicon bytes to an external/cloud model** until DILA's
  resource-level licence-version conflict and the provider boundary are reviewed. Local
  deterministic query expansion is allowed under the restrictive NC baseline.
- **Do not use Patton human English as training/few-shot/model context or as a new
  AI-derived query-expansion source** without stakeholder clearance, despite the CC0
  copyright position. Reader display as an attributed human translation remains allowed.
- **Do not treat the historical MITRA tranche as authorization.** It may be inspected as a
  historical internal artifact, but the pilot may not regenerate it, expand it, promote
  it to reader English, or export it until the CBETA/model-processing decision is cleared.
- The current source registry's redistributable false values for CBETA and DILA are
  **project public-artifact policy**, not a claim that every applicable licence forbids
  all redistribution. The pilot continues to exclude those bytes from public corpus
  artifacts unless a later reviewed export design explicitly clears them.
- Evidence packets default to **URN/link + source/release metadata + hash + the smallest
  permitted verbatim excerpt**. Display permission does not imply packet export
  permission.
- A glossary match retains glossary id, work/translator scope and relation type. A reverse
  dictionary hit never becomes doctrinal equivalence merely because retrieval succeeds.

## Provider boundary: what a later review must prove

No paid/provider model is selected or authorized by this PR. Before any external model
receives source, rendering or glossary bytes, a later provider review must record at least:

1. exact provider, product/API, model and contractual entity;
2. what licence the provider receives over prompts, uploaded files, cached context and
   generated outputs;
3. whether customer inputs/outputs are used for training, model improvement, human review,
   abuse monitoring or evaluation;
4. retention duration, log scope, deletion mechanism and whether a zero-retention mode is
   actually contractual for the selected product;
5. subprocessors, storage/processing region and cross-region transfer;
6. confidentiality/DPA posture and whether the provider can disclose or reuse customer
   content;
7. output ownership/licence and any model-specific downstream restrictions;
8. whether the intended use of NC-licensed material remains noncommercial under the
   concrete deployment facts — **do not infer this merely from the provider being paid or
   unpaid**;
9. any provider prohibition or representation requiring the customer to warrant rights
   broader than Pramāṇa actually has;
10. exact spend/inference authority and execution bounds from their independent gates.

A provider's "no training" marketing sentence is insufficient if retention, abuse review,
subprocessors, input licence or contract scope remains unknown.

## Fail-closed data-flow decision tree

For every candidate byte sequence or excerpt:

1. **Identify the exact resource and layer.** Record source id, exact glossary/publication
   where applicable, edition/release identity and whether the bytes are Chinese source,
   human rendering, generated index English or glossary data.
2. **Check live pilot scope.** If the work/resource is outside the frozen seed +
   accepted commentary/subcommentary neighborhood, stop. Rights clearance never expands
   scope.
3. **Look up the operation.** If the matrix says prohibited, permission required, or
   unclear / unresolved, stop. Record the exact missing permission/review; do not choose a
   substitute corpus/dictionary.
4. **External-provider branch.** Even when the source operation is permitted, source
   clearance + provider_terms + inference_authority + execution_bounds must all clear
   independently before bytes leave the local boundary.
5. **Local-only branch.** If external processing is blocked but local-model processing is
   permitted for that resource, a separately reviewed local model may be used. If local
   processing is also unresolved, no generation occurs.
6. **Reader branch.** Show authoritative Chinese and a cleared human rendering where
   available. Generated reading translation, if later authorized, stays source-bound,
   labelled and non-canonical. Historical index English is not silently promoted to the
   reader layer.
7. **Evidence-packet branch.** If copying is not cleared, emit links/URNs, source/release
   identity, hashes and metadata instead of text. If excerpts are cleared, copy only the
   bounded permitted excerpt with required notices/attribution.
8. **Retention branch.** Evaluation retention is a separate operation. A transiently
   displayable passage is not automatically retainable in a study dataset or export.
9. **Commercial/public branch.** Re-evaluate exact licence/version and artifact contents.
   Never infer commercial clearance from a locally successful pilot.

### Is local-only technically compatible with the trust contract?

Yes **architecturally**, but it is not ready today. The Chinese witness, query provenance,
deterministic fusion, source anchors, translation labels and evidence verification do not
depend on a cloud provider. Deterministic DILA query expansion is already local, and a
future local model could occupy the same bounded reading-translation interface.

What is not established is the actual local model identity/licence, hardware envelope,
quality, latency, evaluator acceptance, execution bounds or CBETA permission for the
generation operation. Therefore "local-only" is a valid fail-closed architecture branch,
not a backdoor readiness claim.

## Registry gap and implementation consequence

The current Sources licence shape — SPDX/class, commercial_use, redistributable and one
derivatives boolean — is useful for broad serving/export gates but **too coarse to
authorize this pilot**:

- dila-glossaries collapses five exact digital resources with conflicting old-specific
  and current portal notices;
- it cannot distinguish underlying public-domain content from a digital/TEI edition;
- derivatives cannot distinguish embeddings, translation, summarisation and other
  transformations;
- it has no provider-transfer/retention axis;
- it cannot distinguish reader display, evidence-packet copying and public artifact
  redistribution;
- it has no place for a nonbinding stakeholder AI-use request such as SuttaCentral's.

For this pilot, this document is the operation-level preflight authority and the source
registry remains a conservative coarse gate. Do not weaken the registry to make the
matrix fit. A future implementation may add structured per-resource rights metadata only
after the pilot requirements are frozen; that is separate product work and remains gated
behind Foundry G0.

## Preflight verdict

This research **does not make the pilot ready**.

- **cbeta_rights stays blocked:** Category A/NC baseline is established, but the complete
  live expanded scope is not frozen and embedding/generated-translation/local-model/cloud
  operations still need explicit clearance.
- **lexicon_rights stays blocked:** local deterministic use is supported under a
  conservative NC reading, but the exact DILA resources carry a primary BY-SA-3.0 versus
  current portal BY-NC-SA-4.0 conflict, and external-model transfer is not cleared.
- **provider_terms stays blocked:** no provider/product/model has been selected or
  authorized, so no provider terms can yet be approved.

The useful outcome is a smaller execution surface, not a false green gate: local
deterministic Chinese retrieval/query expansion can be designed around these constraints,
while every model/provider boundary remains independently fail-closed.
