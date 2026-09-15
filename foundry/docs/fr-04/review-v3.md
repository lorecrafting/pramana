# FR-04 renewed v3 review — FAIL

Date: 2026-09-13 (Pacific/Honolulu). Reviewed corrected candidate in
`/tmp/pramana-fr04`, branch `repair/fr04`, base
`5c69e6c73f572e60a6c2015e955ad841bf504517`. No implementation edits or commits.

## Exact candidate and freeze provenance

The initial freeze declaration was invalid. The supplied response SHA
`ce52f9cc6d8468da4a1f6fc258f51291be09aa84de1dc36a2b2c33ff05e83768`
listed AgentServer SHA `08cd40d3d3048183594437265b0a9f8c0a2f77517008703cbe43744741f9b16e`,
but the file already had different bytes when independently checked. Executable
review was held. The parent acknowledged a post-draft correction and supplied a
new freeze. This review applies only to that replacement freeze:

- `review-response-v2.md`: `1d5f4e0b01a4579c6095fa7f5919aa7bfcd4b9e8a24aff5d7279ea8a55badcf1`.
- `agent_server.ex`: `9eeb87a53ac881d0e20f409241aeff1384c64bff57bf65d74e919efdb0f54685`.
- Prior `review-v2.md`: `3e145afbec9f725222ef8913ef565f7ad49d5f6f268fd4b2301b7b1c8a6247c2`.

All **20** implementation/test entries in the refreshed response manifest were
independently checked with `shasum -a 256 -c`; every entry matched. The response
and AgentServer hashes remained unchanged after executable review. Future freeze
declarations must follow the final edit/hash generation rather than precede it.

## Blocking residuals

### V3-1 / R2 — A drain deadline can remove the marker without cleanup evidence

The responsive RuntimeLease fixes the former synchronous owner/query deadlock.
However, `Coordinator.safe_clean_shutdown_state?/1` (lines 1296–1306) requires
`cleanup_last_result` only when assignment status is `dispatched`. Other states
with a live execution, including `handoff_received`, `review` and
`review_approved`, qualify as clean merely because no cleanup obligation was
recorded yet. A busy AgentServer can exceed its supervisor shutdown deadline
before entering `terminate/2` or writing pending. Then Coordinator permits marker
removal and RuntimeLease releases the fence as clean.

Independent reproduction used the actual application, RuntimeOwner supervisor,
RuntimeLease, Coordinator, AssignmentSupervisor and AgentServer, with only Herdr
replaced by the existing FakeRunner. It reused the setup portion of the existing
runtime cleanup fixture in memory, changed its child shutdown allowance to 50 ms,
set the assignment to the legitimate `handoff_received` lifecycle state, and
blocked a correction prompt in the fake backend. Application shutdown killed the
busy BEAM child at its deadline before cleanup ran:

```text
cleanup_events: []
unclean_marker: false
close_called: false
SUCCESSOR_LEASE_ADMITTED
```

The last line came from successfully starting a real RuntimeLease on that same
isolated root after shutdown. No real pane was created or closed. Assignment
status was injected to isolate this shutdown boundary; this probe does not claim
to exercise handoff validation or full successor workflow replay.

A simpler actual RuntimeOwner/Coordinator probe with a 50 ms busy owned Task and
a handoff-received assignment independently produced the same missing receipts,
removed marker and admitted successor. The existing deadline fixture covers a
different boundary: it lets AgentServer request pending and delays that append.
It does not cover a child already blocked before its cleanup callback begins.

Required bounded correction: clean release must require positive closure evidence
for every launched execution/resource, regardless of its work verdict. Preserve
the unclean marker when a deadline or abnormal termination prevents receipt
creation. Do not infer clean resources from absence of a pending record or from
an assignment status. Keep ownership until the subtree has quiesced, and test the
pre-pending deadline through this actual topology. Full FR-10 reconciliation is
still deferred; conservative successor refusal is sufficient here.

### V3-2 / R3 — Actual Coordinator tick does not handle admission suspension

`Coordinator.Tick.process_queue/10` now correctly returns
`{:admission_suspended, :cleanup_outstanding}` and a filtered queue when resources
remain unresolved. But the actual Coordinator log-handler function at lines
672–708 has no clause for that result. Every such tick raises `:function_clause`,
falls into the broad error catch, and discards `new_state` including queue cleanup.

Independent actual Coordinator probe seeded one outstanding assignment and its
queue entry, sent `:tick`, synchronized through `Coordinator.state/0`, and read
its isolated diagnostics:

```text
tick CRASHED: error :function_clause
queue_after_tick: ["T"]
diagnostics: tick_start, tick_processed, tick_error(error=:function_clause)
```

No admission or backend call occurs, so the new capacity gate remains fail-closed.
Nevertheless, the intended suspension is an ordinary state, not a tick failure;
the queue correction never reaches runtime state and diagnostics are misleading.
The new test calls Tick directly and misses its consumer.

Required correction: handle the new result in Coordinator and verify a real tick
retains the filtered queue, emits the intended suspension diagnostic, and performs
no append/admission/launch while cleanup remains outstanding. This is a small
integration correction, not a scheduler redesign.

## Verified corrections and retained limits

- **R1 corrected for immediate containment:** destructive identity now compares
  exact pane/terminal linkage plus positive shell and foreground PIDs and both
  nonempty generation values. Native session identity is exact; fallback,
  malformed, null, PID-only, missing-generation and CWD-only evidence cannot
  authorize close. Foreground-only replacement after pre-start capture is covered
  by the supplied adapter and AgentServer tests, independently rerun. No post-error
  baseline adoption was restored.
