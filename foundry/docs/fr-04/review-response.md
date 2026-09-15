# FR-04 response to independent review B1–B4

Date: 2026-09-12 (Pacific/Honolulu)  
Base: `5c69e6c73f572e60a6c2015e955ad841bf504517`  
Branch/worktree: `repair/fr04`, `/tmp/pramana-fr04`  
State: uncommitted correction candidate for renewed independent review

This response addresses only B1–B4 in `foundry/docs/fr-04/review.md` (review SHA-256
`369db5d8c513034d4a2aba9eb616177ef03b281f2eb14df81877fb1605d0e124`).
The earlier removal of CWD inference, pane-list cleanup and hard-coded pane exceptions
remains intact. FR-03 startup reconciliation and integration remain suspended; no
FR-05 acceptance/activation or CLI behavior was added.

## B1 — positive incarnation and native-session evidence

Destructive cleanup now has a documented minimum backend contract. Pane process
evidence must contain the exact inspected `pane_id` and `terminal_id`, a positive
`shell_pid`, and a non-empty opaque backend `started_at` generation. The adapter
normalizes and compares only these stable identity fields. Missing-generation,
PID-only, null, CWD-only, malformed, recycled-pane and replacement-generation
responses return unresolved and never issue `pane close`.

Agent cleanup additionally requires an exact native `agent_session` token with a
non-empty value, matching terminal and agent kind. The non-destructive terminal
fallback remains available to observation/prompt code but is rejected by the
destructive cleanup gate. Fresh-pane cleanup is the only pre-session case and is
limited to an exact pre-agent process incarnation.

Evidence: `Herdr.AdapterTest` covers exact close; missing/PID-only/null/CWD/malformed
incarnation; name/pane/terminal/session mismatch; terminal fallback; foreign pane
sharing the same CWD; and a recycled process with the same PID but changed generation.

## B2 — creation baseline before ambiguous start

`AgentServer` captures pane and process presentation immediately after `pane split`
and before invoking `agent start`. Start error/timeout cleanup re-inspects against
that pre-start baseline; it never captures or adopts a post-error occupant. A fixture
changes `started_at` during the start call, returns timeout, and proves the replacement
survives with `:pane_process_identity_changed` and no close argv.

## B3 — durable pending/result evidence on every cleanup branch

Every `cleanup_pane/3` call now records an attributable `cleanup_pending` through the
Coordinator checked gateway before attempting close, then records `cleanup_result`.
The identity includes task, execution, role, agent name, pane, terminal, native
session and pre-start presentation/process incarnation. Accepted and rejected
`submit_review`, work/review timeout, launch failure, handoff rejection, explicit
review approval, crash and supervisor shutdown all use this path.

If pending persistence fails, the adapter is not called. If result persistence fails,
the already-durable pending obligation remains outstanding. AgentServer traps exits,
and application child order now stops the AssignmentSupervisor before Coordinator,
so bounded shutdown leaves the checked gateway available while terminate callbacks
drain. The no-pane split-failure case records pending plus `not_required` without a
backend close.

Evidence includes accepted/rejected review branch tests, a supervisor-shutdown
pending/result test, launch failure tests with injected pending and result failures,
a real `Checkpoint.append/6` plus read-back/restart projection test, and a Coordinator
append-failure recovery test.

## B4 — outstanding cleanup blocks independently of work verdict

New `PramanaFoundry.Cleanup` transitions persist obligations keyed by role and
execution. A result can resolve an obligation only when all owner/resource identity
fields exactly match its pending record. Pending/unresolved assignments remain
`cleanup_pending`/`cleanup_blocked`, are absent from the ordinary retry queue, and
retain their registry slot during the running VM. Completion still records the
independent `work_status` (for example `review`) without presenting cleanup as done.

Launch failure and crash do not increment ordinary retry counters when cleanup is
outstanding. Replay reconstructs the obligation. On startup, FR-03 reconciliation
remains suspended, but the Coordinator now preserves the replayed blocked assignment
inside `recovery_required` instead of replacing it with an empty state; this prevents
ordinary dispatch after restart without implementing FR-10 reconciliation.

## Isolated evidence

All Mix commands used a fresh `mktemp -d` parent, separate `TMPDIR`, explicit
`PRAMANA_OPERATOR_RUNTIME_ROOT`, unset `HERDR_ENV`, `COORDINATOR_TICK`,
`PRAMANA_RUNTIME_ROOT` and `PRAMANA_RUNTIME_ROOT_FRESH`, and PATH pinned to Elixir
1.20.3 / OTP 29. No real Herdr, provider, daemon, pane, process signal, credentials,
model or activation was used.

