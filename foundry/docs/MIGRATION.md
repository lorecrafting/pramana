# Elixir Foundry (workflow)

> **Naming note:** This document was written when the project was `pramana_workflow`
> under `workflow/`. The actual project is now `pramana_foundry` under `foundry/`,
> with module prefix `PramanaFoundry`. All references to `pramana_workflow`,
> `PramanaWorkflow`, and `workflow/` below refer to the same codebase at its
> current location.

**Status: migration complete.** The Elixir OTP release (`pramana_foundry`) is the sole
local dispatcher. The Python supervisor and board have been retired — state archived,
wrappers removed, smoke check installed at `bin/pramana-retire-smoke`.

The standalone Mix project supplies the local OTP release/CLI shell, strict schema
validation, durable-state and fencing, typed Herdr adapter, checkpointed OS-child/check
lifecycle with process-group ownership and crash-recovery adoption, deterministic
scheduling, PM planning lifecycle with attempt caps, quota cooldown and subscription
fallback, exact-commit review, serial candidate integration, terminal board, sanitized
local BEAM inspection, journaled workspace relocation, cutover facade, soak/restart
harness, and a self-healing Improver loop that reads telemetry and creates hardening
tickets.

`docs/PLAN.md` owns priority. [`MIGRATION-TICKETS.md`](MIGRATION-TICKETS.md) owns the ordered
migration inventory and bounded next-ticket contracts.

## Boundary and destination

The tracked `workflow/` tree is a standalone Mix project with pinned dependencies,
`lib/pramana_workflow/`, `test/`, `roles/`, `config/`, `docs/`, and this README surface. It
must not depend on the Phoenix umbrella, Postgres, corpus data, `priv/embed/`, or a running web
server. The existing Python embedding sidecar is not workflow infrastructure and is excluded.
The workflow release must not form a distributed Erlang cluster and must not introduce
Postgres, Oban, a general orchestration framework, or a paid service. Local OTP supervision
and the durable file protocol are the complete coordination boundary.


The ignored runtime root is fixed at:

```text
/Users/raymondluong/dev/pramana/foundry/local/
  state/current/
  state/runs/
  checkouts/integration/
  checkouts/tasks/
  checkouts/candidates/
  cache/
  logs/
  releases/
  archive/
```

Do not derive the runtime root from an arbitrary task checkout. Git tracks source, tests,
templates, schemas, design, and sanitized milestone records. Runtime state, transcripts,
configuration, caches, temporary files, nested worktrees, and provider credentials remain
untracked. Git commits and refs preserve source; an immutable checksum manifest preserves
local evidence. Provider authentication remains in each provider's existing external store.

## Runtime architecture

The target is a separate local OTP release, manually started in a dedicated Herdr pane. It is
not a Phoenix child and has no boot service. One durable coordinator is the only state writer;
one integration owner serializes accepted-candidate promotion. Pure transition, scheduling,
schema, and policy functions return validated intents. Effects execute only after intent is
checkpointed.

Use a `Registry` keyed by unique binary run ID, bounded `DynamicSupervisor` and
`Task.Supervisor` children, and explicit assignment state machines where they make transitions
reviewable. Registry membership is process discovery, not durable truth and not a machine-wide
singleton. Cross-language fencing prevents the Python and Elixir coordinators from both owning
the same runtime on macOS. The foundation's Elixir client holds the live Python supervisor's
exact `supervisor.lock` protocol through a local `python3` stdlib `fcntl.flock` bridge, because
OTP exposes no compatible lock primitive. Fixtures contest the real Python `InstanceLock`
against that client in both acquisition orders. The bridge owns no business policy.

Python v1 JSON snapshots and assignments carry `schema_version`; the live control inbox and
append-only event JSONL envelopes do not. The foundation validates those production wire
shapes, normalizes them to canonical version-1 records, and preserves event-specific fields
as evidence. Assignment import requires the envelope task ID to equal the nested admitted
ticket ID. Rebuilding a projection rejects known authority events without task, run, and role,
and rejects any prompt intent whose identity was not admitted by accumulated durable records.
Sanitized fixtures are compared during tests with records emitted by the actual Python
`StateStore` and assignment serializer. Atomic replace, flush/fsync, schema migration, and
restart recovery are explicit behavior.
ETS and process state are projections rebuilt from durable records. Unknown versions or
authority fields fail closed; non-authority evidence is preserved rather than silently
dropped.

