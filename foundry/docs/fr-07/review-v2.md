# FR-07 renewed independent implementation review

**FAIL — corrected candidate is not ready for FR-07 completion.** Reviewed 2026-09-13.
The actual binding passes all 44 focused tests. Independent production-API/SQLite probes
nevertheless reproduce ownership, recovery and acknowledgment defects. Required sync-error
and reconstruction evidence also remains incomplete. This is a bounded renewed review of
R1–R9 and their corrections, not a reopened architecture review or deployment acceptance.

## Exact reviewed inputs

- Base: `8aa0ebddbfb5fa834bbefa53d1f84b992e4c25bd`.
- Rejected v1: `d99799e46577d24ca178ac67dea12ce2b250ee87`.
- Reviewed v2: `b88918dd54094e657f8c6aae839878327c75e4d6`.
- Tree: `4f2e7b5c6d17cc80749fb6ad331ff0dffabe633c`.
- Worktree: `/private/tmp/pramana-fr07`.
- `candidate-v2.md`: `5dc0c7bbe8bcf21943b03b27aec092116e602ea515c319a54d7b29b995d26b9a`.
- Preserved `review.md`: `bba396dd837ad06018c460a4dd68223792d536542b7fbdb53cfaea2092597f30`.
- `review-response.md`: `d089de9abaca36e65674218844634944cf33a082734666a8a343ce06cbb65f39`.
- `WORKFLOW-CONTRACT.md`: `5d1621ff98fcb1aad2d6d37ba523b2a00c6bf90120873ffeb2518f23fd831488`.
- `REPAIR-PLAN.md`: `8ecb2900160c7a8c7e711039251d2a7ced2eacc20a567ebc46a9d2865c872581`.
- `DURABLE-STORE.md`: `c41998ae08fcc27b650420c693f4f09f0104e72e6b05cd52696a32b24fab9846`.

All **22** entries in candidate-v2's manifest independently matched SHA-256. The base-to-v2
diff contains those 22 paths plus candidate-v2.md: 23 files, 4,222 additions. The manifest's
implementation commit `bda425a` is the earlier content boundary; `b88918d` includes its
candidate document. This is documented provenance, not unexplained source drift.
HEAD/tree were rechecked after execution and remained identical. Only the five previously
untracked dependency directories were present; no source edits occurred.

I read the complete original R1–R9 review, response and v2 candidate, all eight store modules,
the corrected tests/fixtures and store guide, small EventLog/README/Mix diffs, and normative
FR-07/FR-19 plus storage/transaction/authority/recovery/canonical contract sections. This
does not claim a new full FR-06 architecture or unrelated corpus review.

## Blocking implementation findings

### V2-R4a — P1: corruption discovered by idempotent retry does not fence

`gateway.ex:532,692` decodes a retained result but `storage_failure?/1` recognizes only the
wrapped `storage_unavailable` error. The special corruption fence exists solely in
`handle_call({:command, ...})`. Both transaction retry paths can read the same corrupt bytes
without entering recovery.

**Executed minimal trace:** commit A; trusted test connection changes A's result BLOB to
`not-json`; call ordinary `Gateway.transact` again with A's identical actor/ID/command.
It returns `{:error, :corrupt_result}`; status is still `:ready`; new command B commits.
The corruption injection simulates damaged authority, not candidate SQL access.

**Required correction:** one consistent read/error classification across lookup, command,
backup and transaction paths. Any detected corrupt/unsupported authority must fence later
mutations. Retest both ordinary and protected same-ID paths, including unsupported version.

### V2-R4b — P1: write and recovery body contracts disagree; valid-looking corruption passes

`kernel.ex:62` validates projection identity/revisions but not the value shape. `Encoding.json`
accepts a boolean value. `database.ex:375` requires every retained body to decode as an object.

**Executed without any SQL mutation:** submit an otherwise valid candidate bundle with
`projection.value = true`. It returns committed acceptance. Clean stop/reopen enters recovery
with `{:invalid_stored_body, "projections", rowid, :not_an_object}`. Candidate-only input can
therefore commit a store that its own normal startup refuses.

**Second executed trace:** after a normal commit, replace the result body with
`{"schema_version":1,"disposition":"invented"}` through the trusted fault harness. Reopen
reports ready and `Gateway.command` returns that invented disposition. Startup checks only
object/version, not supported result fields, row/body identity or consistency. The separate
SQL disposition column still says accepted. This is not physical page-corruption testing.

**Required correction:** use compatible strict persisted-record validation at admission,
startup and reads. Validate required fields/values and their relational bindings, not only
the top-level version. Add candidate-valid/reopen equivalence and structurally legal but
semantically invalid body regressions.

### V2-R6 — P1: a database filename alias bypasses exclusive authority and offline import

`owner.ex:9` derives the lock/marker paths from the caller's database pathname without
resolving its file identity. SQLite itself opens the symlink's underlying database, but
the two callers hold different owner sidecars.

