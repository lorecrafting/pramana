# MCP interface

Read-only research tools over the Pramāṇa domain. Registration lives in
[server.ex](../apps/pramana_web/lib/pramana_web/mcp/server.ex); parameter schemas
live in the [tool modules](../apps/pramana_web/lib/pramana_web/mcp/tools).
Use discovery for exact schemas rather than treating prose examples as exhaustive.

## Tools

The registration/table correspondence is tested in both directions. Counts are not
repeated in prose because the registry is the owner.

| tool | for |
|---|---|
| `search` | Hybrid source retrieval by default, with provenance filters; semantic availability depends on the serving and indexed data. |
| `search_translations` | Search stored rendering text and return its source anchors, with translation attribution. |
| `survey_corpus` | Count matches across the supported scope rather than infer frequency from ranked top-k hits. |
| `get_passage` | Resolve a URN with optional context and separately labelled renderings. |
| `get_outline` | Read a work's structure. |
| `get_commentaries` | Inspect work-level commentary relationships and available alignment metadata. |
| `get_glosses` | Find accepted commentary alignments attached to a source line. |
| `get_commentary_outline` | Inspect the root locations addressed by an aligned commentary. |
| `compare_translators` | Inspect attested terminology correspondences in loaded glossary data. |
| `get_works_by_person` | Find works linked to an authority identity. |
| `get_person` | Read a linked authority record with its available dates and relationships. |
| `get_parallels` | Inspect curated parallels, including references whose other endpoint is not held. |
| `compare_versions` | Compare renderings and curated parallels without conflating those two relationships. |
| `compare_witnesses` | Inspect variant readings using the edition's witness identifiers. |
| `get_quotations` | Read recorded verbatim reuse; not a proof of direction of borrowing or exhaustive coverage. |
| `get_readings` | Render supported/populated pronunciation or transliteration information. |
| `define_from_canon` | Find passages matching the supported definitional patterns. |
| `verify_citation` | Check recognized quotation bytes or citation existence and report mismatch diagnostics. |
| `verify_report` | Check detected citations and supported declared replay assertions within the report's limits. |

## Search mode matters

An English question can use hybrid `search` when compatible semantic serving and
vectors are available. An English phrase intended to match an existing translation
belongs in `search_translations`. Lexical source-only fallback can be weak for an
English question; inspect `retrievers`, match/fallback mode and coverage rather than
assuming the requested semantic path ran. Similarity is not proof of relevance.

A role/date filter can omit works whose metadata is absent. That is not evidence
that those works do not fit the user's question. Corpus and index coverage are
separate: 100% embedding coverage over existing chunks can coexist with unchunked texts.

## Source and rendering separation

A passage's source text and translations are distinct fields. Rendering records
carry their anchor, rendering identity, translator/method and `citable_as_source: false`.
Do not attribute an English rendering to the original-language witness. A metadata
response such as a person record is not a source span and need not invent a passage URN.

Provenance buckets make origin and role visible, but do not independently certify
historical attribution. An unaligned commentary may paraphrase or lack accepted
alignment evidence; absence of an alignment does not refute the work-level relation.

## Honesty fields and replay

[Reply](../apps/pramana_web/lib/pramana_web/mcp/reply.ex) attaches `bake_id`,
`release_id` and `replay: {tool, arguments}` to successful JSON replies. The release
value can be null until stamped. Error JSON includes source identity and replay
arguments but currently does not include `release_id`.