## Effects and external identity

The Herdr adapter consumes installed help/skill contracts, passes argv arrays without shell
reinterpretation, and parses returned JSON identity. Assignment ownership binds the exact
role, agent name, pane, terminal, session, and run ID. Prompt intent is durable before
delivery. Restart reconciles ambiguous delivery instead of repeating it, and late artifacts
retain their original attempt/run identity.

BEAM monitors do not establish ownership or termination of OS descendants. Checks therefore
run outside coordinator callbacks with durable launch, process-group identity, completion,
deadline, and cancellation evidence. After daemon failure, a surviving matching check is
adopted, or the uncertain run fails with its evidence preserved; it is never blindly rerun.
Pause prevents dispatch and promotion. Stop drains or safely cancels verified owned work.
Control and status remain responsive during silent tests and GPU workloads. Shared build,
database, corpus, GPU, and port resources serialize as declared.
Preparation is task-specific. A workflow-only assignment must not fetch or compile the
Phoenix umbrella, create or migrate a database, or require a running database merely because
the repository also contains those facilities. The admitted ticket's declared needs select
preparation; shared mutable build or database resources serialize only when that ticket
actually declares them.


Authentication and credentials remain external. No state snapshot, event, log, inspection,
or handoff may contain them. Subscription model selection and the existing declared fallback
policy remain explicit: positive Claude subscription quota exhaustion may use its configured
Codex fallback after delivery and owner reconciliation with a new supervisor-issued run ID;
capacity, rate limits, authentication, permissions, ambiguity, or ordinary failure do not
change provider or billing mode. No premium or billed fallback is implied.

## Review, integration, and revision visibility

FR-05 provides fail-closed containment only: submitted identities are no longer synthesized,
auto-approval and production Git bypasses are rejected, and legacy integration cannot start.
FR-13 and FR-14 must establish the exact-candidate review/check and serialized Git guarantees
designed here before promotion is restored. FR-17 separately restores immutable activation.

Every status and board view must display both:

- the source/accepted revision from which runtime code is available; and
- the implementation revision actually loaded by the running Python process or BEAM release.

These revision values are presentation-only labels. They do not prove accepted source,
loaded code, a build manifest, deployment, or activation. FR-17 replaces the disabled raw
source watcher with controller-selected immutable builds and checked rollback.

## Board and inspection

The Elixir board reads the coordinator's authoritative projection and must preserve automatic
refresh, readable cards, keyboard and mouse navigation, detail views, resize behavior, source
freshness, and daemon liveness. A bounded compatibility spike on pinned Elixir 1.20.3 / OTP
29.0.5 precedes the terminal-library choice. Board failure cannot stop dispatch. The Python
board remains available until parity is proved at cutover.

Local BEAM inspection must expose sanitized status/`format_status` and documented attach
instructions without opening public distribution ports or revealing credentials.

## Workspace relocation and rollback

Relocation happens only after the Elixir engine is complete and drained. Before mutation, a
dry-run manifest inventories every `pramana-*` directory and legacy external state/worktree,
including Git common-dir, branch/ref/HEAD, dirty tracked bytes, untracked and ignored content,
live handles, symlinks, destination collisions, disk use, and headroom. Registered checkouts
move through `git worktree move`.

Historical prompts and artifacts remain byte-identical. Their immutable digests are verified
before and after relocation; old absolute paths resolve through a versioned mapping rather
than rewriting historical evidence. Mutable configuration and control references change
transactionally. Each move is journaled before effects so restart can resume or reverse it.
The original checkout's tracked and untracked edits are never moved or rewritten, and the
current root chat's working directory is never moved underneath it.
Before any tracked ignore is available in the original checkout's current branch, protect
`workflow/local/` there with a narrowly scoped entry in that checkout's local Git exclude.
Verify the exclusion before creating runtime files, retain it through the move, and remove it
only after the tracked ignore reaches that branch. Never stage the local exclude or unrelated
user files.

