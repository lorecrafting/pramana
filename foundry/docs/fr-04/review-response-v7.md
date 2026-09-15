# FR-04 response to v7 review residual

Date: 2026-09-13 (Pacific/Honolulu)  
Base: `5c69e6c73f572e60a6c2015e955ad841bf504517`  
Branch/worktree: `repair/fr04`, `/tmp/pramana-fr04`  
State: final uncommitted candidate for independent review

This response addresses only the initial-capture boundary in `review-v7.md`, SHA-256
`a1cc23f5f1ffcdc94edaa1a322bbf8b79daba1faa1647d35fd25d294fbd73559`.
All implementation and test edits were complete and tested before this manifest was
generated. No implementation or test edit followed manifest generation.

## Durable unverified split registration

Immediately after a successful pane split, and before any process-information or
presentation capture, AgentServer synchronously registers an `unverified` cleanup
resource through Coordinator's checked gateway. The durable `pane_created` receipt
contains the stable cleanup resource ID, role, run/execution ID, pane ID, terminal ID
and agent name from the trustworthy split receipt. It contains no manufactured shell,
foreground, generation or native-session evidence.

Coordinator validates the stable owner fields, appends and reads back the checkpoint,
and only then acknowledges AgentServer. The resource is keyed explicitly by the stable
legacy cleanup resource ID `role:execution_id`; duplicate exact registration is
idempotent. A different key, pane, terminal, role or execution cannot enrich or replace
that entry or a sibling entry.

An unverified entry is intentionally inert for destruction. It is visible in status
and replay, makes `cleanup_outstanding` true, blocks ordinary Tick admission and keeps
the runtime unclean marker, but can never authorize pane close or count as terminal.
Only a complete shell and foreground process incarnation linked to the same pane and
terminal may enrich that exact entry to `verified`. After successful agent start, a
valid linked native session may further enrich the same entry under the already
reviewed exact-identity rules.

If initial process capture is malformed, PID-only, missing foreground generation, or
otherwise unsupported, AgentServer starts no agent and closes no pane. Cleanup records
checked pending and unresolved result evidence against the already durable unverified
entry without converting it into close authority. Live status and replay both retain
the resource as unverified and outstanding, and shutdown retains the marker.

If the initial unverified registration append/read-back fails, Coordinator enters
recovery and AgentServer returns before process capture or agent start. The split is
preserved, no close claim is made, and runtime-local ownership plus the durable
recovery/unclean marker remain as the conservative fence. The failed append cannot be
claimed as durable resource evidence.

## Production-topology and replay evidence

The model-free boundary fixture uses the actual RuntimeOwner, RuntimeLease,
Coordinator, AssignmentSupervisor and AgentServer with an injected fake adapter. The
new production-path regression runs both malformed capture shapes:

- PID-only shell observation;
- shell generation present but foreground generation missing.

For each shape it proves one checked split-resource registration occurs before
capture, zero agent-start calls and zero pane-close calls occur, checked pending and
unresolved result evidence is appended, live and replay projections retain
`verification_status: unverified` and `cleanup_outstanding: true`, and the unclean
marker survives shutdown. Existing production-path cases continue to prove that a
valid unchanged fresh pane closes only through checked pending/result, a replacement
process remains unresolved, and registration failure causes zero start/close calls.

Transition tests separately prove that exact duplicate unverified registration is
idempotent, the unverified resource appears in public status/replay, an exact complete
presentation can enrich only that resource, and mismatched/sibling enrichment leaves
the inventory unchanged. Existing two-AgentServer, stale-receipt, drain, append
failure, admission suspension and FR-03 fence/topology regressions remain green.

Every run used a fresh TMPDIR/operator root, the pinned Elixir 1.20.3 / OTP 29.0.5
toolchain, and unset `HERDR_ENV`, `COORDINATOR_TICK` and provider credential variables.
Only injected adapters and isolated fixture state were used. No live Herdr, provider,
daemon, pane, credential, model, production state or activation was accessed.

