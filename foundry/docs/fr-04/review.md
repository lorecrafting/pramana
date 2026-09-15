# FR-04 independent review — FAIL

Reviewed 2026-09-12 (Pacific/Honolulu). This verdict applies only to the frozen,
uncommitted candidate on `repair/fr04` at base
`5c69e6c73f572e60a6c2015e955ad841bf504517`, in `/tmp/pramana-fr04`.
No implementation changes or commits were made by this reviewer.

Candidate artifact SHA-256:
`cfe3b2a6ff3becec6bcb86a2b5eb8dd1402ff7294a8dbdf5ff8cb341da47cebe`.
All eleven implementation/test hashes match its manifest exactly (listed below).

The CWD cleanup removal and injected-adapter change are valuable containment, but
the candidate still authorizes destructive cleanup without positive process
identity and loses some unresolved cleanup receipts. Existing focused tests pass;
adversarial probes below demonstrate gaps they do not cover.

## Blockers

### B1 — Nonempty process metadata is not a process identity

`herdr/adapter.ex:213–236` accepts any nonempty `process_info` map, and
`presentation_still_matches/2` only compares that map for equality. There is no
required process ID, process start/generation identity, relationship to the pane,
or validation of field values. Independently exercised through the actual adapter:

```text
process_info = {"foreground_cwd": "/private/tmp/shared"}
capture_presentation -> ok; close_pane -> ok; last argv = herdr pane close pane-1

process_info = {"shell_pid": null}
capture_presentation -> ok; close_pane -> ok; last argv = herdr pane close pane-1

process_info = {"shell_pid": 101, "foreground_pid": 202}
capture_presentation -> ok; close_pane -> ok; last argv = herdr pane close pane-1
```

The last shape is also the ordinary adapter and AgentServer test fixture. It cannot
distinguish a recycled PID from its former process. A backend omitting process
generation fields therefore permits replacement cleanup rather than returning
unknown. Comparing the whole map is conservative only when identifying evidence
is present; map equality cannot create that evidence. Benign dynamic fields can
also prevent cleanup, so whole-map equality is neither a documented stable
identity contract nor sufficient positive ownership proof.

Related cleanup-specific gap: `require_complete_identity/1` merely requires a
session map. `Identity.session/1` accepts any non-nil native session value, and
`session_matches?/2` explicitly permits terminal fallback to an arbitrary later
native session for the same terminal/agent kind. Thus the claimed exact session
requirement is stronger than the actual cleanup gate. The existing parser may
remain useful for non-destructive observation; cleanup needs stricter evidence.

Required correction: define and validate the minimum backend evidence that
distinguishes process incarnations, require valid exact session identity where
session ownership is claimed, and fail unresolved when that evidence is absent or
unsupported. Preserve the resource for malformed, PID-only, missing-generation,
and replacement cases. Do not fabricate generation evidence from observation time.

### B2 — Post-error capture adopts an already replaced occupant

`agent_server.ex:609–614, 666–674` first captures the fresh presentation identity
*after* `agent start` returns an error. All errors, including timeout/unknown
outcome, use this path. The split result contains only pane/terminal IDs. There is
no earlier process identity to compare against. A replacement already present at
capture is accepted as owned and immediately closed by `close_fresh_pane/3`.

Independent direct `AgentServer.handle_info(:launch, state)` probe used the real
adapter with only a scripted runner:

```text
pane split -> {pane_id: p, terminal_id: t}
agent start -> replace occupant, then {:error, :timeout}
pane get/process-info -> same pane/terminal, replacement PIDs 901/902,
                         started_at = "replacement"
cleanup -> herdr pane close p
closed_occupant: :replacement
receipt: {:agent_launched, "T", {:error, :agent_start_failed, :timeout},
          %{cleanup: %{status: :closed}}}
```

This fails even with generation metadata in the replacement snapshot. Rechecking
the newly observed replacement twice does not connect it to the original split.

