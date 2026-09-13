# FR-01 candidate v5 — independent review

**Verdict: PASS for static containment. Real automatic execution is deliberately
disabled. This is not proof of real subscription routing or authorization.**

Reviewed 2026-09-12 HST by /root/fr01_review against the frozen working tree and
REPAIR-PLAN FR-01/shared contract/F01, WORKFLOW-CONTRACT R2/R5, prior blocker
dispositions, and the current implementation log. No FR-01 blocker remains.
Only this report was written; no source/test/plan/log changes, staging, commit,
provider/model, installed daemon, credentials, activation or live-state access.

## Exact candidate

HEAD: 5179f34b3dd914808181b8c2513b393f9b38fe75, the documentation-only baseline.
All twelve hashes matched; only the two authorized v5 files differ from v3's
other ten frozen files.

| File relative to foundry/ | SHA-256 |
|---|---|
| lib/pramana_foundry/agent_server.ex | 1a8dbcd8d14a3f21034d50517bd797977f44a6c592d0940bbeaf0a16a80c7949 |
| lib/pramana_foundry/coordinator.ex | 241643abf3a1be26d808bfc26055ca9f66665297400ce93b517855f5fa2db0e7 |
| lib/pramana_foundry/coordinator/tick.ex | e4a40c7c9c056b9ca1801724ab5de40d10e0cf45a408f3c60e76238dac0669d5 |
| lib/pramana_foundry/herdr/adapter.ex | 4ec26d65483c3c5321cab05b14beb4573f39c3131d211dc18b44aa65970c49cf |
| lib/pramana_foundry/herdr/runner.ex | 1df506bc0444df2326de7fd9328e72038d990e2bbc36f5c9e038abbbc0fa2650 |
| lib/pramana_foundry/launch_eligibility.ex | ca331865be61be90e80d775631fff3e2fb3a94cccd12e30db6359bd221a8c70f |
| test/pramana_foundry/agent_server_test.exs | 914d266e4e48096076e2f412de601fb6a8aa68df444ccdf1195a8e41d0411f46 |
| test/pramana_foundry/autonomous_launch_test.exs | 8bc2350cd1e09c61a8c71e534786d49ee68c3447e24cd6c8ad94247bfca63391 |
| test/pramana_foundry/board_test.exs | cd455afc307d9fd3b9794d2d8862d817b848016a632f7dc438f02f38c8ca6637 |
| test/pramana_foundry/coordinator/engine_test.exs | e0471669fc52ff8db46efebcb75bda90b9e4bba1e8a1cb610602c200da20fa7c |
| test/pramana_foundry/coordinator_test.exs | c2068847f4497e56a9c65180b670c7347e7fb2b925a1f2f8a2454e3e4b0b25a2 |
| test/support/agent_server_fake_runner.ex | c84f22d4f0e2abf518753f785f74a85682e423a8c4d58c42a9692ea37063cf7e |

Original HEAD a3fa302342238ae3d5a133b35bd86f4fa4f13710 and dirty Coordinator
baseline 1e184cf4c52f500ad2859f6e883a5508ec83e50da2ca1811a281673c7e1cf30
remain historical inputs. The unrelated unblock_ticket change is excluded.

## Accepted containment and blocker disposition

- **B2 resolved:** unknown-field validation now checks every map entry with
  Enum.all?, returning a fixed error. Nil keys, arbitrary BEAM keys, and nil
  masking an additional credential field are rejected. The independent probe
  checked 46 key/masking variants, 138 resolver/role cases and 184 actual
  Tick/AgentServer/initial-review/retry-review boundary cases: stable blocked
  reasons and zero fake calls. Candidate tests also exercise the real
  DynamicSupervisor/AgentServer boundary; denial is not merely a helper result.
  Proper/nested-improper-list, plain-map/struct, invalid UTF-8, newline,
  whole-string canonical selector and exact allow-list regressions remain green.
- **Sentinel sweep:** remaining LaunchEligibility finds return key/value tuples
  (role mappings, cooldowns) or search fixed non-nil strings (required fields).
  The profile reduction returns tagged error tuples versus :ok. None confuses
  arbitrary input values with absence. Tick and Coordinator state folds carry
  state, not admission sentinels; adapter nested lookup treats absent/non-map
  responses as nil without granting capability.
