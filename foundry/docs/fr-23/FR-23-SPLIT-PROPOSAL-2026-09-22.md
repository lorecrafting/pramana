# Proposal: split FR-23 into FR-23a (hygiene now) and FR-23b (decomposition and retirement)

**Type:** proposal only. It edits no ticket, and it needs the user's approval before
[REPAIR-PLAN](../REPAIR-PLAN.md) changes. **Baseline:** `b46d3825` on `repair/fr08b-kernel`.
Every path and line below is at that commit.

**Governing text:** [FR-23](../REPAIR-PLAN.md#fr-23--retire-legacy-surfaces-decompose-god-modules-and-restore-code-hygiene)
and its table row. FR-23 depends on FR-08B, FR-12 and FR-19B, and FR-22 depends on FR-23.
Its acceptance is behaviour-preserving work, with no test deleted or weakened and every
revision-bound attestation rebound in the same commit as its subject. It excludes any
behaviour change.

**Evidence used**, all dated 2026-09-22 and all in the tree:
[documentation retirement inventory](../DOC-RETIREMENT-INVENTORY-2026-09-22.md) (`5ba15f3b`),
[bin script health check](../BIN-SCRIPT-HEALTH-2026-09-22.md) (`87ee6d57`),
[O0 authority inventory](../orchestrator/O0-AUTHORITY-INVENTORY-2026-09-22.md) (`b4396ac0`),
and the [implementation log](../IMPLEMENTATION-LOG.md) entries of that date named below.
A **dead-identifier inventory is forthcoming** and is not in this tree. This proposal does
not state its contents. It only says where its rows would go.

## Why split

FR-23 bundles two kinds of work with different blockers:

- **Work on files no blocking ticket rewrites.** This includes the formatter baseline,
  documentation status routes, bin-script drift, worktrees and branches, and test
  assertions. Nothing in FR-08B, FR-10, FR-11, FR-12 or FR-19B makes it stale. Part of it
  has already been done under FR-23's name tonight, while the ticket is marked Blocked.
- **Work on files those tickets are about to rewrite.** This covers decomposing
  `protected_primitives.ex` and `gateway.ex`, removing legacy JSONL and `events.jsonl`
  references, and retiring migration-era document sections. Doing it now would either
  conflict with those tickets or be redone after them.

A single ticket makes the first kind wait for the second. It also leaves no place to record
the first kind as done.

## FR-23a — hygiene that does not wait for FR-10/11/12/19B

### Contents

The FR-23 *general hygiene* part, the parts of *documentation retirement* that touch no
FR-08B- or FR-19B-owned file, and any *dead surface* whose only sites are in files outside
the rewrite set below.

### Already done on 2026-09-22

| Item | Commit | Record |
|---|---|---|
| Formatter baseline emptied. The six pinned files were already formatted, and `mix format --check-formatted` passes with nothing exempt. No source changed, so no attestation was rebound | `3c61c075` | Log: "FR-23 general hygiene: formatter baseline emptied" |
| Dated status notes on the five designs whose mechanism is live, plus the stale README row | `6bc015ed` | Retirement inventory, "Stale status lines" |
| Documentation classified for retirement. Nothing was retired, and no RETIRE row can be acted on before FR-08B | `5ba15f3b` | Retirement inventory |
| FR-23's recorded `SystemMetrics.system/0` defect confirmed already fixed by `63ee6cb6` | `16744cd9` | Log: "FR-23's live defect was already fixed…" |
| Bin scripts checked for self-check drift. None had drifted, and two stale restated counts were replaced with a pointer to the script | `87ee6d57` | Bin health check |
| `closure_probe.exs` exits non-zero on a regression, and the sweep header's worker default was corrected | `6e05c4b7` | Commit message |

**Done tonight but not FR-23a work:**

- **`91dc324c`** (the Improver proposes nothing until FR-20) is a behaviour change. FR-23
  excludes behaviour changes. It is containment for FR-20's path, which the `SystemMetrics`
  fix opened (log: "The Improver's proposal step is off until FR-20").
- **`b46d3825`** (loose refusal assertions pinned) applies rule 5 of
  [evidence tools](../EVIDENCE-TOOLS.md). It strengthens tests and matches FR-23a's rules,
  but FR-23's scope does not name it.

The user decides whether either is credited to FR-23a.

### Remaining

- **Worktrees and branches.** The log has no entry recording a cleanup tonight. Per FR-23,
  enumerate them from Git (`git worktree list`, `git branch`) rather than keep a list.
- **Bin-script drift the health check recorded and nobody changed:**
  - `assessor_eval.exs`: the documented `-- INPUT.json` invocation, both in the script and in
    [ASSESSOR.md](../ASSESSOR.md).
  - `guard_mutation_sweep.exs`: its usage line, which runs a mode-644 file that has no
    shebang, and its `cp -al … deps` step in a checkout without `foundry/deps`.
  - `tickets_from_review.sh`: mode 644.
  - `closure_cost.exs`: its header figure.

  Each is a usage or documentation fix. Changing the sweep's `cp -al` behaviour would be a
  script behaviour change and needs its own justification.
- **Gate additions** from the health check. See [the gate section](#gate-recommendations-from-the-bin-health-check).
- **Dead identifiers whose every site is outside the rewrite set.** Which ones these are
  waits on the forthcoming inventory. Every identifier FR-23 itself names at `9dd30c3` sits
  in the rewrite set: `RecordCodec`'s `@command_types`, `legacy_*`, and the
  `events.jsonl`/`EventLog` references. It therefore goes to FR-23b unless that inventory
  shows otherwise.

### Dependencies: none on FR-10/11/12/19B

The argument is from the files each ticket's scope rewrites. The mapping comes from the
plan's scope text plus the O0 inventory's crossing table, which says where the relevant
code lives. Paths are under `foundry/lib/pramana_foundry/`.

| Ticket | Scope (plan) | Files it rewrites |
|---|---|---|
| FR-08B | Every command ingress through one reducer; legacy JSONL stops deciding live truth | `workflow/kernel*`, `coordinator.ex`, `coordinator/tick.ex`, `effects/checkpoint.ex`, `event_log.ex` (O0 §1, C3, C12) |
| FR-10 | Effect IDs, intents and receipts; pending/claimed/issued/unknown under the protected gateway; worker monitoring | `durable_store/gateway.ex`, `durable_store/protected_primitives.ex`, `durable_store/transition_plan.ex`, `effects/launch.ex`, `effects/prompt_delivery.ex`, `coordinator.ex` (O0 K1–K16, §3.2) |
| FR-11 | Timeouts, corrections, retry budgets, and CLI and automatic review on one path | `coordinator.ex`, `coordinator/state.ex`, `assignments/correction.ex`, `reviews/` (O0 C5–C7) |
| FR-12 | Tick through the real scheduler, common admission, review capacity | `coordinator/tick.ex`, `scheduler/`, `launch_eligibility.ex` (O0 C2–C4) |
| FR-19B | Diagnostic retention; repair or retire relocation | `relocation.ex`, `relocation/`, and the diagnostic log writers (`telemetry/`, `event_log.ex`, `consolidated_log.ex`) |

The rows are inferred from scope prose and O0's `file:line` citations. They are not a
dependency-graph run, and the [dependency review runbook](../../../docs/agents/DEPENDENCY_REVIEW.md)
still applies to each FR-23a change.

FR-23a's contents are `ci/format_debt.exs` (done), `docs/`, `bin/` scripts and their
headers, test files, Git refs and worktrees, and the gate. None of these is in that table.
Nothing FR-10, FR-11, FR-12 or FR-19B delivers can make that work stale or conflict with it.

**Proposed rule in place of a ticket dependency.** An FR-23a change may not touch a file in
the table above. It also may not touch a file pinned by a revision-bound attestation, which
means any path in `repair/fr08a_protected_boundary.ex` or `repair/h0_accepted_fr07_boundary.ex`.
A change that would has to move to FR-23b. FR-08B is live on this branch, so FR-23a also
stays off FR-08B's files; it is not blocked on FR-08B finishing.

### Acceptance

FR-23's rules apply unchanged:

- Each part is behaviour-preserving, and the full model-free suite passes before and after.
- No test is deleted or weakened.
- Every revision-bound attestation over a touched file is rebound in the same commit. The
  file rule above is meant to make that set empty.
- Identifier removal cites a recorded no-dispatch search.
- Routes and the catalog resolve.
- A defect found is recorded and routed, never repaired inside the commit.

## FR-23b — module decomposition and legacy-surface retirement

**Contents:**

- FR-23's *module decomposition*: `protected_primitives.ex`, `gateway.ex`, and the other
  modules FR-23's scope finds over 800 lines at `9dd30c3`. The kernel-file split proposed in
  REPAIR-PLAN's FR-08B section is FR-08B's own item, not this ticket's.
- *Dead surface removal* in the rewrite set.
- The retirement inventory's RETIRE sections, which are file splits of
  [MIGRATION.md](../MIGRATION.md) and [MIGRATION-TICKETS.md](../MIGRATION-TICKETS.md).
- The OWNED-ELSEWHERE rows, once their owners finish.

**Dependencies:** FR-23's current set, FR-08B, FR-12 and FR-19B, each still for a reason:

- **FR-08B.** It owns retiring legacy JSONL from live truth. The retirement inventory
  records `events.jsonl` as still live in four `lib/` modules, and `Checkpoint.append` as
  still called from `coordinator.ex`, `coordinator/tick.ex` and `effects/prompt_delivery.ex`.
  O0 §1 records that the kernel has no production caller. FR-23 may only sweep what FR-08B
  leaves behind. The RETIRE sections sit in files the inventory gates on FR-08B.
- **FR-12.** FR-12 depends on FR-10 and FR-11, so depending on FR-12 transitively waits for
  all three. Together they rewrite `gateway.ex`, `protected_primitives.ex`, `coordinator*`
  and the scheduler, per the table above. Decomposing those first means either conflicting
  with that work or doing it twice. `protected_primitives.ex` has already serialised two
  tickets purely on file granularity, per FR-23's scope.
- **FR-19B.** It owns repairing or retiring relocation. `relocation.ex` and its six modules
  are live, per the retirement inventory. The inventory also gates MIGRATION.md's relocation
  section and MIGRATION-TICKETS' WF-WORKSPACE-MOVE-01 on FR-19B.

**Acceptance and exclusions:** FR-23's text, unchanged.

## Ordering against FR-22

Both halves must land before FR-22, so FR-22 would depend on FR-23a **and** FR-23b. That
reason still holds for each: FR-22 binds to exact revisions, and any sweep after it
invalidates that binding. The split does not permit an FR-23a item after FR-22. Hygiene
found after FR-22 is new work that re-runs FR-22's acceptance.

## Risks of splitting

1. **Attestation churn twice.** Any revision-bound attestation over a touched file must be
   rebound in the same commit. The 2026-09-20 incident is the example: one added function
   in `protected_primitives.ex` set FR-08A to `ready=false` until the evidence was rebound
   (FR-23, "Sequencing"). If FR-23a touches a pinned file, that file gets rebound once in
   FR-23a and again in FR-23b. The file rule above is what prevents this, so it has to hold.
   The rebinds in FR-10/11/12 happen with or without a split.
2. **Scope creep into FR-23a.** "Hygiene" can drift into lib edits. The file rule and the
   no-behaviour-change exclusion are the check. Two items tonight had to be called out as
   not FR-23a (see above).
3. **Two ticket rows to keep true.** FR-23's row already went stale once: it said the
   `SystemMetrics` defect was live after `63ee6cb6` had fixed it (log, 2026-09-22). A split
   doubles that surface.
4. **FR-23a done does not mean "FR-23 nearly done".** Decomposition and JSONL retirement,
   the bulk of FR-23's risk, stay behind FR-12 and FR-19B.

## Gate recommendations from the bin health check

The health check recommends gating `refusal_sites.exs` and `contract_annotation_diff.exs`,
because each is fast and has a red control. It gives a third candidate, `closure_probe.exs`
at depth 5, only once the probe exits non-zero on a regression. `6e05c4b7` did that, but
the check records the probe's run time at about 77 s. It also suggests a test that runs
each documented usage line once. This proposal puts the first two in FR-23a. FR-21's
Excludes clause says to extend its job in each subsequent ticket rather than wait for the
whole repair.

**Where the change actually lands.** `foundry/ci/run.exs` is two lines. It requires
`lib/pramana_foundry/ci.ex` and calls `PramanaFoundry.CI.main/1`. The stages live in
`ci.ex`, so "adding to `ci/run.exs`" means one of two things:

- editing `ci.ex`, or
- adding ExUnit tests that run the scripts. `mix test` is already a gate stage, and this
  leaves `ci.ex` untouched.

**What pins the runner hash.** `git grep -n runner_sha256 -- foundry/` finds one line,
`lib/pramana_foundry/ci.ex:487`, inside `source_provenance/1`. It records the SHA-256 of
**`lib/pramana_foundry/ci.ex`**, not of `ci/run.exs`, together with `workflow_sha256` of
`.github/workflows/foundry-ci.yml`, into each run's `provenance.json`. No code in `foundry/`
reads `runner_sha256` back, so nothing in the tree checks it.

The only other records of these files' hashes are the dated FR-21 evidence files:

- [integration attestation](../fr-21/integration-attestation.md): `ci.ex` `b2cc9c67…` and
  `ci/run.exs` `c1cecbc2…`;
- [review-v2](../fr-21/review-v2.md) and [acceptance-v2](../fr-21/acceptance-v2.md);
- [review](../fr-21/review.md);
- [review-v3](../fr-21/review-v3.md).

These are prose evidence of what was checked at that time. `ci.ex` has already changed since
then (`d311a03d`), and `shasum -a 256` at `b46d3825` gives `f863e070…`, with no test
failing. So:

- an ExUnit route changes no recorded runner hash;
- a `ci.ex` edit changes the hash in every later `provenance.json` but invalidates no
  checked pin;
- a `ci/run.exs` edit changes neither `runner_sha256` nor any checked pin. Its hash appears
  only in the dated FR-21 records, where it still matches.

Neither `ci.ex` nor `ci/run.exs` is among the paths the `repair/` attestation modules pin.

## Proposed plan edit (not applied)

- Replace the FR-23 row with FR-23a (no ticket dependency, under the file rule above) and
  FR-23b (FR-08B, FR-12, FR-19B).
- Change FR-22's dependency on FR-23 to FR-23a and FR-23b.
- Keep FR-23's section as the parent. Every parent outcome, scope, acceptance paragraph and
  exclusion stays binding across both slices, as the plan already says of A/B slices.
