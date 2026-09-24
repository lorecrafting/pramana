# Pramāṇa invariants

These are engineering constraints, not an assertion that every input, inference or
running deployment is correct. Foundry has separate execution contracts in
[its documentation](https://github.com/lorecrafting/pramana/blob/e1e4b3bf2c666f5d84652758afee446a0b21ebe1/foundry/docs/README.md). Stable numbers below preserve
existing references in code, reviews and older documents.

1. **No unattributed source text leaves the retrieval boundary.** Returned source
   spans must retain their edition address, content hash, offsets and provenance.
   Metadata-only responses are not source spans. Use the actual tool/schema fields;
   do not invent a universal envelope for people, inventory and translation records.
2. **Never invent citation IDs.** Preserve the source's supported citation grammar.
   Distinguish canonical, edition-page and derived addressing; not every digital
   anchor is a recoverable printed line. A syntactically valid URN is not proof that
   the work is loaded or that the address resolves.
3. **Treat `raw/` as append-only source evidence.** Do not patch acquired text in
   place. Correct the normalizer with a regression test and record reproducible
   inputs. Source identity is not a frozen retrieval index: see
   [identity and replay](ARCHITECTURE.md#identity-and-replay).
4. **Provenance is multi-axis.** Keep composition origin, role, attribution
   confidence, addressing and licensing separate. Structural buckets expose those
   distinctions; they cannot prove the metadata is correct or stop a reader from
   misinterpreting it.
5. **Deterministic before probabilistic.** Prefer curated or structural evidence
   when it answers the question. Label inferred alignments and generated text with
   their method and confidence. Character reuse alone does not establish which
   author quoted whom.
6. **Retrieval changes require evaluation.** Evaluate the actual candidate against
   the appropriate gold set, configurations and baseline. Report unavailable
   corpus/model prerequisites instead of treating model-free checks as retrieval evidence.
7. **The MCP surface is read-only. Tools read; the CLI writes.** Do not add corpus
   ingestion, mutation or provider execution to the research tool surface. Existing
   management commands require the operator's authorization and the intended database.
8. **Generated translation is not canonical source evidence.** Keep renderings
   anchored and explicitly attributed. The guard must not accept generated text as
   source. Human renderings are also translations, not the original-language witness.

## What citation verification establishes

[The guard implementation](../apps/pramana/lib/pramana/guard.ex) re-resolves
recognized citations. Quote checking uses byte-substring containment after trimming
the supplied quotation; it is not whole-passage equality. Some detected citations
receive an existence-only check. Inspect verified-quote, existence-only and refusal
counts; a response with zero checked citations is not a verified argument.

The guard does **not** prove interpretation, doctrinal correctness, exhaustive corpus
coverage, metadata truth, or the faithfulness of a translation. Absence from the
loaded corpus does not prove that a passage was fabricated.

See [MCP](MCP.md), [architecture](ARCHITECTURE.md) and
[testing](../../docs/TESTING.md) for current surfaces and verification limits.
