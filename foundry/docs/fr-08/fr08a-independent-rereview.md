# FR-08A corrected-candidate independent critical rereview — BLOCKER

Reviewed 2026-09-19 (Hawaii), Astra-high, independently of the corrections. **BLOCKER.**
The corrected implementation closes several original failures, including loaded-code
binding, old-epoch issuance, wrong-dimension spending and same-request reconciliation.
It still permits rejected commands to mutate authority, semantic identity bypasses,
issuance after predecessor quarantine and corrupted authority on recovery. FR-08A is not
complete and this candidate must not enable FR-08B.

## Exact subject and scope

- Frozen candidate: `ed78312d8b43d41c53777f6ee8bf1665969b9cb8`, tree
  `f4dfc8f6681d00ff83a5a02491a0c93b52454e8f`.
- Corrected core: `44a56be3b4854b7cd392215beef6e01f4f30097a`, tree
  `08aeb550ae5bf6b4c178ac8b933bcfc7e7d956df`.
- Loaded-code evidence: `7d81b5bf634a85ad9a26632c3a9bc11fbe5380d5`.
- Native-fixture path correction: `06d388f2e7683862e4f599cf21b639331f223c1e`.
- Original blocker review: `acb8ae22ff34b908cc65b068292547a0b185e377` and
  [its B1–B9 findings](fr08a-independent-review.md).
- Branch/worktree: `repair/fr08a-protected-primitives`, `/private/tmp/pramana-fr08a`.

The checkout remained clean at the frozen candidate through runtime verification and
canonical CI. Only this report, its [reviewer probes](fr08a-rereview-probes.exs) and catalog
routing are subsequent repository edits. No implementation, maintained tests, frozen
candidate/report, shared plan, implementation log, provider configuration, credentials,
daemon, integration or push was changed or performed.

I read the shared workflow, Foundry orientation/strategy, H0/FR-08A/shared acceptance,
R1/R5/R4a and migration/recovery contract, H0 candidate/blocker/rereview, the original
FR-08A review, corrected source and affected tests. Exact tree identities match. All
11 corrected manifest paths match the candidate; all 12 distinct H0 manifest paths
(13 lines) match its frozen `4c8734c6473be97da77f299bc4b42cd720cdf0b6`; all 56 FR-07 v9
paths match `af0c51b4682c50080e67194dd853fbaa1eebace7`.

All functional probes use public Gateway operations. The two recovery probes modify
only disposable SQLite files after stopping their Gateway; those are logical-corruption
negative controls, never positive authority evidence. Actual OS/channel quiescence,
provider behavior and physical storage failures are outside these model-free probes.

## Remaining blocking findings

### R1 — A durable rejection commits partial authority mutations (B8/B9)

`protected_primitives.ex:20` commits the transaction after either accepted facts or a
semantic rejection. This is safe only if rejected operations have not already performed
unauthorized writes. Two public sequences violate that assumption:

- `set_control` writes its head/history at `:340` before checking the control status.
  Setting `status=bogus` returns a committed `invalid_control_state` rejection, but the
  public control has changed from active/revision 0 to bogus/revision 1. Reopening enters
  recovery with `root_control_history/:lineage`, because the new history belongs to a
  rejected command. The rejection has damaged an otherwise healthy store.
- Propose two reservations of 12 units against the same 20-unit ledger, then admit one
  effect using both. Proposal creation correctly holds nothing. Admission inserts the
  effect at `:891`, activates the first reservation at `:2579`, and rejects the second
  as `reservation_activation_not_permitted`. The committed rejection nevertheless leaves
  a pending effect, one reserved 12-unit hold, one proposed reservation, available 8 and
  held 12. The partial rejected admission even reopens ready.

Derive all admission predicates and aggregate spending before mutation, or roll back
the operation's writes before retaining its rejected command result. Keep intentional
quarantine mutations explicit. A passing injected precommit rollback does not establish
that a semantic rejection is atomic.

### R2 — Semantic identity is still caller-chosen metadata, not admitted authority (B3)

`create_effect` (`:807`) copies phase generation, ordinal, profile and deadline out of the
request. `assignment_id/3` (`:2683`) concatenates supplied ticket/attempt/role strings; it
does not resolve an admitted assignment. The duplicate query at `:2644` compares the
supplied role/generation/ordinal only among nonterminal effects. `predecessor_guard`
accepts every `(ordinal=0, predecessor=nil)` at `:2686`.

