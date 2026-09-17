# Evidence-integrity behavior

[Pramāṇa index](README.md) · [MCP](MCP.md) · [Reader](READER.md) · [Testing](../../docs/TESTING.md)

This change follows the merged behavior-first test cleanup. It changes production
semantics; it does not reopen Foundry repair or certify the live corpus.

## Occurrence-safe repair

`Pramana.Repair.repair/2` returns `original`, amended `text`, `actions`, `edits`,
`counts`, and `repaired?`. Every edit has a half-open UTF-8 byte range in the original
input, exact `before` bytes, replacement `after` bytes, and the citation occurrence's
`source_offset`. Edits retain original coordinates and assemble in one output pass; repeated addresses are separate occurrences.
Only the affected quotation or citation wrapper changes. Unrelated prose and whitespace
remain byte-identical. Nothing writes to source data or the caller's saved document.

Punctuation/glyph repair requires nonempty substantive text and one uniquely aligned
source subspan. Partial quotations cannot expand to the whole passage. Repeated or
overlapping alignments are flagged; whole-span equivalence may retain its surrounding
editorial marks, but may not add substantive words. An unpaired citation wrapper is
flagged rather than partially deleted.

Multiple candidate addresses, overlapping edits, unavailable diagnosis and candidates
that fail exact quotation verification are flagged without changing that occurrence.
An edit inside another citation's quotation is also refused, even when that outer
quotation already verifies and needs no edit of its own. Before returning a deletion,
repair assembles the proposed output once and reparses its citation associations. Original
citation/quotation offsets are mapped through the edit plan with one cumulative sweep; if
a deletion would attach that deleted citation's quotation to another surviving citation,
the deletion is refused as `citation_rebinding`. This protects semantic association even
when the byte ranges themselves do not overlap, without restoring per-occurrence rescans.
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
foreign citations, and repair never edits it. The parser retains separate original-byte
prose regions. Every quotation association, wrapper and edit stays inside one region;
no match can cross a replay fence. Malformed/unterminated fences remain protected.
Compared quotation bytes come from the actual document, never substituted whitespace.

The domain verifier, repairer, MCP tool and reader share the existing **200,000-byte**
input resource limit. Oversize/invalid UTF-8 domain input returns an explicit refusal;
verification is incomplete and repair leaves it unchanged. No evidence is silently
truncated into a pass. The reader retains its preflight size message. This is not a
transport frame-size limit or a complete denial-of-service defense: individual replay
queries still have their own cost and the corpus is not copied into the checker.

`foreign` contains every foreign-looking occurrence found in original prose, with its
original-input offsets. Foreign-looking bytes inside literal quotation bodies are never
canonicalized before quotation verification. After rewriting, report verification maps
those original offsets through the actual rewrite edits and compares them with the Guard's
exact checked quotation ranges. A protected occurrence covered by such a range is literal
source content, not independent foreign evidence, regardless of whether that inner-looking
address itself resolves. An uncovered protected address that resolves is counted as
`unchecked_foreign`; an uncovered address that does not resolve is `unresolved_foreign`.
Either count makes a mixed report `incomplete`, so quotation marks alone cannot make
recognized evidence disappear from the verdict. Foreign citations outside quotation bodies
still rewrite normally, including an outer foreign citation attached to a literal quotation.
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

The new `release_selection` singleton references an immutable release row. Upgrade
backfills the latest legacy stamp, with a deterministic row-ID tie-breaker. Empty
history stays unstamped. This changes selection only, not source bytes or history.

### Writer ordering and its limits

Updated `Release.stamp/0` obtains a **transaction-scoped PostgreSQL advisory lock before
sampling any facts**, and holds it through selection/commit (or outer transaction end
when nested). Concurrent updated stampers therefore cannot sample first and then race
to select an older observation. Plain readers do not take this writer lock. Rollback
releases the lock and rolls back both the history insert and selection update.

This is a cooperative **stamp-writer** lock, not a lock on all corpus mutations or an
immutable retrieval snapshot. Keep source/import/vector writers quiescent when a stable
cutover observation is required. Use the normal Read Committed transaction policy;
a caller must not wrap stamping in an older Repeatable Read snapshot and expect it to
observe facts committed while it waited. No automatic higher-isolation retry is added.
Legacy code does not take this lock or maintain the selection table. **Mixed-version
stamp writers are unsupported.** A successful migration alone does not drain them.

### Upgrade / cutover

1. Identify the intended database and application revision. Take the normal operator
   backup and verify its recovery procedure. Record the last selected/legacy release,
   source bake, and tracked drift before making changes. These tests are not a backup.
2. **Pause and drain all legacy stamp writers before migration**: old CLI sessions,
   scheduled stamp/import tasks, and any processes that can call the old release code.
   Keep them stopped through cutover. Quiesce source/derived-data writers as well when
   comparing a stable before/after state. This is a coordinated cutover, not a supported
   rolling deployment with old and new writers running together.
