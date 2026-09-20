# FR-08A fresh final critical review — BLOCKER

Reviewed 2026-09-19 (Hawaii), Astra-high, independently of implementation. **BLOCKER.**
The maintained 15 rereview probes now pass, and canonical CI passes at the frozen
candidate. Independent variations still reproduce unsafe successor issuance and
acceptance of invented protected authority during recovery. An omitted deadline also
bypasses the new deadline policy predicate. The seven passing report rows bind the
examined implementation correctly, but do not establish FR-08A completion or FR-08B readiness.

## Exact subject and review boundary

- Frozen candidate: `e80b6f0b50de468d178260741b3dc8a53b941ee5`, tree
  `48cf199c0fcfe960b02c1f10d632aae582f86371`.
- Corrected core: `066e29e1b50535759730b64583876b466629195b`, tree
  `ca0339489e051f3c8ae6e0315bdd0139771b21de`.
- Rebound loaded-code evidence: `ea8332b37a87887a28d29f1fb7bfe0504cc0b37e`.
- Bounded format-debt identity correction: `8688b7a3f5079e4a2ed154d681f281f878003271`,
  tree `5d86c971eb1fe2179611705910f02abcf2146e56`.
- Baseline: `fa636fb592eacf4ebd31b72fa377b0a86a6d3e3e`.
- Branch/worktree: `repair/fr08a-protected-primitives`, `/private/tmp/pramana-fr08a`.

I read the shared workflow, Foundry orientation/strategy, shared completion and
H0/FR-08A acceptance, R1/R4a/R5 and recovery contract, H0 candidate/reviews, both prior
FR-08A critical reviews, current candidate, changed source and relevant tests. This
review independently verifies all 14 candidate manifest paths; all 12 distinct H0 paths
(13 matching lines) against frozen `4c8734c6473be97da77f299bc4b42cd720cdf0b6`; and all
56 accepted-FR-07 v9 paths against `af0c51b4682c50080e67194dd853fbaa1eebace7`.

The worktree remained clean at the frozen candidate through runtime verification and
canonical CI. Subsequent edits consist only of this review, its
[reproducible probes](fr08a-final-review-probes.exs), and catalog routing. No implementation,
maintained test, frozen candidate/report, shared plan, implementation log, provider setting,
daemon, push or integration was changed or performed.

All positive authority scenarios use public Gateway APIs. Recovery corruption fixtures
modify only disposable SQLite stores after stopping their Gateway. They are negative
logical-corruption controls; they do not claim administrator-resistant cryptography,
actual channel isolation, provider behavior or physical storage recovery.

## Blocking findings

### F1 — Reconciliation fences only the immediate predecessor, not its owner chain

`protected_primitives.ex:2846` checks only `effect.predecessor_effect_id`; the derived
claim/issue dependencies at `:1912` likewise include only that immediate predecessor.
The correction passes the rereview's one-predecessor case, but not a longer valid chain.

The public probe uses an explicit non-start allowance of 4. It issues ordinal 0, settles
attributable non-start, issues ordinal 1 with the correct predecessor, settles its
attributable non-start, and admits ordinal 2 referencing ordinal 1. A contradictory
delivered-success observation then places ordinal 0 in `reconciliation_required`.
Despite that outstanding conflict for the same `T:A:developer` owner, ordinal 2 is
both claimed and issued **accepted**. The fixture uses the same policy, control, owner
and generation throughout; no arbitrary replacement owner is involved.

R5 requires conflicting terminal evidence to quarantine the owner; R1 forbids a
replacement while the earlier outcome remains uncertain. Recheck the entire relevant
owner lineage or a protected owner quarantine fact at claim and immediately before
issue, and include that authority in the complete read set. Checking only the adjacent
effect leaves every deeper successor outside the fence. This continues original B2/B3/B5
and rereview R3; it is not a request for FR-08B scheduling implementation.

### F2 — Recovery still trusts derived carriers that disagree with authenticated input

The new ledger/effect validators reject the exact prior 2000-unit and issuer fixtures.
They do not reconstruct the complete protected authority or bind it to original commands.
Three independent negative fixtures reopen **ready**:

1. After valid admission, change only the effect's canonical state to
   `phase_generation=42` and `operation_ordinal=97`. Keep the original admission command,
   result and request digest unchanged. The public effect now reports the invented values.
   `validate_effect_command_provenance/1` at `:3888` checks issuer, request digest, request
   ID, role, profile and deadline, but omits generation/ordinal/predecessor and several
   other immutable admission fields. `validate_effect_states/1` rebuilds these fields
   from the same state it is supposed to validate.
2. Claim under epoch A, stop cleanly, change the claim's epoch column and canonical state
   to epoch B, leaving the authenticated claim command/result unchanged. Reopen under
   epoch B: the store is ready and `issue_claim` returns **accepted/issued** without any
   quiescent reclaim command. `validate_claim_states/1` at `:4078` checks column/state
   equality, not the claim/reclaim provenance establishing the epoch. This bypasses the
   corrected takeover predicate through recovery.