Independent public probes show:

- While a developer launch for `T/A` is issued, a second launch for the same assignment
  with phase generation 99 and a new execution/request is accepted.
- After an attributable non-start refunds the first launch, another launch for that same
  owner is accepted with ordinal 0 and no predecessor. Protected policy carries
  `launch_non_start_limit=1`, but no durable allowance check consumes or enforces it.
- A request selecting profile `unapproved`, with deadline 1, is admitted and issued even
  though the retained policy names `allowed_profiles=[sol]`. Source checks only operation
  and scope (`:2532`); it provides no admitted profile/deadline/role binding. This is a
  protected admission gap; broker elapsed-time enforcement remains FR-15a's job.
- `scope=ticket:T` with `ticket_id=other-ticket` is accepted and holds credit. The same
  store then refuses restart because recovery, unlike admission, checks scope identity
  at `:3689`. The live and retained validity predicates disagree.

The fixed operation-to-dimension mapping is useful and passes the original hostile
case. It does not establish semantic owner/generation authority, finite non-start retry
allowances or assignment policy. Root must derive those identities and transitions,
retain terminal semantic keys and bind every permitted successor to the proper owner.
Random generation/attempt/control identifiers cannot stand in for an authorized change.

### R3 — Late predecessor conflict does not fence an admitted successor (B2/B3/B5)

The probe uses a separate policy with non-start limit 3 to avoid testing exhaustion.
It issues a launch, settles attributable non-start, admits ordinal-1 successor referencing
that predecessor, and then submits a contradictory delivered-success receipt for the
predecessor. The predecessor becomes `reconciliation_required`. The successor can still
be claimed and issued accepted.

Predecessor checks occur only at creation. Claim/issue (`:928`, `:986`) neither recheck
the predecessor nor enforce owner quarantine. Their derived read sets (`:1717`, `:1766`)
omit predecessor/owner reconciliation state. Adding its identity to effect metadata is
therefore insufficient: the relevant authority must be in the current predicate and CAS
set immediately before issuance. Otherwise conflicting evidence does not prevent the
replacement action it is required to fence. Released leases are also excluded by
`retain_leases` (`:3153`); the current quarantine is not a complete owner/resource fence.

### R4 — Recovery still accepts invented protected authority (B6)

Policy command/history and pointer checks now reject the original corruption fixtures.
Ledger and effect provenance remain incomplete:

- After a real 20-unit root grant, the negative fixture changes only that ledger's
  `authorized` and `available` columns and canonical state to 2000. The authenticated
  grant command/result remain unchanged. Reopen is ready and the public ledger returns
  2000 authorized/available. Conservation and canonical column/state equality (`:3604`)
  cannot establish that the units were granted.
- After real effect admission by `operator`, changing only canonical effect state
  `issuer` to `impostor` leaves its command, request digest and original result unchanged.
  Reopen is ready and the public fact reports the forged issuer. The settlement path
  subsequently treats that effect issuer as the authenticated provenance check.

`validate_effect_states` rebuilds fields from the same stored state; the semantic checks
at `:3681` do not bind immutable admission fields to the originating command. Similar
receipt validation checks an internally consistent digest but does not re-establish the
authenticated command/issuer provenance. Validate retained authority against its
authenticated derivation, not just mutually consistent carriers. These are local logical
corruption checks, not administrator-resistant cryptography or FR-19 physical recovery.

### R5 — Receipt observation-ID conflicts still become storage failures (B5/B9)

Two independently reproduced cases reach `UNIQUE constraint failed:
root_receipts.receipt_id` and fence a healthy Gateway:

- An unknown observation is followed by terminal evidence for the same issued request
  reusing that observation ID. This is conflicting observation identity and must be
  durably rejected/quarantined; it is not a valid new observation.
- A different legitimately issued claim supplies an observation ID already used by
  another claim, while correctly naming its own immutable request.

The same-request reconciliation correction works when observations have distinct IDs.
However, `settle_with_receipts` and `reconciled_settlement` (`:1412`, `:1454`) check the
current claim's receipts and then insert without adjudicating global observation-ID
ownership. The CAS includes the receipt ID, but a caller using its current revision still
reaches the SQL collision. Detect that semantic conflict before mutation and preserve
the conflicting evidence without a storage fence or credit change.

