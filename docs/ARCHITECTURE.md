# Architecture — How the Sources Get Baked

This is the answer to "how would the sources be baked, and how do we decouple the
LLM from them."

Everything here is **implementation-independent** — the URN scheme, the provenance
axes, the bake, and the citation guard are design, not code. For how it maps onto
Elixir/Phoenix (and the three components that deliberately aren't Elixir), see
`ELIXIR.md`.

## The bake in one line

`acquire → normalize → segment → enrich → index → freeze`

Each stage is pure and re-runnable. The output of the final stage is a **bake**: an
immutable, content-addressed corpus snapshot with an ID that every answer cites.

---

## Stage 0 — Acquire

Downloads pinned upstream snapshots into `raw/`. Nothing is ever edited here.

Everything is recorded in `sources.lock.json`:

```json
{
  "bake_schema": 1,
  "sources": [
    {
      "id": "cbeta",
      "upstream": "https://github.com/cbeta-org/xml-p5",
      "pin": { "type": "git", "commit": "a1b2c3d..." },
      "retrieved_at": "2026-08-13T00:00:00Z",
      "license": { "spdx": "LicenseRef-CBETA-NC", "commercial_use": false },
      "files_sha256": "sha256:...",
      "file_count": 4821
    }
  ]
}
```

Git-hosted sources (CBETA, SuttaCentral, 84000) pin to a commit SHA. Dump-based
sources (SAT, OpenPecha) pin to a dated archive plus its hash. **If you can't pin
it, you can't bake it** — an unpinnable source gets an explicit `pin.type: "mutable"`
flag and its content is marked lower-confidence.

---

## Stage 1 — Normalize

Every source's native format (TEI P5, bilara JSON, 84000 TEI, OCR text) is converted
to one canonical intermediate representation. This stage is where most real
engineering time goes, and where quiet data corruption happens.

What must survive normalization:

| Feature | Why it matters |
|---|---|
| `<lb/>` line breaks | Taishō page/register/line **is** the citation. Lose these, lose citability. |
| `<juan>` fascicle marks | Traditional fascicle (卷) divisions used in all secondary literature |
| `<lg>/<l>` verse structure | Verse vs. prose changes both chunking and translation |
| `<app>/<lem>/<rdg>` | Variant readings across Song/Yuan/Ming/Koryŏ witnesses — a shipped feature |
| `<note>` | Editorial and translator notes, kept separable from body text |
| Gaiji `<g ref="#CB01234"/>` | ~30k rare glyphs; map to Unicode via the gaiji table or keep a stable placeholder |

Traps that have bitten every project in this space:

- **Unicode normalization on CJK.** Do *not* blanket-NFC CJK. Han variant characters
  are semantically meaningful in a critical edition. Store the original codepoint;
  keep a separate normalized field for matching.
- **Editorial punctuation.** CBETA's punctuation was added by modern editors and is
  absent from the witness. Retain it, but flag it, so nobody cites it as original.
- **Tibetan segmentation.** Tibetan has no word spaces, only syllable dots (tsheg)
  and clause markers (shad). Naive splitting produces garbage.

---

## Stage 2 — Segment

The decision that determines whether this project is trustworthy:

> **The citable unit is edition-anchored, not chunker-derived.**

Everyone else chunks by token count and then has to invent an ID. That ID means
nothing to a scholar and can't be checked against a printed page. Instead, adopt each
tradition's existing citation grammar and wrap it in a URN (the scheme is borrowed
from CTS/CITE in classics):

```
pramana:cbeta.T:T0262_009@p0037a13-p0037b02     Lotus Sūtra, Kumārajīva, T vol.9
pramana:sat.T:T2688_001@p0783b12                 Nichiren-school comm., T vol.84
pramana:sc.pali:mn1:1.1                          Mūlapariyāya Sutta, segment 1.1
pramana:84000.kangyur:toh113@F.1.b.1             Derge Kangyur, folio 1b line 1
```

