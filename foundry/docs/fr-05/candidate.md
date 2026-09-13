# FR-05 candidate evidence

Candidate prepared uncommitted on `repair/fr05` from base
`64c226c30248cf140dae74dffeb28406742594dd` on 2026-09-13. This is containment only;
it does not implement FR-13, FR-14 or FR-17.

## Behavior

- Public CLI handoff/review submission passes the decoded artifact unchanged. It no
  longer substitutes coordinator run/base/candidate/check fields or requests
  `skip_git_checks`.
- Direct ticket creation rejects every unknown or duplicate option and all normalized
  `auto_approve` spellings before consulting Coordinator state.
- Completed handoffs and reviews require an explicit existing Git checkout, exact clean
  HEAD, existing base/candidate objects and real base ancestry. Reviews accept only the
  separately issued reviewer run identity. Production builds reject both legacy and
  explicitly test-only Git bypass options.
- `auto_approve` is rejected at direct admission, runtime handoff/review/admit, PM create
  and amend, and replay ticket/handoff boundaries. Synthetic reviews were removed.
- Public Coordinator, pure State and every public legacy Pipeline operation stop before
  intent, check runner, state mutation or Git effect. Legacy replayed success retains an explicit
  `legacy_unverified` claim while leaving `accepted_revision` unchanged.
- The mutable-source watcher and two bypassing legacy fixtures exit before work. The
  watcher uses only shell builtins and exits 78, so a source edit cannot build, stop or
  restart a runtime. Status revision values are labeled non-authoritative presentation.

## Executable evidence

All commands used pinned Elixir 1.20.3 / OTP 29.0.5, fresh isolated `TMPDIR` roots,
unset provider/tick/credential variables and no real Herdr, provider, credential,
daemon, accepted ref or activation target.

- Independent-review focused set (FR-05, integration, status and FR-03/04 containment):
  `63 passed`, exit 0, seed 506.
- FR-03/FR-04 and acceptance compatibility set: `116 passed`, exit 0, seed 505.
- Full model-free suite excluding integration: `422 passed`, exit 0, seed 506. Existing
  suite-owned OS-process fixtures (including its pre-existing Python trampoline/token
  checks) ran; FR-05 adds no Python implementation or fixture.
- Test build warnings-as-errors compilation: 77 files, exit 0.
- Production-compiled `mix run --no-start` probe returned explicit errors for both
  submission bypass options and the legacy integration bypass; it did not start the
  application.
- A second production `--no-start` direct probe proved all six public Pipeline functions
  refused, nine malformed/forbidden ticket-create argument sets refused, and the supplied
  runner was not invoked.
- The focused real-Git fixture creates only an isolated temporary repository. It proves
  stale run/candidate, wrong reviewer role, missing/nonexistent checkout and incomplete
  candidate/check identities fail. The CLI integration assertion byte-compares event
  log/state/ref before and after. The watcher test places fake build/watch/release commands
  on `PATH` and proves none writes its invocation marker.
- `git diff --check` passes. A repository-wide format check remains red because unchanged
  baseline files are unformatted; every touched Elixir file passes the pinned formatter.

## Frozen path hashes

SHA-256 values below were computed after the successful test runs. This evidence file is
excluded from its own non-self-referential manifest.

