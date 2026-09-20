# FR-19A focused correction rereview — PASS

Independent review snapshot, 2026-09-19 Hawaii. **PASS for the bounded B1/B2
correction** and its necessary regressions. This supersedes those two blockers in
the [prior rereview](rereview.md), without broadening its credited physical evidence.
It is not integration, activation, deployment or FR-19B acceptance authority.

## Exact reviewed identity

- Implementation: `6c1e5acb29b10e0cd40c692de87f05f1155804c8`.
- Implementation tree: `0392ee329922c63a5b3f97bf441dc52719f19c6f`.
- Frozen candidate/evidence: `8cfd983b40e5ad6edce4e863ee64906960220f92`.
- Frozen tree: `f2c8cc76fbd30df7b1ee89302295d8d61fb609bd`.
- Prior review: `7ce0c65c0a4f72ec146abdbb26d8f0381f5e96d4`.
- Worktree: `/private/tmp/pramana-fr19a-correction`, branch
  `repair/fr19a-correction`.

Independently checked the clean frozen source, both trees and all 15 hashes in the
[candidate manifest](candidate.md). Read the shared workflow, Foundry orientation,
strategy summary, FR-19A/B criteria, relevant workflow/durable-store contracts, prior
review/reproductions and the complete correction diff. Only review evidence changed
after the clean-candidate checks finished.

## B1: owner loss and probe cleanup

The independent controller monitors the Gateway and owns the timer and actual probe.
Timeout, cancellation and owner death kill the probe and consume its monitored DOWN
before controller exit. Ordinary termination sends cancellation; an untrappable
Gateway death is independently detected by the controller. Probe failure cannot bring
down the Gateway. A completed probe has no remaining callback work after sending its
result and exits normally; that normal-result path demonitoring is not an explicit join.
The request token makes late result/timeout messages inert after request removal.

Repeated the prior owner-kill reproduction against the unchanged public API with no
deadline override. Both actual probe and controller died, rather than retaining the
stalled probe beyond the deadline. Additional fresh-process diagnostics exercised
ordinary Gateway stop, caller death, default timeout and untrappable probe death.
Each observed both owned processes' DOWN messages. Observed cleanup times in this
run were respectively 6 ms, 1 ms, 0 ms, 5,001 ms and 0 ms; these are observations,
not new performance guarantees. Surviving Gateways remained ready with no pending
health request after explicit replay of stale result and timeout messages.

The permanent default-timeout/responsiveness, caller-death and owner-kill/restart
regressions passed in the focused suite and full CI. Restart requires ready state
and a successful health request. Its bounded retry is restricted to the exact
transient SQLite lock status and rejects other recovery reasons. No leak or stale
mutation was observed in the scoped lifecycle cases.

## B2: real operation attribution with nonempty WAL

The test keeps its seeded Gateway connection open, disables autocheckpoint on that
connection, and derives integral positive frames from WAL size and live page size.
The production wrapper encloses only the unchanged `Database.query/2` checkpoint
or `Database.execute/2` VACUUM call. Its finalizer receives that operation's actual
result and stops/joins the interrupter before any subsequent authority verification.
Exceptional cleanup is also invoked before reraising; the interrupter independently
monitors its Gateway. There is no replacement SQLite result in this acceptance case.

Repeated the prior BEAM call/return trace diagnostic, selecting only the interruption
matrix and adding observations in its hook. At checkpoint entry the independently
observed WAL was **16,562,432 bytes**, page size **4,096**, and autocheckpoint **0**:
`(16,562,432 - 32) / (4,096 + 24) = 4,020` complete positive frames. The trace now
reports the actual target failure:

```text
Database.query(conn, "PRAGMA wal_checkpoint(TRUNCATE)")
=> {:error, "interrupted"}
EXACT_OPERATION_RESULT: {:checkpoint, {:error, "interrupted"}}
EXACT_OPERATION_RESULT: {:backup, {:error, "interrupted"}}
Result: 1 passed, 15 excluded
```

Unlike the rejected reproduction, a successful empty checkpoint cannot satisfy the
operation-result assertion. The scoped finalizer stops its worker before later reads,
so a later verification error cannot supply this result. These observations establish
interruption during the target engine calls, not an instruction-level deterministic
SQLite progress callback; the repeated interrupt remains scheduled by the BEAM.

