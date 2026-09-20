# FR-08A fresh acceptance review — BLOCKER

Reviewed 2026-09-19 (Hawaii), Astra-high, independently of implementation. **BLOCKER.**
The final correction closes the reproduced F1 deep-predecessor and F3 explicit-deadline
failures and the exact F2 origin-forgery probes. Recovery still accepts derived current
authority that contradicts retained authenticated transitions. Four fresh probes establish
duplicate issuance, reopening of retired credit, and release of an issued hold without
settlement. This continues B6/R4/F2; FR-08A is not accepted and FR-08B must not begin.

## Exact subject and review boundary

- Candidate: `32059dc49d8add1bb8fef1ad1dc3d105aa544c1c`, tree
  `ecafb1af2909533170b142c9ab271dd65f4d95fd`.
- Corrected core: `e79a88a163202ef38cf32ea65ed348554a3dedc1`, tree
  `5afd76721c082c596ddd32898c46520a1f23d775`.
- Rebound evidence: `408fd0d21d7ba8a07170809dab2a2f1e30c5d5b2`, tree
  `9e33ee71bca59c9df0767575b3cd0d1c42b25d35`.
- Baseline: `fa636fb592eacf4ebd31b72fa377b0a86a6d3e3e`.
- Branch/worktree: `repair/fr08a-protected-primitives`, `/private/tmp/pramana-fr08a`.

I read project orientation, shared completion/H0/FR-08A acceptance, the FR-06
encoding/R1/R4a/R5/recovery/compatibility contract, H0 candidate and independent reviews,
all three earlier FR-08A independent reviews, the corrected candidate, correction diff,
authority/recovery paths and relevant tests. The earlier findings are evidence to
reproduce, not acceptance authority. All three named trees match. All 15 candidate
manifest entries match; all 12 distinct H0 paths (13 lines) match frozen
`4c8734c6473be97da77f299bc4b42cd720cdf0b6`; all 56 accepted-v9 paths match
`af0c51b4682c50080e67194dd853fbaa1eebace7`.

The candidate remained clean through canonical CI and the independent runtime checks.
Subsequent repository edits are this review, its [probe script](fr08a-acceptance-review-probes.exs)
and the catalog link. No implementation, maintained test, frozen candidate/report, shared
plan, implementation log, provider setting, daemon, push or integration was changed.

Positive authority observations use public Gateway APIs. Corruption fixtures alter only
disposable SQLite stores after stopping their Gateway. For each of the four new failures,
the probe compares every `root_commands` row before and after corruption, including actor,
digest, canonical request, disposition and result, and requires exact equality. No
authenticated command or retained result is rewritten in those failure fixtures. This
is logical recovery validation, not administrator-resistant storage cryptography or proof
of provider behavior or physical-media recovery.

## G1 — Recovery does not reconstruct current protected transitions

`protected_primitives.ex:4051` reconstructs initial claim and reclaim epoch origins,
but excludes `issue_claim` and settlements. Its final comparison at `:4062` checks
effect identity and epoch only. `validate_effect_relations/1` at `:3841` accepts matching
claim/effect status without comparing it to retained issue history. Ledger provenance
at `:3889` permits any current authorized amount below the creation amount; it does not
derive open/closed status or balance movements. Reservation checks at `:3826` reconcile
aggregate holds with rows, and `:4232` compares columns with canonical state, but neither
binds current units and settlement status to their authenticated transitions.

The fresh required-behavior probes reproduce:

1. **Issued claim rewind, same epoch.** Admit and issue a real launch. Stop the Gateway,
   change claim and effect status from `issued` to `claimed`, and reservation status from
   `issued_unknown` to `reserved`, in both columns and canonical state. Keep revisions,
   epoch, request identity and all command rows untouched. Recovery reports `ready`.
   A new public `issue_claim` commits **accepted/issued** for the same claim/request.
   Its first issued authorization is still recorded, so this is a second authorization
   across an outcome that was never settled.
2. **Issued claim rewind, successor epoch.** Apply the same corruption, reopen under
   epoch B, then use the public quiescent reclaim A→B and issue APIs. Both commit accepted.
   Thus the failure does not depend on reusing the original Gateway epoch. A legitimate
   takeover cannot make an already-issued uncertain request eligible for replacement.
3. **Closed generation reopens.** Grant 20 units and close its generation through public
   commands. Change only its row/state to `open`, available 20, retired 0, preserving
   authorized units, revision and the retained close command/result. Recovery is ready.
   Public reservation, effect admission, claim and issue then all succeed from that
   formerly closed generation. Creation provenance and conservation remain true while
   the required no-new-issuance fence is lost.
