# FR-01 candidate v1 — independent authority/spending review

**Verdict: FAIL — three blockers.** Reviewed 2026-09-12 (HST), against the frozen
working tree, not HEAD alone. The default paid model and implicit `yolo` selection
are removed, and all three automatic launch sites now call a common eligibility
function. The candidate does not yet establish that the approved account/billing
selection controls execution, reject malformed policy consistently, or preserve its
new reviewer block through the existing agent lifecycle.

Reviewer: `/root/fr01_review`. No implementation changes, staging, commit, daemon,
provider/model invocation, credential access, activation, or live-state mutation.
This new review file is the only repository write made by the reviewer. Compilation
and tests updated ordinary ignored build output; tests used disposable state.

## Exact candidate and scope

`git rev-parse HEAD` returned `a3fa302342238ae3d5a133b35bd86f4fa4f13710`.
All six frozen SHA-256 values matched on entry and were rechecked at completion:

| Working-tree file | SHA-256 |
|---|---|
| `foundry/lib/pramana_foundry/agent_server.ex` | `43509a080f9f7b3d415364230e53293a9f35988f09f36f575da43aa212b09099` |
| `foundry/lib/pramana_foundry/coordinator.ex` | `396f648c6710b21d6d0e639fd06f374e5def7fdb29d5501b5625df562a1bbbe0` |
| `foundry/lib/pramana_foundry/coordinator/tick.ex` | `d0df5a69a4b6bff1ea1dc9a8aef2d70e10ba2d5881e66e90920926e8a911215a` |
| `foundry/lib/pramana_foundry/launch_eligibility.ex` | `cd5fd0aafe88144da42d1cccaeeab30f06fb12931c5db564a48b610823afd11f` |
| `foundry/test/pramana_foundry/agent_server_test.exs` | `e29997f9f340aec78687b227dcd30dfd4aa79672c5f54de455c4870ea37f61c1` |
| `foundry/test/pramana_foundry/autonomous_launch_test.exs` | `8916a95b63a4bdb5e9df4c10ab441b6f97b484ba75f3e0d0ae41153dbd3f9f5a` |

The starting Coordinator hash was
`1e184cf4c52f500ad2859f6e883a5508ec83e50da2ca1811a281673c7e1cf30`.
The `unblock_ticket/1` public wrapper and corresponding handler in its HEAD diff
belong to that earlier dirty baseline. They are excluded from this review and are
not claimed as FR-01 work. CLI, README and planning/design-status changes also
predate or sit outside this behavior candidate. FR-06 manifest status edits are
not FR-01 source drift.

Read project instructions and coding conventions, the repair plan's shared
contract, FR-01 and F01 routing, audit F01, workflow contract R2/R5, and the frozen
implementation log. Traced current source through AgentServer, Coordinator/Tick,
Herdr Adapter/Argv/Runner, cooldown/fallback, PM/HardeningPM, Improver,
application startup, and relevant tests. General lifecycle, cleanup, persistence,
acceptance and OS-isolation repairs remain assigned to their existing tickets;
the blockers below concern the effectiveness of this new containment boundary.

## Blockers

### B1 — Validated subscription identity is not bound to the execution request

Location: `agent_server.ex:395–431`; `launch_eligibility.ex:103–149`.

The guard accepts any nonempty provider/account/model/approval strings when the
subscription flags are set. AgentServer then discards account and reasoning at
the launch boundary. It supplies provider/billing/profile as three
`PRAMANA_FOUNDRY_*` pane environment labels and passes only `--model` and
`--approval-mode` to OMP. Adapter and Argv merely serialize these values; no
repository consumer makes those environment labels select an account or billing
channel. The implementation therefore cannot establish that an allowed
subscription account is used.

**Exercised:** a profile declaring `provider=openai-codex`, an explicit account,
and subscription billing accepted
`model=openrouter/deepseek/deepseek-v4-flash`. The actual AgentServer launch
callback reached the fake runner with that paid model in `herdr agent start`
argv. Changing account A to B and reasoning high to low produced identical
adapter argv. The fake deliberately stopped at agent start; no model ran.

The removed default is a useful correction, but this profile/route mismatch can
still request the manual-only paid route while its metadata claims subscription.
The current success assertions verify those labels rather than account/billing
selection, so they pass the reproduced mismatch. A profile name or self-declared
billing label is insufficient evidence of the selected authentication path.

