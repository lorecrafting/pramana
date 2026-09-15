# Elixir workflow migration tickets

> **Naming note:** This document was written when the project was `pramana_workflow`
> under `workflow/`. The actual project is now `pramana_foundry` under `foundry/`.
> All references to `pramana_workflow` and `PramanaWorkflow` below refer to the same
> codebase reorganized.

**Historical status recorded 2026-09-08: migration declared complete.** All 8 tickets in
the ordered chain were reported implemented. WF-ELIXIR-CUTOVER-02 and
WF-ELIXIR-RETIRE-01 were reported executed live: the Python supervisor was drained, its
state imported (27 records, SHA-256 verified), soak run (20 iterations, zero crashes), and
the Python runtime retired (wrappers removed, state archived, smoke check installed). The
Elixir OTP release (`pramana_workflow`) was reported as the sole local dispatcher, with an
active self-healing Improver loop.

The 2026-09-12 audit found that these migration-ticket claims did not establish the repaired
end-to-end lifecycle. `REPAIR-PLAN.md`, not this historical ticket list, is authoritative for
current completion. FR-21 retired the absent Python parity executable on 2026-09-13.

All implementation after this bounded architecture ticket returns to the configured
subscription-backed Sol/medium developer and separate Sol/medium reviewer profiles. Do not
launch another premium or milestone-planning pass unless separately authorized. Existing
fallback remains narrow: only positively classified Claude subscription quota exhaustion may
use that ticket's predeclared Codex fallback after exact-owner/delivery reconciliation and a
fresh run ID; capacity, rate limit, authentication, permission, ambiguity, and ordinary
failure are not fallback authority.

## Ordered chain

1. **WF-ELIXIR-PLAN-01** — publish architecture, priority, routing, parity matrix, and bounded
   next contracts. No runtime or relocation.
2. **WF-ELIXIR-FOUNDATION-01** — standalone Mix project, release/CLI shell, schema/import
   validation, pure transitions, durable state/fencing prototype, dependency boundary,
   task-specific preparation contract, and parity harness.
3. **WF-ELIXIR-EFFECTS-01** — Herdr adapter and OS-child/check lifecycle with identity,
   recovery, and cancellation conformance.
4. **WF-ELIXIR-ENGINE-01** — scheduler, PM lifecycle, quota, correction, review, and serial
   integration pipeline, plus runtime/source revision visibility.
5. **WF-ELIXIR-BOARD-01** — Elixir terminal board and sanitized inspection. It may overlap
   effects/engine only after interfaces and disjoint scopes/resources are concrete; integration
   remains serial.
6. **WF-WORKSPACE-MOVE-01** — dry-run manifest, journaled relocation, immutable digest
   preservation, versioned old-path mapping, temporary original-checkout local exclude, and
   reverse recovery.
7. **WF-ELIXIR-CUTOVER-01** — drain/fence Python, import latest state, activate the pinned OTP
   release, prove a bounded real reviewed task, and exercise compatible rollback.
8. **WF-ELIXIR-RETIRE-01** — bounded unattended soak/restart evidence, remove obsolete Python
   workflow runtime and wrappers, retain rollback refs/diagnostics, then resume product work.

The chain is strict except the conditional BOARD overlap stated above. Product tickets remain
deferred through cutover. The already assigned fixture cleanup may drain under its immutable
contract; a stale duplicate may be parked only through validated PM data.

## Foundation contract: WF-ELIXIR-FOUNDATION-01

**Outcome.** The standalone `workflow/` Mix project and local OTP release/CLI shell define
strict versioned schemas/import validation, pure transition interfaces, atomic durable state,
cross-language singleton fencing, and a parity harness. Shadow mode cannot invoke Herdr or
write live state.

**Dependencies.** `WF-ELIXIR-PLAN-01` accepted. Admission uses that accepted revision as its
fresh base; the supervisor generates a new run ID and isolated checkout/artifact paths.

**Implementation scope.** `workflow/.formatter.exs`, `workflow/mix.exs`, `workflow/mix.lock`,
`workflow/config/**`, `workflow/lib/**`, `workflow/test/**`, `workflow/roles/**`,
`workflow/docs/**`, `workflow/README.md`, narrowly required `.gitignore` and roadmap updates,
and read-only use of `automation/pramana_supervisor.py` plus fixtures as the baseline. No
Python runtime replacement, live-state mutation, Herdr mutation, workspace move, or
corpus/Phoenix change.