4. **Issued hold shrinks without settlement.** Reserve four units, admit and issue.
   Change reservation units to one in its column/state, and change matching ledger held
   4→1 and available 16→19. Keep original reservation/admission/issue commands and results
   intact and create no receipt. Recovery is ready; its public ledger exposes three
   returned units despite the unresolved four-unit issued operation.

These are four manifestations of one incomplete derivation boundary, not four requests
for unrelated features. Reconstruct or validate legal protected transitions against retained
authenticated inputs, with exact immutable reservation identities and the resulting
claim/effect/lease/ledger state. Preserve intentional quarantine transitions and legitimate
late settlement. Matching carriers and creation bounds cannot establish that issue,
closure, refund or hold reduction occurred. This work belongs to FR-08A's protected
recovery boundary; FR-08B's domain replay and FR-19 physical recovery cannot supply it.

## Prior finding disposition and credited controls

| Family | Fresh disposition |
|---|---|
| F1; B2/B3/B5; R3 | Corrected tested cases. Five-deep chains include all ancestors in both claim and issue CAS. Omitting the oldest ancestor rejects incomplete; changing an interior ancestor rejects stale; fresh reads still reject quarantined ancestry before and after restart. A clean five-deep chain issues and settles after restart. |
| F2; B6; R4 | Exact origin defects corrected, family remains blocked by G1. Mutually forged root grant, child allocation, reset grant, effect predecessor, initial claim epoch and reclaim result/row carriers refuse. Two successive valid reclaims survive restarts and issue under the final epoch; stale prior-epoch takeover and issue reject. Current protected transitions remain unproved as above. |
| F3; B3; R2 | Explicit deadline policy corrected. Omission, null, string `500`, 499 and 501 reject against `[500]`; adding null to the allowlist still cannot admit null. Approved 500 admits, issues, settles and survives restart. A policy without a deadline list retains the existing optional-deadline behavior; actual elapsed-time enforcement remains FR-15a. |
| B1 | Corrected. Frozen report reproduces exactly; changed executable Gateway behavior with unchanged source causes all seven capabilities to become unavailable. |
| B2/B3; R2 | Maintained tests preserve epoch/control checks, finite non-start ordinal, wrong-dimension rejection, scope/profile binding and semantic duplicate prevention. G1 still undermines recovered issued authority. |
| B4; R6 | Public recursive close/reset, mixed open/closed descendants, root reset, same-ID retry and closed-parent no-refill controls pass. Recovery of closure remains G1. |
| B5; R5 | Request binding, same-request distinct observations, same/cross-claim observation-ID collision and restart quarantine preserve credit and avoid a storage fence in tested paths. |
| B7 | Unsupported/partial/corrupt migration markers refuse, supported rerun passes. Prior nonempty accepted-v9 migration and rollback-build semantic compatibility evidence remains an explicitly unproved follow-up. |
| B8/B9; R1 | Legacy/root modes remain exclusive. Proposal-only reservations hold no units. Invalid-control and overcommitted admission rejections roll back; precommit faults, lost replies and real child postcommit exit recovery pass. |

H0's immutable accepted record remains 4 passed/3 unavailable. Its historical provider
correctly gives 7 unavailable on current changed source. The FR-08A report is genuinely
bound to nine exercised source/loaded-BEAM identities and reproduces SHA-256
`7dbece07e252b5a7d45e07a48c87591b622f7c758e7fd1c0793af4a54f03f139`, with
7 passed and `ready=true`. Its bounded scenarios cannot override G1's substantive failure.
Accepted/selected/healthy pointers remain honestly absent.

## Executed verification

Pinned Elixir 1.20.3 / OTP 29.0.5 / ERTS 17.0.5 through the recorded `run.sh`, with
isolated build/runtime/temp roots under `/private/tmp/fr08a-acceptance.NzGQtp/`.
Focused checks reuse dependency sources; canonical CI restores locked dependencies into
fresh roots and checks the exact clean candidate before and after execution.

| Check | Actual result |
|---|---|
| Forced warnings-as-errors compile | exit 0; 108 project files |
| DurableStore and repair directories, legacy containment and effect checkpoint, seed 9311 | exit 0; 125 passed, including native xSync, modes, failpoints and loaded-code negative controls |
| Maintained final-review probes, seed 9302 | exit 0; 22 passed |
| Fresh expanded probe script, seed 9302 | exit 2; 37/41 passed; four failures above (22 maintained + 19 added variations) |
| Original independent recovery probes, seed 9283 | exit 0; 7 passed |
| Original changed-loaded-code probe | exit 0; changed behavior executes, source unchanged, all seven unavailable |
| Original real process-exit probe/child | exit 0; child exits 73 after protected commit; ambiguous owner fences; observed-exit recovery and same-ID retry retain one 3-unit grant |
| Exact hashes/manifests/report/H0/debt evidence script | exit 0 |
| Canonical `elixir ci/run.exs --output .../ci` | exit 0 on first fresh run; 572 passed, one optional Python/tiktoken recomputation excluded; dependency policy, compile, format, escript and clean-source postflight pass |
| Bounded ProcessGroup/Checks.Runner check, seed 9312 | exit 2; 17/19 passed, two inherited startup-observation races described below |
| Same unchanged ProcessGroup/Checks.Runner check, seed 0 | exit 2; 18/19 passed, one inherited observation race |
| `git diff --check fa636fb HEAD` | exit 0 |
| Frozen-candidate and staged-review documentation gate | exit 0; 80 passed each |

