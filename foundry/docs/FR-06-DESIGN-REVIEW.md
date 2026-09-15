# FR-06 independent design review

Version **1**, 2026-09-12. Reviewer: Codex, in a separate review session from the
proposal's authoring session. Scope: the manifested working-tree proposal, not a
certification of the daemon or another implementation audit. Findings below remain
open; this review does not amend the proposed workflow contract.

## Blocking findings, ordered by severity

### R1 — P0: cancellation and privileged execution have no common ordering point

**Contract:** [WORKFLOW-CONTRACT](WORKFLOW-CONTRACT.md), lines 199–208: “Revoke pending
productive effects and capabilities,” “Integration that already happened cannot be
undone by cancel,” and “Every irreversible worker action rechecks current authority.”
Lines 235–240 require old epochs to be rejected. Lines 268–271 put `git update-ref`
after a durable intent, in a separately reconciled effect. The agreed operating
contract assigns authority to durable steering; audit F12/F14/F22 require responsive
controls and fencing of old-owner effects.

**Failure scenario:** An integration worker checks policy/epoch, then stalls before
`update-ref`. The controller commits and acknowledges cancellation or revocation.
The worker resumes and advances the ref. Git's old-ref comparison succeeds: it knows
nothing about cancellation or writer epochs. This is neither an integration that
“already happened” at cancellation nor a rejected stale action. The same window
exists between launcher authorization and starting a process. A new owner can also
encounter an old operation that passed its check before ownership changed.

**Evidence:** The proposal specifies a recheck and reconciliation, but no durable
effect claim/start state or serialization rule shared with cancellation. A writer
fence and SQL transaction cannot themselves order an external Git operation. Current
`Integration.Pipeline.promote_candidate/3` only checks a supplied state map and changes
that map; it supplies no existing protocol to fill this gap. This is an interleaving
derived from the design, not an exercised fault in a proposed implementation.

**Smallest required resolution:** Specify the broker's durable authorization/claim
boundary and its ordering with cancel, policy revision and epoch takeover. Define
whether an already claimed operation may finish after cancellation, what cancellation
acknowledges in that case, and when reconciliation permits final cancellation. The
broker must bind the exact effect/request and prevent stale or duplicate claims;
unresolved old claims must not be treated as safe retries. Keep slow Git/backend calls
outside controller callbacks. FR-10/14/15/17 can implement and inject the corresponding
interleavings later; choosing their required outcomes belongs in FR-06.

### R2 — P0: execution credentials have no specified boundary against bypassing the broker

**Contract:** WORKFLOW-CONTRACT lines 55–57 include arbitrary shell, build hooks and
tests in the threat model. Lines 68–77 isolate accounts and provision “OMP subscription
credentials ... into the isolated execution context.” Lines 210–223 require bounded
reservations, permitted profiles and the scheduler as “the sole launch path.” The
repair plan's product contract prohibits autonomous expansion of spending/authority.

**Failure scenario:** If the arbitrary-shell execution can use its account's reusable
OMP authentication, it can invoke a second harness or provider request directly, outside
the controller's execution ID, reservation, profile selection and cancellation path.
Separating that account from the controller and other workers does not prevent use of
its *own* credentials. A fixed privileged launcher constrains launcher requests, not
ordinary child processes launched by an already authorized worker. No stolen steering
credential or administrator privilege is necessary for this scenario.

**Evidence:** The contract distinguishes operator secrets from subscription credentials,
but does not distinguish the trusted authenticated harness from the untrusted shell it
executes, or specify who enforces profile/session limits on direct provider access.
FR-09 asks whether authentication works under isolation; FR-15a tests cross-role and
controller denial. Neither explicitly requires denial/accounting of this same-slot
bypass. Current AgentServer constructs a profile in its own process; that is not evidence
of an enforced replacement boundary. No credentials were read and no bypass was tried.
This is a conditional design gap, not a claim about installed OMP token semantics.