**Risk.** P0 workflow recovery: a false singleton, lossy import, or effectful shadow mode can
create two dispatchers or corrupt durable evidence.

**Acceptance tests.** The standalone project builds without the umbrella or database, and a
dependency boundary rejects distributed clustering, Phoenix/Ecto/Postgrex/Oban, general
orchestration frameworks, and paid services. Strict schemas accept the actual Python
snapshot, control, assignment, and event envelopes, require the envelope and nested ticket
task IDs to agree, and preserve event-specific evidence while unknown authority and versions
fail closed. Projection rebuild rejects authority events without complete task/run/role
identity and prompt identities that were not admitted by prior durable records. Atomic
crash-at-checkpoint cases recover deterministically. A macOS contest between the actual
Python `InstanceLock` and Elixir client produces exactly one owner in both acquisition
orders; integration ownership is singleton. Shadow mode proves no Herdr call and no
live-state write. Workflow-only preparation performs no umbrella or database setup, while a
database-declaring control retains its prerequisites. Executable parity regenerates sanitized
records through the production Python serializers and detects baseline drift.

**Developer required checks.** The recovery assignment uses these executable argv arrays:

```text
["sh", "-c", "cd workflow && exec mise exec -- mix format --check-formatted"]
["sh", "-c", "cd workflow && exec mise exec -- mix compile --warnings-as-errors"]
["sh", "-c", "cd workflow && exec mise exec -- mix test"]
["python3", "-m", "unittest", "automation.tests.test_supervisor_fixture"]
```

**Integration-only check.** Exactly one
`["mise", "exec", "--", "mix", "precommit"]` after exact-commit approval.

## Effects contract: WF-ELIXIR-EFFECTS-01

**Outcome.** Implemented typed Herdr argv/JSON adaptation and the OS child/check lifecycle:
durable launch/completion/cancel evidence, process-group ownership, deadline handling,
adoption after coordinator crash, and ambiguous-delivery reconciliation. Not wired to a live
coordinator, scheduler, or Herdr binary; every acceptance test below is a fixture proof.

**Dependencies.** Accepted `WF-ELIXIR-FOUNDATION-01` (already satisfied at admission).

**Implemented scope.** `workflow/lib/pramana_workflow/herdr/**` (`Argv`, `Runner`, `Identity`,
`Adapter`), `workflow/lib/pramana_workflow/effects/**` (`Checkpoint`, `Launch`,
`PromptDelivery`, `ProcessGroup`, `SilenceWatchdog`), `workflow/lib/pramana_workflow/checks/**`
(`Runner`, `Status`, `Adoption`), matching `workflow/test/pramana_workflow/{herdr,effects,
checks}/**` fixtures. No scheduler/PM policy, board, relocation, or live provider run; no
Python file was changed.

**Concrete interfaces.**

- `PramanaWorkflow.Herdr.Adapter` re-inspects the live agent and refuses to prompt, interrupt,
  or close unless name, pane, terminal, and session (`PramanaWorkflow.Herdr.Identity`) all still
  match what the caller expects; `Argv` builds every verb as a plain argv list, never a shell
  string.
- `PramanaWorkflow.Effects.Checkpoint` appends a durably fsynced event (reusing
  `PramanaWorkflow.EventLog`) before any effect and after it completes.
  `PramanaWorkflow.Effects.Launch` and `.PromptDelivery` use it so a crash between the two
  checkpoints is reconciled (inspect-and-adopt, or transcript-confirmed delivery) rather than
  ever repeating `agent start` or `agent prompt`; genuinely ambiguous evidence returns an error
  instead of guessing.
