# Pramāṇa architecture

Current implementation reference, checked against source at the documentation-audit
baseline. It describes code, not the state of a running database. See
[the repository map](REPO_MAP.md) for the separate Foundry system and
[the retained original design](records/architecture-design.md) for proposals and history.

## Pipeline and ownership

`acquire → normalize → segment → enrich → index → record identity`

Acquisition and loading have filesystem, network and database effects. Transformation
stages are intended to be deterministic; the whole pipeline is not a collection of
pure functions. The CLI owns mutations. MCP and the reader call the core domain.

| Stage | Source of truth | Contract |
|---|---|---|
| Acquire | [Acquisition modules](../apps/pramana/lib/pramana/acquire/), [source registry](../apps/pramana/lib/pramana/sources.ex), [lockfile](../sources.lock.json) | Preserve upstream snapshots and hashes; do not edit `raw/` in place |
| Normalize | [Normalizers](../apps/pramana/lib/pramana/normalize/) | Preserve citable structure, editorial apparatus and source distinctions |
| Segment | [Segmenters](../apps/pramana/lib/pramana/segment/), [URN parser](../apps/pramana/lib/pramana/urn.ex) | Adopt supported source anchors; distinguish derived addressing |
| Enrich | Commentary, quotations, translations, readings and authority modules in the core | Method and confidence travel with inferred or generated material |
| Index/retrieve | [Retrieval](../apps/pramana/lib/pramana/retrieval.ex), [hybrid](../apps/pramana/lib/pramana/retrieval/hybrid.ex) | Lexical and dense semantic retrieval, rank fusion and optional reranking; report which arms ran |
| Verify | [Citation guard](../apps/pramana/lib/pramana/guard.ex), verification/integrity tasks | Re-resolve source citations; separate reproducibility, completeness and interpretation |

PostgreSQL holds the text, provenance, relational layers and vectors. The CJK Rustler
NIF supplies segmentation. The separate Rust quotation scanner uses **seed-and-extend**
and JSONL files; Elixir imports results into Postgres. Python helpers perform batch
inference/training and artifact transfer, not corpus queries or normalization.

BGE-M3 capabilities are not all implemented retrieval modes. The current hybrid path
uses lexical and dense semantic results; sparse/ColBERT generation, hypothetical
questions and other design ideas must not be inferred from the model's capability list.
Without an available embedding serving or embedded rows, hybrid can fall back to
lexical and reports that limitation. [Embedding](EMBEDDING.md) owns that workflow.

## Addresses and provenance

The implemented URN grammar is:

```text
pramana:<source>.<witness>:<work>[@<locator>[-<end>]][#tr:<lang>/<translator>]
```

For example, `pramana:cbeta.T:T0262_009@p0037a13` uses an edition line anchor.
`pramana:sc.ms:mn1@1.1` illustrates the SuttaCentral source/witness and locator shape.
Parsing an example does not establish that it resolves in a particular database.
A rendering fragment identifies a translation of an anchor, not a new source work.

[Corpus schemas](../apps/pramana/lib/pramana/corpus/schemas.ex), the source registry
and source-specific classifiers own the fields. Composition origin, text role,
attribution confidence, date basis, addressing and licensing are distinct axes.
A Chinese rendering of an Indic root work is not given a `translation` text role
merely because its language changed. Local manifests support roles including `root`,
`treatise`, `commentary`, `subcommentary`, `apocryphon`, `catalogue`, `history` and `conflation`.

Grouped results make provenance visible. They do not guarantee that a classifier or
catalogue attribution is correct, nor can a tool prevent a model from ignoring a bucket.
[Invariants](pramana/INVARIANTS.md) state the constraints without treating them as proof.

## Identity and replay

[Pramana.Bake](../apps/pramana/lib/pramana/bake.ex) hashes the lockfile-derived inputs,
pipeline version and bake configuration. This is **source input identity**. Reproducing
source bytes also requires using those inputs and the matching pipeline correctly,
then validating the result; an ID alone cannot attest a manually altered database.