**Required correction:** bind supported explicitly authorized profiles to the
actual provider/account/billing/model/approval execution selection; reject
inconsistent or unsupported selections before pane creation. If the current
harness cannot enforce a particular selection, keep it blocked until its
adapter contract is proved. Propagate configured reasoning or explicitly reject
unsupported reasoning, rather than silently dropping it. Add boundary tests
whose expected route changes when account or reasoning changes, plus the
subscription-label/paid-model contradiction. This does not require implementing
the whole FR-15a gateway or FR-16 switching in FR-01.

### B2 — Malformed policy can authorize a launch or crash instead of blocking

Location: `launch_eligibility.ex:103–149`, `coordinator/tick.ex:40–46`,
`coordinator.ex:923–929`, and the reused `quota/cooldown.ex:27–30`.

The new boundary checks equality against literal `true` for optional deny flags,
without validating their types. A string `"true"` for `premium_authorized` or
`exhausted` is accepted. A present cooldown entry with no expiry is treated as
no cooldown. These are malformed/unknown policy states, not positive evidence of
eligibility. Other malformed values raise: a list in `provider_cooldowns`, a map
in `quota_status` while formatting the reason, or a list role-profile mapping in
Tick. The resolver's generic map guard does not cover these nested shapes.

**Exercised:** both malformed boolean cases and `%{"provider_cooldowns" =>
%{"s" => %{}}}` returned accepted. Malformed cooldown and role containers raised
`ArgumentError`; map quota status raised `Protocol.UndefinedError`. The well-formed
mapping control returned a normal block. These pure calls had no adapter effects.

Ticket selection also uses `ticket_profile || role_default`: a malformed `false`
value is treated as absence. For reviewer selection the same rule applies to
`reviewer_profile`. Neither source nor tests defines a strict absent-versus-invalid
selection contract. Invalid explicit choices must not silently enable a default.

**Required correction:** validate policy/mapping/profile/quota/cooldown shapes
and allowed value types before admission; distinguish absent optional state from
present malformed state; return a stable blocked reason for every invalid case.
Cover malformed cases through Tick, both reviewer call boundaries and AgentServer,
with zero adapter calls and no exception. Rule 79 applies: a crash is not the
required blocked response.

### B3 — Reviewer eligibility block is erased by the running developer

Location: `coordinator/tick.ex:179–186`, `coordinator.ex:932–935`,
`agent_server.ex:331–341,199–217`, and
`coordinator.ex:740–783,786–818`.

When initial reviewer eligibility fails, Coordinator sets `status=blocked` but
returns handoff success to the developer. AgentServer consequently stays alive
and arms its ordinary ten-minute review timer. Its eventual `:review_timeout`
completion is handled as `completed`, overwriting the block. If that developer
crashes instead, the crash handler changes the blocked assignment to `queued`
and consumes a work retry. A subsequent Tick can start an eligible developer
again although the required reviewer is still ineligible. Reviewer-retry blocks
are exposed to the same remaining developer lifecycle.

**Exercised:** starting from the candidate's own `Tick.block_assignment/4`
reviewer block, actual Coordinator callbacks produced:

```text
blocked_after_developer_review_timeout: "completed"
blocked_after_developer_crash: {"queued", ["T"]}
```

The timer was delivered as an explicit callback input, with temporary event
storage; no ten-minute wait, daemon or agent was needed. Source tracing establishes
that a successful real handoff arms that timer. The existing handlers predate
FR-01, but the new blocked transition must compose with them to deliver FR-01's
explicit waiting behavior. The focused tests stop immediately after inspecting
the block and never exercise the later callback.

**Required correction:** preserve the eligibility-blocked status, role/candidate
and reason against completion/crash/retry messages from the retained developer;
do not restart developer work to satisfy unavailable reviewer eligibility. Add
the handoff → blocked reviewer → timeout/crash traces and a subsequent queue
processing assertion. Keep the general execution-identity/lifecycle redesign in
FR-10/11; this containment needs only a conservative no-progress guard.

## Path and evidence assessment

