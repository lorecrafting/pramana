# FR-03 independent review — frozen candidate

Verdict: **FAIL — do not integrate as completed FR-03; FR-07 remains blocked.**

Reviewed on 2026-09-13 UTC (2026-09-12 Pacific/Honolulu), against base
`7aecf31c541ab1b1f3de4045ac3c487f6ef0708f` in
`/tmp/pramana-fr03.YeVMZP/tree`. The reviewer changed no implementation or test
candidate files. This review uses the post-format bytes below, not the obsolete
preflight hashes. Findings concern the immediate F02/F14 containment contract;
they do not demand implementation of FR-07/08/10/15a in this ticket.

## Frozen inputs

Paths are relative to `foundry/`; hashes are SHA-256.

| File | Hash |
|---|---|
| lib/pramana_foundry/application.ex | `8456e819fd0b165c185ab02980c162793d91c6c43b767c0641a0ce694f99f3c4` |
| lib/pramana_foundry/runtime_root.ex | `1bf3fe5bd5de23ce3dbac85ffff887b6f913afd64662ea4008826116267683d2` |
| lib/pramana_foundry/runtime_owner.ex | `2b60d6408427e469411820a669de9d800d3498b3b29d86f150cb266d1fcdd679` |
| lib/pramana_foundry/coordinator.ex | `03e6aad574c3a763118d19cc69e98169cafd6062d34e3f3940727393ef8327e1` |
| lib/pramana_foundry/coordinator/tick.ex | `7e4fe128917126e286d6dbabab091585b9174eba191df69de007480a93f753a1` |
| lib/pramana_foundry/fence.ex | `59ab62c203d29b2f0bf56133743f9bc3f4e4e4ce91113573844a59a880b4efb7` |
| lib/pramana_foundry/improver.ex | `eeb5c8a353bac57409527ef4d90b7c898725d11c5d7a18d578b5530f14df186d` |
| lib/pramana_foundry/consolidated_log.ex | `ff7eebb85bd34f39b0bf345432de3ca1ed4e7f1b6b62cc1bfa4f1b991352137c` |
| lib/pramana_foundry/board.ex | `57b097d4cb7ad4ca1e2a10dbb0ab1862ccbae1b1ae25c7c34dca3757e32ae2c6` |
| lib/pramana_foundry/board/findings_panel.ex | `aaa8190073b2dd81a41ddd9c6bf00bd81849195159a1a48bed57480334da9977` |
| test/pramana_foundry/legacy_persistence_containment_test.exs | `424acdc9634d8b10cb7b20f23fbe004fac89beecf3a6b27c05a12ad5e32e94b5` |
| test/pramana_foundry/runtime_root_test.exs | `676bcae97d52c9a832cb6474680e3ca48a9d355b2c15e67b2d498c2f71b50e3b` |
| test/pramana_foundry/runtime_startup_boundary_test.exs | `4eab0b6e948b8639cd4802189c75ea464c5da54b070f8ada16091273bdf7a783` |

## Blocking findings

### B1 — P0: an incomplete final record can still receive a successful append

`Coordinator.init/1` (coordinator.ex:130) trusts `Checkpoint.events/1`, whose
`Import.read_jsonl/3` splits lines without checking the final newline. A complete
JSON object with its final newline missing is accepted. `EventLog.append/2` then
appends the next JSON object directly against the closing brace of the first.

Independent reproduction used an isolated valid `tick_processed` record, removed
only its terminal newline, loaded through Coordinator, then called public
`Coordinator.enqueue_ticket/1`. Results:

```text
TORN_LOAD: {nil, "running"}
TORN_ENQUEUE: :ok
TORN_AFTER_APPEND: {:error, %{reason: :malformed_json, line: 1, ...}}
```

The successful public mutation has made its own history unreadable on restart.
The existing malformed-JSON test misses this exact append boundary. Refuse an
unterminated existing tail before enabling writes, preserve its bytes, expose the
recovery boundary, and test a valid prefix plus both incomplete JSON and complete
JSON lacking its delimiter. Do not silently repair or discard the tail.

### B2 — P1: the runtime fence is released before its effectful subtree is quiescent

`RuntimeOwner.terminate/2` (runtime_owner.ex:53) releases the bridge lock while the
owner itself exits. `:rest_for_one` can only begin stopping subsequent children
after that exit. Thus the docstring's claim that loss takes all effectful children
down before ownership can be reacquired is false. Killing the bridge has the same
ordering concern: its OS lock disappears before the supervisor completes teardown.

An isolated supervisor used the exact RuntimeOwner and `:rest_for_one` topology,
with a model-free later child that traps shutdown. After stopping RuntimeOwner,
the reviewer acquired a successor Fence while that old child was in shutdown,
then instructed the old child to write a fixture file. Result:

```text
SUCCESSOR_OWNS_WHILE_OLD_CHILD_WRITES: {true, "old child still mutates"}
```

This is a deterministic reproduction of the ownership gap using a representative
effectful child, not a claim that a provider launch was exercised. Coordinator's
checked call helper is useful but does not cover startup appends, individual Tick
appends after its entry check, or already-running asynchronous effect children.
FR-01's real-launch denial does not establish the F14 ownership guarantee.