**Smallest required resolution:** Define which principal holds reusable provider
authentication and how untrusted shell/build/runtime code is prevented from using it
outside authorized execution. Select a concrete mechanism (for example, a separately
isolated authenticated harness with restricted tool execution, or an enforceable scoped
credential/request boundary). If installed OMP cannot support it, retain the execution
block and record the required design exception. Add same-slot direct-launch/profile
bypass to FR-09/15a acceptance. Actual authentication, host denial and subscription
smoke tests remain deferred; the missing enforcement responsibility does not.

### R3 — P1: the permanent kernel exclusion narrows the agreed self-update contract

**Contract:** REPAIR-PLAN, “Product and authority contract,” permits “Foundry merge and
activation once the acceptance and deployment protocols are proved”; temporary
containment must name its restoration ticket. Audit “Contract and evidence boundary”
permits autonomous Foundry activation within durable steering policy. In contrast,
WORKFLOW-CONTRACT lines 106–115 put the entire authoritative kernel in the controller
and require operator maintenance for every kernel upgrade, permanently excluding it
from autonomous activation. FR-15a expressly excludes autonomous controller upgrade.

**Contradiction:** A repair to an ordinary lifecycle/replay defect in the authoritative
kernel, which neither broadens authority nor weakens gates, can be independently
reviewed and pass all mandatory checks yet can never be autonomously activated. FR-20's
normal repair pipeline and FR-22's successful runtime-only demonstration would leave
that central class of Foundry repairs outside the agreed capability. Protecting the
policy/gate enforcement root is justified; treating all kernel behavior as that root
is an additional product decision, not a consequence of the spending prohibition.

**Evidence:** The exclusion is explicit, not merely an unimplemented acceptance test.
Current Application starts Coordinator/Improver/HardeningPM in one release; the proposed
split therefore changes the meaning of “Foundry update.” No recorded operator decision
in the reviewed contract accepts this narrower meaning. The audit recommends protecting
the highest-priority gate policy, not a blanket ban on all kernel repairs.

**Smallest required resolution:** Record an explicit disposition of the autonomy scope:
either obtain agreement to this permanent exclusion and identify the operator-maintained
components and unsupported repairs, or revise the split so authorized kernel repairs can
activate through a protected verifier/activation root without changing governing policy.
Reflect the choice in FR-17/20/22 and the operating contract. This review chooses neither
on the operator's behalf. No accounts or upgrade implementation are needed to settle it.

### R4 — P1: the transition table does not settle several legal lifecycle outcomes

**Contract:** FR-06 promises “legal transitions”; WORKFLOW-CONTRACT lines 172–200 enumerate
ticket phases and trigger/action summaries. The table introduces `cancel_requested`
without defining whether it is a phase or an orthogonal control record. It defines
developer success and developer crash separately without their allowed source phases.
Drain prohibits new developers but allows admitted reviews/integration to finish.

**Failure scenarios:** (1) A valid candidate is frozen, then its developer process exits
abnormally. Applying the unqualified crash row ends the attempt and queues new work;
treating it as cleanup preserves the candidate and queued review. Both readings fit the
table. (2) A reviewer asks for correction while draining. Correction requires a fresh
developer, which drain forbids, but the table does not say whether stop can finish with
that ticket queued/blocked or must wait for it. (3) A cancel with pending Git effects
has no defined final ticket/attempt state beyond reconciling “owned executions.”

**Evidence:** There is no from-state/event/guard registry or execution-state vocabulary
elsewhere in the reviewed proposal. Attempt terminal reasons are promised but the
successful attempt's terminal boundary is unspecified. Current AgentServer's cleanup
on `:review_approved` and re-prompt correction illustrate why downstream implementers
cannot safely inherit the existing lifecycle; audit F07/F09/F10 found precisely this
family of divergent completion rules.

**Smallest required resolution:** Add a compact legal-transition specification covering
ticket, attempt, execution and control state, with default rejection/no-op rules and
the terminal boundary for successful attempts. Settle result-versus-exit precedence,
check failure/timeout, cancel finalization including non-session effects, and drain's
treatment of corrections/queued or unresolved work. State who closes a successful
developer and invalidates its productive deadline so capacity-one review can proceed.
FR-08/11/12 then test these decisions; FR-06 need not implement a reducer.