- Unsupported/fallback/nested session values now serialize as bounded observed
  text separately from authority; the authoritative session becomes null. Tests
  exercise persisted unresolved cleanup through those paths without an exception.
- The new first-child RuntimeLease remains available while later effect children
  drain. The existing success, pending-failure, result-failure and in-gateway
  deadline fixtures pass with real production startup mode and isolated roots.
  The old five-second owner-query deadlock is resolved. V3-1 is a different missing
  evidence boundary before pending, not recurrence of that deadlock.
- Existing production boundary tests pass for owner contention, bogus/stale PID
  text, owned-BEAM kill, bridge loss, effect quiescence, clean successor startup,
  effect-free client startup and torn-history recovery. The suite uses only its
  own subprocesses/roots. No claim is made that these tests cover every arbitrary
  lease/owner instruction boundary; V3-1 remains a concrete F14 containment gap.
- Cleanup results preserve the assignment's latest independent `work_status`
  rather than its pending snapshot. Coordinator completion uses that retained
  status. Pure/replay interleaving tests for terminal and unresolved outcomes pass.
  Outstanding resources globally suspend Tick admission, including a competing
  ticket, rather than relying on dead PIDs as capacity. V3-2 concerns integrating
  that result with Coordinator, not the gate's direct decision.
- FR-03 startup reconciliation and integration remain suspended; replay retains
  outstanding cleanup in visible recovery state. CWD enumeration, hard-coded pane
  exceptions and direct AgentServer System cleanup remain removed. Cleanup uses
  the injected adapter and checked pending/result gateway.
- The destructive-path sweep still finds the typed adapter pane-close path and
  the unchanged ProcessGroup/check-trampoline signalling paths. No new CWD-based
  recovery, broad shell cleanup, CLI acceptance or activation path was introduced.
- All new fixtures are Elixir. The existing Fence Python POSIX-lock bridge is
  unchanged. The shell wrapper still allocates and deletes only its own temporary
  parent. F01–F24 routing remains intact, including FR-09/15a backend conformance,
  FR-10 reconciliation, FR-05 acceptance/activation containment, and FR-21/22
  independent CI, executable provenance and real lifecycle acceptance.
- Backend generation values remain opaque and unsupported evidence preserves
  resources. Atomic backend compare-and-close and real provider conformance remain
  explicitly unproved and downstream. Neither residual above requires those
  deferred capabilities to reproduce or fix.

## Independent commands and evidence

Read refreshed response, relevant diffs and complete RuntimeOwner/RuntimeLease
implementations, cleanup/state/tick consumers, actual runtime fixture and production
boundary tests. Reused project/contract/audit orientation from prior reviews.

```text
shasum -a 256 foundry/docs/fr-04/review-v2.md \
  foundry/docs/fr-04/review-response-v2.md
awk '/^[a-f0-9]{64}  foundry\// {print}' \
  foundry/docs/fr-04/review-response-v2.md | shasum -a 256 -c
# 20 OK, refreshed manifest only
git diff --check

# In foundry/, isolated pinned test environment:
mix test test/pramana_foundry/herdr/adapter_test.exs \
  test/pramana_foundry/agent_server_test.exs \
  test/pramana_foundry/coordinator_test.exs \
  test/pramana_foundry/transition_test.exs \
  test/pramana_foundry/runtime_startup_boundary_test.exs \
  test/pramana_foundry/daemon_recovery_test.exs \
  test/pramana_foundry/autonomous_launch_test.exs \
  test/pramana_foundry/stress_test.exs --seed 40427
# 96 passed, exit 0; the two existing stress warnings.

mix run --no-start -e '...'
# Isolated actual-owner busy-Task probe: exit 0, V3-1 result above.
# Isolated actual-application AgentServer probe: exit 0, V3-1 result above.
# Isolated actual-Coordinator tick probe: exit 0, V3-2 result above.
```

The AgentServer probe evaluated the existing fixture setup via `Code.eval_string`
without writing a modified fixture. After successful launch it set
`assignments["T-RUNTIME-CLEANUP"].status` to `handoff_received`, installed a
FakeRunner correction-prompt callback that acknowledged entry then waited for a
never-sent message, sent `{:apply_correction, %{ "findings" => []}}`, and stopped
the application after receiving that acknowledgement. It read actual checkpoint
events and marker state and attempted an isolated successor lease. The first
attempt omitted the fake runner's default ETS table used by the pre-existing
correction-prompt path and exited with a fixture error; a fresh-root repeat added
that table and yielded the recorded result. No implementation was changed to
make either probe pass or fail.

All runs used newly created `/tmp/pramana-fr04-v3-*` parents with separate TMPDIR
and operator roots, pinned Elixir 1.20.3/OTP 29.0.5 paths, and no HERDR_ENV or
COORDINATOR_TICK. Test suite used MIX_ENV=test; its existing process fixtures and
the direct application probe used MIX_ENV=dev, explicit daemon startup mode and
fresh isolated runtime overrides to exercise the real ownership topology.

No live daemon, provider, credential, production state, activation, real pane or
real pane-close was accessed. The boundary suite kills its own isolated owner
subprocess as designed; direct deadline probes let their own supervisor terminate
their own BEAM child. Only fixture leases/bridges were started/stopped. Temporary
direct-probe parents were left in place. Full-suite/live-provider acceptance is
not claimed.
