# FR-07 v7 renewed local correctness review — FAIL

Reviewed 2026-09-19 (Hawaii). This is a bounded recheck of the six data-integrity findings
in the v6 review and necessary correction regressions. B3–B6 are corrected in the inspected
and executed cases. B1 and B2 remain incomplete: the shared reader can still use missing
projection state or an invalid owning command result to commit a new decision.

## Exact candidate

- Revision: `c75bb340a4e94c8969df201b6d98cc0f35d56831`.
- Tree: `e15eaca44f7e744496654efb3424603e86bb79cd`.
- Implementation: `ca3445bcbd34833f1ece0c624e59c8a05ae71cbf`;
  implementation tree `ededaf9951cfb2ad5d353f1dd6089b0eb6490b6f`.
- Checkout: `/Users/raymondluong/dev/pramana-fr07-worktree`.
- Independently verified all **50 candidate manifest entries**, without mismatches.
- `candidate-v7.md` SHA256:
  `15eddb1b3d531f7cc109ca0de6d8a0af8f78b7949bed785ecba0c3463e9c974f`.
- `review-v6.md` SHA256:
  `7151d544e1d64e757d75f33428e361d668c84356631b09fed1d3daeda491f35f`;
  matches the original `/tmp/fr07-v6-recovered-review.md`.
- `review-response-v6.md` SHA256:
  `a8fe0475b04d74eafdf96c0b9ce986b9de71f22de4b87c6aa9e88db49ccf8ad4`.
- The implementation-to-freeze difference is only the candidate document.
- Final HEAD/tree/status and all 50 hashes remained unchanged; the worktree is clean.

No repository files, references, live runtime or provider state were modified. Source review
was restricted to these corrections and their associated tests/contracts. All executed
database mutations below were disposable local test fixtures. No network work was performed.

## Remaining blockers

Paths are relative to `foundry/`. These are executed data-integrity reproductions, not
inferred failures from test counts.

### V7-R1 — Missing projection rows still satisfy an absent precondition (v6 B1)

`lib/pramana_foundry/durable_store/authority.ex:850` now validates a present projection
against its complete indexed carrier chain. But the empty-row branch at lines 858–859
still immediately returns `{:ok, :absent}` without checking whether retained events require
that projection.

Executed trace:

1. Commit A, creating `ticket-A` revision 0 and its projection carrier.
2. Delete only the projection row. Input, command, result and carrier remain intact.
3. The scoped projection read returns `{:ok, :absent}`.
4. Submit eventless B with the expected projection revision set to `"absent"`.
5. B commits and the gateway remains ready. A full authority read reports projection
   reconstruction corruption on the same database.

The caller's precondition concerns exactly the damaged entity; this is not an unrelated
out-of-band row that a scoped read reasonably has not encountered. Directly reading A
would detect its missing required projection, but a dependency lookup bypasses that check.

Required: for completed projection/dependency reads, distinguish a genuinely new entity
from a missing required projection using the new entity index. A retained carrier makes
absence corruption. Preserve the explicit internal pre-materialization case needed by a
new transaction; do not extend that exception to completed dependency reads. Assert a
typed corruption error, recovery fencing and no B rows for the trace above.

### V7-R2 — Owner-result semantics remain weaker in dependencies; one retained error raises (v6 B2)

`authority.ex:768` centralizes command/input/result presence and byte/column bindings, but
`read_command_owner/2` returns after decoding the result at line 813. The sequence and
command/event/effect checks remain separately in `valid_scoped_result?/4:820` and are
applied by a direct command read, not by projection/ledger owner traversal.

Executed in two separate valid protected stores:

1. Commit protected A with one event, projection, intent, claim, generation and reservation.
2. Change A's result to a canonically encoded accepted result with `committed_seq=999`,
   and update its SQL committed-sequence column to the same value. No event is removed.
