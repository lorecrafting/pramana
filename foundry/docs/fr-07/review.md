# FR-07 independent implementation review

**FAIL — not ready for FR-07 acceptance.** Review date: 2026-09-13. The frozen candidate passes its focused tests, but independent probes reproduce authority bypass, lost-reply, corruption-recovery and source-preservation failures. This is an implementation verdict on the exact candidate below, not an expansion into FR-08/15a/17/19 or a deployment authorization.

## Exact input boundary

- Base: `8aa0ebddbfb5fa834bbefa53d1f84b992e4c25bd`.
- Candidate: `d99799e46577d24ca178ac67dea12ce2b250ee87`.
- Tree: `2fc76e2316ddef5ab2c27b0879bbf0ee90d28757`.
- Worktree: `/private/tmp/pramana-fr07`.
- `foundry/docs/fr-07/candidate.md`: SHA-256 `79a5ded644517b294a67e3e3e7a214b97f3ee518d448b8e39929e846e794b4e9`.
- All 15 candidate-manifest path hashes independently matched. The exact diff is 16 files (the 15 manifested files plus candidate.md), 2,467 additions, no deletions. Source/tests/docs in that diff were read; small README/Mix/EventLog diffs were checked separately. Existing untracked dependency directories were present and remain excluded.

Normative inputs were reviewed during independent preparation from base 8aa0ebd: AGENTS.md, relevant project orientation, full storage/transaction/recovery/import and authority sections of WORKFLOW-CONTRACT revision 3, FR-07/19 ticket requirements, FR-06 design reviews/responses/verification/focused R4a review, F02/F20/F21 audit and CODE_CONVENTIONS.md. Checklist: `/tmp/fr07-review-prep.md`. Broad unrelated corpus orientation output was truncated and is not claimed as a full corpus-plan review.

No candidate source or repository documentation was edited. Independent probe files and fresh runtime/build artifacts are under `/tmp/fr07-review-run.M4mDAI`. No live Foundry state, providers, credentials, account provisioning, Git integration or activation was used.

## Blocking findings

### R1 — P0: candidate-facing proposals can manufacture issued authority

`durable_store/kernel.ex:71` accepts every effect status, including `claimed`, `issued`, `succeeded` and `unknown`. `gateway.ex:68` sends the unauthenticated-by-capability `transact` path directly to `do_transact` with empty protected facts; `insert_intents` persists the supplied status and request digest verbatim. The protected capability is therefore not needed to create the durable fact that R1 defines as the irrevocable authorization boundary.

**Executed:** call `Gateway.transact` with an ordinary valid envelope and an intent `%{effect_id: "forged", request_digest: "not-a-digest", status: "issued", value: %{"operation" => "update_ref"}, schema_version: 1}`. It returns `{:ok, ... committed_seq: 1 ..., :committed}`. Real SQL reads `[["issued", 0, 0]]` for effect status, claim count and reservation count. No protected reference, raw receipt or reservation was supplied. This is not a same-VM introspection exploit: only the advertised candidate operation created the row. No external Git effect was run or claimed proved.

**Correction:** candidate proposals may only request bounded pending intents. Protected code must exclusively derive issue/claim/terminal status, canonical exact request binding and required owner/claim/ledger evidence. Reject unknown command/event operations instead of allowing arbitrary nonempty type strings to inject authority. Preserve the separate updatable domain reducer; this is a protected API fix, not a request to move the whole kernel into root.

### R2 — P1: command preconditions are ignored and rejected results can mutate domain history

`Gateway.validate_command/1` only verifies that `expected_revisions` is a map. `commit_bundle` never checks that map against durable facts. Its projection CAS uses independently caller-supplied `proposal.expected_revision`, not the command's read set. `ProtectedVerifier.validate_required_revisions/2` compares one supplied map with another and does not consult the DB. Domain events/intents/projections are always inserted regardless of `result.disposition`.

**Executed:** a command with `%{"nonexistent-policy" => 999}` as its expected revision map commits successfully. A proposal with `disposition: "rejected"` and a domain event also commits that event at sequence 3. Both are incompatible with the FR-06 transaction contract: complete durable read checks, protected reads the caller cannot omit, and durable semantic rejection with no domain mutation.

