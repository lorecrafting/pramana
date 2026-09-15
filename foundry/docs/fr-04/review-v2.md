# FR-04 renewed independent review — FAIL

Reviewed 2026-09-12 (Pacific/Honolulu), frozen corrected candidate in
`/tmp/pramana-fr04`, branch `repair/fr04`, base
`5c69e6c73f572e60a6c2015e955ad841bf504517`.

Verified input SHA-256:

- Original review: `369db5d8c513034d4a2aba9eb616177ef03b281f2eb14df81877fb1605d0e124`.
- Correction response: `f00880a5c1a9ed312428d33e2f05676d0e105513b022e7fe85f4b996d2910640`.
- All fifteen implementation/test hashes match the response manifest exactly.

The correction addresses several original failures, but three blocking areas
remain. The requested focused suite independently passes all 83 tests. Direct
model-free adversarial probes reproduce the failures below.

## Remaining blockers

### R1 / B1–B2 — Shell incarnation does not identify the foreground occupant

`herdr/adapter.ex:234–263` normalizes process evidence to pane ID, terminal ID,
shell PID and `started_at`. It discards foreground process identity, even when
the backend provides it. The baseline is captured before agent start, so an
unchanged shell is entirely compatible with a different foreground process after
start, timeout or later replacement.

Independent actual-adapter probe:

```text
Captured:
  pane_id=p, terminal_id=t, shell_pid=100, started_at=shell-generation,
  foreground_pid=200, foreground_started_at=original
Live:
  pane_id=p, terminal_id=t, shell_pid=100, started_at=shell-generation,
  foreground_pid=300, foreground_started_at=replacement
Agent name/pane/terminal/native session metadata otherwise unchanged.

Adapter.close_pane -> {:ok, %{"ok" => true}}
Last argv -> ["herdr", "pane", "close", "p"]
```

This is not the explicitly deferred race between reinspection and close. The
replacement exists before reinspection and its supplied identity is discarded.
The same comparator is used by `close_fresh_pane`, which additionally has no
agent/session inspection. Thus pre-start capture fixes post-error baseline
adoption only for changes to the shell generation; it does not preserve a
replacement foreground occupant under an unchanged shell.

Required correction: evidence must identify every process occupant whose
termination the close authorizes. Fail unresolved when foreground ownership or
generation is missing/changed/unknown. Keep pre-agent and agent-owned cleanup
states distinct: a failed or timed-out start cannot authorize closing an unknown
foreground process solely because its parent shell remains the same. No live
provider is needed to prove these refusal cases.

### R2 / B3 — Production shutdown deadlocks against the ownership gateway

The new application order leaves Coordinator alive while assignments stop, but
`RuntimeOwner.terminate/2` synchronously waits for the entire subtree. AgentServer
cleanup synchronously calls Coordinator; its checked append synchronously calls
`RuntimeOwner.owned?/0`. The owner cannot answer because it is waiting for that
same subtree. See `runtime_owner.ex:76–85,119–127`,
`coordinator.ex:1167–1219`, and `agent_server.ex:91–94,638–662`.

Independent isolated production-boundary probe used the actual RuntimeOwner and
Coordinator with `require_runtime_owner: true`. A temporary owned Task, stopped
after Coordinator in reverse supervisor order, called the same
`{:record_cleanup, :pending, attrs}` gateway during shutdown. All paths were under
a new temporary root; no Herdr/provider was used. Results:

```text
drain_ms: 5019
{:error, {:recovery_required,
  {:runtime_fence_unavailable,
    {:timeout, {GenServer, :call,
      [PramanaFoundry.RuntimeOwner, :owned?, 5000]}}}}}
events_after_drain: {:ok, []}
unclean_marker_after_drain: false
```

The owned child was given an eight-second shutdown allowance and its call a
seven-second timeout, so this isolates the five-second owner query timeout
rather than a deliberately short child deadline. The owner then treats shutdown
as clean and removes its marker despite the failed pending receipt. Actual
AgentServer's default five-second supervisor shutdown deadline can cut off the
same chain even earlier. The current injected-callback shutdown test never
exercises this owner query.

Required correction: initiate/record/drain cleanup while the owner can still
serve checked ownership queries, or provide an equally fenced bounded mechanism
that does not synchronously call a terminating owner. Retain pending/unclean
evidence if draining cannot durably finish. Preserve FR-03's fence-until-subtree-
quiescence guarantee; do not solve this by dropping the ownership check or
releasing the fence early. Add a test through the real owner + Coordinator path,
including result/pending failure and drain deadline behavior.

