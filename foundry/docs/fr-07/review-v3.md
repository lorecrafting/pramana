# FR-07 focused renewed review — v3

**FAIL — three implementation blockers remain, plus the separately unpassed FR-07
attributed sync-failure acceptance case.** Reviewed 2026-09-13. Most exact v2 defect
traces are corrected and the 49-test focused suite passes independently. The remaining
failures arise in the same admission/reconstruction and ownership invariants; this review
does not reopen the architecture or demand downstream lifecycle implementation.

## Exact boundary and provenance

- Base: `8aa0ebddbfb5fa834bbefa53d1f84b992e4c25bd`.
- Rejected v2: `b88918dd54094e657f8c6aae839878327c75e4d6`.
- V3 implementation: `5f3af472a3c59f2ad3dcbaae6d448145869ba9ca`.
- Implementation tree: `d7e6f4e40b64ce2f972b852414e865807af1cbf6`.
- Reviewed candidate: `f4a77de4ab3795716b00f807b4cd659e602654c4`.
- Reviewed tree: `8a38dcae936d536a71b55a1327836087fb51e4b9`.
- Worktree: `/private/tmp/pramana-fr07`.
- `candidate-v3.md`: SHA-256 `00400c9d445fd96287e5a6848362e3519cad75087f19dc16c235968856b9ff6a`.
- Preserved `review-v2.md`: SHA-256 `4dab766e7616e40630d2000499319f37ee8216851f5a73f25cf74f6a2c9e8ad4`.
- `review-response-v2.md`: SHA-256 `9e0e2be78603b2069961d8b363cd50715a0d58d53f48910ceaa8790f8ac92556`.
- `WORKFLOW-CONTRACT.md`: SHA-256 `5d1621ff98fcb1aad2d6d37ba523b2a00c6bf90120873ffeb2518f23fd831488`.
- `REPAIR-PLAN.md`: SHA-256 `8ecb2900160c7a8c7e711039251d2a7ced2eacc20a567ebc46a9d2865c872581`.

All **25** current manifest path hashes independently matched. The candidate document is
outside that manifest; its later commit is documented provenance. All implementation
diffs since v2, amended tests/fixtures, current response and candidate, and normative FR-07,
FR-19 and storage acceptance wording were read. The previous review supplies the unchanged
source/context boundary. HEAD/tree were rechecked after tests and had not moved. Only the
same five fetched dependency directories were untracked. No repository source/doc edits
were made by this reviewer.

## Blocking findings

### V3-R4 — P1: optional result field produces acknowledged, unreadable authority

`kernel.ex:34` allows `reason_code` to be omitted, but `gateway.ex:542` adds only
`committed_seq` before storing the result. The strict live/startup readers now require
exactly all four result keys, including `reason_code`.

**Executed, no SQL mutation:** remove only `:reason_code` from an otherwise valid result
in a candidate bundle. `Gateway.transact` returns `{:ok, result, :committed}`. Its first
`Gateway.command(id)` returns recovery/corrupt_result. Clean stop/reopen reports
`{:invalid_stored_body, "command_results", rowid, :result_binding_mismatch}`.

This is the v2 admission/reopen mismatch recurring with another schema-valid input.
**Correction:** use one shared result schema/normalization contract for admission,
persistence and retained reads; either normalize the explicitly optional field or reject
its absence before commit. Exercise omitted/null/present fields across commit, same-ID
retry, direct read and reopen. Do not solve only this example while retaining separately
maintained incompatible validators.

### V3-R7 — P1: projection-event validation is one-way and permits unreconstructable commits

`kernel.ex:134` verifies each proposed projection has its matching event, but never verifies
each event's reserved projection transition has a matching proposed projection. The new
backup reducer consumes every `payload.projection` regardless.

**Executed, no SQL mutation:** submit the normal supported event with its complete
`payload.projection`, but remove the corresponding projection row proposal and use an empty
read set. `Gateway.transact` returns committed acceptance. `Gateway.backup` then returns
`:projection_replay_mismatch` because replay creates a projection absent from live state.