**Executed:** start first gateway on `authority.sqlite3`; create `alias.sqlite3` as a symlink
to it; start a second gateway on the alias. Both are ready and the second commits a command.
Stop only the second; `LegacyImport.run(alias_path, source, archive)` succeeds while the
original gateway remains alive and ready. Ordinary same-path same-VM and OS exclusion tests
pass; they do not cover this alias.

**Required correction:** bind ownership to one validated canonical store identity before
opening either gateway or importer. Reject unsupported symlink/hardlink aliases or prove
they share the exact same lock/marker. Include aliases in separate-process/offline tests.
This is local store ownership; it does not demand FR-15a external-worker fencing early.

### V2-R2a — P1: valid stale-read rejection is still not a durable command decision

`gateway.ex:549` now reads expected revisions inside the transaction, which fixes the ignored
precondition. But `commit_bundle` returns `{:error, {:bundle_rejected, ...}}` after rollback
without retaining input, command or rejected result.

**Executed:** a schema-valid command and internally aligned proposal expect revision 99 for
an absent entity. The gateway returns the expected revision-conflict error; subsequent
`Gateway.command(id)` is `:not_found`, and commands count is zero. This is a valid semantic
precondition failure, distinct from an unknown schema or a malformed proposal.

**Required correction:** retain the authenticated semantic rejection with no domain mutation,
and return its immutable result on same-ID retry. WORKFLOW-CONTRACT's transaction section
explicitly requires this. Rejected proposals with events are now refused and cannot mutate;
that useful correction does not satisfy durable rejection by itself.

### V2-R2b — P1: claimed protected allocation conservation is still caller-supplied arithmetic

The only v1-to-v2 change in `ProtectedVerifier` returns required_revisions to the gateway.
`allocations_fit/2` still checks authorizations against newly supplied generation balances;
it does not derive/read/debit the referenced parent's allocation.

**Executed through `transact_verified` with the fixture's legitimate root capability:**
commit a parent generation with allocation 1; then commit child allocation 100 naming that
parent, with no parent read precondition. Both commit. SQL shows child 100 and parent 1,
consumed 0 for each. No root facts are independently fetched to prevent this transfer.

This is not proof that an isolated hostile kernel can obtain the capability, and no external
request was made. It disproves the store guide's claim of conserved protected allocation and
leaves the explicit v1 R2 correction unresolved in an available API.

**Required correction:** either implement the in-transaction protected parent checks/transfer
for this supported operation, or reject that operation until its owning ledger implementation
exists and accurately delimit the scaffold. Full reset/settlement lifecycle remains FR-08
and budgeting tickets; that deferral cannot make an unconserved child transfer authoritative.

## Required acceptance still unavailable or incomplete

### V2-R7 — full table copying corrected; reconstruction/replay proof still missing

Backup now hashes all 18 authority/import/metadata/sequence tables with stable ordering;
nonempty protected/import data and file/directory sync are exercised. This resolves the
omitted-table inventory finding. `VACUUM INTO` is an engine snapshot and is not rejected
merely for differing from sqlite3_backup.

However `reconstruction_evidence/1` hashes a join of current input/result/event rows, and
`validate_reconstruction/1` checks only an upper bound on result sequence and existence of
projection event IDs. Neither reconstructs supported state or compares it with projections.

**Executed:** take backup after one normal command; change the existing projection body from
`ready` to `invented` with the same row count; take another backup. Both succeed, and their
`reconstruction` maps are identical while their projection content hashes differ. This
does not prove the engine copied incorrectly; it proves the reconstruction digest contains
no validation of the changed projection. The test checks the content hash is a hash, not an
actual reconstructed state.

FR-07's incorporated contract says verify full content/replay, and v1 R7 requested this
specifically. Require executable reconstruction for the supported FR-07 boundary and ensure
retained inputs/events contain what that reconstruction needs. The full workflow reducer
and complete command migration remain FR-08. Keep this required evidence open rather than
renaming a join digest replay.

### V2-R8 — real COMMIT I/O failure passes; a controlled failed sync remains unpassed

The 44-test run exercised real SQLite FULL, filesystem read-only refusal and the OS
RLIMIT_FSIZE child. The child reaches checked COMMIT, returns `disk I/O error`, and the prior
command survives reopen with explicit owner-recovery evidence. Failpoints after every
bundle insertion and complete protected hard-exit bundles also passed. These are material
improvements over the v1 one-row/pre-SQL cases.

They do not establish a failed fsync. The candidate explicitly acknowledges this and no
specific sync fault hook was found in the examined Exqlite public/NIF interface. A `disk I/O
error` caused by file-size-limited writing cannot be identified as an fsync error from its
generic message. This review did not independently prove that every nonprivileged way of
injecting such an error on this host is unavailable.

**Disposition: unavailable required FR-07 acceptance, not waived or passed.** REPAIR-PLAN's
FR-07 v2 refinement explicitly retains real binding/write/**sync**/import faults, and
WORKFLOW-CONTRACT repeats sync/write errors for FR-07. FR-19's additional full filesystem
ENOSPC/sync/WAL/checkpoint/compaction matrix does not erase that narrower obligation.
A deterministic, attributed sync failure through the actual binding, with no success
acknowledgment and prior complete content preserved after reopen, resolves this item.
Hardware power loss, privileged filesystem faults, physical ENOSPC and checkpoint/compaction
soak are not demanded for FR-07. If an explicit design exception is needed, record/resolve
it under the governing contract; honest limitation text alone is not acceptance.

