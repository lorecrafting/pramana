# FR-04 response to v3 review residuals

Date: 2026-09-13 (Pacific/Honolulu)  
Base: `5c69e6c73f572e60a6c2015e955ad841bf504517`  
Branch/worktree: `repair/fr04`, `/tmp/pramana-fr04`  
State: final uncommitted candidate for independent review

This response addresses only the two residuals in `review-v3.md`, SHA-256
`131b848c17fb95308b501f12b9752e97592abd32cbdaa891d2c54ad37fcc8fa2`.
All implementation and test edits were complete, formatted and tested before the
manifest below was generated. No CLI, FR-05 activation, FR-10 reconciliation or
FR-03 suspended startup reconciliation/integration was added.

## V3-1 — status-independent clean release

Fence-marker removal now requires positive terminal cleanup evidence for every
assignment carrying a persisted owned resource identity. The decision is independent
of work status. Pane, terminal, agent, cleanup identity or presentation identity makes
the assignment owned; absence of pending evidence is never treated as closure. The
terminal result must match the current pane, terminal, agent, presentation and native
session identity, so a stale close for a replaced execution also cannot authorize
release. Any outstanding obligation, missing result, unresolved result, mismatched
result, recovery state or pre-pending child kill retains the unclean marker.

The status matrix covers `dispatched`, `handoff_received`, `review`,
`review_approved`, `correcting`, `completed` and `failed`, both without closure and
with exact terminal closure, plus a stale/recycled result. The production fixture now
also runs the reviewer reproduction boundary: an actual AgentServer reaches a blocked
correction prompt under the actual Coordinator + AssignmentSupervisor + RuntimeOwner
topology, has a 50 ms shutdown allowance, writes no cleanup receipt, performs no
close, and leaves the marker. All earlier lease-cycle and successor-refusal tests
remain passing.

## V3-2 — ordinary Coordinator admission suspension

Coordinator now explicitly consumes
`{:admission_suspended, :cleanup_outstanding}`. It retains Tick's filtered queue and
registry, schedules the next tick normally, emits a structured
`tick_admission_suspended` diagnostic, and does not append a checkpoint, call the
backend, launch a child or emit `tick_error`. The integration test sends `:tick` to
the real Coordinator with one blocked and one competing ticket and verifies all of
those effects rather than calling Tick alone.

## Isolated evidence

Every run used fresh TMPDIR/operator roots, explicit Elixir 1.20.3 / OTP 29 paths,
and unset `HERDR_ENV`, `COORDINATOR_TICK`, `PRAMANA_RUNTIME_ROOT` and
`PRAMANA_RUNTIME_ROOT_FRESH`. Fixtures were model-free; no real Herdr, provider,
daemon, pane, credential, model, production state or activation was accessed.

```text
# /tmp/pramana-fr04-v3-runtime.48yEew
mix test test/pramana_foundry/runtime_startup_boundary_test.exs --seed 40430
10 passed; exit 0

# /tmp/pramana-fr04-v3-freeze.OXoxNi
mix test test/pramana_foundry/herdr/adapter_test.exs \
  test/pramana_foundry/agent_server_test.exs \
  test/pramana_foundry/coordinator_test.exs \
  test/pramana_foundry/transition_test.exs \
  test/pramana_foundry/runtime_startup_boundary_test.exs \
  test/pramana_foundry/daemon_recovery_test.exs \
  test/pramana_foundry/autonomous_launch_test.exs \
  test/pramana_foundry/stress_test.exs --seed 40433
99 passed; exit 0

# /tmp/pramana-fr04-v3-compile.uKvVBQ
MIX_ENV=test mix compile --force --warnings-as-errors
76 files compiled; exit 0

bash -n bin/test_daemon_recovery.sh
bash bin/test_daemon_recovery.sh
1 passed; exit 0

git diff --check
exit 0
```

