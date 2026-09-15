# FR-04 response to v4 review residual

Date: 2026-09-13 (Pacific/Honolulu)  
Base: `5c69e6c73f572e60a6c2015e955ad841bf504517`  
Branch/worktree: `repair/fr04`, `/tmp/pramana-fr04`  
State: final uncommitted candidate for independent review

This response addresses only the residual in `review-v4.md`, SHA-256
`9bcc9d294c27bd2ad42462442e460081b8d3ba03222d970bd2dddb38ab81db29`.
All implementation/test edits were complete and tested before this manifest was
generated. No edits followed manifest generation.

## Bounded per-resource inventory

Each successful AgentServer launch now reports its role and execution ID. The checked
`pane_created` event and its replay register a cleanup resource under
`role:execution_id`, retaining pane, terminal, native session, agent name and full
shell/foreground presentation identity. Legacy top-level assignment fields remain for
compatibility but no longer decide whether every resource is terminal.

`cleanup_pending` and `cleanup_result` update only their matching resource entry.
Terminal evidence must have passed the existing exact pending/result identity check;
clean fence release additionally requires every recorded resource entry to contain a
complete destructive identity and terminal status. A later reviewer launch/result
therefore cannot overwrite or settle a developer entry. Duplicate terminal results
without their pending receipt fail, and a sibling's otherwise-valid identity cannot
settle another execution.

Coordinator public status exposes the per-task `cleanup_resources` inventory, and
event replay reconstructs every entry. This is a bounded legacy ownership projection;
it does not add automatic cleanup/reconciliation or weaken FR-10 ownership.

## Actual two-AgentServer regression

The model-free production fixture starts distinct developer and reviewer AgentServers
for one assignment through the actual RuntimeOwner, RuntimeLease, Coordinator and
AssignmentSupervisor. With the developer blocked before cleanup and a 50 ms shutdown
allowance, the reviewer closes exactly, the developer writes no receipt and is not
closed, replay reports developer `owned` plus reviewer `closed`, and the unclean marker
remains. Separate runs explicitly terminate developer first and reviewer first; both
orders remove the marker only after both exact terminal receipts exist.

## Isolated evidence

Every command used fresh TMPDIR/operator roots, pinned Elixir 1.20.3 / OTP 29 paths,
and unset `HERDR_ENV`, `COORDINATOR_TICK`, `PRAMANA_RUNTIME_ROOT` and
`PRAMANA_RUNTIME_ROOT_FRESH`. Only fake adapters and isolated fixture state were used.
No live Herdr, provider, daemon, pane, credential, model, production state or
activation was accessed.

```text
# /tmp/pramana-fr04-v4-runtime.aTQ9sY
mix test test/pramana_foundry/runtime_startup_boundary_test.exs \
  test/pramana_foundry/transition_test.exs --seed 40435
# The initial run exposed one test expectation that failed earlier at resource
# validation; implementation and runtime cases passed. The expectation was corrected
# before the final run below.

# /tmp/pramana-fr04-v4-freeze.inCDQj
mix test test/pramana_foundry/herdr/adapter_test.exs \
  test/pramana_foundry/agent_server_test.exs \
  test/pramana_foundry/coordinator_test.exs \
  test/pramana_foundry/transition_test.exs \
  test/pramana_foundry/runtime_startup_boundary_test.exs \
  test/pramana_foundry/daemon_recovery_test.exs \
  test/pramana_foundry/autonomous_launch_test.exs \
  test/pramana_foundry/stress_test.exs \
  test/pramana_foundry/status/status_test.exs --seed 40437
105 passed; exit 0

# /tmp/pramana-fr04-v4-compile.2IEVrb
MIX_ENV=test mix compile --force --warnings-as-errors
76 files compiled; exit 0

bash -n bin/test_daemon_recovery.sh
bash bin/test_daemon_recovery.sh
1 passed; exit 0

git diff --check
exit 0
```

The focused suite reports only two pre-existing `stress_test.exs` warnings (unused
`proj`; unused private default argument). The isolated daemon fixture continues to
byte/SHA-compare unrelated JSONL state after cleanup.

## Final implementation/test manifest