- **B1 remains resolved for containment:** System unconditionally reports
  unsupported, and Coordinator directly selects System. No configuration or opts
  can mark it enforced. Missing/invalid/raising capability fails closed; Tick,
  both reviewer paths and AgentServer gate before pane/provider action. The
  test-only fake's enforced declaration is a deterministic backend contract,
  not a production override or entitlement proof.
- **B3 remains resolved in memory:** reviewer blocks preserve the entire
  assignment, role and candidate/handoff against launched success/failure,
  completion and crash; subsequent Tick does not relaunch. The focused tests
  reconstruct the block via handoff, exercise those callbacks, and assert
  assignment equality and zero calls.
- Explicit account/profile, provider, exact model, reasoning and approval argv
  remain checked at the fake execution boundary. Ticket-versus-role selection,
  absent/paid/premium/exhausted/unknown/cooldown denials and no fallback remain.
  Source tracing still finds developer Tick plus initial/retry reviewer only;
  no automatic PM model caller, new manual-paid path, or dynamic switching was
  introduced. Uncalled legacy Effects.Launch/quota fallback helpers do not
  establish an alternate production orchestration path.

## Checks and limitations

From foundry/, exact commands, all exit 0:

    env -u HERDR_ENV -u COORDINATOR_TICK PATH=/Users/raymondluong/.local/share/mise/installs/elixir/1.20.3-otp-29/bin:/Users/raymondluong/.local/share/mise/installs/erlang/29.0.5/bin:/usr/bin:/bin mix test --no-start test/pramana_foundry/autonomous_launch_test.exs test/pramana_foundry/agent_server_test.exs --seed 424201
    env -u HERDR_ENV -u COORDINATOR_TICK PATH=/Users/raymondluong/.local/share/mise/installs/elixir/1.20.3-otp-29/bin:/Users/raymondluong/.local/share/mise/installs/erlang/29.0.5/bin:/usr/bin:/bin mix test --no-start test/pramana_foundry/herdr/adapter_test.exs test/pramana_foundry/herdr/argv_test.exs test/pramana_foundry/herdr/identity_test.exs test/pramana_foundry/quota/quota_test.exs test/pramana_foundry/reviews/reviews_test.exs test/pramana_foundry/coordinator/recovery_test.exs --seed 424201
    env -u HERDR_ENV -u COORDINATOR_TICK PATH=/Users/raymondluong/.local/share/mise/installs/elixir/1.20.3-otp-29/bin:/Users/raymondluong/.local/share/mise/installs/erlang/29.0.5/bin:/usr/bin:/bin mix compile --warnings-as-errors

Results: **26 focused passed** (0.7 seconds), **44 supporting passed** (0.2
seconds), compile green. Expected fake launch-error/timeout logs are not failures.
The separate 460-call term-position matrix returned 454 errors with printable
reasons, six legitimate accepted values, and no exceptions. It samples finite
terms, not every possible BEAM value or resource-exhaustion condition.

Root checks:

    git rev-parse HEAD
    shasum -a 256 foundry/lib/pramana_foundry/agent_server.ex foundry/lib/pramana_foundry/coordinator.ex foundry/lib/pramana_foundry/coordinator/tick.ex foundry/lib/pramana_foundry/herdr/adapter.ex foundry/lib/pramana_foundry/herdr/runner.ex foundry/lib/pramana_foundry/launch_eligibility.ex foundry/test/pramana_foundry/agent_server_test.exs foundry/test/pramana_foundry/autonomous_launch_test.exs foundry/test/pramana_foundry/board_test.exs foundry/test/pramana_foundry/coordinator/engine_test.exs foundry/test/pramana_foundry/coordinator_test.exs foundry/test/support/agent_server_fake_runner.ex
    git diff --check
    rg -n 'Enum\.(find|find_value|reduce)' foundry/lib/pramana_foundry/{agent_server.ex,coordinator.ex,coordinator/tick.ex,herdr/adapter.ex,herdr/runner.ex,launch_eligibility.ex}
    rg -n 'AgentServer|Effects.Launch|pick_fallback|fallback_profile' foundry/lib

