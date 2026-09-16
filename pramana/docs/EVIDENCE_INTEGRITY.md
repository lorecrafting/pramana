# Evidence-integrity behavior

[Pramāṇa index](README.md) · [MCP](MCP.md) · [Reader](READER.md) · [Testing](../../docs/TESTING.md)

This change follows the merged behavior-first test cleanup. It changes production
semantics; it does not reopen Foundry repair or certify the live corpus.

## Occurrence-safe repair

`Pramana.Repair.repair/2` returns `original`, amended `text`, `actions`, `edits`,
`counts`, and `repaired?`. Every edit has a half-open UTF-8 byte range in the original
input, exact `before` bytes, replacement `after` bytes, and the citation occurrence's
`source_offset`. Edits apply right-to-left; repeated addresses are separate occurrences.
Only the affected quotation or citation wrapper changes. Unrelated prose and whitespace
remain byte-identical. Nothing writes to source data or the caller's saved document.

Multiple candidate addresses, overlapping edits, unavailable diagnosis and candidates
that fail exact quotation verification are flagged without changing that occurrence.
An edit inside another citation's quotation is also refused, even when that outer
quotation already verifies and needs no edit of its own.
`no_sources` means the citation provides no verified support here; it does not assert
that the quotation was invented. Bare/blank quotations receive `existence_only`, not
`verified`. Repair still handles the recognized Pramāṇa citation grammar, not arbitrary
bibliographic references.

## Diagnosis is bounded evidence

The definite `quote_mismatch` verdict is separate from diagnostic search:

| Reason | Search status | Meaning |
|---|---|---|
| `wrong_address` | `matched` | The phrase search returned candidate addresses; repair verifies the exact pair before replacing one. |
| `not_found_in_search` | `no_match` | A completed phrase search found no match in its searched material. This does not establish fabrication or absence from all sources. |
| `search_unavailable` | `unavailable` | A diagnostic operation failed or returned an unusable result. No absence conclusion is made. |

These replace the former overconfident diagnostic `absent_from_corpus` outcome.
Callers branching on that reason must migrate. Other exact mismatch, provenance and
source-versus-generated-translation constraints remain unchanged.

## Report status contract

The domain result, MCP payload and reader share one overall status and summary:

| Status | Meaning |
|---|---|
| `verified` | At least one recognized quotation or asserted replay value verified, with no failed or incomplete evidence. |
| `failed` | A definite citation or replay assertion did not hold. Other unchecked evidence remains in the counts. |
| `incomplete` | Evidence remains unresolved, malformed, skipped, unavailable, existence-only or execution-only, without a definite failure. |
| `no_checkable_evidence` | No recognized evidence was available to check. This is not a pass. |

`ok?` is true only for `verified`. A replay without assertions is `executed`, not
`verified`. A recorded bake unavailable here is `unverifiable`, including when this
instance has no current bake. Interpretation and completeness are never established
by the status. Unsourced-figure detection remains a heuristic warning, not a verdict.

Replay `assert` must be a map with nonempty dotted paths. Missing paths differ from
explicit JSON null; false values are preserved. Invalid JSON, invalid assertions and
unterminated replay fences are reported, not dropped. At most 25 replays execute.
Replay JSON is treated as replay data, not scanned again as prose quotations or
foreign citations, and repair never edits it. Masking preserves byte offsets and
leaves the original JSON intact.

`foreign` contains each original citation occurrence and its original-input offsets.
Citation findings after foreign-address rewriting use `citations.offset_basis =
resolved_text`; their ranges refer to the returned `resolved_text`, not the original
string. Repair's ranges always refer to its returned `original`.
MCP foreign-resolution tuple reasons become `{code, details}` objects for JSON.

## Holdings and complete addresses

CBETA `works_held` is the actual distinct loaded work count. Per-collection
`works_loaded` is separate from catalogue `works_expected`; the compatibility field
`collections_held` means represented, not completely ingested. Uncatalogued loaded
collections are reported explicitly. A count below the catalogue is partial; matching
or exceeding the count is still unknown without validating expected work identities.
Representing every collection never suppresses the completeness caveat.

SAT/CBETA forms with a supplied volume enforce it. For volume-spanning texts, the
segment's volume metadata is authoritative. Shorter forms remain supported, but two
matching addresses return ambiguity. No first-row selection or guessed volume is used.
Repeated foreign references rewrite independently in their original occurrence order.

## Release-selection migration and rollback

Run the normal reviewed Ecto migrations against the intended database before starting
this version. The new `release_selection` singleton references the selected immutable
release row. Upgrade backfills the row the old timestamp-based reader would select,
with a deterministic row-ID tie-breaker. An empty release history stays unstamped.

Stamping a state and selecting its release happen in one transaction. A → B → A reuses
A's original identity/timestamp and selects it again. Reads never create or refresh a
selection. MCP success and error responses both attach that selected release.

Rollback drops only the selection table, retaining release history. Older code again
selects the latest original stamp timestamp; after A → B → A this can select B.
Coordinate rollback with the operator rather than promising selection continuity across
old code. This migration does not change source bytes, translation/vector identities,
or existing coverage thresholds. Same-count content edits and code/default changes
remain outside the coarse release fingerprint; exact historical replay is not promised.

## Validation boundary

Focused regression cases cover repeated/multibyte edits, unavailable searches, complete
and incomplete reports, missing/null assertions, partial holdings, wrong/ambiguous
volumes, A → B → A selection, and actual migration backfill SQL. Fresh database migrations,
application tests, formatting and static analysis are checked in CI. Corpus-scale
retrieval evaluation, production upgrade/deployment, and live-provider work require
separate operator acceptance and are not authorized or established by this change.
