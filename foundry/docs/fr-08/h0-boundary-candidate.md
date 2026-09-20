# H0 accepted-FR-07 public-boundary candidate

Frozen 2026-09-19 (Hawaii) as the bounded H0 implementation/evidence candidate. This
checkpoint is complete as an honest inventory, but its seven-capability gate is
**blocked**, not ready. It does not implement FR-08A, authorize FR-08B, or enable a
daemon, provider, credential, deployment or activation path.

## Exact identity

- Accepted FR-07 v9 implementation: `af0c51b4682c50080e67194dd853fbaa1eebace7`,
  tree `e4aed492d5973d185a7e772d1b764e1117df11c1`.
- Accepted independent review: `8d7223b79cb237d3406f156c7d1a06a8bcb48d81`,
  tree `894e47756305f1b0fb615c6471f2dfdc644f16f3`.
- H0 adapter/probe revision: `800d200687fa4af2d5a08711c5a1e853df4d36a7`,
  tree `c6884159ec8048b3b4fb26375c6a28088be1b586`.
- Base supplied for this work: `25e109730bdb31fa475215813030d9b01ec43675`.
- Branch: `repair/h0-fr07-boundary`; worktree:
  `/Users/raymondluong/dev/pramana-h0`.
- Frozen report: `h0-accepted-fr07-report.txt`, SHA-256
  `a6ff9b7a33ab1ebe15edb2378d58281039fb6ee676b522cfd7e1963a493570f8`.

The provider binds the accepted revision before any probe runs. A different subject
revision yields seven unavailable results, so evidence for v9 cannot be replayed against
later source. Tests independently read each named API blob with `git show` at the accepted
revision, verify its digest, and require the current file to be byte-identical.

## Public API identity

| Accepted v9 path | SHA-256 |
|---|---|
| `foundry/lib/pramana_foundry/durable_store/gateway.ex` | `71742ca574ccc21806eb5cd6fb211946bad18a5049f1048bf9bde5c655723247` |
| `foundry/lib/pramana_foundry/durable_store/kernel.ex` | `918e7efbfbaaf6f2943b1b1ce403cf08615c330b300d6e0c9e1b7b192a6406ac` |
| `foundry/lib/pramana_foundry/durable_store/legacy_import.ex` | `158a8419cc59ee7e3998f2e497308d2a03a88871f79c1e031849cfcfef24a322` |
| `foundry/lib/pramana_foundry/durable_store/record_codec.ex` | `8bd05827b932e00dffbeeda84383d509a61d1cbc4be3fa58943ecfbef2930131` |

No DurableStore source, schema or API was changed. The provider calls only documented
`Gateway` operations and the documented offline `LegacyImport.run/4` boundary. It does
not call `Authority`, `Database`, `ProtectedVerifier`, `transact_verified/6`, SQL, or
private table interfaces.

## Honest capability disposition

The report preserves the existing ordered seven-probe gate and produces 4 passed,
0 failed and 3 unavailable capabilities. Therefore `FR08HandoffGate.ready?/1` is false.

| Capability | Result | Public evidence or limitation |
|---|---|---|
| Same-command lookup before revision | passed | A committed command is retried with an invalid empty proposal and returns the original result; a different actor conflicts. Receipt `7e2513de461477f0aeccc74c49a3295e3156028754c246204bb6a71f3e1da939`. |
| Complete read-set CAS | unavailable | Projection CAS exists, but the public API cannot evolve policy, control or allocation state, so their complete CAS lifecycle cannot be proved. |
| Atomic authority commit | unavailable | The public boundary cannot perform receipt or lease creation, claim issuance/settlement, or ledger evolution. Table presence and protected test helpers are not substituted for lifecycle evidence. |
| Revision and inbox facts | unavailable | Projection revisions exist, but no public authenticated inbox sequence/seal operation exists. |
| Protected-field boundary | passed | Nine hostile public proposals independently attempt claims, receipts, leases, ledger generations, policy/control revisions, artifact references, balances and accepted refs. Each is rejected and public counts remain zero. Receipt `ef3f8123c5d8e5d0d19428535f1f33196682f4b166c9698b99934b57ccf7a4ac`. |
| Fail-closed recovery | passed | A missing store reports `:not_initialized`, refuses transaction/count access and does not create a database. Receipt `2e1035b1f6cc5ad9bdbfdb8f8e61fc80d991b107b7cb8b92d71a1246b1494125`. |
| Immutable legacy import | passed | Canonical fixture bytes contain one unsupported-version row and one malformed row. Both are retained as invalid evidence, the archive remains byte-identical, and authority command/event counts remain zero. Receipt `8f183f57a3b73b6b086f831f706295f414541eac6358e862c9979b2b5207ff9a`. |