## Cutover and cutover interfaces

Cutover drains and fences Python, snapshots and imports the latest state, starts the pinned OTP
release in a dedicated pane, and proves controls, board, identities, review, checks, and one
bounded real task. The following interfaces are implemented and fixture-proven under
`workflow/lib/pramana_workflow/cutover/`:

- `PramanaWorkflow.Cutover.SupervisorControl.status/2`, `drain/3`, `undrain/2`, `start_daemon/4`,
  `pause/2`, `stop/2`, `await_drained/2`, `await_undrained/2`, `drain_state/1`: typed Python
  supervisor CLI wrapper for bounded drain/fence with polling loops. The operator issues
  `drain --timeout-seconds N` to block new dispatch and wait for in-flight workers; `undrain`
  restores dispatch capability.

- `PramanaWorkflow.Cutover.Import.extract/1`, `import/2`, `read_manifest/1`, `verify_manifest/1`:
  schema-validated, digest-verified, crash-recoverable durable state import. The operator
  reads the latest `state.json` and writes a manifest under an archive directory. Each record
  retains its full original assignment map so identity is preserved.

- `PramanaWorkflow.Cutover.Release.start/2`, `stop/2`, `health_probe/0`, `health_check/2`,
  `activate/2`: OTP release activation via the release binary's daemon/rpc verbs. The operator
  runs `activate/2` to start the release and poll for coordinator health.

- `PramanaWorkflow.Cutover.Rollback.rollback/4`: combined rollback that stops the OTP release,
  removes the Python fence via `undrain`, waits for dispatch restoration, and verifies the
  import archive is still byte-identical. Each step's result is kept in the returned map even
  on partial failure.

Rollback is first exercised in a fixture (proven in `test/pramana_workflow/cutover_test.exs`).
Production rollback consumes the latest Elixir state only through a tested compatible export;
it must not silently restore an older accepted revision. Python runtime and wrappers remain
until soak and restart evidence makes retirement safe.

## Executable parity matrix

Each row is a required observable contract. “Fixture” means disposable repositories and fake
backends; “live” means a bounded real Herdr/provider path. Later ticket admission must map each
proof to an exact test or integration check.