### R5 — P1: durable counters are specified, but budget conservation is not

**Contract:** WORKFLOW-CONTRACT lines 129–130 bind attempts to reservations and executions
to attempts or PM objectives. Lines 184, 190, 192, 194 and 210–217 require reservations,
separate role retries, scoped operator reset, consume-on-start-or-uncertainty and refund
only on proved non-start. FR-06 explicitly owns budget ownership; FR-08/11/16 rely on it.

**Failure scenario:** A PM decomposes one objective into multiple tickets. Implementations
could give each new ticket a fresh limit or allocate all tickets against the objective's
remaining limit; the proposal specifies no relationship. Reviewer retries on the same
attempt also need new execution reservations, despite the identity table binding a
reservation to an attempt. After an uncertain start becomes a proved non-start, a refund
arriving after a scoped reset needs a defined ledger generation to avoid crediting the
new allowance. Distinct receipt observation IDs alone do not settle that accounting.

**Evidence:** No budget unit, parent/child allocation rule, reservation state machine or
reset reconciliation rule is specified. This is not a request to choose numerical limits
in FR-06. Current Tick charges generic launch failures; importing that behavior would
contradict the new capacity-denial rule rather than resolve these open decisions.

**Smallest required resolution:** Define reservation identity per charged execution or
validation action, its one-time settlement transitions, the objective/ticket relationship,
and reset generations including outstanding reservations. State a conservation invariant
for each bounded ledger (available plus held plus consumed equals authorized allocation,
with explicit transfers/resets). Decide which retries, rebase attempts and amendments
charge which ledger; a new ticket/spec/profile must not implicitly replenish an existing
allowance. FR-08/11/16 should later prove duplicate receipts, late reconciliation, reset,
correction and multi-ticket sequences against this specification.

## Other design conclusions and deferred acceptance

**Identities, replay and acknowledgment:** Separate store/ticket/attempt/execution/session/
presentation/candidate identities, raw artifact digests, one `apply` implementation and
transactional result/event/projection/intent publication are appropriate directions.
Acceptance is correctly distinguished from external success. The remaining interface
clarifications should accompany R4/R5: define canonical request encoding, the revision
scope for multi-entity commands, and make same-ID result lookup precede *current* revision
validation so a lost-reply retry still works after state advances. “Without mutation” for
a revision rejection should mean no domain mutation, since its command result is durable.
Generated IDs/time must enter pure decision logic as explicit inputs. These are small
schema clarifications, not reasons to retain a second reducer.

**Storage decision:** SQLite is a reasonable provisional selection on maintenance and
transactional-bundle grounds. The spike does not show SQLite beating a repaired journal
on the audit's complete failure-conformance set. Both arms pass the shared tested
boundaries; no performance advantage was measured. The verification note mostly describes
these limits accurately. Selecting SQLite need not wait for production implementation,
but FR-07/19 must retain the untested cases rather than call the comparison complete.

| Evidence actually inspected/rerun | What it establishes; what it does not |
|---|---|
| Same bundle in a SQLite row and journal frame; child exits before/after commit; same-key retry | Bundle presence/absence and deduplication at those selected process-exit boundaries; not interruption inside commit/fsync or power loss |
| Second OS writer while transaction/flock held, then retry after release | Write exclusion in the prototype; child failure is checked by exit code, not an assertion of the precise lock error; no external worker fencing |
| SQLite `max_page_count` capacity error | Prior two records remain; not filesystem ENOSPC, WAL/checkpoint capacity or sync failure; no equivalent journal capacity test |
| Backup and migration | Backup row count is checked, not full content/replay under concurrent writes; rollback is `PRAGMA user_version`, not deployed schema/code downgrade |
| Version refusal and journal damage | Application body version 99 is refused; partial journal tail/interior checksum mismatch refused with prior bytes retained; not SQLite page/WAL corruption handling |
| Journal unpublished snapshot | An independently read old snapshot ignores a partial pending file; no discovery/publication/rename/directory-sync recovery protocol is tested |