### R6 — One already-closed descendant prevents parent close/reset (B4)

Delegate four units to a child, close the child, then close its still-open parent.
The parent command durably rejects `generation_already_closed`, leaving the parent open
with its 16 available units. `close_generation` requires **every** subtree member to be
open (`:679`), and both root and child reset repeat that predicate (`:712`, `:769`).
Thus ordinary prior child closure/reset prevents later recursive closure of remaining
authority. This is especially significant after child reset, which deliberately retains
the closed old child generation in the parent's tree.

Recursive closure must preserve already-closed members and close/revoke the remaining
open subtree atomically. Rejecting closure is not the required no-new-issuance fence.
The all-open recursive positive case and closed-parent no-refill case do pass.

## Original B1–B9 disposition and credited controls

| Original family | Independent correction result |
|---|---|
| B1 loaded implementation | Corrected. Nine named modules bind compile-metadata source SHA-256 and loaded BEAM MD5. The original in-memory changed-Gateway probe now yields 0 pass, 7 unavailable, `ready=false`; changed behavior executes and source bytes remain unchanged. |
| B2 epoch/control/CAS | Current epoch rejection, explicit quiescent reclaim and cancellation of unissued descendants pass. Current predecessor/owner authority is still missing: R3. Actual external quiescence proof remains FR-15a. |
| B3 semantic identity/dimension | Wrong-dimension admission rejects safely; semantic/assignment/ordinal policy remains blocked by R2. |
| B4 recursive generations | All-open recursion, no issue after close and no closed-parent refill pass; mixed open/closed subtree remains blocked by R6. |
| B5 receipts/reconciliation | Immutable request mismatch rejects; distinct observations reconcile unknown to terminal on the same request. Observation collisions and owner quarantine remain R3/R5. |
| B6 recovery | Original policy/history, pointer, malformed-input and migration corruption probes pass; invented ledger/issuer authority remains R4. |
| B7 safe migration | Future protected version and missing-pointer migration refuse without repair. Current-version rerun passes. Nonempty accepted-v9 migration and rollback-build semantic compatibility are not established by the empty v1-shaped fixture. |
| B8 one authority truth | Maintained public tests pass both explicit modes: legacy facts prohibit root writes; root commands retire productive legacy writes. Proposed reservations hold no units before admission. Partial rejected admission remains R1. |
| B9 rejection/faults | Original malformed policy, wrong inbox actor and distinct-owner lease collision no longer fence. Root precommit rollback, lost-reply retry and real postcommit child exit pass. R1/R5 still violate the broader rejection contract. |

The original public suite's three failures are obsolete positive setup expectations,
not preserved unsafe behavior. New probes explicitly verify durable rejection after
restart for wrong-dimension admission, return into a closed parent and duplicate-owner
admission. A separate valid second owner reaches the lease conflict path: its claim
rejects `lease_conflict`, no second claim/lease appears, held remains 2, and restart is
ready. Thus the early duplicate rejection does not hide required lease behavior.

H0 history is intact. Its historical provider correctly refuses to credit changed
FR-08A code (7 unavailable), while the frozen accepted-v9 record remains 4 pass/3
unavailable. Inherited idempotency, protected-field, missing-store and immutable-import
controls pass in the evolved provider/suites. This does not retrospectively change H0's
scope or prove the new protected invariants. Pointers remain honestly absent and
FR-18A can represent that absence without waiting for FR-17 production.

## Executed verification

Pinned Elixir 1.20.3 / OTP 29.0.5 / ERTS 17.0.5 through the recorded `run.sh`, with
isolated build/runtime/temp roots under `/private/tmp/fr08a-rereview.URAvcb/`. Focused
checks reused dependency sources; canonical CI restored locked dependencies into its
own fresh root and verified the clean frozen source before and after execution.

