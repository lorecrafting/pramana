# FR-04 response to v8 review residual

Date: 2026-09-13 (Pacific/Honolulu)  
Base: `5c69e6c73f572e60a6c2015e955ad841bf504517`  
Branch/worktree: `repair/fr04`, `/tmp/pramana-fr04`  
State: final uncommitted candidate for independent review

This response addresses only the derived cleanup-fence defect in `review-v8.md`,
SHA-256 `559728790b3f1819e89360f8b2d145eaeca136911448cf8a27119dd17239b1bf`.
All implementation and test edits were complete and tested before this manifest was
generated. No implementation or test edit followed manifest generation.

## Inventory-derived cleanup fence

`Cleanup.assignment_outstanding?/1` is now the single predicate for assignment-level
cleanup capacity. It evaluates the complete `cleanup_resources` inventory plus checked
pending obligations. Every unverified, owned, pending, unresolved, malformed-terminal,
or otherwise nonterminal resource keeps the fence true. The fence clears only when
every recorded resource has an exact valid terminal result and no pending obligation
remains. For legacy states without a resource inventory, an explicit outstanding flag
is conservatively retained.

Registration, pending application and result application all recompute the stored
`cleanup_outstanding` projection through that predicate. A terminal result also uses
the recomputed inventory before restoring work status, so closing one resource leaves
the assignment `cleanup_blocked` when any sibling is outstanding. The runtime-owner
terminal check, Coordinator registry/capacity decisions, completion status handling,
replay retry handling and Tick's global admission gate all call the same predicate.
Tick therefore cannot be fooled by a stale false projection when inventory itself is
nonterminal.

## Ordering, gateway, replay and Tick regressions

Two checked production-Coordinator gateway tests cover both legal sibling orderings:

1. register an unverified developer, then register and close a verified reviewer;
2. register and close the verified reviewer, then register the unverified developer.

In both orderings, `pane_created`, `cleanup_pending` and `cleanup_result` use the
checked append/read-back gateway. Live state and public status retain both resources,
the developer remains `unverified`, the reviewer remains `closed`, and
`cleanup_outstanding` remains true. Rebuilding the task's durable records produces the
same blocking inventory. The actual `Tick.process_queue/9` path returns
`{:admission_suspended, :cleanup_outstanding}` and leaves a competing queued ticket
unlaunched. Exact presentation/session enrichment followed by the developer's own
checked pending/closed result makes both resources terminal and only then clears the
fence. Both forward and reverse order are asserted.

The prior presentation-enrichment regression now explicitly records that a verified
but not yet terminal resource remains outstanding. The pending-append-failure test
likewise records that a previously registered owned resource remains outstanding even
when the pending append fails. Its test cleanup now restores the injected Coordinator
recovery hook so randomized focused-suite ordering cannot leak fixture recovery state
into another test module.

Every run used a fresh TMPDIR/operator root, pinned Elixir 1.20.3 / OTP 29.0.5, and
unset `HERDR_ENV`, `COORDINATOR_TICK`, inherited runtime-root/startup settings and
provider credential variables. Only injected adapters and isolated fixture state were
used. No live Herdr, provider, daemon, pane, credential, model, production state or
activation was accessed.