Another B3 gap remains for unsupported identities: `cleanup_obligation/1`
serializes the observed session, while `Cleanup.validate_resource_identity/1`
rejects terminal-fallback sessions entirely. Such a resource can reach a failed
pending call with no attributable durable obligation. Nested malformed session
values can also raise in `persisted_session/1` before `record_cleanup`'s rescue.
Recording an unresolved observation must not require the destructive authority
that is specifically missing. Keep untrusted observed data distinct from verified
close authorization, and test malformed/fallback launch identities through the
AgentServer-to-Coordinator persistence path.

### R3 / B4 — Cleanup can overwrite a newer work verdict; capacity is not retained

`Cleanup.apply_result/2` restores `pending["work_status"]`, both for unresolved
results and for the final terminal result. That value is a snapshot from when
cleanup began, not necessarily the latest validated work verdict. Independently
exercised pure production functions:

```text
assignment.status = dispatched
Cleanup.apply_pending
Cleanup.preserve_work_status(..., "review_approved")
Cleanup.apply_result(..., status="unresolved")
assignment.work_status -> "dispatched"
```

A result/approval arriving while cleanup is pending is a normal interleaving;
replaying the same events must preserve that newer verdict. The terminal-result
branch uses the same stale value. Coordinator's completion handler also reads
`status` rather than the retained `work_status` when deciding whether approval
already exists, so `cleanup_blocked` can hide an existing approval and downgrade
it to `review`.

Additionally, retaining a dead PID in `agent_registry` does not reserve execution
capacity. `Coordinator.Tick.process_queue/10` does not consult registry size or
cleanup obligations before admitting another task. The effective launch limit
is DynamicSupervisor `max_children`; the stopped AgentServer has released that
slot. The claim that unresolved cleanup retains its slot is therefore not
implemented. This is a source-backed finding, not an exercised live launch.

`Cleanup.apply_pending/2` also leaves any existing queue entry untouched. Normally
admitted work has already left the queue, but rejected/retried work can have been
re-enqueued before its cleanup begins. Tick skips the now-blocked head without
removing it, so the response's claim that pending/unresolved assignments are
absent from the ordinary queue is not generally true.

Required correction: preserve the latest independent work verdict when cleanup
results arrive, filter blocked entries from the ordinary queue, and enforce
outstanding cleanup capacity in the actual admission path (or use a bounded
global recovery suspension). This need not implement FR-10 reconciliation.
Exercise overlapping result/cleanup events, existing queued entries, and another
ticket attempting admission while a dead execution retains unresolved resources.

## Corrections verified and limits preserved

- B1's CWD-only, PID-only, null and missing-generation process metadata now fail
  closed. Pane/terminal linkage is required. Exact nonempty native sessions are
  required for destructive agent cleanup; terminal fallback does not pass that
  adapter gate. The issue in R1 is the narrower process identity, not rejection
  of those original weak-map fixtures.
- B2's presentation capture now occurs before `agent start`. A changed shell
  generation during start error/timeout is preserved. No post-error recapture
  remains. R1 still applies to a replacement child under the same shell.
- Ordinary cleanup branches call checked pending before close and checked result
  afterward. Pending append failure prevents close; result append failure keeps
  durable pending evidence. Reviewer accepted/rejected and shutdown code paths
  now call this common routine. Tests cover callback failures and actual
  Coordinator checkpoint/read-back/replay; R2 is outside those fixture boundaries.
- Replayed outstanding cleanup is retained in a visible recovery state instead
  of resetting assignments. FR-03 startup reconciliation and integration remain
  suspended. The existing owner/append gateway is not bypassed.
- Coordinator CWD enumeration and direct close remain removed. The all-lib/bin
  sweep still finds only adapter pane-close construction, the pre-existing
  ProcessGroup verified signal path and the check trampoline's owned-child
  `killpg` path. No new destructive path or default System cleanup was introduced.
- The shell fixture still owns/deletes only its generated parent and invokes the
  isolated model-free Elixir test. New fixtures are Elixir; the existing Fence
  Python POSIX-lock bridge remains unchanged. No new Python implementation was added.
- F01–F24 routing and FR-03/05/09/10/15a/21/22 obligations remain unchanged.
  Full reconciliation, protected installed-backend conformance, atomic backend
  compare-and-close, real lifecycle/provider smoke and independent CI/provenance
  are still deferred to their named owners. Those deferrals do not excuse R1's
  deterministic replacement close or R2's deterministic shutdown cycle.

## Independent verification

