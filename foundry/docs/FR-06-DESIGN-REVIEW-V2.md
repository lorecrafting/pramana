# FR-06 independent re-review — v2 proposal

Review version **2**, 2026-09-12. Reviewer: Codex, the independent review session,
not the v2 proposal-writing session. [Review v1](FR-06-DESIGN-REVIEW.md) is preserved
unchanged. This review evaluates the manifested v2 proposal and
[author response](fr-06/review-response-v2.md); it does not repair either document.

## Remaining blocker

### R4a — P1: proved launch non-start does not have a domain recovery transition

**Exact contract:** [WORKFLOW-CONTRACT](WORKFLOW-CONTRACT.md), R1 lines 271–275,
allows `issued → non_started`; R4 line 352 allows an execution to become `closed`
on “proved non-start.” R5 lines 478–480 releases the associated held start units.
But the R4 domain rows at lines 375 and 386 require, respectively, “verified
exit/timeout” and “reviewer crash/timeout” to retry work without a valid result.
R4 begins by declaring unlisted public transitions rejected. The retained FR-11
acceptance explicitly includes **failed reviewer launch**; audit F10 distinguishes
reviewer launch failure from the generic developer retry path.

**Concrete trace:** A frozen candidate passes checks. The scheduler moves its
attempt/ticket to `reviewing` and reserves a reviewer start. The trusted launcher
proves that no reviewer process/session started, for example because process creation
failed before spawning a child. R1 settles the effect as `non_started`, R4 permits
execution closure, and R5 refunds the start hold. There is no reviewer crash, exit,
timeout or submitted verdict. No domain row returns this candidate to the reviewer
queue or puts it into a recoverable infrastructure block. The ticket can remain
`reviewing` with a closed execution. Synthesizing a process crash would erase the
non-start distinction; falling through a developer failure path would repeat F10.

The same omission affects developer launch non-start after `developing` is entered.
It is separate from scheduler capacity denial **before** creating an intent, and
from a possibly started execution, which must remain unknown until reconciled.

**Supporting evidence and limit:** This is a cross-table gap in the revised legal
contract, established by reading R1/R4/R5 together and searching the complete contract
for non-start and launch-failure handling. No proposed kernel exists to probe. R1
permits a safe effect retry after proof, but does not decide which role/attempt/domain
phase should own that retry. The current Tick's generic launch-retry path and
AgentServer's timeout/completion conflation were inspected in v1; their bytes remain
unchanged and cannot supply the missing normative behavior.

**Smallest required resolution:** Add explicit developer and reviewer launch-non-start
rows, with domain phase, attempt disposition, resource release, retry/block decision
and role ownership. Preserve the frozen candidate for reviewer infrastructure retries;
specify whether a developer non-start retains or ends its attempt. Bind each retry to
R1 predecessor/quiescence evidence, R5 non-start settlement and a bounded infrastructure
retry policy. Distinguish pre-intent capacity denial, proved non-start and unknown start.
Apply the same rule explicitly to PM/other role launches where applicable. Add these
traces to FR-08/10/11/12 acceptance, including restart after non-start settlement before
the next dispatch. Do not charge a confirmed process start that never happened merely
to bound retries.

This is a **small residual design correction**, not a request to redesign the authority
boundary again or implement those tests now. R4's other v1 scenarios are resolved.

## Disposition of the original findings

| Finding | Independent disposition against v2 |
|---|---|
| R1: privileged action/cancel ordering | **Resolved at design level.** `issued` is an explicit authorization boundary; cancellation before it prevents issue, cancellation after it reports outstanding claims and permits that one operation to settle. |
| R2: own-slot credential bypass | **Resolved at design level.** Reusable authentication resides in a protected gateway; trusted harness and arbitrary tools have separate principals and network/IPC authority. Per-request claims prevent direct or hidden requests from bypassing accounting. |
| R3: autonomous kernel exclusion | **Resolved at design level.** The workflow kernel is updatable outside the protected writer/verifier; root safety predicates use their own policy, ledger and evidence rather than candidate projections. Autonomous kernel-repair activation is an explicit FR-17/20/22 obligation. |
| R4: legal lifecycle outcomes | **Partially resolved; R4a remains.** Result/exit precedence, sealed input, developer cleanup, check classification, drain corrections, successful-attempt termination and non-session cancellation now have specified outcomes. Launch non-start is not mapped back into the domain lifecycle. |
| R5: budget conservation | **Resolved at design level.** Typed units, per-action reservations, parent-funded allocations, held unknowns, one-time settlement and generation-scoped resets replace the ambiguous counters. R4a still needs a bounded domain retry decision after a refunded launch. |

“Resolved at design level” closes the stated design objection, not an implementation
finding or security/durability acceptance gate. The following reasoning and limits are
part of these dispositions.