```text
# /tmp/pramana-fr04-v8-finaltarget.vTVWgN
mix test test/pramana_foundry/transition_test.exs \
  test/pramana_foundry/coordinator_test.exs --seed 40456
28 passed; exit 0

# /tmp/pramana-fr04-v8-freeze2.xpguYe
mix test test/pramana_foundry/herdr/adapter_test.exs \
  test/pramana_foundry/agent_server_test.exs \
  test/pramana_foundry/coordinator_test.exs \
  test/pramana_foundry/transition_test.exs \
  test/pramana_foundry/runtime_startup_boundary_test.exs \
  test/pramana_foundry/daemon_recovery_test.exs \
  test/pramana_foundry/autonomous_launch_test.exs \
  test/pramana_foundry/stress_test.exs \
  test/pramana_foundry/status/status_test.exs --seed 40458
115 passed; exit 0

# /tmp/pramana-fr04-v8-finalcompile.214rcx
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
f88dee9b1da90ad9b01c0d7f53dd3ac3e8d4a65dfc50de9feaf44b633d363359  foundry/lib/pramana_foundry/cleanup.ex
cfd0f275742a29a5bde92b511e384ff05dbe1a23e8c3438de8b2c7bfab22fe23  foundry/lib/pramana_foundry/coordinator.ex
8df097027896c88bb55f03f50a6cb6f5592c64a8c201f41aa1bf186754143ee0  foundry/lib/pramana_foundry/coordinator/tick.ex
404406087170a1e37fcaaa3a6bc0ea9528cc659a689260ac2664bf1e5e846189  foundry/lib/pramana_foundry/herdr/adapter.ex
5f8f08a72a8f4146860179de61dbc65b00ff741ed1713831b3322bc6f51c97d5  foundry/lib/pramana_foundry/herdr/identity.ex
80e8cb54aea4e47a15d2840e4177e2adcdf07ec86de231a23cd27b1a81a3ff39  foundry/lib/pramana_foundry/runtime_lease.ex
00eea833c442ac19987e341733e513610e50e74a2aef11c484bf85e646150e2d  foundry/lib/pramana_foundry/runtime_owner.ex
ab0c29c76446dbede22d4efe459e9fa5858c888e76415c5271c9c58a7e902274  foundry/lib/pramana_foundry/status/report.ex
ea91e5087229c5048c425d62c734c9d3ae0618a53eb7935a05fc56b8e4cf2fcd  foundry/lib/pramana_foundry/transition.ex
2da4321a628fc70757b5de3ea0507c3163cdb5eb4316d79de032e61efbf5a55b  foundry/test/pramana_foundry/agent_server_test.exs
8a90782f8a6b5a9497a917fe6d79377555ace2d06571da137f06122882ada23f  foundry/test/pramana_foundry/autonomous_launch_test.exs
20c86b76f8bcf2a16950e370a9ba1da75d8ca61f3d0990ca3333d3fed43a88c1  foundry/test/pramana_foundry/coordinator_test.exs
3b4977469a61f1b21ab68ea673411197238bf5558bca160bd3c6778154714776  foundry/test/pramana_foundry/daemon_recovery_test.exs
931843cb63a32c7050b58c8cf32caf89cc66ce9ba42cdf50fc74b5be7a5656e2  foundry/test/pramana_foundry/herdr/adapter_test.exs
3e5b63d5afd666cdc4ce9eba284e2f6510c383a7865b9841d2bcc81f7b60e540  foundry/test/pramana_foundry/runtime_startup_boundary_test.exs
8a4776b0234c391d05caadf8816cefc39af32dd458478e76f49ae1cf48347bdb  foundry/test/pramana_foundry/stress_test.exs
00368370750656cf9c9b7412322c9c2b6be4b0062fc772c29e51289fd6ab23d1  foundry/test/pramana_foundry/transition_test.exs
39878dd85b8e23f0d80c8293c16017542864aa47e8a7baf76be64acfc0c58af6  foundry/test/support/runtime_cleanup_fixture.exs
521b77cf2747b79296d79f416b3e9a40eb1e02e4d1f5f87bcf3e683c7186318a  foundry/test/support/runtime_two_resource_fixture.exs
```

## Retained boundaries

- The inventory and its exact per-resource identities remain the authority; the
  assignment flag is a derived compatibility projection, never a sibling-level
  terminal claim.
- Unsupported or malformed backend identity remains inert and cannot become terminal
  destructive authority.
- Backend comparison and close are not atomic; FR-09/15a conformance remains
  downstream. Richer automatic durable reconciliation remains FR-10 work.
- FR-03 startup reconciliation/integration remains suspended; no CLI or FR-05 path
  changed.