3. Submit eventless B depending on A's projection revision 0; it commits and remains ready.
4. Repeat with B depending on A's ledger revision 0; it also commits and remains ready.
5. Each store's global reader reports
   `{:authority_corrupt, "command_results", "A", :invalid_sequence_or_disposition}`.

The related owner is now visited, but its result is still validated less completely than
at the other authority boundaries. The concrete absent-result case is repaired; a present
result with an impossible watermark remains usable for the same decision.

A second executed retained-result case shows incomplete error handling in this correction:
change A's result consistently to rejected, with a nonempty reason, while its effect remains.
`Authority.read(conn, {:revision, {:ledger, "generation-A"}})` raises `WithClauseError`.
The accepted-owner match at `authority.ex:1157` receives `{:ok, rejected_owner}`, and the
`else` at lines 1165–1168 does not handle that shape. Through `Gateway.transact`, transaction
rescue converts it to `{:storage_unavailable, {:exception, %WithClauseError{}}}` and fences.
This companion trace does not commit B, but violates the shared typed retained-corruption
contract; the standalone checked reader is not total over this supported corruption case.

Required: share the required owner-result/event/effect semantics as well as decoding, with
bounded traversal that avoids recursive owner/projection cycles. Apply valid historic
eventless watermark rules already specified in diagnosis-v6. Return typed corruption for
rejected/blocked owners retaining effects, rather than raising or reporting a storage
exception. Add both dependency families to the sequence-bound test, not only direct reads.

## Disposition of all six prior findings

| Prior finding | Renewed result |
|---|---|
| B1 current projection | Exact historical-row rewind is rejected by final indexed reconstruction. Missing-row dependency case remains V7-R1. |
| B2 owner/result/effect/FK relations | Missing owner results and orphan effect/FK source backup cases are corrected; backup destination stays absent. Present owner-result semantics remain V7-R2. |
| B3 malformed inputs | Struct read sets, malformed revision keys, invalid UTF-8 epochs/identities and invalid lookup IDs are rejected without crashing/fencing in the associated tests. Existing-ID ordering is preserved. The retained-error exception above is a B2 case, not a recurrence of malformed ingress. |
| B4 import staging | Exclusive creation is used; preexisting mismatched bytes are preserved/refused, and matching digest-verified staging is adopted. Cleanup is limited to a current-operation identity. Associated interruption/rerun tests pass. |
| B5 SQLite schema contract | Validation derives its reference from initialization DDL and compares schema SQL plus table/index/FK attributes. Wrong-column/nonunique index, wrong partial predicate and missing-FK table cases reject before backup publication. |
| B6 scoped scan | The ordered partial entity index is used; only relevant carriers are streamed through the shared reducer, with relevant owner IDs collected. The query-plan and unrelated-malformed-event tests pass. No scale or latency measurement is claimed. |

The shared live/replay reducer remains wired through `RecordCodec.apply_projection`,
including explicit intermediate materialization checks and final touched validation.
The internal intermediate scopes are not present in the Gateway caller protocol.
The current store schema still has 18 tables; new event carrier columns and their index
are included in validation and backup. No additional blocker was found in B3–B6 within
this bounded renewed review.

## Executed verification

Fresh build/runtime root: `/private/tmp/fr07-v7-review.hqKW0k`.
Pinned Elixir 1.20.3 / OTP 29.0.5 through `mise exec --`; `MIX_ENV=test`,
`MIX_BUILD_PATH=/private/tmp/fr07-v7-review.hqKW0k/build`,
`TMPDIR=/private/tmp/fr07-v7-review.hqKW0k`, `COORDINATOR_TICK=0`; external HERDR and
runtime-root environment variables removed. Existing fetched dependency sources were
reused; this is a fresh build, not a fresh network dependency audit.

- `mix compile --force --warnings-as-errors`: exit 0; 90 project files.
- `mix test test/pramana_foundry/durable_store test/pramana_foundry/legacy_persistence_containment_test.exs test/pramana_foundry/effects/checkpoint_test.exs --seed 9181`:
  exit 0; **88 passed**. This includes the complete 75-test durable-store suite.