- `PramanaWorkflow.Effects.ProcessGroup` captures pid/process-group/start-time/command via `ps`
  (mirroring the Python supervisor's `process_identity`) and refuses to signal unless a fresh
  lookup still matches exactly, covering stale-PID and replacement-owner cases.
- `PramanaWorkflow.Checks.Runner` spawns a check as an independent OS process (a small
  stdlib-only Python trampoline, the same boundary `PramanaWorkflow.Fence` already uses for the
  singleton lock) so a BEAM crash orphans rather than kills it; the trampoline starts the check
  in its own session, durably publishes the child pid, watches a cancellation file, and records
  the exit code even if nothing is watching it. `PramanaWorkflow.Checks.Status` and `.Adoption`
  read that evidence back and classify `:running`, `{:completed, code, promotable?}`, `:timeout`
  (which beats a late zero exit), `:cancelled`, or `:uncertain` (never silently rerun).
- `PramanaWorkflow.Effects.SilenceWatchdog` is a provider-response-silence deadline separate
  from task/check timeouts; it only accepts durable-provider-event evidence carrying live
  agent/pane/terminal/session/role/task/run/pid identity (a spinner string or bare wall-clock
  gap is structurally refused), and a check with its own deadline is exempt. It classifies
  capacity/rate-limit/subscription-quota/cooldown/unrelated-provider signals from evidence the
  caller already collected and never itself decides to retry: interrupting a verified,
  safely-interruptible hung owner is this ticket's effect (`ProcessGroup.signal/2` /
  `Checks.Runner.terminate/3`), and applying the bounded retry policy after that interrupt is
  `WF-ELIXIR-ENGINE-01`'s scheduler, not implemented or preassigned here.

**Known simplifications, left for the next ticket to close or accept as-is.** The Herdr pane-
busy start retry loop, the `answer_prompt`/`press_enter` verb, and quota/cooldown/capacity
provider-response classification beyond `SilenceWatchdog.classify/1`'s pass-through are not
ported from `automation/pramana_supervisor.py`. Nothing here has run against a live `herdr`
binary; `HERDR_ENV=1` gating is enforced but untested against the real CLI.

**Risk.** P0 workflow recovery: BEAM monitor semantics do not own OS descendants; stale PID or
ambiguous prompt handling can kill a replacement or duplicate paid/provider work.

**Acceptance tests.** Installed-help-shaped JSON fixtures preserve pane/terminal/session/run
identity; argv never passes through a shell; crash injection on both sides of launch and
prompt checkpoints produces at most one effect; a surviving silent check is adopted exactly
once; uncertain execution fails without rerun; verified process groups terminate within bounds
(real `sh`/`sleep` fixtures in `checks/runner_test.exs`); stale PID/start-time/command and
replacement-owner cases refuse cleanup; deadline expiry beats a late zero exit.

**Developer required checks.**

```text
["sh", "-c", "cd workflow && exec mise exec -- mix format --check-formatted"]
["sh", "-c", "cd workflow && exec mise exec -- mix compile --warnings-as-errors"]
["sh", "-c", "cd workflow && exec mise exec -- mix test"]
```

**Integration-only check.** Exactly one
`["mise", "exec", "--", "mix", "precommit"]` after exact-commit approval.

### Telemetry extension points reserved for `WF-ELIXIR-EFFECTS-TELEMETRY-01`

Telemetry emission is out of scope for this ticket; no parallel telemetry record convention is
implemented here. The successor should attach `:telemetry.execute/3` calls (or the accepted
`WF-ELIXIR-OBSERVABILITY-05` interface directly) at these exact call sites, without reworking
the effect code around them:

| Phase | Call site | Suggested attribution fields |
|---|---|---|
| launch start | `PramanaWorkflow.Effects.Launch.start/6`, immediately after the `launch_intent` checkpoint succeeds | `task_id`, `run_id`, `role`, `source: "effects.launch"`, `quality: "durable"` |
| launch finish | `PramanaWorkflow.Effects.Launch.persist_completed/5`, after the `launch_completed` checkpoint | as above, plus `pane_id`, `terminal_id`, outcome (`:ok` / error reason) |
| prompt-delivery start | `PramanaWorkflow.Effects.PromptDelivery.send_prompt/8`, immediately after the `prompt_intent` checkpoint succeeds | `task_id`, `run_id`, `role`, `source: "effects.prompt_delivery"`, `quality: "durable"` |
| prompt-delivery finish | `PramanaWorkflow.Effects.PromptDelivery.persist_delivered/6` | as above, plus `evidence` (`"delivered_now"` or `"confirmed_via_transcript"`) |
| check start | `PramanaWorkflow.Checks.Runner.launch/1`, once `await_child_pid/2` resolves | `task_id`, `run_id`, `role`, `source: "checks.runner"`, `quality: "durable"`, process identity (pid/pgid/started_at/command) |
| check finish | the caller reading `PramanaWorkflow.Checks.Runner.read_completion/1` after `PramanaWorkflow.Checks.Status.classify/1` resolves a terminal outcome | as above, plus the resolved outcome (`:completed`/`:timeout`/`:cancelled`/`:uncertain`) and `promotable?` |
| cancellation | `PramanaWorkflow.Checks.Runner.terminate/3`, both the cooperative file write and the `ProcessGroup.signal/2` call | `task_id`, `run_id`, `role`, `source: "checks.runner.terminate"`, `reason`, signal outcome (`:ok` / `:stale_identity` / other) |

