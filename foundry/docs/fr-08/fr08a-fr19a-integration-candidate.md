# FR-08A + FR-19A integration candidate

Frozen combined candidate, 2026-09-20 (Hawaii). This record proposes the accepted
FR-08A protected-primitives implementation together with the accepted FR-19A operational
storage baseline for fresh Astra-high critical review. It is not an acceptance verdict,
FR-08B authority, provider execution, daemon activation or deployment authorization.

## Exact subject and provenance

- Accepted FR-19A main parent: `c53801245fac71c7e6de9f321947f2a9403c4745`.
- Accepted FR-08A parent: `5851c9be9b6d0cfb7f3fad5d41e06fa139b852bd`.
- Explicit non-squash merge: `1d0b128ff7c78bf72577d23658e267d7508e4763`,
  tree `f06d664214c65c435b0d8633bee845731e825e20`, with those two parents in that order.
- Combined integration core/tests: `240d16f6823a8b9118c4d2b52d305314c6a97203`,
  tree `d9f97d8e0b03f32d03884f4f21ceeab36ee297bb`.
- Revision-bound gate/report evidence: `b05f8342fbb83cb26a0fa157472bee15a020ad7e`,
  tree `91810f46acc152acd17e5c4a42cf42faff1b9c4f`.
- Branch/worktree: `repair/fr08a-fr19-integration`,
  `/private/tmp/pramana-fr08-integration.NfvG46`.

The automatic source merge had no semantic conflict. The combined Gateway retains
FR-19A's bounded health-controller lifecycle, checkpoint/backup operations and recovery
fencing while adding FR-08A migration, capability-authenticated root authority,
writer epochs and root/legacy route exclusion. No accepted contract was weakened.

## Combined behavioral evidence

The new focused integration file proves six cross-feature families:

1. Ready state exposes the protected capability/writer epoch and operational-health
   controller fields; not-initialized recovery keeps the bounded health shape and every
   protected read refuses with the recovery reason.
2. An accepted-v1 store containing domain history migrates additively, reruns
   idempotently and retains the exact legacy table digests. Future metadata, a partial
   marker and a corrupt current schema each refuse without being normalized into a
   supported state.
3. One store can commit ordinary domain replay plus root policy, control, ledger,
   reservation, effect and claim authority, then report health, checkpoint, publish a
   verified backup and reopen under a new writer epoch. Stale-epoch issue refuses;
   explicit quiescent reclaim followed by new-epoch issue succeeds.
4. Killing a Gateway during an in-flight capacity probe terminates caller, probe and
   controller. An evidenced reopen retains the root claim and returns bounded health.
5. Injected checkpoint and backup engine failures enter recovery and retain an exact
   `Authority.read(:all)` view across the domain and root registries. Reopen and a new
   verified backup preserve replay plus root claims, ledgers and reservations.
6. The immutable H0 artifact remains the historical 4-passed/3-unavailable record,
   while the evolved live H0 provider refuses positive credit as 0-passed/7-unavailable.

The executable FR-08A provider is bound to the combined core revision/tree and nine
loaded APIs by source SHA-256 plus BEAM MD5. Fresh generation is byte-identical to
[`fr08a-protected-report.txt`](fr08a-protected-report.txt): ready, 7 passed, 0 failed,
0 unavailable. The seven bounded semantic receipt digests are unchanged; the changed
Gateway source and loaded BEAM identities are explicitly new.

## Verification

Pinned Elixir 1.20.3, OTP 29.0.5 and ERTS 17.0.5 were selected by absolute path. Direct
checks used isolated build/temp roots, the existing dependency sources and Exqlite's
bundled `c_src` headers. The canonical runner created its own isolated dependency root.