- `mix test --seed 9182`: exit 0; **508 passed**. The candidate's recorded missing-tiktoken
  benchmark failure did not reproduce in this reviewer environment. No dependency was
  installed or changed to obtain this result.
- Durable module/test/support and Mix-file format check: exit 0.
- Independent `renewed_probes.exs`: exit 0, three characterization tests reproduced the
  two remaining blockers and the retained-owner exception. Their green characterization
  assertions are evidence of the defects, not acceptance passes.
- Independent `sync_probes.exs`: exit 0, the complete preserved oracle/recovery test passed.
- `git diff --check 103ee1de234af8929d504e78c51297b6d9907d71 HEAD`: exit 2 for the candidate's
  extra EOF blank line and review-response date trailing whitespace; these are documentation
  formatting suggestions, separate from correctness blockers.

## Preserved full-bundle recovery evidence

The prior independent fixture was rerun against this exact v7 build. It independently
enumerates actual SQL tables, constructs successful A/CONTROL/B protected transaction rows
in a separate oracle, compares every row in all 18 tables and checks reconstructed state.
The engine remains SQLite 3.53.4; loaded NIF SHA256 is
`7b855b28389db2fd16f250184060231c2ae337bd73ee455e625212fac303de95`.

Both actual connection-scoped WAL xSync scenarios observed WAL/FULL/FK enabled, an
unrelated connection succeeding while the target was armed, 52 successful target writes,
write order 52 followed by sync order 53, flags 2, returned SQLite code 1034, COMMIT error,
no success acknowledgment and refusal of a subsequent protected mutation.

- Ordinary close: ready reopen exactly matched prior A/CONTROL with B absent. Same-ID B
  then committed and every table matched the complete oracle.
- Hard child exit 75: unproved reopen refused ambiguous ownership; explicit observed-exit
  recovery retained complete A/CONTROL/B. Same-ID B with obsolete empty proposal/facts
  returned its original result idempotently, with exact unchanged rows.

Both branches then passed a malformed-obsolete retry, independent backup reopen, exact
all-table comparison and three-projection reconstruction comparison. The shared final
row-map digest is `c42a3972dce24a1eae549f9b1c2276969b8b2466a4066a284256a0551603c2d9`.
These are observed absent and complete branches, not merely conditional allowances.
This preserves the bounded SQLite VFS error/recovery evidence; it makes no physical
fsync, power-loss or media-durability claim.

## Evidence and limits

Temporary review scripts remain under `/private/tmp/fr07-v7-review.hqKW0k/`:

| File | SHA256 |
|---|---|
| helpers.exs | `bf1943c991c886371392fc53e2b984319105fb2b01afebe8c662b6a7f7940f43` |
| renewed_probes.exs | `475b576f562d96726722c21fc28d1977485c8f2b0544f6ca6ed02854accc2652` |
| sync_child.exs | `a08460d3be91920a6c62f2aa66aea3948fd928eea594d1cdbabcc230c025e6ca` |
| sync_probes.exs | `d19505385f11d5485eb53abc4a5c4b232fab699765853b80cebac2e6904ee61d` |

`renewed_probes.exs` evaluates the preserved v6 helper with its temporary root replaced;
the replacement's exact bytes are also retained as the v7 helpers file above.

Suggestions: remove the two new documentation whitespace defects, and retain the independent
full-row recovery oracle as owned executable support. Neither suggestion changes the
verdict. FR-08, FR-15a, FR-17, FR-19 and FR-22 remain deferred as before; this review asks
for no additional downstream capability. The two remaining blockers are local completeness
of the already-required retained-authority reader.

FR-07 is not ready for acceptance. Correct V7-R1/V7-R2 without weakening the credited
indexed scan, shared reducer, typed ingress, staging or schema checks, then freeze the
corrected revision for a bounded renewed check.