Every row's `source`/`quality` pair is a proposed default, not a schema this ticket fixes;
`WF-ELIXIR-EFFECTS-TELEMETRY-01` owns the actual event names and any additional attribution
`WF-ELIXIR-OBSERVABILITY-05` requires.

## Engine contract: WF-ELIXIR-ENGINE-01

**Outcome.** Implemented deterministic scheduling, durable PM planning, quota/cooldown, fallback,
corrections, exact-commit review, and serial candidate integration. Exposes accepted/source
revision separately from the implementation revision loaded by the running runtime. The live Python
supervisor remains authoritative until WF-ELIXIR-CUTOVER-01.

**Dependencies.** Accepted `WF-ELIXIR-EFFECTS-01`.

**Implemented scope.** `workflow/lib/pramana_workflow/{coordinator,scheduler,assignments,pm,reviews,integration,quota,status}/**`,
matching `workflow/test/**`. No TUI, physical workspace move, cutover, Python retirement, corpus
mutation, or provider credentials. The live Python supervisor remains authoritative until cutover.

**Concrete interfaces.**

- `PramanaWorkflow.Scheduler` and `.Policy`: deterministic prioritization and ranking, provably
  disjoint scope checking (`scopes_may_overlap?/2`), explicit parallel conflict detection
  (`parallel_conflict/2` checking base revisions, checkouts, run IDs, dependencies, environment,
  and shared resources), and worker-ceiling capacity gating with prompt pause/stop suppression.
- `PramanaWorkflow.PM`: transactional batch application (`apply_proposals/2`) enforcing all-or-none
  atomicity across `create`, `split`, `amend`, `reprioritize`, and `park` operations with dependency
  graph cycle detection; `AttemptCap` enforces dual-cap semantics (consecutive rejections sharing
  normalized hexadecimal reasons, and total attempt ceiling per revision), launch-revision attribution,
  suspension neutrality, and human-only `reset_pm_attempts` escape hatch.
- `PramanaWorkflow.Quota`: durable provider/profile cooldown tracking under virtual time, and symmetric
  Codex ↔ Claude subscription cross-provider fallback (`begin_fallback/5`, `can_fallback?/3`,
  `release_fallback_intent/2`), generating fresh run IDs per continuation while suppressing concurrent
  in-flight intents on affected providers.
- `PramanaWorkflow.Reviews`: engine derivation of reviewer profiles from `model_policy.review_matrix`
  (`derive_reviewer_profile/2` based on risk/priority/work_class) without ticket/handoff author choices;
  exact review artifact schema validation (`validate_artifact/4`) enforcing matching check argv,
  clean checkout status, and zero exit codes on approvals.
- `PramanaWorkflow.Assignments`: completed and blocked handoff validation (`validate_handoff/4`)
  including path scope/exclusion checks and pre-handoff clean checkout verification (zero uncommitted
  changes, commit sole difference from base); correction lifecycle gating (`handle_review/2`) permitting
  up to two corrections with evidence retention before parking.
- `PramanaWorkflow.Integration`: serial singleton candidate owner (`acquire_owner/3`, `release_owner/2`),
  readiness gating (`validate_readiness/3` refusing pause, stop, or stale bases), combined gate checks
  (`run_gate_checks/3`), failure preservation of accepted revisions (`fail_integration/3`), and atomic
  promotion (`promote_candidate/3`) blocking promotion from post-stop evidence without re-execution.
- `PramanaWorkflow.Status`: exposes `accepted_revision` and `runtime_implementation_revision` separately,
  visibly reporting revision disagreement until controlled restart reconciliation
  (`reconcile_runtime_implementation_revision/1`).
