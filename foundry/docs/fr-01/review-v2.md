# FR-01 candidate v2 — renewed independent review

**Verdict: FAIL — B1/B2/B3 improved but not fully resolved.** Reviewed 2026-09-12
(HST) by `/root/fr01_review`. The new flags are real OMP flags, the ordinary
malformed JSON/map cases now block, and developer completion/crash no longer
erase a reviewer block. Residual route/authentication, malformed-input and
late-launch-failure cases still defeat the claimed containment.

Only this new repository document was written. No source/test/plan edits,
staging, commit, daemon, activation, provider/model invocation, credential access
or live-state mutation. The installed OMP executable was inspected as bytes,
not executed. Test/build output and disposable probe directories were the only
other writes; probe directories were removed after use.

## Frozen candidate

HEAD remained `a3fa302342238ae3d5a133b35bd86f4fa4f13710`. All six candidate hashes
matched at entry and completion:

| File, relative to `foundry/` | SHA-256 |
|---|---|
| `lib/pramana_foundry/agent_server.ex` | `505ebd8a8e9de1b61c05dcac02e6597c0367b54df52c4f3800174b7b1a467057` |
| `lib/pramana_foundry/coordinator.ex` | `1f7f65a5ebb8b6690e7ae8ee1b2a402cb8eee4d4511ae6964719f6d0cc2f3b0d` |
| `lib/pramana_foundry/coordinator/tick.ex` | `8d06d93b001aef78928f0980eee940c2629ffadc4fc04fd27de14afe4b691f7c` |
| `lib/pramana_foundry/launch_eligibility.ex` | `89d8f2170a89f76c05173b298880919d4bf3b6b8f648c58168f8eab22f65f0e6` |
| `test/pramana_foundry/agent_server_test.exs` | `914d266e4e48096076e2f412de601fb6a8aa68df444ccdf1195a8e41d0411f46` |
| `test/pramana_foundry/autonomous_launch_test.exs` | `5a47b10095d8734599eeab5f0092cb03fb01d01ef7f66719ac2db2abc8c26fec` |

The original dirty Coordinator baseline was
`1e184cf4c52f500ad2859f6e883a5508ec83e50da2ca1811a281673c7e1cf30`.
Its unrelated `unblock_ticket` wrapper/handler are excluded, as in v1. The v1
review remains historical evidence; this report assesses the corrected working
tree, not HEAD alone. Shared contract, audit F01, FR-01 routing and R2/R5 remain
the standards from the preceding review. The v2 implementation-log record was
also inspected.

## B1 — Residual blocker: OMP profile/selector flags do not establish the claimed billing and exact-model boundary

**What is fixed:** `agent_server.ex:422–428` now supplies explicit `--profile`,
`--provider`, `--model`, `--thinking` and `--approval-mode`. The ineffective pane
environment labels are removed. The focused suite exercises actual Tick →
AgentServer → Adapter/Argv → fake runner, verifies those flags, and checks that
changing account/reasoning changes argv. An unlisted model is rejected before
child construction. The v1 problem of silently dropping account/reasoning is
resolved.

**What remains:** the reviewed installed OMP executable is
`/Users/raymondluong/.local/bin/omp`, SHA-256
`defc1d398d6a90f34998d5120fb5b53cf7ae08c10dff91b834cab5a3b0461119`.
Its embedded source provides more precise evidence than the option names:

- `packages/utils/src/dirs.ts`, bundled `FD`/`D7e`/`Fee`: `--profile` selects
  configuration/state directories. It is not a subscription-only authentication
  switch or a credential/account-ID assertion. `FD` trims the name and treats
  blank input and `default` as the default profile.
- `packages/ai/src/auth-storage.ts`, bundled `getApiKey(e,t,s)` at byte offset
  `78813374`: after attempting OAuth credentials, it can return a stored API-key
  credential, then `to(e)` (exported as `getEnvApiKey`), then another stored
  API-key credential/fallback resolver. The Foundry launch neither disables these
  alternatives nor verifies which billing/authentication path will be used.
- `packages/coding-agent/src/config/model-resolver.ts`, bundled `gm` at byte
  offset `81634577`: a supplied provider limits the candidate provider, but after
  the exact reference lookup misses, the CLI still invokes its model matcher
  `Eh` on that provider's catalog. Passing `--model` does not make an arbitrary
  selector an exact model ID. The new allow-list checks raw string membership,
  not the resolved provider/model identity.