Define containment that prevents successor admission until old runtime/effect
authority is quiescent, and prove orderly loss plus abrupt bridge/owner failure.
A mere different restart strategy or PID text check does not close this gap.
Full durable claims/epochs remain FR-10/15a; the immediate guarantee must be honest
without them, even if uncertain takeover requires explicit recovery.

### B3 — P1: invalid authoritative replay is still silently converted to healthy empty state

Coordinator routes JSON/schema load failures to recovery, but trusts
`Transition.rebuild/2`. Existing `Transition.apply_record/2` (transition.ex:145)
discards projection errors. A canonical `prompt_intent` for a never-admitted
assignment therefore passes the loader, disappears during replay, and starts
Coordinator normally with no assignments or retained projected events.

Independent result for one such record:

```text
INVALID_REPLAY: {nil, "running", [], true}
```

The last value proves the fixture bytes were unchanged; preserving bytes alone
does not prevent silently forgetting authority. This is an existing defect that
the new startup containment still permits, rather than a newly introduced reducer
bug. Add a strict startup validation/error boundary for unreplayable authority and
exceptions before enabling mutations. This need not repair runtime/replay parity
or create a second reducer; those remain FR-08.

### B4 — P2: public operational inspection hides the new recovery state

The recovery-specific status clause at coordinator.ex:236 calls the same
`Status.status/1` projector, which omits both `status` and `recovery_error`.
`Coordinator.health/0` (coordinator.ex:586) also omits them. With a directory in
place of the event log, the independent public calls returned an empty health
count map and ordinary status fields with no recovery indicator:

```text
RECOVERY_HEALTH: %{active_assignments: 0, queue_depth: 0, running_agents: 0}
```

Raw `Coordinator.state/0` does expose the error, and mutating calls are denied;
those parts work. The normal status/health interfaces still cannot distinguish
unreadable history from no work. Carry the explicit recovery state/reason through
these existing public inspection results and test it. Broader board, telemetry
and canonical-projection redesign remains FR-18, not a prerequisite here.

## Acceptance evidence and remaining gaps

Independent commands ran only in the isolated worktree, with private parent
`/tmp/fr03-review.EojoVXnQ` created by `mktemp -d`. No access to the configured
operator state tree, provider execution, Herdr invocation, generated escript,
live daemon, credentials or activation occurred. No subagents were spawned.
The parent was retained for evidence inspection.

Common environment used explicit installed paths:

```sh
PATH=/Users/raymondluong/.local/share/mise/installs/elixir/1.20.3-otp-29/bin:/Users/raymondluong/.local/share/mise/installs/erlang/29.0.5/bin:/opt/homebrew/bin:/usr/bin:/bin
TMPDIR=/tmp/fr03-review.EojoVXnQ
PRAMANA_RUNTIME_ROOT_FRESH=1
```

Every execution cleared `HERDR_ENV` and `COORDINATOR_TICK`. The two test/probe
application roots were respectively `focused-runtime` and `adversarial-runtime`
beneath that private parent; neither existed before its startup. Both used
`MIX_ENV=test` and `PRAMANA_STARTUP_MODE=client`; Application intentionally chooses
the isolated test stack in test mode. The independent adversarial script explicitly
configured `/nonexistent/fr03-review-herdr`. The supplied focused test boot still
printed the configured Herdr executable, but did not invoke it: empty initial
history, no tick, cleared HERDR_ENV, and fake-backed Tick failure.

| Command/check | Result |
|---|---|
| `mix test test/pramana_foundry/runtime_root_test.exs test/pramana_foundry/runtime_startup_boundary_test.exs test/pramana_foundry/legacy_persistence_containment_test.exs --seed 424204` | Exit 0; 15 passed, 2.8 seconds |
| `mix run --no-start /tmp/fr03-review.EojoVXnQ/adversarial.exs` | Exit 0; reproduced B1–B4 above |
| Direct `MIX_ENV=dev mix run --no-start -e ...` with startup-mode override unset; inspect actual plain arguments, start application, inspect child registrations, stop application | Exit 0; nonempty real Mix arguments, client mode, `{nil, nil, nil}` for Coordinator/Improver/HardeningPM |
| `MIX_ENV=test mix compile --warnings-as-errors` | Exit 0; existing isolated build accepted, not a clean-build claim |
| `git diff --check` | Exit 0 |
| `git diff --stat` and `git diff -w --stat`, plus relevant source/diff reads | Tracked 8-file diff: 1376 additions/738 deletions; whitespace-insensitive: 895/257; untracked additions assessed separately |

Adversarial probe source SHA-256:
`2f54a39f66f88fd9d4b3aeb4b4f1f8f7433133b1ac2514542fef177e71695238`.
The script is retained at the exact path in the command table. Its fixture mutations
occur only beneath the private runtime root. Its lock-overlap child is a BEAM Task;
the production Fence's existing OS bridge supplies flock.