- `PramanaWorkflow.Coordinator`: GenServer boundary orchestrating lifecycle calls, controls, queries,
  and deterministic crash recovery without duplicate prompt or dispatch.

**Accepted tests.** Comprehensive unit and integration coverage in `test/pramana_workflow/{engine_test.exs,
recovery_test.exs,coordinator_test.exs,scheduler/**,pm/**,quota/**,reviews/**,assignments/**,integration/**,status/**}`:
two isolated disjoint workers running concurrently while integration remains singleton, transactional PM
proposal batch rollbacks, attempt caps and human-only reset, virtual time quota cooldown and fallback,
pause/stop dispatch/promotion blocking, dirty checkout refusal, review rejection, and revision visibility
disagreement across restart.

**Developer required checks.**

```text
["sh", "-c", "cd workflow && exec mise exec -- mix format --check-formatted"]
["sh", "-c", "cd workflow && exec mise exec -- mix compile --warnings-as-errors"]
["sh", "-c", "cd workflow && exec mise exec -- mix test"]
```

**Integration-only check.** Exactly one
`["mise", "exec", "--", "mix", "precommit"]` after exact-commit approval.

## Board contract: WF-ELIXIR-BOARD-01

**Outcome.** Implemented the Elixir terminal board and sanitized BEAM inspection: a resilient TUI
reading the coordinator's authoritative projection with automatic refresh, readable cards, keyboard
navigation, detail views, resize handling, source/runtime revision visibility, and BEAM inspection/attach
instructions, proving that board failure or exit cannot crash or disrupt coordinator dispatch. The live
Python board (`automation/pramana_board.py`) remains available until cutover.

**Dependencies.** Accepted `WF-ELIXIR-ENGINE-04` (and `WF-ELIXIR-ENGINE-01` contract).

**Implemented scope.** `workflow/lib/pramana_workflow/board/**`, `workflow/lib/pramana_workflow/board.ex`,
`workflow/test/pramana_workflow/board/**`, and `workflow/test/pramana_workflow/board_test.exs`. No physical
workspace move, cutover, Python board/supervisor retirement, corpus mutation, or provider credentials.
The live Python board and supervisor remain authoritative until cutover.

**Concrete interfaces.**

- `PramanaWorkflow.Board`: GenServer managing the terminal board lifecycle with bounded periodic refresh
  (`refresh_interval_ms`, default 1000ms), keyboard input dispatch (`handle_key/2`), dimension updates
  (`resize/3`), manual refresh (`refresh/1`), frame rendering (`render_frame/1`, `render_lines/1`),
  data loading (`load_data/2`), and unlinked startup (`start/1`) proving fault isolation. Deterministic
  helpers provide canonical column mapping (`status_column/1`), card title derivation (`card_title/1`),
  and one-line outcome extraction (`card_summary/2`).
- `PramanaWorkflow.Board.View`: pure functional terminal frame rendering supporting wide, standard, and
  focused layouts, drawing 8 canonical status columns (`Backlog/Planned`, `Queued`, `Working`, `Review`,
  `Integration`, `Accepted`, `Parked`, `Cooldown`), active column tabs, card listings with selection
  indicators (`▶`), and full-screen ticket detail views.
- `PramanaWorkflow.Board.ViewState`: immutable view state and functional navigation handling column
  switching (arrow/vim keys `h`/`l`), card selection (`j`/`k`), detail view expansion (`Enter`) and
  dismissal (`Esc`/`q`), detail scrolling, and terminal dimension clamping.
- `PramanaWorkflow.Board.Inspection`: sanitized local BEAM inspection exposing node info, OTP release,
  Elixir version, process counts, memory breakdown, and coordinator status (`status/1`, `formatted_status/1`),
  along with documented local-only attach instructions (`attach_instructions/1`) without opening public
  distribution ports or exposing credentials.

**Accepted tests.** Comprehensive coverage in `test/pramana_workflow/board_test.exs` and
`test/pramana_workflow/board/inspection_test.exs`: all 8 canonical columns rendered, deterministic card
titles and summaries, column and card navigation with boundary clamping, detail view expansion with all
ticket metadata and dismissal, smooth resize handling across dimensions, visible revision mismatch
highlighting until reconciled, automatic refresh on state changes without keystrokes, and complete fault
isolation under board process termination (`:kill` and unhandled messages).