3. Grant 20 units, then change the ledger's columns/state and its retained accepted
   result to 2000 units. Keep the authenticated canonical `grant_ledger` request and its
   digest unchanged at **20**. Reopen is ready and the public ledger exposes 2000
   available units. `validate_ledger_result_provenance/1` at `:3847` trusts a revision-zero
   fact found recursively in a result; `validate_root_commands/1` at `:3553` validates
   result envelope identity but does not derive that fact from the original grant request.
   Mutually consistent derived rows/results therefore invent authority.

These fixtures preserve canonical encoding and the relevant row carriers. They do not
rewrite the authenticated input log. Validate derived facts against that retained input
and the legal transitions establishing them, including claim epoch changes and complete
immutable effect identity. Conservation and matching carriers alone do not prove a
grant or reclaim occurred. This continues B6 and rereview R4.

### F3 — Omitting a deadline bypasses the new protected deadline predicate

`deadline_allowed?/2` at `protected_primitives.ex:2634` accepts `nil` unconditionally.
With a policy explicitly declaring `allowed_deadlines=[500]`, an effect request that
omits `deadline` is admitted, claimed and issued accepted; its retained deadline is null.
The independent probe otherwise uses the approved role/profile/scope and valid budget.

The rereview's combined unapproved-profile/expired-deadline probe now passes because
the profile is rejected. It does not establish mandatory deadline binding. The protected
boundary must derive or require the fixed bounded deadline permitted by policy and
retain it in the admitted assignment/effect. Actual elapsed-time enforcement remains
FR-15a; accepting an unbounded identity is the protected admission problem here.
This is the remaining deadline component of B3/rereview R2.

## Prior finding disposition and credited controls

| Prior family | Fresh result at this candidate |
|---|---|
| B1: loaded-code/evidence identity | Corrected. Nine module source/loaded-BEAM identities match; changed executable Gateway behavior with unchanged source makes all seven capabilities unavailable. |
| B2: epoch, controls and complete read set | Normal old-epoch issue rejects; explicit quiescent reclaim and cancellation tests pass. F1 and F2 retain owner/epoch authority blockers. |
| B3: semantic identity and dimensions | Live generation-99 and ordinal-zero reuse reject, as do wrong dimension, unapproved profile and mismatched ticket scope. F3 leaves deadline admission incomplete; F2 leaves recovered semantic identity unbound. |
| B4: recursive close/reset | Corrected tested cases. All-open and mixed closed/open closure pass; root reset with a closed child survives restart and exact same-ID retry without regrant. Closed-parent return remains rejected. |
| B5: receipt identity/reconciliation | Original request mismatch and observation-ID collisions now reject without a store fence. Distinct observations reconcile the same immutable request. Independent collision/restart control preserves one held unit and the durable conflicting-evidence result. Owner quarantine remains F1. |
| B6: recovery provenance | Original seven recovery probes pass, including policy/history, pointers and migration damage. F2 reproduces remaining complete-provenance failures. |
| B7: migration | Future/partial/corrupt protected markers refuse; supported rerun and existing schema tests pass. Nonempty accepted-v9 migration/rollback-build compatibility remains an explicitly unproved follow-up. |
| B8: one protected truth and atomic admission | Legacy/root authority mode tests pass. Proposed reservations hold no units. The overcommitted admission rejection now rolls back all operation writes. |
| B9: durable rejection and root faults | Invalid-control and overcommitted admission reject with no partial authority mutation; restart stays ready. Malformed input/actor/lease conflict checks, precommit rollback, postcommit lost-reply retry and real process-exit recovery pass. |

The six rereview families therefore have this disposition: **R1 corrected in the tested
paths; R2 partially corrected, blocked by F3; R3 blocked by F1; R4 blocked by F2;
R5 corrected in the tested collision/restart paths; R6 corrected in the tested recursive
close/reset paths.** The new implementation rolls ordinary semantic rejection back before
retaining its durable result; intentional receipt quarantine has its own explicit commit
branch. No partial mutation was reproduced in the rejection variations.

The report reproduces byte-for-byte with SHA-256
`1fae01a518c97149894018eb430abdd299111245f5f43a7f3b5ccb802da680be` and records
7 passed, 0 failed, 0 unavailable, `ready=true`. Its source/BEAM binding is real and its
positive probes execute real transactions. The result remains a bounded scenario report:
the failures above prohibit treating that ready label as substantive full-contract
acceptance. H0's historical provider correctly reports 7 unavailable on the changed
current implementation; the immutable accepted H0 record remains 4 pass/3 unavailable.

## Executed verification

Pinned Elixir **1.20.3 / OTP 29.0.5 / ERTS 17.0.5**, using the recorded `run.sh` and
isolated build/runtime/temp roots under `/private/tmp/fr08a-final-review.lTFoGo/`.
Focused checks reuse existing dependency sources. Canonical CI independently restores
locked dependencies into fresh roots and verifies the exact clean source before and after.