Retrieval chunks are then *windows over* these anchors, and a chunk's URN is a range
of real citation points. A chunk can be re-resolved to the exact characters it came
from, which is what makes the citation guard possible.

Two-level indexing: embed ~200–400 token windows for recall, but return the
containing structural unit (verse, gāthā, commentary gloss) for readability.

---

## Stage 3 — Enrich

Where we beat the competition. **Deterministic methods first.**

- **Quotation graph.** Commentaries quote root texts verbatim. Run suffix-array /
  n-gram matching across the full corpus to find reuse. Over ~250M characters this
  is a large but entirely tractable batch job — and it yields a real citation
  network with zero LLM involvement. Powers "show me every text that quotes this
  passage of the Lotus Sūtra."
- **Cross-canon parallels from existing scholarship.** SuttaCentral's `sc-data`
  already contains thousands of hand-curated Āgama↔Nikāya parallels, free and CC0.
  Ingest them rather than rediscovering them with embeddings.
- **Term correspondence tables.** The *Mahāvyutpatti* is a canonical
  Sanskrit–Tibetan term dictionary; 84000 publishes a Skt–Tib–Eng glossary; DDB
  covers Chinese Buddhist terms. These give exact, citable cross-lingual anchors.
- **Commentary structure parsing.** Commentaries follow lemma-and-gloss form (科文):
  quote a phrase, then explain it. Parsing that structure yields root↔commentary
  alignment *deterministically*.
- **Multiple-translation alignment (異譯本).** Many works were translated into
  Chinese 2–6 times (the Lotus Sūtra three times). Aligning these is high-value and
  unique to the Chinese canon — see ROADMAP.
- **Authority linking.** DILA person/place/time authority DB, BDRC RIDs, Wikidata
  Q-IDs for people, places, and dates.

The LLM is used **only for the residual** after all of the above, and anything it
produces is stored with `method: "llm"` and a confidence score, so it can be
filtered out or re-verified independently.

---

## Stage 4 — Index

**One Postgres.** Text, provenance, embeddings, and FTS in a single ACID store, so
that this composes in one query plan:

```sql
-- "semantically similar, but only Indic-origin root texts"
WHERE composition_origin = 'indic' AND text_role = 'root'
ORDER BY embedding <=> :query_vec
```

That predicate-plus-vector query is the single most important thing this system
does. Splitting the vector store from the metadata store makes it awkward, which is
why we don't.

- **Embeddings:** BGE-M3. Multilingual, 8192 context, and it emits dense + sparse +
  ColBERT vectors in one pass — hybrid retrieval without a second model.
- **Multi-vector per segment.** Embed (a) the source text, (b) an English gloss,
  (c) generated hypothetical questions. Cross-lingual retrieval over Classical
  Chinese with a general multilingual model is genuinely weak — `tripitaka-mcp`
  concedes exactly this about Pāli. Embedding a translation alongside the original
  is the cheapest large win available.
- **Lexical:** `pg_bigm` for Chinese/Japanese (no whitespace — `pg_trgm` and
  `to_tsvector` assumptions break); Postgres FTS with per-language configs for
  Latin-script and transliterated text.
- **Fusion:** Reciprocal Rank Fusion over dense + sparse + lexical.

---

## Stage 5 — Freeze

```
bake_id = sha256(sources.lock.json + pipeline_version + bake_config)
```

`Pramana.Bake` implements this, and `bake_id` is stamped on API and MCP responses.
Two people with the same id hold byte-identical corpora, so a citation is reproducible
years later — the real meaning of "decoupled."

Bump `pipeline_version` whenever a change alters normalization or segmentation
**output**; not for refactors or new query paths, which leave the corpus identical.
Erring lax is the dangerous direction: two different corpora sharing an id means a
citation that verified yesterday can fail today with nothing to point at.