3. Apply the reviewed `20260916060759_select_current_release.exs` migration through the
   normal Ecto migration process against that database, before starting updated readers.
   Inspect the migration list rather than assuming this is the newest migration forever.
4. Confirm the selection is the expected last legacy release and the history rows are
   unchanged. With empty history, confirm there is no selection. Useful read-only checks:

   ```sql
   SELECT current_database(), current_schema();
   SELECT id, release_id, source_bake_id, stamped_at
   FROM releases ORDER BY stamped_at DESC, id DESC LIMIT 1;
   SELECT s.id, s.selected_at, r.release_id, r.source_bake_id, r.stamped_at
   FROM release_selection s JOIN releases r ON r.id = s.release_id;
   ```

5. Start only the updated code, verify the selected identity and tracked drift with the
   existing release/doctor checks, and check both success and error response envelopes.
   **Do not automatically restamp to hide unexpected drift**. Investigate first; stamp
   only when selecting the observed state is the operator's intended action. Resume only
   updated writers after acceptance.

For the application-only v2 content-identity upgrade, there is no additional schema
migration: an existing unprefixed selected release intentionally reports
`identity_version` drift. Investigate any other drift, keep data writers quiescent, then
run `mix pramana.release.stamp` only when the live state is the intended selection. That
creates/selects a v2 row and leaves every v1 history row unchanged.

A late legacy writer can insert B into history after the one-time backfill selected A,
without updating the selection. The writer fence prevents that unsupported transition;
the advisory lock cannot constrain old code that never acquires it.

### Rollback / re-upgrade

1. Stop updated readers and **all** stamp/data writers, drain in-flight transactions,
   and record the current selected identity, history and drift. Code requiring the
   selection table must not be running when that table is dropped.
2. Inspect intervening migrations and perform the reviewed Ecto rollback of this
   migration. Its `down/0` drops **only `release_selection`**; release history remains.
   Do not blindly roll back the newest migration or reset the database.
3. Start the chosen older revision only after schema acceptance. Older code selects by
   the original stamp timestamp. The first v2 stamp creates a new v2 history row with a
   fresh timestamp, so a rollback can select that cutover row. After later **A → B → A**
   within v2, however, reselecting A still reuses A's original timestamp and older code can
   select **B** instead. Check and report the selected row before resuming service. This
   migration cannot promise selection continuity across old code. Restoring a backup has
   its own operator-approved recovery procedure; dropping this table is not one.
4. For re-upgrade, drain the old writers again and repeat the cutover. The new backfill
   again uses legacy timestamp order, not the previously deleted selection pointer.
   Verify identity/drift, then explicitly select an intended state only after review.

A → B → A under updated code reuses A's identity/timestamp and selects it atomically.
Reads never create or refresh a selection; MCP success/error envelopes attach it. V2
component ids cover same-count rendering and vector-row changes, including stored vector
bytes; retrieval code/defaults and historical database snapshots remain outside the
fingerprint. Exact historical replay and global snapshot isolation are not promised.

PostgreSQL references: [transaction advisory locks](https://www.postgresql.org/docs/18/explicit-locking.html#ADVISORY-LOCKS)
and [Read Committed](https://www.postgresql.org/docs/18/transaction-iso.html#XACT-READ-COMMITTED).

## Validation boundary

Focused regression cases cover repeated/multibyte edits, unavailable searches, complete
and incomplete reports, missing/null assertions, partial holdings, wrong/ambiguous
volumes, A → B → A selection, and actual migration backfill SQL. The association
regressions cover deletion-induced quote rebinding, repeated addresses with multibyte
prefixes, literal SuttaCentral/Taishō address text, outer foreign citation rewriting,
resolved protected text with no attached citation, unresolved address-like source text
inside a checked quote, and cumulative offset shifts before later literal quotations.
Fresh database migrations, application tests, formatting and static analysis are checked
in CI. The dedicated `release_acceptance_test.exs` uses disposable empty schemas and a
separate four-connection pool to run actual history/selection migrations up/down/up. Its
controlled writer test observes distinct PostgreSQL backend IDs and a waiting advisory
lock before releasing the first stamper. It does not infer concurrency from a sleep or
shared Sandbox owner.

Boundary regressions exercise real domain, MCP and reader paths, including CRLF and
malformed fences. Pure interval checks compare against an independent all-pairs oracle.
For parser/overlap/output scaling without database or model work, run from `pramana/`:
`mix run --no-start bench/evidence_scaling.exs`. It reports warmed median timings rather
than imposing a fragile hardware-specific millisecond assertion. Corpus-scale
retrieval evaluation, production upgrade/deployment, and live-provider work require
separate operator acceptance and are not authorized or established by this change.