```text
38d3f83088431fd20e995cbab5d74a14e3e0661168e931d8542030fdba7474ea  foundry/README.md
d1344319172d01f66f6b65f6899c679b81aa31b6db8331cff279a9cb0b3300f4  foundry/bin/live_test.exs
ce8ac3d69f059c2b1239a6c1b0348fbd58056052e6757e657394d69693c70112  foundry/bin/pramana-live.sh
0acecf48b370ba8d9c2a85108ee3ab27d013bf587ee3b9f4f022e1f7b3cf0792  foundry/bin/tickets_from_review.sh
5785a4f1a6f0f402b8a3a9fca178f5c38e08c7041f5974de4bfbb9d91d91220c  foundry/docs/EVENT_SOURCING.md
a3b9bb6eb355203a339081b68b16fc617f7c3423d7e45e2ca14ee28ca98d6e6c  foundry/docs/MIGRATION.md
43538d16c444e83ca3dc0efbeca2b9673f1cb60b8f1d1547073ed8b08eef0afa  foundry/lib/pramana_foundry/assignments/handoff.ex
b967dea898c28f415cee391cd1aa4f1b55fe975d831c72588e9042cd50b8c67a  foundry/lib/pramana_foundry/cli.ex
bf18ecd9bcb22d162e0d5d6f0c735f1d5f50b4e0b985743cc6df1b796f01fbac  foundry/lib/pramana_foundry/coordinator.ex
5d4cbe0804b9f59a6671a5475d88fabc040250ce3ad32b5c2668f49768a8f927  foundry/lib/pramana_foundry/coordinator/state.ex
a1660d6bc9a0e4ca086d810fd7a7fba64278520af61f6bddff59c4899ad80ee5  foundry/lib/pramana_foundry/integration/pipeline.ex
5813c1afac7b2c2050b5ce7039b8ecc6cecf6cb623c9b7d996c9a474023d5004  foundry/lib/pramana_foundry/pm/proposal.ex
33d1b10499ab22a932fc7918ad6dd1cdc1c4449424ed49b8b73ac65bd6040721  foundry/lib/pramana_foundry/reviews/artifact.ex
70e5d31f3eb89481384b7e8c3f0e7263b4b6feb7034c32e500d646c59c439886  foundry/lib/pramana_foundry/status/report.ex
a4941d97ffc53779ff74d1c3273625ccf4735ec2467c5f411a54f5ad06945fb6  foundry/lib/pramana_foundry/transition.ex
4f044446b3559e8635da488e2d9f9f1047c1b665f56f4c84cb8fad43394fc7ce  foundry/lib/pramana_foundry/git_evidence.ex
f0516ac97ecb6f2fff2d8fe6f0ce0bb57666ad693095bad9efcda6578b16c1e1  foundry/test/pramana_foundry/agent_server_test.exs
06fc9df1ba583d041fe369c2a599fc0a05ac3e6dafc504eb366618946ab58571  foundry/test/pramana_foundry/assignments/assignments_test.exs
6a1c087412a84e659ac6d2ac6d1bf707ce073bcb82b18e0c009086da0085d081  foundry/test/pramana_foundry/coordinator/engine_test.exs
456b3f6b86299d1e89a55fcd2e8bfaec09eff9b32ee16633cd03b66f9f44287a  foundry/test/pramana_foundry/coordinator/recovery_test.exs
07c1a4842813362d7ffbf7f7f00136661a3fd47cdcfb836582453d2a4fb9bd30  foundry/test/pramana_foundry/coordinator_test.exs
9b1ae78c3d4b5458910f537424e2e436fb6dfd735f576aacbe650cf6f93b28b0  foundry/test/pramana_foundry/integration/integration_test.exs
14892c6bffbcdb6cdd96bb8348d21629ff27003c32bc66fe0a58e1046b4c324a  foundry/test/pramana_foundry/reviews/reviews_test.exs
5f40ae1529f3b9bd4f8aace0d080aa9224457c8ec2de1f4d5c4e36488934f515  foundry/test/pramana_foundry/status/status_test.exs
40f025b7f2aed5ece9c4efa26bc10af3304047e84c83a2a104d90ba79abb8df9  foundry/test/pramana_foundry/stress_test.exs
d1b827ea771136c95b4c5c3681f0c95b455e4877125696773ddd69c2ae4d02ea  foundry/test/pramana_foundry/fr05_containment_test.exs
```

## Limitations and restoration owners

- Mutable checkout checks are containment, not immutable artifact custody, full Git diff
  scope verification or controller-generated check receipts. FR-13 owns those guarantees.
- No accepted ref is updated and no recoverable integration worker exists. FR-14 owns
  compare-and-swap promotion and reconciliation.
- No build, release switch, health gate or rollback is implemented. FR-17 owns immutable
  accepted-build activation.
- The compile-time test build retains the old bypass option solely for legacy isolated
  unit fixtures. Production compilation omits that allowance, and public CLI code does not
  send either bypass option.
- FR-03 checked persistence/startup and legacy integration suspensions and FR-04 cleanup
  ownership/inventory remain intact. FR-13/14/17 restoration was not started.