**Exercised without OMP execution:** Foundry accepts a profile with
`account="   "`; the inspected OMP normalizer resolves that string to default.
Foundry also accepts `model="claude", allowed_models=["claude"]`, although that
is a selector rather than a pinned model identity. No real model resolution or
credential fallback was run; the latter paths are established by installed
source, not an assertion about the operator's current credentials or usage.

An operator's explicit subscription authorization remains necessary, but this
candidate does not enforce it at the execution boundary. Named profile selection
alone cannot distinguish that profile's subscription authentication from an
API-key alternative. This is the same spending-boundary obligation as B1, not a
request to finish all credential isolation in this containment ticket.

**Required bounded correction:** reject blank/noncanonical/unsupported OMP
profile identities before pane creation; bind or verify a supported exact
provider/model identity rather than arbitrary matcher syntax; require a launch
mechanism that demonstrably restricts the configured execution to its authorized
subscription path. If the current mechanism cannot make that guarantee, block
that route with a reason until its FR-09/15a proof exists. Do not certify a route
by testing fake flags alone or infer entitlement from provider/model spelling.
Full protected gateway, OS isolation, reusable credential custody and bounded
live smoke remain downstream obligations.

## B2 — Residual blocker: validators are not total on malformed Elixir maps

**What is fixed:** `select_profile/3` distinguishes absence from explicit false,
validates role mappings and preserves explicit-profile precedence. Boolean,
enum, known-field, required-field, role-list, model-list and cooldown shape checks
cover the v1 malformed ordinary map cases. The expanded tests exercise those
cases through developer Tick, both reviewer handlers and AgentServer with zero
fake-runner calls. Premium and paid are now independently tested.

**What remains:** `is_map` admits structs, but the validator then enumerates
them using `Enum.reduce_while`/`Enum.find`. A struct without the Enumerable
protocol raises instead of returning a blocked reason. Reproduced:

```text
profiles = %URI{}                         -> Protocol.UndefinedError
state.provider_cooldowns = %URI{}         -> Protocol.UndefinedError
```

Locations: `launch_eligibility.ex:123–151,289–309`. Role-profile mappings have
the same `is_map`/Enum pattern by source inspection. These inputs are not JSON
values, but policy is accepted directly from Elixir application configuration/
opts and the public resolver advertises `term()` inputs. Strict total fail-closed
behavior cannot rely on the input having been JSON decoded elsewhere. The
whitespace account issue is additionally covered under B1.

**Required correction:** reject unsupported structs/containers explicitly or
validate using operations whose supported input matches the guards. Extend the
malformed matrix to struct containers through each reachable launch boundary;
preserve stable reason and zero adapter effects. No need for a general workflow
state validator or a persistence redesign.

## B3 — Residual blocker: late launch failure still requeues blocked reviewer work

**What is fixed:** `Tick.block_assignment/4` records `blocked_role`; the new
Coordinator wrappers at `coordinator.ex:740–753` preserve a reviewer-blocked
assignment across developer timeout/completion/crash, including its handoff,
original role and reason. The test calls the real handoff handler to create the
block, delivers these messages and then invokes Tick; the full assignment stays
unchanged and no runner call occurs. The three specific v1 reproductions are
resolved.

**What remains:** the earlier `{:agent_launched, task_id, {:error,...}, ...}`
handler at `coordinator.ex:663–703` does not consult the block. Delivering an
outstanding/late launch failure changes the assignment back to queued and
increments `launch_retries`, retaining only a stale `blocked_role` field:

```text
reviewer_block_after_late_launch_failure: {"queued", ["T"], "reviewer"}
```

This was exercised using the candidate's own block helper and actual Coordinator
callback with disposable event/log paths. The handler has no run identity and
can be reached by an earlier launch outcome; it does not require any new authority
or a deliberate unblock. A later Tick checks only `status=queued`, so the
eligible developer can launch again while reviewer eligibility is still missing.
The current successful-launch callback can also mutate pane/agent attribution
on a blocked assignment, although it does not itself change the blocked status.