The improved backup now detects this contradiction correctly; admission must prevent
acknowledging it. **Correction:** validate complete correspondence and ordering between
supported projection-changing events and all projection writes inside the transaction.
Cover extra/missing transitions, multiple events, duplicate entity transitions and event
order versus proposal order. Alternatively derive the supported writes from the one
transition representation and verify its expected revisions. Full domain semantics still
belong to FR-08; transactional live/reconstructed consistency for this implemented format
belongs here.

### V3-R6 — P1: lexical owner path differs from the database actually opened

`owner.ex:15` uses `Path.expand` before filesystem inspection/sidecar derivation, while
`Gateway.open` passes the original string to `Database.open`. Expansion collapses `..`
lexically; the OS traverses an earlier symlink before resolving `..`. The direct final-file
symlink and hardlink refusals pass but do not close this class.

**Executed setup and trace:**

```text
root/authority.sqlite3           initialized otherwise idle store
root/other/authority.sqlite3     initialized store with first gateway alive
root/other/child/                directory
root/link -> root/other/child    directory symlink
second path = root/link/../authority.sqlite3
```

`Path.expand(second_path)` yields `root/authority.sqlite3`, so the second owner locks that
store's sidecar. SQLite opens `root/other/authority.sqlite3`. Both gateways report ready;
the second commits a command and the first reads commands count 1 from its connection.
After stopping only the second, `LegacyImport.run(second_path, source, archive)` succeeds
while the first remains ready. This is demonstrated with the real binding, not an inferred
filesystem discrepancy.

**Correction:** resolve/reject the complete path once under a consistent contract and use
that exact validated identity for owner, actual DB open, importer and migration. Rejecting
noncanonical traversal is sufficient if consistently enforced. Add this regression across
the shared entry points; checking just the final component is insufficient. No external
worker fencing or privileged host isolation is demanded by this finding.

## Disposition of prior findings and strengthened evidence

- **V2-R4a corrected for exercised paths:** ordinary corrupt-result and protected
  unsupported-version same-ID retries fence. The independent ordinary probe verifies a
  later command cannot commit. Same-ID lookup still precedes obsolete proposal/current
  fact checks. Direct read and reopen detect the tested invented disposition.
- **V2-R4b partial:** scalar projection/payload and invalid result semantics are refused;
  persisted result/event/projection/pending-effect envelope binding is stronger. The
  optional-field admission/read mismatch above still blocks closure.
- **V2-R6 partial:** final-component symlink/hardlink and same-path same-VM/OS owner tests
  pass; independent direct symlink probe passes. Parent-symlink traversal remains blocked
  as above. Explicit previous-owner recovery evidence is still an operator assertion in
  these fixtures; final hostile-worker fencing remains FR-15a.
- **V2-R2a corrected:** authoritative stale revisions produce durable rejected input,
  command and result without domain rows. Independent stop/reopen/same-ID retry with an
  obsolete empty proposal returns the same rejection and zero events. The focused suite
  also covers policy/control/dependency rejection and row counts.
- **V2-R2b corrected by refusal:** the prior parent/child transfer is rejected before any
  rows commit; independently reproduced refusal. New top-level allocations require exact
  available funding for verified reservations. This limited store scaffold is not complete
  R5 ledger lifecycle or authority to let an untrusted caller provision arbitrary roots;
  root capability/isolation and later ledger ownership remain as documented.
- **V2-R7 improved but not complete:** backup now executes an ordered projection reducer
  and compares the resulting state to stored projections. The same-count changed projection
  probe now fails and fences. Ordered create/update and all-table content comparisons pass.
  The new one-way admission failure above remains in scope.
- **V2-R8 strengthened evidence passed:** after each bundle insert stage, tests reopen and
  compare complete table hashes plus reconstruction against the prior protected baseline.
  Hard-exit fixtures now seed prior protected history and verify old/new bundle counts after
  recovery. The real RLIMIT_FSIZE COMMIT I/O error preserves complete before/after content
  and reconstruction in its fixture. Hard-exit assertions themselves remain count checks,
  not complete row-hash comparisons; no broader claim is inferred from them.