```text
bbf27c265bfa56236c8884f04355432ab1156802fbe36924b723697a2c50c4cd  foundry/bin/test_daemon_recovery.sh
f78e819e5b9b3c6f112fddd130b88554406ea60f0495ea00d9ce427b54d313ae  foundry/lib/pramana_foundry/agent_server.ex
2acd833e4c3bbffa87d110d6c986dc699ee98469cb884b87fbd9dfa8fdeb3786  foundry/lib/pramana_foundry/application.ex
0d3055c3cf5fc0a8010e71ff0abc286c339ab11a9f4de104f0017406154f656c  foundry/lib/pramana_foundry/cleanup.ex
122ec160e51c4c9d867e3ad54fc23960f43073b1ea8859dce4cd5ec5a429f40c  foundry/lib/pramana_foundry/coordinator.ex
2877c7f5953e9a6f6ca720bae2e8b5facb6265ffa06b6536073ebd8affe2ada7  foundry/lib/pramana_foundry/coordinator/tick.ex
404406087170a1e37fcaaa3a6bc0ea9528cc659a689260ac2664bf1e5e846189  foundry/lib/pramana_foundry/herdr/adapter.ex
5f8f08a72a8f4146860179de61dbc65b00ff741ed1713831b3322bc6f51c97d5  foundry/lib/pramana_foundry/herdr/identity.ex
80e8cb54aea4e47a15d2840e4177e2adcdf07ec86de231a23cd27b1a81a3ff39  foundry/lib/pramana_foundry/runtime_lease.ex
00eea833c442ac19987e341733e513610e50e74a2aef11c484bf85e646150e2d  foundry/lib/pramana_foundry/runtime_owner.ex
ab0c29c76446dbede22d4efe459e9fa5858c888e76415c5271c9c58a7e902274  foundry/lib/pramana_foundry/status/report.ex
3f5b88e142a522dad2c193366ef18507ca83bc148144523c0b473b1638f22a3f  foundry/lib/pramana_foundry/transition.ex
39616ccbcb621ba715d29724068d8724300ee026128261bb1a0e97510a6637f2  foundry/test/pramana_foundry/agent_server_test.exs
d553535ae62e5d4687d95b4f9b8d4096a870fd163923a33e95df9a585f3aaceb  foundry/test/pramana_foundry/autonomous_launch_test.exs
9c90d0fcb2302ad7aa81b4521b2419b83aac46235c51297fb08a49102733139a  foundry/test/pramana_foundry/coordinator_test.exs
3b4977469a61f1b21ab68ea673411197238bf5558bca160bd3c6778154714776  foundry/test/pramana_foundry/daemon_recovery_test.exs
931843cb63a32c7050b58c8cf32caf89cc66ce9ba42cdf50fc74b5be7a5656e2  foundry/test/pramana_foundry/herdr/adapter_test.exs
6c9a89de82941622d13945bd9457caeaf83c6f6e2f69986ab49088928eafa027  foundry/test/pramana_foundry/runtime_startup_boundary_test.exs
8a4776b0234c391d05caadf8816cefc39af32dd458478e76f49ae1cf48347bdb  foundry/test/pramana_foundry/stress_test.exs
d10bbb117be39241180ab7d10acdfb9d392113b3a004ee8788e4ea76d4a25596  foundry/test/pramana_foundry/transition_test.exs
f295b6fc61c4fb605e653f7411b3f8fe7366f064e3a83d4043fc32c2b52694aa  foundry/test/support/runtime_cleanup_fixture.exs
521b77cf2747b79296d79f416b3e9a40eb1e02e4d1f5f87bcf3e683c7186318a  foundry/test/support/runtime_two_resource_fixture.exs
```

## Retained boundaries

- Inventory keys use the stable role/execution identity available at this legacy
  layer; exact resource identity is retained inside each entry. A richer durable
  resource ID and automatic reconciliation remain FR-10 work.
- Unsupported or malformed backend identity remains inert and cannot become terminal
  destructive authority.
- Backend comparison and close are not atomic; FR-09/15a conformance remains
  downstream.
- FR-03 startup reconciliation/integration remains suspended; no CLI or FR-05 path
  changed.
