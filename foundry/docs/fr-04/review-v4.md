# FR-04 renewed v4 review — FAIL

2026-09-13 (Pacific/Honolulu), frozen uncommitted candidate in
`/tmp/pramana-fr04`, branch `repair/fr04`, base
`5c69e6c73f572e60a6c2015e955ad841bf504517`.

Verified response artifact is **`review-response-v3.md`** (the requested short
name `response-v3.md` does not exist), SHA-256
`5ecccd64bc98f7421364665a2b35fed9d5d57d7fd93f4e6124604a0bf1ea09a9`.
Prior review SHA-256 matches:
`131b848c17fb95308b501f12b9752e97592abd32cbdaa891d2c54ad37fcc8fa2`.
All **20** implementation/test manifest entries independently match. Current
status contains those intended modified/new implementation/test paths and the
review artifacts. No implementation edits or commit were made by this reviewer.

The two named fixes work for their new fixtures, and the focused suite passes
**99 tests**. One ownership case still defeats the clean-release requirement.

## Blocking residual: closure of the last role hides the earlier role's resource

`Cleanup.all_owned_resources_terminal?/1` checks each assignment's single current
pane/cleanup identity against its last result. But
`Coordinator.handle_agent_launched/2` overwrites those same fields when a reviewer
launches for that assignment. A developer and reviewer can both still own panes.
Until cleanup begins, the earlier developer has no entry in
`cleanup_obligations`; its successful launch identity has been replaced in the
assignment projection. A closed reviewer therefore satisfies the new predicate
even when the developer dies before writing pending and never closes its pane.

This is the same V3-1 requirement—positive closure of every owned resource before
marker removal—under the existing two-role execution path. It is also the shared
assignment-pane problem identified in audit F05, not a requirement to implement
full FR-10 reconciliation.

### Independent actual-runtime reproduction

Reused the setup portion of `runtime_cleanup_fixture.exs` in memory, without
editing the fixture or implementation:

1. Started its actual developer AgentServer on mocked `pane-runtime` under the
   actual application, RuntimeOwner, RuntimeLease, Coordinator and
   AssignmentSupervisor. Developer shutdown allowance was 50 ms.
2. Started a second actual AgentServer with role reviewer and a distinct run,
   agent/session, pane, terminal, shell and foreground incarnation. Its backend
   used a separate existing FakeRunner ETS table and exact close evidence.
3. Set the assignment to the legitimate `handoff_received` lifecycle state to
   isolate the shutdown boundary; handoff validation itself was not under test.
4. Blocked the developer's correction prompt in the fake runner before cleanup
   could begin, then stopped the application. The reviewer drained normally;
   the developer exceeded its deadline and wrote no cleanup receipt.

Observed output (exit 0):

```text
Agent launched ... pane=pane-runtime name=pramana-dev-run-runt
Agent launched ... pane=review-pane name=pramana-review-review
current_assignment_pane: "review-pane"
cleaned up owned pane review-pane
cleanup_receipts: [
  {"cleanup_pending", "reviewer", "review-pane"},
  {"cleanup_result", "reviewer", "review-pane"}
]
developer_closed: false
unclean_marker: false
```

Both resources were created through actual AgentServer launch code and reported
through the actual Coordinator launch handler. No real Herdr/pane/provider was
used. The absence of developer closure is independently corroborated by no
developer cleanup events and no developer close argv. Unlike the original
single-resource deadline, the newer role supplies valid terminal evidence for
its own resource, which incorrectly authorizes removing the marker for both.

### Required bounded correction

Retain ownership separately for every launched role/execution until its own exact
terminal cleanup result is durable. A later pane-created event or another role's
result must not erase the earlier resource. Alternatively, conservatively retain
the marker whenever the legacy projection cannot prove all historical launched
resources closed. Registering a small ownership inventory at launch and resolving
it by exact identity is containment; automatic restart reconciliation remains
FR-10. Include this two-AgentServer pre-pending deadline test, both role close
orders, and stale results from one execution against the other.

