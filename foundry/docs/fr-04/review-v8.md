# FR-04 independent review v8 — FAIL

Reviewed 2026-09-13 against the frozen v7 correction. Only this review artifact was written.

## Freeze

- `review-response-v7.md`: SHA-256 `3f41ab6ff38f3d639a4c1cab2372740eba406e6e44c4caf8a57c130b2576266f`.
- Prior `review-v7.md`: SHA-256 `a1cc23f5f1ffcdc94edaa1a322bbf8b79daba1faa1647d35fd25d294fbd73559`.
- All 22 response manifest entries verified against current bytes before testing and at handoff. Base/branch remain `5c69e6c73f572e60a6c2015e955ad841bf504517`, `repair/fr04`. No implementation/test drift observed; `git diff --check` passed.

```sh
shasum -a 256 foundry/docs/fr-04/review-response-v7.md foundry/docs/fr-04/review-v7.md
awk '/^[a-f0-9]{64}  foundry\// {print}' foundry/docs/fr-04/review-response-v7.md | shasum -a 256 -c
git status --short
git diff --check
```

## Original residual corrected

The split receipt is now synchronously checkpointed as an unverified resource before initial presentation capture. Independently executed the actual isolated RuntimeOwner/RuntimeLease/Coordinator/AssignmentSupervisor/AgentServer fixture with `process-info` replaced by JSON null. The fake callback read the checkpoint file before returning and asserted exactly one `pane_created` receipt, with `verification_status: unverified` and `resource_id: developer:RUN-RUNTIME`.

After capture failed, assertions passed for zero agent-start and pane-close calls, live and replay `cleanup_outstanding: true`, live and replay unverified inventory, and retained `runtime-owner.unclean` after shutdown. Durable events were exactly `pane_created`, `cleanup_pending`, `cleanup_result` for this resource. This directly regresses the v7 blocker with an additional malformed shape.

The focused suite also executes the PID-only and missing-foreground-generation actual runtime fixtures, append-failure recovery, valid same-resource presentation/session enrichment, sibling identity conflicts, both closure orders, and the bounded developer drain with an outstanding resource.

## Blocking residual: verified sibling clears an unverified resource's admission fence

`Cleanup.update_registration_fence/2` (lines 475–481) sets the assignment fence for an unverified registration, but a subsequent verified registration recomputes it only from `cleanup_obligations`. An unverified resource does not yet require a pending obligation to exist. Consequently, registering a verified sibling clears `cleanup_outstanding` while the first resource is still unverified.

Independent pure projection probe followed by the actual `Tick.process_queue/9` implementation produced:

```text
developer:R: status=unverified, verification_status=unverified
reviewer:R: status=owned, verification_status=verified
assignment cleanup_outstanding=false
Cleanup.all_owned_resources_terminal?(state) == false
Tick.process_queue([], state, %{}, nil, 1, self(), nil, nil, 1)
  => {state, %{}, []}
```

Tick's inspected admission gate depends on `cleanup_outstanding`. After the sibling registration, that global admission fence is absent. This contradicts the new unverified-resource contract even though inventory identity remains immutable and the shutdown terminal predicate correctly remains false. The observation is a synthetic allowed registration ordering, not a claim that the ordinary scheduler was observed to launch a reviewer while developer capture was blocked. No actual launch or destructive action was performed in this probe.

Reproduce under isolated `MIX_ENV=test` with `mix run --no-start -e`:

```elixir
alias PramanaFoundry.Cleanup
alias PramanaFoundry.Coordinator.Tick
base = %{"task_id" => "T", "execution_id" => "R", "role" => "developer",
  "pane_id" => "dev", "terminal_id" => "term", "agent_name" => "dev"}
s = %{"assignments" => %{"T" => %{"status" => "dispatched"}}, "queue" => []}
{:ok, s} = Cleanup.register_resource(s, base)
sibling = Map.merge(base, %{"role" => "reviewer", "pane_id" => "rev",
  "agent_name" => "rev", "presentation_identity" => %{
    "pane_id" => "rev", "terminal_id" => "term", "process_identity" => %{
      "pane_id" => "rev", "terminal_id" => "term", "shell_pid" => 1,
      "started_at" => "g", "foreground_pid" => 2,
      "foreground_started_at" => "f"}}})
{:ok, s} = Cleanup.register_resource(s, sibling)
false = s["assignments"]["T"]["cleanup_outstanding"]
false = Cleanup.all_owned_resources_terminal?(s)
{^s, %{}, []} = Tick.process_queue([], s, %{}, nil, 1, self(), nil, nil, 1)
```

The fence should account for every remaining unverified resource as well as pending/unresolved obligations. The same inventory-aware rule should be checked wherever terminal results recompute `cleanup_outstanding`; clearing one obligation must not release a separate unverified entry. No automatic reconciliation or additional destructive authority is needed.

## Commands and evidence

Pinned Elixir `1.20.3-otp-29` / OTP `29.0.5`; fresh `mktemp` roots with independent TMPDIR/operator/runtime directories. Unset `HERDR_ENV`, `COORDINATOR_TICK`, and inherited runtime-root settings. Actual runtime probes explicitly set only their fresh fixture root and daemon startup mode and used injected fake adapters.

```sh
mix test test/pramana_foundry/herdr/adapter_test.exs \
  test/pramana_foundry/agent_server_test.exs \
  test/pramana_foundry/coordinator_test.exs \
  test/pramana_foundry/transition_test.exs \
  test/pramana_foundry/runtime_startup_boundary_test.exs \
  test/pramana_foundry/daemon_recovery_test.exs \
  test/pramana_foundry/autonomous_launch_test.exs \
  test/pramana_foundry/stress_test.exs \
  test/pramana_foundry/status/status_test.exs --seed 40455
```

**113 passed**, 17.6 seconds, exit 0. Two pre-existing stress-test warnings remain. The null-capture actual-runtime probe and sibling pure projection/Tick probe each exited 0 with the assertions/results above. A preliminary `sed` in the sibling command used an incorrect relative path; it was read-only, unrelated to the Elixir probe, and did not affect its execution.

## Limits

No live Herdr, provider/model, credentials, production state or activation accessed. No implementation edits or commits. No fresh full-shell-wrapper or force-compile run; selected tests compile as needed. This is a narrow renewed review, not a fresh exhaustive audit of all process interleavings. Previous exact close authority, supervision/lease ordering, FR-03 containment and F-routing conclusions remain unchanged within the passing focused regressions. Backend compare/close atomicity, richer reconciliation and the existing FR-03 startup/integration suspensions remain deferred. The inventory-level admission-fence contradiction above remains a blocker.