| Check | Actual result |
|---|---|
| Forced warnings-as-errors compile | exit 0; 108 project files |
| DurableStore and repair directories, seed 9292 | exit 0; 111 passed, including native xSync and loaded-code negative controls |
| Legacy persistence containment and effect checkpoint tests, seed 9294 | exit 0; 13 passed |
| Original public probes, seed 9281 | exit 2; 9/12 passed; three early rejections independently covered above |
| Original recovery probes, seed 9283 | exit 0; 7 passed |
| Original loaded-code binding probe | exit 0; altered loaded Gateway refused |
| Original real-process crash probe/child | exit 0; child exits 73, ambiguous owner fences, observed-exit recovery and same-ID retry preserve one grant |
| New reviewer probes, seed 9293 | exit 2; 3/15 passed; 12 required-behavior failures grouped as R1–R6 |
| Canonical `elixir ci/run.exs --output .../ci` | exit 0; 571 passed, 1 optional Python/tiktoken recomputation excluded; dependency policy, compile, format, native tests, escript and clean-source postflight pass |
| Exact manifests and `git diff --check fa636fb HEAD` | exit 0 |
| Frozen-candidate and staged-review `elixir bin/check_docs.exs` | both exit 0; 80 passed each |

The initial focused command also named two nonexistent test paths; Mix exercised the
two existing directories. The separate correctly named containment/checkpoint invocation
above supplies those checks. During new-probe development, the grant corruption carrier
initially included a query-only field and the issuer fixture needed JSON-null conversion;
those fixture errors were corrected before the final 15-test run. No implementation was
changed. The native header-path fix passes canonical CI without the former `CPATH` workaround.

CI evidence has a separate inherited limitation: its provenance includes
`format_debt.error="format-debt baseline changed"` despite overall exit 0. Independent
hashing confirms all seven excluded debt entries mismatch their recorded baselines;
the runner catches that error as metadata while excluding those paths from formatting.
The runner, debt file and seven files have no delta from the FR-08A baseline. Therefore
the green command proves formatting only outside that excluded set, not successful debt
identity verification. Repair that existing CI policy gap separately; it does not explain
or excuse R1–R6, and this review changes none of those files.

The committed probe is byte-identical to external `hostile.exs`; run from `foundry/`
with the pinned toolchain and isolated test environment:

```sh
mix run --no-start --no-compile docs/fr-08/fr08a-rereview-probes.exs
```

It intentionally asserts required behavior and therefore fails this candidate. It
creates only uniquely named disposable fixture stores beneath the chosen temp root.
Original scripts remain at `/private/tmp/fr08a-independent.YFHW86/`, unchanged.

## Evidence hashes and follow-up boundary

These artifacts are under `/private/tmp/fr08a-rereview.URAvcb/`:

| Artifact | SHA-256 |
|---|---|
| `run.sh` | `e8e1688a51c48bc0b94cb4e22b551bf4fb0db2797f7718f216e975056f1beeef` |
| `manifest.exs` | `64f8ebe710074c0cf3c7284519fe61bf018b81ea7d3ff85a18782c085ec745e1` |
| `hostile.exs` / committed reviewer probe | `04cd3821181cb003f237d8c25c8a955951570e864b1dddbd58c28ccd733f8f3f` |
| `hostile.log` | `aebc3ae750ff3939f3eebd8fe147367285fe993558934e40441c6affb4a6ae6a` |
| `binding.log` | `4bbbb89d5a5c83a7c5713efa47cc3ad05028dbb0118e10b802930e80e1c137bd` |
| `public-original.log` | `1edf1b8e9acb1d854dfa8a945538cc1b35e151ba9d6027d0f2ae48aa66b1d5a5` |
| `recovery-original.log` | `c6b06b1cb3b2ee322b71d817cbd94e53252d80eb13bc906c48787142a632e7dd` |
| `crash.log` | `8cc1da19325bf7446f52dc33f6ac046ac50f5331bd416049f5fbf1ba83d7931f` |
| `ci/provenance.json` | `870b2a94182d45386269ed82683db73ce928361c8dd0f54e8316d9529b97cb76` |

R1–R6 are blockers, not suggestions. Separate documentation/interface follow-ups are
to clarify dimension-specific ledger/objective envelope identity, root-reset grant versus
transfer accounting, and the irreversible maintenance/rollback compatibility boundary;
to establish nonempty accepted-store migration evidence; and to provide bounded query
summaries/raw-evidence access for FR-18A. The current queries still materialize associated
rows. None of these observations substitutes for the reproduced blocking findings.

Preserve the accepted H0/FR-07 evidence and corrected controls, repair the protected
invariant families, refreeze, and obtain another independent critical review. FR-08B
still owns all-ingress/domain replay, FR-15a actual isolation/channel fencing, FR-18
presentation, FR-19 physical maintenance, FR-17 pointer production/activation and FR-22
whole-lifecycle acceptance. This review authorizes none of those activities.
