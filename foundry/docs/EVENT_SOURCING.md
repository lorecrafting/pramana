# Event Sourcing Architecture

**Purpose:** This doc exists so a future LLM session can extend the workflow without
reintroducing the bugs we already fixed. Read it before adding a new event type,
state transition, or agent role.

The coordinator is an event-sourced state machine. Every state mutation emits a
durable event to `events.jsonl`. On restart, `Transition.rebuild` replays all events
to reconstruct the full state — the in-memory GenServer state is a disposable cache.

---

## 1. Event conventions

### Validate-first, then write

Events are written **after** validation succeeds, not before. This was a deliberate
decision after discovering that write-ahead caused orphan events in the log when
validation rejected the transition.

```
DO:
  case CoordState.mutate(state, args) do
    {:ok, new_state} ->
      Checkpoint.append(log_path, "event_type", ...)
      {:reply, ..., %{data | state: new_state}}
    {:error, reason} ->
      {:reply, {:error, reason}, data}
  end

DON'T:
  Checkpoint.append(log_path, "event_type", ...)  # orphan if validation fails!
  case CoordState.mutate(state, args) do
    ...
```

**Exceptions:** Side-effect notification events (pane_created, task_crashed,
task_completed) are written before state update because they record an observed
fact (the pane was created, the agent crashed) — validation can't fail for these.

### One event per mutation

Each GenServer handler writes exactly one event per state transition. If a
transition has two phases (e.g., integrate starts then completes), write two
events.

### Event schema

Every event has these fields (enforced by `Schema.validate(:event, ...)`):

```json
{
  "schema_version": 1,
  "event": "event_type_name",
  "at": "2026-09-12T00:00:00Z",
  "task_id": "TASK-ID",
  "run_id": "run-hex",
  "role": "developer|reviewer|pm|system",
  "attributes": { ... transition-specific data },
  "evidence": { ... original payload for audit }
}
```

---

## 2. State reconstruction (Transition.rebuild)

`Transition.rebuild/2` reads `events.jsonl` and produces `%{projection: ..., state: ...}`.

**`state`** — a complete `CoordState`-compatible map: assignments, queue, PM state,
integration lock, provider cooldowns, etc. Each event type's `project/2` function
updates the state map.

**`projection`** — a subset used by `Transition.plan/2` for idempotency checks
(duplicate dispatch, duplicate prompt). Contains `assignments` (task_id → {run_id,
role}) and `prompt_intents` (MapSet of delivered prompts).

### Adding a new event type

1. **Define the event** — choose a name, decide its attributes. Add a `project/2`
   clause in `Transition` that updates BOTH the state map and the projection.
2. **Write the event** — add a `Checkpoint.append` call in the coordinator handler
   (after validation succeeds).
3. **Update plan/2** — only if the event affects duplicate-prevention (see
   `@authority_events`).
4. **Test recovery** — add a test to `stress_test.exs` that rebuilds state from
   the new event type.
5. **Update the doc table** below.

### Current events and their state effects

| Event | State effect |
|---|---|
| `ticket_enqueued` | Adds assignment (queued), appends to queue |
| `ticket_re_enqueued` | Sets status to queued, appends to queue |
| `assignment_admitted` | Sets status to dispatched, removes from queue |
| `launch_retried` | Re-enqueues, increments retry count |
| `launch_parked` | Sets status to parked with reason |
| `pane_created` | Records pane_id and agent_name on assignment |
| `handoff_received` | Sets status to handoff_received; auto-approved history is rejected |
| `handoff_recovered` | Same as handoff_received (recovery-only) |
| `review_received` | Sets review_approved or re-queues for correction |
| `integration_started` | Acquires integration owner lock |
| `integration_completed` | Releases a legacy lock; a success becomes an explicit unverified historical claim and cannot update accepted_revision |
| `task_completed` | Maps completion reason to status |
| `task_crashed` | Sets status to crashed with error |
| `assignment_parked` | Sets status to parked with blocker |
| `tick_processed` | Summary metadata, no state mutation |
| `pm_proposal_created` | Records PM proposal state |

### Resilience rules

- **Invalid events are skipped**, not halted. `apply_record` catches
  `Schema.validate` and `project` errors and continues (`{:cont, {:ok, result}}`).
- **Duplicate assignment admissions** supersede to the latest identity (different
  run_id after re-enqueue overwrites the old). True duplicates (same run_id) are
  skipped.