**Required correction:** conservatively preserve the reviewer eligibility block
against outstanding launch success/failure messages as well as completion/crash,
and test the subsequent Tick with an otherwise eligible developer profile.
General stale-execution fencing remains FR-10/11; no full identity redesign is
needed to stop these messages from authorizing progress past a new block.

## Scope, deferred obligations and suggestions

No new automatic PM model caller or fallback launcher was introduced. The
production constructors remain developer Tick plus initial/retry reviewer in
Coordinator. PM/HardeningPM/Improver remain deterministic proposal logic, and
`Effects.Launch`/quota fallback remain unwired helpers. PM rejection is tested at
AgentServer; no real PM execution capability is claimed. The candidate adds no
manual paid path, switching, weakening of review gates or activation change.

The following remain **deferred**, not waived by this review:

- FR-07/08/10/11: durable block/assignment identity, full resolved profile and
  limits on the attempt, replay/recovery, protected budget ledger and role-aware
  lifecycle. In-memory block preservation is only immediate containment.
- FR-09/15a/16: actual provider quota observations/freshness, subscription
  entitlement evidence, installed harness proof, protected policy/authentication,
  account/egress isolation and bounded subscription switching. Static configured
  `quota_status` and profile-keyed cooldown input are not live provider knowledge.
  B1 specifically prevents accepting currently unsupported routes while those
  downstream mechanisms remain unfinished.
- FR-04/21: direct System-runner pane cleanup still bypasses the fake adapter.
  Focused tests set `HERDR_ENV=1`, so the restricted PATH used below is required
  to prevent real Herdr cleanup. This review did not exercise real cleanup.
- FR-22: full autonomous lifecycle and spending closure. The implementer's full
  suite report (316/317, two integration exclusions, tiktoken timeout) was not
  independently rerun or counted as a green whole-system gate here.

Suggestions: document the exact temporary configuration schema, OMP profile
meaning, normalization/selection constraints, defaults, static quota limitations
and the protected-policy migration once the route contract is corrected. Retain
the v1/v2 reports and publish each residual's disposition. The new denial tests
are useful actual application-boundary tests; they still do not observe installed
OMP authentication or model-selector resolution.

## Commands and evidence

Verification from the repository root, exit 0 with hashes above:

```sh
git rev-parse HEAD
shasum -a 256 foundry/lib/pramana_foundry/agent_server.ex foundry/lib/pramana_foundry/coordinator.ex foundry/lib/pramana_foundry/coordinator/tick.ex foundry/lib/pramana_foundry/launch_eligibility.ex foundry/test/pramana_foundry/agent_server_test.exs foundry/test/pramana_foundry/autonomous_launch_test.exs
```

Focused checks from `foundry/`:

```sh
env -u HERDR_ENV -u COORDINATOR_TICK PATH=/Users/raymondluong/.local/share/mise/installs/elixir/1.20.3-otp-29/bin:/Users/raymondluong/.local/share/mise/installs/erlang/29.0.5/bin:/usr/bin:/bin mix test --no-start test/pramana_foundry/autonomous_launch_test.exs test/pramana_foundry/agent_server_test.exs --seed 424201
env -u HERDR_ENV -u COORDINATOR_TICK PATH=/Users/raymondluong/.local/share/mise/installs/elixir/1.20.3-otp-29/bin:/Users/raymondluong/.local/share/mise/installs/erlang/29.0.5/bin:/usr/bin:/bin mix compile --warnings-as-errors
git diff --check
```

Results: **20 passed, exit 0**, 0.4s reported test time; compile **exit 0**;
diff check **exit 0**. `--no-start` prevented the application/daemon tree from
starting, and PATH excluded both real Herdr and OMP. Expected fake launch errors
appeared in the tests; cleanup was denied by environment. No broad suite or
provider benchmark was run.

Both supplementary probes used the exact environment/PATH prefix above followed
by `mix run --no-start -e 'BODY'`. Each exited 0; BODY was as follows.

### Malformed/container and selector probe