Required correction: cleanup must compare against trustworthy creation evidence
obtained before any ambiguous start/replacement interval. If the backend cannot
provide such evidence, preserve the pane and record unresolved cleanup. Do not
equate a synchronous API error with proof that no agent/session started.

### B3 — Several cleanup paths never reach checked persistence

`agent_server.ex:413–426`: the `:shutdown` terminate branch discards
`cleanup_pane/3`'s receipt. Independently invoking this callback with a launched
pane, absent identity, nil telemetry path and `coordinator_pid: self()` printed
`cleanup unresolved ... :missing_cleanup_identity`, returned `:ok`, and left the
mailbox empty. No checked Coordinator append is possible.

`agent_server.ex:334–344`: both `submit_review` branches clean up and return a stop
tuple without sending a cleanup receipt. `cleanup_result` then suppresses any
terminate notification. Review acceptance/rejection occurs before this cleanup
and cannot have recorded its outcome. Optional best-effort telemetry is not
FR-03's checked authority gateway and its errors are merely printed.

Launch-failure receipts also carry only `%{cleanup: result}` (`:193`), omitting
the split pane/terminal and any captured ownership evidence. Failed launches have
no successful `pane_created` checkpoint, so an unresolved launch resource cannot
be identified from the authoritative failure receipt alone.

Required correction: cover every cleanup branch with an attributable receipt
through the checked persistence boundary, including reviewer termination,
supervisor shutdown and failed launch. Retain pane/execution/role identity in
unresolved records. If checked recording cannot finish during shutdown, retain an
explicit pending obligation before stopping; do not rely on optional diagnostics.
Add real append/read-back and injected append-failure assertions for these paths.

### B4 — Unresolved cleanup is erased from active status and treated as complete

`coordinator.ex:890–948` adds cleanup attributes to an event but still marks a
timeout `completed` and removes both registry entries irrespective of unresolved
cleanup. Launch failure/crash paths similarly permit ordinary retry. Cleanup
status is not retained in assignment state, and `Transition`'s completion/crash
projection ignores it. The new test explicitly asserts `completed` for an
unresolved timeout (`coordinator_test.exs:98`). It substitutes a callback returning
`{:ok, %{}}`, so its title's claim of durable append is not exercised.

This is an existing lifecycle weakness now explicitly exercised by the candidate,
not a new request to implement the full FR-10 kernel. Nevertheless, an unresolved
resource must remain visible as an outstanding obligation and must not be silently
treated as released capacity or successful completion. The workflow contract
requires unknown cleanup to block affected work and retain capacity (lines
463–469). A bounded recovery/block state is sufficient containment; full restart
reconciliation and domain lifecycle redesign remain deferred. Preserve already
validated work verdicts independently of cleanup status.

## What passed and what remains deferred

- Coordinator no longer enumerates panes by CWD, uses hard-coded exceptions, or
  directly closes panes. Searches across `foundry/lib` and `foundry/bin` found no
  residual `foreground_cwd`, `w3:p1`, `w3:p0`, or pane-list cleanup there.
- AgentServer cleanup uses its injected adapter and merges its injected options;
  no direct System runner close remains. Changed name, pane, terminal, explicit
  native session, and differing process maps are refused in the supplied tests.
- Successful launch receipts and pane-created projection preserve the additional
  cleanup/presentation fields. Completion/launch-failure/crash events that actually
  arrive at Coordinator still use FR-03 `persist_info`/checked append before their
  state continuation. Its fencing and append-failure recovery code is unchanged.
- FR-03's startup reconciliation suspension remains before effects. Removing the
  unreachable destructive recovery helpers does not restore recovery. Integration
  remains suspended. No FR-05 acceptance/activation or FR-01 subscription-route
  capability was enabled.
