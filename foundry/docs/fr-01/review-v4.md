# FR-01 candidate v4 — independent review

**Verdict: FAIL — one bounded malformed-policy validation blocker.**
V4 fixes v3's improper-list crashes and terminal-newline selectors. Production
automatic launches remain disabled, and B1/B3 remain resolved for static
containment. An unknown nil profile key still passes validation and can mask
another unknown field. All four automatic launch boundaries accept that malformed
profile and reach the deterministic fake pane adapter.

Reviewed 2026-09-12 HST by /root/fr01_review against the exact working tree.
Only this new repository document was written. No source, tests, plans or log
were edited; nothing was staged or committed. No provider/model, installed
daemon, credentials, activation or live state was used.

## Frozen input and scope

HEAD: 5179f34b3dd914808181b8c2513b393f9b38fe75. Its baseline integration changes
documentation and documentation evidence only; none of these twelve source/test
files changed in that commit. All twelve hashes matched at entry and after the
probes. Only LaunchEligibility and autonomous_launch_test differ from v3.

| File relative to foundry/ | SHA-256 |
|---|---|
| lib/pramana_foundry/agent_server.ex | 1a8dbcd8d14a3f21034d50517bd797977f44a6c592d0940bbeaf0a16a80c7949 |
| lib/pramana_foundry/coordinator.ex | 241643abf3a1be26d808bfc26055ca9f66665297400ce93b517855f5fa2db0e7 |
| lib/pramana_foundry/coordinator/tick.ex | e4a40c7c9c056b9ca1801724ab5de40d10e0cf45a408f3c60e76238dac0669d5 |
| lib/pramana_foundry/herdr/adapter.ex | 4ec26d65483c3c5321cab05b14beb4573f39c3131d211dc18b44aa65970c49cf |
| lib/pramana_foundry/herdr/runner.ex | 1df506bc0444df2326de7fd9328e72038d990e2bbc36f5c9e038abbbc0fa2650 |
| lib/pramana_foundry/launch_eligibility.ex | f8cfdf6e15a106344d8c28f58648b91fe8a6ad4906f6684d5d70dc78d03e5c2a |
| test/pramana_foundry/agent_server_test.exs | 914d266e4e48096076e2f412de601fb6a8aa68df444ccdf1195a8e41d0411f46 |
| test/pramana_foundry/autonomous_launch_test.exs | 438e40876401d89c1d4ca28f139beb7c5f30abaa354880f5c18cd243920c4673 |
| test/pramana_foundry/board_test.exs | cd455afc307d9fd3b9794d2d8862d817b848016a632f7dc438f02f38c8ca6637 |
| test/pramana_foundry/coordinator/engine_test.exs | e0471669fc52ff8db46efebcb75bda90b9e4bba1e8a1cb610602c200da20fa7c |
| test/pramana_foundry/coordinator_test.exs | c2068847f4497e56a9c65180b670c7347e7fb2b925a1f2f8a2454e3e4b0b25a2 |
| test/support/agent_server_fake_runner.ex | c84f22d4f0e2abf518753f785f74a85682e423a8c4d58c42a9692ea37063cf7e |

The original pre-baseline HEAD was a3fa302342238ae3d5a133b35bd86f4fa4f13710.
The unrelated dirty Coordinator unblock_ticket baseline
1e184cf4c52f500ad2859f6e883a5508ec83e50da2ca1811a281673c7e1cf30 remains
excluded, not claimed as FR-01. Review used the project instructions, repair-plan
FR-01/shared contract/F01 routing, WORKFLOW-CONTRACT R2/R5, prior reviews and
current implementation log. Runtime bytes, not HEAD alone or a combined digest,
bind this verdict.

## Earlier blocker disposition

**B1 remains resolved for static containment, not subscription conformance.**
System's optional capability callback unconditionally returns unsupported.
Coordinator constructs that System runner directly, with no configuration/caller
option to declare it enforced. Adapter accepts only the exact enforced atom,
and missing, invalid, raising, throwing or exiting callbacks fail closed.
Tick and both reviewer paths gate before child/pane admission; AgentServer
independently gates before scheduling launch. The focused tests rerun these
boundaries, including System and invalid capability cases.

