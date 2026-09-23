# Dogfood readiness and the shortest safe path

> **Status, later on 2026-09-23:** M1–M5 **approved by the operator**, recorded as a
> [plan amendment](REPAIR-PLAN.md#dogfood-gate-amendment). T1 (subcommit 2) and T2
> (subcommit 3, reviewer, with Core reviewer independence) have landed and passed Fable
> review with their fixes applied (gate green at `8ed8d233`). §0's "no code has landed" is
> superseded. Next: Batch D (T3–T7).

**Date:** 2026-09-23. **Type:** PROPOSAL; its decisions M1–M5 are now approved. It changes no ticket, dependency,
contract or code. **Taken at `33395c92`** (`repair/fr08b-kernel`). Line numbers are at that
commit and will drift. Paths under `lib/` are relative to `foundry/lib/pramana_foundry/`.

## 0. Answer in brief

- **Distance.** No part of the dogfood alpha runs today. The pure kernel exists and is
  reviewed. It has no production caller. Nothing starts the durable Gateway in production, and
  no human can take a ticket through to a durable review receipt on either path (§3). The next
  piece of the path, subcommit 2's `decide/3`, is designed and approved but no code has landed:
  `grep "def decide" lib` is empty.
- **The plan as written is longer than it looks.** Dogfood means "Batch C and then Batch D"
  (`REPAIR-PLAN.md:128-129`). Batch C includes FR-10 (`:139`). FR-10 depends on FR-09 (`:458`),
  FR-09 depends on FR-15aB (`:457`), and FR-15aB is real host isolation (`:464`). So the
  literal dependency graph puts provider isolation on the dogfood path. The milestone itself
  says execution stays manual until that evidence exists (`:114-118`).
- **Thin-dogfood verdict: possible, but not safely before FR-08B subcommits 2 and 3 (reviewer
  only) land and pass review.** After those, a manual lane can run real work packets with
  durable review receipts. It needs no FR-09, FR-15aB, FR-11 or FR-12, and only an optional
  slice of FR-10, if the operator accepts the named risks in §4. It needs an operator amendment
  to the milestone gate (§6, decision M1).

## 1. What the dogfood alpha must deliver

| # | Requirement | Source |
|---|---|---|
| D1 | Accept real tickets | `REPAIR-PLAN.md:114`; `docs/PLAN.md:355-356` |
| D2 | Track and replay them durably | `REPAIR-PLAN.md:114-115`; `IMPLEMENTATION-LOG.md:1354` |
| D3 | Produce bounded work packets | `REPAIR-PLAN.md:115`, `:226` ("manual work packets") |
| D4 | Accept independently reviewed results, as durable review receipts | `REPAIR-PLAN.md:115`, `:226-227`; `IMPLEMENTATION-LOG.md:1354-1355` |
| D5 | Recover after restart | `REPAIR-PLAN.md:116`; `docs/PLAN.md:357` |
| D6 | Execution stays supervised or manual. The lane "must not silently enable an unproved autonomous provider path" | `REPAIR-PLAN.md:116-118`, `:226-227` |
| D7 | The CLI calls the same semantic operations as any controller. Manual dogfood is one of its named uses | `ORCHESTRATOR-BOUNDARY.md:288-291`; Standard Controller "for initial dogfood" `:714` |
| — | Not claimed: deployment, autonomous execution, completion of any ticket by implication, FR-22 | `REPAIR-PLAN.md:118-119` |

Context, not requirements:

- ROADMAP's G0 is FR-22 (`docs/strategy/ROADMAP.md:22-26`), which is the *second* finish
  line. Dogfood is a pre-G0 milestone. ROADMAP forbids dispatching *product* builds before G0
  (`:29-31`). Using Foundry on Foundry is the milestone's stated purpose (`REPAIR-PLAN.md:117-118`),
  so the operator should confirm that it is not a product build under ROADMAP.
- STRATEGY asks for operator effort per independently accepted outcome (`STRATEGY.md:44-46`).
  Dogfood is the first place that number can be measured, but no document makes it a gate.

## 2. Requirement → ticket → status at `33395c92` → does dogfood need it?

"Full lane" means the autonomous, provider-executing lane that dogfood explicitly excludes (D6).

| Req | Provider | Status | Dogfood needs | Full lane only |
|---|---|---|---|---|
| D1 admission | FR-08B `ticket_admitted` (O0 S2); FR-12 common admission and spec/checkout validation (`REPAIR-PLAN.md:1001-1003`) | The kernel event exists. The codec cannot carry the kernel's steering or evidence types (O0 `:34`). That fix is `decide/3` commit 0 (`FR08B-SUBCOMMIT2-DECIDE-DESIGN-2026-09-23.md:282-285`), not landed | A durable admission, plus base, scope and acceptance validation | FR-12's scheduler, capacity, priorities and dependencies (`:1005-1024`) |
| D2 track/replay | FR-08B, one live/replay reducer (`:853-889`) | Subcommit 1 closed. Subcommit 2 designed and approved (`…DECIDE…:3-14`); code not landed. Subcommit 3 approved with PM removed (`FR08B-SUBCOMMIT3-DESIGN-2026-09-23.md:3-6`, `:66-79`). Subcommits 4 and 5 not designed | `decide/3` for the developer and reviewer; a production Gateway | The four subcommit 5 ingress migrations (`fr08b-kernel-correction-design.md:235-241`) that retire the legacy JSONL paths |
| D3 work packets | No ticket. Batch D itself (`REPAIR-PLAN.md:226`). FR-12 is the nearest: "launch receives the admitted environment and assignment" (`:1008-1010`) | Nothing produces a packet | Yes: a packet format bound to the ticket, attempt, execution and base revision | The launch environment carried into an `AgentServer` |
| D4 review receipts | FR-08B subcommit 3 (reviewer `decide/3`); E3 `review_recorded` (O0 E3); FR-11 review lifecycle; FR-13 artifact and check receipts (`:1030`) | Reducer transitions exist (`…SUBCOMMIT3…:15-17`). The terminal settlement producer landed at `15e53763`. Reviewer `decide/3` not landed. E1–E4 have no protected producer (O0 `:259`) | Reviewer plans; a receipt bound to the exact candidate and reviewer execution | FR-11 timers, crash budgets and automatic review (`:967-992`); FR-13 scope and artifact verification |
| D5 restart | FR-10 (`:934-961`); FR-19A storage and backup, **complete** (`:470`) | FR-10 designed, Q1–Q4 answered (`fr-10/FR10-DESIGN-2026-09-23.md:3-7`). The quarantine exit is closed fail-closed at `69614867`. The rest is not landed | Replay of durable state, plus the operator settling the claims left outstanding | Boot reconciler, worker monitors, `AgentServer` routing, hard-kill matrix (FR-10 D4–D6, commits 5–9, `:215-219`) |
| D6 non-enablement | FR-01 and FR-05 containment, **complete** (`REPAIR-PLAN.md:446`, `:450`) | Automatic launch fails closed before pane creation (`README.md:44-60`). Promotion and activation are disabled (`README.md:29-42`) | Keep all of it as it is | FR-09, FR-15aB and FR-16 restore automatic launch |
| D7 CLI | FR-08B subcommit 5, public-ingress slice (`fr08b-kernel-correction-design.md:235-237`) | Legacy CLI only (§3) | A small set of manual-lane commands through `decide/3` and Gateway | The other three ingress slices |
| — status | FR-18A, **in progress** (`REPAIR-PLAN.md:468`) | A read-only Gateway snapshot and query exist (O0 `:28`) | A minimal `status` over the Gateway store | FR-18B board, telemetry and usage |

## 3. The live path today

**How a human would try it.** Start the release. `bin/pramana ticket create …` runs, then
`handoff submit`, then `review submit`. The RPC allowlist admits exactly these shapes plus
`ticket status`, `ticket list` and `ticket integrate` (`lib/pramana_foundry/cli/rpc.ex:127-151`).

**What works**

- The command transport is inert and bounded (FR-02, `README.md:69-81`).
- `ticket create` enqueues a ticket and persists `ticket_enqueued` to JSONL (O0 C12).
- Containment holds:
  - the tick is off by default (`application.ex:17-19`);
  - the subscription-route gate refuses before admission (`coordinator/tick.ex:66`, then `:75-77`);
  - `auto_approve` is rejected, and legacy integration stops before any effect (`README.md:29-42`).
- The durable store, its backup and recovery (FR-19A) and the FR-08A protected primitives
  exist. The attestation reports `ready=true` on 7 of 7 capabilities (`REPAIR-PLAN.md:454`).

**What is missing**

- **No path reaches a review receipt.** Admission (`CoordState.admit_assignment`) happens only
  inside the tick, after the subscription-route gate (`tick.ex:66-77`), so a manual ticket never
  becomes an assignment. `handoff submit` then fails as "unknown assignment"
  (`coordinator/state.ex:185-186`). Even with an assignment, a review needs a `reviewer_run_id`
  (`reviews/artifact.ex:31-35`). That ID is minted only when an automatic reviewer launch
  succeeds (`coordinator.ex:422`, `:457`), and that launch is contained.
- **Nothing in production starts the durable Gateway.** The supervision tree in
  `application.ex:23-75` has no Gateway child. Only the attestation modules under `repair/`
  call `Gateway.start_link`. The coordinator never calls Gateway (O0 `:25`, seam 5 `:262`).
- **The kernel has no production caller,** and `decide/3` does not exist (O0 `:20-26`).
- **No work packet exists** in any form (D3).

**What is unsafe, and must not be the dogfood lane**

- **Legacy truth is in-memory state plus JSONL** (O0 `:25`). Restart is contained, not
  reconciled: boot enters `recovery_required` (`FR10-DESIGN…:116-120`).
- **The one route to real execution is host-bound.** `AgentServer` would launch OMP directly,
  with no claim or receipt (`FR10-DESIGN…:109-115`), under the host principal
  (`STRATEGY.md:290-307`).
- **`ticket create` falls back to a hard-coded base revision** when the coordinator has no
  `accepted_revision` (`cli.ex:362-363`), so a packet could name a stale base silently.
- **Reviewer independence on the legacy path is a random ID minted by the controller** (O0 U6, `:244`).
- **`ticket unblock` exists in the CLI** (`cli.ex:516`) but is not in the RPC allowlist, so
  `bin/pramana` cannot reach it. On the legacy path it would zero `launch_retries` (O0 C13).

**Stale operator documentation.** The memory note tells each session to read
`foundry/roles/steerer.md`. That file drives `bin/pramana-supervisor`, `automation/RUNBOOK.md`,
`docs/STATUS.md` and `docs/AGENT_GUIDE.md` (`steerer.md:3-4`, `:17-22`). None of them exists at
`33395c92`.

## 4. The thin-dogfood option

**Idea.** The human, or a human-supervised agent session they start themselves, is the
execution channel. Foundry never spawns a process. It records admission, issues one claimed
effect per packet, receives the result as a receipt, binds an independent review to the exact
candidate, and replays all of it after restart. With nothing launched, the FR-09 and FR-15aB
isolation questions do not arise: the executor runs under the same authority as today's manual
development. That is the D6 condition, not a waiver of it.

### Required (T1–T7)

| # | Item | Owner | Why it cannot be skipped |
|---|---|---|---|
| T1 | Subcommit 2, commits 0–5: codec admits the kernel vocabulary and `claim_effect`; domain-read check; `Kernel.Plan`; developer launch, non-start, successor and cancel (`…DECIDE…:282-303`) | FR-08B, in progress | Without commit 0, most plans cannot commit (`…DECIDE…:39-53`). Without `decide/3`, nothing produces a plan |
| T2 | Subcommit 3, reviewer only, commits 1 and 3–5 (`…SUBCOMMIT3…:127-141`) | FR-08B | D4: `review_recorded` requires a reviewer execution. PM is deferred (D2 there) and dogfood does not need it: the operator writes the tickets |
| T3 | A **manual execution backend.** `issue` writes the packet. The receipt arrives through the CLI. Non-start and unknown are operator attestations, settled by the issuer | Batch D | The effect protocol runs claim, issue, adapter, settle (`FR10-DESIGN…:129-137`). The human is the adapter |
| T4 | **Work packet**: ticket and attempt IDs, `execution_id`, base revision taken from the store (never a literal), scope, acceptance criteria, and the reviewer-independence requirement | Batch D | D3 |
| T5 | **Manual-lane CLI**: `admit`, `packet`, `submit`, `review`, `settle`, `status`, through `decide/3` and Gateway. The legacy commands stay as they are | Batch D; the public-ingress slice of subcommit 5 | D7. A separate command set keeps it off `coordinator.ex`, which the other subcommit 5 slices own (`FR-23-SPLIT…:120`) |
| T6 | **Gateway started only behind an explicit flag,** with its own store path, disjoint from the legacy JSONL tickets | Batch D | D2. A ticket must never exist on both paths at once |
| T7 | **A restart drill on the manual lane**: stop the daemon after admit, after issue, after submit and after the review, then check the state rebuilt by replay | Batch D; a subset of FR-10 A5 (`FR10-DESIGN…:27`) | D5 needs evidence, not just a design |

**Checks.** Use the contract's explicit policy-empty check set (R4.12.o3,
`WORKFLOW-CONTRACT.md:475`), or record the checks the human ran as evidence. Do not build
subcommit 4's check workers for this lane.