- The shell wrapper allocates one `mktemp -d` parent, points TMPDIR beneath it,
  clears runtime overrides, and deletes only that parent. The fixture uses the
  fresh published test root and mocked backend. No broad pane deletion or fixed
  log truncation remains. Its unrelated-log assertion establishes preservation
  during the mocked close, not a real restart or comprehensive shell-trap test.
- The all-lib/bin sweep also found the pre-existing `Adapter.stop` ctrl+C path,
  `Effects.ProcessGroup.signal`, and the check trampoline's `os.killpg` path.
  The group helper rechecks PID/group/start/command before signalling; the
  trampoline signals its own unreaped child created with `start_new_session`.
  These were inspected, not executed, and were not changed by this candidate.
  Their real lifecycle/conformance remains with the existing downstream owners;
  no assertion of atomic compare-and-close under backend races is made here.
- F01–F24 routing and dependencies in REPAIR-PLAN remain unchanged. F05's full
  reconciliation remains FR-10; F23/F24's real lifecycle, provider conformance,
  independent CI and executable provenance remain FR-21/22 and their listed
  dependencies. FR-09/15a still own installed backend and protected execution
  evidence. No live-provider test is required to resolve the deterministic
  blockers above.

## Independent commands and limits

Read project orientation and conventions, Foundry README, repair/dependency
inventory and FR-03/04/05 scopes, workflow ownership/recovery/lifecycle clauses,
audit F05/F23/F24, implementation-log FR-03/04 and candidate artifact. Inspected
exact and whitespace-insensitive implementation diffs plus the broader destructive
call-site inventory.

All executable probes used fresh `mktemp -d /tmp/pramana-fr04-review*.XXXXXX`
parents, separate child TMPDIR, explicit separate
`PRAMANA_OPERATOR_RUNTIME_ROOT`, `MIX_ENV=test`, and unset `HERDR_ENV`,
`COORDINATOR_TICK`, `PRAMANA_RUNTIME_ROOT`, `PRAMANA_RUNTIME_ROOT_FRESH`.
PATH was pinned to installed Elixir `1.20.3-otp-29`, Erlang `29.0.5`, `/usr/bin`
and `/bin`. `elixir --version` reported Elixir 1.20.3 / OTP 29, erts-17.0.5.

```text
git rev-parse HEAD
git branch --show-current
shasum -a 256 foundry/docs/fr-04/candidate.md
git diff --name-only -z | xargs -0 shasum -a 256
git diff --check                         # exit 0
bash -n foundry/bin/test_daemon_recovery.sh  # exit 0

# From foundry/, under the isolated environment above:
mix test test/pramana_foundry/herdr/adapter_test.exs \
  test/pramana_foundry/agent_server_test.exs \
  test/pramana_foundry/coordinator_test.exs \
  test/pramana_foundry/daemon_recovery_test.exs --seed 40423
# 29 passed, exit 0

mix run --no-start -r test/pramana_foundry/herdr/support/fake_runner.exs -e '...'
# Two direct probes, exit 0; observed unsafe outcomes recorded under B1–B3.
```

The first direct probe scripted `agent get`, `pane get`, `pane process-info` and
`pane close` with `Herdr.Test.FakeRunner.install/1`; for each B1 map it called
`Adapter.capture_presentation`, then `Adapter.close_pane` with the parsed exact
native session identity, and inspected `FakeRunner.calls()`. It then called
`AgentServer.terminate(:shutdown, state)` and inspected the current mailbox.
The second scripted split/start/get/process-info/close and invoked
`AgentServer.handle_info(:launch, state)` with a minimal launching-state map,
returning timeout at start after recording replacement ownership. Neither probe
started the application, a GenServer, Herdr or a provider.

The focused Mix suite starts only the isolated test application. No live daemon,
production state, credential, provider, activation, real pane close, OS kill,
full suite, or real backend conformance was exercised. Review-created temporary
test parents were left in place; no external resources were deleted.

## Verified implementation/test SHA-256 manifest

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