```elixir
alias PramanaFoundry.LaunchEligibility, as: L
p = %{"provider" => "anthropic", "account" => "sub-account", "billing_class" => "subscription", "subscription_authorized" => true, "automatic_roles" => ["developer"], "quota_status" => "available", "model" => "claude", "allowed_models" => ["claude"], "approval_mode" => "write", "reasoning" => "high"}
for {label, profiles, state} <- [
  {"whitespace_account", %{"s" => Map.put(p, "account", "   ")}, %{}},
  {"fuzzy_model_selector", %{"s" => p}, %{}},
  {"profiles_struct", %URI{}, %{}},
  {"cooldowns_struct", %{"s" => p}, %{"provider_cooldowns" => %URI{}}}
] do
  result = try do
    case L.resolve(profiles, "s", :developer, state, now: 1000) do
      {:ok, selected} -> {:accepted, selected.account, selected.model}
      {:error, reason} -> {:blocked, L.reason(reason)}
    end
  rescue e -> {:raised, e.__struct__} end
  IO.inspect({label, result})
end
```

```text
{"whitespace_account", {:accepted, "   ", "claude"}}
{"fuzzy_model_selector", {:accepted, "sub-account", "claude"}}
{"profiles_struct", {:raised, Protocol.UndefinedError}}
{"cooldowns_struct", {:raised, Protocol.UndefinedError}}
```

### Late launch-failure probe

```elixir
alias PramanaFoundry.{Coordinator, Coordinator.Tick}
{tmp, 0} = System.cmd("mktemp", ["-d", "/tmp/pramana-fr01-review-v2.XXXXXX"])
tmp = String.trim(tmp)
try do
  assignment = %{"status" => "handoff_received", "run_id" => "dev-run", "role" => "developer", "handoff" => %{"commit" => "frozen"}}
  state = %{"assignments" => %{"T" => assignment}, "queue" => []}
  blocked = Tick.block_assignment(state, "T", :reviewer, "reviewer subscription unavailable")
  data = %{state: blocked, event_log_path: Path.join(tmp, "events.jsonl"), coordinator_log_path: Path.join(tmp, "coord.jsonl"), telemetry_path: nil, agent_registry: %{}, max_launch_retries: 3}
  {:noreply, returned} = Coordinator.handle_info({:agent_launched, "T", {:error, :agent_start_failed, :late_failure}, %{}}, data)
  IO.inspect({get_in(returned, [:state, "assignments", "T", "status"]), returned.state["queue"], get_in(returned, [:state, "assignments", "T", "blocked_role"])}, label: "reviewer_block_after_late_launch_failure")
after
  File.rm_rf!(tmp)
end
```

Output is quoted under B3. Only the probe's own temporary log directory was
removed. No application process or fake/real provider runner was needed.

### Installed OMP static inspection

`command -v omp` identified the executable above. An initial attempt to read it
with `sed` exposed its Mach-O header rather than a shell launcher; subsequent
inspection used bounded Ruby substring extraction from the binary's embedded
JavaScript source. No executable, configuration, credential or profile was loaded
by OMP. Hash verification exited 0:

```sh
shasum -a 256 /Users/raymondluong/.local/bin/omp
```

Exact source-location extraction command, exit 0:

```sh
ruby -e 's=File.binread(ARGV[0]); ["function FD(", "function gm(", "  async getApiKey(e, t, s) {", "function D7e("].each { |needle| i=s.index(needle); marker=s.rindex("// packages/",i); puts "SOURCE #{s[marker,s.index("\n",marker)-marker]} OFFSET #{i}"; puts s[i,needle.include?("getApiKey") ? 900 : 430] }' /Users/raymondluong/.local/bin/omp
```

Other bounded reads used the same `File.binread`/`String#index` pattern for
`function gm(`, `function Qz(`, `function Eh(`, `function to(`,
`getEnvApiKey:`, `class Fee`, and the profile-name regex. In `gm`, the exact
lookup `Qz(c,f,a)` is followed, on failure, by `Eh(f,m,r,...)`, with `m`
restricted to the explicit provider. `getEnvApiKey` exports `to`; its body reads
the provider's configured environment-key name. These source facts support the
residual findings, but do not prove which credential or model a real operator
profile would select; that was deliberately not inspected or executed.

## Disposition

Return v2 for bounded correction of the residual B1–B3 cases. Do not treat this
review as authorization to launch a subscription smoke, provision credentials,
enable the daemon or implement the downstream gateway. A corrected candidate
needs another exact-tree review and relevant boundary checks. Full F01 and the
R2/R5 implementation obligations remain open.
