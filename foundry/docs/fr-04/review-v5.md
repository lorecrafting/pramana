# FR-04 renewed v5 review — FAIL

2026-09-13 (Pacific/Honolulu), frozen uncommitted candidate in
`/tmp/pramana-fr04`, branch `repair/fr04`, base
`5c69e6c73f572e60a6c2015e955ad841bf504517`.

Verified `review-response-v4.md` SHA-256:
`861349bbb97a25538f6a94a3996d22f288b54fe24228edc31e72c80938d4daee`.
Verified prior `review-v4.md` SHA-256:
`9bcc9d294c27bd2ad42462442e460081b8d3ba03222d970bd2dddb38ab81db29`.
All **22** current implementation/test manifest hashes match. No implementation
edits or commits were made. The requested focused suite independently passes
**105 tests**, including the actual two-resource runtime cases.

## Remaining blocker: pending can rewrite registered ownership

The inventory now retains developer and reviewer separately, and the ordinary
two-role deadline is corrected. However, `Cleanup.apply_pending/2` does not verify
its resource identity against the existing `cleanup_resources[role:execution_id]`.
It calls `put_resource_if_owned`, which merges the pending attributes into that
entry, replacing its pane, terminal, session and presentation identity.
`apply_result/2` then compares only against the rewritten pending record. Thus a
misattributed sibling pending/result pair can settle the wrong registered owner.
`register_resource/2` likewise unconditionally merges an existing key rather than
rejecting conflicting resource identity.

Independent direct production-function probe, using complete valid process
incarnation maps and no backend or application startup:

```text
register developer:D -> dev-pane
register reviewer:R -> review-pane

apply_pending(reviewer resource identity, role=developer, execution_id=D) -> ok
apply_result(same attributes, status=closed) -> ok
apply_pending(reviewer:R, its correct review-pane identity) -> ok
apply_result(reviewer:R, status=closed) -> ok

inventory: %{
  "developer:D" => {"review-pane", "closed"},
  "reviewer:R" => {"review-pane", "closed"}
}
all_owned_resources_terminal? -> true
```

No receipt closed `dev-pane`; the inventory lost it. The new sibling test changes
the **result** after a correct developer pending record, which is rejected. It
does not change the pending attribution relative to the already registered
resource, which is accepted.

Evidence limit: this is a synthetic malformed/stale attribution sequence through
the actual projection functions, not an observed normal AgentServer scheduling
interleaving or a claim of a new public attack surface. It directly tests the
requested rule that a sibling/stale receipt cannot settle another entry. The
checked Coordinator gateway and replay call these same functions, so append
checking does not supply the missing identity comparison.

Required bounded correction: once a role/execution resource is registered, retain
its authoritative identity. Pending and result updates must match it as well as
each other. An exact repeated registration can be idempotent; conflicting
registration must preserve the earlier resource and refuse or retain explicit
uncertainty. Keep bounded observed-session diagnostics separate from the identity
comparison. Failed launches without a prior registered resource may still create
an attributable pending entry. Test a conflicting pending/result pair and a
conflicting duplicate registration, then prove the original resource remains
nonterminal. This is integrity of the new inventory, not FR-10 reconciliation.

## Verified corrections

- Successful AgentServer receipts include role/execution identity; checked
  `pane_created` events and replay retain both role resources. Public status
  exposes the inventory. Normal sibling cleanup no longer overwrites the other
  entry.
- The actual two-AgentServer deadline fixture passes: developer blocked before
  pending plus reviewer closure retains developer `owned`, reviewer `closed`, and
  the unclean marker. Both explicit closure orders become clean only after both
  terminal receipts. Duplicate terminal result without pending is refused.
- Prior exact shell/foreground incarnation and native-session gates, pre-start
  capture, weak/malformed/fallback identity refusal, injected-adapter-only cleanup,
  pending/result durability and failed-append containment remain unchanged and
  covered by the independently rerun tests.
- RuntimeLease remains responsive during bounded shutdown; owner contention,
  bridge/owned-process-loss, successor refusal, shutdown deadlines and recovery
  fixtures pass. The older ownership-query deadlock is not reintroduced.
- Latest work verdict survives cleanup/replay interleavings. Actual Coordinator
  consumes Tick's admission-suspended result, retains filtered state and registry,
  reschedules and does not launch or emit tick-error. Outstanding obligations
  continue to suspend admission globally.
- FR-03 startup reconciliation and integration remain suspended. No CWD cleanup,
  hard-coded pane exceptions, default System cleanup, CLI acceptance or activation
  path was added. New fixtures remain model-free Elixir. The unchanged existing
  Fence bridge is the only Python dependency in this ownership boundary.
- F01–F24 routing and deferred FR-09/15a backend conformance, FR-10 reconciliation,
  FR-05 acceptance/activation, and FR-21/22 lifecycle/CI/provenance obligations remain
  intact. Backend compare-and-close remains non-atomic and explicitly unproved.

## Independent commands and limits

```text
shasum -a 256 foundry/docs/fr-04/review-response-v4.md \
  foundry/docs/fr-04/review-v4.md
awk '/^[a-f0-9]{64}  foundry\// {print}' \
  foundry/docs/fr-04/review-response-v4.md | shasum -a 256 -c
# All 22 OK
git status --short
git diff --check

# From foundry/, isolated pinned environment:
mix test test/pramana_foundry/herdr/adapter_test.exs \
  test/pramana_foundry/agent_server_test.exs \
  test/pramana_foundry/coordinator_test.exs \
  test/pramana_foundry/transition_test.exs \
  test/pramana_foundry/runtime_startup_boundary_test.exs \
  test/pramana_foundry/daemon_recovery_test.exs \
  test/pramana_foundry/autonomous_launch_test.exs \
  test/pramana_foundry/stress_test.exs \
  test/pramana_foundry/status/status_test.exs --seed 40437
# 105 passed, exit 0; two existing stress warnings.

mix run --no-start -e '...'
# Actual Cleanup sibling-attribution probe described above: exit 0.
```

The direct probe constructed two maps with distinct pane/terminal/agent names,
matching linked shell/foreground process identities, nil session (valid fresh-pane
identity), and distinct role/execution IDs. It used `Map.merge` to retain the
reviewer resource fields while changing only role/execution to the developer key,
then called `register_resource`, `apply_pending`, `apply_result`, and
`all_owned_resources_terminal?` in the order shown above.

Every run used a fresh `/tmp/pramana-fr04-v5-*` parent, separate TMPDIR/operator
root, pinned Elixir 1.20.3/OTP 29.0.5 paths, and no HERDR_ENV or COORDINATOR_TICK.
The focused test application and its existing production-boundary subprocesses
used only isolated runtime roots. The direct probe used `--no-start` and launched
no process or backend. No live daemon/provider/credential/production state,
activation or real pane was accessed. Boundary tests operate on their own
subprocesses as documented. Direct-probe roots were left in place. No full-suite
or live-provider acceptance is claimed.