The fake runner is a legitimate deterministic test backend: its declaration
authorizes only its in-memory scripted execution, not real provider entitlement.
It is loaded from test support and does not alter System. The exact profile,
provider, model, thinking and approval-mode argv checks remain. No hidden
DeepSeek/OpenRouter/default approval fallback, manual-path weakening or dynamic
switching was introduced. Source tracing still finds only developer Tick and
initial/retry reviewer constructors; there is no autonomous PM model caller.
PM proposal helpers are not a model launch; existing Effects.Launch and quota
fallback helpers have no production orchestration call site.

**B3 remains resolved for the reviewed in-memory reviewer block.** All
agent_launched successes/failures, completions and crashes preserve the whole
reviewer-blocked assignment, including role, candidate/handoff and reason.
Registry references are removed without requeue; the subsequent Tick skips it.
The focused test obtains the block through the handoff handler, then exercises
each callback and Tick, asserting assignment equality and zero adapter calls.
General execution fencing, owned cleanup and restart durability remain deferred.

**V3's listed B2 residuals are fixed.** Recursive proper-list checking precedes
enumeration, including nested improper-element rejection. Whole-string anchors,
valid-UTF-8 checks and unchanged-trim checks reject terminal newlines and malformed
identities. Canonical profile/provider/model syntax and exact model allow-list
equality are enforced without normalization. These are syntax checks, not a
provider catalog or installed OMP selector/entitlement proof.

## Blocker B2 — nil sentinel defeats unknown-field rejection

At lib/pramana_foundry/launch_eligibility.ex:200, only_known_fields/2 uses
Enum.find over profile keys, then treats nil as absence of an offending key.
An actual unknown nil key is indistinguishable from that sentinel. Consequently,
adding nil => :invalid to an otherwise valid profile returns an authorized
profile. On this candidate/runtime it also masks a second unknown string key:

    %{"credential" => "implicit"}                   # rejected
    %{nil => :invalid, "credential" => "implicit"}  # accepted

The second line is not credential execution: both extra fields are ignored.
The defect is acceptance of malformed policy despite the common strict
known-field contract. Required subscription/model/quota checks still execute,
and System remains unsupported, so this is not a reopened production spending
route. It is a blocker under this review's explicit arbitrary-term,
malformed-policy and zero-launch-on-denial requirement, not a request to expand
FR-01 into gateway or lifecycle work.

Independent probes supplied the nil-key profile through the actual boundaries.
A test-only fake stopped on its first pane-split call; no pane was created:

| Boundary | Observed result | Fake adapter calls |
|---|---|---|
| Tick | dispatched; launched log entry | 1 |
| AgentServer, PM role | init authorized; launch reached pane split | 1 |
| Initial reviewer | reviewer child launched | 1 |
| Retry reviewer | reviewer child launched | 1 |

The appropriate result for this malformed configuration is a stable blocked
reason before any adapter action. Use an unambiguous unknown-key check; include
nil alone and nil masking another unknown key in the public-boundary denial
matrix. Other Enum.find sites inspected either search fixed string field lists
or return key/value tuples, so they do not share this particular collision.

## Verification and exact commands

From repository root, these read-only checks returned expected HEAD/hashes and
exit 0:

    git rev-parse HEAD
    git show --stat --oneline HEAD
    shasum -a 256 foundry/lib/pramana_foundry/agent_server.ex foundry/lib/pramana_foundry/coordinator.ex foundry/lib/pramana_foundry/coordinator/tick.ex foundry/lib/pramana_foundry/herdr/adapter.ex foundry/lib/pramana_foundry/herdr/runner.ex foundry/lib/pramana_foundry/launch_eligibility.ex foundry/test/pramana_foundry/agent_server_test.exs foundry/test/pramana_foundry/autonomous_launch_test.exs foundry/test/pramana_foundry/board_test.exs foundry/test/pramana_foundry/coordinator/engine_test.exs foundry/test/pramana_foundry/coordinator_test.exs foundry/test/support/agent_server_fake_runner.ex
    git diff --check
    rg -n 'AgentServer|Effects.Launch|pick_fallback|fallback_profile' foundry/lib
    rg --files foundry/lib/pramana_foundry | rg 'pm|improver'