| Path | Source result | Candidate tests and limits |
|---|---|---|
| Automatic developer | Tick resolves ticket `profile`, then developer role default, before admission/child construction; AgentServer rechecks | Real Tick and fake-runner launch exercised; absent profile blocks. Paid/quota/malformed/default-precedence cases are not all exercised through Tick |
| Initial reviewer | Handoff handler resolves ticket `reviewer_profile`, then reviewer role default; AgentServer rechecks | Real handler plus DynamicSupervisor/fake runner exercised for paid and allowed profiles. Subsequent blocked lifecycle is missing; B3 |
| Reviewer retry | Rejected-review handler resolves the reviewer profile again | Real handler exercised for active cooldown and allowed profile. Missing configuration, paid/quota and malformed variants are not all exercised through this path |
| PM | No autonomous PM model launcher is reachable in the inspected source | Resolver allows PM and denial tests call AgentServer for PM. No allowed PM launch test exists; no PM feature is claimed |

The no-autonomous-PM-caller claim is supported by source tracing: the only
production AgentServer child constructors are Tick's developer constructor and
Coordinator's two reviewer constructors. PM delegates to proposal/attempt-cap
logic; HardeningPM deterministically builds amendments/parking proposals;
Improver deterministically emits proposals. Their model/profile fields describe
future developer work and do not invoke a PM model. `Effects.Launch.launch/6`
has test callers but no current production caller. No reachable production
fallback caller was found; `Quota.Fallback` remains an unwired helper. No manual
paid execution path was introduced or altered, and no new switching or gate
weakening was found in the FR-01 diff.

AgentServer's second check is real and runs before `send(self(), :launch)`;
denied cases therefore cannot split a pane. It rechecks the same supplied policy
snapshot, however, and inherits B1/B2. Default model/approval options are gone;
an explicit approval string is now required. Ticket profile precedence is direct
and has no fallback on an unknown nonempty name, which is good; nil/default and
invalid-value behavior still need tests.

## Deferred obligations and suggestions

- **Deferred — FR-07/08/10/11:** the new block and full resolved assignment are
  not durable. Tick persists only the profile name; reviewer selection is not
  persisted as a resolved profile. Restart/replay, exact account/model/role/
  reasoning/quota/limit attribution and conserved start/request ledgers remain
  unproved. Do not claim F01 or R5 closed from this containment.
- **Deferred — FR-09/15a/16:** quota comes from `launch_profiles`, captured at
  Coordinator init from opts/application configuration. `quota_status` has no
  freshness metadata or live observation producer. The check additionally reads
  profile-keyed `state["provider_cooldowns"]`; only the unwired fallback helper
  records those observations. Actual provider exhaustion currently enters generic
  failure/retry handling and does not refresh this static availability value.
  Observed exhaustion/unknown freshness, cooldown propagation, restart behavior,
  bounded switching, gateway request enforcement and credential/egress isolation
  still require their routed implementation evidence. Mock available/exhausted
  flags do not establish live quota handling.
- **Deferred — FR-04/21:** cleanup still calls `Runner.System` directly, bypassing
  the fake adapter. The new test sets `HERDR_ENV=1`; running it in an ordinary
  environment can therefore address real Herdr cleanup for its fake pane ID.
  This review excluded Herdr from PATH. Retain that test isolation until owned
  cleanup is repaired; fake-runner zero-call assertions do not observe direct
  System-runner cleanup.
- **Suggestion / completion obligation:** document the temporary
  `launch_profiles` / `launch_role_profiles` schema, selection precedence,
  fail-closed default, status behavior, static quota limitations and migration to
  protected operator policy. No operator/developer configuration documentation
  for these new keys was present in the reviewed docs/README. The module comment
  mentions FR-16 but not the R2 protected-policy migration. The coordination owner
  still needs the shared completion/status entries after a corrected review.
- **Suggestion:** extend tests to a complete per-reachable-path denial matrix,
  including premium with subscription billing, missing subscription authorization,
  missing fields, unknown profile, expired cooldown, role mismatch, mapping
  precedence and conflicting legacy model options. Current paid fixture combines
  paid billing and premium=true, so it cannot independently prove both gates.

## Commands, results and reproducible probes

Commands ran from the repository root for Git/hashes and from `foundry/` for Mix.
No shell output was used as a substitute for exit status. Source discovery used
`rg`, `rg --files`, `sed`, `nl` and scoped `git diff`; source searches found no
consumers of the new provider/billing environment labels outside their producer
and tests.

Exact candidate verification command (exit 0, values above):

```sh
git rev-parse HEAD
shasum -a 256 foundry/lib/pramana_foundry/agent_server.ex foundry/lib/pramana_foundry/coordinator.ex foundry/lib/pramana_foundry/coordinator/tick.ex foundry/lib/pramana_foundry/launch_eligibility.ex foundry/test/pramana_foundry/agent_server_test.exs foundry/test/pramana_foundry/autonomous_launch_test.exs
```