**Correction:** check complete expected read/write sets against authoritative rows inside the same transaction, derive mandatory protected reads internally or through an actually trusted checked reader, and enforce rejection semantics. Add cases with stale policy/control and read-only dependencies, not only a projection's local CAS. Ledger facts likewise currently consist of caller-supplied new generations and allocation/consumed fields; they do not implement the R5 held/delegated/retired conservation model. Full later budgeting behavior can remain deferred, but the available protected store API must not claim conserved authoritative allocation based solely on supplied fresh balances.

### R3 — P1: verified retries check current facts before idempotency

`gateway.ex:91-94` calls Kernel validation and `ProtectedVerifier.derive` before `do_transact` performs existing-ID lookup. This reverses the explicitly settled FR-06 lost-reply ordering for the protected path.

**Executed:** commit a verified command with `required_revisions: %{}`; retry the same actor/ID/semantic command after required facts change to `%{"policy" => "new"}`. The result is `{:error, :incomplete_protected_read_set}`, not its original durable accepted result. No command data changed. The original candidate test only retries identical current facts and therefore misses this case.

**Correction:** after authenticating access and computing the semantic digest, return the existing durable result/conflict before deriving current proposal authority. Exercise changed policy/read requirements and invalid obsolete proposals after a lost reply. Keep revoked mutation capability checks distinct from an independently authorized old-result read.

### R4 — P1: corrupt stored bodies remain healthy and subsequent writes continue

`Database.validate/1` checks `quick_check`, pragmas, user_version and four metadata values, not retained application envelopes, record versions, foreign-key violations or replay consistency. `Gateway.command` does not fence the gateway on `:corrupt_result`; `storage_failure?/1` only recognizes `storage_unavailable`.

**Executed:** commit a valid command, use a trusted test connection to set its result BLOB to `not-json`, stop and reopen the gateway. Startup reports `%{mode: :ready}`; reading the result returns `{:error, :corrupt_result}`; status remains ready; a new command commits at sequence 6. The test mutation simulates structurally legal SQLite content corruption, not candidate SQL access. It disproves the explicit corrupt-authority recovery promise even without physical WAL corruption.

**Correction:** validate supported persisted bodies and authoritative relational invariants before ready, and enter explicit recovery/fence on detected corrupt/unsupported history from any read path. Preserve original evidence. Full physical corruption repair and page/WAL fault matrix remain FR-19; recognizing an invalid durable result and refusing further healthy mutation belongs to FR-07 now.

### R5 — P1: import can overwrite its original and commits from an uncaptured source

`legacy_import.ex:13-26` accepts arbitrary manifest_path and writes there after committing, with no source/archive/DB alias checks. `import_lines` reads `source_path` after separately digesting and archiving it, rather than the already verified archive. The stored source digest and size are never revalidated against those imported bytes.

**Executed:** `LegacyImport.run(db, source, archive, manifest_path: source)` returns `{:ok, manifest}`, then `File.read!(source) == original_bytes` is false. The original JSONL has been replaced by JSON manifest content. The archive remains available, so this test did not destroy all copies, but the required preserved-original invariant is violated. Source-to-DB/sidecar aliases are the same unchecked class; those more destructive aliases were not exercised.

**Source-backed additional trace:** source changes after archive verification and before `import_lines`; DB rows then contain the changed bytes under the old source digest/archive metadata, and success does not verify consistency. This race was not executed. The code also permits import while another gateway is idle: a momentary SQL transaction lock is not an offline boundary.

**Correction:** validate normalized/resolved manifest/source/archive/DB/sidecar paths and reject collisions before writing, including default manifest collisions. Parse the immutable verified archive (or a verified captured handle), derive byte totals from that exact input and validate consistency. Supply a real exclusive offline owner boundary for import. Retain originals and error manifest on failed/rerun paths; test manifest publication failure and source mutation. This is the new FR-07 importer, not a demand to finish old cross-device relocation in FR-19.