The current loader replaces rows. Segments have no per-row bake identity supporting
coexistent historic snapshots. Re-baking does not preserve a queryable older database.
Retain the actual inputs and backups needed to reconstruct or inspect an older result.

[Pramana.Release](../apps/pramana/lib/pramana/release.ex) already implements a separate
retrieval stamp. It records source identity, translation/vector counts, translator IDs
and embedding model names. `mix pramana.release.stamp` writes it;
`mix pramana.doctor` can report its status. **This is not a content hash of all
renderings and vectors.** Same-count edits, search-code/default changes and some other
state changes can be invisible. Its current drift comparison also omits source identity.
Do not advertise a matching `release_id` as a byte-complete retrieval snapshot.

[MCP Reply](../apps/pramana_web/lib/pramana_web/mcp/reply.ex) places `bake_id`,
`release_id` and the caller's non-null arguments in successful JSON replies.
`release_id` may be null until stamped. Error replies carry `bake_id` and replay
arguments but currently omit `release_id`. Omitted defaults are not pinned by the
replay record. **Re-runnable is not a promise of identical results.**

## Citation verification, precisely

The guard resolves a supplied URN and checks byte-substring containment for recognized
quoted text after trimming it. In free-form output, recognized quotation formats have
bounded matching; other detected URNs can receive existence-only checks. It does not
compare every sentence in an answer, establish entailment, or prove corpus-wide absence.
Inspect the breakdown of checked citations and refusals, not just an `ok?` boolean.

Generated renderings are not canonical source evidence. Human translations are also
labelled as renderings rather than merged into the original source. Translation
fidelity, historical attribution and interpretation remain separate questions.
[Translation](TRANSLATION.md) and [MCP](MCP.md) describe the relevant interfaces.

## What is implemented versus proposed

Work relations, passage-level commentary alignment, translation pools, reading
exceptions, authority linking, the reader and report checking have implementations.
Their presence does not establish complete corpus coverage or successful live acceptance.
A query-time translation cache/promotion service is not established by a proposed schema;
`translation_candidates` is not a current Ecto schema. An `index` versus `reader` purpose
policy is a design distinction, not an enforced column-level isolation guarantee.

Use [testing](TESTING.md) for evidence requirements, [status](STATUS.md) for the recorded
corpus snapshot, and the appropriate [plan section](PLAN_INDEX.md) for future work.

## Historical section bookmarks

These links preserve older references; their targets are explicitly historical/design material.

| Earlier section |
|---|
| <a id="architecture--how-the-sources-get-baked"></a>[Architecture — How the Sources Get Baked](records/architecture-design.md#architecture--how-the-sources-get-baked) |
| <a id="the-bake-in-one-line"></a>[The bake in one line](records/architecture-design.md#the-bake-in-one-line) |
| <a id="stage-0--acquire"></a>[Stage 0 — Acquire](records/architecture-design.md#stage-0--acquire) |
| <a id="stage-1--normalize"></a>[Stage 1 — Normalize](records/architecture-design.md#stage-1--normalize) |
| <a id="stage-2--segment"></a>[Stage 2 — Segment](records/architecture-design.md#stage-2--segment) |
| <a id="stage-3--enrich"></a>[Stage 3 — Enrich](records/architecture-design.md#stage-3--enrich) |
| <a id="stage-4--index"></a>[Stage 4 — Index](records/architecture-design.md#stage-4--index) |
| <a id="stage-5--freeze"></a>[Stage 5 — Freeze](records/architecture-design.md#stage-5--freeze) |
| <a id="the-provenance-model"></a>[The provenance model](records/architecture-design.md#the-provenance-model) |
| <a id="your-taishō-requirement-solved"></a>[Your Taishō requirement, solved](records/architecture-design.md#your-taishō-requirement-solved) |
| <a id="the-decoupling-contract"></a>[The decoupling contract](records/architecture-design.md#the-decoupling-contract) |
