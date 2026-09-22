# Review briefing — `integration_issued?`, the in-flight predicate

**Candidate:** `b5077625`, on `repair/fr08b-kernel`, parent `f0609c38`.
**Outcome: BLOCKed, then corrected.** The review found the `closed`-is-unissued argument below
false — `worker_closed` is not behind `require_no_ref_receipt`, so a landed effect can be
closed and `integration_issued?` reads false on it. Behaviour was safe by
`require_receipt_for_integration` sitting earlier in the `with` chain, which the change cited
nowhere and nothing pinned. Corrected in the follow-up commit; item 1 below is kept verbatim as
the claim that was wrong, because it is the record of what the review was aimed at.
**Scope:** one kernel predicate, one deleted qualifier, one test converted to a loop, one
test added, one log entry plus a correction to an earlier one. Nothing else.

Read the diff with `git show b5077625`. Do **not** run the full gate — it is already green
below and costs five minutes. Do **not** launch background work. Deliver a verdict from what
you have.

## What the change claims

`integration_issued?` scanned every integration execution for `lifecycle != "pending"`, which
answers "has this attempt ever held an integration effect". The claim is that R4 row :484
("ready_to_integrate/integrating; accepted base moved **before issuance**") asks whether it
holds one *now*, and that the old predicate was already wrong before any other delta: after
the bounded retry R4 requires, the attempt holds I1 `closed` beside I2 `pending`, and
`attempt_settled(superseded_base)` was refused `:integration_already_issued` although the
current effect is unissued.

It now tests membership of `@issued_lifecycles ~w(starting running closing unknown)`.

## The four things worth attacking

1. **Is `closed` safely on the unissued side?** The argument is an enumeration: an integration
   execution reaches `closed` through exactly two call sites, `integration_settled` (the
   non-start settlement) and `worker_closed` on the `no_ref_change` retry path, and
   `require_no_ref_receipt` refuses both once a receipt exists — so a closed integration
   execution never carries an effect that landed. If there is a third route to `closed`, or a
   state where a landed effect has no recorded receipt, the predicate is wrong in the
   dangerous direction. Check this by grepping `close_execution` call sites, not by reading
   the claim.
2. **Is `unknown` correctly on the issued side?** The warrant cited is
   `WORKFLOW-CONTRACT.md:573-576` (`reserved → issued_unknown`, "unavailable for reuse") and
   the R4 integration row's "unknown blocks reconciliation". Verify the citation says what the
   comment says it says. The repo has shipped an over-read citation before, on this exact row.
3. **The deleted `attempt["phase"] == "integrating"` qualifier.** It is deleted, and rule 6 on
   it is recorded as **green** — restoring it turns no test red. The claim is that it is
   redundant rather than merely false, because attempt phase `ready_to_integrate` has exactly
   two writers (`kernel.ex:821` `reviewer_closed` on an approved verdict, `kernel.ex:878`
   `integration_settled`) and neither can coexist with a live integration execution. If you can
   reach attempt phase `ready_to_integrate` holding a `starting`/`running`/`closing`/`unknown`
   integration execution, the deletion changes behaviour and is untested. Also worth asking:
   should an unwitnessed deletion ship at all, or should the qualifier stay until the state is
   reachable?
4. **Is the new predicate's own denominator honest?** The in-flight test loops four lifecycles
   and each has a red control. The retry test has one. Nothing else in the suite pins the
   predicate. Say so if that is thin.

## Exact numbers to reproduce

- `mix test test/pramana_foundry/workflow/kernel_test.exs` → **115 passed**.
- Rule 6, each reversal applied and undone by exact string replacement in
  `lib/pramana_foundry/workflow/kernel.ex`:

  | Neutralisation | Expected |
  |---|---|
  | `execution["lifecycle"] in @issued_lifecycles` → `execution["lifecycle"] != "pending"` | red, 114/115 |
  | drop `starting` from `@issued_lifecycles` | red, 114/115 |
  | drop `running` | red, 114/115 |
  | drop `closing` | red, 114/115 |
  | drop `unknown` | red, 114/115 |
  | `if integration_issued?(attempt),` → `if attempt["phase"] == "integrating" and integration_issued?(attempt),` | **green**, 115 |

- Full gate on `b5077625`, clean tree: `result: passed`, all six steps exit 0,
  **924 passed, 13 skipped, 1 excluded**, suite 293.6s.
- No mutation sweep was run. The claim is that none is owed: the sweep's population is every
  non-definition `require_*(` call, `integration_issued?` is not one, and the only `require_`
  string in the diff is inside a comment. Verify with `git show b5077625 | grep require_`.

## What this does not touch

B3 (row :467's unguarded `no pause/drain/cancel` conjuncts) is subcommit 2's and is
deliberately untouched. EV-3, EV-6, EV-2 and EV-1 are unstarted. `integration_already_issued`
remains classified deeper-than-the-bound in guard reachability, not genuinely unreachable, and
that classification is unchanged by this delta.
