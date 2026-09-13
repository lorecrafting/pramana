# FR-04 response to renewed review R1–R3

Date: 2026-09-13 (Pacific/Honolulu)  
Base: `5c69e6c73f572e60a6c2015e955ad841bf504517`  
Branch/worktree: `repair/fr04`, `/tmp/pramana-fr04`  
State: uncommitted correction candidate for renewed independent review

This response addresses only R1–R3 in `foundry/docs/fr-04/review-v2.md`
(SHA-256 `3e145afbec9f725222ef8913ef565f7ad49d5f6f268fd4b2301b7b1c8a6247c2`).
The earlier removal of CWD ownership inference and hard-coded pane exceptions remains
intact. FR-03 startup reconciliation and integration remain suspended. No CLI or
FR-05 acceptance/activation behavior was added.

## R1 — foreground-incarnation authority

The adapter's stable destructive-cleanup contract now requires and exact-compares
all of `pane_id`, `terminal_id`, positive `shell_pid`, opaque non-empty shell
`started_at`, positive `foreground_pid`, and opaque non-empty
`foreground_started_at`. Agent cleanup additionally requires the exact native
agent session. Missing, malformed, changed, fallback, recycled or replacement
evidence returns unresolved without issuing `pane close`.

The presentation is still captured immediately after split and before agent start.
The start-error test now replaces only the foreground PID/generation while leaving
the shell incarnation unchanged and proves no close. Adapter tests cover an
equivalent later foreground replacement and all earlier pane, terminal, session,
missing-incarnation, CWD and recycled-ID cases.

## R2 — responsive fence and bounded shutdown drain

`RuntimeOwner` is now a `:rest_for_one` supervisor. Its first child is the dedicated
`RuntimeLease` GenServer, which owns the `Fence` and unclean marker but no effect
subtree. Registry, Coordinator, AssignmentSupervisor and remaining effects follow
it. Reverse shutdown drains AgentServer cleanup calls through the still-responsive
Coordinator and lease; Coordinator authorizes marker removal only after its state
has no outstanding cleanup. The lease releases the fence last.

Abnormal lease loss retains the unclean marker and `:rest_for_one` stops all later
effects. Automatic successor startup is refused. Coordinator recovery inhibits a
clean release. The Coordinator traps shutdown exits so its final safety decision is
actually executed.

`runtime_cleanup_fixture.exs` exercises the actual application topology with an
injected model-free adapter. It proves:

- success appends checked pending and result receipts before close and clean release;
- pending append failure prevents close and retains the unclean marker;
- result append failure leaves the durable pending receipt and retains the marker;
- a 50 ms AgentServer shutdown deadline cannot deadlock the fence query, does not
  close, and leaves the eventual pending receipt plus unclean marker;
- every shutdown finishes below the test's two-second bound.

The pre-existing production-boundary tests also revalidate single ownership, clean
successor startup, kill/bridge-loss refusal, effect-subtree quiescence and recovery
guards. Fallback and nested malformed sessions are now serialized only as bounded
`observed_session` text while the authoritative `session` remains null. Their
AgentServer-to-Coordinator pending/result path persists an unresolved obligation
without raising or closing.

## R3 — independent verdict and retained capacity

`Cleanup.apply_result/2` restores the assignment's latest `work_status`, never the
pending event's stale snapshot. Coordinator completion decisions consult that same
independent status. Replay tests cover both unresolved and terminal cleanup results
interleaved after a newer validated work outcome.

Pending cleanup removes the affected ticket from the queue. The actual
`Coordinator.Tick.process_queue/10` admission path removes cleanup-blocked queue
entries and conservatively suspends all admission while any assignment has an
outstanding cleanup obligation. Thus a dead execution with an unresolved resource
cannot release effective capacity or admit a competing ticket. Direct transition,
replay, queued-entry and competing-ticket tests cover these cases.

## Isolated evidence

All executable runs used fresh roots/TMPDIR, an explicit separate operator root,
unset `HERDR_ENV`, `COORDINATOR_TICK`, `PRAMANA_RUNTIME_ROOT` and
`PRAMANA_RUNTIME_ROOT_FRESH`, and PATH pinned to Elixir 1.20.3 / OTP 29. No real
Herdr, provider, daemon, pane, credential, model or activation was used.