Exact focused checks:

```sh
env -u HERDR_ENV -u COORDINATOR_TICK PATH=/Users/raymondluong/.local/share/mise/installs/elixir/1.20.3-otp-29/bin:/Users/raymondluong/.local/share/mise/installs/erlang/29.0.5/bin:/usr/bin:/bin mix test --no-start test/pramana_foundry/autonomous_launch_test.exs test/pramana_foundry/agent_server_test.exs --seed 424201
env -u HERDR_ENV -u COORDINATOR_TICK PATH=/Users/raymondluong/.local/share/mise/installs/elixir/1.20.3-otp-29/bin:/Users/raymondluong/.local/share/mise/installs/erlang/29.0.5/bin:/usr/bin:/bin mix compile --warnings-as-errors
```

Results: **14 passed, exit 0**, 0.1s reported test time; compile **exit 0**.
`--no-start` deliberately prevented the application/daemon tree from starting.
Fake-runner success/failure cases were exercised; existing cleanup attempts
returned `:herdr_env_not_set`. Excluding `/opt/homebrew/bin` prevented the new
test's temporary `HERDR_ENV=1` from enabling real Herdr. No cleanup/model command
could resolve the real Herdr executable in this process.

All three supplemental probes used the same exact `env`/PATH prefix above followed
by `mix run --no-start -e 'BODY'`. Bodies below are the executed Elixir inputs.
They do not write source or start the application. Probe exits were 0 except the
explicitly recorded initial temporary-directory setup mistake below.

### Probe 1: malformed policy and contradictory route

```elixir
alias PramanaFoundry.LaunchEligibility, as: L
p = %{"provider" => "openai-codex", "account" => "approved-subscription", "billing_class" => "subscription", "subscription_authorized" => true, "premium_authorized" => false, "automatic_roles" => ["developer", "reviewer", "pm"], "quota_status" => "available", "model" => "openai-codex/explicit-model", "approval_mode" => "explicit", "reasoning" => "medium"}
for {label, profile, state} <- [
  {"paid_model_labeled_subscription", Map.put(p, "model", "openrouter/deepseek/deepseek-v4-flash"), %{}},
  {"malformed_premium_boolean", Map.put(p, "premium_authorized", "true"), %{}},
  {"malformed_exhausted_boolean", Map.put(p, "exhausted", "true"), %{}},
  {"malformed_cooldown_entry", p, %{"provider_cooldowns" => %{"s" => %{}}}},
  {"malformed_cooldown_container", p, %{"provider_cooldowns" => []}},
  {"malformed_quota_status", Map.put(p, "quota_status", %{}), %{}}
] do
  result = try do
    case L.resolve(%{"s" => profile}, "s", :developer, state, now: 1000) do
      {:ok, selected} -> {:accepted, selected.model}
      {:error, reason} -> {:blocked, L.reason(reason)}
    end
  rescue e -> {:raised, e.__struct__} end
  IO.inspect({label, result})
end
state = %{"assignments" => %{"T" => %{"status" => "queued", "ticket" => %{}}}, "queue" => ["T"]}
result = try do
  PramanaFoundry.Coordinator.Tick.process_queue(["T"], state, %{}, nil, 1000, self(), nil, nil, 3, profiles: %{}, role_profiles: %{"developer" => "s"}, now: 1000)
  :blocked_normally
rescue e -> {:raised, e.__struct__} end
IO.inspect({"well_formed_mapping_control", result})
result = try do
  PramanaFoundry.Coordinator.Tick.process_queue(["T"], state, %{}, nil, 1000, self(), nil, nil, 3, profiles: %{}, role_profiles: [], now: 1000)
rescue e -> {:raised, e.__struct__} end
IO.inspect({"malformed_role_mapping", result})
```

Output: paid-model case accepted the OpenRouter model; malformed premium,
exhausted and cooldown-entry cases accepted `openai-codex/explicit-model`;
cooldown-container and role-mapping cases raised `ArgumentError`; quota-status
case raised `Protocol.UndefinedError`; mapping control blocked normally.

### Probe 2: actual AgentServer-to-adapter argv

