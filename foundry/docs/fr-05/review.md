# FR-05 independent containment review

**FAIL — two remaining direct public-boundary gaps.** Reviewed 2026-09-13 on
`repair/fr05`, base/HEAD `64c226c30248cf140dae74dffeb28406742594dd`. No implementation
changes, commit, live daemon, provider, credential inspection or activation occurred.

Candidate SHA-256:
`b20fcc14863864523f70ea67daf8ec5bb3881037b5239decc9524a97addc1d9c`.
All 24 frozen path hashes in `candidate.md` matched using
`sed -n '/^[0-9a-f]\{64\}  /p' foundry/docs/fr-05/candidate.md | shasum -a 256 -c`.
The candidate manifest is the exact reviewed path inventory; it excludes this report.

## Blocking findings

### R1 — direct Pipeline boundary still accepts absent Git facts and runs checks

`lib/pramana_foundry/integration/pipeline.ex:133` returns `:ok` when an explicitly
supplied integration directory does not exist. The same production call also accepts
an invented accepted/base/candidate identity, an empty review map and an
`auto_approve` ticket. `run_gate_checks/3` at line 142 invokes its runner without any
containment refusal. `Integration` publicly delegates both functions. This leaves the
direct boundary outside the requested suspension before runner/state effects.

Reproduced with production-compiled `mix run --no-start`:

```elixir
alias PramanaFoundry.Integration.Pipeline
s = %{"accepted_revision" => "invented", "integration" => %{}}
a = %{"status" => "review_approved", "review" => %{},
      "ticket" => %{"base_revision" => "invented", "auto_approve" => true},
      "candidate_commit" => "invented"}
Pipeline.validate_readiness(s, a, integration_path: "/tmp/fr05-independent.bW7A04/absent")
# :ok
Pipeline.run_gate_checks("/tmp/fr05-independent.bW7A04/absent", [["irrelevant"]],
  fn _, _ -> send(self(), :runner_invoked); {"", 0} end)
# :ok; :runner_invoked received
```

This does **not** advance an accepted ref: `promote_candidate/3` correctly refuses,
as do Coordinator and State integration commands. The defect is the requested direct
boundary's absent-Git success and effectful runner, not a claim of successful promotion.
Suspend the remaining public integration entry points (or make unsupported helpers
inaccessible), then prove direct calls fail without invoking the runner or changing
owner/assignment state. Do not restore FR-14 integration to address this containment gap.

Pipeline SHA-256:
`dac525dc45adf5635382007ed8b8877e0e0c7e975972dfbb4354eba2424916eb`.

### R2 — direct CLI ticket creation silently drops auto-approve requests

`lib/pramana_foundry/cli.ex:354` parses arbitrary extra option pairs but constructs a
ticket containing only selected fields. Calling
`CLI.main(["ticket", "create", "--title", "probe", "--priority", "P2", "--auto_approve", "true"])`
returned success, appended an event and queued a ticket in an isolated Coordinator.
The forbidden option was discarded before State could reject it. FR-05 requires
auto-approve requests to fail explicitly through public commands.

The normal RPC wrapper already rejects this unknown option via its option allowlist;
this finding concerns direct CLI/escript invocation, not a wrapper transport bypass.
No synthetic approval was granted. Apply equivalent option rejection at CLI.main and
test unchanged state/log for both underscore and supported spelling variants.

CLI SHA-256:
`07ab44acc775f001616ec3a3207a58d1fa2d5ce526c86ed7978affd66917b4d2`.

## Verified containment and test evidence

Ran pinned Elixir 1.20.3 / OTP 29.0.5 with an allowlisted environment, original HOME,
fresh `TMPDIR=/tmp/fr05-independent.bW7A04`, and an operator runtime under that root.
Provider, Herdr environment and tick variables were absent. Production probes used
`--no-start`; test processes were suite-owned and used fake launch/cleanup adapters.
An initial mise invocation refused the untrusted temporary checkout and an initial
empty environment lacked HOME; neither reached tests. Direct pinned binaries with the
original HOME then ran successfully.

`MIX_ENV=test mix test` with the following six files and `--seed 506` returned exit 0,
**61 passed**, 14.7 seconds:

- `test/pramana_foundry/fr05_containment_test.exs`
- `test/pramana_foundry/integration/integration_test.exs`
- `test/pramana_foundry/status/status_test.exs`
- `test/pramana_foundry/legacy_persistence_containment_test.exs`
- `test/pramana_foundry/runtime_startup_boundary_test.exs`
- `test/pramana_foundry/agent_server_test.exs`

These exercise verbatim stale/incomplete CLI submissions, wrong reviewer identity,
missing/nonexistent submission checkout, Coordinator admission and runtime/PM
auto-approve rejection, replay auto-approval rejection, integration state/log/ref
preservation, unverified historical success, presentation-only revision labels,
watcher no-child behavior, and FR-03/04 persistence/startup/cleanup compatibility.
The candidate's larger full-suite counts were not independently rerun here.

Independent production GitEvidence probes created an isolated real Git repository:

- Base: `4bfe782ed294c92aa00880e1e31c283862e3a4a5`
- Candidate: `61936e75748442de66c8d7fafcda90db61114949`
- Unrelated orphan commit: `2c01f4c6a2cf7e4135da0be5749297339a1481fe`

The valid base/candidate returned `:ok`; unrelated ancestry, stale HEAD and nonexistent
base object returned explicit errors. Both `skip_git_checks: true` and
`test_only_skip_git_checks: true` returned production errors. GitEvidence SHA-256:
`4f044446b3559e8635da488e2d9f9f1047c1b665f56f4c84cb8fad43394fc7ce`.

Source sweep of `bin/` and `lib/` found no remaining CLI submission identity/check
substitution or production GitEvidence bypass. The mutable watcher and legacy fixture
scripts refuse immediately; the watcher contains only builtins and exits 78. Its
SHA-256 is `ce8ac3d69f059c2b1239a6c1b0348fbd58056052e6757e657394d69693c70112`.
`git diff --check` passed. FR-01 launch enforcement remains blocked; existing FR-02
inert RPC transport remains unchanged. No new unrestricted source interpolation path
was found. General release RPC authority remains explicitly deferred to FR-15a.

## Deferred and nonblocking observations

Controller-owned receipts, full Git diff/scope verification, immutable custody and
independent reviewer isolation remain FR-13/15a work. Current submitted check records
are self-reports; their structural acceptance is not evidence that checks ran. Replay
review labels likewise are not protected evidence. These do not justify restoring
promotion. FR-14 owns accepted-ref integration and FR-17 accepted-build activation.
Revision labels are explicitly non-authoritative and cannot supply those guarantees.

The Pipeline moduledoc still advertises atomic accepted-revision promotion; correct it
when closing R1. This wording issue alone would not block the containment review.