**Ordering and idempotency:** The R1 issue/cancel cases now have a shared transactional
order and an honest acknowledgment. A check before an external call is no longer
presented as cancellation enforcement. Semantic operation keys constrain duplicate IDs;
old-epoch receipt settlement is separate from new authorization. An issued-but-undelivered
operation may remain unknown, which sacrifices availability rather than inventing a
safe retry. Old-ref equality is correctly insufficient until the issuer/channel is
quiescent. The implementation must retain this conservative behavior across the broker's
own crash, not only across a kernel crash.

Command result lookup now precedes current revision checks, and a separately authorized
read path handles revoked submission tokens. Canonical bytes, multi-entity read sets,
explicit IDs/time, versioned projections and atomic command/event/ledger/intent commits
settle the smaller v1 interface concerns. The protected gateway and domain reducer have
different responsibilities; implementation must not recreate two competing domain reducers.

**Authority and autonomous repair:** V2 names actual enforcement responsibilities:
protected reusable authentication, fixed provider operations, isolated remote tools,
disabled candidate extension discovery, and denial of direct network/proxy/IPC access.
This resolves the missing own-slot boundary without claiming installed OMP already
supports it. Herdr remains optional sanitized presentation. FR-09's required adapter
proof and FR-15a's actual host denial tests are material feasibility gates, not paperwork.
If either fails, automatic execution stays disabled and a bounded design exception is
required. No credential copying or replacement harness is implicitly approved.

The root/kernel split now preserves ordinary autonomous lifecycle/replay repairs while
keeping policy, budget grants, privileged claims, receipt provenance and activation out
of candidate control. A candidate's false `integrated` label is not enough to obtain a
Git update. This is a defensible architectural split, not a proof that arbitrary kernel
code is correct or that the eventual verifier API is sufficient. FR-07/08/15a must
derive protected reads/predicates independently of submitted projections. Moving the
whole reducer back into the operator-only root would reopen R3, as the contract states.

**Lifecycle and capacity:** A valid frozen candidate survives later abnormal developer
exit; the broker processes the sealed inbox before deciding no result exists. Immediate
developer closure, followed by check and reviewer workers, removes the capacity-one
review deadlock. Unknown stream completeness or process cleanup deliberately blocks
affected work. Drain now leaves correction/rebase work durably blocked without waiting
for a developer it forbids. Cancel finalization includes imports, Git and release effects;
integration/deployment facts survive cancellation. These are concrete improvements over
v1 and should not be reopened merely because their tests have not yet been implemented.

**Ledger:** The per-generation equation and parent-to-child transfer rule preserve units
without counting delegated allocation twice. Unknown issuance remains held; confirmed
start is consumed even if later cancelled; a proved non-start is released. A late refund
to a closed generation becomes retired, not new spending power. Explicit new grants
remain subject to parent/global caps including outstanding old holds. These conclusions
are algebraic case analysis, not an executed ledger model. Integer/constraint/transaction,
duplicate/conflicting receipt and recursive reset tests remain FR-07/08/15/16 obligations.
Request/start budgets correctly do not pretend to be measured token or currency ceilings.

**Git, activation and storage:** Exact frozen object custody, renewed review on base
movement, root-owned CAS and issued-effect reconciliation remain coherent. Safe staging
copy verification, immutable outputs, actual start/stop/health and kernel-repair activation
must be demonstrated in FR-13/14/17. Write-set inclusion is stronger than merely overlapping
version declarations. Rollback must preserve all acknowledged commands and protected facts;
an incompatible failure remains recovery mode, never restoration of an old snapshot over
new work. Root health checks and install allowlists cannot be supplied by the candidate.

SQLite remains a reasonable provisional maintenance/transaction choice. The storage script
and results are unchanged from the v1 rerun. V2 correctly narrows its backup/version/lock
claims and retains physical capacity, sync/WAL corruption, compaction and deployed rollback
limits. No new storage question required another rerun. This re-review does not establish
the real Elixir binding, full multi-table atomicity or filesystem crash durability.

## Dependencies and acceptance obligations

The v2 dependency graph is acyclic, has no unknown ticket, and FR-22 transitively reaches
every other ticket. FR-15a now depends on FR-07/08; initial policy, claims and ledgers can
be exercised there without waiting for the PM loop. FR-09 uses bounded preconfigured
assignments, so the later scheduler/switching tickets do not create a hidden cycle.
Actual host provisioning remains an external prerequisite. FR-20's proposal work can
precede FR-17, but its own text explicitly withholds full activation completion until
FR-17 passes; the dependency table is not permission to waive that obligation.

All F01–F24 matrix rows remain present once each. The retained ticket acceptance plus v2
refinements preserve the substantive groups checked in v1: spending/profile enforcement;
write failure and replay; actual artifact/role/scope verification; owned cleanup; truthful
execution/review outcomes; actual Git and immutable activation; steering; observability;
maintenance; independent CI and provider conformance. Added auth and kernel-repair tests
strengthen F01/F13/F22 rather than substitute a weaker runtime-only demonstration.
The failed-reviewer-launch requirement survives in FR-11 and is why R4a must be settled.
No audit finding is marked implemented or closed by this re-review.

