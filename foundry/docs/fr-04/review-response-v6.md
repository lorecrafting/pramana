# FR-04 response to v6 review residual

Date: 2026-09-13 (Pacific/Honolulu)  
Base: `5c69e6c73f572e60a6c2015e955ad841bf504517`  
Branch/worktree: `repair/fr04`, `/tmp/pramana-fr04`  
State: final uncommitted candidate for independent review

This response addresses only the launch-boundary residual in `review-v6.md`, SHA-256
`3f6a61921cff8a301540a8790acba34329207520ce581f8a85a9c2be0bd90f76`.
All implementation/test edits were complete and tested before this manifest was
generated. No implementation or test edits followed manifest generation.

## Checked split ownership before start

Immediately after a successful pane split and trustworthy presentation capture,
AgentServer synchronously sends the role, execution ID, pane, terminal, agent name and
complete shell/foreground presentation identity through Coordinator's checked cleanup
resource gateway. Coordinator validates the resource, appends and reads back the
`pane_created` checkpoint, and only then acknowledges AgentServer. `agent start` is not
invoked before that acknowledgement.

The existing `role:execution_id` inventory key is stable across this legacy launch.
The initial resource has no agent session because no agent exists yet. If start
succeeds, AgentServer synchronously checkpoints a narrowly permitted enrichment of the
same resource before prompting: every stable field must remain exact and the new native
session must be valid and linked to the same terminal. No pane, terminal, role,
execution, agent name or presentation field can change. Coordinator no longer waits
for the asynchronous launch notification to establish ownership.

If the initial checked append or validation fails, Coordinator enters recovery and
AgentServer returns before `agent start`. AgentServer does not attempt cleanup without
registered authority and includes the trustworthy split resource in its failure
notification. Under the recovery fence Coordinator retains that resource as an
in-memory owned observation; the durable unclean marker remains. There is deliberately
no close claim when the registration append itself failed.

## Failed-start behavior

After successful pre-start registration, start error/timeout cleanup uses that exact
fresh-pane identity. Pending and result checkpoints must match the registered entry.
An unchanged pane/process incarnation closes through the checked pending/result path;
replay reports the resource `closed`. If the foreground process identity changed after
the start attempt, compare-and-close refuses it; replay reports `unresolved`, the pane
is not closed, capacity remains blocked and the unclean marker remains.

The optional session fields are omitted from durable fresh-pane records and normalized
back to absence during replay. This avoids treating the legacy event encoder's textual
representation of an Elixir nil as identity evidence.

## Production-topology and focused evidence

The model-free production fixture uses the actual RuntimeOwner, RuntimeLease,
Coordinator, AssignmentSupervisor and AgentServer with an injected fake adapter:

- unchanged start timeout: one pre-start resource checkpoint, checked pending/result,
  exact close, durable `closed`, clean marker released;
- replaced foreground after start timeout: one pre-start resource checkpoint, checked
  pending/unresolved result, no close, durable `unresolved`, marker retained;
- injected pre-start registration append failure: zero start calls, zero close calls,
  no durable resource/close claim, recovery marker retained, and the trustworthy
  resource remains locally visible as `owned` until shutdown.

The AgentServer unit regression independently observes the resource callback before
any start call and proves a callback failure produces neither start nor close. Cleanup
projection tests prove only an exact linked native-session enrichment is accepted.
Existing sibling, two-AgentServer, drain, replay, tick and FR-03 fence regressions remain
green.

Every command used fresh TMPDIR/operator roots, pinned Elixir 1.20.3 / OTP 29 paths,
and unset `HERDR_ENV`, `COORDINATOR_TICK` and provider credential variables. Only fake
adapters and isolated fixture state were used. No live Herdr, provider, daemon, pane,
credential, model, production state or activation was accessed.

