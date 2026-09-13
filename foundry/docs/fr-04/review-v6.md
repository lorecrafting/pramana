# FR-04 renewed v6 review — FAIL

2026-09-13 (Pacific/Honolulu), frozen candidate in `/tmp/pramana-fr04`,
branch `repair/fr04`, base `5c69e6c73f572e60a6c2015e955ad841bf504517`.

Verified `review-response-v5.md` SHA-256:
`3ab777b66c83dc6920f200596160e09d986b146e7f49f714ba98a1b462bf0402`.
Verified prior review SHA-256:
`35e66ef185e9943768d11268de73fab5a709a219110cf18754133c50674be4de`.
All **22** implementation/test hashes match. No implementation edit or commit.

The exact v5 identity-confusion issue is corrected. One new failure of the
clean-marker condition results from refusing every unregistered pane pending
receipt while registration still occurs only after a successful agent launch.

## Blocking regression: failed launch loses its unresolved resource

An actual AgentServer can successfully split a pane and capture its creation
identity, then receive an error/timeout from agent start. No successful launch
receipt exists, so Coordinator has not registered the pane. The new
`identity_matches_registered/3` rejects cleanup pending with
`:cleanup_resource_not_registered`. AgentServer conservatively performs no close,
but its launch-error notification contains only the cleanup error, not an owned
resource registration. Coordinator records `launch_failed` without pane identity,
inventory or an outstanding cleanup obligation. Clean shutdown then finds no owned
resources and removes the unclean marker.

Independent reproduction used the actual application, RuntimeOwner, RuntimeLease,
Coordinator, AssignmentSupervisor and AgentServer. Reused the setup portion of
`runtime_cleanup_fixture.exs` in memory, wrapping only the fake runner's `agent
start` call to return `{:error, :start_timeout}` after its normal successful split
and presentation capture. Waited for the child to exit, synchronized Coordinator
state, stopped the application, and read actual events and marker state:

```text
split pane: pane-runtime
agent start error: :start_timeout
cleanup unresolved ... {:cleanup_pending_persistence_failed,
                        :cleanup_resource_not_registered}
assignment_after_failure: %{"status" => "launch_failed"}
resource_events: []
unclean_marker: false
close_called: false
```

Exit 0. Unlike the synthetic attribution probe in v5, this follows an ordinary
launch-failure path with no injected assignment/projection state. The mocked pane
remains unresolved, but no attributable resource record survives and the marker
is cleared. This contradicts the prior B3 durable-unresolved and R2 clean-release
conditions. Tests of AgentServer launch failure inject a permissive recording
callback, so passing those tests does not establish this actual gateway path.

Required bounded correction: retain trustworthy split ownership before any start
failure can occur, or record the failed-launch resource as an explicit unresolved
observation/recovery obligation that cannot grant close authority. Keep rejecting
unregistered destructive authority and mismatched registered identities. Missing
registration must not erase evidence of a resource already created by this
execution. The actual start-error/timeout path must retain the marker and resource
identity until resolved; no full FR-10 reconciliation is required.

## Exact requested identity probes passed

Independently reran the previous two-resource production-function sequence:

```text
unregistered complete pane pending -> {:error, :cleanup_resource_not_registered}
registered developer key + sibling pane pending ->
  {:error, :cleanup_pending_resource_identity_mismatch}
conflicting duplicate registration ->
  {:error, :cleanup_resource_registration_conflict}
exact duplicate pending -> identical returned state
sibling result after exact developer pending ->
  {:error, :cleanup_result_identity_mismatch}
```

The original inventory remains intact on rejected calls. The new Coordinator
regression also checks conflicting pending against actual durable event read-back
and unchanged runtime state. Result updates now mutate only status/reason/work
status, preserving registered identity. Exact duplicate registration preserves
the existing entry.

The narrowly selected suite independently passed **36 tests**, covering transition
identity/replay, Coordinator gateway/tick behavior, actual one/two-resource
shutdown, both terminal closure orders, owner contention, bridge/process loss,
successor refusal and clean-marker conditions for successfully registered
resources. Earlier adapter identity gates, RuntimeLease ordering and FR-03
suspensions are unchanged by this correction. No CWD/destructive/CLI/activation
path was added. F01–F24 and downstream FR-09/15a/10/21/22 boundaries remain intact.

## Commands and limits

```text
shasum -a 256 foundry/docs/fr-04/review-response-v5.md \
  foundry/docs/fr-04/review-v5.md
awk '/^[a-f0-9]{64}  foundry\// {print}' \
  foundry/docs/fr-04/review-response-v5.md | shasum -a 256 -c
# All 22 OK

mix test test/pramana_foundry/transition_test.exs \
  test/pramana_foundry/coordinator_test.exs \
  test/pramana_foundry/runtime_startup_boundary_test.exs --seed 40440
# 36 passed, exit 0

mix run --no-start -e '...'
# Direct Cleanup refusal/idempotence probe: exit 0.
# Actual production-topology start-timeout probe: exit 0, regression above.
```

Every run used a fresh `/tmp/pramana-fr04-v6-*` parent, separate TMPDIR/operator
root and pinned Elixir 1.20.3/OTP 29.0.5 paths. HERDR_ENV and COORDINATOR_TICK were
unset. Tests used MIX_ENV=test; their production subprocesses and the direct
application probe used MIX_ENV=dev with explicit fresh isolated runtime overrides.
Only fake adapters were used. No live daemon/provider/credential/production state,
activation or real pane was accessed. Boundary tests operate on their own
subprocesses; direct probe roots were left in place. The full focused suite was
not repeated beyond the selected 36 tests in this narrow review. No full-suite or
live-provider acceptance is claimed.