HEAD/hash/diff checks passed. No full-suite, installed-daemon or real-provider
test was performed. Unchanged fixture files retain v3's review, not a new v5
fixture-suite run. The broad probe calls application callbacks with isolated
state and an enforced fake; focused tests additionally use a supervised launch
boundary. PATH excludes Herdr/OMP. Temporary event files were removed; no user
material was deleted. No application/daemon was started by the probes.

## Deferred obligations; non-blocking suggestions

- **FR-09/15a:** prove installed OMP exact selectors, real subscription-only
  provider/account/billing binding, protected policy/credentials, and
  execution/egress isolation before restoring real automatic execution.
  Merely flipping the System capability is not accepted conformance.
- **FR-07/08/10/11/12/16:** durable assignments/blocks/budgets, recovery,
  execution identity, actual quota observations/freshness and switching.
  Configured available/cooldown state is static, not measured entitlement.
  R2/R5 gateway and per-request budget enforcement are not installed here.
- **FR-04/21/22:** owned cleanup, fixture isolation and integrated lifecycle
  acceptance remain. One unchanged legacy recovery helper found during the
  wider sweep, Coordinator.find_handoff_in_output/1, returns truthy :none
  inside Enum.find_value and can stop before a later handoff. This is a
  downstream recovery obligation, not a new launch-eligibility regression;
  it was source-inspected, not fault-tested in this review.
- **Suggestions:** retain the prior separately-supervised/restored fixture
  configuration improvement. Completion/operator documentation must clearly
  state real automatic launches are disabled and name FR-09/15a as restoration
  owners. This PASS does not authorize activation or satisfy those obligations.

## Reproducible adversarial probes

Both used the exact restricted environment above followed by
mix run --no-start -e 'BODY', exit 0. An initial boundary probe exited 1 because
its expected reviewer blocker omitted the existing "automatic reviewer launch
blocked: " prefix; corrected below. Candidate denial was correct in that run.