```text
# /tmp/pramana-fr04-v6-replay2.M6kQGI
mix test test/pramana_foundry/runtime_startup_boundary_test.exs \
  test/pramana_foundry/transition_test.exs --seed 40445
27 passed; exit 0

# /tmp/pramana-fr04-v6-final.KLrm3P
mix test test/pramana_foundry/herdr/adapter_test.exs \
  test/pramana_foundry/agent_server_test.exs \
  test/pramana_foundry/coordinator_test.exs \
  test/pramana_foundry/transition_test.exs \
  test/pramana_foundry/runtime_startup_boundary_test.exs \
  test/pramana_foundry/daemon_recovery_test.exs \
  test/pramana_foundry/autonomous_launch_test.exs \
  test/pramana_foundry/stress_test.exs \
  test/pramana_foundry/status/status_test.exs --seed 40447
111 passed; exit 0

# /tmp/pramana-fr04-v6-compile.5VI3ae
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
3e32312f492eaaca352e5a99a4288482d2b1e3423b62cba9ccd35be84dd4cb97  foundry/lib/pramana_foundry/agent_server.ex
2acd833e4c3bbffa87d110d6c986dc699ee98469cb884b87fbd9dfa8fdeb3786  foundry/lib/pramana_foundry/application.ex
c57c15dc9004718e52c84be3a80eef8e25c8d467a0e8fde21f66f82fc6a90909  foundry/lib/pramana_foundry/cleanup.ex
3a735bdf4adc696076cfc86c8b66b31aa25a91e18adfcb9899b369eba8591b6e  foundry/lib/pramana_foundry/coordinator.ex
2877c7f5953e9a6f6ca720bae2e8b5facb6265ffa06b6536073ebd8affe2ada7  foundry/lib/pramana_foundry/coordinator/tick.ex
404406087170a1e37fcaaa3a6bc0ea9528cc659a689260ac2664bf1e5e846189  foundry/lib/pramana_foundry/herdr/adapter.ex
5f8f08a72a8f4146860179de61dbc65b00ff741ed1713831b3322bc6f51c97d5  foundry/lib/pramana_foundry/herdr/identity.ex
80e8cb54aea4e47a15d2840e4177e2adcdf07ec86de231a23cd27b1a81a3ff39  foundry/lib/pramana_foundry/runtime_lease.ex
00eea833c442ac19987e341733e513610e50e74a2aef11c484bf85e646150e2d  foundry/lib/pramana_foundry/runtime_owner.ex
ab0c29c76446dbede22d4efe459e9fa5858c888e76415c5271c9c58a7e902274  foundry/lib/pramana_foundry/status/report.ex
3f5b88e142a522dad2c193366ef18507ca83bc148144523c0b473b1638f22a3f  foundry/lib/pramana_foundry/transition.ex
2da4321a628fc70757b5de3ea0507c3163cdb5eb4316d79de032e61efbf5a55b  foundry/test/pramana_foundry/agent_server_test.exs
8a90782f8a6b5a9497a917fe6d79377555ace2d06571da137f06122882ada23f  foundry/test/pramana_foundry/autonomous_launch_test.exs
c5594b8980b822d4a19511177cc51730d745455abdeb8ae0427e496c3507eee3  foundry/test/pramana_foundry/coordinator_test.exs
3b4977469a61f1b21ab68ea673411197238bf5558bca160bd3c6778154714776  foundry/test/pramana_foundry/daemon_recovery_test.exs
931843cb63a32c7050b58c8cf32caf89cc66ce9ba42cdf50fc74b5be7a5656e2  foundry/test/pramana_foundry/herdr/adapter_test.exs
4794b21ac15c21560367f0285a791fdb964a807bd017921242fdf13297019aa6  foundry/test/pramana_foundry/runtime_startup_boundary_test.exs
8a4776b0234c391d05caadf8816cefc39af32dd458478e76f49ae1cf48347bdb  foundry/test/pramana_foundry/stress_test.exs
195e199f4fdf920383d2a343961ce6cb269b8095a0f5941f9013fc3c0306ca38  foundry/test/pramana_foundry/transition_test.exs
26417b912b3c8f94f6823d484392584cdd9f67d91eadff71870cbc602cfc4443  foundry/test/support/runtime_cleanup_fixture.exs
521b77cf2747b79296d79f416b3e9a40eb1e02e4d1f5f87bcf3e683c7186318a  foundry/test/support/runtime_two_resource_fixture.exs
```

## Retained boundaries

- The stable resource key is the role/execution identity available at this legacy
  layer. Richer durable resource IDs and automatic reconciliation remain FR-10 work.
- A failed append cannot create durable resource evidence; it instead leaves the
  durable recovery/unclean marker and an in-memory owned observation. Successor startup
  remains refused until that recovery condition is handled.
- Unsupported or malformed backend identity remains inert and cannot become terminal
  destructive authority.
- Backend comparison and close are not atomic; FR-09/15a conformance remains
  downstream.
- FR-03 startup reconciliation/integration remains suspended; no CLI or FR-05 path
  changed.
