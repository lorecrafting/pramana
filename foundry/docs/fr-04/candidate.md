# FR-04 candidate — verified-owned cleanup containment

> Superseded for renewed review by `review-response.md`, which contains the B1–B4
> corrections, current evidence and current hashes. The original record below is
> retained only as the artifact reviewed in `review.md`.

Date: 2026-09-12 (Pacific/Honolulu)  
Base: `5c69e6c73f572e60a6c2015e955ad841bf504517`  
Branch/worktree: `repair/fr04`, `/tmp/pramana-fr04`  
State: uncommitted candidate, frozen for independent review

## Scope and outcome

- Removed Coordinator's CWD-based pane enumeration, `/private/tmp` inference,
  hard-coded pane exceptions, and direct destructive System-runner cleanup.
- Kept FR-03 containment intact: legacy startup reconciliation remains suspended.
  The old direct inflight-pane recovery implementation was removed rather than made
  reachable again. FR-10 still owns durable restart reconciliation.
- Herdr cleanup now requires both:
  - exact live agent name, pane, terminal and session identity; and
  - an exact pane/process-info presentation snapshot captured while the AgentServer
    owned the launch.
- Missing, changed, recycled, unreachable or malformed identity returns an error and
  never issues `pane close`. The only pre-session path is a newly split pane whose
  pane/terminal/process snapshot is captured after a synchronous start failure and
  then rechecked immediately.
- AgentServer cleanup uses only its injected adapter and adapter options. It no longer
  constructs a default `Runner.System` close from a pane ID.
- Cleanup results travel in AgentServer lifecycle receipts. Coordinator includes the
  result in its existing checked append before applying the completion/launch-failure/
  crash transition. Uncertainty is therefore visible as `cleanup_status=unresolved`
  plus `cleanup_reason`, as well as in the AgentServer diagnostic line.
- Successful pane events persist both the complete cleanup identity and presentation
  identity for later reconciliation; this ticket does not activate startup recovery.
- Replaced the live-daemon/fixed-root recovery test and broad EXIT cleanup with a
  model-free Elixir fixture under the per-run isolated test root. The shell file is
  now only the existing wrapper boundary and deletes only the directory it created.

No CLI, FR-05 acceptance/integration/activation behavior, provider configuration,
live daemon, live pane, credentials or production state was touched.

## Acceptance mapping

| Obligation | Evidence |
|---|---|
| exact owned identity closes | adapter exact-close test; AgentServer timeout cleanup test |
| foreign pane in same temporary CWD survives | adapter fixture uses a shared `/private/tmp` CWD and proves no pane enumeration/close |
| recycled pane/session identifier survives | replacement native-session test; no close argv |
| terminal/session/name/pane mismatch survives | explicit adapter mismatch tests; no close argv |
| missing identity survives | fail-before-backend-call test |
| replacement process survives | same pane/terminal/session with changed process-info test; no close argv |
| unresolved cleanup observable and checked | AgentServer receipt test plus Coordinator checked-append test |
| unrelated state logs survive test cleanup | isolated recovery fixture byte- and SHA-256-compares an unrelated JSONL file after close |
| no CWD inference/hard-coded exceptions/default close | static source scans listed below |

## Commands and results

Every Mix command used explicit installed Elixir 1.20.3/OTP 29 paths, a newly
`mktemp -d` parent and separate `TMPDIR`; it unset `HERDR_ENV`,
`COORDINATOR_TICK`, `PRAMANA_RUNTIME_ROOT` and
`PRAMANA_RUNTIME_ROOT_FRESH`. No command used Herdr or a model.

Toolchain:

```text
elixir --version
Erlang/OTP 29 [erts-17.0.5]
Elixir 1.20.3 (compiled with Erlang/OTP 29)

mix --version
Mix 1.20.3 (compiled with Erlang/OTP 29)
```

Compile:

```text
MIX_ENV=test mix compile --warnings-as-errors
exit 0; fresh parent /tmp/pramana-fr04-compile.hEh2SI
```

FR-04 adapter/AgentServer/isolated recovery acceptance:

```text
mix test test/pramana_foundry/herdr/adapter_test.exs \
  test/pramana_foundry/agent_server_test.exs \
  test/pramana_foundry/daemon_recovery_test.exs --seed 40423
23 passed; exit 0; fresh parent /tmp/pramana-fr04-accept.A1a5Ej
```

Coordinator checked unresolved receipt:

```text
mix test test/pramana_foundry/coordinator_test.exs --seed 40423
6 passed; exit 0; fresh parent /tmp/pramana-fr04-persist.ahR4AS
```

FR-01 launch plus Transition compatibility:

```text
mix test test/pramana_foundry/autonomous_launch_test.exs \
  test/pramana_foundry/coordinator_test.exs \
  test/pramana_foundry/stress_test.exs --seed 40423
41 passed; exit 0; fresh parent /tmp/pramana-fr04-compat-final.0KSpjO
```

The compatibility run reports two pre-existing warnings in `stress_test.exs`
(unused `proj`, unused private default argument); it exits zero. The candidate
compile itself passes warnings-as-errors.

Existing wrapper boundary:

```text
./bin/test_daemon_recovery.sh
1 passed; exit 0
```

Static checks:

```text
bash -n bin/test_daemon_recovery.sh
rg 'foreground_cwd|w3:p1|w3:p0|pane", "list' lib bin
rg 'PramanaFoundry.Herdr.Runner.System.run' lib/pramana_foundry/agent_server.ex
rg 'cleanup_orphan_panes|recover_inflight_agents' lib/pramana_foundry/coordinator.ex
git diff --check
```

All prohibited-shape searches returned no match; shell syntax and diff check exited
zero.

## Candidate hashes

```text
bbf27c265bfa56236c8884f04355432ab1156802fbe36924b723697a2c50c4cd  foundry/bin/test_daemon_recovery.sh
bd120f83e2d5beb4f338fa36ace1d5b8073de506db5bf2e7c2ee440f6e75a244  foundry/lib/pramana_foundry/agent_server.ex
21af0e0395a43fd70e537438a0974f9b32bf1ca4b206807ad157bc64afda68de  foundry/lib/pramana_foundry/coordinator.ex
86712cbebcdb2f8a98bbd891a90c14354f5b3ea4d63a5aa53e6c728274310a3d  foundry/lib/pramana_foundry/herdr/adapter.ex
6c21873fdb88595d96f9d327b5c199d9e71ab7be6ce21f8487aae58d3132d6b4  foundry/lib/pramana_foundry/transition.ex
1642d610f7296b2519733ea8936b2eff0e648e8311e742925a065a3b9e730f58  foundry/test/pramana_foundry/agent_server_test.exs
61e18969713801717e84a455dd926c4b6030e6085fd8d202fb098d7a0901803e  foundry/test/pramana_foundry/autonomous_launch_test.exs
472d53972606b8a631cdda622c13f5b4037f240213d357b3d90afd7e11f54d07  foundry/test/pramana_foundry/coordinator_test.exs
24ad1f069954c50f83db86272d625bb9cd5e1d2c8ea3a9755be274851b00b958  foundry/test/pramana_foundry/daemon_recovery_test.exs
176ab828eb22d00e9f2b9c7f48cf2b51f777746c3e2418e8d0fe0b36a0c5634b  foundry/test/pramana_foundry/herdr/adapter_test.exs
20c964b5afff9a058e2f944dacc440bfb83e0e0853e796921a791b8be84a7d0f  foundry/test/pramana_foundry/stress_test.exs
```

These are the authoritative frozen implementation/test hashes after formatting and
all executable evidence above.

## Limitations

- This is immediate legacy containment, not FR-10 restart reconciliation. Unknown
  cleanup stays unresolved; it is never guessed closed or automatically retried.
- Process-info is compared as the complete backend map. A benign backend-field change
  can conservatively preserve an owned pane; false-negative cleanup is preferred to
  closing a replacement process.
- No live-provider conformance, real pane lifecycle, daemon restart, paid execution,
  credentials, activation or full Foundry suite was run. The former shell exercise did
  not provide safe evidence for those claims and no longer claims them.
- Formatter output expands diffs in the two legacy orchestration files. Review should
  inspect `git diff --ignore-all-space` alongside exact hashes.