```text
# /tmp/pramana-fr04-suite-freeze.p0pTF2
mix test test/pramana_foundry/herdr/adapter_test.exs \
  test/pramana_foundry/agent_server_test.exs \
  test/pramana_foundry/coordinator_test.exs \
  test/pramana_foundry/transition_test.exs \
  test/pramana_foundry/daemon_recovery_test.exs \
  test/pramana_foundry/autonomous_launch_test.exs \
  test/pramana_foundry/stress_test.exs --seed 40423
83 passed; exit 0

# /tmp/pramana-fr04-compile-final2.nCAJrK
MIX_ENV=test mix compile --warnings-as-errors
exit 0

bash bin/test_daemon_recovery.sh
1 passed; exit 0

bash -n bin/test_daemon_recovery.sh
git diff --check
exit 0
```

The compatibility run reports only two pre-existing warnings in `stress_test.exs`
(unused `proj`; unused private default argument). The production compile passes
warnings-as-errors. The isolated daemon-recovery fixture byte- and SHA-256-compares
an unrelated JSONL file after exact mocked cleanup; its wrapper removes only its own
`mktemp` parent.

## Frozen implementation/test hashes

```text
bbf27c265bfa56236c8884f04355432ab1156802fbe36924b723697a2c50c4cd  foundry/bin/test_daemon_recovery.sh
7b27c3743d2b920aea433b44910c80c0b4b43a085459f9ce203b80da53384856  foundry/lib/pramana_foundry/agent_server.ex
2acd833e4c3bbffa87d110d6c986dc699ee98469cb884b87fbd9dfa8fdeb3786  foundry/lib/pramana_foundry/application.ex
88258fdf40ee0690287dbd454654d63e9f7c826ccd2e9e3fd360d98081f0fc16  foundry/lib/pramana_foundry/cleanup.ex
1dc6c75649bee56f9ffdf593d4318879a0c36937e303cb355c246dabab68a61d  foundry/lib/pramana_foundry/coordinator.ex
75e4fc7c91f63e3e392ed829e03d2858a9a4f99439c7486864ccad1c35bc8e2e  foundry/lib/pramana_foundry/herdr/adapter.ex
5f8f08a72a8f4146860179de61dbc65b00ff741ed1713831b3322bc6f51c97d5  foundry/lib/pramana_foundry/herdr/identity.ex
a0e2cd6645f20c26c673d2005643cfb959fb248b2e92f2551ad5edef406bbeed  foundry/lib/pramana_foundry/transition.ex
561237108b410387aea874465a688ecdddc32cece7b57a4aa42d1689cff9ff39  foundry/test/pramana_foundry/agent_server_test.exs
68dbc28f780658635dbec2e7eb506c43988f82a99fa9e67b795b52753e8fb0b0  foundry/test/pramana_foundry/autonomous_launch_test.exs
da911b7a0295997456ba4a68eb2072300e926f895c11d9057062972c85e81e74  foundry/test/pramana_foundry/coordinator_test.exs
22dd480896487c62549b5bd0170263f3d88fb6ad9e823394ececd4931f26bc4b  foundry/test/pramana_foundry/daemon_recovery_test.exs
c31277bd8590bbf42f2a4aaabe73095f3f0ff930200b8ffc81da7f28f27f8247  foundry/test/pramana_foundry/herdr/adapter_test.exs
3ada1d0b276d613fdaf6fc706c2b2d2b43de0bfbc36c4f662fdf9a04f750da71  foundry/test/pramana_foundry/stress_test.exs
b18a212eaa5e542cda15e3ccf5a47b4cf2febb2c162c7b90ee04418a723c9095  foundry/test/pramana_foundry/transition_test.exs
```

## Limitations retained intentionally

- `started_at` is treated as opaque backend generation evidence; this legacy layer
  does not invent it. Backends that omit it are unsupported for destructive cleanup
  and therefore preserve the resource.
- This is bounded containment, projection and shutdown draining, not FR-10 automatic
  reconciliation. Restart with an outstanding cleanup obligation halts in visible
  `recovery_required` with the obligation preserved.
- No atomic backend compare-and-close primitive was established here. An exact
  reinspection precedes close, but backend atomicity/conformance remains downstream.
- No live lifecycle or provider claim is made. Formatter expansion remains in the
  legacy Coordinator/AgentServer-oriented diff; review may use whitespace-insensitive
  diff alongside the exact hashes.