Each positive receipt is SHA-256 over the bounded semantic result selected by the probe,
not a temporary path or raw database. Two fresh-VM report invocations produced identical
gate output. The probes create only disposable canonical `/private/tmp` stores and remove
them after closing their gateways.

## Candidate path manifest

This candidate record is excluded to avoid a recursive self-hash.

```text
a6ff9b7a33ab1ebe15edb2378d58281039fb6ee676b522cfd7e1963a493570f8  foundry/docs/fr-08/h0-accepted-fr07-report.txt
442c659c0cc7631a4f61e1083114ce94406453c005f2d000069d5993b809324e  foundry/lib/pramana_foundry/repair/h0_accepted_fr07_boundary.ex
e3cbce816ad7fa34588122ea8a8eee588647541db926013d1b13bcfa9ca88bd3  foundry/test/pramana_foundry/repair/h0_accepted_fr07_boundary_test.exs
710f42d0467e97f58540342ba1c566959d995f1d561242c275f88eab2017228b  foundry/lib/pramana_foundry/repair/fr08_handoff_gate.ex
513bead9e36322a0f2d09a59124fd717d2bc3a3945d065eb58e75e941bece591  foundry/test/pramana_foundry/repair/fr08_handoff_gate_test.exs
df569423c58a67452cdb93d98259615ac0996b671dccb40089de28dce8c24caf  foundry/mix.exs
bf2a61f815533a96b2abec87b1690ae49145bec56e60703a22b4db178c56e954  foundry/mix.lock
```

## Executed checks and limitations

Pinned Elixir 1.20.3 / OTP 29.0.5 was used with isolated build and canonical temporary
roots, `MIX_ENV=test`, `COORDINATOR_TICK=0`, and provider/runtime overrides removed.

- `mix compile --force --warnings-as-errors`: exit 0; 106 project files.
- H0 provider plus unchanged gate tests at seed 1904: exit 0; 17 passed.
- DurableStore/public hostile suite excluding the independent VFS sync-fault file, plus
  containment, checkpoint, H0 and gate tests at seed 9221: exit 0; 107 passed. Log
  SHA-256 `703dec4f203b52aa90ded02ac1174fb63ae9810725cc88a51d4ddd4fd4281aaa`.
- Changed-path format checks and `git diff --check`: exit 0.

The repository CI runner was also executed from the clean adapter revision. Its first run
used macOS's symlinked default temporary root and correctly failed the DurableStore path
defense (74 failures); it is not acceptance evidence. A canonical `/private/tmp` rerun
passed locked dependency resolution, warnings-as-errors compilation and formatting, then
the BEAM exited with signal 11 (`mix test` exit 139) before an ExUnit summary. The same
exit 139 reproduces when `sync_fault_test.exs` runs alone; the 107-test suite excluding
that VFS interposition file passes. Canonical CI provenance SHA-256:
`20f1a84180f4eb4f94965b57071d428421ff00650e8c5b60a82e5d44163bf430`.
No green full-CI claim is made, and the external provenance artifact remains under
`/private/tmp/pramana-h0-ci-canonical.QmMrdH/artifacts/`.

This H0 candidate neither investigates nor repairs the VFS test-process crash because it
does not touch the H0 public boundary and DurableStore changes are excluded from this
slice. Independent review should treat the failed full runner as an explicit verification
limitation. H0's report remains evidence-complete and honestly blocked; only FR-08A may
add the missing protected primitives and produce a substantive ready gate at a new
reviewed revision.