The supplied startup suite proves contention between two real independently
started BEAM applications, lock-text irrelevance while held, stale-text reuse once
released, and explicit client startup without effectful children. Its owner exit
is **graceful Application.stop**, not the required killed-owner acceptance case.
Add a real owned-OS-process kill case and bridge-loss case with deterministic
handshakes; verify old effects cannot continue during takeover. Do not promote the
current graceful test to hard-kill evidence.

The supplied malformed, schema-version-2, oversized and directory-I/O fixtures
preserve the tested bytes/path, disable tick and expose raw recovery state. They
are one-record/no-prefix tests and call `Coordinator.init/1` directly; no real
application-recovery test with retained useful history was supplied. Public enqueue
append failure returns recovery_required and retains assignments unchanged. The
fake Tick failure makes zero backend calls. These are useful positive results but
do not cover every append site or later-write failure.

## Authoritative append and ordering audit

Coordinator's mutation branches now route checkpoint calls through
`persist_call`/`persist_info`; startup recovery uses `startup_append_or_halt`.
Tick routes its admission and retry/park writes through `persist_or_halt`.
The remaining raw checkpoint invocations are the two Coordinator helpers and
one Tick helper. The source-count test verifies only that syntax shape; it does
not establish callback ordering or prevent another append API from bypassing it.

Reviewed event families: ticket enqueue; accepted/rejected handoff; accepted/
rejected review and reviewer retry; integration intent and result; PM batch;
tick summary; pane creation; launch retry/park; completion/crash; recovered handoff;
startup re-enqueue; Tick admission and prelaunch/DynamicSupervisor retry. Normal
call continuations now follow a checked append, and failure switches to recovery.
`Effects.Launch` and `Effects.PromptDelivery` already check their checkpoint writes
with `with`; they are outside the changed candidate. Coordinator's raw
`EventLog.append` is telemetry, and Improver/ConsolidatedLog use diagnostic logs,
not an alternative workflow-authority journal.

Still requiring FR-03 fault evidence: failure on each public handoff/review/PM
branch must not acknowledge new state or notify/launch a fake child; failure on
later tick writes or integration result must retain a truthful partial/unknown
outcome. Tick can start children after earlier records and before a later record
fails; its catch restores old state/registry and does not reconcile those children.
Likewise startup can append several recovery records before a later append fails.
The existing tests exercise only the first failing write. Where safe truthful
containment is unavailable, suspend the path as the ticket explicitly requires;
do not call multi-record legacy work atomic. These are acceptance gaps, not claims
that the reviewer injected ENOSPC/fsync failure or exercised actual Git integration.

Memory-only pause/resume/stop/reset/admission/reset-PM mutations predate this change
and remain visible in Coordinator. Full acknowledged-command/replay consistency,
transactional bundles, durable command deduplication and storage-capacity management
are still FR-07/08; this review does not mistake checked appends for their completion.
Unsafe orphan cleanup is FR-04; actual integration/activation containment is FR-05;
owned effect reconciliation is FR-10. No deferred obligation permits B1 or B2.

## Scope, language and documentation

Formatting churn alone is **not an integration blocker**. Exact hashes preserve
review identity, and whitespace-insensitive/source inspection separates substantial
Coordinator changes from mechanical Improver/board formatting and runtime-root
routing. Keep subsequent corrections narrowly scoped and re-freeze/re-review.

Operator instruction requires Elixir tests wherever practical. The new Python
`start_bogus_lock_holder/1` in runtime_startup_boundary_test.exs:66 is avoidable:
launch an Elixir/BEAM Port fixture, acquire the existing Fence, replace only its
held-lock metadata with bogus text, announce readiness, retain the fence until
explicit shutdown, and assert a second BEAM is refused. The production OS flock
bridge is an existing external boundary; reproducing its Python implementation in
the test is unnecessary. Replace the new Python test helper before acceptance.
The hard-coded absolute Mix path is also a portability limitation; explicit pinned
toolchain provenance is good, but a checked executable input would travel better.

Shared completion docs have not yet been updated in this frozen candidate. After
correction, document startup modes, fresh/test root behavior, recovery-required
operation, stale-owner recovery and any suspended legacy capability with its
restoration ticket. Update REPAIR-PLAN and root PLAN alongside integration and
record renewed exact hashes and evidence. Do not cite the reported full-suite
338-pass implementation run as independently repeated here; this reviewer reran
the focused suite and adversarial checks only.

Context inspected: AGENTS.md and its orientation/Foundry routing; root STATUS/PLAN/
ROADMAP context and applicable RULES 8/17/41/60/62/63/79/81; CODE_CONVENTIONS;
Foundry README; REPAIR-PLAN execution/shared completion, FR-03 and F02/F14 routing;
WORKFLOW-CONTRACT including R1–R5 and supersession; audit F02/F14 and adjacent
recovery/ownership findings; the candidate implementation log and the main worktree
log's FR-03 incident/preflight entries (the latter had newer documentation).

Final disposition: **FAIL**. B1 and B2 alone prevent the claimed immediate
durability/fencing containment; B3 and B4 leave recovery failure handling incomplete.