Boundary BODY:

    Code.require_file("test/support/agent_server_fake_runner.ex")
    alias PramanaFoundry.{AgentServer, Coordinator, Coordinator.State, Coordinator.Tick, Herdr.Adapter, LaunchEligibility}
    alias PramanaFoundry.AgentServerTest.FakeRunner
    {tmp, 0} = System.cmd("mktemp", ["-d", "/tmp/pramana-fr01-review-v5-boundary.XXXXXX"])
    tmp = String.trim(tmp)
    table = :fr01_v5_boundary
    FakeRunner.create_table(table)
    FakeRunner.install(table, fn _ -> raise "denied policy reached adapter" end)
    policy = FakeRunner.launch_policy()
    adapter = Adapter.new(FakeRunner)
    base = String.duplicate("1", 40)
    commit = String.duplicate("2", 40)
    terms = [nil, false, true, :invalid, 0, -1, 1.5, "", <<255>>, <<1::size(1)>>, [], [:invalid], ["value" | :invalid], [["value" | :invalid]], %{}, %URI{}, self(), make_ref(), fn -> :ok end, {:x, :y}, "value\n", " value", "value\r\n"]
    reason = ~s(profile "test-subscription" has invalid unknown field configuration)
    try do
      for key <- terms, masked <- [false, true] do
        bad = Map.put(policy.profiles["test-subscription"], key, :invalid)
        bad = if masked, do: Map.put(bad, "credential", "implicit"), else: bad
        profiles = %{"test-subscription" => bad}
        for role <- [:developer, :reviewer, :pm] do
          {:error, error} = LaunchEligibility.resolve(profiles, "test-subscription", role)
          ^reason = LaunchEligibility.reason(error)
        end
        ticket = %{"task_id" => "T", "base_revision" => base, "scope" => ["lib/**"], "exclusions" => [], "required_checks" => [["true"]], "review_required_checks" => [["true"]], "checkout" => "/tmp/unused-fr01", "profile" => "test-subscription", "reviewer_profile" => "test-subscription"}
        {:ok, queued} = State.enqueue_ticket(State.new(accepted_revision: base), ticket)
        {:ok, _, dispatched} = State.admit_assignment(queued, "T", "run", "developer")
        handoff = %{"schema_version" => 1, "task_id" => "T", "run_id" => "run", "assigned_base" => base, "commit" => commit, "changed_files" => ["lib/a.ex"], "reproduction_evidence" => %{"before" => "fail", "after" => "pass"}, "checks" => [%{"command" => ["true"], "exit_code" => 0}], "remaining_risks" => [], "status" => "completed", "outcome" => "probe"}
        {:ok, _, reviewing} = State.receive_handoff(dispatched, "T", handoff, skip_git_checks: true)
        review = %{"schema_version" => 1, "task_id" => "T", "run_id" => "wrong", "commit" => commit, "verdict" => "approved", "findings" => [], "remaining_risks" => [], "checks" => [%{"command" => ["true"], "exit_code" => 0}]}
        data = %{state: dispatched, event_log_path: Path.join(tmp, "events.jsonl"), herdr_adapter: adapter, herdr_timeout: 1000, telemetry_path: nil, agent_registry: %{}, launch_profiles: profiles, launch_role_profiles: policy.role_profiles, launch_now_fn: fn -> 1000 end, herdr_opts: [ets_table: table]}
        {s, %{}, [{:launch_blocked, "T", ^reason}]} = Tick.process_queue(["T"], queued, %{}, adapter, 1000, self(), Path.join(tmp, "tick.jsonl"), nil, 3, profiles: profiles, now: 1000, herdr_opts: [ets_table: table])
        "blocked" = s["assignments"]["T"]["status"]
        {:stop, {:launch_blocked, ^reason}} = AgentServer.init(task_id: "T", run_id: "run", checkout: "/tmp/unused-fr01", coordinator_pid: self(), profile: "test-subscription", launch_profiles: profiles, role: :pm, adapter: adapter, launch_state: %{}, launch_now: 1000, herdr_opts: [ets_table: table])
        {:reply, _, initial} = Coordinator.handle_call({:receive_handoff, "T", handoff, [skip_git_checks: true]}, {self(), make_ref()}, data)
        {:reply, _, retry} = Coordinator.handle_call({:receive_review, "T", review, [skip_git_checks: true]}, {self(), make_ref()}, %{data | state: reviewing})
        expected_blocker = "automatic reviewer launch blocked: " <> reason
        for d <- [initial, retry] do
          "blocked" = d.state["assignments"]["T"]["status"]
          ^expected_blocker = d.state["assignments"]["T"]["blocker"]
          "reviewer" = d.state["assignments"]["T"]["blocked_role"]
        end
        [] = FakeRunner.calls(table)
      end
      IO.inspect(%{key_variants: length(terms) * 2, resolver_checks: length(terms) * 6, boundary_checks: length(terms) * 8, adapter_calls: FakeRunner.calls(table)}, label: "PASS")
    after
      File.rm_rf!(tmp)
    end

Totality BODY:

    Code.require_file("test/support/agent_server_fake_runner.ex")
    alias PramanaFoundry.LaunchEligibility, as: L
    %{profiles: profiles, role_profiles: mappings} = PramanaFoundry.AgentServerTest.FakeRunner.launch_policy()
    name = mappings["developer"]
    profile = profiles[name]
    terms = [nil, false, true, :invalid, 0, -1, 1.5, "", <<255>>, <<1::size(1)>>, [], [:invalid], ["value" | :invalid], [["value" | :invalid]], %{}, %URI{}, self(), make_ref(), fn -> :ok end, {:x, :y}, "value\n", " value", "value\r\n"]
    calls = for term <- terms do
      [
        fn -> L.resolve(term, name, :developer) end,
        fn -> L.resolve(profiles, term, :developer) end,
        fn -> L.resolve(profiles, name, term) end,
        fn -> L.resolve(profiles, name, :developer, term) end,
        fn -> L.resolve(profiles, name, :developer, %{}, term) end,
        fn -> L.select_profile(nil, term, :developer) end,
        fn -> L.select_profile(term, mappings, :developer) end,
        fn -> L.resolve(profiles, name, :developer, %{"provider_cooldowns" => %{name => term}}) end
      ] ++ for field <- Map.keys(profile) do
        fn -> L.resolve(put_in(profiles, [name, field], term), name, :developer) end
      end
    end |> List.flatten()
    outcomes = Enum.map(calls, fn call ->
      case call.() do
        {:ok, _} -> :ok
        {:error, reason} -> true = is_binary(L.reason(reason)); :error
      end
    end)
    IO.inspect(Enum.frequencies(outcomes), label: "totality_matrix")