| Check | Actual result |
|---|---|
| `mix compile --force --warnings-as-errors` | exit 0; 108 project files |
| DurableStore and repair directories plus legacy persistence containment, seed 9301 | exit 0; 122 passed, including native xSync, mode/failpoint and loaded-code negative controls |
| Correct checkpoint test path, seed 9303 | exit 0; 3 passed |
| Maintained 15 rereview probes, seed 9293 | exit 0; 15 passed |
| Extended independent probes, seed 9302 | exit 2; 17/22 passed, five failures grouped as F1–F3 |
| Original recovery probes, seed 9283 | exit 0; 7 passed |
| Original loaded-code negative probe | exit 0; changed loaded Gateway refuses all seven capabilities |
| Original process-exit probe and real child | exit 0; child exits 73 after protected commit, ambiguous owner fences, observed-exit recovery and same-ID retry preserve one 3-unit grant |
| Frozen report/H0/debt evidence script and exact manifests | exit 0 |
| Canonical `elixir ci/run.exs --output .../ci` | exit 0; 572 passed, 1 optional Python/tiktoken recomputation excluded; dependency policy, compile, formatting, escript and clean-source postflight pass |
| `git diff --check fa636fb HEAD` | exit 0 |
| Frozen and staged-review `elixir bin/check_docs.exs` | exit 0; 80 passed each |

The initial focused invocation also named nonexistent `effect_checkpoint_test.exs`;
the actual `effects/checkpoint_test.exs` was run separately as recorded above. During
probe authoring, the root-reset control initially used the wrong field names and returned
`invalid_protected_request`; correcting it to the public `old_generation` and explicit
null-parent fields produces the passing reset/retry control. Neither setup mistake is
counted as an implementation failure. Final probe results are the 22-test run above.

The bounded format-debt commit changes only the seven recorded SHA-256 values. All seven
now independently match actual source bytes and canonical provenance, without formatting
those unrelated files. Exact matching values are recorded in `evidence.log` and
`ci/provenance.json`; there is no `format_debt.error` in this run. This establishes the
current identities, not a repair of the inherited runner behavior that catches a future
identity error as metadata while omitting debt paths from formatting.

## Reproducible evidence and separate suggestions

The committed [review probe](fr08a-final-review-probes.exs) is byte-identical to external
`variations.exs`. It retains the original 15 probes and adds seven variations: five
required-behavior failures and two positive controls. Run from `foundry/` in the pinned,
isolated test environment after compilation:

```sh
mix run --no-start --no-compile docs/fr-08/fr08a-final-review-probes.exs
```

Artifacts remain under `/private/tmp/fr08a-final-review.lTFoGo/`:

| Artifact | SHA-256 |
|---|---|
| `run.sh` | `ba6b8c2f802694de20371914ffbdb9b384ac89eff4db0f7b7f674002650e53d8` |
| `variations.exs` / committed probe | `ba29f581504c44494777b7ec5128fbed8a6bf71049bfaa457ec8371079af3bc5` |
| `variations.log` | `d264d24818f66b3ecfc9e0396a4c218a149252aa4dea03d19f1985be64d92f8d` |
| `maintained.log` | `b74c398c05b48e7bfb6b4297995c6806a8c04478e8b6052361b014d356973e99` |
| `binding.log` | `e867c659c78a4c69966e5bd0d03b9b6f25fab2285757738752b70f39eb88d7d8` |
| `recovery.log` | `19a3bfd11d3069231e3d67c00661675932e9d1966c2eeb5094408290b86351d9` |
| `crash.log` | `8cc1da19325bf7446f52dc33f6ac046ac50f5331bd416049f5fbf1ba83d7931f` |
| `evidence.exs` | `cafbeafc7941cf4698d90eebcba52acff33e610cff7814a52fb79cfe3e2a297e` |
| `evidence.log` | `3bf2711a8376adf345c02b6e1c859dc515747ddbb14340a2bbc97450acd98263` |
| `ci/provenance.json` | `ccc9d7612f51bea9fb1633f965149d3fe47e01917b5d56fb995f7080bb7fd069` |

F1–F3 are blockers. Separate suggestions retain the prior nonempty migration and rollback
compatibility evidence, explicit dimension/objective-envelope and root-reset grant/transfer
semantics, bounded query summaries/raw-evidence access, and the inherited CI debt-error
enforcement correction. These follow-ups do not substitute for correcting the blockers.

No claim extends to FR-08B all-ingress/domain replay, FR-15aB actual principal/channel
isolation and elapsed-time enforcement, FR-18 public observations/redaction, FR-19 physical
maintenance/recovery, FR-17 pointer production/activation or FR-22 whole-lifecycle acceptance.
Pointers remain honestly absent; FR-18A may represent that absence without waiting for
FR-17. Preserve accepted H0/FR-07 evidence, correct these protected invariants, refreeze,
and obtain renewed independent critical review before integration or FR-08B.
