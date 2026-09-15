# FR-01 candidate v3 — independent review

**Verdict: FAIL — one remaining validation blocker.** V3 resolves the production
route and late-event blockers: real automatic execution is deliberately disabled,
and reviewer blocks survive all inspected launch/completion/crash callbacks.
The requested total/canonical input contract still fails on improper lists and
terminal newlines. Neither residual re-enables the production System runner.

Reviewed 2026-09-12 (HST) by `/root/fr01_review`, against the exact working tree.
Only this new repository document was written. No source/test/plan/log edits,
staging, commit, provider/model invocation, daemon, credentials, activation or
live-state access. Tests used ignored build output and temporary state. One
isolated application test process was started and stopped with ticks disabled;
this was not the installed daemon.

## Frozen input

HEAD: `a3fa302342238ae3d5a133b35bd86f4fa4f13710`. The twelve hashes from the v3
implementation-log record matched at entry and completion:

| File relative to `foundry/` | SHA-256 |
|---|---|
| `lib/pramana_foundry/agent_server.ex` | `1a8dbcd8d14a3f21034d50517bd797977f44a6c592d0940bbeaf0a16a80c7949` |
| `lib/pramana_foundry/coordinator.ex` | `241643abf3a1be26d808bfc26055ca9f66665297400ce93b517855f5fa2db0e7` |
| `lib/pramana_foundry/coordinator/tick.ex` | `e4a40c7c9c056b9ca1801724ab5de40d10e0cf45a408f3c60e76238dac0669d5` |
| `lib/pramana_foundry/herdr/adapter.ex` | `4ec26d65483c3c5321cab05b14beb4573f39c3131d211dc18b44aa65970c49cf` |
| `lib/pramana_foundry/herdr/runner.ex` | `1df506bc0444df2326de7fd9328e72038d990e2bbc36f5c9e038abbbc0fa2650` |
| `lib/pramana_foundry/launch_eligibility.ex` | `26c747c2abc332df0e07f1f6f38342b57bd150370766de38129230b000e82e74` |
| `test/pramana_foundry/agent_server_test.exs` | `914d266e4e48096076e2f412de601fb6a8aa68df444ccdf1195a8e41d0411f46` |
| `test/pramana_foundry/autonomous_launch_test.exs` | `2afdc9c2c4ee9636a5c64c14e7d9baf9a0bf8f0d50107131fffa9b2c166bb611` |
| `test/pramana_foundry/board_test.exs` | `cd455afc307d9fd3b9794d2d8862d817b848016a632f7dc438f02f38c8ca6637` |
| `test/pramana_foundry/coordinator/engine_test.exs` | `e0471669fc52ff8db46efebcb75bda90b9e4bba1e8a1cb610602c200da20fa7c` |
| `test/pramana_foundry/coordinator_test.exs` | `c2068847f4497e56a9c65180b670c7347e7fb2b925a1f2f8a2454e3e4b0b25a2` |
| `test/support/agent_server_fake_runner.ex` | `c84f22d4f0e2abf518753f785f74a85682e423a8c4d58c42a9692ea37063cf7e` |

The original dirty Coordinator baseline
`1e184cf4c52f500ad2859f6e883a5508ec83e50da2ca1811a281673c7e1cf30`
and its unrelated `unblock_ticket` change remain excluded. V1/v2 reviews and
v3 implementation-log scope were read. Per-file bytes above, not the reported
combined diff digest or HEAD alone, bind this review.

## Disposition of earlier blockers

### B1 resolved for static containment; real conformance remains disabled

`Runner.System.subscription_route_capability/1` unconditionally returns
`:unsupported`. Coordinator constructs `Adapter.new(Runner.System,
herdr_command)` directly; no configuration option selects a different runner or
turns that System result into `:enforced`. Explicit override-looking opts,
malformed opts, missing callbacks and a raising callback all returned
`{:error, :subscription_route_not_enforced}` in the review probes.