The matrix passed source inode and nonempty WAL inode retention, recovery mode,
later transaction/backup fencing, baseline digest immutability, any partial destination
retention, and exact recovered content. Offline verification checks complete ordered
authority and reconstructed replay, including claims, ledger generations and
reservations; the assertions are not merely row counts.

## Executed checks and reproducibility

Review root: `/private/tmp/fr19a-critical-review.Bg5ljm`. Toolchain was pinned by
absolute PATH to Elixir 1.20.3 and OTP 29.0.5 (ERTS 17.0.5). `TMPDIR` was that
canonical root; `CPATH` selected the existing Exqlite bundled `c_src` headers.
Direct Mix checks used `MIX_ENV=test`, `COORDINATOR_TICK=0`, isolated `build` below
the review root and existing `/Users/raymondluong/dev/pramana/foundry/deps` sources.

| Check | Observed result |
|---|---|
| All 15 candidate manifest hashes | Matched |
| Operational storage, sync fault, relocation containment, Linux orchestration/workflow tests; seed 19317 | Exit 0; 25 passed |
| Independent operation trace matrix; seed 19319 | Exit 0; 1 passed, 15 excluded |
| Independent five-case owner/probe diagnostic | Exit 0; all owned processes terminated |
| Host error-table/loop-identity shell regressions | Exit 0 |
| Clean frozen candidate `elixir ci/run.exs --output .../ci-artifacts` | Exit 0; 555 passed, 13 skipped, 1 excluded |
| Correction whitespace check | Exit 0 |

The first staged documentation check found the new report lacked a route from the
shared router (79/80). A single catalog link corrects that documentation-only issue.
The corrected staged documentation gate exited zero with 80 passed.

Full CI includes locked dependency restore/inventory, forced warnings-as-errors
compile, formatter check, model-free tests and fresh escript build. Both source
snapshots identify the exact frozen revision/tree and no dirty paths. The relocation
skips and optional Python/tiktoken exclusion retain their existing limitations.
The known contradictory `format_debt.error` metadata persists despite the formatter
and overall gate passing; it is unchanged by this correction.

SHA-256 evidence:

```text
7ad9c483c8bb26196fb0c470c1b070b4fb8bcbf5238dcdf5a963b5fe8bb3eb9b  focused.log
8c08db7d9386c914aa04d7ca88c92f7740d06296ed7c0feb4ce5edf3010b4cf4  trace.log
3e5b5549aa5dc9133ae4b5136180a8c787b151db0c7f588ef8407d5e1fffcc21  owner.log
fff9a15453f6fa6333baa4b720f4c85f112827b359c47431c91673625e743f44  ci-artifacts/provenance.json
513aa9282bebaabf75cb3f1e4ce40f8adf17e460467c4961d9ca73fb68649dd9  ci-artifacts/pramana_foundry
```

The reviewer scripts `trace.exs` and `owner.exs` remain in the local review root.
The trace adapts the prior [recorded diagnostic](rereview-evidence.md): tags select
the existing matrix, the armed hook prints real WAL stat/page-size/autocheckpoint,
and the finalizer prints its operation result. Production modules are unchanged.
The owner script monitors both probe and controller, applies each named lifecycle
event, waits for both DOWN messages, and verifies stale tokens leave an empty map.

## Preserved physical evidence and limits

Both fresh suite runs included the Darwin physical ENOSPC cases and passed. The
post-run image inventory contained no FR-19A image. The prior independently credited
Linux run `35498430877`, artifact `10601228576`, remains attributed to revision
`5f4984be07c67de8515a26d953d4d5b7de907c05` and tree
`7f6b91e6815bc19b4110e697c1d9fc6d7361ad85`. This review did not rerun or redownload
that physical Linux experiment. An exit-zero exact diff independently confirms the
workflow, host/orchestration/parser/raw-control helpers, Linux fixture and Maintenance
module are unchanged. Inspection confirms backup sync and its fault seam remain
unchanged; the new wrapper only surrounds VACUUM.

The credited kernel EIO/fencing/retained-content recovery after orderly remount
therefore remains applicable at its prior narrow scope. It does not prove failed-sync
persistence, physical WAL xSync failure, power loss, controller/cache flush or media
durability. FR-19B, provider/daemon operation, activation and deployment remain open
or separately governed. No shared plan/log, provider, daemon, push or integration was
changed by this review.