```text
# /tmp/pramana-fr04-v7-freeze.pbMuM1
mix test test/pramana_foundry/herdr/adapter_test.exs \
  test/pramana_foundry/agent_server_test.exs \
  test/pramana_foundry/coordinator_test.exs \
  test/pramana_foundry/transition_test.exs \
  test/pramana_foundry/runtime_startup_boundary_test.exs \
  test/pramana_foundry/daemon_recovery_test.exs \
  test/pramana_foundry/autonomous_launch_test.exs \
  test/pramana_foundry/stress_test.exs \
  test/pramana_foundry/status/status_test.exs --seed 40454
113 passed; exit 0

# /tmp/pramana-fr04-v7-compile.5muwja
MIX_ENV=test mix compile --force --warnings-as-errors
76 files compiled; exit 0

bash -n bin/test_daemon_recovery.sh
exit 0

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
ec7e1ea88b26afc0f5b6ef3912479828334c32b16030ba6113aec1639aa360de  foundry/lib/pramana_foundry/agent_server.ex
2acd833e4c3bbffa87d110d6c986dc699ee98469cb884b87fbd9dfa8fdeb3786  foundry/lib/pramana_foundry/application.ex
040d0ef12d54656e78ce6691cf2a454311a4a079a7dbae98fc308363df3698ae  foundry/lib/pramana_foundry/cleanup.ex
01c2536ee38adaa6594f018730ca1e4e48f66d12e0e9f5a1edd4669117f72e6c  foundry/lib/pramana_foundry/coordinator.ex
2877c7f5953e9a6f6ca720bae2e8b5facb6265ffa06b6536073ebd8affe2ada7  foundry/lib/pramana_foundry/coordinator/tick.ex
404406087170a1e37fcaaa3a6bc0ea9528cc659a689260ac2664bf1e5e846189  foundry/lib/pramana_foundry/herdr/adapter.ex
5f8f08a72a8f4146860179de61dbc65b00ff741ed1713831b3322bc6f51c97d5  foundry/lib/pramana_foundry/herdr/identity.ex
80e8cb54aea4e47a15d2840e4177e2adcdf07ec86de231a23cd27b1a81a3ff39  foundry/lib/pramana_foundry/runtime_lease.ex
00eea833c442ac19987e341733e513610e50e74a2aef11c484bf85e646150e2d  foundry/lib/pramana_foundry/runtime_owner.ex
ab0c29c76446dbede22d4efe459e9fa5858c888e76415c5271c9c58a7e902274  foundry/lib/pramana_foundry/status/report.ex
c173b862b635cb65ed59e7bdcfea378387c89cfa4bd150d9124177dcef86d2de  foundry/lib/pramana_foundry/transition.ex
2da4321a628fc70757b5de3ea0507c3163cdb5eb4316d79de032e61efbf5a55b  foundry/test/pramana_foundry/agent_server_test.exs
8a90782f8a6b5a9497a917fe6d79377555ace2d06571da137f06122882ada23f  foundry/test/pramana_foundry/autonomous_launch_test.exs
c5594b8980b822d4a19511177cc51730d745455abdeb8ae0427e496c3507eee3  foundry/test/pramana_foundry/coordinator_test.exs
3b4977469a61f1b21ab68ea673411197238bf5558bca160bd3c6778154714776  foundry/test/pramana_foundry/daemon_recovery_test.exs
931843cb63a32c7050b58c8cf32caf89cc66ce9ba42cdf50fc74b5be7a5656e2  foundry/test/pramana_foundry/herdr/adapter_test.exs
3e5b63d5afd666cdc4ce9eba284e2f6510c383a7865b9841d2bcc81f7b60e540  foundry/test/pramana_foundry/runtime_startup_boundary_test.exs
8a4776b0234c391d05caadf8816cefc39af32dd458478e76f49ae1cf48347bdb  foundry/test/pramana_foundry/stress_test.exs
c9a151734064a23f892903d1d7af99c761cd0c8015586405a9ef092b4e8dfb4a  foundry/test/pramana_foundry/transition_test.exs
39878dd85b8e23f0d80c8293c16017542864aa47e8a7baf76be64acfc0c58af6  foundry/test/support/runtime_cleanup_fixture.exs
521b77cf2747b79296d79f416b3e9a40eb1e02e4d1f5f87bcf3e683c7186318a  foundry/test/support/runtime_two_resource_fixture.exs
```

## Retained boundaries

- The explicit stable resource ID is the role/execution identity available at this
  legacy layer. A later valid capture may enrich this entry but cannot rewrite its
  stable identity or settle another execution's resource.
- A failed append cannot create durable resource evidence; it instead leaves the
  durable recovery/unclean marker and runtime-local ownership. Successor startup
  remains refused until that recovery condition is handled.
- Unsupported or malformed backend identity remains inert and cannot become terminal
  destructive authority.
- Backend comparison and close are not atomic; FR-09/15a conformance remains
  downstream. Richer automatic durable reconciliation remains FR-10 work.
- FR-03 startup reconciliation/integration remains suspended; no CLI or FR-05 path
  changed.