`Adapter.require_subscription_route/2` is called before admission/child creation
in Tick and both reviewer paths, and independently in AgentServer before it
sends itself `:launch`. Adapter requires the exact atom `:enforced`; boolean
true, unsupported, unavailable modules, callback exceptions/throws/exits and
invalid adapters do not grant capability. The System callback ignores opts.
Source tracing found no alternate reachable automatic constructor: developer
Tick, initial reviewer and retry reviewer are the three production launch sites.
No automatic PM model caller was added. Existing `Effects.Launch` and quota
fallback helpers still have no production orchestration caller.

The fake runner's `:enforced` is a legitimate deterministic test-backend
declaration: its `run/2` records argv and invokes an in-memory script, never a
provider. It does not turn System into an enforced backend, and it is loaded from
test support, not installed in the production application. Its test declaration
does not prove subscription entitlement. Arbitrary trusted BEAM code can of
course replace modules/state; the protected code/authority boundary remains
FR-15a/17 and is not claimed installed here.

The five explicit OMP flags from v2 remain bound to configured values at the
fake runner boundary. No default DeepSeek, implicit approval mode, manual paid
path, dynamic switching or new acceptance bypass appears in this candidate.
Since production OMP cannot pass capability admission, the installed OMP
authentication/matcher defects from v2 are now contained without claiming they
were fixed. Re-enabling System by merely changing its callback is not an accepted
FR-09/15a implementation.

### B3 resolved for the reviewed in-memory block

Coordinator now intercepts all `agent_launched` success/failure messages as well
as `agent_completed` and `agent_crashed` while the assignment is reviewer-blocked.
It preserves the entire assignment, including `blocked_role`, reason, handoff,
candidate and original role; it removes registry references and does not queue
or increment a retry. The focused test creates the block through the real
handoff handler, supplies each callback and then calls Tick with an otherwise
eligible developer. It asserts assignment equality and zero fake-runner calls.
The v2 late-launch-error and attribution-mutation cases are covered.

This is conservative containment, not general stale-execution fencing or owned
process cleanup. Those remain downstream. No block durability/restart claim is
made by the in-memory callback tests.

## Remaining blocker — B2 total/canonical validation is still incomplete

**Resolved portions:** the new plain-map checks reject `%URI{}` at policy,
profile, workflow, role-mapping, cooldown-container and cooldown-entry positions.
Ordinary malformed booleans/enums/selections/containers are tested through Tick,
AgentServer and both reviewer handlers with stable blocked reasons and zero
adapter calls. Blank/default account and simple unqualified model selectors
are rejected.

**Residual 1: improper lists raise.** `is_list/1` accepts an improper cons list,
but `Enum.all?/2` and `Enum.uniq/1` expect proper lists. At
`launch_eligibility.ex:232–253`, either of these configured values raises
`FunctionClauseError`:

```elixir
"automatic_roles" => ["developer" | :invalid]
"allowed_models" => ["subscription/test-model" | :invalid]
```

Both were reproduced through all four real application call boundaries: Tick,
AgentServer initialization, initial reviewer and retry reviewer. Every one
raised instead of returning its required blocked result. Fake runner calls
remained `[]`. Because policy is supplied through Elixir opts/application config
and `resolve/5` accepts `term()` inputs, it cannot rely on a preceding JSON
decoder to exclude these values. This is the same totality requirement as the
struct correction, with a different supported Elixir container.

**Residual 2: terminal newline passes canonical validation.** The three patterns
at `launch_eligibility.ex:23–25` use `$`, which accepts a match immediately before
a final newline. A profile with `account="test-account\n"` is accepted and the
newline survives in the resolved account. This is not the canonical identity the
new validation promises. The same anchor is used for profile/provider/model
syntax; exact allow-list equality does not repair an allow-listed string that
already contains the newline.

**Impact and bounded correction:** the real System backend remains unsupported,
so neither issue reopens production spending. They do fail the requested common
validation contract and its explicit blocked behavior. Validate proper lists
before enumeration (or consume/reject their tails explicitly), and require
whole-string identity matches rather than line-end matches. Add these cases to
the actual-boundary denial matrix. No provider, gateway, persistence or lifecycle
redesign is needed to finish this residual.