The following exact commands ran from foundry/. PATH deliberately excludes Herdr
and OMP; --no-start prevents application/daemon startup:

    env -u HERDR_ENV -u COORDINATOR_TICK PATH=/Users/raymondluong/.local/share/mise/installs/elixir/1.20.3-otp-29/bin:/Users/raymondluong/.local/share/mise/installs/erlang/29.0.5/bin:/usr/bin:/bin mix test --no-start test/pramana_foundry/autonomous_launch_test.exs test/pramana_foundry/agent_server_test.exs --seed 424201
    env -u HERDR_ENV -u COORDINATOR_TICK PATH=/Users/raymondluong/.local/share/mise/installs/elixir/1.20.3-otp-29/bin:/Users/raymondluong/.local/share/mise/installs/erlang/29.0.5/bin:/usr/bin:/bin mix test --no-start test/pramana_foundry/herdr/adapter_test.exs test/pramana_foundry/herdr/argv_test.exs test/pramana_foundry/herdr/identity_test.exs test/pramana_foundry/quota/quota_test.exs test/pramana_foundry/reviews/reviews_test.exs test/pramana_foundry/coordinator/recovery_test.exs --seed 424201
    env -u HERDR_ENV -u COORDINATOR_TICK PATH=/Users/raymondluong/.local/share/mise/installs/elixir/1.20.3-otp-29/bin:/Users/raymondluong/.local/share/mise/installs/erlang/29.0.5/bin:/usr/bin:/bin mix compile --warnings-as-errors

Results: focused **25 passed**, 0.6 seconds; supporting **44 passed**, 0.3 seconds;
compile exit 0; diff check exit 0. Expected fake launch-failure/timeout logs are
not test failures. These are separate selected suites, not a coverage figure or
whole-system gate.

Adversarial probes used the same restricted environment/PATH, with
mix run --no-start -e 'BODY'. A finite 460-call matrix placed 23 terms at eight
public selector/resolver positions and every one of twelve profile fields:
nil, booleans, atom, integer/negative/float, empty binary, invalid UTF-8,
non-byte bitstring, empty/proper/improper/nested-improper lists, plain map,
URI struct, PID, reference, function, tuple, newline/space/CRLF strings.
Results: 454 errors with printable reasons, six legitimate accepted values,
zero exceptions. This is bounded empirical evidence, not proof over every BEAM
term. Unknown-key probing separately found the nil collision above.

An initial matrix command exited 1 because the review probe destructured the
fake policy map as a tuple; no candidate call ran. Correcting it to
%{profiles: profiles, role_profiles: mappings} yielded the results above.
A source-search command initially named nonexistent pm.ex and exited 2;
the corrected recursive search above completed. Neither is a candidate failure.

Exact minimal masking reproduction BODY (exit 0):

    Code.require_file("test/support/agent_server_fake_runner.ex")
    p = PramanaFoundry.AgentServerTest.FakeRunner.launch_policy().profiles
    for extra <- [%{"credential" => "implicit"}, %{nil => :invalid, "credential" => "implicit"}] do
      bad = Map.update!(p, "test-subscription", &Map.merge(&1, extra))
      IO.inspect({extra, PramanaFoundry.LaunchEligibility.resolve(bad, "test-subscription", :developer)}, label: "unknown_key_masking")
    end