**Developer required checks.**

```text
["sh", "-c", "cd workflow && exec mise exec -- mix format --check-formatted"]
["sh", "-c", "cd workflow && exec mise exec -- mix compile --warnings-as-errors"]
["sh", "-c", "cd workflow && exec mise exec -- mix test"]
```

**Integration-only check.** Exactly one
`["mise", "exec", "--", "mix", "precommit"]` after exact-commit approval.

## Workspace relocation contract: WF-WORKSPACE-MOVE-01

**Scope.** Journaled workspace relocation, dry-run manifest, immutable digest preservation, versioned
old-path mapping, safe worktree relocation adaptation, and temporary original-checkout local exclude verification.

**Accepted modules and interfaces.**
- `PramanaWorkflow.Relocation`: top-level coordinator managing dry-run inventory (`inventory/1`), planning
  (`plan/1`), execution (`execute/2`), deterministic crash resumption (`resume/2`), and clean rollback (`rollback/2`).
- `PramanaWorkflow.Relocation.Manifest`: dry-run inventory analyzing `pramana-*` directories and legacy
  external state/worktrees for Git common-dir, branch/ref/HEAD, dirty tracked bytes, untracked/ignored content,
  live process handles, symlinks (including broken targets), destination collisions, disk use, and destination headroom.
- `PramanaWorkflow.Relocation.Journal`: append-only transaction log with per-entry fsync (`init/3`, `record/9`,
  `append_entry/2`, `read_entries/1`, `reconstruct_state/1`) enabling crash resumption and rollback.
- `PramanaWorkflow.Relocation.Digest`: immutable SHA-256 snapshot and verification (`snapshot/2`, `verify/3`,
  `hash_bytes/1`, `hash_file/1`) ensuring historical prompts and artifacts remain byte-identical.
- `PramanaWorkflow.Relocation.PathMap`: versioned old-path mapping (`new/3`, `add_mapping/4`, `resolve/2`,
  `reverse_resolve/2`, `chain/3`, `save/2`, `load/1`) resolving old paths without mutating historical evidence.
- `PramanaWorkflow.Relocation.Worktree`: safe worktree relocation via `git worktree move` (`worktree?/1`,
  `original_checkout?/2`, `root_chat_directory?/2`, `validate_move/3`, `move/3`, `rollback_move/3`), guaranteeing
  that original checkout tracked/untracked edits and root chat working directories are never moved or rewritten.
- `PramanaWorkflow.Relocation.LocalExclude`: temporary original-checkout runtime root protection (`exclude_file_path/1`,
  `protect/2`, `protected?/2`, `verify_protection/2`, `unprotect/2`, `tracked_ignore_present?/2`), proving in disposable
  fixtures that a narrow `.git/info/exclude` entry hides `workflow/local/` without staging `.git/info/exclude` or user files.

**Accepted tests.** Comprehensive coverage in `test/pramana_workflow/relocation_test.exs` and `test/pramana_workflow/relocation/*`:
- Complete dry-run inventory manifest analysis including Git metadata, dirty tracked bytes, untracked/ignored content,
  live handles, symlinks, destination collisions, and filesystem headroom.
- Worktree vs original checkout identification and invariant enforcement (refusing to move original checkout or root chat dir).
- Disposable checkout fixture proving narrow `.git/info/exclude` runtime protection, probe verification, and clean removal.
- SHA-256 byte-for-byte invariance and versioned `PathMap` resolution.
- Crash injection at every journaled boundary (`:after_prepare`, `:before_move`, `:after_move`, `:after_digest_verify`,
  `:after_complete`, `:after_path_map`), proving deterministic resumption, SHA-256 byte invariance, and clean rollback
  without leaving orphaned state.

**Developer required checks.**

```text
["sh", "-c", "cd workflow && exec mise exec -- mix format --check-formatted"]
["sh", "-c", "cd workflow && exec mise exec -- mix compile --warnings-as-errors"]
["sh", "-c", "cd workflow && exec mise exec -- mix test"]
```

**Integration-only check.** Exactly one
`["mise", "exec", "--", "mix", "precommit"]` after exact-commit approval.