## Fixture review and deferred obligations

The board, Coordinator and engine fixture changes install only a fake adapter
and explicit test profiles/role mappings after reset. They do not rewrite
assignment status, handoff/review content, accepted revisions or test assertions
to fabricate the expected result. Their existing checks still run. All 29 tests
in those three files passed in an isolated application process during this
review. They remain component fixtures, not production launch/acceptance proof.

Their `:sys.replace_state` injection is acceptable as test setup for this
bounded change, with two **suggestions**: use a separately supervised Coordinator
when practical and restore replaced launch configuration so unrelated tests
cannot inherit the fake. The direct application-state replacement is not an
operator-facing configuration API and is not evidence of protected authority.
No test assertion was removed in these fixture diffs.

**Deferred obligations remain:**

- FR-09/15a: prove a real backend enforces provider/account/billing/model/reasoning,
  no API-key fallback, exact installed selector semantics, protected policy,
  credential custody and execution/egress isolation before restoring real launches.
  Regex syntax alone is not a catalog or entitlement proof. In particular,
  provider/model correspondence and all installed OMP naming/selector rules still
  belong to that conformance work.
- FR-07/08/10/11/12/16: durable resolved assignments/blocks/budgets, recovery,
  execution identity, actual quota observations/freshness, scheduling and bounded
  switching. The configured availability/cooldown checks are static inputs.
- FR-04/21: owned cleanup and fully isolated fixtures. AgentServer cleanup still
  uses System directly; fake-runner call counters do not intercept it. This review
  removed real Herdr/OMP from PATH and cleared `HERDR_ENV`; the application fixture
  also selected a nonexistent presentation command. No real pane action ran.
- FR-22: integrated lifecycle acceptance. The pre-fixture full-suite result in
  the log was not upgraded to a green run. This review ran focused/supporting/
  affected-fixture tests, not the entire suite.

**Documentation suggestion / completion obligation:** once the residual passes,
the authoritative completion entry and operator docs must plainly state that
all real automatic launches are disabled until FR-09/15a conformance. Keep the
temporary config schema and restoration owner discoverable. The implementation
log currently states that limitation accurately; no runtime activation is
authorized by the review.

## Commands and results

Root verification, exit 0 and values above:

```sh
git rev-parse HEAD
shasum -a 256 foundry/lib/pramana_foundry/agent_server.ex foundry/lib/pramana_foundry/coordinator.ex foundry/lib/pramana_foundry/coordinator/tick.ex foundry/lib/pramana_foundry/herdr/adapter.ex foundry/lib/pramana_foundry/herdr/runner.ex foundry/lib/pramana_foundry/launch_eligibility.ex foundry/test/pramana_foundry/agent_server_test.exs foundry/test/pramana_foundry/autonomous_launch_test.exs foundry/test/pramana_foundry/board_test.exs foundry/test/pramana_foundry/coordinator/engine_test.exs foundry/test/pramana_foundry/coordinator_test.exs foundry/test/support/agent_server_fake_runner.ex
git diff --check
```

Exact focused/supporting/compile commands from `foundry/`:

```sh
env -u HERDR_ENV -u COORDINATOR_TICK PATH=/Users/raymondluong/.local/share/mise/installs/elixir/1.20.3-otp-29/bin:/Users/raymondluong/.local/share/mise/installs/erlang/29.0.5/bin:/usr/bin:/bin mix test --no-start test/pramana_foundry/autonomous_launch_test.exs test/pramana_foundry/agent_server_test.exs --seed 424201
env -u HERDR_ENV -u COORDINATOR_TICK PATH=/Users/raymondluong/.local/share/mise/installs/elixir/1.20.3-otp-29/bin:/Users/raymondluong/.local/share/mise/installs/erlang/29.0.5/bin:/usr/bin:/bin mix test --no-start test/pramana_foundry/herdr/adapter_test.exs test/pramana_foundry/herdr/argv_test.exs test/pramana_foundry/herdr/identity_test.exs test/pramana_foundry/quota/quota_test.exs test/pramana_foundry/reviews/reviews_test.exs test/pramana_foundry/coordinator/recovery_test.exs --seed 424201
env -u HERDR_ENV -u COORDINATOR_TICK PATH=/Users/raymondluong/.local/share/mise/installs/elixir/1.20.3-otp-29/bin:/Users/raymondluong/.local/share/mise/installs/erlang/29.0.5/bin:/usr/bin:/bin mix compile --warnings-as-errors
```