The focused suite reports only the two pre-existing `stress_test.exs` warnings
(unused `proj`; unused private default argument). The daemon fixture remains isolated
and byte/SHA-compares an unrelated JSONL file after cleanup.

## Final implementation/test manifest

```text
bbf27c265bfa56236c8884f04355432ab1156802fbe36924b723697a2c50c4cd  foundry/bin/test_daemon_recovery.sh
9eeb87a53ac881d0e20f409241aeff1384c64bff57bf65d74e919efdb0f54685  foundry/lib/pramana_foundry/agent_server.ex
2acd833e4c3bbffa87d110d6c986dc699ee98469cb884b87fbd9dfa8fdeb3786  foundry/lib/pramana_foundry/application.ex
7e80e2d8e4de60bda1b8ae115106b1b1060aefd455d9a56473a85382fbb7de42  foundry/lib/pramana_foundry/cleanup.ex
62009c11457b364d9423bc1667300d7ec656cab540bdfeb9fb7d757e3ff0ac07  foundry/lib/pramana_foundry/coordinator.ex
2877c7f5953e9a6f6ca720bae2e8b5facb6265ffa06b6536073ebd8affe2ada7  foundry/lib/pramana_foundry/coordinator/tick.ex
404406087170a1e37fcaaa3a6bc0ea9528cc659a689260ac2664bf1e5e846189  foundry/lib/pramana_foundry/herdr/adapter.ex
5f8f08a72a8f4146860179de61dbc65b00ff741ed1713831b3322bc6f51c97d5  foundry/lib/pramana_foundry/herdr/identity.ex
80e8cb54aea4e47a15d2840e4177e2adcdf07ec86de231a23cd27b1a81a3ff39  foundry/lib/pramana_foundry/runtime_lease.ex
00eea833c442ac19987e341733e513610e50e74a2aef11c484bf85e646150e2d  foundry/lib/pramana_foundry/runtime_owner.ex
a0e2cd6645f20c26c673d2005643cfb959fb248b2e92f2551ad5edef406bbeed  foundry/lib/pramana_foundry/transition.ex
39616ccbcb621ba715d29724068d8724300ee026128261bb1a0e97510a6637f2  foundry/test/pramana_foundry/agent_server_test.exs
d553535ae62e5d4687d95b4f9b8d4096a870fd163923a33e95df9a585f3aaceb  foundry/test/pramana_foundry/autonomous_launch_test.exs
9c90d0fcb2302ad7aa81b4521b2419b83aac46235c51297fb08a49102733139a  foundry/test/pramana_foundry/coordinator_test.exs
3b4977469a61f1b21ab68ea673411197238bf5558bca160bd3c6778154714776  foundry/test/pramana_foundry/daemon_recovery_test.exs
931843cb63a32c7050b58c8cf32caf89cc66ce9ba42cdf50fc74b5be7a5656e2  foundry/test/pramana_foundry/herdr/adapter_test.exs
1ca8216bca1de3f28f538bdf637b4ad4d5330c5521948171f11453f14dd5eb3b  foundry/test/pramana_foundry/runtime_startup_boundary_test.exs
8a4776b0234c391d05caadf8816cefc39af32dd458478e76f49ae1cf48347bdb  foundry/test/pramana_foundry/stress_test.exs
0edd3f3b4154730ab8bcbacdc36b5c02a6fee644177709b68d06a3f3d30d5ddf  foundry/test/pramana_foundry/transition_test.exs
f295b6fc61c4fb605e653f7411b3f8fe7366f064e3a83d4043fc32c2b52694aa  foundry/test/support/runtime_cleanup_fixture.exs
```

## Retained limitations

- Backend generation values remain opaque; unsupported identity preserves resources.
- Backend compare-and-close is not atomic; FR-09/15a conformance remains downstream.
- Outstanding cleanup requires explicit recovery; FR-10 automatic reconciliation is
  not implemented.
- No live lifecycle or provider claim is made.