Separate SQL rows/constraints, the Elixir binding on the pinned platform, atomic budget
and projection consistency, physical storage errors, large history, import reruns,
checkpoint/compaction interruption and compatible rollback are deferred implementation
acceptance. No broad new storage benchmark is required by this review. The exact rerun
reproduces the supplied observations, not a stronger durability claim.

**Authority:** Separate controller ownership, per-slot accounts, transport-derived roles,
revocable scoped capabilities, fixed launcher assignments, protected refs/releases and
headless fallback are substantially more concrete than same-user worktree conventions.
They are not yet a fully specified boundary because of R1/R2 and the scope decision R3.
Actual UID/group/process/filesystem denial, slot cleanup, listener binding, status/crash
redaction, launcher input validation and immutable controller installation remain FR-15a
proof obligations. A non-login account label alone is not that proof. OMP authentication,
reconnect and Herdr attachment must be tested under the real restricted identity; success
under the interactive operator identity cannot close FR-09. Missing reconnect or uncertain
termination correctly retains leases and blocks only dependent work.

**Correction and review progress:** Fresh attempts with cleanup before relaunch eliminate
the current double-owner correction strategy. Separate reviewer retry accounting and a
durable priority review queue address the documented saturation failure. Progress still
depends on R4's successful-developer cleanup and on scheduling mandatory check workers as
well as reviewers. An uncertain live process intentionally holding capacity is a reported
block, not evidence that the capacity policy failed. Exhaustion must remain durable under
R5; it is not a reason to silently replenish developer attempts.

**Git and activation:** Fast-forward-only promotion with base equality, exact immutable
candidate receipts and renewed review after base movement is coherent. Serialized CAS
and old/new/third-ref reconciliation establish actual Git outcomes once R1 is resolved.
Private immutable builds, externally observed process/build identity, separate accepted/
deployed/healthy pointers and code-only compatible rollback preserve the right distinctions.
FR-13/17 must demonstrate safe freezing/import/copy while untrusted writers run, pinned
build inputs, mandatory external probes that a candidate cannot forge, and actual failed
stop/start/health recovery. Compatibility must cover all versions the new runtime can
cause to be written and all acknowledged commands, not merely overlapping declared ranges.
The explicit prohibition on restoring an old snapshot over newer acknowledged work is
correct; incompatible failure is correctly recovery mode, not claimed successful rollback.

## Dependency and acceptance disposition

The dependency inventory has no cycle or unknown ID. A valid order is FR-01, FR-02,
FR-03, FR-04, FR-05, FR-06, FR-07, FR-08, FR-15a, FR-09, FR-10, FR-11, FR-12,
FR-15, FR-13, FR-14, FR-16, FR-21, FR-17, FR-18, FR-19, FR-20, FR-22. FR-22
transitively reaches every other ticket, including FR-15a. This establishes graph
consistency, not availability of host provisioning or the missing FR-06 decisions.

There is routing drift: WORKFLOW-CONTRACT lines 65, 83 and 310 still assign isolation
proof to FR-15, whereas the backlog assigns it to FR-15a to let FR-09 precede the PM
loop. Align those references and distinguish initial operator-installed policy/scoped
protocol from FR-15's full durable steering. Do not make FR-15a require the later PM
loop, or silently waive its host provisioning prerequisite. No provisioning was attempted.

Every F01–F24 row appears once in the routing matrix, and its full audit/ticket acceptance
is explicitly retained. The following review disposition supplements that checksum:

| Obligations | Disposition after redesign |
|---|---|
| F01 | FR-01/16 retain role/profile/quota tests; R2/R5 add enforceable execution and accounting requirements |
| F02 | FR-03 containment remains necessary; FR-07 replaces the mechanism, not failed-write/corrupt/large-history obligations |
| F03–F04 | FR-02/05 containment and FR-12/13/15a preserve actual wrapper identity, ancestry/scope, independent role and mandatory receipt checks |
| F05–F06 | FR-04/10 ownership and FR-02/15a inert transport/scoped authority survive supersession; R1/R2 qualify effect authority |
| F07–F10 | FR-08–11 retain replay, stale observations, observer loss, role cleanup and reviewer recovery; R4/R5 must settle expected outcomes |
| F11 | FR-12/16 retain actual scheduler/environment/capacity tests; R4/R5 qualify progress and retry accounting |
| F12–F14 | FR-05 suspension is restored only by FR-13/14/17 evidence; R1/R3 qualify restoration; FR-03/10/15a retain singleton/old-writer obligations |
| F15–F16 | FR-12/15 retain optional PM/full specification; FR-08/11/13 retain actual blocked/partial public paths, without implicit retries |
| F17–F19 | FR-18/20 retain canonical board/telemetry/classifier and durable proposal outcomes; kernel repair activation remains unresolved under R3 |
| F20–F21 | FR-07/18/19 retain bounded storage, archival verification, offline relocation, unknown evidence refusal and preservation on failure |
| F22 | FR-15a/15/17/18 retain policy provenance, actual isolation and redaction; R1–R3 are unresolved design obligations, not waived by containment |
| F23–F24 | FR-04/21/22 retain owned non-vacuous tests, independent CI, source/build provenance, historical-tool disposition and bounded real-provider evidence |

No audit obligation is closed here. In particular, a runtime-only FR-22 activation must
not silently stand in for the unresolved autonomous kernel-update capability. Containment
FR-01–FR-05 can proceed independently; FR-07 stays blocked on this review's open findings
as well as its existing FR-03 dependency.

## Reviewed inputs and verification record

HEAD was `a3fa302342238ae3d5a133b35bd86f4fa4f13710`. Hashes below are SHA-256 of
**pre-review-edit working-tree bytes**, not a committed proposal. All four entries of
`fr-06/manifest.json` matched before edits. This review intentionally leaves that manifest
unchanged: the required review-status edit to REPAIR-PLAN subsequently changes its hash.
The original plan hash remains the reviewed input, not evidence of unexplained drift.

```text
AGENTS.md 56b2b70ae8f1c415cb057c3785eea42dfa0b949b1a9b2ae88155fb5471982c87
docs/STATUS.md a37c2b3411e223b060ecf733fbf9c55feb5064eead7ea7fdb81c2494973f2815
docs/PLAN.md 03d38d0065954c2eccaa84c1a47789363809b12ae591dda58651d9ab5c48fee9
docs/ROADMAP.md abe413c758cc58b1f6cb573d2b2a5a3877f979bb33f7e9fbebf9064046b9bac5
docs/RULES.md 45057c7ff3f412372290f4df58e4ab350a52500dde46f070ccdcd49e2286e1f5
docs/CHECKS.md b537b32716b5d3dd25c46f3bf9664e3c658f651bc15c54dafcbd53af1d6f8f39
foundry/README.md 43cf6d45fa01748e6cffbbf977d087f786a06870005e4765ac25ceef992cdb9c
foundry/docs/REPAIR-PLAN.md d493019f7f57c4bc8b132cbe211fc8fd72d92fb4e50d0336c7d8beac475045a2
foundry/docs/WORKFLOW-CONTRACT.md d455d412af17c746d1e78f9d96ca454fa403fd41a0b9c2d8d686612a2555cb29
foundry/docs/AUDIT-2026-09-12.md 3cd1818a5d57f1b58092166dd3396d2ae17455157bf8844f2bcfa02cf441121a
foundry/docs/fr-06/verification.md 91df1816a2d3df54f2fcd634cdbd8c09d537772d78f3f6896aed0a3557041718
foundry/docs/fr-06/manifest.json cb1a9b6b2136e9195149a4a6c1c6db6e4fd7fd28aadcc08966ec90a3386403cb
foundry/docs/fr-06/storage_spike.py 65da1683f1256d9ce623a75693b0f185454b2387c3d519a09a85e6dfda97d5eb
foundry/docs/fr-06/storage-results.json d6ae141fa56d7ceb649b63033de23ee4a3973672d76c76208cf81266a98a01ce
foundry/lib/pramana_foundry/application.ex c9f88ecdea02180483cef27c6ecacc45a876401df80b19562e846385a7c2bb72
foundry/lib/pramana_foundry/event_log.ex ed63f0b4372aeba5259d7c4d08d4f92a2faa884d4a0b7673e1dc310c8793700a
foundry/lib/pramana_foundry/effects/launch.ex b76aa1650acdfac03b35e2e498f5260c1f23081c682007f7a80b26fa89c9da22
foundry/mix.exs 15f5abc54b5636d2aab0da57df1157f763a28b3cbb8a714750b3bf492dea61d6
foundry/lib/pramana_foundry/coordinator/tick.ex 3a94a8eae4fae1408a2647d9a34b726a31fa7ee7814ac03bec19bc3b61c1bb78
foundry/lib/pramana_foundry/integration/pipeline.ex 32137db4796b260e125dbc8cfec70be1ffa5bf633f16b7cf84c85ab941b62cc1
foundry/lib/pramana_foundry/agent_server.ex 10c19bdf3c2ce4c526d5eac9765141404a35982e68e816c6045bb94498cd2bb6
foundry/bin/pramana-live.sh a6388fe16876d1ced3a79d8522c279b24fb0bd6d4dd4a732e590d695dc62dc2c
```

