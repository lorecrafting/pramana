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
`release_id` and `replay: {tool, arguments}` to both successful and error JSON replies
through one shared helper. Both identity keys are present even when their values are
null: no recorded bake means `bake_id: null`, and no recorded release means
`release_id: null`. Errors retain their MCP error flag, reason and message.

These are read-only lookups. A reply does not create or refresh a release stamp;
`release_id` remains the most recently recorded stamp even when tracked source or
derived facts have changed. `Pramana.Release.drift/0` reports those differences.
The lookups do not provide a transactional snapshot of the preceding tool execution.

Source identity does not freeze all derived data. Current v2 retrieval stamps hash
stored translation content and vector-row content including embedding bytes; historical
coarse stamps remain unchanged. A replay records supplied non-null arguments rather
than every resolved default, and a stamp is not a historical database snapshot.
[Architecture](ARCHITECTURE.md#identity-and-replay) explains why rerunning is not a
promise of the identical answer after code, defaults or data have changed.

## Replay argument contract

Both `verify_report` and the reader's `/check` use
[ReplayExecutor](../apps/pramana_web/lib/pramana_web/mcp/replay_executor.ex). Before
invoking an allowlisted tool, it checks argument names against that component's schema
and applies its generated `mcp_schema/1` validator. A misspelled or unsupported filter
must not be silently removed and then yield a pass for an unfiltered query. Knowing an
atom with that name does not make the argument valid for this tool.

Invalid arguments return `{:invalid_arguments, reason}` from the executor. The report
retains the original record and marks that replay `error`; the overall report is
`incomplete` unless separate evidence genuinely fails. No assertion in the refused
replay is compared, and no callback for that replay runs. The outer report check may
still resolve citations/read identities and check other valid replays.

| Reason | Meaning / operator action |
|---|---|
| `unknown_field` | A top-level argument is not declared by this tool, or its key is not a name. Check the original invocation against the discovered tool schema. |
| `schema_mismatch` | A required value is missing or a supplied value violates the declared schema. Check JSON types; `false` is not the string `"false"`, and `20` is not `"20"`. |
| `duplicate_field` | An in-process map supplied both atom and string forms of a field. Supply one unambiguous key. |
| `expected_object` | An in-process caller did not supply a plain argument map. JSON replay parsing already requires an object. |

Valid string-key and atom-key calls remain supported. Optional nulls, booleans, lists,
defaults and tool-specific caps keep the component's existing semantics. This enforces
**declared** constraints, not values mentioned only in prose descriptions, a new
retrieval policy, or lossless JSON parsing. Validator error values are not echoed.
The tool allowlist and recursion prohibition remain unchanged.

**Do not delete an unsupported filter merely to make a report green.** Recover the
original supported invocation/receipt or label the claim as needing a fresh check.
Older reports that relied on ignored fields or wrongly typed values are intentionally
refused; legacy bake-only identities remain supported under their existing limitations.
There is no migration or rewrite of reports, corpus rows, stamps or defaults. Rolling
back this application change reintroduces permissive replay argument handling; it does
not restore historical data or make earlier results trustworthy.

## Verification limits

The citation guard checks byte-substring containment after trimming a recognized
quotation. Other detected citations can receive existence-only checks; free-form
parsing does not recognize every possible citation/quotation layout. Read the
verified-quote, existence-only and refusal counts. An `ok?` result with zero checked
citations does not verify an uncited report.

`verify_report` checks supported declared replay blocks, not every factual sentence
in prose. Its domain default caps replay processing at 25 and reports skipped items.
Copy **both** `bake_id` and `release_id` from the original tool reply into its
`pramana-replay` block alongside `tool`, `arguments` and `assert`. Do not replace a
historical id with today's stamp to make a report pass.

A different or unavailable named bake/release makes a replay `unverifiable` before it
executes. For a release-bound replay, the returned tool receipt must also contain matching
recorded identities before any assertion is compared. `checked_identity` records what the
verifier read at entry, separately from the outer reply's metadata. Missing, null or
malformed returned identity cannot establish the recorded release.

Older records omitting `release_id` (or using null) keep their existing behavior, with
`identity_scope: source_bake_only` or `unrecorded` and a limitation note; they check current
values, not historical retrieval equivalence. Historical nonempty release ids are opaque,
not upgraded to v2. An invalid non-null recorded release makes the block malformed.
A matching identity still does not address all the state limitations above. Inspect the
[report implementation](../apps/pramana/lib/pramana/report.ex).

A failure to find wording in the loaded corpus is not proof of fabrication. A genuine
quotation is not proof of the attached interpretation. Generated text is not canonical
source evidence; [the invariants](INVARIANTS.md) make these distinctions explicit.

<a id="report-execution-budget"></a>
## Report-check admission and execution

`verify_report` gives verification and repair one shared monotonic **25-second**
execution budget, starting when the component is invoked. Trusted application
configuration may shorten it:

```elixir
config :pramana_web, PramanaWeb.MCP.Tools.VerifyReport, timeout_ms: 15_000
```

The value must be an integer from 1 through 25,000. Unknown options and invalid
configuration fail explicitly before report work; a report or MCP argument cannot
increase or disable the budget. The reader's existing 60-second policy is unchanged.
These are resource policies, not measured corpus-speed or correctness thresholds.

Before a report worker starts, the reader and MCP `verify_report` share one node-local
admission pool. Its default capacity is four active checks; trusted configuration may
set `PramanaWeb.CheckAdmission` `max_active` from 1 through 64. Client input cannot
change that limit. A full pool refuses immediately rather than queueing another report
worker. MCP returns `report_check_busy`; the reader shows a `busy` execution state. In
both cases verification and repair do not start and no report verdict is invented. See
[report-check admission](REPORT_CHECK_ADMISSION.md) for permit lifecycle, recovery and
rollback semantics.

The admission server may restart without losing active capacity because live permit
processes outlive it. The permit-supervisor generation is different: if it fails,
in-flight `CheckRun` coordinators observe permit loss and stop their owned workers, while
new admission remains unavailable for that application lifetime. Recovery is a
coordinated application restart, not automatic adoption of a fresh zero-count pool.

Completed verification keeps its existing `status`, `ok?`, counts, identity receipts
and refusal semantics. Successful completion adds `execution: "completed"` and the
normal repair object. If only repair fails, times out or is cancelled, the completed
verification is still returned, with `execution` equal to `error`, `timed_out` or
`cancelled`, `repair: null`, and an explicit note. A genuine failed assertion cannot
be hidden by a later repair failure. An evidence verdict and an execution outcome
answer different questions.

If verification does not finish, the MCP result is an error with reason
`report_check_busy`, `report_check_timed_out`, `report_check_failed` or
`report_check_cancelled`; it has no invented report `status` or `ok?`. Existing error
provenance/replay fields remain. Inspect the MCP error flag first, then `execution` and
the evidence fields when present. Do not retry automatically or relabel an interrupted
check as a refutation.

The shared [check coordinator](../apps/pramana_web/lib/pramana_web/check_run.ex)
observes its worker's termination before returning and releases admission only after that
cleanup. It cooperates with Anubis's existing cancellation and session teardown; explicit
protocol cancellation may return Anubis's cancellation error instead of a completed tool
payload. MCP calls emit no reader progress messages. This is not a second dispatcher or
persistent job.

The HTTP transport's 30-second response wait is distinct: it includes time queued
in the session. The component budget does not bound that queue, JSON encoding,
provenance lookups after execution, network delivery or another tool's execution.
The shared admission pool bounds **report checks on one BEAM node only**; it does not
bound other MCP tools, session queues, another node or end-to-end latency. Killing a
BEAM worker cannot guarantee recall of already-dispatched database/native/model work.
These limits also apply to stdio; `mix pramana.mcp.stdio` starts the `pramana_web`
application before the stdio transport, so it uses the same node-local admission service.
Transport disconnect is not a new cancellation promise. No database writes, migrations,
automatic retries or historical replay snapshots are introduced. Rollback removes the
shared report capacity boundary and returns to per-call deadline protection; it does not
restore stored data.

## Resources and transports

The registered resources describe the corpus guide and inventory. Resource capability
advertisement and registration must both exist; inspect `server.ex` for current names.

Stdio uses [bin/pramana-mcp](../bin/pramana-mcp) and the checked-in
[.mcp.json](../.mcp.json) client example. The wrapper keeps build output off protocol
stdout. Other clients/harnesses need their own supported configuration; provider choice
alone does not imply that `.mcp.json` is automatically loaded.

Streamable HTTP is routed at `/mcp`. The LiveView reader calls core domain functions;
it is not a client of that HTTP endpoint. External edition URLs are convenience
links with their own verification metadata, not replacements for stored citation
addresses or proof that a third-party page remains available.

[Reader](READER.md) · [Testing](TESTING.md) · [Historical interface notes](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/mcp-interface-notes.md)

## Historical section bookmarks

These bookmarks open the retained pre-cleanup revision in Git history, not current instructions.
See [retired files](RETIRED_FILES.md) for recovery and offline-access limits.

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
