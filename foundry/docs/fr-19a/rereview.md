# FR-19A independent correction rereview — BLOCKER

Reviewed 2026-09-19, Hawaii, by the independently assigned Astra-high reviewer.
Verdict: **BLOCKER**. The production-default health response and backup failure
classification are corrected, and physical ENOSPC/kernel-sync evidence is now
credited. B1's worker ownership and B2's in-progress checkpoint acceptance remain
incomplete. This verdict does not authorize integration, deployment, activation or
a shared ticket-status change. FR-19B remains open.

## Exact candidate and evidence binding

- Frozen candidate: `ad455a8137b9cafbbec1670a3f683aa9364d5789`.
- Candidate tree: `282234589a15856449389cbed21530d457aa3c41`.
- Implementation checkpoint: `3852f0566ccf5a09f2f5eaf110df1f2d5643f886`.
- Implementation tree: `2ef98a6a43d6b34a9bf98f826a372b726fb2237d`.
- Original implementation base: `4a9098d8f6d8bcfbe21c0276f14230d888d04038`.
- Original blocker review commit: `705e7b604483c631b2ac968c9a99ca627d8ad616`;
  [review](review.md).
- [Candidate record](candidate.md) SHA-256:
  `19153a815068e088fd8cf4f5ba667c2cec8697301862ae7d9154d4c9d3fd6839`.
- Branch/worktree: `repair/fr19a-correction`,
  `/private/tmp/pramana-fr19a-correction`.

HEAD, tree, all 15 implementation-manifest hashes and clean source were independently
checked. The Linux evidence revision is
`5f4984be07c67de8515a26d953d4d5b7de907c05`, tree
`7f6b91e6815bc19b4110e697c1d9fc6d7361ad85`. Its differences from the frozen candidate
are three evidence documents and `operational_storage_test.exs`; production,
dependency and Linux harness inputs are unchanged. Thus the Linux result applies to
the candidate's exercised backup path, while the revised interruption regression
requires its own scrutiny below.

Reviewed the shared workflow, Foundry orientation/strategy, current FR-19A/B ticket,
F20/F21, workflow and durable-store contracts, original review, correction records,
production changes, permanent tests, Linux workflow/host/orchestration/parser/fixture,
and the downloaded raw artifact. [Evidence and reproduction details](rereview-evidence.md)
preserve the new counterexamples and bounded Linux observations.

## B1 — Stalled worker survives untrappable Gateway termination

The original default-deadline defect is fixed: the public API waits for the Gateway's
owned five-second timer, the worker runs outside the callback, unknown capacity is
returned, and ordinary status/counts calls remain responsive. The permanent default
regression and caller-death cleanup test passed in both independent suite runs.

However, `gateway.ex:145` uses `spawn_monitor/1`, which establishes only a monitor
from the Gateway to its worker. The worker neither links to nor monitors the Gateway.
The only timeout is delivered to the Gateway (`gateway.ex:151`); termination cleanup
depends on `terminate/2` (`gateway.ex:115`). An untrappable exit bypasses that callback.

Independent reproduction started the same permanently stalled probe without a deadline
override, began a public health request, waited for the worker-start handshake, and
called `Process.exit(gateway, :kill)`. The caller exited with the expected killed-call
reason, but the worker remained alive 5,500 ms later. The reviewer explicitly killed
and joined that worker afterward. No production source was changed for this probe.

This is an unbounded owned-worker leak after owner loss, not evidence of lost database
authority. The candidate's claim that Gateway termination always removes owned work
is false. Complete the lifecycle so owner loss terminates the worker even when
`terminate/2` cannot run, without allowing a failed diagnostic worker to take down the
Gateway. Add a regression that observes worker death after untrappable owner loss;
retain the passing default deadline, responsiveness and caller-death cases.

## B2 — Checkpoint interruption test passes after checkpoint already succeeded