### R6 — P1: no exclusive store owner; a second OS gateway is ready

`Gateway.start_link/open` obtains no persistent ownership lease and allows another process to open the same DB. SQLite excludes simultaneous write transactions, not multiple authorities between transactions.

**Executed:** with one gateway alive and idle, a separate `mix run --no-start` OS process opens another Gateway with `mode: :ready` and `BEGIN IMMEDIATE` succeeds. With the first connection holding `BEGIN IMMEDIATE`, the second still reports ready and its attempted transaction returns the exact wrapped `:busy` error. A separate same-VM second gateway also commits a new command while the first remains alive. The first probe establishes the missing owner boundary; the held-transaction probe confirms SQLite locking itself functions.

**Correction:** wire the gateway/import path into one exclusive persistent authority ownership boundary before ready, with explicit recovery after ambiguous owner loss. Existing RuntimeOwner containment is not referenced by this new gateway. Do not infer external-effect fencing from SQLite; real old-worker/isolation proof remains FR-15a and downstream effect tickets.

### R7 — P1: backup verification omits protected and import tables; no reconstruction proof

`gateway.ex:545-547` hashes only inputs, commands, command_results, events, projections, effects, claims, ledger_generations, reservations and legacy_records. It omits **metadata, receipts, leases, policy_revisions, control_revisions, artifact_references and import_runs**. Candidate.md and DURABLE-STORE.md claim all authoritative/import tables are fully compared. No backup reconstruction/replay test exists.

**Executed:** successful `Gateway.backup` returns exactly those ten table keys. The candidate suite compares one event count/hash and opens the backup; neither it nor the implementation verifies the omitted content. This is not evidence that VACUUM itself drops rows: the copy can be coherent while its claimed verification is incomplete.

**Correction:** compare every authoritative/import table and relevant metadata/sequence identity with stable explicit ordering, exercise nonempty protected/import data and same-count changed content, and reconstruct supported state from retained inputs/events to prove the storage backup contract. A full lifecycle reducer remains FR-08, but a mere row hash is not the promised reconstruction evidence. VACUUM INTO is an engine snapshot, not bare file copying; its use is not rejected just because the binding lacks sqlite3_backup. Record and validate its exact durable publication/sync semantics rather than silently equating mechanisms. Interrupted operational archival/compaction remains FR-19.

### R8 — P1: FR-07 sync-failure and multi-row crash evidence is incomplete

This is an acceptance-evidence blocker, not an observed failed fsync. The candidate explicitly admits no failed fsync syscall was exercised. Its injected `write_error`/`full` returns before any SQL, and `before_commit` returns before COMMIT. Its hard-exit fixture contains only command/result/event rows, while protected ledger/claim atomicity is tested only on success. There is no failure after each protected insert, inside commit/sync, import interruption/rerun, or transactional schema migration rerun. FR-07's v2 acceptance explicitly retains real binding/write/sync/import faults, not only the original one-row spike.

**Executed positive evidence:** 31 focused tests pass, including real max_page_count FULL, read-only-open refusal and hard exits before/after commit. These establish those exact cases. No fsync failure result can be inferred from FULL being configured or from max_page_count failure. The real FULL test starts from an empty store; it does not independently assert preservation of a prior populated protected transaction after failure.

**Correction:** add controlled real binding/VFS write/sync/commit error conformance and failpoints around a populated multi-table protected transaction and import publication, asserting full prior/new contents after reopen. If the chosen binding/platform cannot supply the required evidence, resolve that explicit design exception before closing FR-07; honest disclosure is necessary but not a waiver. Hardware power loss, physical filesystem ENOSPC/WAL/checkpoint exhaustion/compaction soak remain FR-19 and are not all required to run in this ticket.

### R9 — P1: canonical bytes violate the fixed command protocol

`encoding.ex:27` delegates string escaping to `:json.encode`. The FR-06 canonical protocol requires every U+0000–001F control to use lowercase `\\u00xx`, and requires a schema/domain-tagged digest object. Gateway hashes actor+command without an explicit domain tag.

