# Foundry repair plan

Created 2026-09-12 from [the audit](AUDIT-2026-09-12.md) and the operator's agreed
contract. This is an external Markdown backlog; it does not depend on Foundry's
admission, state tracking, or agents. No repairs are marked complete by creating it.

The [independent alignment audit](ALIGNMENT-AUDIT-2026-09-19.md), SHA-256
`c825b22bb857ccccd08171d79fae3b2d33ce76025fdf7dcb5db91ecc3ff63fe7`, was
performed read-only against `2f603675e3feb1a65f0ce57a3bd69aa93deec29d`. Its
coordinator-approved dispositions are incorporated here. The report is durable evidence,
not a second backlog; this file remains the sole authority for ticket status, dependency
order and acceptance obligations.

## How to execute this plan

Use one implementation session per ticket. Keep this file as the authoritative
backlog and the audit as dated evidence. Record decisions in versioned design notes,
not only in chat. Read the relevant audit findings and current source before starting:
audit line references and reproductions may become stale as repairs land.

Start with FR-01. Then finish the other ready containment tickets and FR-06 before
starting the dependent workflow redesign. A ticket's dependencies are necessary,
not evidence that its design has already been decided. Rows marked **blocked** need
their dependencies completed and their interface assumptions revalidated. Split a
ticket further if its investigation exposes independently reviewable changes; keep
the original ID as the parent and preserve its acceptance obligations.

Do not dispatch this whole backlog to simultaneous agents. The early work overlaps
in Coordinator, CLI, startup and state contracts. Keep one implementation owner for
those files. Independent work can run concurrently after contracts stabilize, with
explicit file/interface ownership; this plan does not itself launch agents.

### Product and authority contract

- One operator, one machine, Pramāṇa. Retain a standalone OTP application.
- Implement supervisor repairs, transport, persistence, orchestration, validation and
  fixtures in Elixir wherever technically possible. A non-Elixir process is acceptable
  only when the contract inherently crosses that boundary (for example Git, OS process
  acceptance, or the existing Herdr provider CLI), and its necessity must be recorded.
- Lean autonomous execution, including Foundry merge and activation once the
  acceptance and deployment protocols are proved. Temporary containment must name
  the capability it suspends and the ticket that safely restores it.
- Steering owns durable intent, priorities and authority. PM elaborates broad or
  ambiguous objectives; already specified work can go directly to admission.
- Foundry cannot broaden spending, enable paid fallbacks, weaken mandatory gates,
  or increase its authority without explicit operator steering.
- Automatic execution uses explicitly permitted subscription profiles only.
  OpenRouter/DeepSeek paid use remains manual. No eligible profile means affected
  work waits with a reason, rather than consuming another billing channel.
- The current governing repair contract retains OMP as the harness and Herdr as the
  initial presentation backend until explicit revision and renewed review. Pi is the
  preferred first replacement evaluation, not a silent substitution. A pane is optional
  presentation; its lifetime cannot establish workflow success or failure.
- Ticket, attempt, execution/session, pane, artifact, review, integration and
  deployment identities have separate lifetimes and explicit relationships.
- Acknowledged decisions survive restart. Uncertain external outcomes reconcile
  before retry. Agent assertions do not establish acceptance.

### Shared completion requirements

Each implementation must include its relevant executable acceptance evidence,
updated operator/developer documentation, and a status entry here and in
[`docs/PLAN.md`](../../docs/PLAN.md). Record the candidate revision, test commands,
results and remaining limitations. Required review evaluates the exact candidate.
Changing it after review requires renewed validation appropriate to the change.

The [audit probes](audit-2026-09-12/probes.exs) assert **broken behavior**. Use them
to understand a defect, then add regression tests for the required behavior to the
normal suite. Do not preserve a bug just to keep a characterization probe passing.
Keep the original audit as a dated record; link new evidence from ticket completion.

Use isolated temporary state, Git repositories and owned processes. Tests must not
truncate shared logs, broadly close panes, or launch billed fallback profiles.
Model-free tests should cover deterministic contracts. A bounded real subscription
smoke is needed where mocks cannot establish harness behavior; record provider,
profile, limits and observed usage, including unknown values. Existing authorization
permits isolated testing, but does not expand spending or governing policy.

No ticket may claim that the entire repair is complete based on component tests.
FR-22 owns final lifecycle acceptance, while earlier tickets supply the tests it uses.

### Model and context strategy