```text
# /tmp/pramana-fr04-r3-runtime.bnt5Qh
mix test test/pramana_foundry/runtime_startup_boundary_test.exs --seed 40424
9 passed; exit 0

# /tmp/pramana-fr04-r3-freeze.PM3dzs
mix test test/pramana_foundry/herdr/adapter_test.exs \
  test/pramana_foundry/agent_server_test.exs \
  test/pramana_foundry/coordinator_test.exs \
  test/pramana_foundry/transition_test.exs \
  test/pramana_foundry/runtime_startup_boundary_test.exs \
  test/pramana_foundry/daemon_recovery_test.exs \
  test/pramana_foundry/autonomous_launch_test.exs \
  test/pramana_foundry/stress_test.exs --seed 40428
96 passed; exit 0

# /tmp/pramana-fr04-r3-compile.hxtBkc
MIX_ENV=test mix compile --warnings-as-errors
exit 0

bash -n bin/test_daemon_recovery.sh
bash bin/test_daemon_recovery.sh
1 passed; exit 0

git diff --check
exit 0
```

The focused run reports only the two pre-existing `stress_test.exs` warnings
(unused `proj`; unused private default argument). The isolated daemon-recovery
fixture byte- and SHA-256-compares an unrelated JSONL file after cleanup. Its shell
wrapper is the existing boundary and operates only inside its generated temporary
parent.

## Frozen implementation/test hashes

```text
bbf27c265bfa56236c8884f04355432ab1156802fbe36924b723697a2c50c4cd  foundry/bin/test_daemon_recovery.sh
9eeb87a53ac881d0e20f409241aeff1384c64bff57bf65d74e919efdb0f54685  foundry/lib/pramana_foundry/agent_server.ex
2acd833e4c3bbffa87d110d6c986dc699ee98469cb884b87fbd9dfa8fdeb3786  foundry/lib/pramana_foundry/application.ex
11002ab8f05a509489f131ef8600a46b34343cf7f019fff043e169a97c1cf1a4  foundry/lib/pramana_foundry/cleanup.ex
f22ad367fc0eea879ca7ca6eedd46c5496fc7db3b743f91fe9cca3338d2a3329  foundry/lib/pramana_foundry/coordinator.ex
2877c7f5953e9a6f6ca720bae2e8b5facb6265ffa06b6536073ebd8affe2ada7  foundry/lib/pramana_foundry/coordinator/tick.ex
404406087170a1e37fcaaa3a6bc0ea9528cc659a689260ac2664bf1e5e846189  foundry/lib/pramana_foundry/herdr/adapter.ex
5f8f08a72a8f4146860179de61dbc65b00ff741ed1713831b3322bc6f51c97d5  foundry/lib/pramana_foundry/herdr/identity.ex
80e8cb54aea4e47a15d2840e4177e2adcdf07ec86de231a23cd27b1a81a3ff39  foundry/lib/pramana_foundry/runtime_lease.ex
00eea833c442ac19987e341733e513610e50e74a2aef11c484bf85e646150e2d  foundry/lib/pramana_foundry/runtime_owner.ex
a0e2cd6645f20c26c673d2005643cfb959fb248b2e92f2551ad5edef406bbeed  foundry/lib/pramana_foundry/transition.ex
39616ccbcb621ba715d29724068d8724300ee026128261bb1a0e97510a6637f2  foundry/test/pramana_foundry/agent_server_test.exs
d553535ae62e5d4687d95b4f9b8d4096a870fd163923a33e95df9a585f3aaceb  foundry/test/pramana_foundry/autonomous_launch_test.exs
9108c64bdb8c6a899c6788a1894c2065f4b46c3e26d796a6df4ef6c6fe2efb9d  foundry/test/pramana_foundry/coordinator_test.exs
3b4977469a61f1b21ab68ea673411197238bf5558bca160bd3c6778154714776  foundry/test/pramana_foundry/daemon_recovery_test.exs
931843cb63a32c7050b58c8cf32caf89cc66ce9ba42cdf50fc74b5be7a5656e2  foundry/test/pramana_foundry/herdr/adapter_test.exs
a7ac2e3fa07b0a7801afd1f3da4d5f87932645511b180f93a494c8f18080cb3b  foundry/test/pramana_foundry/runtime_startup_boundary_test.exs
8a4776b0234c391d05caadf8816cefc39af32dd458478e76f49ae1cf48347bdb  foundry/test/pramana_foundry/stress_test.exs
92565598306cec4e637d3758e0710705e81296c74f32c9928343da3aca9de18e  foundry/test/pramana_foundry/transition_test.exs
2681be87e90907e5bc1d1cb2cdd8091f735f46db00b1b3e02b500f715ba869f4  foundry/test/support/runtime_cleanup_fixture.exs
```

## Deliberate limitations

- Backend generation values remain opaque; unsupported backends cannot authorize
  destructive cleanup and therefore preserve the resource.
- The adapter still cannot make reinspection and close atomic. Backend atomic
  compare-and-close/conformance remains downstream.
- This is bounded containment, durable projection and shutdown drain, not FR-10
  automatic reconciliation. Restart with an outstanding obligation remains visibly
  recovery-required.
- No live lifecycle/provider claim is made. FR-03's suspended startup reconciliation
  and integration are not restored.