```elixir
Code.require_file("test/support/agent_server_fake_runner.ex")
alias PramanaFoundry.AgentServerTest.FakeRunner
alias PramanaFoundry.{AgentServer, Herdr.Adapter}
table = :fr01_review_boundary
FakeRunner.create_table(table)
FakeRunner.install(table, fn
  ["herdr", "pane", "split" | _] -> FakeRunner.json(%{"result" => %{"pane" => %{"pane_id" => "review-fake-pane", "terminal_id" => "review-fake-terminal"}}})
  ["herdr", "agent", "start" | _] -> {:error, :review_probe_stop_before_model}
end)
p = %{"provider" => "openai-codex", "account" => "account-A", "billing_class" => "subscription", "subscription_authorized" => true, "automatic_roles" => ["developer"], "quota_status" => "available", "model" => "openrouter/deepseek/deepseek-v4-flash", "approval_mode" => "explicit", "reasoning" => "high"}
traces = for profile <- [p, Map.merge(p, %{"account" => "account-B", "reasoning" => "low"})] do
  :ets.insert(table, {:calls, []})
  {:ok, state} = AgentServer.init(task_id: "T-BOUNDARY", run_id: "same-run", checkout: "/tmp/unused-fr01-review", role: :developer, profile: "s", launch_profiles: %{"s" => profile}, adapter: Adapter.new(FakeRunner), coordinator_pid: self(), herdr_opts: [ets_table: table])
  {:stop, {:launch_failed, :agent_start_failed, :review_probe_stop_before_model}, _} = AgentServer.handle_info(:launch, state)
  FakeRunner.calls(table)
end
IO.inspect(hd(traces), label: "captured_adapter_calls", limit: :infinity)
IO.inspect(Enum.at(traces, 0) == Enum.at(traces, 1), label: "changing_account_and_reasoning_keeps_identical_argv")
```

Captured start:

```text
["herdr", "agent", "start", "pramana-dev-same-run", "--kind", "omp",
 "--pane", "review-fake-pane", "--timeout", "30000", "--", "--model",
 "openrouter/deepseek/deepseek-v4-flash", "--approval-mode", "explicit"]
changing_account_and_reasoning_keeps_identical_argv: true
```

Pane argv contained subscription/provider/profile labels, but no account or
reasoning. Fake calls stopped before prompt/model execution; the cleanup branch
returned `:herdr_env_not_set`.

### Probe 3: preservation of the new reviewer block

```elixir
alias PramanaFoundry.{Coordinator, Coordinator.Tick}
{tmp, 0} = System.cmd("mktemp", ["-d", "/tmp/pramana-fr01-review.XXXXXX"])
tmp = String.trim(tmp)
try do
  state = %{"assignments" => %{"T" => %{"status" => "handoff_received", "run_id" => "dev-run", "work_retries" => 0}}, "queue" => []}
  blocked = Tick.block_assignment(state, "T", :reviewer, "no subscription profile configured for reviewer")
  data = %{state: blocked, event_log_path: Path.join(tmp, "events.jsonl"), telemetry_path: nil, agent_registry: %{}, max_work_retries: 2}
  {:noreply, completed} = Coordinator.handle_info({:agent_completed, "T", "dev-run", :review_timeout, %{}}, data)
  IO.inspect(get_in(completed, [:state, "assignments", "T", "status"]), label: "blocked_after_developer_review_timeout")
  {:noreply, crashed} = Coordinator.handle_info({:agent_crashed, "T", "dev-run", :unexpected_exit, %{}}, data)
  IO.inspect({get_in(crashed, [:state, "assignments", "T", "status"]), crashed.state["queue"]}, label: "blocked_after_developer_crash")
after
  File.rm_rf!(tmp)
end
```

Output is quoted in B3. The initial run mistakenly matched `System.cmd` as
`{:ok, tmp}`, exited 1 before the probe, and created only the empty directory
`/tmp/pramana-fr01-review.owLhma`. `rmdir /tmp/pramana-fr01-review.owLhma`
exited 0. The corrected run above exited 0 and removed only its own disposable
event directory. Neither run touched Foundry live state.

## Limits and disposition

The earlier implementation-log report of 313 tests was inspected, not independently
rerun here; it is not upgraded to lifecycle/spending proof by this review. No actual
subscription, OMP authentication behavior, account switch, provider quota event,
restart, deployment or OS isolation was exercised. No assertion claims a real paid
request occurred: B1 proves that the prohibited model reaches the actual application
launch boundary, not that a provider billed it.

Return candidate v1 for correction of B1–B3. Preserve the frozen evidence. Review
the corrected exact working tree and rerun relevant boundary tests before closing
FR-01; later-ticket obligations remain open even after containment passes.