| Contract | Planned proof | Owner ticket |
|---|---|---|
| Developer implementation reaches a handoff | Fixture: admitted assignment produces a schema-valid handoff for its exact run | FOUNDATION, ENGINE |
| Independent review binds the candidate commit | Fixture: changed candidate after review is rejected; live cutover task receives separate review | ENGINE, CUTOVER |
| Integration advances only after all checks | Fixture: one failed combined check leaves accepted revision unchanged | ENGINE |
| Rejection enters correction without losing evidence | Fixture: rejected review and correction artifacts remain linked | ENGINE |
| Exactly two correction rounds then park | Virtual/fixture transition test over all three outcomes | ENGINE |
| Crash does not duplicate assignment or prompt | Crash injection before and after intent/delivery checkpoints | FOUNDATION, EFFECTS |
| Context and role recover from canonical files | Fixture restart reloads native entrypoint, role, assignment, task, and run identity | ENGINE |
| Quota cooldown is bounded and model-free | Virtual-time fixture with unrelated provider continuing | ENGINE |
| Only declared subscription fallback occurs | Fixture: positive quota permits configured fallback/new run; other classes refuse | ENGINE |
| Stale review cannot integrate | Fixture: candidate SHA change after verdict parks | ENGINE |
| Pause blocks dispatch and promotion | Fixture during idle and long-running check | EFFECTS, ENGINE |
| Stop drains or cancels only verified ownership | Process-group fixture including descendants and mismatched identity | EFFECTS |
| Two isolated developers can run concurrently | Fixture with disjoint scopes/resources/build/database/ports | ENGINE |
| Integration remains singleton and serial | Fixture contests concurrent promotion attempts | FOUNDATION, ENGINE |
| Singleton fencing works across Python and Elixir | macOS process contest: exactly one coordinator acquires ownership | FOUNDATION |
| Workflow-only preparation avoids application/database setup | Fixture: a workflow-only assignment runs without umbrella dependency preparation or database creation; a database-declaring control still receives its prerequisites | FOUNDATION, ENGINE |
| Runtime dependency boundary stays local and standalone | Dependency/boundary test rejects distributed clustering, Phoenix/Ecto/Postgrex/Oban, general orchestration frameworks, and paid services | FOUNDATION |
| Malformed or oversized artifacts fail closed | Fixture for JSON, UTF-8, shape, size, and identity mismatch | FOUNDATION, ENGINE |
| Ambiguous prompt delivery is reconciled | Crash fixture never sends a second prompt without proof of absence | EFFECTS |
| Silent surviving check is adopted once | Kill/restart fixture adopts matching process-group/completion evidence | EFFECTS |
| Uncertain check is not rerun | Crash window fixture preserves evidence and returns explicit failure | EFFECTS |
| Failed cleanup preserves a replacement owner | Stale PID/session/terminal fixtures refuse signaling or pane close | EFFECTS |
| Runtime and source revisions are both visible | Status/board fixture shows mismatch until controlled restart | ENGINE, BOARD |
| PM batches are transactional | Fixture: one invalid create/amend/park rejects the entire batch | ENGINE |
| Control stays responsive during long work | Fixture status/pause/stop while a silent child runs | EFFECTS |
| File move resumes after crash | Fixture injects failure at every journaled boundary and reaches one manifest | WORKSPACE-MOVE |
| Historical evidence survives relocation | Before/after byte and digest comparison with versioned old-path lookup | WORKSPACE-MOVE |
| Runtime root is protected during branch transition | Disposable original checkout: local Git exclude hides only `workflow/local/` until the tracked ignore reaches that branch, then is removed without staging user files | WORKSPACE-MOVE |
| Rollback uses latest state | Fixture exports latest Elixir state and rejects silent old-revision restoration | CUTOVER |
| TUI failure cannot stop dispatch | Fixture terminates board while coordinator continues | BOARD |
| Real cutover works end to end | Live: one bounded Herdr/OMP task, review, checks, and serial integration | CUTOVER |
| Unattended restart remains safe | Bounded soak plus daemon/check crash recovery, separately labeled from fixtures | RETIRE |

Cooldown tests use virtual time. Crash tests inject failure at side-effect boundaries. Fixture,
live-provider, and elapsed-time evidence stay separately labeled. No LLM polls runtime state,
and no duplicate broad suite is added without a distinct risk it can detect.

### EFFECTS-owned rows: exact test mapping

These proofs are at the primitive level implemented by `WF-ELIXIR-EFFECTS-01`
(`workflow/lib/pramana_workflow/{herdr,effects,checks}/**`) and are not yet integrated with a
live coordinator, scheduler, or dispatch loop — that wiring is ENGINE's row to close.

| Contract | Exact test |
|---|---|
| Crash does not duplicate assignment or prompt | `test/pramana_workflow/effects/launch_test.exs`, `test/pramana_workflow/effects/prompt_delivery_test.exs` |
| Ambiguous prompt delivery is reconciled | `test/pramana_workflow/effects/prompt_delivery_test.exs` |
| Silent surviving check is adopted once | `test/pramana_workflow/checks/adoption_test.exs` |
| Uncertain check is not rerun | `test/pramana_workflow/checks/status_test.exs`, `test/pramana_workflow/checks/adoption_test.exs` |
| Stop drains or cancels only verified ownership | `test/pramana_workflow/checks/runner_test.exs` (real `sh`/`sleep` process, `ProcessGroup.signal/2`) |
| Failed cleanup preserves a replacement owner | `test/pramana_workflow/checks/runner_test.exs`, `test/pramana_workflow/effects/process_group_test.exs` |
| Control stays responsive during long work | Not yet integration-proven: `Checks.Runner.terminate/3` returns without blocking on the check, but no coordinator loop exists yet to demonstrate status/pause/stop responsiveness end to end |

### WORKSPACE-MOVE-owned rows: exact test mapping

These proofs are implemented by `WF-WORKSPACE-MOVE-01` (`workflow/lib/pramana_workflow/relocation/**`
and `workflow/lib/pramana_workflow/relocation.ex`):