`operational_storage_test.exs:219` closes the seeded connection before starting the
faulted Gateway. In the independent diagnostic run, the WAL at the checkpoint hook
was **zero bytes**. A BEAM call/return trace of the unchanged production
`Database.query/2` then observed:

```text
PRAGMA wal_checkpoint(TRUNCATE)
=> {:ok, [[0, 0, 0]]}
```

The existing test still passed its storage-error/`"interrupt"` assertion. Its worker
keeps calling `Sqlite3.interrupt/1` every millisecond until the complete public request
returns (`operational_storage_test.exs:255`), so it can interrupt the subsequent
`Authority.read/2` at `gateway.ex:1077` after the checkpoint has already succeeded.
The hook handshake proves that the interrupter started; it does not locate the failed
SQLite operation. Increasing committed command payloads cannot make a zero-frame
checkpoint perform the intended WAL work.

The diagnostic only added a WAL stat at the existing test hook and enabled BEAM return
tracing; it did not replace the Gateway, Database, SQLite operation or test assertions.
The original matrix returned **1 passed**, while the trace demonstrated this false
positive. This is an acceptance-proof gap, not a demonstrated checkpoint data-loss bug.

Required correction: retain a demonstrably nonempty, uncheckpointed WAL immediately
before the target operation, localize the failure/interruption to the actual checkpoint
operation, and ensure an error in a later verification query cannot satisfy the case.
Then verify the complete prior authority, replay, claims, ledger generations,
reservations, retained source/WAL and later-effect fencing. Keep interruption-worker
cleanup reliable when assertions fail. Recheck the backup case with equivalent
operation attribution; the current repeating-worker assertion is also too broad to
establish that attribution by itself. A larger timed workload is not a deterministic
in-operation handshake.

The physical-full checkpoint case is separate and useful: it keeps a real nonempty WAL
on the full owned filesystem and passed. It does not replace the specifically required
interrupted-checkpoint case. Post-operation hard exits also retain their narrower
meaning. Consequently the previous B2 acceptance requirement is not fully discharged.

## Credited physical and maintenance evidence

The backup implementation now separates target/path preflight from post-preflight
execution, wraps the latter's errors as `storage_unavailable`, fences later mutations,
and closes snapshot file/directory descriptors in `after` clauses. Existing-target
refusal preserves the target and leaves a healthy store ready. Full-content/replay
backup verification, corruption fencing and explicit unclean-owner recovery remain.

Both independent suite runs executed the Darwin HFS+ cases. They fill exclusively owned
12 MiB and 20 MiB images until an actual Erlang write returns `:enospc`, then exercise
backup and a nonempty-WAL checkpoint respectively. These are filesystem exhaustion,
not SQLite page ceilings or process size limits. Typed failure/recovery and complete
baseline recovery assertions passed; the checkpoint case also explicitly checks later
protected-operation refusal. The tests retain partial destinations and the original
source during verification. Post-run disk-image inventory showed no FR-19A image
remaining attached. No unrelated image was touched.