Commands/results in this review session:

- `git status --short`, `git rev-parse HEAD`: recorded the baseline and existing changes.
  Existing PLAN/README/CLI/Coordinator edits and untracked audit/evidence/review files
  were present before this review. No commit, reset, staging or production edit occurred.
- `cat`, bounded `sed`/`nl` reads and `rg`: orientation, proposal/evidence, relevant audit
  findings and the source paths above. Large initial combined orientation output was
  truncated; targeted reads supplied the Foundry plan, project status/phase context and
  applicable rules 8/60/62/63/79/82. This is not a line-by-line review of the corpus plan.
  A guessed `effects/check_runner.ex` read failed (file absent); `rg --files` located
  actual effects files, and the relevant gate path was read in Integration.Pipeline.
- Python `hashlib.sha256(Path(path).read_bytes())` against each manifest entry: all four
  matched. The same operation produced the input inventory above.
- Python subprocess invocation of `foundry/docs/fr-06/storage_spike.py`, with captured
  output and a 30-second timeout: exit **0**; parsed JSON exactly equaled the existing
  `storage-results.json`, including Python **3.9.6**, SQLite **3.51.0**, and observations.
  The experiment allocated its own TemporaryDirectory; captured evidence was not rewritten.
- Python dependency-table traversal, expanding FR-11–FR-21: no cycle/unknown ticket;
  FR-22 has every other ticket as an ancestor. Parsing the acceptance table yielded
  exactly F01 through F24, once each. Semantic dispositions are recorded above.
- Final documentation checks: `git diff --check`, direct trailing-whitespace/relative-link
  checks of the review and plan entries, and verification that only the intentional plan
  status update differs from the original FR-06 manifest inputs.

No full audit probes, Foundry/umbrella test suite, daemon RPC, account provisioning,
credential access, paid or subscription model invocation, live Git integration, release
activation, hardware fault or network isolation test ran. Generic implementation gates
in CHECKS were not used to imply completion of an implementation in this design-only
session. Existing audit executions are cited as dated evidence, not rerun results.
R1–R5 are design reasoning against explicit passages; none claims an exploit was measured.

## Verdict

**Not ready.** Resolve R1–R5, reconcile the smaller interface/routing clarifications,
and review the revised, newly hashed proposal before opening FR-07. Deferred implementation
acceptance remains with its owning tickets. Stop here; this review authorizes no repair,
provisioning, execution or activation.