**Executed:** `Encoding.canonical(%{"x" => "\n\t\r\b\f"})` produces JSON using `\\n\\t\\r\\b\\f`, not `\\u000a\\u0009\\u000d\\u0008\\u000c`. This will disagree with conforming cross-client request hashes. FR-08 owns the full client vector suite, but FR-07 implements and persists the canonical identity now.

**Correction:** implement the specified canonical string encoder/domain-tagged digest and add exact-byte vectors before persisting the v1 identity contract. No need to introduce a different canonical standard.

## Scope and useful results

The in-process dependency is actually Exqlite 0.40.0 on Elixir 1.20.3, OTP 29 from the pinned 29.0.5 install, aarch64-apple-darwin; the loaded SQLite reports 3.53.4. Independent inspection of the **actual gateway writer connection** returned journal_mode `wal`, synchronous `2` (FULL), foreign_keys `1`. This is stronger than checking settings on a newly opened backup connection. The separate-table transaction, FK/uniqueness/CAS rejection and same-ID ordinary retry tests are useful and passed.

Candidate capabilities were not read through `:sys.get_state` to demonstrate R1. That helper was used only by the trusted review harness to inspect real connection PRAGMAs and run the OS-lock probe. Actual denial of candidate VM/filesystem/process introspection is deliberately FR-15a, not claimed or demanded here. There is no evidence of an externally executed forged operation; the defect is the durable authorization row/API itself.

The >8 MiB, torn-record, unknown-version and ordinary rerun tests pass and preserve bytes in their tested noncolliding cases. All imported records are stored as legacy evidence, not events, so this candidate is an evidence archive with a compatibility writer; it does not reconstruct legacy workflow state. That distinction must remain explicit.

Writer integration remains opt-in `EventLog.append({:durable_store, gateway, actor, opaque_command_id}, event)`. A whole-source search finds no Coordinator/Application/config reference to DurableStore. Effects.Checkpoint still constructs current-time JSONL events and reads the legacy path; Coordinator append paths and startup are unchanged from base containment. Thus no current application command is migrated. I do **not** demand all mutation/replay migration before FR-08 or mark the unchanged FR-03 containment regressed. FR-07 may claim only this exercised opt-in compatibility boundary, not that the running writer now persists atomic workflow decisions. docs/PLAN and REPAIR-PLAN were not updated in this candidate; keep its status incomplete pending corrections and update the living plan with the eventual accepted work.

Full deployment write-set inclusion/rollback remains FR-17; this candidate has fixed metadata version checks, no executable compatibility migration/replay/write-set scenario. Complete domain command routing/reducer, external claim dispatch/reconciliation, OMP, budgets/reset lifecycle and operational retention remain with their owning tickets. The defects above are in the FR-07 API and claimed storage/error/import contracts, not deferred end-to-end behaviors.

## Commands, reproducibility and limits

Identity checks: `git rev-parse HEAD HEAD^{tree}`, `shasum -a 256 foundry/docs/fr-07/candidate.md`, Ruby Digest comparison of all 15 manifest entries (printed `15 hashes matched`), `git diff --stat 8aa0ebd..HEAD`, bounded full source/test/doc reads, small-path exact diffs and source reference search. `git status --short` showed only the pre-existing untracked dependency directories.

Fresh directory allocated with `mktemp -d /tmp/fr07-review-run.XXXXXX`: `/tmp/fr07-review-run.M4mDAI`. Pinned commands ran from `/private/tmp/pramana-fr07/foundry` with:

```text
PATH=/Users/raymondluong/.local/share/mise/installs/elixir/1.20.3-otp-29/bin:/Users/raymondluong/.local/share/mise/installs/erlang/29.0.5/bin:/opt/homebrew/bin:/usr/bin:/bin
MIX_ENV=test
MIX_BUILD_PATH=/tmp/fr07-review-run.M4mDAI/build
TMPDIR=/tmp/fr07-review-run.M4mDAI
```