**Current limit, stated plainly.** `segments` carries no `bake_id` and the loader
replaces rows in place, so there is exactly **one current bake** at a time. Bakes do
not coexist, and re-baking does not leave old citations resolvable against the older
bake. Acceptable while a single corpus is being built, and cheap to change later (a
nullable column is not a table rewrite) — but the docs must not claim more than the
code does.

---

## The provenance model

**Provenance is several orthogonal axes, never one `source` field.** This is what
makes the Taishō problem tractable.

| Axis | Values | Example |
|---|---|---|
| `witness` | Taishō, Koryŏ, Song, Derge, Dunhuang ms. | Which printed/physical edition |
| — | — | *(`text_role` says what a text IS; `composition_origin` says where it came from. A Chinese translation of an Indian sūtra is `indic` + `root`, not "translation" — how it arrived is already answered by origin.)* |
| `work` | stable work ID (FRBR-style) | The abstract text, across all its versions |
| `composition_origin` | indic, chinese, japanese, tibetan, korean | Where it was *composed* |
| `text_role` | root, treatise, commentary, subcommentary, apocryphon, catalogue, history, translation, conflation | What the text **is** |
| `division` | 阿含部, 般若部, 經疏部, 疑似部 … | The Taishō's own 部 classification |
| `attributed_author` | + `attribution_confidence` | Much of the canon is pseudepigraphic |
| `date_range` | earliest/latest | Composition or translation date |
| `license_class` | cc0, cc-by-sa, nc, restricted | Drives redistribution gating |

### Your Taishō requirement, solved

CBETA covers Taishō vols **1–55 and 85**. SAT covers **1–85**. The delta —
vols **56–84** — is precisely the Japanese-composed sectarian corpus (Shingon,
Tendai, Nichiren, Zen). So there is a **mechanical rule**, not a heuristic:

```
volume 56..84  →  composition_origin = japanese, text_role = commentary
```

In practice this is now applied at finer resolution through the **division table**
(`Pramana.Taisho.Divisions`), which maps Taishō *text numbers* to 部 and derives origin
and role from them — 續經疏部 (2185–2700) and 悉曇部 (2701–2731) are precisely the works
in vols 56–84. CBETA ships no classification markup, so the table was assembled from
two independent published contents listings and is **validated against the corpus**:
every division's numbers must fall inside its stated volumes, checked over all 2,471
works before any write. Populated result: 1,781 indic, 555 chinese, 57 apocrypha, and
135 left deliberately unattributed.

Same axis cleanly handles the 疑偽部 (apocrypha, T2865–2920): Chinese-composed texts
that *present themselves* as Indian translations —
`composition_origin = chinese, text_role = apocryphon`.

Two enforcement layers, and the second is the one that matters:

1. Filterable: `origin != japanese` is one SQL predicate.
2. **Structural.** Retrieval results are returned *grouped by origin and role*, so a
   Kamakura-period Nichiren commentary arrives in a visibly different bucket than a
   Kumārajīva translation. The model cannot flatten them into one undifferentiated
   pile, because the tool response was never flat. Prompting for this would be a
   suggestion; shaping the response makes it a property of the system.

---

## The decoupling contract

The boundary between corpus and model is a hard interface:

**The LLM never sees the database.** It sees retrieval tools that guarantee:

1. Every span returns `urn`, `char_start`, `char_end`, `sha256`, provenance.
2. `verify(urn, quoted_text) -> bool` re-resolves and byte-compares.
3. No tool returns text without attribution.
4. Responses are structured data, never pre-formatted prose. (This is also what
   makes a fojin-style web reader cheap to add later — the UI becomes a renderer.)

**The citation guard runs after generation, outside the model:** extract every URN
from the output, re-resolve it against the bake, byte-compare quoted spans, and flag
or reject mismatches. It is deterministic and works with *any* model — Claude today,
a local model tomorrow, something else in three years — with no change to the corpus.

That is the decoupling. The bake is the durable asset; the model is a commodity.