| Contract | Exact test |
|---|---|
| File move resumes after crash | `test/pramana_workflow/relocation/crash_recovery_test.exs` injects failure at every journaled boundary (`:after_prepare`, `:before_move`, `:after_move`, `:after_digest_verify`, `:after_complete`, `:after_path_map`), proving deterministic resumption and clean rollback |
| Historical evidence survives relocation | `test/pramana_workflow/relocation/digest_test.exs`, `test/pramana_workflow/relocation/path_map_test.exs`, `test/pramana_workflow/relocation/crash_recovery_test.exs` |
| Runtime root is protected during branch transition | `test/pramana_workflow/relocation/local_exclude_test.exs` (disposable Git fixture hides `workflow/local/`, verifies probe, removes exclusion cleanly without staging user files) |

### CUTOVER-owned rows: exact test mapping

These proofs are at the cutover level implemented by `WF-ELIXIR-CUTOVER-02`
(`workflow/lib/pramana_workflow/cutover/**`, `automation/pramana_supervisor.py`) and are
fixture-proven. The live Python runtime remains authoritative until the operator activates
the pinned release and exercises verified rollback.

| Contract | Exact test |
|---|---|
| Drain accepted while idle transitions to drained | `test/pramana_workflow/cutover/supervisor_control_test.exs` ("drain accepted while idle transitions promptly to drained and checkpoints durable evidence") |
| Undrain restores dispatch and the cycle works again | `test/pramana_workflow/cutover/supervisor_control_test.exs` ("undrain cleanly restores dispatch capability and a fresh drain works again after it") |
| Already-drained supervisor refuses to dispatch | `test/pramana_workflow/cutover/supervisor_control_test.exs` ("a supervisor started already drained refuses to dispatch a queued ticket") |
| Bounded drain waits for in-flight workers | `test/pramana_workflow/cutover/supervisor_control_test.exs` ("a bounded drain waits for an in-flight owned worker instead of falsely completing") |
| Reject malformed state with structured error | `test/pramana_workflow/cutover/import_test.exs` ("extract rejects malformed state (wrong schema_version)") |
| Reject unknown top-level fields | `test/pramana_workflow/cutover/import_test.exs` ("extract rejects a snapshot with an unknown top-level field") |
| Filter importable statuses correctly | `test/pramana_workflow/cutover/import_test.exs` ("extract returns only accepted/working/parked/blocked records, sorted by task_id") |
| Write digest-verified manifest | `test/pramana_workflow/cutover/import_test.exs` ("import writes a digest-verified manifest preserving full record identity") |
| Detect tampered archive | `test/pramana_workflow/cutover/import_test.exs` ("verify_manifest detects a tampered archive") |
| Crash-recoverable import retry | `test/pramana_workflow/cutover/import_test.exs` ("a retried import after an injected crash still reaches one recovered manifest") |
| health_probe reports coordinator state | `test/pramana_workflow/cutover/release_test.exs` ("health_probe/0 reports the coordinator's live accepted revision") |
| Release start/stop verbs | `test/pramana_workflow/cutover/release_test.exs` ("start/2 and stop/2 run the release binary's daemon/stop verbs") |
| Release health_check parses rpc JSON | `test/pramana_workflow/cutover/release_test.exs` ("health_check/2 parses the JSON line rpc prints, ignoring any banner text") |
| Release activate polls until healthy | `test/pramana_workflow/cutover/release_test.exs` ("activate/2 polls health_check until healthy within the start timeout") |
| Release activate gives up on timeout | `test/pramana_workflow/cutover/release_test.exs` ("activate/2 gives up at the bound when the release never becomes healthy") |
| End-to-end cutover: import, dispatch, rollback | `test/pramana_workflow/cutover_test.exs` ("cutover: import Python's drained state, run one bounded real task through the Elixir coordinator, then roll back cleanly") |

### RETIRE-owned rows: exact test mapping

These proofs are at the cutover/retirement level implemented by `WF-ELIXIR-RETIRE-01`
(`workflow/lib/pramana_workflow/cutover/{soak,retire}.ex`,
`workflow/test/pramana_workflow/cutover/{soak,retire}_test.exs`).