The first expanded run contained 38 cases and exposed issued rewind. Subsequent additions
test new-epoch takeover, closed-generation reopening and hold reduction. The final 41-case
run additionally asserts exact preservation of all command rows for the four failures.
No failed implementation assertion was weakened or repaired. The committed probe is
byte-identical to the final external `variations.exs`; it reads the maintained 22-case
artifact and appends its 19 variations in memory, leaving that artifact unchanged.

### Unrelated process-observation variability

The earlier candidate records a first CI failure where state changed `Rs`→`Ss` between
reads. The retained failed provenance identifies clean `408fd0` and test exit 2; its
immediate unchanged rerun passed. Source inspection finds an exact whole-map pinned
identity comparison at `checks/runner_test.exs:130`, which includes transient process
state. ProcessGroup, Checks.Runner and both associated tests have no diff from `fa636fb`.

This review's full canonical run passes. The bounded follow-up exposes related startup
observation variability: the injected-signal-error test sees `stale_identity` before its
fake kill call; the argv-marker test sees transient `(python3)` instead of final argv.
The unchanged retry retains the former failure and clears the latter. The helper's two
matching observations do not establish that process startup is complete. These are
inherited test/process-observation issues, not an FR-08A source regression, and do not
explain G1. The exact earlier Rs→Ss event was not independently reproduced. No process
test or runtime code was changed, and this review does not certify that flake repaired.

## Reproduction, hashes and limits

From candidate `foundry/`, using the pinned isolated environment after compilation:

```sh
mix run --no-start --no-compile docs/fr-08/fr08a-acceptance-review-probes.exs
```

It intentionally asserts required behavior and exits 2 at this candidate. Artifacts
remain under `/private/tmp/fr08a-acceptance.NzGQtp/`:

| Artifact | SHA-256 |
|---|---|
| `run.sh` | `04e46fcc6a959930e915fecb9b29a69fbb517f011f6e996104d4527ddfa79fca` |
| `variations.exs` / committed probe | `f2261d351f95b829d02d6c32d4265874dfe79e2fb16c938bf2d1aaae12b4980d` |
| `variations-final.log` | `c6c2cd4ec54f4097f4df02ee569808e085d163274f5d40e7dc92c24553f6e1c0` |
| `maintained.log` | `7d18498774c7c61572edcc2b91daeb431f06490123c4bccdcdd301879758036a` |
| `binding.log` | `149cb573e1c47a8b93816c5f8d039d1ea98780c980fccb49ff82dcd78dd502d7` |
| `recovery.log` | `337f8922ad0850ef1d0d566336f73dfa55f3c0153eaed90f1e14013f458b4fb7` |
| `crash.log` | `886ee564bbff7b65bc213e32bee752cd62712199dd518f2781e0b017b0d2c222` |
| `evidence.exs` | `66dc07d66df9703412dea638ceb993b4d1df3c4f22a24d2e9e552649b63c8a48` |
| `evidence.log` | `ad88bef04f03221377505d941112de95dd5eac11bf334dfe71d27e1dc4eb350b` |
| `ci/provenance.json` | `dfcc7e69285bc5f34fd39a37f879ea8ef88d55d2a30310612cb5526122328beb` |
| `process-group.log` | `2ad0e644053b7e86c766cac877370f9ab028d8c6ff81419030c86163f710ea18` |
| `process-group-retry.log` | `1545275f2219ba1855a5045a41f5abbfc3e7ac54de80bae3d070a6089c49fca7` |

All seven format-debt identities independently match the current source and CI provenance.
The inherited future debt-error enforcement gap remains separate. Other prior suggestions
remain nonempty migration/rollback evidence, dimension/objective-envelope and reset
grant/transfer semantics, and bounded public summaries versus controlled raw evidence.

G1 requires correction and renewed independent review before integration. This review
does not prove FR-08B all-ingress/domain replay, FR-15a principal/channel isolation or
elapsed-time enforcement, FR-18 public DTO/redaction, FR-19 physical maintenance, FR-17
pointer production/activation or FR-22 whole-lifecycle acceptance. No provider or daemon
was launched and no integration or activation is authorized by a green component gate.