- `mix test test/pramana_foundry/durable_store test/pramana_foundry/legacy_persistence_containment_test.exs test/pramana_foundry/effects/checkpoint_test.exs --seed 7721`: **31 passed, exit 0**; fresh build compiled dependencies and 84 project files. Test application startup printed tick=false and used isolated test runtime; no provider execution occurred.
- `mix run --no-start /tmp/fr07-review-run.M4mDAI/probes.exs`: **exit 0**, reproduced R1/R2/R3/R4/R5 and inspected actual PRAGMAs, canonical bytes, backup keys and second same-VM writer. Its first attempt exited 1 at compile time due to an invalid `put_in` expression in the review script, before any body executed; corrected only that temporary script and reran successfully.
- `mix run --no-start /tmp/fr07-review-run.M4mDAI/more_probes.exs`: **exit 0**, recorded runtime/SQLite versions and independent OS owner/lock results. Idle child BEGIN succeeded; held-transaction child reported `{:error, {:unexpected_sql_result, :busy}}`.

Probe files contain complete minimal API fixtures and exact SQL inspection. They allocate only explicitly named fresh review DB/source files. Their results are observations, not success assertions that the defective behavior is acceptable. R5's source-race extension and other explicitly labeled source traces were not executed. The suite was not broadened after multiple independent acceptance blockers were established; no full 440-test run, live/provider smoke, full physical storage failure matrix, OS provisioning, deployment or broad benchmark was performed. Existing author full-suite evidence is not relabeled as this review's execution.

## Manifest inventory independently verified

```text
33136e5c3c25e92976762c3a581380d24d3ca2771162557d9d42bb0d4cc74c83  foundry/README.md
11011de2498e324355be95bc1c17667663ebedc57dd62467adb5df329691c6f0  foundry/docs/DURABLE-STORE.md
ebbf593cfb9acb975ff37ae12affcea5f9dae1896b2f4b679f56f83f85733182  foundry/lib/pramana_foundry/durable_store/compatibility_writer.ex
7818b553bde34fb3dfd6e749d4c6d82d60f9c30c2dead1569576b8b12bc14c5f  foundry/lib/pramana_foundry/durable_store/database.ex
b706e1976f8cd09f9fa0b311e099343e3498586539c1e92c1b78e5fa3f42e8a0  foundry/lib/pramana_foundry/durable_store/encoding.ex
b85aa65f52eb4da8f6185e60b9b4ab58a5ecf8ea93889a1f82e2de193baefe5b  foundry/lib/pramana_foundry/durable_store/gateway.ex
191c8038857005a4ceb6f637f14c5d8a1e4b04027b103b8c23ee23fbe9703c67  foundry/lib/pramana_foundry/durable_store/kernel.ex
2b56047016cb74ef6354604bcbb2e0809823bf9212842ff4304616ccd4fadb4d  foundry/lib/pramana_foundry/durable_store/legacy_import.ex
4a3dd40378a7d02fc490b5f72d9a4556d152b2d0aa5521e4700d739a8e6fdb48  foundry/lib/pramana_foundry/durable_store/protected_verifier.ex
02735f8c61c864e003fe3ec596476cd315f8833080ee5c26e7cb152abf27fd41  foundry/lib/pramana_foundry/event_log.ex
df569423c58a67452cdb93d98259615ac0996b671dccb40089de28dce8c24caf  foundry/mix.exs
bf2a61f815533a96b2abec87b1690ae49145bec56e60703a22b4db178c56e954  foundry/mix.lock
55048c42848fb44086bbf8864b566d20137cf2f6994baa866cafc3ac8900b52a  foundry/test/pramana_foundry/durable_store/gateway_test.exs
dbef76cf8a02bf544617ff76b5ef2303cf20064d6fa3c7b6aac64f10e5ba3fc4  foundry/test/pramana_foundry/durable_store/legacy_import_test.exs
372365daecf086fd4af6e6bddc8ee16ef937ad16ef96b84669e0de759bdde371  foundry/test/support/durable_store_crash_fixture.exs
```

The smallest acceptable follow-up is a corrected frozen candidate with R1–R9 dispositions, executable regressions for the observed traces and explicit resolution of required missing storage evidence. Re-review the changed paths and affected invariants; do not replace the independent FAIL with the candidate author's own passing tests.