| Check | Result |
|---|---|
| Initial combined accepted suites before identity rebind | Exit 2; 30/32 passed, with only the two expected stale identity/report assertions failing |
| New combined integration suite, seed 20821 | Exit 0; 6 passed |
| Fresh compile plus report generation and byte comparison | Exit 0; 110 files; generated report matched the frozen report |
| Combined focused matrix, seed 20823 | Exit 0; 46 passed in 88.0 seconds |
| Full clean `elixir ci/run.exs --output /private/tmp/fr08a-integration-ci/artifacts` | Exit 0; 612 passed, 13 skipped, 1 optional Python/tiktoken recomputation excluded |

Full CI preflight and postflight both identify evidence revision `b05f8342fbb83cb26a0fa157472bee15a020ad7e`,
tree `91810f46acc152acd17e5c4a42cf42faff1b9c4f`, and no dirty paths. Dependency
inventory, forced warnings-as-errors compile, formatter enforcement and fresh escript
build passed. Provider launch was disabled.

```text
5e05880b664a1a215c8be9f5716950f94db83d140e2984c3f44ad38e56840f12  focused.log
0506e031b5af50b43c1d0cc03a8f4553cb6bccb52135b1c4930e9001070e0800  generated-report.txt
9c4551b23a614ce59039520969b0a9b33421f091ab9bfa74254c321589314465  ci.log
0b64cce3b531f9b4a9130c8dfcdedf03dc0c71bbced220a5ebfd3202c1cb074e  artifacts/provenance.json
2dd5a07d0c2c2e4014a3249c90ccf53eadc5d8883cc99b7808df485d780d403f  artifacts/pramana_foundry
```

## Candidate manifest

Historical H0, FR-08A review and FR-19A physical evidence are excluded from this
integration manifest because they were not rewritten.

```text
9a6481b1fd09cdafc0a37cc5fa5bfb032b6993088ea8063d09a55cc002725929  foundry/lib/pramana_foundry/durable_store/gateway.ex
d0b94ba108f8a1be0b3c17db4478bcbe25783991ceb17bc5ca3bb8edd886d99c  foundry/lib/pramana_foundry/durable_store/authority.ex
bf21cc2dc37b58cdec0de191025a7753529fc08d66b887f15331d8bdf026e464  foundry/lib/pramana_foundry/durable_store/database.ex
eea13e7e9d463aca24e2e32e14e249bd99ede6f4c1df5f008bd003e7b3297fef  foundry/lib/pramana_foundry/durable_store/protected_primitives.ex
6a92c29174127f7a689a9933faf8d831c90fc069a0c8f67fb2fd27dd2528c276  foundry/lib/pramana_foundry/repair/fr08a_protected_boundary.ex
0506e031b5af50b43c1d0cc03a8f4553cb6bccb52135b1c4930e9001070e0800  foundry/docs/fr-08/fr08a-protected-report.txt
78d2e39dca032868bc22fd398411509bb60b6858f93f37d756b4fa809f27156a  foundry/test/pramana_foundry/durable_store/fr08a_fr19a_integration_test.exs
4a837161996755848c559e92212c836c6a057f3f6add693cb46b2d2a4468231b  foundry/test/pramana_foundry/repair/fr08a_protected_boundary_test.exs
```

## Preserved physical evidence and limits

An exact diff from accepted FR-19A main through evidence revision `b05f834` is empty for
the Linux workflow, raw/host/orchestration/parser helpers, `Maintenance`, Linux fixture,
maintenance-crash fixture and their orchestration/workflow tests. Therefore the prior
independently credited run `35498430877`, artifact `10601228576`, remains historical
evidence at its original revision and narrow scope. It was not rerun or relabelled as
execution of this combined Gateway binary. No combined behavior contradicted that
evidence or required a new privileged workflow.

The physical record still does not prove failed-sync persistence, SQLite WAL `xSync`
media durability, power-loss survival, controller/cache flush or deployment behavior.
The clean CI result is model-free and excludes the optional external Python/tiktoken
recomputation. FR-08B, FR-19B, providers, credentials, live daemons, activation,
deployment and main-branch integration remain outside this candidate.