The focused suite also reran original pending-only intent/digest, constraints, import
oversize/torn/unknown-version/publication-rerun, compatibility writer and canonical vectors.
No original obligation is superseded by the new tests.

## Separate sync-failure acceptance disposition

**Required FR-07 acceptance remains unpassed.** This is not a newly observed failed-sync
implementation defect. The candidate openly reports no specifically attributed failed
fsync through the actual binding. RLIMIT_FSIZE proves a checked COMMIT/write error; its
generic `disk I/O error` does not identify a sync syscall failure.

The exact unchanged FR-07 v2 refinement retains real binding/write/**sync**/import faults.
WORKFLOW-CONTRACT reiterates sync/write errors for FR-07. FR-19 owns the broader physical
capacity/WAL/checkpoint/compaction and full filesystem fault matrix; its ownership does not
waive the narrower deterministic sync-error conformance required here. This review does
not require hardware power loss, privileged mounts, physical ENOSPC or operational soak.

Resolve with a controlled attributed sync failure on the actual binding and documented
commit/acknowledgment/reopen contents, or an explicitly resolved governing design exception.
No such exception is present in these reviewed inputs. The author's lack of an exposed
Exqlite hook is a disclosed limitation, not proof that every nonprivileged mechanism is
unavailable. This review did not attempt a new binding/VFS implementation and does not
claim hardware or filesystem durability beyond the executed cases.

## Reproducibility and limits

Fresh root: `/tmp/fr07-v3-review.r4ohlM`. Commands from
`/private/tmp/pramana-fr07/foundry` used:

```text
PATH=/Users/raymondluong/.local/share/mise/installs/elixir/1.20.3-otp-29/bin:/Users/raymondluong/.local/share/mise/installs/erlang/29.0.5/bin:/opt/homebrew/bin:/usr/bin:/bin
MIX_ENV=test
MIX_BUILD_PATH=/tmp/fr07-v3-review.r4ohlM/build
TMPDIR=/tmp/fr07-v3-review.r4ohlM
```

- `mix test test/pramana_foundry/durable_store test/pramana_foundry/legacy_persistence_containment_test.exs test/pramana_foundry/effects/checkpoint_test.exs --seed 7727`:
  **49 passed, exit 0**, fresh dependency build and 85 project files compiled.
- `mix run --no-start /tmp/fr07-v3-review.r4ohlM/probes.exs`:
  **7 passed, exit 0**, seed 941302. Four probes confirm prior corrections, three reproduce
  remaining defects. The earlier run was 6/7, exit 2, because the trusted corruption
  fixture tried writing SQLite TEXT into a STRICT BLOB column. Corrected only that temporary
  fixture to `CAST(... AS BLOB)` and reran; the failure was not attributed to the candidate.
- Complete minimal fixtures: `/tmp/fr07-v3-review.r4ohlM/probes.exs`, SHA-256
  `a2407071126400cee70b0785a389eb66770000a396a550d1bbe1779229220e4c`.
- Ruby Digest check: all 25 manifest hashes matched. SHA-256 checks, exact diff inspection,
  `git rev-parse HEAD HEAD^{tree}` and final `git status --short` confirmed frozen inputs.

Only isolated temporary state/owned processes were exercised; trusted inspection/SQL
corruption injection is not evidence of candidate SQL access. No live state, provider,
credential, provisioning, Git integration, activation or full-suite rerun was performed.
The author's 458-test full-suite result is not relabeled as this review's execution.
Nothing here constitutes FR-08/15a/17/19/22 closure or deployment acceptance.

Because admission/reopen and path-identity defects have now recurred across candidates,
the next correction should diagnose and unify those contracts, with table-driven boundary
equivalence tests, rather than add only another narrow special case. Preserve prior FAIL
records and re-review the next exact candidate and affected invariants.