The inserted-stage tests assert table counts rather than complete pre/post content. The
hard-exit fixture initializes a fresh store and tests a complete bundle but does not seed
prior protected history. Strengthen these assertions while fixing the above; do not claim
they already establish all prior protected row contents.

## Other original review dispositions

- **R1:** the observed unauthenticated candidate-issued/terminal-state manufacture is
  corrected. Known command/event operations, pending-only intents and exact domain-tagged
  digest checks pass. A whitelist and digest do not establish all future operation-specific
  bounds; actual claim/issue safety predicates and hostile-host isolation remain with
  FR-08/15a and downstream effect tickets. No SQL or external-effect authority bypass was
  newly inferred from a pending intent alone.
- **R2:** authoritative checks of supplied dependency/policy/control revisions and refusal
  of rejected bundles containing domain mutations pass. Durable rejection and protected
  conservation remain blocked as above.
- **R3:** corrected ordering passes: same actor/ID/digest returns the original protected
  result despite an obsolete invalid proposal and missing current facts. Current capability
  authentication remains first. Corruption fencing on that path is V2-R4a.
- **R4:** malformed JSON, unsupported result version and FK violations are detected by the
  tested startup/direct-read paths; the additional body/retry edges remain blocked.
- **R5:** direct source/manifest collisions and hardlink-to-store publication collisions are
  refused; original bytes survive tested errors. Import now parses the verified archive
  rather than reopening the source. Interrupted line ingestion and external manifest
  publication rerun without duplicate rows. The test named source-change changes source
  only after import has completed; it is not an executed mid-import race. No mid-import
  archive mutation/race was injected by this review. Offline exclusivity remains broken
  through the tested store alias under V2-R6.
- **R6:** same-path same-VM and OS exclusion and ambiguous-owner marker recovery pass. The
  recovery evidence supplied by tests is an explicit operator string, not independently
  verified evidence of all old external workers being fenced. FR-15a retains that proof.
- **R7/R8:** partial corrections and remaining required evidence are detailed above.
- **R9:** exact encoding correction passes independently for all 32 U+0000–001F controls;
  command and effect identities have explicit v1 domain tags. Full cross-client vector and
  command schema coverage remains FR-08.

No new findings are marked mere suggestions in place of blockers. Legacy writer integration
is still only the opt-in EventLog adapter; this candidate does not migrate the running
Coordinator, activate a deployment, complete FR-08/15a/17/19, or satisfy FR-22.

## Executed commands and limitations

Fresh artifacts: `/tmp/fr07-v2-review.1vZ0rI`; pinned commands ran from
`/private/tmp/pramana-fr07/foundry` with:

```text
PATH=/Users/raymondluong/.local/share/mise/installs/elixir/1.20.3-otp-29/bin:/Users/raymondluong/.local/share/mise/installs/erlang/29.0.5/bin:/opt/homebrew/bin:/usr/bin:/bin
MIX_ENV=test
MIX_BUILD_PATH=/tmp/fr07-v2-review.1vZ0rI/build
TMPDIR=/tmp/fr07-v2-review.1vZ0rI
```

- `mix test test/pramana_foundry/durable_store test/pramana_foundry/legacy_persistence_containment_test.exs test/pramana_foundry/effects/checkpoint_test.exs --seed 7722`:
  **44 passed, exit 0**; fresh dependency build and 85 project source files compiled.
- `mix run --no-start /tmp/fr07-v2-review.1vZ0rI/probes.exs`: initially 7 characterization
  probes passed; after adding the separate ledger probe, **8 passed, exit 0**, seed 75468.
  These assertions deliberately demonstrate defects and are not acceptance assertions.
  The complete minimal API fixtures and SQL fault injections are in that file, SHA-256
  `3f304d569ed8fe27d812abb1b12283363f703fe231815efd4f47d73b7d3318c5`.
- Actual gateway connection: WAL, synchronous `2` (FULL); SQLite `3.53.4`.
- `git rev-parse HEAD HEAD^{tree}`, `git diff --stat 8aa0ebd HEAD`, exact small-path diff,
  Ruby SHA-256 comparison of all 22 manifest entries, and SHA-256 checks of listed inputs.

Only isolated temporary state and owned test processes were used. The focused suite starts
its isolated test application with tick=false; the independent probes use `--no-start` and
supervised gateway children. `:sys.get_state` appears only in the trusted fault/inspection
harness, not as evidence of candidate access. No live daemon, provider, credential, account
provisioning, Git promotion, activation, full-suite rerun or physical storage fault matrix
was used or claimed. No repository source/doc edit was made by this review.

Return this frozen candidate to its implementation owner for bounded corrections, preserve
both independent FAIL records, and renew review against the resulting exact candidate.