[Linux run 35498430877](https://github.com/lorecrafting/pramana/actions/runs/35498430877)
and artifact `10601228576` were independently downloaded and inspected. The archive's
655,833 bytes hash to
`ad315c15657068a921a1faeb73831a66c08bbecd252dc79145f539c7cca76959`, matching GitHub's
artifact digest. The run/revision/tree and all recorded harness hashes match. The
recorded runner uses Elixir/Mix 1.20.3, OTP 29 and ERTS 17.0.5; the workflow pins OTP
29.0.5 and the resolved setup-beam path is traced. The local gate independently verifies
the full exact OTP version. The Linux artifact itself does not contain the local
gate's `OTP_VERSION` policy attestation.

The raw control and real Gateway descriptor each show a kernel `fsync` EIO on their
exact owned paths after the exact 262,144-sector mapper `error` table was live. Gateway
descriptor 25 opened before the fault, failed at `1789891329.806418`, and closed at
`1789891329.808686`. The production `:file.sync` call returned
`{:error, {:storage_unavailable, {:backup_failed, :eio}}}` through the public backup API;
recovery mode and later protected-effect refusal were asserted. This is a genuine
controlled kernel/block-stack fault, not an injected SQLite return value.

The tracked dirty helper closed/joined, the Gateway stopped, the exact linear mapping
was restored, and an ordinary unmount/fresh mount used the same loop/image inode and
mapper. The raw mount records show `emergency_ro` before unmount and writable ext4
afterward, without fsck, mkfs, replacement, forced or lazy unmount. The retained
188,416-byte backup's digest stayed
`ccb2b4d029ac200f013abb2ea07ad949484bcadcb645bd8938116a538760b852` before remount,
after remount and after verification, matching the baseline. The fixture compares
every ordered-content digest and reconstructed replay, including claims, ledger
generations and reservations, and independently verifies a recovered backup from the
unaffected source. Both exact resource sets report cleanup success and absent owned
mount/mapper/loop; workflow cleanup exits zero. The parser also passed when independently
rerun against the downloaded traces.

This proves the exercised backup kernel-sync failure, fencing and retained-content
recovery after orderly remount. It does not prove persistence across the failed sync,
power loss, controller/cache flush, physical media reliability or real WAL `xSync`
failure. Existing injected VFS WAL-sync tests retain their separate attribution.
No additional hardware durability guarantee or broad FR-19B completion is inferred.

## Independently executed checks

Elixir 1.20.3 / OTP 29.0.5 / ERTS 17.0.5, selected with absolute toolchain paths.
Canonical temporary root: `/private/tmp/fr19a-rereview.rTTr6P`. The full CI runner
restored locked dependencies into its own root; direct checks used a separate build and
existing dependency sources. `CPATH` selected Exqlite's bundled native fixture headers.

| Check | Result |
|---|---|
| Exact candidate/tree and 15 manifest hashes | Matched |
| Host error-table/loop-identity shell regressions | Exit 0 |
| Focused operational/sync/relocation/harness suite, seed 19233 | Exit 0; 24 passed |
| Canonical `elixir ci/run.exs`, clean frozen candidate | Exit 0; 554 passed, 13 skipped, 1 excluded |
| Independent parser on downloaded raw Linux artifact | Exit 0 |
| Traced existing interruption matrix, seed 19231 | 1 passed, 14 excluded; successful empty checkpoint observed |
| Default stalled-probe owner-kill diagnostic | Worker alive after 5,500 ms; explicitly cleaned up |
| Candidate diff whitespace | Exit 0 |
| Staged review/evidence documentation gate | Exit 0; 80 passed |

Canonical CI covers forced warnings-as-errors compile, formatting, tests, dependency
inventory and escript build. Source preflight/postflight both name the exact candidate
and tree with no dirty paths. Provenance SHA-256:
`2b7e1760e6ab310f44edc0a6bd3f16774a8ac2ef0867d6bcd920968a8f8e3a24`.
Escript SHA-256:
`ab46e4ba889d5171d5f3412c78b08c8addecf5eb0a25c03641372232166ce99e`.
The 13 explicit relocation skips and one optional Python/tiktoken exclusion retain
their prior meaning. The unchanged runner still records the known contradictory
`format_debt.error` text despite a successful formatter/gate; it is not new debt proof.

## Nonblocking suggestions and handoff

The Linux parser emits `ext4_emergency_ro=false` whenever the errno is EIO, even though
this run's raw mapper/remount records show `emergency_ro`. Derive that field from the
observation or label it as whether EROFS provenance was required. This metadata defect
does not negate the independently inspected EIO proof.

When the remaining blockers are corrected, reconcile the current durable-store
reference's older physical-evidence paragraph with the exact new accepted scope.
Shared repair status and historical evidence must retain their respective ownership.

This review changes only its report, supporting evidence and catalog links. It repairs
no implementation and performs no integration, push, provider operation, live-daemon
operation, deployment or activation. Fix B1/B2 and obtain an independent rereview of a
new frozen candidate; preserve the valid physical evidence and its limitations.