Results: **24 passed** (0.6s), **44 passed** (0.2s), compile **exit 0**;
each test process exited 0. `git diff --check` exited 0. These counts are separate
selected suites, not a coverage percentage or whole-system gate.

The affected-fixture command used the same environment/PATH plus `MIX_ENV=test`
and `mix run --no-start -e 'BODY'`, with this exact body:

```elixir
{tmp, 0} = System.cmd("mktemp", ["-d", "/tmp/pramana-fr01-review-v3-fixtures.XXXXXX"])
tmp = String.trim(tmp)
try do
  Application.put_env(:pramana_foundry, :runtime_root, tmp)
  Application.put_env(:pramana_foundry, :herdr_command, "fr01-no-executable")
  Application.put_env(:pramana_foundry, :enable_tick, false)
  {:ok, _} = Application.ensure_all_started(:pramana_foundry)
  Mix.Task.run("test", ["--no-start", "test/pramana_foundry/board_test.exs", "test/pramana_foundry/coordinator/engine_test.exs", "test/pramana_foundry/coordinator_test.exs", "--seed", "424201"])
after
  Application.stop(:pramana_foundry)
  File.rm_rf!(tmp)
end
```

Result: **29 passed**, 0.8s, exit 0, no selected-file exclusions. Startup reported
tick=false, zero recovered events and `herdr=fr01-no-executable`. The application
stopped and its disposable state directory was removed.

### Supplemental capability and validation probe

Same restricted environment/PATH, `mix run --no-start -e 'BODY'`, exit 0:

```elixir
Code.require_file("test/support/agent_server_fake_runner.ex")
alias PramanaFoundry.{LaunchEligibility, Herdr.Adapter, Herdr.Runner}
p = PramanaFoundry.AgentServerTest.FakeRunner.launch_policy().profiles["test-subscription"]
for {label, value} <- [{"improper_roles", Map.put(p, "automatic_roles", ["developer" | :invalid])}, {"improper_models", Map.put(p, "allowed_models", ["subscription/test-model" | :invalid])}, {"newline_account", Map.put(p, "account", "test-account\n")}] do
  result = try do
    LaunchEligibility.resolve(%{"s" => value}, "s", :developer, %{}, now: 1000)
  rescue e -> {:raised, e.__struct__} end
  IO.inspect({label, result})
end
for opts <- [[], [subscription_route_capability: :enforced], [subscription_route_enforced: true], %{capability: :enforced}, nil] do
  IO.inspect({opts, Adapter.require_subscription_route(Adapter.new(Runner.System), opts)}, label: "System_override_attempt")
end
IO.inspect(Adapter.require_subscription_route(Adapter.new(PramanaFoundry.AgentServerTest.FakeRunner), false), label: "raising_fake_callback")
IO.inspect(Adapter.require_subscription_route(Adapter.new(URI)), label: "missing_callback")
```

Output: both improper lists raised `FunctionClauseError`; newline account was
returned unchanged in `{:ok, profile}`. All five System override attempts,
raising-fake-callback and missing-callback returned
`{:error, :subscription_route_not_enforced}`. No runner `run/2` was called.

### Actual-boundary improper-list probe

Same restricted environment/PATH, `mix run --no-start -e 'BODY'`, exit 0:

```elixir
Code.require_file("test/support/agent_server_fake_runner.ex")
alias PramanaFoundry.{AgentServer, Coordinator, Coordinator.State, Coordinator.Tick, Herdr.Adapter}
alias PramanaFoundry.AgentServerTest.FakeRunner
{tmp, 0} = System.cmd("mktemp", ["-d", "/tmp/pramana-fr01-review-v3-inputs.XXXXXX"])
tmp = String.trim(tmp)
table = :fr01_v3_malformed
FakeRunner.create_table(table)
policy = FakeRunner.launch_policy()
adapter = Adapter.new(FakeRunner)
base = String.duplicate("1", 40)
commit = String.duplicate("2", 40)
try do
  for field <- ["automatic_roles", "allowed_models"] do
    invalid = if field == "automatic_roles", do: ["developer" | :invalid], else: ["subscription/test-model" | :invalid]
    profiles = put_in(policy.profiles, ["test-subscription", field], invalid)
    ticket = %{"task_id" => "T", "base_revision" => base, "scope" => ["lib/**"], "exclusions" => [], "required_checks" => [["true"]], "review_required_checks" => [["true"]], "checkout" => "/tmp/unused-fr01", "profile" => "test-subscription", "reviewer_profile" => "test-subscription"}
    {:ok, queued} = State.enqueue_ticket(State.new(accepted_revision: base), ticket)
    {:ok, _, dispatched} = State.admit_assignment(queued, "T", "run", "developer")
    handoff = %{"schema_version" => 1, "task_id" => "T", "run_id" => "run", "assigned_base" => base, "commit" => commit, "changed_files" => ["lib/a.ex"], "reproduction_evidence" => %{"before" => "fail", "after" => "pass"}, "checks" => [%{"command" => ["true"], "exit_code" => 0}], "remaining_risks" => [], "status" => "completed", "outcome" => "probe"}
    {:ok, _, reviewing} = State.receive_handoff(dispatched, "T", handoff, skip_git_checks: true)
    review = %{"schema_version" => 1, "task_id" => "T", "run_id" => "wrong", "commit" => commit, "verdict" => "approved", "findings" => [], "remaining_risks" => [], "checks" => [%{"command" => ["true"], "exit_code" => 0}]}
    data = %{state: dispatched, event_log_path: Path.join(tmp, "events.jsonl"), herdr_adapter: adapter, herdr_timeout: 1000, telemetry_path: nil, agent_registry: %{}, launch_profiles: profiles, launch_role_profiles: policy.role_profiles, launch_now_fn: fn -> 1000 end, herdr_opts: [ets_table: table]}
    for {path, call} <- [
      {:tick, fn -> Tick.process_queue(["T"], queued, %{}, adapter, 1000, self(), Path.join(tmp, "tick.jsonl"), nil, 3, profiles: profiles, now: 1000, herdr_opts: [ets_table: table]) end},
      {:server, fn -> AgentServer.init(profile: "test-subscription", launch_profiles: profiles, role: :developer, adapter: adapter, launch_state: %{}, launch_now: 1000, herdr_opts: [ets_table: table]) end},
      {:initial_reviewer, fn -> Coordinator.handle_call({:receive_handoff, "T", handoff, [skip_git_checks: true]}, {self(), make_ref()}, data) end},
      {:retry_reviewer, fn -> Coordinator.handle_call({:receive_review, "T", review, [skip_git_checks: true]}, {self(), make_ref()}, %{data | state: reviewing}) end}
    ] do
      result = try do call.() rescue e -> {:raised, e.__struct__} end
      IO.inspect({field, path, result, FakeRunner.calls(table)}, label: "boundary_probe")
    end
  end
after
  File.rm_rf!(tmp)
end
```

Each of the eight field/path combinations returned the captured observation
`{:raised, FunctionClauseError}` and runner calls `[]`. The exceptions were caught
by the probe, not the candidate. Only temporary handoff/review event files were
written; the probe removed its directory after completion.

## Next disposition

Correct the one bounded validation residual and renew exact-tree review. B1's
production disablement and B3's in-memory block protection should be preserved;
they do not need reopening to fix proper-list validation and whole-string
anchors. Real subscription execution remains disabled pending its named owners,
regardless of whether the next static-containment review passes.