## Verified fixes and regressions

- The new clean-release predicate is independent of work status for the currently
  stored resource. Missing closure across dispatched, handoff, review, correction,
  completed and failed statuses is refused, and stale/mismatched resource results
  are refused in the supplied matrix. The actual single-AgentServer 50 ms
  pre-pending deadline fixture now retains the marker. The residual above concerns
  the missing earlier resource, not failure of those comparisons.
- Coordinator now consumes `{:admission_suspended, :cleanup_outstanding}`,
  preserves Tick's filtered state/registry, emits `tick_admission_suspended`, and
  reschedules without a checkpoint/backend call/launch or `tick_error`. Its real
  Coordinator integration test independently passes.
- Prior B1/R1 identity refusals, shell and foreground generation comparison,
  exact native-session requirement, pre-start capture, missing/fallback/malformed
  evidence preservation and injected-adapter cleanup remain intact.
- Prior B3/R2 ordinary checked pending/result sequencing, append-failure handling,
  fallback observation serialization, responsive RuntimeLease topology,
  owner/bridge-loss tests and bounded drain fixtures pass. There is no recurrence
  of the former owner-query deadlock.
- Latest work verdict survives cleanup interleavings and replay. Outstanding
  obligations suspend actual Tick admission globally. The residual concerns a
  resource erased before an obligation exists, so that global gate cannot see it.
- FR-03 startup reconciliation/integration suspension, recovery behavior and
  ownership ordering remain intact. No CWD enumeration, hard-coded exceptions,
  direct System pane-close or broad fixture cleanup has been restored. The known
  typed close and pre-existing ProcessGroup/check-trampoline signal paths remain
  the only destructive paths identified by the prior all-lib/bin sweep; no new
  executable path was introduced in this correction.
- F01–F24 routing remains unchanged. Full FR-10 reconciliation, FR-09/15a protected
  backend conformance and atomic compare-and-close, FR-05 acceptance/activation,
  and FR-21/22 real lifecycle/CI/provenance remain outside this containment verdict.

## Commands, scope and limitations

```text
shasum -a 256 foundry/docs/fr-04/review-response-v3.md \
  foundry/docs/fr-04/review-v3.md
awk '/^[a-f0-9]{64}  foundry\// {print}' \
  foundry/docs/fr-04/review-response-v3.md | shasum -a 256 -c
# All 20 OK
git status --short

# From foundry/, isolated pinned environment:
mix test test/pramana_foundry/herdr/adapter_test.exs \
  test/pramana_foundry/agent_server_test.exs \
  test/pramana_foundry/coordinator_test.exs \
  test/pramana_foundry/transition_test.exs \
  test/pramana_foundry/runtime_startup_boundary_test.exs \
  test/pramana_foundry/daemon_recovery_test.exs \
  test/pramana_foundry/autonomous_launch_test.exs \
  test/pramana_foundry/stress_test.exs --seed 40433
# 99 passed, exit 0; two existing stress warnings.

mix run --no-start -e '...'
# In-memory two-role runtime fixture described above; exit 0.
```

The first probe attempt had an Elixir expression-parenthesis error before any
application startup. The second attempted to recreate a default ETS table already
created by the refreshed fixture. A fresh-root third attempt conditionally reused
that table and produced the recorded result. No source file was changed to correct
these probe-only mistakes.

All runs used fresh `/tmp/pramana-fr04-v4-*` parents, separate TMPDIR/operator
roots, pinned Elixir 1.20.3/OTP 29.0.5 and no HERDR_ENV or COORDINATOR_TICK. The
focused suite used MIX_ENV=test; its production-boundary subprocesses and the
direct probe used MIX_ENV=dev with explicit fresh isolated runtime overrides.
Only fake Herdr adapters were used. The boundary tests operate on their own
subprocesses; direct probes let the owned supervisor enforce its child deadline.
No live daemon/provider/credential/production state/activation/real pane was
accessed. Direct-probe temporary parents were left in place. No full-suite or
live-provider acceptance is claimed.