Every executable run used a fresh `mktemp -d /tmp/pramana-fr04-v2-*.XXXXXX`
parent, separate TMPDIR and explicit separate PRAMANA_OPERATOR_RUNTIME_ROOT.
PATH was pinned to installed Elixir `1.20.3-otp-29`, Erlang `29.0.5`, `/usr/bin`
and `/bin`; MIX_ENV=test. HERDR_ENV, COORDINATOR_TICK, PRAMANA_RUNTIME_ROOT and
PRAMANA_RUNTIME_ROOT_FRESH were unset. No source/test edits or commit were made.

```text
git rev-parse HEAD
shasum -a 256 foundry/docs/fr-04/review.md foundry/docs/fr-04/review-response.md
git diff --name-only -z | xargs -0 shasum -a 256
shasum -a 256 foundry/lib/pramana_foundry/cleanup.ex
git diff --check

# From foundry/ under isolated environment:
mix test test/pramana_foundry/herdr/adapter_test.exs \
  test/pramana_foundry/agent_server_test.exs \
  test/pramana_foundry/coordinator_test.exs \
  test/pramana_foundry/transition_test.exs \
  test/pramana_foundry/daemon_recovery_test.exs \
  test/pramana_foundry/autonomous_launch_test.exs \
  test/pramana_foundry/stress_test.exs --seed 40423
# 83 passed, exit 0; the same two legacy stress warnings.

mix run --no-start -r test/pramana_foundry/herdr/support/fake_runner.exs -e '...'
# Actual adapter foreground replacement and pure Cleanup interleaving probes:
# exit 0, unsafe results shown under R1/R3.

mix run --no-start -e '...'
# Actual isolated RuntimeOwner/Coordinator plus owned shutdown Task:
# corrected harness exit 0; R2 results above.
```

The first shutdown probe exited 1 because the test caller remained linked to the
normally shutting-down owner. A fresh-root repeat unlinked only the test caller,
retaining the actual owner/subtree links, and captured the failure evidence above.
No OS process was killed by the reviewer. The isolated owner naturally closed its
own Fence bridge and removed its own shutdown marker. Temporary probe parents
were left in place. No live daemon, pane, provider, credential, production state,
activation, real shell/pane close or full suite was exercised.

## Verified corrected manifest

```text
bbf27c265bfa56236c8884f04355432ab1156802fbe36924b723697a2c50c4cd  foundry/bin/test_daemon_recovery.sh
7b27c3743d2b920aea433b44910c80c0b4b43a085459f9ce203b80da53384856  foundry/lib/pramana_foundry/agent_server.ex
2acd833e4c3bbffa87d110d6c986dc699ee98469cb884b87fbd9dfa8fdeb3786  foundry/lib/pramana_foundry/application.ex
88258fdf40ee0690287dbd454654d63e9f7c826ccd2e9e3fd360d98081f0fc16  foundry/lib/pramana_foundry/cleanup.ex
1dc6c75649bee56f9ffdf593d4318879a0c36937e303cb355c246dabab68a61d  foundry/lib/pramana_foundry/coordinator.ex
75e4fc7c91f63e3e392ed829e03d2858a9a4f99439c7486864ccad1c35bc8e2e  foundry/lib/pramana_foundry/herdr/adapter.ex
5f8f08a72a8f4146860179de61dbc65b00ff741ed1713831b3322bc6f51c97d5  foundry/lib/pramana_foundry/herdr/identity.ex
a0e2cd6645f20c26c673d2005643cfb959fb248b2e92f2551ad5edef406bbeed  foundry/lib/pramana_foundry/transition.ex
561237108b410387aea874465a688ecdddc32cece7b57a4aa42d1689cff9ff39  foundry/test/pramana_foundry/agent_server_test.exs
68dbc28f780658635dbec2e7eb506c43988f82a99fa9e67b795b52753e8fb0b0  foundry/test/pramana_foundry/autonomous_launch_test.exs
da911b7a0295997456ba4a68eb2072300e926f895c11d9057062972c85e81e74  foundry/test/pramana_foundry/coordinator_test.exs
22dd480896487c62549b5bd0170263f3d88fb6ad9e823394ececd4931f26bc4b  foundry/test/pramana_foundry/daemon_recovery_test.exs
c31277bd8590bbf42f2a4aaabe73095f3f0ff930200b8ffc81da7f28f27f8247  foundry/test/pramana_foundry/herdr/adapter_test.exs
3ada1d0b276d613fdaf6fc706c2b2d2b43de0bfbc36c4f662fdf9a04f750da71  foundry/test/pramana_foundry/stress_test.exs
b18a212eaa5e542cda15e3ccf5a47b4cf2febb2c162c7b90ee04418a723c9095  foundry/test/pramana_foundry/transition_test.exs
```