- **Duplicate ticket_enqueued** deduplicate the queue (second event updates the
  ticket data but doesn't add to queue).
- **Unknown event types** are recorded in the projection's event list for audit
  but don't mutate state.

---

## 3. Deterministic gates

The checks below describe legacy containment. They are not complete acceptance evidence;
FR-13 owns immutable artifacts, controller receipts and full-diff scope verification.

| Gate | What it checks | Where |
|---|---|---|
| **Ticket structure** | scope must be list of strings, checks must be command lists | `CoordState.validate_ticket_structure` |
| **Base revision** | ticket.base_revision must equal coordinator.accepted_revision | `CoordState.enqueue_ticket` |
| **Handoff fields** | handoff must have exactly `@completed_fields` or `@blocked_fields` set | `Assignments.Handoff.validate` |
| **Handoff identity** | task_id, run_id must match the assignment | `Assignments.Handoff.validate` |
| **Handoff git check** | checkout HEAD must be a descendant of assigned_base | `validate_clean_checkout` |
| **Handoff scope** | changed_files must be within ticket scope | `validate_changed_files` |
| **Handoff checks** | every required_check must have been run with exit_code | `validate_checks` |
| **Review identity** | task_id and commit match; run_id is the separately issued reviewer identity | `Reviews.Artifact.validate` |
| **Review checks** | checks must match ticket.review_required_checks | `validate_checks` |
| **Review checkout** | checkout HEAD must match accepted_revision | `validate_checkout_consistency` |
| **Legacy integration** | unconditionally suspended before intent, check, Git and state effects | `Coordinator.integrate`, `CoordState.integrate_candidate` |
| **Correction limit** | max corrections (from ticket.corrections.max, default 2) | `Correction.handle_review` |
| **Launch retry budget** | max_launch_retries (default 3), then parked | Coordinator opts + tick |
| **Work retry budget** | max_work_retries (default 2), then parked | Coordinator opts |
| **Handoff retry budget** | max_handoff_retries (default 3), then parked | CoordState.receive_handoff |

---

## 4. AgentServer role system

The same `AgentServer` module handles both developer and reviewer agents. The
`role` option (`:developer` or `:reviewer`) controls:

| Behavior | Developer | Reviewer |
|---|---|---|
| Agent name prefix | `pramana-dev-` | `pramana-review-` |
| Role file | `foundry/roles/developer.md` | `foundry/roles/reviewer.md` |
| Prompt | "Execute assignment..." | "Review the completed assignment..." |
| Result submission | `AgentServer.handoff/3` | `AgentServer.submit_review/3` |
| Post-handoff state | `:pending_review` (wait for review) | N/A (stops after review) |

### Lifecycle

```
Developer:
  init → :launch → do_launch (split pane, start agent, prompt)
  → {:noreply, launched_state}
  → AgentServer.handoff(pid, data) → received_handoff → enters :pending_review
  → receives {:apply_correction, review} (if corrections needed)
  → OR receives :review_approved → cleanup pane → send {:agent_completed, ...} → stop

Reviewer (launched by coordinator after successful handoff):
  init → :launch → do_launch (split pane, start agent, prompt with handoff context)
  → {:noreply, launched_state}
  → AgentServer.submit_review(pid, data) → received review → cleanup pane → stop
```

### Pane lifecycle (cleanup)

| Shutdown reason | Cleans up pane? | Trigger |
|---|---|---|
| `:normal` | **No** (handler already did it) | Handoff/submit_review success |
| `:shutdown` | **Yes** | Supervisor kills agent (terminal-state cleanup) |
| Other (crash) | **Yes** | Process crash, also sends `:agent_crashed` |

**Orphan pane cleanup:**
- Startup: `cleanup_orphan_panes` in coordinator init
- Periodic: every 16 ticks (~4 min) via the tick handler
- Manual: `cleanup_agents_for_task` on terminal state (integrated, parked)

### Error feedback loop (LLM not following its role file)

If the LLM agent ignores the role file and produces a malformed artifact, the
validation gate rejects it. The system then auto-re-enqueues the task (up to
`max_handoff_retries`). On the next launch, the **rejection reason is threaded
into the agent's prompt** as `previous_error`:

```
Attempt 1: prompt → agent writes handoff with wrong run_id → validation rejects
  → error stored on assignment: "completed handoff run_id mismatch"
  → task re-enqueued
Attempt 2: prompt includes "Previous attempt failed with: completed handoff
  run_id mismatch" → agent corrects the run_id → validation passes
```

This is implemented in:
- `coordinator/tick.ex` — reads `error` from assignment, passes as `previous_error`
  in `handoff_data` to AgentServer
- `agent_server.ex` — if `handoff_data.previous_error` is non-empty, appends it
  to the agent prompt as a self-correction hint

Without this feedback, a hallucinating agent produces the same malformed artifact
on every retry until it exhausts the retry budget and gets parked permanently.

The former live lifecycle recipe is intentionally unavailable. FR-13/FR-14/FR-17 restore
verified evidence, Git promotion and immutable activation; FR-22 owns the final executable
lifecycle proof. Until then, submission may reach review but cannot promote or activate.

Historical pre-containment checklist (not executable acceptance guidance):

```
1. Create a checkout with proper git history
2. Start daemon: COORDINATOR_TICK=1 HERDR_ENV=1 bin/pramana_foundry daemon
3. Enqueue: Coordinator.enqueue_ticket(%{...scope, required_checks, checkout...})
4. Wait for tick → developer AgentServer launches → Herdr pane appears
5. Submit handoff: AgentServer.handoff(dev_pid, %{...valid handoff...})
   → dev enters pending_review, reviewer launched automatically
6. Submit review: AgentServer.submit_review(reviewer_pid, %{...valid review...})
   → or Coordinator.receive_review(task_id, review) if reviewer pane not tracked
7. Legacy integration is suspended; no bypass or map-only promotion is accepted
8. Revision labels in status are presentation-only, not acceptance evidence
```

---

## 6. Common failure modes (and what to check)

| Symptom | Likely cause | Fix |
|---|---|---|
| Event log has orphan events after restart | Handoff/review event was written before validation | Move Checkpoint.append after CoordState call |
| Task stuck in "handoff_received" forever | Reviewer never launched, or review never submitted | Check reviewer launch in coordinator's receive_handoff |
| Pane visible after task is done | terminate/2 didn't clean up on :shutdown | Update terminate/2 cond (we fixed this) |
| Rebuild crashes with identity mismatch | Two assignment_admitted for same task with different run_ids | project_assignment should supersede (we fixed this) |
| Correction never processed | Task was queued as "queued_correction" which tick ignores | Use "queued" status (we fixed this) |
| Telemetry not writing | emit_telemetry catches nil path silently | Don't pass nil as telemetry_path |