| Contract | Exact test |
|---|---|
| Bounded soak completes without crash | `test/pramana_workflow/cutover/soak_test.exs` ("default iterations complete without crash", "many iterations for stress") |
| No duplicate dispatch during soak | `test/pramana_workflow/cutover/soak_test.exs` ("all dispatched run_ids are distinct") |
| No state loss during soak | `test/pramana_workflow/cutover/soak_test.exs` ("all enqueued tickets are accounted for") |
| Controlled restart proves assignments survive | `test/pramana_workflow/cutover/soak_test.exs` ("controlled restart proves assignments survive", "no duplicate dispatch after restart") |
| Soak completes in bounded virtual time | `test/pramana_workflow/cutover/soak_test.exs` ("completes within normal process dispatch latency") |
| Retire stops daemon, archives state, removes wrappers | `test/pramana_workflow/cutover/retire_test.exs` ("stops the daemon, archives state, removes wrappers, and installs smoke check") |
| Retire writes digest-verified archive manifest | `test/pramana_workflow/cutover/retire_test.exs` ("archives state files to the archive directory with a manifest") |
| Retire removes Python runtime wrappers | `test/pramana_workflow/cutover/retire_test.exs` ("removes Python runtime wrappers") |
| Retire installs executable smoke check | `test/pramana_workflow/cutover/retire_test.exs` ("installs the retire smoke check binary") |
| Verify retired detects missing wrappers | `test/pramana_workflow/cutover/retire_test.exs` ("returns :ok when all wrappers removed and Elixir active") |
| Rollback diagnostics: archived state, checkouts, versioned Python code | `test/pramana_workflow/cutover/retire_test.exs` ("archives state files to the archive directory with a manifest" — manifest contains artifacts with sha256) |
| plan_for_repo generates correct retire plan | `test/pramana_workflow/cutover/retire_test.exs` ("generates a retire plan from a repo root") |
| Retire is idempotent against already-stopped daemon | `test/pramana_workflow/cutover/retire_test.exs` ("idempotent against already-stopped daemon") |

## Cutover-to-retirement checklist

The complete migration chain from cutover through retirement:

1. **Drain** — `Cutover.SupervisorControl.drain/3`: issue `drain --timeout-seconds N` to the
   Python supervisor. Blocks new dispatch and waits for in-flight workers to complete. Verify
   with `Cutover.SupervisorControl.await_drained/2`.

2. **Activate** — `Cutover.Release.activate/2`: start the pinned OTP release in a dedicated
   pane and poll for coordinator health via `health_check/2`. Verify the Elixir coordinator
   reports healthy with the correct accepted revision.

3. **Soak** — `Cutover.Soak.run/1`: run the bounded unattended soak harness against the
   active Elixir coordinator with virtual iterations. Verify:
   - No crash (`evidence.crashes == []`)
   - No duplicate dispatch (`evidence.duplicate_run_ids == []`)
   - No state loss (`evidence.state_loss == []`)
   - Restart survival (`evidence.restart_survived == true`)

4. **Retire** — `Cutover.Retire.retire/1`: stop the Python supervisor daemon, archive its
   durable state to a digest-verified manifest, remove the Python runtime wrappers
   (`bin/pramana-supervisor`, `bin/pramana-board`), and install the smoke check
   (`bin/pramana-retire-smoke`). Verify with `Cutover.Retire.verify_retired/1`.

5. **Rollback (if needed)** — `Cutover.Rollback.rollback/4`: stop the OTP release,
   `undrain` the Python supervisor, verify dispatch restoration, and confirm the import
   archive remains intact for inspection. Rollback diagnostics are preserved in the
   archive directory with SHA-256 digests of every artifact.

Post-retirement diagnostics: the archive directory under
`.pramana-supervisor/archive/retired/` contains the complete durable state snapshot,
retired Python scripts, and a `retire-manifest.json` with SHA-256 digests. Any preserved
task or candidate checkouts remain at their original paths or in the archive. Versioned
Python code (`automation/pramana_supervisor.py`, `automation/pramana_board.py`) is
archived with its source digests for forensic inspection.