### Accepted risks (A1–A6); the operator must accept each explicitly

- **A1. Quiescence is attested, not proved.** Today `issuer_quiescent` is a string token
  (`FR10-DESIGN…:75-79`). For a human channel, the operator's attestation *is* the evidence, and
  the record should label it that way.
- **A2. An `unknown` settlement is permanent.** It keeps its units and leases, and there is no
  quarantine exit yet (`FR10-DESIGN…:3-6`). The ticket is abandoned and a new one admitted.
  FR-10 commits 2 and 4 would remove this (`:212-214`). They are optional for thin dogfood.
- **A3. Reviewer independence is attested,** by a fresh agent (per the Fable memory note), not
  proved by principal lineage (O0 U6). **Amended 2026-09-23:** the lineage predicate now
  lands with FR-08B subcommit 3, ahead of FR-10/11/12
  ([plan amendment](REPAIR-PLAN.md#reviewer-independence-amendment)); until FR-15aB, the
  principals it compares are recorded, not proved isolated.
- **A4. No candidate-scope or artifact verification** (FR-13). The reviewer checks the diff
  against the packet's scope by hand.
- **A5. Integration is manual Git outside Foundry.** The lane ends at an approved review.
  Nothing records `integrated`, because E5 has no protected producer (O0 `:137`, U3).
- **A6. Budgets are counted units only.** Foundry spends nothing because it launches nothing.

### Must stay disabled

- `COORDINATOR_TICK`, and with it the whole legacy dispatch path.
- The Herdr System runner's subscription capability. Do not change it as a workaround
  (`README.md:55-60`).
- `AgentServer` launch and prompt.
- `ticket integrate`, `pramana-live.sh`, `tickets_from_review.sh` and `live_test.exs`.
- `auto_approve`.
- PM proposals acting as admission (O0 C9).
- Any paid profile.

The manual backend must never call `Adapter` or Herdr. A test should prove that from the module graph.

**Design:** [Batch D thin lane design](batch-d/THIN-LANE-DESIGN-2026-09-23.md) specifies T3–T7 at `8ed8d233`.

### Verdict

**Not safely before T1 and T2 land and pass review.** Before then, the only paths are the
legacy coordinator, which fails every item in §3, or a hand-written Gateway client, which
would be a third encoding of R4 (`REPAIR-PLAN.md:139-157` argues against a second one).

**After T1 and T2, T3–T7 are enough** under A1–A6. FR-09, FR-15aB, FR-11, FR-12, FR-10
commits 5–9 and FR-08B subcommits 4–5 all stay on the full-lane path. None of them is a
dogfood prerequisite, because thin dogfood has no autonomous worker to reconcile, time out
or schedule.

## 5. Critical path

1. FR-08B subcommit 2: commits 0–5, then its own review.
2. FR-08B subcommit 3, reviewer only. Its batch review with subcommit 4 (`…SUBCOMMIT3…:147`) is
   a sequencing question for the operator (M3).
3. Batch D thin lane: T3–T6, as one reviewed candidate.
4. T7 drill, then the first real packet, with operator effort per accepted outcome recorded.
5. Full lane, unchanged: subcommits 4–5, FR-10 (fake adapter first, per Q1), FR-11, FR-12,
   then FR-09 and FR-15aB.

## 6. Ranked work that shortens the path

**FR-08B's files at `33395c92`:**

- `workflow/kernel*`
- `durable_store/{transition_plan,record_codec,gateway,protected_primitives}.ex`
- `test/support/kernel_*`
- the R4 coverage tests
- `docs/fr-08/fr08a-protected-report.txt`, which every protected change rebinds (`:15-19`)

**Parallel** means it touches none of those files. Parallel work must still have one owner per
file (`REPAIR-PLAN.md:28-31`).

| Rank | Work | Files | Parallel with FR-08B now? |
|---|---|---|---|
| 1 | **M1–M3 below, as a plan amendment.** Record the thin-lane gate and the FR-10→FR-09 edge reading | `REPAIR-PLAN.md` (Batch D and milestone text only), `docs/PLAN.md` | **Yes.** Docs, with operator approval. The FR-08B status row stays with FR-08B's own owner |
| 2 | **Batch D design doc**: T3–T7, the packet schema, the CLI command set, the disabled list and the non-launch test | new `docs/batch-d/…` | **Yes** |
| 3 | **Work packet schema and validator (T4)**: a pure module plus tests. Base revision read from the store, never a literal | new `lib/pramana_foundry/work_packet.ex` and its test | **Yes**, once rank 2 is approved |
| 4 | **Manual execution backend (T3)** against the existing protected primitives, tested at the `create_effect`→`settle_claim` level. It does not call `decide/3` yet | new `lib/pramana_foundry/manual_backend/…` and tests | **Yes on files.** It reads the effect API, which FR-10 commits 2–4 may later change. Keep it thin |
| 5 | **Operator runbook replacing the stale `steerer.md`** for the manual lane. Update the memory note's pointer | `foundry/roles/steerer.md` | **Yes** (FR-23a docs rule, `FR-23-SPLIT…:37-42`) |
| 6 | **FR-10 commit 1, the encoder cost fix** (`FR10-DESIGN…:211`) | `durable_store/encoding.ex` | **Files yes, rebind no.** `encoding.ex` is attestation-pinned (`fr08a-protected-report.txt:19`), so its rebind serializes with FR-08B's. Protected maintenance under R3 |
| 7 | **FR-10 Quint model** (commit 0, `:210`). No `.qnt` file exists at `33395c92` | new `docs/fr-10/*.qnt` | **Yes.** It de-risks A2's later removal |
| 8 | **Gate `refusal_sites.exs` and `contract_annotation_diff.exs`** (`BIN-SCRIPT-HEALTH-2026-09-22.md:105-109`) | `foundry/ci/run.exs` | **Yes** (FR-23a) |
| 9 | **Replace `ticket create`'s hard-coded base-revision fallback** (`cli.ex:362-363`) with a refusal | `cli.ex` | **Yes on files**, but FR-08B subcommit 5 owns public ingress. Coordinate, or leave it until T5 supersedes it |
| 10 | **FR-18A minimal `status` over the Gateway store** | `observations/…` | **Yes.** FR-18A is its own in-progress ticket |
| 11 | **Flagged Gateway supervision child (T6)** | `application.ex` | Files yes. **Wait for rank 2.** It is the lane's on-switch |
| 12 | **T5 CLI and T7 drill** | new CLI module and tests | **No.** Needs T1 and T2 |

Top five to dispatch now: ranks **1, 2, 5, 7 and 8**. They are all docs or gate changes and
none needs the kernel. Ranks 3 and 4 follow once rank 2 is approved.

### Decisions for the operator

- **M1.** Amend the milestone gate. Dogfood requires FR-08B subcommits 2 and 3 (reviewer) plus
  Batch D's thin lane, not all of Batch C. `REPAIR-PLAN.md:128-129` currently says Batch C then
  Batch D. Batch C's completion stays required for the full finish line.
- **M2.** Record that FR-10's dependency on FR-09 (`:458`) and FR-09's on FR-15aB (`:457`) apply
  to the full lane only. A manual backend needs neither. This agrees with the approved FR-10
  Q1, to build against a fake adapter first (`FR10-DESIGN…:3-4`).
- **M3.** Decide whether subcommit 3 (reviewer) may be reviewed before subcommit 4, so thin
  dogfood does not wait on the check, freeze, build and integration workers.
- **M4.** Accept or reject A1–A6 individually.
- **M5.** Confirm that dogfood on Foundry is not a "product build" under ROADMAP G0 (`docs/strategy/ROADMAP.md:29-31`).