## Inputs, commands and limitations

HEAD: `a3fa302342238ae3d5a133b35bd86f4fa4f13710`. Manifest SHA-256:
`42817763eda93bacaa0598eda3c63cb957bce20306cfae73857f5d2c3fef075b`.
The supplied manifest digest and **all 13 entries matched** before review-status edits.
The reviewed working-tree hashes are recorded here so later plan edits do not obscure
the evidence boundary:

```text
AGENTS.md 56b2b70ae8f1c415cb057c3785eea42dfa0b949b1a9b2ae88155fb5471982c87
docs/STATUS.md a37c2b3411e223b060ecf733fbf9c55feb5064eead7ea7fdb81c2494973f2815
docs/PLAN.md 431e71f48e35c579de0c6ac6f6af6e81c866cccd1745e57703d96fbece390f42
docs/ROADMAP.md abe413c758cc58b1f6cb573d2b2a5a3877f979bb33f7e9fbebf9064046b9bac5
docs/RULES.md 45057c7ff3f412372290f4df58e4ab350a52500dde46f070ccdcd49e2286e1f5
foundry/docs/WORKFLOW-CONTRACT.md 4041ce015980c02f0c2aec37e39fac9e0c0349c84e882cdea39125964a7f434c
foundry/docs/REPAIR-PLAN.md a882edd74554cc17ed929431dbb519a2c0691bd2e51b5f9d44f1c02bdd69c300
foundry/docs/FR-06-DESIGN-REVIEW.md d953b960c0fd1b746290764adff46dddbafd85d8cb852c24fa78142cff247134
foundry/docs/AUDIT-2026-09-12.md 3cd1818a5d57f1b58092166dd3396d2ae17455157bf8844f2bcfa02cf441121a
foundry/docs/fr-06/review-response-v2.md 426da04cf0e04f44192a4357e867fba1ac5f6668a44a8f37a9f4b1e1638fc179
foundry/docs/fr-06/verification.md 687a56213967ac6b60e0a7072fedbd891247ebd33e02e9cef835ece9f001225c
foundry/docs/fr-06/storage_spike.py 65da1683f1256d9ce623a75693b0f185454b2387c3d519a09a85e6dfda97d5eb
foundry/docs/fr-06/storage-results.json d6ae141fa56d7ceb649b63033de23ee4a3973672d76c76208cf81266a98a01ce
```

- `git status --short`, `git rev-parse HEAD`: baseline captured; existing unrelated
  README/CLI/Coordinator edits and audit/review artifacts were preserved.
- Targeted `cat`, `sed` and `rg`: complete v2 contract/response/verification, changed
  plan sections, retained acceptance and v1 finding references. Initial combined tool
  output was truncated; focused contract and verification reads recovered it. Orientation,
  audit and focused source review from v1 were retained in this session; their hashes
  were checked rather than repeating the full audit.
- Python `hashlib.sha256(Path(path).read_bytes())`: supplied manifest digest and all
  entries matched. The focused source hashes in review v1 also still matched, including
  Tick, AgentServer, Integration.Pipeline, Application, EventLog, Effects.Launch, mix.exs
  and the watcher. No new source behavior is claimed from that identity check.
- Python dependency-table traversal with FR-11–FR-21 expanded: exit 0; no cycle/unknown
  ID; FR-22 reaches every ticket. Acceptance-table parsing: F01–F24 exactly once. This
  is a routing check, supplemented by the semantic review above, not a test of repair.
- Pre-edit hashes of manifest inputs and tracked changed files saved to
  `/private/tmp/fr06-rereview-v2-baseline.json` for the final preservation check.
- Final documentation validation **passed**: `git diff --check` exited 0; direct
  whitespace/link checks and comparison with the saved input hashes passed. The only
  intentional input changes are review
  status in REPAIR-PLAN and the Foundry entry in docs/PLAN. The manifest stays unchanged
  as the exact v2 input record; its two plan entries therefore become historical hashes.

No implementation, daemon access, credentials, host provisioning, model invocation,
storage rerun, broad audit, full suite, live integration or activation was performed.
No executable probe was needed to resolve the remaining missing transition: the proposed
state machine has no implementation whose behavior could establish the normative answer.
The v2 author's historical hash-reconstruction and paragraph-comparison commands were
read as evidence; this re-review independently verified the current manifest and graph,
not those author's temporary scripts.

## Verdict

**Ready after specified corrections.** Resolve R4a with explicit role-specific non-start
transitions and acceptance traces, then perform a focused check of those revised passages
and refreshed hashes. R1/R2/R3/R5 need no further architectural revision unless that change
affects their guarantees. FR-07 remains blocked on R4a and its existing FR-03 prerequisite.
Stop after this review; no implementation ticket begins here.