Recommended working default: **Sol, medium** for bounded ticket implementation,
test writing, documentation and elaborating downstream tickets against settled
contracts. This is an engineering recommendation, not a Foundry model benchmark.
The [official Sol reference](https://developers.openai.com/api/docs/models/gpt-5.6-sol)
documents medium reasoning support; it does not prove a success rate for this repo.

Use **Sol-high** for routine independent review. Use **Astra-high** for the first review
of critical authority, persistence/schema, replay/recovery, R1/R5 budget state, actual
isolation/credential routing, Git custody/CAS and activation/rollback work. Use
**Astra-medium** only for a narrow critical re-review that reruns the reproduced defect
and relevant positive/regression controls against the changed candidate. Re-escalate to
Astra-high when a correction crosses another invariant family or repeated failures show
that the abstraction, rather than one local implementation, is wrong. FR-22 receives a
fresh Astra-high whole-lifecycle review; xhigh is reserved for a concrete cross-cutting
audit chosen explicitly, not the default ticket review tier. Preserve historical model
labels as the evidence identities actually used. Model selection does not replace
deterministic gates or independent review.

Save this plan and decisions before clearing context. A fresh implementation session
needs project instructions, the assigned ticket, shared contracts, relevant findings,
dependency completion evidence, and current source—not the entire audit conversation.
Read more when an interface crosses the assigned scope. Switching models alone is
not a reason to discard useful context.

### Two-level delivery strategy

The repair has two explicit finish lines. They are milestones over this authoritative
ticket graph, not a second backlog, and they do not change any dependency, finding owner,
ticket acceptance paragraph or F01–F24 obligation.

1. **Supervised dogfood alpha.** Foundry can accept real tickets, durably track and replay
   them, produce bounded work packets, accept independently reviewed results, and recover
   after restart. Execution remains supervised/manual until the autonomous provider and
   isolation path has its own required evidence. This milestone permits using Foundry to
   harden Foundry; it is not deployment, autonomous-execution approval, ticket completion
   by implication, or FR-22 lifecycle acceptance.
2. **Full repaired system.** Complete the remaining isolation, automatic execution,
   conserved budgets, Git integration, immutable activation/rollback, maintenance,
   constrained improvement and FR-22 whole-lifecycle acceptance. Only this second finish
   line can close the repair backlog.

**Current operator-directed target, set 2026-09-20: supervised dogfood alpha**, the first
finish line above. This is recorded here rather than only in a session's memory so that a
restarted or cleared session finds it by reading this plan. It changes no dependency,
acceptance paragraph or F01–F24 obligation; it states which finish line is currently being
worked toward. Reaching it means Batch C and then Batch D below. The second finish line
remains the only one that can close the backlog.

Use coherent batches to reach those milestones without creating one unreviewable
FR-08–FR-22 change:

- **Batch A:** current FR-04 correction, H0 and FR-19A may proceed concurrently under
  disjoint ownership; freeze and review each candidate separately.
- **Batch B:** FR-08A plus the minimal FR-18A slice enabled by its settled protected
  interfaces; freeze one critical batch candidate with a per-ticket acceptance matrix.
- **Batch C:** FR-08B, FR-10, FR-11 and FR-12 as one lifecycle branch with attributable
  subcommits and every parent obligation retained; freeze and review the batch as a unit.
- **Batch D:** establish the supervised dogfood lane using manual work packets and durable
  review receipts. It must not silently enable an unproved autonomous provider path.
- **Batch E:** complete isolation/harness conformance, artifact and Git custody, activation,
  and final lifecycle work in the dependency inventory's order.

During a batch, run focused checks for each attributable subcommit, the full relevant
suite at candidate freeze and again after integration, reusable reviewer-owned failure
probes, and one manifest/evidence packet for the frozen batch. Batch review reduces
duplicated context; it never converts missing per-ticket evidence into a pass.

**Brief a reviewer on the delta, not the candidate, and never pay twice for a settled
fact.** Independent review is the most expensive step in this repair, and its cost is
dominated by re-establishing things already established rather than by finding defects.
Recorded 2026-09-20 after a single re-review consumed roughly 383,000 tokens, most of it
recomputing nine attestation hashes, regenerating a report the gate already regenerates,
re-running a full suite whose result was supplied, and re-auditing a whole candidate when
only one correction was in question.

Every review briefing must therefore:

- **State what is already established and must not be re-derived.** Attestation hashes,
  suite counts with their seeds, and CI provenance are supplied as given. A reviewer may
  spot-check any of them and must say so, but re-establishing them as routine is waste:
  the revision-bound gate already recomputes source and loaded-BEAM identities on every
  run and fails closed, so a second manual recomputation proves nothing new.
- **Name the exact revisions and the diff.** "Review `git diff <base> <candidate>`" with
  the commits enumerated, never "review the candidate".
- **For a re-review, scope to the reproduced defect and its regression controls.** Give
  the defect, the correction, and what must still hold. Whole-candidate re-audit is
  explicitly out of scope unless escalation applies.
- **Say what the previous pass of the same reviewer already verified**, so it is not
  repeated. A resumed reviewer retains its own findings; it does not need to rediscover
  them.
- **Ask for a full suite run only when the change plausibly affects unrelated modules.**
  Otherwise supply the result and seed. Concurrent full-suite runs additionally produce
  spurious physical-fault failures, so a redundant one is worse than merely expensive.

**Escalate a narrow re-review to a full one when** the correction touches a different
file or invariant family than the reported defect, or when a previous correction for that
same defect already failed review. Both conditions were met on 2026-09-20: one correction
was itself incomplete for a shape its author had not considered, and two structural gaps
were found only because a review deliberately went broad. Narrow is the default for a
correction; it is not a default for everything.

**Contract coverage is a separate review dimension from candidate correctness.** A
candidate review asks whether the code does what it claims, correctly and safely. A
coverage review asks whether what it claims is enough to satisfy the governing contract.
These are different questions and a candidate can pass the first while failing the second.

Added 2026-09-20 on evidence: two independent reviews passed the FR-08A transition-plan
codec on candidate correctness, and both were right on their own terms. The codec
nonetheless could not express two of R4a's four domain-owner rows — it had no
`review_settled` and no check-worker settlement slot — and could not bind admission
authority on any role, because `launch_authority_v1` had no producer. Neither review was
asked whether the mechanism covered R4a, so neither looked.

Every batch freeze therefore requires one review pass that walks the governing contract
rows — R4's transition table and R4a's domain-owner rows for a lifecycle batch — and, for
each, names where the candidate satisfies it or records that it does not. An obligation
with no home is a blocker, not a gap to be discovered later. Prefer executable coverage
assertions over prose: a test that enumerates the contract's rows and fails when one has
no destination is durable, while a reviewer's row-by-row read is not.

### Coordination efficiency discipline

These rules reduce duplicated context and execution without weakening any dependency,
acceptance paragraph or F01–F24 obligation:

- Keep one active implementation writer for each shared subsystem or unsettled interface.
  Parallel agents may investigate, design tests or review read-only, but they do not edit
  the same authority surface. Integrate shared-interface candidates sequentially.
- Give each bounded agent the ticket, exact base/candidate, relevant contract passages,
  acceptance matrix, known blockers and permitted files—not the full historical corpus.
  Expand context only when a concrete crossed interface requires it.
- Run focused tests while developing. Run the full relevant model-free suite at candidate
  freeze, during independent review when required, and after integration; do not repeat
  identical full runs after every local edit.
- Generate hashes, manifests, revision/tree identities and evidence inventories
  mechanically. Reuse independently owned hostile/fault probes across later tickets when
  their contract remains applicable, while recording the exact revision each run tested.
- Keep a ticket's bounded implementation owner for concrete corrections. Use a different,
  fresh reviewer only after the candidate is frozen; a moving source tree has no review
  verdict. Narrow re-reviews cover the reproduced defect and affected invariant family.
- Batch coherent lifecycle work as defined above, with attributable subcommits and a
  per-ticket acceptance matrix. A batch review never hides a missing ticket obligation.
- When evidence contradicts an invariant or prerequisite, stop that implementation path
  and diagnose the abstraction once. Do not accumulate patches or retries against an
  interface already shown to be wrong.
- Prepare downstream work concurrently only through bounded read-only inventories or test
  design until its dependency interface freezes. Do not code against a speculative API.
- Wait on confirmed live agent/process handles rather than busy-polling. Persist and report
  state changes, candidate identities, verdicts and blockers; repeated unchanged status is
  not progress evidence.

These are coordination rules, not permission to skip independent review, physical or
provider acceptance, actual Git/restart/activation evidence, or FR-22 lifecycle proof.

Use Astra-high at the critical FR-08A authority gate, FR-09 + FR-15aB execution/isolation
gate, FR-13 + FR-14 artifact/Git-custody gate, and FR-17/FR-22 activation/final-lifecycle
gate. Use Astra-medium only for narrow corrections at those gates, Sol-high for routine
independent review, and Sol-medium for implementation. Re-escalate when a correction
crosses invariant families or exposes an abstraction contradiction; reserve Astra-xhigh
for an explicitly chosen new whole-system audit.

Suggested fresh-session instruction:

> Implement FR-01 from foundry/docs/REPAIR-PLAN.md. Read project instructions and
> the plan's shared contract, then its referenced audit findings and current source.
> Confirm dependencies and preserve unrelated working-tree changes. Implement only
> this ticket and its necessary tests/docs. Report evidence and limitations, update
> the backlog, and stop before starting another ticket. If the agreed architecture
> proves inadequate, document the concrete decision needed instead of silently
> changing governing policy.

Substitute the next ready ID. Before ending each session, leave a short completion
or continuation entry under that ticket with files, decisions, tests and exact next
step. FR-06's R4a correction and exact revision-3 inputs passed
[focused independent verification](fr-06/r4a-focused-review.md). This closes the
design gate only; every routed implementation obligation remains open.

## Dependency inventory

**Ready** means specified enough to begin investigation and implementation; it does
not mean a repair has been made. **Blocked** means wait for listed dependencies.

| ID | Deliverable | Depends on | Status | Findings |
|---|---|---|---|---|
| FR-01 | Remove automatic paid execution paths | — | **Complete: reviewed static containment** | F01 |
| FR-02 | Transport CLI arguments as inert data | — | **Complete: reviewed inert transport** | F06 |
| FR-03 | Fence startup and fail closed on legacy persistence errors | — | **Complete: reviewed containment** | F14, F02 |
| FR-04 | Restrict cleanup to verified owned resources | — | **Complete: historical containment plus reviewed current-revision false-death correction integrated** | F05, F23 |
| FR-05 | Contain acceptance and mutable-source activation bypasses | — | **Complete: reviewed containment** | F03, F04, F12, F13, F22 |
| FR-06 | Decide durable workflow and authority contracts | — | **Complete: focused R4a design verification passed** | F02, F07–F09, F13, F22 |
| FR-07 | Implement durable store and compatibility boundary | FR-03, FR-06 | **Complete: independently reviewed and locally integrated; not deployed** | F02, F20, F21 |
| H0 | Honest accepted-FR-07 boundary inventory/report (evidence checkpoint, not a ticket) | FR-07 | **Complete: independently reviewed; 4 pass, 3 unavailable, not ready** | Inherits FR-07/08 handoff evidence only |
| FR-08A | Complete protected primitives and substantive revision-bound handoff proof | H0 | **Complete: protected authority, typed recovery and the atomic protected/domain handoff are independently reviewed and integrated, and the protected-result/domain-plan binding correction that reopened the ticket is closed. All six subcommits — lifecycle event vocabulary, codec, authoritative output derivation, protected discriminator, Gateway plan resolution and replay revalidation — are integrated and independently reviewed; the revision-bound attestation is rebound at `e491e41` and reports ready=true on 7 of 7 capabilities** | F07, F16 |
| FR-08B | Migrate every command ingress to one live/replay reducer | FR-08A | **In progress: the FR-08A dependency is now satisfied in full, which discharges blocker B4; the first pure-kernel slice at `a00decc` still holds an independent BLOCKER on B1–B3, whose correction is designed but not implemented** | F07, F16 |
| F | Bounded Pi-first FR-09/15a execution feasibility (evidence checkpoint, not a ticket) | FR-01, FR-02, FR-03, FR-04, FR-05, FR-06 | **Complete: provider-free inventory independently reviewed; governed execution remains blocked** | Inherits FR-09/15a evidence only |
| FR-09 | Prove the selected execution and presentation contract (OMP governs until reviewed substitution) | FR-01, FR-04, FR-06, FR-15aB, FR-18A, F | Blocked | F08–F10 |
| FR-10 | Persist owned effects and reconcile executions | FR-08B, FR-09 | Blocked | F08, F09 |
| FR-11 | Close correction, timeout and review lifecycles | FR-10 | Blocked | F09, F10, F16 |
| FR-12 | Wire admission, resource scheduling and review capacity | FR-08B, FR-10, FR-11 | Blocked | F04, F11, F15 |
| FR-13 | Verify artifacts, candidate scope and check receipts | FR-02, FR-05, FR-10, FR-12, FR-15aB | Blocked; FR-15 edge removed only under the ownership condition below | F03, F04, F16 |
| FR-14 | Perform serialized recoverable Git integration | FR-13 | Blocked | F12 |
| FR-15aA | Specify feasibility, provisioning and complete executable-path inventory | F | **Complete: executable specification and hostile validator independently reviewed and integrated; no host provisioning performed** | F01, F04, F06, F13, F14, F22 |
| FR-15aB | Prove actual principal/channel/auth/network isolation and useful conformance | FR-02, FR-03, FR-05, FR-06, FR-08B, FR-15aA | Blocked | F01, F04, F06, F13, F14, F22 |
| FR-15 | Implement durable steering and optional PM planning | FR-08B, FR-12, FR-15aB | Blocked | F15, F22 |
| FR-16 | Implement bounded subscription switching | FR-01, FR-09, FR-12, FR-15 | Blocked | F01, F11 |
| FR-17 | Activate immutable accepted builds and recover failures | FR-05, FR-07, FR-14, FR-15, FR-18A, FR-19A, FR-21 | Blocked | F13, F22 |
| FR-18A | Supply minimal canonical observations, identities, unknowns and failure visibility | FR-08A | **In progress: bounded protected effect query independently reviewed and integrated; the recorded execution-summary coverage gap is closed; remaining completion obligations are unchanged** | F17, F18 |
| FR-18B | Complete producer→store→board/classifier/usage chain | FR-18A, FR-10, FR-11 | Blocked | F17, F18 |
| FR-19A | Establish operational storage/backup/recovery and maintenance containment | FR-07 | **Complete: physical ENOSPC/kernel-sync and bounded maintenance recovery independently reviewed and integrated** | F20, F21 |
| FR-19B | Bound diagnostics and repair or retire offline relocation | FR-19A, FR-18B | Blocked | F20, F21 |
| FR-20 | Reconnect constrained improvement proposals | FR-15, FR-18B, FR-17 | Blocked | F19 |
| FR-21 | Establish independent Foundry CI and build provenance | FR-01, FR-04, FR-05 | **Complete: reviewed and integration-attested** | F23, F24 |
| FR-23 | Retire legacy surfaces, decompose god modules and restore code hygiene | FR-08B, FR-12, FR-19B | Blocked | F23, F24 |
| FR-22 | Prove full lifecycle and reconcile operating docs | FR-11, FR-12, FR-13, FR-14, FR-15aA, FR-15aB, FR-15, FR-16, FR-17, FR-18A, FR-18B, FR-19A, FR-19B, FR-20, FR-21, FR-23 | Blocked | F01–F24 |

There are **24 ticket nodes: FR-01 through FR-23, plus child ticket FR-15a**. H0 and F
are bounded evidence checkpoints, and the A/B labels are slices of their existing parent
tickets. **FR-23 is a ticket; F23 and F24 are audit findings** routed to existing owners in
the checksum below. The similar names are unrelated: findings use the `F` prefix and
tickets the `FR` prefix. FR-23 was added on 2026-09-20 by operator direction after repair
work accumulated concrete hygiene evidence; it creates no FR-24. Every parent outcome, scope, acceptance paragraph and
exclusion remains binding across its slices.

Removing FR-15 as a direct FR-13 dependency is valid only because FR-08A/B and FR-15aB
now explicitly own the core steering/policy/grant interfaces that artifact admission must
bind. If implementation leaves any of those interfaces solely in FR-15, restore the
FR-15→FR-13 edge before beginning FR-13. This does not waive the full admitted-spec or
policy-identity acceptance, and FR-17 and FR-22 still require FR-15.

## FR-06 sequencing and supersession

The [workflow contract](WORKFLOW-CONTRACT.md) governs dependent tickets. Original
acceptance paragraphs below remain obligations; these decisions refine mechanisms,
never waive a failing case. No containment is claimed installed by this plan.

| Work class | Tickets / disposition |
|---|---|
| Immediate containment | FR-01 authorized profiles; FR-02 inert transport; FR-03 exclusive startup plus checked legacy persistence; FR-04 owned cleanup; FR-05 disable unsupported acceptance/integration and source watcher activation |
| Superseded interim mechanisms | FR-02 general RPC replaced by FR-15a scoped protocol; FR-03 legacy append patches replaced by FR-07/08 atomic kernel; FR-05 integration/activation suspension restored only by FR-13/14/17 evidence |
| Do not build | A second production journal backend; parallel live/replay reducers; pane-driven recovery; both correction resume and relaunch; synthetic acceptance; raw-source rebuild watcher; custom compaction before choosing storage |
| Durable foundation | FR-06 independent review → FR-07 accepted store → H0 honest inventory → FR-08A protected primitives/full handoff proof → FR-08B one live/replay kernel. FR-15aB uses the completed protected interfaces to establish isolated execution before the later PM loop |
| Early feasibility | Bounded joint FR-09/15a Pi-first investigation may run before FR-08B; it records supported/blocked topology and provisioning needs but closes neither parent and enables nothing |
| Dependent execution | FR-15aB isolation → FR-09 selected-harness conformance → FR-10 recovery → FR-11 lifecycle → FR-12 scheduling → FR-15 durable steering; FR-16 bounded subscription switching |
| Dependent delivery | FR-13 verified evidence → FR-14 protected ref promotion → FR-17 immutable runtime activation; FR-21 supplies build provenance before activation |
| Operational closure | FR-18 projections; FR-19 retention/offline relocation; FR-20 constrained improvement; FR-22 scenario acceptance and documentation |

FR-15a is a child of the existing FR-15 authority work, not an additional audit finding.
FR-15aA records feasibility/provisioning and the complete executable-path inventory;
FR-15aB performs actual principal/channel/auth/network denial and positive-usefulness
conformance against FR-08B's protected interfaces. Initial operator policy, reset/cancel
primitives and claim predicates are FR-08 interfaces exercised under FR-15aB isolation;
the optional PM loop and full steering UX remain FR-15. FR-09 can use bounded
preconfigured assignments and reservations without waiting for FR-12 scheduling/FR-16
switching; live orchestration still cannot bypass those later gates. Host provisioning
and installed OMP compatibility are explicit FR-15a/09 prerequisites, not implied
available because the graph is acyclic.

The F checkpoint evaluates pinned Pi RPC first against the common
start/observe/prompt/interrupt/reconcile/close contract and the required subscription,
reservation, credential and tool-separation topology. **OMP remains the governing
FR-06 baseline until an explicit contract revision and independent review select a
substitute.** Unsupported routes remain blocked; neither direct provider access,
credential copying nor a synthetic adapter is an acceptable feasibility result.

V2 supersedes the **design** of an operator-only workflow kernel: FR-17 restores autonomous
kernel repairs behind the fixed verifier/activation root. No runtime-only demonstration
may stand in for that capability in FR-20/22. FR-05 remains temporary containment until
the restored paths pass their original and v2 acceptance obligations.
FR-07 can build the store contract in isolated tests before controller provisioning;
production authority and execution remain gated by FR-15a. FR-21's early CI need not wait
for the entire lifecycle; expand it as dependent implementation lands.

### Audit acceptance obligations retained

This matrix is a routing checksum, not a replacement audit. Each referenced finding's
full repair/acceptance obligation and the ticket acceptance text remain binding.

| Finding | Owners | Required evidence retained |
|---|---|---|
| F01 | FR-01, FR-09, FR-15a, FR-16 | Every autonomous role, explicit subscription eligibility, quota/unknown/cooldown/restart; no paid fallback |
| F02 | FR-03, FR-07 | Failed writes cannot acknowledge or launch; corrupt/torn/oversize/versioned history never resets; atomic recovery |
| F03 | FR-02, FR-05, FR-13 | Real wrapper preserves raw identity; stale/wrong-role/candidate and fabricated checks rejected |
| F04 | FR-05, FR-12, FR-13, FR-15a | Common admission, protected mandatory gates, actual ancestry/full diff, isolated independent reviewer |
| F05 | FR-04, FR-10 | Foreign/recycled/unknown identities preserved, verified owned cleanup |
| F06 | FR-02, FR-15a | Literal actual-wrapper transport; no general evaluation authority for agents |
| F07 | FR-08, FR-11, FR-17 | All controls/verdicts/PM mutations replay identically; artifacts/budgets retained; stale completion harmless |
| F08 | FR-09, FR-10 | Reconcile before retry; adopt owned surviving work and reviewer continuation; unknown blocks |
| F09 | FR-10, FR-11 | Role/execution IDs, monitors, stale/duplicate/late timers, hard-kill recovery |
| F10 | FR-09, FR-11 | Distinct timeout, single correction strategy, CLI/auto cleanup, role retry accounting |
| F11 | FR-12, FR-16 | Actual scheduler, capacity/review progress, persistent resources, assignment environment, no capacity retry charge |
| F12 | FR-05, FR-14 | Actual refs/trees, responsive async gates, changed base/conflict/concurrent/crash reconciliation |
| F13 | FR-05, FR-15a, FR-17, FR-20, FR-22 | Watcher disabled, immutable accepted build, real start/stop/health and compatible rollback |
| F14 | FR-03, FR-10, FR-15a | Two OS owners, effect-free inspection, stale PID and old-owner effects fenced |
| F15 | FR-12, FR-15 | Durable steering, conditional PM, full admitted spec, no invented authority |
| F16 | FR-08, FR-11, FR-13 | Public blocked/partial schema and lifecycle, explicit partial rescope; no accidental retry |
| F17 | FR-18 | Board/status canonical projection; unavailable/corrupt is not empty healthy |
| F18 | FR-18 | Real producers validate and correlate; resource/usage unknowns explicit |
| F19 | FR-20 | Classifiers consume emitted schemas; deduplication/admission retry/resolution survives restart |
| F20 | FR-07, FR-18, FR-19 | Bounded queries, capacity health, serialized retention/backup/compaction; diagnostics distinct from authority |
| F21 | FR-07, FR-19 | Offline explicit maintenance, strict paths/journal, unknown space/digest/live handles block, verify copy before removal, collision-safe rollback |
| F22 | FR-15a, FR-15, FR-17, FR-18 | Enforced OS/capability boundary, policy provenance, listener inspection, telemetry/crash redaction |
| F23 | FR-04, FR-21, FR-22 | Owned isolated non-vacuous tests, independent CI, real lifecycle/restarts and bounded provider smoke |
| F24 | FR-21, FR-22 | Explicit dependency/executable provenance; retired diagnostic/parity paths resolved; docs match reality |

FR-22 reconciles every row with actual revisions/evidence and remaining gaps. The
storage spike supplies design evidence only; it closes none of these findings.

## Tickets

### FR-01 — Remove automatic paid execution paths

**Outcome:** Every autonomous developer, reviewer and PM launch must use an explicitly
configured subscription profile; missing or exhausted eligibility yields no launch.

**Scope:** Trace AgentServer defaults, Tick, reviewer launch, configuration and all
fallback callers. Add a common launch eligibility check and explicit blocked reason.
Do not guess subscription entitlement from a model name. Keep manually selected paid
execution distinct from automatic routing. Record how temporary configuration feeds
the later protected policy contract.

**Acceptance:** Exercise every autonomous role with absent configuration, an allowed
subscription profile, a paid profile and a quota failure. Assert captured launch argv
and billing/profile selection, and zero launches for disallowed cases. No hidden
OpenRouter default survives. Existing manual paths require explicit invocation.

**Excludes:** Dynamic switching and benchmarking; FR-16 owns switching.

### FR-02 — Transport CLI arguments as inert data

**Outcome:** User text reaches the daemon literally, without becoming Elixir source.

**Scope:** Replace wrapper interpolation with a fixed RPC entry point and an inert,
validated payload transport. Enumerate command types and reject unknown shapes.
Audit the other executable entry points for equivalent interpolation.

**Acceptance:** Run the actual wrapper boundary with quotes, backslashes, newlines,
Unicode, `#{1+1}`, and malformed payloads. Assert exact round-trip values, explicit
errors, and no expression evaluation. Preserve useful command exit statuses.

**Excludes:** A new remote API or distributed control protocol.

### FR-03 — Fence startup and fail closed on legacy persistence errors

**Outcome:** One runtime owns a state directory; inspection cannot start orchestration.

**Scope:** Wire fencing into actual startup before any mutation. Separate daemon,
read-only CLI/board and offline maintenance startup. Define stale-owner recovery
without deleting a live owner's lock. Check that effectful children remain off in
inspection paths even when tick scheduling is disabled.

**Acceptance:** Two OS processes contend for the same isolated state directory; only
one writes or launches. Read-only commands cannot start Coordinator/Improver effects.
Kill the owner and prove defined recovery, including a misleading stale PID case.

**Containment addition (FR-06):** Check every authoritative legacy append before success
or effects; persistence/load/unsupported-version errors enter explicit recovery mode.
Do not translate unreadable history to `[]`. If a legacy multi-write path cannot provide
an honest acknowledgment, disable that path until FR-07/FR-08. Test failing append and
load through public commands as well as startup; assert no acknowledged mutation or
launch after failure. This closes the immediate F02 gap without repairing two reducers.

**Excludes:** Storage format redesign, delivered by FR-07. The legacy append patch is
superseded by SQLite transactions, but writer fencing and effect-free clients remain.

### FR-04 — Restrict cleanup to verified owned resources

**Outcome:** Recovery and test scripts can close only resources they created or whose
persisted ownership has been positively verified.

**Scope:** Remove CWD-based ownership inference and hard-coded pane exceptions from
destructive paths. Require backend identity checks; uncertainty leaves a visible
unresolved resource. Replace broad recovery-test cleanup with isolated test ownership.

**Acceptance:** Foreign panes in the same temporary directory survive cleanup;
recycled pane/process identifiers are not killed; missing identity causes no deletion;
owned resources close successfully. Test cleanup also preserves unrelated state logs.

**Excludes:** Full restart reconciliation, delivered by FR-10.

**Current-revision correction — jointly routed with FR-10 (2026-09-19):** The historical
FR-04 PASS remains valid evidence for its named owned-cleanup candidate; it is not erased
or retroactively relabelled. Current `ProcessGroup.gone?/1` can nevertheless report a
live process dead when its argv contains `defunct`. Before this primitive is reused for
new quiescence or retry guarantees, replace command-substring inference with actual
process-state and bound identity evidence. Regression acceptance must cover a live argv
marker, a real zombie, an absent process, a recycled identity, observation failure as
unknown rather than absence, and the `Checks.Runner` cancellation caller. FR-04 owns the
bounded predicate/caller correction; FR-10 still owns descendant, issuer and delivery-
channel quiescence and all durable reconciliation. This correction changes no backend
activation permission.

### FR-05 — Contain acceptance and mutable-source activation bypasses

**Outcome:** Unverified submissions cannot be promoted, and editing source cannot
activate a new Foundry runtime.

**Scope:** Reject incomplete artifact identities rather than synthesize current ones;
remove synthetic review and permissive production Git-check bypasses. Prevent the
existing memory-only integration path from reporting successful acceptance. Disable
raw-source watcher activation until FR-17 supplies the accepted-build protocol. Make
these temporary restrictions visible in commands and docs with restoration ticket IDs.

**Acceptance:** Stale/incomplete artifacts and auto-approve requests fail explicitly;
missing Git evidence cannot advance accepted state; editing a watched source file
cannot rebuild/restart the runtime. Read-only inspection remains usable. Tests prove
restrictions through real public command paths, not only validator calls.

**Excludes:** Complete evidence validation, real integration and safe autonomous
activation: FR-13, FR-14 and FR-17 restore these capabilities.

### FR-06 — Decide durable workflow and authority contracts

**Outcome:** Versioned design notes settle the interfaces needed by downstream tickets.

**Scope:** Specify entity IDs, command/event/result schemas, legal transitions,
idempotency, commit/ack boundaries, unknown outcomes, budget ownership and deterministic
replay. Define operator policy provenance and the enforcement boundary outside candidate
control. Explicitly address agents running as the operator's OS user: repository
conventions alone cannot protect governing files or an unrestricted RPC channel.

Run a small storage conformance spike comparing a transactional local store with a
repaired journal against the audit's required failure cases. Select the smallest
adequate option; event sourcing does not require JSONL. Define schema migration and
rollback compatibility. Record the evidence and tradeoffs; do not build both backends.

**Acceptance:** Transition table includes rejection, blocking, corrections, exhaustion,
cancel/drain and PM proposals. Effect protocol identifies each ambiguous crash boundary.
Storage decision records tested and untested failure cases. Authority design states
what a candidate can and cannot mutate and how enforcement is achieved. Downstream
interface changes are reflected in this plan. Focused independent design review finds
no unresolved contradiction in these contracts before FR-07 starts.

**Decision/evidence — 2026-09-12:** [Workflow contract](WORKFLOW-CONTRACT.md) selects
SQLite WAL with checked transactional decisions/projections/intents, one pure kernel,
fresh-attempt corrections, explicit unknown effects, fast-forward exact-candidate
integration, and a protected controller outside candidate execution authority. The
[storage experiment](fr-06/storage_spike.py) and [results](fr-06/storage-results.json)
record observed crash/deduplication/writer/capacity cases and untested durability limits.
No runtime implementation or provider invocation occurred.

**Independent review — 2026-09-12, v1 (historical):**
[FR-06 design review](FR-06-DESIGN-REVIEW.md) recorded verdict **not ready**, R1–R5.
The original manifest matched before the documented plan-status edits. The review and
its reviewed hashes remain unchanged; the current manifest now identifies revision v2.

**Revision v2 — 2026-09-12:** [Response and dispositions](fr-06/review-response-v2.md)
revises claim/issue ordering, isolated authentication, autonomous kernel activation,
legal lifecycle/cleanup and conserved budget generations. It also settles encoding,
revision read sets, lost-reply lookup order, projection authority and routing. The agreed
product/authority contract above is unchanged. Protocol arguments are design evidence;
OS/OMP/fault/activation proof remains in implementation acceptance. R1–R5 are addressed
for independent re-review, not certified closed. FR-07 stays blocked. Verify the current
[manifest](fr-06/manifest.json) and [verification record](fr-06/verification.md).

**Independent v2 re-review — 2026-09-12:** [Review v2](FR-06-DESIGN-REVIEW-V2.md)
verified the supplied manifest digest and all 13 input hashes. Verdict: **ready after
specified corrections**. R1/R2/R3/R5 are resolved at design level; R4a remains: map
proved developer/reviewer launch non-start into explicit domain retry/block/attempt
transitions, distinct from capacity denial, crash/timeout and unknown start. Preserve
review candidates and role accounting, and add the corresponding acceptance traces.
Check that focused correction and refreshed input hashes before opening the design gate.
FR-07 remains blocked on R4a and FR-03; implementation acceptance is still deferred.
The v2 manifest is retained unchanged; this status edit intentionally changes this
file's hash. Neither the proposal nor historical review was silently repaired.

**Revision v3 — R4a correction proposed, 2026-09-12:**
[Response v3](fr-06/review-response-v3.md) adds only launch-non-start domain recovery.
Developer non-start retains its active attempt for bounded retry; reviewer non-start
retains the frozen candidate and reviewer ownership. Pre-intent waiting, proved non-start
and unknown possible start have separate outcomes. Retries require the R1 predecessor and
quiescence proof, one-time R5 settlement and a finite infrastructure allowance independent
of refunded process-start units. PM and other launch roles follow the same rule, with
pause/drain/cancel/generation/restart behavior explicit. R1/R2/R3/R5 are unchanged.
FR-07 remains blocked pending focused independent verification and FR-03.

**Focused independent verification — 2026-09-12:**
[R4a review](fr-06/r4a-focused-review.md) verified the revision-3 manifest digest
`27e8315697ad84db96dfbcf985f2055014b3065c91561c5c6cba7067d307dd38`
and every entry, then returned **PASS**. R4a is resolved at design level without
reopening R1/R2/R3/R5. Review SHA-256:
`51b40e94e097ceb9de581901ca7187d1ace8593907718f924b6a0d910861f32f`.
This closes FR-06's design gate, not any implementation finding. FR-07 remains
blocked on FR-03.

**Excludes:** Multi-user services, generic adapters, implementation of the full kernel.

### FR-07 — Implement durable store and compatibility boundary

**Status (2026-09-19): Complete, independently reviewed and locally integrated; not
deployed.** Exact v9 candidate `8d7223b79cb237d3406f156c7d1a06a8bcb48d81`
received an independent Astra-high [PASS](fr-07/review-v9.md). All 56 manifest hashes,
92 focused tests and the bounded carrier/closure/full-row recovery probes passed. The
reviewed source and evidence were integrated at
`c4816b2e1ef5ae41943c98591246851b2672561f`, then combined with current GitHub
`origin/main` `4c91bf7ef917e67c73574eb0246d8d57cc28806d`; no reviewed durable-store
source, test or dependency file changed upstream. Pinned combined-tree compilation,
92 focused tests and the 546-test full suite passed. This closes FR-07 only. FR-08,
FR-19, activation and FR-22 lifecycle acceptance remain open. The alignment audit
preserves this completion but shows that the old full FR-07→FR-08 gate cannot be
satisfied honestly by a thin adapter: several required lifecycle primitives are
deliberately outside accepted FR-07. H0 now inventories and revision-binds what the
accepted public boundary supports and reports unavailable capabilities without
manufacturing a pass. FR-08A supplies the missing protected primitives and owns the
substantive full handoff proof before FR-08B.

**Outcome:** Accepted decisions and effect intents are durable; corrupt authority cannot
silently become an empty workflow.

**Scope:** Implement the [FR-06 contract](WORKFLOW-CONTRACT.md): SQLite WAL/FULL via a
pinned in-process Elixir binding, separate command/event/projection/intent tables,
writer integration, checked commits,
version validation and explicit recovery mode. Provide an offline import of current
history that preserves originals, reports invalid records and cannot silently drop
acknowledged work. Keep diagnostics separate from authoritative history.

**Acceptance:** Crash before/after commit and before reply; retry the same command;
inject write/full-disk errors, torn input and unknown versions; import history larger
than the current reader limit. Assert the documented durable outcome and fail-closed
behavior. Prove transactional state/event/intent consistency and migration rerun safety.

**V2 review acceptance refinement:** Implement the protected SQLite write gateway separately from the isolated, updatable
kernel. Prove atomic command/event/projection/claim/ledger rows, foreign-key and uniqueness
failures; no candidate SQL access. Retain every untested storage case from review v1,
including real binding/write/sync/import faults, not only the one-row spike.

**Excludes:** Optimizing log retention; FR-19 handles measured operational limits.

### H0 — Honest accepted-FR-07 boundary inventory/report

**Outcome:** A reproducible report binds the accepted v9 store revision to its public API,
adapter/probe revision, source/tree/API identity, fixtures, commands and artifact hashes,
and names every supported, failed and unavailable handoff capability.

**Scope:** Exercise only accepted public FR-07 interfaces. Preserve the current seven-
capability gate's fail-closed behavior and retained failure details. Empty protected tables
are not positive lifecycle evidence. H0 may run and remain blocked before FR-08A; that is
an honest boundary result, not an FR-07 regression or permission to invent capabilities.

**Acceptance:** Reproduce supported positive and hostile cases against the accepted
revision, bind every result to exact evidence, and report receipts/leases, evolving
policy/control revisions, authenticated inbox sequence/seal facts, claim issuance and
ledger evolution as unavailable where the accepted API cannot perform them. No direct
SQL, private-table mutation, generic JSON/table-name inference or synthetic passing
provider is allowed.

**Sequencing disposition:** This replaces the old impossible requirement that all seven
capabilities pass before *any* FR-08 work starts. H0 must complete honestly before FR-08A;
FR-08A must then implement and independently prove the missing protected boundary and
pass the substantive revision-bound full gate before FR-08B begins. Original acceptance
is deferred to the correct owner, not weakened.

### FR-08A — Complete protected primitives and full handoff proof

**Outcome:** The accepted foundation gains the protected public operations required for
real workflow authority, and the full handoff gate passes with meaningful positive and
negative evidence against the newly reviewed revision.

**Scope:** Implement versioned public APIs and schema evolution for authenticated inbox
sequence/seal, evolving policy/control/allocation read-set CAS, claim issue/settlement,
receipts, leases, ledger generations/reservations and root-derived protected facts.
Distinguish fixed verifier predicates from the autonomously updatable domain reducer.
Use the same protected gateway; do not expose SQL or add a competing authority store.

**Acceptance:** Preserve H0 provenance and add positive transactions plus hostile
proposals, changing complete read sets, sealed result-versus-exit ordering, atomic
receipt/claim/lease settlement, durable rejection and same-ID recovery. R5 proves
parent-funded allocation, holds, consumption, proved refunds, closed generations and
late/conflicting receipts without implicit credit. Reject an always-refusing
implementation as insufficient. A first critical independent review is Astra-high.

**Completion — 2026-09-20:** After multiple adversarial review/correction cycles, the
protected implementation supplies authenticated inbox sequencing/sealing, complete
read-set CAS, policy/control and assignment binding, epoch-safe claims, request/receipt
provenance, leases, conserved generation/reservation ledgers, recursive close/reset,
typed transition replay and fail-closed migration/recovery. The final branch correction
`f9e35b42d2eb768f4407543ac0f84e2758409ab4` received focused independent PASS
`5851c9be9b6d0cfb7f3fad5d41e06fa139b852bd`.

Because FR-19A had independently evolved the same Gateway, completion binds the actual
combined tree: merge `1d0b128ff7c78bf72577d23658e267d7508e4763`, integration tests
`240d16f6823a8b9118c4d2b52d305314c6a97203`, revision-bound evidence
`b05f8342fbb83cb26a0fa157472bee15a020ad7e`, frozen candidate
`176dab44354b5bbdde5b488f44766849c9d8927d` and Astra-high PASS
`a22753569254ca42773f04632ca42a72573c9a2e`. The combined gate reports 7/7 ready;
clean CI passed 612 tests with 13 intentional skips and one optional exclusion. H0's
accepted-v9 4/3 artifact remains immutable historical evidence while the evolved live
implementation correctly refuses to impersonate it. This closes FR-08A only: FR-08B
still owns every-ingress reducer migration, FR-15aB actual isolation, FR-18 presentation,
FR-17 activation and FR-22 lifecycle acceptance. No provider, daemon or deployment ran.

### FR-08B — Unify all command transitions and replay

**Outcome:** One deterministic transition contract produces equivalent live and
reconstructed state.

**Scope:** Inventory and route **every** mutation ingress through the kernel/store,
including CLI/public RPC, Coordinator/State/Tick, PM, scheduling, agent callbacks,
correction, cleanup and recovery, plus steering controls, PM proposals, reviews, budgets
and resets. Distinguish commands, persisted decisions
and projections. Remove parallel mutation paths; use recorded time rather than replay
wall-clock time. Model blocked/partial/rejected outcomes explicitly or reject them
consistently at admission with documented alternatives.

**Acceptance:** Table-driven sequences cover every supported command/verdict and compare
live state with reconstruction. Pause/stop and all PM proposals survive restart;
exhausted retries stay exhausted; completion cannot overwrite accepted review state;
duplicate commands are idempotent. The public block command reaches its intended state.

**V2 review acceptance refinement:** Implement v2 canonical encoding/read-set CAS, same-ID lookup before current revision
checks, and explicit clock/ID inputs. Persist root controls, claim predicates and R5
ledgers as the early interface for FR-15a, independently of PM. Table-driven tests must
cover all R4 source-state guards, sealed result-versus-exit ordering, terminal dispositions
and all R5 transfers/settlements/reset generations. A kernel cannot forge protected facts
by changing a domain projection; live/replay equivalence applies to both authoritative
facts and the domain reducer. Test multi-ticket allocation and no implicit refill.

**R4a acceptance trace:** Table-test each role from its exact scheduling phase through
pre-intent capacity/eligibility denial, proved launch non-start and unknown possible start.
Assert developer non-start retains one active attempt and returns the ticket to queued;
reviewer non-start returns the same frozen candidate to awaiting_review; PM retains its
planning owner. Restart after atomic non-start settlement but before redispatch must
reconstruct one owner, one infrastructure ordinal, no live execution and no replay of the
settled launch. Pause/drain/cancel/exhaustion and generation changes reproduce the v3 rows.

**Excludes:** Running external effects inside the reducer. FR-08A's protected verifier is
not a second domain reducer, and legacy JSONL may remain only as checked import/export or
diagnostic compatibility after it ceases deciding live workflow truth.

### FR-09 — Prove OMP execution and presentation contract

**Outcome:** A narrow execution interface has measured capabilities and honest limits.

**Scope:** Conform to the FR-06 identity/effect contract under FR-15a isolation. Define
start, observe, prompt, interrupt, reconcile and close operations with
execution/session identity. Put Herdr attach/inspect/close behind presentation operations.
Exercise installed OMP structured modes, session persistence and quota observations.
Keep Herdr as the initial backend; do not replace it speculatively.

**2026-09-19 harness-selection note:** Before spending substantial implementation effort
on OMP-specific FR-09 conformance, run the bounded substitution evaluation described in
[STRATEGY](STRATEGY.md#pi-explicit-session-contracts-and-replaceable-execution), with
pinned Pi RPC as the preferred first replacement candidate. Compare the same
start/observe/prompt/interrupt/reconcile/close semantics, usage observability, failure
reconciliation, extension/tool isolation, subscription-route enforceability and
maintenance burden. This note changes evaluation order, not authority: the current
OMP-specific FR-06 contract remains governing and automatic execution remains blocked.
If Pi is selected, explicitly revise and independently re-review the affected FR-06/FR-09
contract text before production adoption; do not silently substitute a harness.

**Acceptance:** A bounded allowed-subscription execution produces a result without a
pane where supported; disconnect/reconnect, cancellation and exit observation have
recorded outcomes. Pane closure alone cannot assert ticket completion. Unsupported
capabilities produce a documented explicit outcome, not an invented liveness signal.
Record exact executable versions and observed usage/entitlement signal limitations.

**V2 review acceptance refinement:** Prove the installed OMP harness can use the credential gateway and remote isolated
tool bridge with candidate plugin/startup-code loading disabled. Reusable auth must never
reach arbitrary tool execution. Test a second harness/direct request/profile override
from the same slot, forged request identity, proxy/credential access and unauthorized
extra model calls; they fail or traverse new authorized reservations. Verify hidden
backend retries cannot evade per-request accounting. If unsupported, report execution
blocked with the required adapter change; do not copy credentials or replace OMP silently.

**Excludes:** Model ranking, generic multi-provider plugin infrastructure.

### FR-10 — Persist owned effects and reconcile executions

**Outcome:** Restart reconciles prior work before deciding whether another launch is safe.

**Scope:** Persist effect IDs/intents/receipts and separate developer, reviewer and PM
execution IDs under attempts. Wire checked launch/prompt/process operations into actual
orchestration. Monitor execution workers and reconnect or terminate verified ownership
after Coordinator loss. Define explicit unknown outcomes where backend idempotency is
unavailable; do not promise exactly-once external execution.

**Acceptance:** Restart between intent, launch, receipt and completion; hard-kill a worker
and Coordinator separately; deliver late/duplicate messages from old attempts. Assert
no blind relaunch, no stale transition, recovery of reviewer work and explicit uncertain
states. The runtime registry rebuilds from durable identities rather than pane guesses.

**V2 review acceptance refinement:** Implement pending/claimed/issued/unknown/terminal states under the protected gateway.
Inject claim→cancel→issue, issue→cancel→external action, duplicate delivery and old-writer
takeover. Assert exact outstanding claim IDs, no second delivery and no retry from an old
ref/missing process alone. Include non-session effects in reconciliation, issuer/channel
quiescence proof and late receipts settling only their original reservations. R1's issued
boundary is authorization for one operation, not an assertion that it has finished.

**R4a acceptance trace:** Prove launch non-start only after the named issuer/delivery
channel is quiescent. Atomically close the execution, settle its one reservation and emit
the role-specific domain transition. Duplicate and late receipts must neither release
twice nor advance the infrastructure ordinal twice. An unknown possible start retains
holds/leases and cannot be replaced. A new launch effect must reference the terminal
predecessor; restart between settlement and new claim cannot redispatch the old effect.

**Excludes:** Scheduler prioritization and deployment effects.

### FR-11 — Close correction, timeout and review lifecycles

**Outcome:** Every attempt has one explainable terminal disposition and bounded retries.

**Scope:** Separate timeout from successful completion, cancel/invalidate old timers,
use the FR-06 fresh-attempt correction strategy (close/reconcile old execution before
new launch; no simultaneous re-prompt), and make CLI and automatic review use the same
transition/cleanup path. Persist developer/reviewer retry budgets separately as designed.
Release execution capacity while awaiting review without losing resumable session state.

**Acceptance:** One correction cannot both re-prompt and relaunch the developer;
old deadlines cannot end a newer execution; reviewer crashes consume the intended budget;
blocked and exhausted work remain correctly classified across restart. Check all owned
executions and panes after success, reject, cancel, timeout and failed reviewer launch.

**V2 review acceptance refinement:** Test valid frozen result then abnormal exit, exit with a prior durable inbox result,
missing/incomplete stream, successful developer close before capacity-one review, and
reviewer-result cleanup through CLI and automatic paths. Test check assertion versus
infrastructure failure/timeout, malformed validation exhaustion, and cancellation after
an attempt already has a terminal disposition. No exit or timer can overwrite a valid
result. Retries obey role reservations, closed generations and exact-once settlement.

**R4a acceptance trace:** A proved developer non-start closes only that execution and
retains the same nonterminal attempt until bounded infrastructure exhaustion or budget
exhaustion; no crash/timeout/result is synthesized. A proved reviewer non-start preserves
candidate, checks and reviewer ownership and never enters developer retry. Exercise below-
limit retry, infrastructure block, explicit resumption, developer budget exhaustion and
reviewer budget block/exhaustion, including restart and stale receipts from the failed
launch. Process-start units are refunded only on proof and are not charged to bound the
separate durable infrastructure allowance.

**Excludes:** Evidence acceptance itself, delivered by FR-13.

### FR-12 — Wire admission, resource scheduling and review capacity

**Outcome:** The actual launch path enforces policy, specification requirements,
dependencies, resource conflicts and bounded capacity while allowing reviews to progress.

**Scope:** Route Tick through the real scheduler and common admission; validate usable
checkout/base/spec references and environment propagation. Reserve or otherwise guarantee
review progress under developer saturation. Scheduling denial is not an execution retry.

**Acceptance:** Exercise competing tickets, unresolved dependencies, resource conflicts,
priority changes, unusable checkouts and full worker capacity through live orchestration
with a fake execution backend. No denied work launches or burns attempt budget. A queued
review progresses under the configured maximum concurrency. Agent launch receives the
admitted environment and assignment, with secrets omitted from diagnostic output.

**V2 review acceptance refinement:** Schedule mandatory check/build workers as well as model roles. Test capacity one:
developer close→checks close→review close. Under drain, correction/rebase becomes blocked
queued work and stop may complete after issued claims/cleanup settle; unknown work blocks
stop visibly. PM decomposition transfers existing objective allocations to tickets;
capacity/dependency/profile denial neither reserves nor consumes a start unit.

**R4a acceptance trace:** Pre-intent capacity/resource/profile/eligibility denial stays
in the current scheduling phase, creates no execution/claim/reservation and does not
increment launch infrastructure attempts. After proved non-start, schedule only a new
effect referencing the predecessor and only when current policy, controls, resource
revalidation, budget generation and finite role allowance permit. Under pause, retain but
do not issue; under drain, block developer/PM retries while reviewer/check/finalization
retries remain eligible; cancel never retries. Verify released checkout resources are
reacquired/revalidated and immutable reviewer candidate custody is retained.

**Excludes:** Dynamic profile switching and PM-generated specifications.

### FR-13 — Verify artifacts, candidate scope and check receipts

**Outcome:** An independent review and required checks approve an exact attributable
candidate, with controller-verified scope and ancestry.

**Scope:** Carry explicit ticket/attempt/execution/base/spec/policy identity end to end.
Validate real Git ancestry and diff against admitted scope. Run required checks in an
owned worker and store controller-generated receipts bound to tree, command, environment
and result. Reviewer execution identity cannot be substituted with the developer's.

**Acceptance:** Actual wrapper-to-controller tests reject stale artifacts, wrong role,
nonexistent checkout, unrelated one-commit history, hidden out-of-scope changes, altered
candidate after review, and fabricated check assertions. A legitimate real candidate
and independent review pass. Empty checks are allowed only if governing policy explicitly
permits them, not because a field was missing.

**V2 review acceptance refinement:** Prove freezing/import uses controller-custodied immutable objects despite concurrent
untrusted writer changes; forbid candidate hooks/paths from executing in the root. Gate
receipts and accepted facts cannot be forged through kernel domain events. Cover all
v2 blocked/partial/invalid/check-result transitions at actual submission boundaries.

**Excludes:** Updating the accepted Git ref; FR-14 owns integration.

### FR-14 — Perform serialized recoverable Git integration

**Outcome:** Acceptance corresponds to an actual verified Git tree/ref transition.

**Scope:** Use durable integration intents and owned asynchronous workers. Apply
FR-06's fast-forward-only accepted-ref compare-and-swap. A moved base requires a fresh
rebase attempt, renewed checks and independent exact-candidate review; no unreviewed
merge tree. The protected controller owns the accepted repository. Reconcile interrupted ref updates; serialize competing integrations. Keep pause,
cancel and status responsive while Git/check commands are running.

**Acceptance:** Real Git tests cover successful integration, conflict, changed base,
failed checks, stale review, concurrent acceptance and crash before/after ref update.
Assert both durable records and actual refs/trees. No nonexistent SHA advances state;
an interrupted effect cannot be reported successful without checking its outcome.

**V2 review acceptance refinement:** Exercise an issued Git worker stalled before CAS while cancel or epoch takeover
commits. Cancel returns pending with that claim; settling actual ref wins over guessed
cancellation. Old ref alone cannot justify another issuer until the original process and
channel are quiescent. Non-issued cancellation prevents CAS; changed base renews checks
and review, charging the existing allocation for actual new work.

**Excludes:** Building or activating the running release.

### FR-15a — Prove protected verifier and execution isolation

**Outcome:** Candidates cannot exercise operator/controller authority or impersonate a
reviewer. This is the early infrastructure portion of FR-15, separated to avoid making
FR-09 depend on a steering loop that itself depends on execution.

#### FR-15aA — Feasibility and provisioning specification

**Scope:** Jointly with FR-09's F checkpoint, inventory every candidate-controlled
execution path: harness, shell/file/custom tools, extensions and startup code, build hooks,
language services, subprocesses, inherited environment and file descriptors, network,
IPC/process memory, Git metadata and shared writable state. Specify the actual host
topology, restricted principals, credential/auth gateway, request-reservation handshake,
slot cleanup, controlled acquisition path and provisioning steps. Evaluate pinned Pi RPC
first against the common execution contract while OMP remains governing. Start with
synthetic credentials and controlled endpoints; provider/host changes needing additional
authority stay outside this investigation.

**Acceptance:** Publish exact executable/config versions and an explicit supported or
blocked result for subscription routing, credential separation, pre-request reservation,
tool isolation, cancellation/reconciliation and one representative useful build/test
path. Name every required adapter or provisioning change. A paper design, same-user
directory convention, sandboxed shell with unsandboxed extensions, copied credentials,
direct provider calls or permissive mock cannot pass. This slice closes no production
capability and does not replace the parent acceptance below.

**Completion — 2026-09-19:** The executable provisioning specification, machine-readable
manifest, fail-closed validator and hostile controls are integrated through
`a1c66de64e7c4ec5d41a7d273bbdf54720710fef`. The final substantive candidate was
`9ed32575f2840e90fe3e1ebb1f1ebcd0bd54040b` (tree
`1c5dd96f0da66286ecb47eec029c09b2f3733802`); focused independent review passed in
`f093cbfabcd1be2b43eacf68fd42865f3d317c11`. Integrated validation passed the manifest,
22 maintained tests, independent hostile mutations, formatting and all 80 documentation
checks. The record inventories the distinct protected root, workflow kernel, auth harness,
tool/worker and role principals; exact channels, pinned inputs, executable dependencies,
network/IPC/environment boundaries, provisioning ownership and rollback. This is a
provider-free provisioning result only: no account, network, credential, daemon, Herdr or
host change was made. Actual isolation remains FR-15aB; installed-harness/subscription
conformance remains FR-09.

#### FR-15aB — Actual isolation and conformance

**Scope:** Implement the account/worker isolation and narrow local capability protocol
in [FR-06](WORKFLOW-CONTRACT.md), using FR-08A/B's completed durable gateway and ledger contracts.
Protect verifier/launcher/auth gateway/activation-root code, state, policy, accepted refs,
release store and activation credentials. Keep untrusted build/test/runtime code outside
that principal. Separate role/slot access; Herdr attachment must not inherit steering
credentials. Pin the initial operator-installed controller and immutable deny-by-default
policy. Full durable policy changes/PM remain in FR-15.

**Acceptance:** From actual isolated developer, reviewer, PM, build and runtime processes,
try controller file writes, other-role token/checkout reads and writes, general release
RPC, unauthorized policy changes and forged/replayed capability calls. Assert denial;
valid scoped submission/query works. Inspect actual listeners and crash/status redaction.
Reused execution slots cannot retain prior tokens/processes. Verify old writer epochs
cannot authorize new effects. Test accounts and resources must be explicitly owned.
If the host cannot enforce the chosen isolation, keep the affected capabilities disabled
and record the failed requirement; a same-user directory convention is not a substitute.

**V2 review acceptance refinement:** Prove the selected root/kernel/auth-harness/tool principal separation, including
same-slot reusable-auth/direct-provider bypass, network/proxy/IPC/process-memory denial,
launcher input validation and no candidate-loaded code in trusted harness/root contexts.
Use deterministic local fake provider endpoints for exhaustive denial/accounting tests;
FR-09 separately owns actual installed-harness subscription conformance. Root write gateway
must reject forged budget/acceptance events from an isolated candidate kernel. Its safety
predicates and initial policy must work without the later PM loop.

**Excludes:** Installing privileged host accounts in an ordinary ticket without necessary
operator provisioning authority; full steering/PM behavior or autonomous protected-root
upgrade. The workflow kernel is not part of that exclusion; FR-17 activates its repairs.
FR-15a completion must provide a reproducible isolated test setup and host setup procedure.

### FR-15 — Implement durable steering and optional PM planning

**Outcome:** Operator direction becomes durable policy and bounded admitted work.

**Scope:** Use the FR-15a authority boundary and FR-06 actor/commit contract for durable
pause/drain/cancel/priority/autonomy changes, and an optional PM path that creates a
versioned spec. Forward the full admitted assignment and artifact contract to the
developer. Directly admit already specified work without a redundant planning call.

**Acceptance:** Change authority mid-run and prove its effect on new actions and the
declared handling of active work, including restart. A PM/candidate cannot enable paid
fallback, weaken required gates or broaden authority through files or exposed commands.
Broad direction yields a spec and admitted ticket; a specific request skips PM; an
ambiguous proposal yields an explicit unresolved decision instead of invented authority.

**V2 review acceptance refinement:** Use existing gateway cancel/revoke/reset primitives; do not create a competing
steering transition path. Test cancellation acknowledgments naming issued work, revocation
between claim and issue, reset with old unknown reservations, and controls surviving
kernel replacement. Root grants require authenticated operator commands; PM amendments,
new tickets and profile changes cannot replenish a ledger or select weaker gates.

**Excludes:** A polished conversational UI; a working steering command boundary is
sufficient if its durable records can support the later conversation surface.

### FR-16 — Implement bounded subscription switching

**Outcome:** Quota problems switch only within explicit per-role permitted profiles,
without duplicate execution or hidden paid use.

**Scope:** Persist profile ordering, exhaustion/cooldown evidence and bounded retry
decisions under protected policy. Label quota observations with freshness/uncertainty.
Reconcile possibly running work before switching. Stop admitting affected work when
no eligible profile remains; expose the reason and an operator recovery command.

**Acceptance:** Deterministic cases cover low/unknown quota, quota rejection after
launch, all profiles exhausted, stale signals, restart and manual recovery. Verify the
chosen profile and billing path at the backend boundary; no automatic paid fallback.
Real smoke proves only the signals actually exposed by installed subscription tooling.

**V2 review acceptance refinement:** Exercise role-start plus model-request reservations through profile switching,
unknown deliveries, duplicate and late receipts, reset generations and parent/child
allocation limits. The gateway fixes billing/profile fields from the claim; available
credentials never imply permission. Unknown holds remain charged against available
capacity until reconciliation, never converted into zero usage or new-generation credit.

**Excludes:** Inventing a capability ranking before benchmarks exist.

### FR-17 — Activate immutable accepted builds and recover failures

**Outcome:** Foundry can autonomously deploy accepted code with identifiable running
builds and compatible rollback.

**Scope:** Build from accepted immutable input, record source/build/policy/schema
versions, drain or reconcile active effects, and use the real release start/stop
interfaces. Keep the activation controller and mandatory health/gate policy outside
candidate control as specified by FR-06. Define rollback when state migration prevents
loading an older executable; do not silently discard acknowledged post-upgrade work.

**Acceptance:** Activate a real isolated build and verify its loaded revision. Inject
build, stop, start, health and compatibility failures and crashes at activation boundaries.
Recover a usable compatible runtime with preserved evidence. A candidate modifying its
own health checks cannot bypass mandatory external criteria. Merge success and deployment
success remain distinguishable. Restore automatic activation only through this protocol.

**V2 review acceptance refinement:** Activate an actual kernel lifecycle/replay repair autonomously while the verifier,
policy/gates/auth root and their hashes remain fixed. Attempted root replacement or
forged acceptance/health/ledger requests from that kernel must fail. Verify every version
the new kernel can write is supported by the rollback build and root allowlist; mere
range overlap is insufficient. Test cancellation at each issued build/stop/switch/start
boundary, safe copy under concurrent writes, and rollback preserving newer acknowledged
work. Protected-root upgrades remain explicit operator maintenance, not all kernel repairs.

**Excludes:** Fleet deployment or distributed release orchestration.

### FR-18 — Make status, board and telemetry reflect real state

**Outcome:** The operator can see what runs, why it waits, and what evidence is missing.

#### FR-18A — Minimal honest observations

**Scope:** Provide the smallest canonical query/observation identity surface needed for
FR-09/15a trials and later activation: ticket/attempt/execution/effect/control identity,
source and freshness, accepted versus deployed pointers, unknown outcomes/usage and
unavailable/corrupt status distinct from empty healthy state. This slice follows FR-08A
and does not claim the legacy producer chain is repaired.

**Acceptance:** Against canonical protected facts, show supported state and explicit
unknown/unavailable/corrupt outcomes without projection-manufactured health. Bind every
observation to revision/source/quality and redact representative secrets. A source
inventory or schema declaration alone is not live/deployed truth.

#### FR-18B — Complete status and telemetry chain

**Scope:** Consume one versioned query/projection contract; fix board envelope handling
and distinguish unavailable/corrupt data from empty success. Align actual telemetry
producers with validators and consumers; correlate ticket/attempt/execution/effect IDs.
Report worker ownership, unknown outcomes, retry budgets and accepted/running revisions.
Review diagnostic redaction and local inspection exposure against FR-06's boundary.

**Acceptance:** Drive launch/correction/review/block/crash/restart events through real
producers and assert board/status/log agreement with authoritative state. Telemetry
records validate; invalid records are surfaced. Representative secret-bearing commands
are redacted. A corrupt/unreachable store cannot show a healthy empty board.

**V2 review acceptance refinement:** Show separate ticket/attempt/execution/control facts, pending cancellation claim IDs,
check/cleanup/stop blocks, old-generation holds, unknown usage and root-derived accepted/
deployed pointers. A candidate domain projection cannot manufacture healthy acceptance.

**2026-09-19 measurement refinement:** Repair the known producer/schema split before
claiming lifecycle telemetry: AgentServer's current command-shaped lifecycle records do
not satisfy the canonical command validator, while Coordinator writes a different
EventLog-style shape. Connect the selected harness to versioned LLM usage observations
correlated through ticket/attempt/execution/request and exact candidate/review outcome.
Preserve source/quality for input, cache-read/cache-write, output/reasoning/total usage,
context utilization, retries/compactions and provider-reported cost where exposed; missing
values remain unknown. Record tool duration/result size/truncation and bounded context
admission without copying raw prompt/response bodies into telemetry. Keep human
steering/review/recovery effort and subscription/infrastructure cost as separate measures.
Telemetry compaction must preserve the numeric usage aggregates and provenance required to
compare like task classes over time. Acceptance tests cover failed/retried/corrected work
as well as successful final runs and demonstrate that a cheaper token path cannot hide
worse review, acceptance or operator-effort outcomes.

**OpenTelemetry convergence:** [the observability route](OBSERVABILITY.md) stages this
work across seven steps. Steps 2 through 5 are FR-18B's; step 1 is split, with FR-18A
owning the identity, source/quality and unknown vocabulary and FR-18B reconciling the
telemetry schemas to it; steps 6 and 7 have no owner recorded and must be assigned before
either is started. Export is **step 5 of 7**, gated on steps 1 through 4, and steps 6 and
7 follow it.

**The four JSONL surfaces need named owners.** The observability route documents
fragmentation across `coordinator.jsonl`, `telemetry.jsonl`, `events.jsonl` and
`findings.jsonl`. Assigning them so none is retired by assumption:

- `coordinator.jsonl` is **FR-18B's**. It is a free-form diagnostic log, and the
  measurement refinement above already names its producer — "Coordinator writes a
  different EventLog-style shape" — as part of the split FR-18B must repair. FR-08B routes
  Coordinator *mutation ingress* through the kernel, which governs whether Coordinator
  decisions become commands, not what it writes as diagnostics.
- `telemetry.jsonl` is **FR-18B's for its producers**, and **FR-19B's for retention,
  rotation and bounded query behavior**. Neither supersedes the other.
- `events.jsonl` is **FR-08B's** for when it stops deciding live workflow truth, after
  which FR-08B's exclusion permits it only as checked import/export or diagnostic
  compatibility. **FR-23** then sweeps the remaining module references, which its scope
  already enumerates.
- `findings.jsonl` is **FR-20's**, whose scope requires persisting finding, proposal and
  admission outcomes separately. The metrics snapshots the route says this file also
  carries belong to route step 6, which has no recorded owner.

These are cross-ticket assignments recorded inside one ticket's section, which is the
one-side-knows drift this clause exists to prevent. Each named ticket should carry a
pointer back here, or the table should move somewhere neutral, before any of them starts.

**The correlation model is already required; the route extends it as direction, not
obligation.** The measurement refinement above already requires correlation "through
ticket/attempt/execution/request and exact candidate/review outcome", and that tail is
what makes the economics claim checkable: showing a cheaper token path cannot hide worse
review or acceptance outcomes needs cost tied to the accepted outcome, which a chain
ending at the effect cannot express. **That refinement text is the acceptance chain.** The
route additionally proposes an `objective_id` at the head, which appears in no ticket; the
envelope should be able to carry it, but it is design direction and not an acceptance
obligation. Acceptance text must be exact enough to test, so no clause here widens the
chain open-endedly.

**Trace and metric roles are separated by cardinality.** Identities that are unique per
unit of work — request, tool call, effect, candidate, review — belong on traces, where
high cardinality is expected. Metrics carry bounded dimensions only: role, phase, outcome
class, provider, model. Putting a per-request identity on a metric label makes the metric
series unbounded, which is how a telemetry system becomes too expensive to keep and then
gets turned off. This is a design constraint on the envelope, not an export detail, so it
is recorded here rather than left to step 5.

**Extensibility is the reason for the seam, not a side effect.** One canonical envelope
emitted once through `:telemetry`, with durable analytics, traces/metrics and the board
and Improver as independent consumers, means a new consumer is added without touching
producers and a new producer is added without touching consumers. A chain in which one
consumer's format becomes the next one's contract has the opposite property. Any change
that makes a consumer's schema load-bearing for another consumer contradicts this and
should be refused.

**Export is routed to FR-18B but is not an FR-18B acceptance obligation.** Exporters are
optional sinks, never a new source of truth, so FR-18B may close without export having
been done. If export is ever required, it becomes a distinct deliverable with its own
pinned semantic-convention acceptance and needs its own ticket rather than an extension of
this one. Recording the routing without this sentence would leave it ambiguous whether
FR-18B had silently acquired an obligation its acceptance paragraph never states.

Exporting a telemetry model before its semantics are repaired only publishes the wrong
model in a portable format, so no flag-day logging rewrite is acceptable.

**Excludes:** Building a new dashboard framework.

### FR-19 — Bound storage and make offline maintenance safe

**Outcome:** Diagnostic growth and maintenance failures cannot erase authoritative work.

#### FR-19A — Operational storage, backup and recovery baseline

**Status (2026-09-19): Candidate implementation prepared; independent review pending.**
The bounded implementation adds capacity/last-sequence health, limited event diagnostics,
serialized content-checked WAL checkpointing, offline owner-locked backup replay
verification and fail-closed relocation mutation containment. It preserves prior claim and
ledger rows through backup, checkpoint and deterministic process-interruption probes. The
host could not safely provide physical filesystem ENOSPC, power-loss, kernel `fsync(2)` or
media-flush evidence; SQLite logical-full, kernel file-size-limit and injected VFS `xSync`
evidence retain their exact narrower attribution. FR-19B diagnostic retention/compaction
and cross-device relocation remain open.

**Scope:** After FR-07, establish bounded operational queries/capacity health, verified
SQLite backup/replay and explicit offline maintenance containment. Exercise physical
ENOSPC/sync/WAL/checkpoint/corruption cases that FR-07 explicitly deferred. Disable unsafe
relocation paths clearly until FR-19B repairs or retires them. Preserve original authority
and old claim/ledger evidence on every failure.

**Acceptance:** Verify backup content and replay, not row count; cover interrupted
checkpoint/backup, full disk and corrupt SQLite with originals retained and effects fenced.
Record measured limits and unsupported physical guarantees. This baseline is required by
FR-17 but does not close the parent's diagnostic-retention or cross-device obligations.

**Completion — 2026-09-19:** Final implementation
`6c1e5acb29b10e0cd40c692de87f05f1155804c8` and frozen candidate
`8cfd983b40e5ad6edce4e863ee64906960220f92` received focused independent PASS
`95eccd6b160b6f339376cfd79e7de81f997c4ba6` after the earlier Astra-high blocker
reviews. The accepted evidence covers bounded/unknown capacity health, owner-death-safe
probe cleanup, verified backup/replay, genuine nonempty-WAL checkpoint and VACUUM
interruption, corrupt input, an owned Darwin filesystem reaching physical ENOSPC, and a
Linux device-mapper run where the unchanged Gateway backup path received kernel
`fsync EIO`, fenced, restored the same device, remounted ordinarily, verified complete
content/replay/source authority and removed every owned resource. Integration is through
`efd8e89967ad90e7ea30dddd08864de5afadd4d1`; clean-checkout pinned CI passed 590
tests with 13 intentional skips and one optional exclusion. This does not prove power-loss,
failed-sync persistence, controller/cache flush or media durability. FR-19B still owns
diagnostic retention and offline relocation closure; FR-17/22 own activation/lifecycle.

#### FR-19B — Diagnostic retention and offline relocation

**Scope:** Add measured retention/rotation and bounded query behavior for diagnostic
logs. Apply FR-07's snapshot/compaction protocol where needed. Repair or retire relocation
commands explicitly: validate paths, space and digests, check journals and avoid dynamic
atoms; cross-device moves verify the destination before source removal. Preserve evidence
when maintenance fails.

**Acceptance:** Exercise large logs, malformed diagnostic records, interrupted rotation,
compaction and migration, full disk and cross-device copy failures. Verify acknowledged
state, originals and unrelated paths survive. Record measured data sizes, resource costs
and limits; make no unmeasured performance claim. Disabled historical tools must fail
clearly and have a documented supported replacement where required.

**V2 review acceptance refinement:** Retain full filesystem ENOSPC/sync/WAL/checkpoint/compaction and SQLite corruption
recovery obligations; verify backup content and replay, not just row count. Old ledger
and claim evidence must survive retention and offline maintenance. The small comparison
is not completion of the full storage failure-conformance set.

**Excludes:** Retaining unsafe Python compatibility just for historical parity.

### FR-20 — Reconnect constrained improvement proposals

**Outcome:** Operational findings can yield attributable, deduplicated improvement
work through the same admission and acceptance gates as other changes.

**Scope:** Align classifiers with emitted schemas and actual states; persist finding,
proposal and admission outcomes separately. Replace fixed ticket IDs and stale paths;
do not suppress a finding merely because proposal generation/admission failed. Route
repair work through current specs, checkout allocation and policy. Complete autonomous
integration/activation uses FR-14/FR-17, never a privileged shortcut.

**Acceptance:** Real emitted failures produce appropriate proposals without crashing;
legitimate states do not trigger known false classifications. Failed admission retries
within budget; restart neither loses pending work nor duplicates admitted repairs.
Completed repair tickets remain complete. An improvement cannot broaden governing policy.

**V2 review acceptance refinement:** Include ordinary kernel defects in the repair path. Generate a scoped proposal,
consume existing allocation, independently review and autonomously activate via FR-17;
no root privilege shortcut or operator-only kernel exclusion. Proposal plumbing may be
implemented before FR-17, but kernel repair activation is not complete until FR-17 passes.

**2026-09-19 efficiency refinement:** After FR-18 provides trustworthy usage and outcome
correlation, improvement proposals may compare context, model/reasoning and tool policies
on comparable task classes. They must include failed/retried/corrected work, review
quality and operator effort rather than optimize raw token count or provider cost alone.
Unknown usage yields insufficient evidence, not a zero-cost win. Every optimization still
needs a baseline, fixed acceptance gates, bounded experiment and ordinary admission/review/
activation; telemetry cannot weaken authority or auto-promote its own recommendation.

**Excludes:** Open-ended recurring PM calls or self-generating management hierarchies.

### FR-21 — Establish independent Foundry CI and build provenance

**Outcome:** Foundry checks run independently of the corpus stack and test artifacts
have identifiable source/dependency inputs.

**Scope:** Add a Foundry CI job with fresh isolated state/TMPDIR, explicit exclusions
and appropriate compile/format checks. Resolve tracked deps/escript provenance with an
explicit build/vendoring policy. Replace vacuous lifecycle tests with meaningful assertions
as repaired paths become available. Date or retire absent Python parity claims/tools.
Handle existing formatting debt separately from functional changes.

**Acceptance:** Reproduce the job locally from a clean checkout without corpus services;
run it twice without stale temporary-path collisions. Build provenance identifies inputs.
No CI test closes foreign panes or launches paid agents; real-provider tests are explicit,
bounded and separately reported. Publish excluded coverage rather than implying it ran.

**Excludes:** Waiting for the whole repair before adding CI; extend this job in each
subsequent ticket as new lifecycle tests land.

### FR-23 — Retire legacy surfaces, decompose god modules and restore code hygiene

**Outcome:** The repaired system is left in a state a maintainer can safely change, with
no dead vocabulary, no module too large to review as a unit, and no legacy surface still
implying it decides live truth.

**Scope:** One exhaustive, evidence-backed sweep in three separable parts.

*Dead surface removal.* Remove or explicitly retire identifiers that no longer dispatch.
Evidence gathered 2026-09-20 at `9dd30c3`: `RecordCodec`'s `@command_types` contains
`reset`, `propose`, `submit_artifact` and `submit_review`, each with zero uses anywhere in
`lib/` outside the list literal itself. Twenty distinct `legacy_*` identifiers and six
modules referencing `events.jsonl`/`EventLog` remain. Each is either genuinely required
compatibility, and says so, or is removed.

*Module decomposition.* Evidence at `9dd30c3`: twelve modules exceed 800 lines and
`protected_primitives.ex` is 7,547 — roughly a fifth of the whole `lib/` tree in one file,
and the single most contended file in the repair, which serialised FR-18A against the
FR-08A binding correction purely by file granularity rather than by any logical dependency.

*Documentation retirement.* The repair produced a large body of dated records, and the
distinction between the ones that must survive and the ones that should go is not
obvious. Apply this rule rather than judgement:

- **Preserve, always.** Dated audits, independent reviews, candidate records, verdicts and
  attestation artifacts. These are evidence of what was checked against which revision,
  and the repository's existing convention is explicit that they are kept as dated
  evidence rather than rewritten into one current narrative. A superseded candidate's
  review is still true about that candidate. Retiring it destroys the only record that a
  claim was independently checked.
- **Retire.** Design material whose mechanism was replaced and whose replacement is
  itself recorded; documents describing code that no longer exists; migration-era material
  that no longer describes anything, once FR-08B has retired legacy JSONL from deciding
  live workflow truth; and routes pointing at either.
- **Neither delete nor leave silently stale.** A superseded design that explains *why* an
  approach failed is worth keeping when the failure is instructive, but it must say so at
  the top and name what replaced it. The event-vocabulary design is the worked example:
  its first mechanism was unimplementable, and revision 2 keeps that account deliberately
  rather than deleting it, because the mistake is the useful part.

Deciding rule: **evidence of a check is preserved; description of a mechanism is retired
when the mechanism is gone.** When the two are in one file, split it rather than choosing.

*General hygiene.* Formatter baseline debt, accumulated worktrees and branches, and
documentation routes left pointing at superseded evidence. Branch and worktree state is
mechanical — see the implementation log's note on archive tags — so prefer enumerating it
from Git over maintaining a list.

**Sequencing, and why it is not literally last:** this ticket must land **before** FR-22,
not after it. FR-22 is whole-lifecycle acceptance bound to exact revisions. A sweep
performed after FR-22 would invalidate that acceptance wholesale. This is demonstrated,
not predicted: on 2026-09-20 adding a single function to `protected_primitives.ex` changed
its source SHA-256 and loaded BEAM MD5, broke the frozen FR-08A attestation and reported
`ready=false` until the evidence was rebound. A decomposition changes every pinned
identity at once. FR-22 therefore depends on FR-23.

**Acceptance:** Each part is behavior-preserving and demonstrated so: the full model-free
suite passes before and after with no test deleted or weakened to accommodate a move, and
every revision-bound attestation is rebound in the same commit that changes its subject,
never in a follow-up. Decomposition preserves public interfaces or migrates every caller
in the same change, using the [dependency review runbook](../../docs/agents/DEPENDENCY_REVIEW.md).
Removal of any identifier is justified by a recorded search showing no dispatch, not by
inspection alone. Documentation routes and the catalog resolve after the sweep.

**Excludes:** Behavioral change of any kind, including "obvious" fixes found while moving
code. A defect found during the sweep is recorded and routed to its owning ticket, never
repaired inside a refactoring commit. This ticket does not relitigate settled design,
rename durable record fields, change any persisted format, or alter policy.

**Ownership boundaries:** FR-08B owns legacy JSONL's retirement from deciding live workflow
truth; FR-19B owns offline relocation's repair or retirement. FR-23 covers what those leave
behind and must not duplicate or pre-empt them.

### FR-22 — Prove full lifecycle and reconcile operating docs

**Outcome:** Demonstrate the agreed autonomous engineering workflow end to end, including
recovery, and state exactly what remains unsupported.

**Scope:** Assemble prior tests into scenario-level conformance. Reconcile README,
EVENT_SOURCING, migration docs, roles, commands and AGENTS references with exercised
behavior. Retain the dated audit; add a closure matrix linking each F01–F24 finding to
implementation revisions and evidence or an explicitly unresolved gap.

**Acceptance:** Steer an objective, optionally plan, admit, launch, submit a real commit,
request a correction, independently review, integrate and activate a Foundry change.
Repeat with restarts at decision/effect boundaries and variants for blocked work, quota
exhaustion, full capacity, stale artifacts, partial persistence, lost observers and failed
activation. Assert actual Git/build/state outcomes and owned resource cleanup, while
foreign resources survive. Use deterministic fake backends for exhaustive fault cases
and a bounded real subscription smoke for harness integration. Report limitations of
each; mocks alone cannot establish real-provider behavior.

**V2 review acceptance refinement:** Add scenario variants for every R1–R5 interleaving/invariant and one real autonomous
kernel repair under unchanged root policy. Verify both kernel update success and attempted
root/credential/budget bypass denial. Runtime-only activation cannot close this capability.
Retain the complete original F01–F24 matrix and publish unresolved implementation limits.

**Excludes:** Declaring unknowns safe because all existing component tests pass.

## Completion log

2026-09-12, FR-06: design and isolated storage evidence recorded in
[WORKFLOW-CONTRACT.md](WORKFLOW-CONTRACT.md). No production repair implemented.
Independent design review was pending when that proposal was recorded.

2026-09-12, FR-06 independent review v1: [review](FR-06-DESIGN-REVIEW.md) completed;
verdict **not ready**, R1–R5 unresolved. Manifest matched before review-status edits;
the isolated storage rerun exactly reproduced the recorded JSON. No proposal or runtime
repair performed. Next: resolve the review findings, record revised input hashes and
review their disposition. Continue FR-01–FR-05 containment independently. FR-07 stays
blocked; stop this session after the review.

2026-09-12, FR-06 revision v2: [response](fr-06/review-response-v2.md) records R1–R5
protocol dispositions and smaller clarifications. Original manifest inputs verified;
reversing only the documented review-status edits reproduces both original plan hashes.
Historical review preserved. Current manifest identifies the revised input set. No
production repair or model invocation. **FR-07 remains blocked pending independent
re-review; no self-certification.** Next at that revision: verify v2 hashes, review protocols/dispositions
and implementation routing, record a new independent verdict. Stop after this design revision.

2026-09-12, FR-06 independent re-review v2: [review](FR-06-DESIGN-REVIEW-V2.md)
records **ready after specified corrections**. Manifest digest and all inputs matched;
dependency and F01–F24 routing checks passed. R1/R2/R3/R5 resolved at design level;
R4a retains the missing role-specific launch-non-start recovery transitions. Next:
make that bounded design correction and check its passages, acceptance traces and new
hashes. FR-07 stays blocked on R4a and FR-03. No implementation, provisioning or model
invocation occurred; the workflow proposal and historical review remain unchanged.

2026-09-12, FR-06 revision v3: [response](fr-06/review-response-v3.md) proposes the
bounded R4a correction and routes its acceptance traces to FR-08/10/11/12. Both independent
reviews and response v2 remain historical evidence. No production code, tests, daemon,
credentials or model execution changed. **FR-07 remains blocked pending focused independent
verification of the refreshed manifest, plus FR-03.** This entry does not certify R4a.

2026-09-12, FR-06 focused independent verification:
[review](fr-06/r4a-focused-review.md) returned **PASS** against the exact v3 manifest
and resolved R4a at design level. FR-06's design gate is complete. No production
implementation finding closed; FR-07 still waits for FR-03 completion evidence.

2026-09-12, FR-01: candidate v5 received an independent Astra-high
[PASS](fr-01/review-v5.md) for static containment. Every current automatic developer
and reviewer path requires the common validated policy plus an enforced subscription
route capability; the production System runner deliberately reports that capability as
unsupported, so no real automatic model launch is currently possible. PM eligibility is
covered although no PM model caller exists. Model-free focused, supporting, adversarial
and full-suite acceptance passed; the final isolated full run reported 323 passed and 2
integration-tag exclusions. Real OMP subscription/account/billing conformance and safe
re-enablement remain FR-09/15a, dynamic switching remains FR-16, and full lifecycle
acceptance remains FR-22. Candidate hashes and the review chain are retained in
[IMPLEMENTATION-LOG.md](IMPLEMENTATION-LOG.md).

2026-09-12, FR-02: Elixir-only candidate v2 received an independent
[PASS](fr-02/review-v2.md). `bin/pramana` now transports user argv as a bounded,
versioned JSON envelope inside canonical URL-safe base64 to one fixed RPC expression;
the daemon-side decoder rejects duplicate keys, malformed/oversized/noncanonical data,
NUL and unknown command shapes before dispatch. Actual-wrapper tests preserve literal
quotes, backslashes, newlines, Unicode, empty/interpolation-looking data, stdout/stderr
and exit status. General release eval authority remains FR-15a; equivalent historical
interpolation in `tickets_from_review.sh` and `test_daemon_recovery.sh` remains routed
to FR-03/04/05. No live daemon/provider was used.

2026-09-12, FR-03: candidate `69ede99128b14134cec9bddd728883e56f8cf62c`
received an independent [PASS](fr-03/review-v2.md) for immediate F02/F14 containment
after the original [review](fr-03/review.md) reproduced four blockers and the
[response](fr-03/review-response.md) corrected them. Startup now admits one fenced
runtime whose owner contains the effectful subtree; clean release follows subtree
quiescence, while abrupt/uncertain loss leaves an unclean marker and refuses automatic
takeover. Unterminated or invalid authoritative history is preserved and enters visible
recovery through the single strict replay path. Checked legacy writes cannot acknowledge
or launch after failure. Unsafe automatic startup reconciliation, multi-item tick work
and legacy Git integration are suspended for FR-07/08 and FR-05 rather than represented
as atomic. The new fixtures are Elixir; the existing Fence bridge remains the external
POSIX-lock boundary. This is integrated containment, not deployment or FR-22 lifecycle
acceptance. FR-07 is now ready because both FR-03 and FR-06 have completion evidence.

2026-09-13, FR-04: candidate `cd77de43475b1fbb4ef600384817b3f2434c6b4d`
received independent [PASS](fr-04/review-v9.md) after an adversarial review chain retained
in `docs/fr-04/`. Destructive cleanup now requires exact pane, terminal, native-session,
shell-generation and foreground-generation evidence; split ownership is durably recorded
before agent start, unverified/unknown resources are preserved, and developer/reviewer
resources remain distinct in a bounded role/execution inventory. Cleanup pending/results
use FR-03's checked gateway. Outstanding cleanup blocks admission and clean fence release;
all owned resources must have matching terminal evidence. CWD inference, hard-coded pane
exceptions, default-adapter close and the destructive fixed-root recovery fixture are gone.
This is immediate F05/F23 containment, not FR-10 reconciliation or atomic backend
compare-and-close; no live backend/provider or deployment was exercised.

2026-09-13, FR-05: candidate `5bc8c1ca81bfe65dff2b40a164ea8e12e2424f80`
received independent [PASS](fr-05/review-v2.md) after its original
[review](fr-05/review.md) found and the [response](fr-05/review-response.md) closed
two direct-boundary bypasses. CLI submissions no longer synthesize artifact, revision,
check or reviewer identity; automatic approval and production Git-check bypasses fail
closed. Every public legacy Pipeline/integration operation refuses before runner, state,
filesystem, Git ref or cleanup effects. Replayed legacy integration success is retained
only as an unverified historical claim and cannot advance the authoritative accepted
revision. The mutable-source watcher invokes no child and exits 78. This is containment,
not FR-13 artifact custody, FR-14 integration or FR-17 immutable activation; none is
deployed or re-enabled.

2026-09-19, FR-07: exact v9 candidate
`8d7223b79cb237d3406f156c7d1a06a8bcb48d81` received an independent Astra-high
[PASS](fr-07/review-v9.md), SHA-256
`08379ffd3315ec2724c4578a0a14e690f535238104107c778bd8d777efbf8638`.
All 56 manifest hashes matched; the focused 92-test suite and independent carrier,
retained-authority closure and both full-row recovery branches passed. Reviewed source and
evidence were integrated at `c4816b2e1ef5ae41943c98591246851b2672561f` and merged with
GitHub `origin/main` `4c91bf7ef917e67c73574eb0246d8d57cc28806d`. Upstream changed
only `foundry/README.md` among the candidate's 56 paths and did not change reviewed
durable-store behavior. Combined-tree warnings-as-errors compilation, 92 focused tests and
546 full-suite tests passed with exit zero. FR-07 is complete locally and not deployed.
The accepted-revision handoff adapter, FR-08, operational durability, activation and FR-22
remain open. Implementation pauses for the authorized whole-Foundry alignment audit.

2026-09-19, independent whole-Foundry alignment disposition: exact read-only audit
`ALIGNMENT-AUDIT-2026-09-19.md`, SHA-256
`c825b22bb857ccccd08171d79fae3b2d33ce76025fdf7dcb5db91ecc3ff63fe7`,
audited `2f603675e3feb1a65f0ce57a3bd69aa93deec29d` and recommended continuing the
repair without a ground-up rewrite. Coordinator disposition preserves FR-07 completion
and all F01–F24 routing, corrects its inventory row, introduces honest H0 followed by
FR-08A/B, records the current ProcessGroup correction under FR-04/10, splits FR-15a,
FR-18 and FR-19, advances bounded Pi-first feasibility without changing the governing
OMP contract, and updates review tiers/dependencies. No source, runtime, provider,
credential, policy, deployment or activation changed. Next resumable work is the bounded
FR-04 current-revision correction and H0 accepted-boundary report; either may proceed
without claiming FR-08A readiness or enabling execution.

2026-09-19, checkpoint F: corrected provider-free candidate
`148476c93497653abbbc52fb040cf76927478d3f`, tree
`e23217f94f295c115b893ac936c86ab719331647`, received a fresh independent Sol-high
[PASS](fr-09/checkpoint-f-rereview.md) at review commit
`ca8c6d0b5edc9a5cfb9c265e710b29f3210f5cbe`. The exact synthetic Pi RPC fixture
proved its bounded raw lifecycle and useful model-free Bash path while also reproducing
the missing credential gateway, R1/R5 broker/reservations, startup-extension denial,
principal/process/Git and network/IPC isolation. Its first review remains preserved as
the evidence that environment overlay and an escaped Jiti cache were corrected. This
completes only the honest F inventory and makes FR-15aA specification ready. OMP remains
governing; FR-09, FR-15aA/B, subscription conformance and automatic execution remain open.
No provider/model, live daemon, Herdr operation, installation or host-policy change ran.