Source identity does not freeze all derived data. The current release stamp hashes
counts and model/translator identities, not every vector/rendering byte, and the
replay records supplied non-null arguments rather than all resolved defaults.
[Architecture](ARCHITECTURE.md#identity-and-replay) explains why rerunning is not a
promise of the identical answer after code, defaults or data have changed.

## Verification limits

The citation guard checks byte-substring containment after trimming a recognized
quotation. Other detected citations can receive existence-only checks; free-form
parsing does not recognize every possible citation/quotation layout. Read the
verified-quote, existence-only and refusal counts. An `ok?` result with zero checked
citations does not verify an uncited report.

`verify_report` checks supported declared replay blocks, not every factual sentence
in prose. Its domain default caps replay processing at 25 and reports skipped items.
A different named source bake can make a replay unverifiable; a matching identity
does not address all the state limitations above. Inspect the [report implementation](../apps/pramana/lib/pramana/report.ex).

A failure to find wording in the loaded corpus is not proof of fabrication. A genuine
quotation is not proof of the attached interpretation. Generated text is not canonical
source evidence; [the invariants](INVARIANTS.md) make these distinctions explicit.

## Resources and transports

The registered resources describe the corpus guide and inventory. Resource capability
advertisement and registration must both exist; inspect `server.ex` for current names.

Stdio uses [bin/pramana-mcp](../bin/pramana-mcp) and the checked-in
[.mcp.json](../../.mcp.json) client example. The wrapper keeps build output off protocol
stdout. Other clients/harnesses need their own supported configuration; provider choice
alone does not imply that `.mcp.json` is automatically loaded.

Streamable HTTP is routed at `/mcp`. The LiveView reader calls core domain functions;
it is not a client of that HTTP endpoint. External edition URLs are convenience
links with their own verification metadata, not replacements for stored citation
addresses or proof that a third-party page remains available.

[Reader](READER.md) · [Testing](../../docs/TESTING.md) · [Historical interface notes](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/mcp-interface-notes.md)

## Historical section bookmarks

These bookmarks open the retained pre-cleanup revision in Git history, not current instructions.
See [retired files](../../docs/RETIRED_FILES.md) for recovery and offline-access limits.

| Earlier section |
|---|
| <a id="the-mcp-surface"></a>[The MCP Surface](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/mcp-interface-notes.md#the-mcp-surface) |
| <a id="an-english-question-needs-search_translations-not-search"></a>[An English question needs `search_translations`, not `search`](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/mcp-interface-notes.md#an-english-question-needs-search_translations-not-search) |
| <a id="translations-never-arrive-in-text"></a>[Translations never arrive in `text`](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/mcp-interface-notes.md#translations-never-arrive-in-text) |
| <a id="comparison-keeps-its-two-kinds-apart"></a>[Comparison keeps its two kinds apart](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/mcp-interface-notes.md#comparison-keeps-its-two-kinds-apart) |
| <a id="quotations-are-found-not-judged"></a>[Quotations are found, not judged](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/mcp-interface-notes.md#quotations-are-found-not-judged) |
| <a id="readings-say-where-each-one-came-from"></a>[Readings say where each one came from](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/mcp-interface-notes.md#readings-say-where-each-one-came-from) |
| <a id="variants-name-the-witness-and-the-witness-is-per-text"></a>[Variants name the witness, and the witness is per text](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/mcp-interface-notes.md#variants-name-the-witness-and-the-witness-is-per-text) |
| <a id="definitions-are-quoted-not-composed"></a>[Definitions are quoted, not composed](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/mcp-interface-notes.md#definitions-are-quoted-not-composed) |
| <a id="resources"></a>[Resources](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/mcp-interface-notes.md#resources) |
| <a id="honesty-fields"></a>[Honesty fields](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/mcp-interface-notes.md#honesty-fields) |
| <a id="errors"></a>[Errors](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/mcp-interface-notes.md#errors) |
| <a id="verifying-a-whole-report-not-just-a-quotation"></a>[Verifying a whole report, not just a quotation](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/mcp-interface-notes.md#verifying-a-whole-report-not-just-a-quotation) |
| <a id="reader-deep-links"></a>[Reader deep-links](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/mcp-interface-notes.md#reader-deep-links) |
| <a id="transports"></a>[Transports](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/mcp-interface-notes.md#transports) |
| <a id="semantic-search-is-opt-in"></a>[Semantic search is opt-in](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/mcp-interface-notes.md#semantic-search-is-opt-in) |
