# Pramāṇa CLI index

Commands are derived from task modules at the audit baseline, not from a design wish list.
Use `mix help TASK` for current flags and prerequisites. These are **not all read-only**:
ingestion, imports, acquisition, stamping, indexing and acceptance can mutate state or
use paid services. Read the task before executing it. Foundry uses its separate
[CLI and workflow contracts](../foundry/docs/README.md).

| Task | Source summary |
|---|---|
| [`mix pramana.acquire`](../apps/pramana/lib/mix/tasks/pramana.acquire.ex) | Fetches pinned upstream corpus sources into raw/ |
| [`mix pramana.acquire_all`](../apps/pramana/lib/mix/tasks/pramana.acquire_all.ex) | Bulk-acquires an entire source into raw/ from one pinned archive |
| [`mix pramana.authority.import`](../apps/pramana/lib/mix/tasks/pramana.authority.import.ex) | Imports DILA authority people, their lineage, and their external ids |
| [`mix pramana.authority.link`](../apps/pramana/lib/mix/tasks/pramana.authority.link.ex) | Links work bylines to DILA authority persons |
| [`mix pramana.bake`](../apps/pramana/lib/mix/tasks/pramana.bake.ex) | Normalizes, segments, and loads acquired sources into the corpus |
| [`mix pramana.bake_all`](../apps/pramana/lib/mix/tasks/pramana.bake_all.ex) | Bakes every acquired work via Oban, resumably |
| [`mix pramana.chunk`](../apps/pramana/lib/mix/tasks/pramana.chunk.ex) | Builds retrieval chunks over the baked segments |
| [`mix pramana.coherence`](../apps/pramana/lib/mix/tasks/pramana.coherence.ex) | Cross-checks independently derived facts about the same works |
| [`mix pramana.commentary.align`](../apps/pramana/lib/mix/tasks/pramana.commentary.align.ex) | Aligns commentaries to their root texts, lemma by lemma |
| [`mix pramana.derge.images`](../apps/pramana/lib/mix/tasks/pramana.derge.images.ex) | Fetches BDRC's image lists for the Derge Kangyur, one per volume |
| [`mix pramana.derge.ingest`](../apps/pramana/lib/mix/tasks/pramana.derge.ingest.ex) | Ingests the Digital Derge Kangyur, volume by volume |
| [`mix pramana.derge.relations`](../apps/pramana/lib/mix/tasks/pramana.derge.relations.ex) | Links Tibetan commentaries to the works they explain, from their titles |
| [`mix pramana.derge.titles`](../apps/pramana/lib/mix/tasks/pramana.derge.titles.ex) | Promotes the Degé title already held in works.meta into works.title |
| [`mix pramana.docs.figures`](../apps/pramana/lib/mix/tasks/pramana.docs.figures.ex) | Regenerates the corpus figures embedded in documentation, or checks them |
| [`mix pramana.doctor`](../apps/pramana/lib/mix/tasks/pramana.doctor.ex) | Prints the state a session otherwise rediscovers with hand-written SQL |
| [`mix pramana.embed`](../apps/pramana/lib/mix/tasks/pramana.embed.ex) | Embeds retrieval chunks with BGE-M3 |
| [`mix pramana.embed.export`](../apps/pramana/lib/mix/tasks/pramana.embed.export.ex) | Exports pending chunk text for embedding on a GPU elsewhere |
| [`mix pramana.embed.fetch_model`](../apps/pramana/lib/mix/tasks/pramana.embed.fetch_model.ex) | Brings the fine-tuned embedding weights back from the GPU volume |
| [`mix pramana.embed.import`](../apps/pramana/lib/mix/tasks/pramana.embed.import.ex) | Imports vectors produced on a GPU elsewhere |
| [`mix pramana.embed.index`](../apps/pramana/lib/mix/tasks/pramana.embed.index.ex) | Builds (or rebuilds) the HNSW index over chunk vectors |
| [`mix pramana.evals.compare`](../apps/pramana/lib/mix/tasks/pramana.evals.compare.ex) | Diffs two eval scorecards, and says which differences mean nothing |
| [`mix pramana.evals.derive`](../apps/pramana/lib/mix/tasks/pramana.evals.derive.ex) | Derives gold-set cases from ground truth already in the corpus |
| [`mix pramana.evals`](../apps/pramana/lib/mix/tasks/pramana.evals.ex) | Scores retrieval, citation and provenance against the gold set |
| [`mix pramana.evals.sweep`](../apps/pramana/lib/mix/tasks/pramana.evals.sweep.ex) | Runs the gold set across a grid of retrieval configurations |
| [`mix pramana.gate`](../apps/pramana/lib/mix/tasks/pramana.gate.ex) | Runs every checkpoint check, cheapest first, and stops at the first failure |
| [`mix pramana.glossary.anchor`](../apps/pramana/lib/mix/tasks/pramana.glossary.anchor.ex) | Resolves glossary citations to URNs this corpus can open |
| [`mix pramana.glossary.dila`](../apps/pramana/lib/mix/tasks/pramana.glossary.dila.ex) | Imports DILA's TEI glossaries — Soothill-Hodous, Karashima, Mahāvyutpatti |
| [`mix pramana.glossary.import`](../apps/pramana/lib/mix/tasks/pramana.glossary.import.ex) | Imports a markdown glossary as pinned term renderings |
| [`mix pramana.integrity`](../apps/pramana/lib/mix/tasks/pramana.integrity.ex) | Corpus-wide fidelity check: nothing printed in raw/ is missing from the bake |
| [`mix pramana.kangyur.catalogue`](../apps/pramana/lib/mix/tasks/pramana.kangyur.catalogue.ex) | Titles the Kangyur from 84000's catalogue, and links it to BDRC |
| [`mix pramana.kangyur.glossary`](../apps/pramana/lib/mix/tasks/pramana.kangyur.glossary.ex) | Ingests 84000's per-translation glossaries as Skt–Tib–En term anchors |
| [`mix pramana.kangyur.translations`](../apps/pramana/lib/mix/tasks/pramana.kangyur.translations.ex) | Ingests 84000's English translations as renderings of the Derge Kangyur |
| [`mix pramana.local.add`](../apps/pramana/lib/mix/tasks/pramana.local.add.ex) | Hashes, bakes and loads a local source directory into the corpus |
| [`mix pramana.local.validate`](../apps/pramana/lib/mix/tasks/pramana.local.validate.ex) | Checks a local source directory. Writes nothing. |
| [`mix pramana.parallels.import`](../apps/pramana/lib/mix/tasks/pramana.parallels.import.ex) | Fetches and imports SuttaCentral's curated cross-tradition parallels |
| [`mix pramana.provenance`](../apps/pramana/lib/mix/tasks/pramana.provenance.ex) | Populates provenance axes from the Taishō division table |
| [`mix pramana.public.bake`](../apps/pramana/lib/mix/tasks/pramana.public.bake.ex) | Bakes the redistributable-only corpus into a separate database |
| [`mix pramana.public.check`](../apps/pramana/lib/mix/tasks/pramana.public.check.ex) | Says whether this database is safe to expose publicly |
| [`mix pramana.quotations.scan`](../apps/pramana/lib/mix/tasks/pramana.quotations.scan.ex) | Finds verbatim text reuse across works and stores the quotation graph |
| [`mix pramana.readings.build`](../apps/pramana/lib/mix/tasks/pramana.readings.build.ex) | Derives the reading dictionary from Unihan and CC-CEDICT |
| [`mix pramana.readings.check`](../apps/pramana/lib/mix/tasks/pramana.readings.check.ex) | Scores the reading layer against the Buddhist test set |
| [`mix pramana.readings.import`](../apps/pramana/lib/mix/tasks/pramana.readings.import.ex) | Loads the built reading dictionary into the database |
| [`mix pramana.readings.seed`](../apps/pramana/lib/mix/tasks/pramana.readings.seed.ex) | Seeds the reading-exception layer from the glossary |
| [`mix pramana.recall`](../apps/pramana/lib/mix/tasks/pramana.recall.ex) | Measures retrieval against the corpus's own verbatim quotations |
| [`mix pramana.relations.derive`](../apps/pramana/lib/mix/tasks/pramana.relations.derive.ex) | Derives commentary→root relations from work titles |
| [`mix pramana.relations.parallels`](../apps/pramana/lib/mix/tasks/pramana.relations.parallels.ex) | Derives work-level parallel_of from curated passage parallels |
| [`mix pramana.relations.shared_text`](../apps/pramana/lib/mix/tasks/pramana.relations.shared_text.ex) | Links Chinese commentaries to their roots through the quotation graph |
| [`mix pramana.release.stamp`](../apps/pramana/lib/mix/tasks/pramana.release.stamp.ex) | Records what the retrieval state currently is, for stamping on answers |
| [`mix pramana.sat.metadata`](../apps/pramana/lib/mix/tasks/pramana.sat.metadata.ex) | Fetches IIIF metadata for the Taishō 56–84 works this corpus cannot show |
| [`mix pramana.sc.chinese`](../apps/pramana/lib/mix/tasks/pramana.sc.chinese.ex) | Ingests bilara-data's English of the Chinese Āgamas as renderings of CBETA |
| [`mix pramana.sc.ingest`](../apps/pramana/lib/mix/tasks/pramana.sc.ingest.ex) | Ingests SuttaCentral bilara-data Pāli root text |
| [`mix pramana.sc.translations`](../apps/pramana/lib/mix/tasks/pramana.sc.translations.ex) | Ingests bilara-data translations into the translation pool |
| [`mix pramana.tengyur.titles`](../apps/pramana/lib/mix/tasks/pramana.tengyur.titles.ex) | Reads Tengyur work titles out of the works themselves |
| [`mix pramana.texts.count_chars`](../apps/pramana/lib/mix/tasks/pramana.texts.count_chars.ex) | Backfills texts.char_count for rows baked before the column existed |
| [`mix pramana.tibetan.pairs`](../apps/pramana/lib/mix/tasks/pramana.tibetan.pairs.ex) | Exports aligned Tibetan-English pairs for embedder fine-tuning |
| [`mix pramana.translate.bakeoff`](../apps/pramana/lib/mix/tasks/pramana.translate.bakeoff.ex) | Builds a blinded side-by-side sheet for ranking translations |
| [`mix pramana.translate.export`](../apps/pramana/lib/mix/tasks/pramana.translate.export.ex) | Exports passages for generation on a rented GPU |
| [`mix pramana.translate.import`](../apps/pramana/lib/mix/tasks/pramana.translate.import.ex) | Stores generated renderings as tier-1 translations |
| [`mix pramana.vectors`](../apps/pramana/lib/mix/tasks/pramana.vectors.ex) | Creates the chunk vector rows that a run of pramana.embed will fill |
| [`mix pramana.verify`](../apps/pramana/lib/mix/tasks/pramana.verify.ex) | Re-resolves baked segments and byte-compares them against raw/ |
| [`mix pramana.witnesses.import`](../apps/pramana/lib/mix/tasks/pramana.witnesses.import.ex) | Records each text's witness sigla from its own pinned TEI header |
| [`mix pramana.mcp.stdio`](../apps/pramana_web/lib/mix/tasks/pramana.mcp.stdio.ex) | Runs the Pramāṇa MCP server over stdio |

This table establishes discoverability, not successful execution. [Testing](TESTING.md)
separates source-only checks from corpus and provider acceptance.
