# FR-04 independent review v7 — FAIL

Reviewed 2026-09-13. Scope: frozen v6 correction, isolated model-free execution only.

## Freeze and provenance

- Base: `5c69e6c73f572e60a6c2015e955ad841bf504517`; branch `repair/fr04`.
- Response input SHA-256: `12a97807ae51db30524887e7f058336c54800f1759afb97cc3375ac274503ac5` (`review-response-v6.md`).
- Prior review input SHA-256: `3f6a61921cff8a301540a8790acba34329207520ce581f8a85a9c2be0bd90f76` (`review-v6.md`).
- All 22 implementation/test hashes in the response matched before and after execution. No implementation/test drift observed. `git diff --check` passed; status remains the declared uncommitted candidate plus review/response documents. This review changes only this file.

Verification command from repository root:

```sh
shasum -a 256 foundry/docs/fr-04/review-response-v6.md foundry/docs/fr-04/review-v6.md
awk '/^[a-f0-9]{64}  foundry\// {print}' foundry/docs/fr-04/review-response-v6.md | shasum -a 256 -c
git status --short
git diff --check
```

## Blocking residual: failed initial identity capture loses the split resource

An ordinary failed-launch boundary still falsely releases the clean-shutdown fence:

1. `pane split` succeeds with `pane-runtime` / `term-runtime`.
2. Initial `process-info` returns only `shell_pid: 100` (unsupported/malformed generation evidence).
3. AgentServer correctly refuses this identity, never starts an agent, and never closes the pane.
4. Because capture precedes checked registration (`agent_server.ex`, around lines 501–518), failure bypasses resource registration. `cleanup_pane/3` returns unresolved without a checked pending/result.
5. The normal launch-failure handler receives the resource observation but does not retain it; `preserve_unregistered_launch_resource/2` is used only when Coordinator is already in recovery. It records a generic `launch_parked` event and changes the live work status to `launch_failed` without setting cleanup inventory/outstanding.
6. Shutdown sees no owned resource and removes `runtime-owner.unclean`.

Independently reproduced using actual RuntimeOwner, RuntimeLease, Coordinator, AssignmentSupervisor and AgentServer, with only the fixture's injected adapter replaced. Observed output:

```text
presentation_identity_failed: :missing_process_incarnation
cleanup unresolved: :cleanup_resource_not_registered
LIVE: %{"status" => "launch_failed"}
REPLAY: %{"status" => "parked"}
V7_CAPTURE: %{close: false, start: false, resource_events: 0, marker: false}
```

`resource_events` counts `pane_created`, `cleanup_pending`, and `cleanup_result`. Both live and replay projections lack pane ownership and cleanup-outstanding state. Physical non-destruction is correct, but unresolved ownership/durability and the clean-release claim are not. This is not a request for automatic reconciliation: retaining an inert unknown-resource observation and fencing recovery belongs to FR-04's immediate failure contract. Never manufacture a generation or grant close authority to repair this case.

### Reproduction

Run from `foundry/` with a fresh `mktemp -d /tmp/pramana-fr04-v7-capture.XXXXXX` root, its own `tmp`, operator and runtime subdirectories, pinned Elixir `1.20.3-otp-29` / Erlang `29.0.5` PATH, `MIX_ENV=dev`, `PRAMANA_STARTUP_MODE=daemon`, `PRAMANA_RUNTIME_ROOT_FRESH=1`, `FR04_SHUTDOWN_MODE=success`, and unset `HERDR_ENV` / `COORDINATOR_TICK`. This starts only the isolated application fixture, not the live daemon.

Execute via `mix run --no-start -e`, evaluating the existing runtime fixture prefix before its `{:ok, agent_pid} = DynamicSupervisor.start_child` line, followed by:

```elixir
[{:script, original_script}] = :ets.lookup(table, :script)
FakeRunner.install(table, fn
  ["herdr", "pane", "process-info" | _] ->
    FakeRunner.json(%{"process_info" => %{"shell_pid" => 100}})
  argv -> original_script.(argv)
end)
{:ok, pid} = DynamicSupervisor.start_child(PramanaFoundry.AssignmentSupervisor, child)
ref = Process.monitor(pid)
receive do
  {:DOWN, ^ref, :process, ^pid, _} -> :ok
after
  2_000 -> raise "agent hung"
end
state = Coordinator.state()
IO.inspect(Map.take(state["assignments"]["T-RUNTIME-CLEANUP"],
  ~w(status cleanup_resources cleanup_outstanding pane_id)), label: "LIVE")
:ok = Application.stop(:pramana_foundry)
{:ok, events} = Checkpoint.events(event_path)
{:ok, %{state: replayed}} = Transition.rebuild(events)
IO.inspect(Map.take(replayed["assignments"]["T-RUNTIME-CLEANUP"],
  ~w(status cleanup_resources cleanup_outstanding pane_id)), label: "REPLAY")
IO.inspect(%{
  resource_events: Enum.count(events, &(&1["event"] in
    ~w(pane_created cleanup_pending cleanup_result))),
  start: Enum.any?(FakeRunner.calls(table),
    &match?(["herdr", "agent", "start" | _], &1)),
  close: Enum.any?(FakeRunner.calls(table),
    &match?(["herdr", "pane", "close" | _], &1)),
  marker: File.exists?(Path.join(runtime_root, "runtime-owner.unclean"))
}, label: "V7_CAPTURE")
```

## Passing evidence

Independently ran the full focused command below under fresh TMPDIR/operator roots, `MIX_ENV=test`, pinned toolchain and no live runtime root: **111 passed**, seed 40448, 16.6 seconds. Two existing stress-test warnings remain (unused variable and unused default argument).

```sh
mix test test/pramana_foundry/herdr/adapter_test.exs \
  test/pramana_foundry/agent_server_test.exs \
  test/pramana_foundry/coordinator_test.exs \
  test/pramana_foundry/transition_test.exs \
  test/pramana_foundry/runtime_startup_boundary_test.exs \
  test/pramana_foundry/daemon_recovery_test.exs \
  test/pramana_foundry/autonomous_launch_test.exs \
  test/pramana_foundry/stress_test.exs \
  test/pramana_foundry/status/status_test.exs --seed 40448
```

These execute the unchanged/start-timeout replacement and registration-append failure runtime fixtures, sibling/replay/status projection checks, native-session enrichment restrictions, real two-resource closure orders and developer drain deadline, pending/result append failures, FR-03 fence/topology cases, and Coordinator/Tick suspension regressions.

Two additional independent actual-topology probes passed:

- Changed child `run_id` to empty before launch: checked resource validation returns `invalid_cleanup_owner`; zero start, close or resource events; Coordinator recovery state and unclean marker retained after shutdown.
- After successful launch, sent forged `agent_launched` with foreign pane/terminal/name: registered inventory and checkpoint events remained byte-for-term identical; the pre-start registration plus exact native-session enrichment produced two resource events; exact shutdown cleanup released the marker.

Code inspection confirms asynchronous success now only updates dispatch time, while checked enrichment preserves role/execution/pane/terminal/agent/presentation identity. The known sibling pending/result immutability and per-resource terminal predicates remain in place. No new destructive path appeared in the lib/bin sweep: pane close remains behind typed adapter identity verification, with the previously reviewed owned process-group and check-runner child cleanup paths unchanged.

## Limits and routing

No live Herdr, provider/model, production state, credentials or activation accessed. No implementation edits or commits. No new full-shell-wrapper or force-compile run in this review; the focused tests compile as needed, and daemon recovery tests execute their isolated coverage. Earlier broad audit conclusions are regressed by the focused suite and targeted inspection, not claimed as a fresh exhaustive proof of every scheduler interleaving. Backend compare/close atomicity and richer durable reconciliation remain deferred downstream; F01–F24 routing and FR-03 startup/integration suspensions are unchanged. The capture-failure residual above blocks acceptance now.