Exact actual-boundary reproduction BODY (exit 0):

    Code.require_file("test/support/agent_server_fake_runner.ex")
    alias PramanaFoundry.{AgentServer, Coordinator, Coordinator.State, Coordinator.Tick, Herdr.Adapter}
    alias PramanaFoundry.AgentServerTest.FakeRunner
    Logger.configure(level: :emergency)
    {tmp, 0} = System.cmd("mktemp", ["-d", "/tmp/pramana-fr01-review-v4-boundary.XXXXXX"])
    tmp = String.trim(tmp)
    table = :fr01_v4_boundary
    FakeRunner.create_table(table)
    FakeRunner.install(table, fn _argv -> {:error, :review_probe_stop} end)
    policy = FakeRunner.launch_policy()
    profiles = update_in(policy.profiles, ["test-subscription"], &Map.put(&1, nil, :invalid))
    adapter = Adapter.new(FakeRunner)
    base = String.duplicate("1", 40)
    commit = String.duplicate("2", 40)
    System.put_env("HERDR_ENV", "1")
    {:ok, supervisor} = DynamicSupervisor.start_link(name: PramanaFoundry.AssignmentSupervisor, strategy: :one_for_one)
    try do
      for path <- [:tick, :server, :initial_reviewer, :retry_reviewer] do
        :ets.insert(table, {:calls, []})
        ticket = %{"task_id" => "T", "base_revision" => base, "scope" => ["lib/**"], "exclusions" => [], "required_checks" => [["true"]], "review_required_checks" => [["true"]], "checkout" => "/tmp/unused-fr01", "profile" => "test-subscription", "reviewer_profile" => "test-subscription"}
        {:ok, queued} = State.enqueue_ticket(State.new(accepted_revision: base), ticket)
        {:ok, _, dispatched} = State.admit_assignment(queued, "T", "run", "developer")
        handoff = %{"schema_version" => 1, "task_id" => "T", "run_id" => "run", "assigned_base" => base, "commit" => commit, "changed_files" => ["lib/a.ex"], "reproduction_evidence" => %{"before" => "fail", "after" => "pass"}, "checks" => [%{"command" => ["true"], "exit_code" => 0}], "remaining_risks" => [], "status" => "completed", "outcome" => "probe"}
        {:ok, _, reviewing} = State.receive_handoff(dispatched, "T", handoff, skip_git_checks: true)
        review = %{"schema_version" => 1, "task_id" => "T", "run_id" => "wrong", "commit" => commit, "verdict" => "approved", "findings" => [], "remaining_risks" => [], "checks" => [%{"command" => ["true"], "exit_code" => 0}]}
        data = %{state: dispatched, event_log_path: Path.join(tmp, "events.jsonl"), herdr_adapter: adapter, herdr_timeout: 1000, telemetry_path: nil, agent_registry: %{}, launch_profiles: profiles, launch_role_profiles: policy.role_profiles, launch_now_fn: fn -> 1000 end, herdr_opts: [ets_table: table]}
        result = case path do
          :tick -> {s, _, log} = Tick.process_queue(["T"], queued, %{}, adapter, 1000, self(), Path.join(tmp, "tick.jsonl"), nil, 3, profiles: profiles, now: 1000, herdr_opts: [ets_table: table]); {s["assignments"]["T"]["status"], log}
          :server -> {:ok, state} = AgentServer.init(task_id: "T", run_id: "run", checkout: "/tmp/unused-fr01", coordinator_pid: self(), profile: "test-subscription", launch_profiles: profiles, role: :pm, adapter: adapter, launch_state: %{}, launch_now: 1000, herdr_opts: [ets_table: table]); AgentServer.handle_info(:launch, state); :init_authorized
          :initial_reviewer -> {:reply, _, d} = Coordinator.handle_call({:receive_handoff, "T", handoff, [skip_git_checks: true]}, {self(), make_ref()}, data); d.state["assignments"]["T"]["status"]
          :retry_reviewer -> {:reply, _, d} = Coordinator.handle_call({:receive_review, "T", review, [skip_git_checks: true]}, {self(), make_ref()}, %{data | state: reviewing}); d.state["assignments"]["T"]["status"]
        end
        receive do {:agent_launched, "T", {:error, :pane_split_failed, :review_probe_stop}, %{}} -> :ok after 2000 -> raise "missing fake boundary event" end
        IO.inspect({path, result, length(FakeRunner.calls(table))}, label: "nil_key_boundary")
      end
    after
      Supervisor.stop(supervisor)
      System.delete_env("HERDR_ENV")
      File.rm_rf!(tmp)
    end

This starts only a temporary DynamicSupervisor, not the application or daemon.
HERDR_ENV enables the tested branch only in that isolated process; the adapter
is fake and real executables remain excluded. Temporary event files were
removed after the probe; no user material was deleted.

## Deferred obligations and suggestions

- FR-09/15a: real subscription routing, exact installed OMP semantics, credential
  custody, protected policy and execution/egress isolation must be proved before
  automatic System execution is restored. A capability atom or regex is not that
  proof. R2/R5's protected authentication and per-request reservations are not
  claimed implemented by FR-01.
- FR-07/08/10/11/12/16: durable policy/blocks/assignments, lifecycle identity,
  recovery, actual quota observations/freshness and bounded switching remain.
  Availability/cooldown are static supplied inputs here.
- FR-04/21/22: owned cleanup, fully isolated fixtures and integrated acceptance
  remain. The unchanged fixture edits were reviewed in v3; they inject only fake
  launch configuration, not fabricated assignment results or weakened assertions.
  They were not rerun in v4; the focused and supporting sets above were.
- Suggestions from v3 remain: separately supervise/restore Coordinator test
  configuration when practical; ensure final operator docs clearly say all real
  automatic launches are disabled and name FR-09/15a as restoration owners.

No full-suite green claim, actual model/subscription conformance claim, durable
block claim or production activation approval follows from this review. Finish
the narrow unknown-field correction and renew exact-candidate review; do not
reopen the accepted production disablement or reviewer-block preservation.