## Cutover contract: WF-ELIXIR-CUTOVER-02

**Outcome.** Implemented drain/fence protocol for the Python supervisor (`begin_drain`, `end_drain`,
`drain_progress`, `DrainedDispatchError`) with CLI `drain`/`undrain` verbs and durable checkpointing
under the existing `audit.drain` field; durable state import (`PramanaWorkflow.Cutover.Import`) that
reads the latest Python supervisor `state.json`, validates it against the accepted schema, and replays
every accepted/working/parked/blocked assignment record into a digest-verified crash-recoverable archive;
pinned OTP release activation (`PramanaWorkflow.Cutover.Release`) with health probe via the release's
own `rpc` command; and fixture-proven rollback (`PramanaWorkflow.Cutover.Rollback`) that stops the
release, removes the Python fence, and verifies archive integrity. The live Python runtime remains
authoritative until the operator exercises release activation and verified rollback toward
WF-ELIXIR-RETIRE-01.

**Dependencies.** Accepted `WF-WORKSPACE-MOVE-01` (already satisfied at base `9dd14e6`).

**Implemented scope.**
- `automation/pramana_supervisor.py`: `DrainedDispatchError`, `Supervisor.drain_state/0`,
  `begin_drain/1`, `end_drain/0`, `has_owned_worker/2`, `pm_owned/0`, `in_flight_evidence/0`,
  `drain_progress/0`, drain/undrain CLI parsers and control dispatch, drain check in `dispatch_halt_reason`,
  `drain_progress()` in `tick()`, `DrainedDispatchError` guard in `dispatch()`, and `control_drain`/
  `control_undrain`/`supervisor_drained` scheduling transition events.
- `workflow/lib/pramana_workflow/cutover.ex`: thin `defdelegate` facade over the four submodules.
- `workflow/lib/pramana_workflow/cutover/supervisor_control.ex`: typed Python CLI wrapper for
  status/drain/undrain/start_daemon and bounded polling loops (`await_drained`, `await_undrained`).
- `workflow/lib/pramana_workflow/cutover/import.ex`: schema-validated, digest-verified,
  crash-recoverable durable state import (`extract/1`, `import/2`, `read_manifest/1`, `verify_manifest/1`).
- `workflow/lib/pramana_workflow/cutover/release.ex`: OTP release activation (`start`, `stop`,
  `health_probe`, `health_check`, `activate`) via the release binary's daemon/rpc verbs.
- `workflow/lib/pramana_workflow/cutover/rollback.ex`: combined rollback of release stop, Python
  undrain, dispatch restoration, and archive integrity verification.

**Concrete interfaces.** See `workflow/lib/pramana_workflow/cutover/*.ex` and the submodule
`@moduledoc` entries above. Every acceptance criterion is fixture-proven.

**Accepted tests.**
- `test/pramana_workflow/cutover/supervisor_control_test.exs`: drain acceptance (idle), undrain + fresh
  drain cycle, already-drained startup refusing dispatch, bounded drain waiting for in-flight workers.
- `test/pramana_workflow/cutover/import_test.exs`: malformed state rejection, unknown field rejection,
  status filtering (accepted/working/parked/blocked only), manifest write + digest verification, tampered
  archive detection, crash-recoverable retry.
- `test/pramana_workflow/cutover/release_test.exs`: health_probe response, start/stop, health_check
  JSON parsing, activate polling until healthy, start timeout, non-zero exit reflection.
- `test/pramana_workflow/cutover_test.exs`: end-to-end cutover reading a disposable fixture Python
  checkout, importing records, dispatching a lightweight reviewed task through the real Coordinator,
  rolling back cleanly, and re-verifying archive integrity.

**Developer required checks.**

```text
["sh", "-c", "cd workflow && exec mise exec -- mix format --check-formatted"]
["sh", "-c", "cd workflow && exec mise exec -- mix compile --warnings-as-errors"]
["sh", "-c", "cd workflow && exec mise exec -- mix test"]
```

**Integration-only check.** Exactly one
`["mise", "exec", "--", "mix", "precommit"]` after exact-commit approval.

## Retirement boundary

`WF-ELIXIR-RETIRE-01` remains a roadmap summary. Its scope, artifacts, checks, and run identity
will be elaborated from the then current accepted revision after cutover soak evidence.
