# FR-08B subcommit 3 batch: independent review findings

**Reviewer:** Fable 5.1 (`claude-fable-5-1`), a fresh agent working read-only. **Subject:**
the batch ending at `8867cfe2`, made up of the
[reviewer-independence check](FR08B-REVIEWER-INDEPENDENCE-DESIGN-2026-09-23.md), the
subcommit 2 fixes and subcommit 3.

## Verdicts

| Part | Verdict |
|---|---|
| Reviewer independence | PASS WITH CHANGES |
| Subcommit 2 fixes | PASS WITH CHANGES (documentation) |
| Subcommit 3 | BLOCKER (S1) |

## Findings

| # | Severity | Finding | Resolution |
|---|---|---|---|
| I1 | Medium, required | Core read `independent_of_roles` only from the policy the new operation names, at its current revision. It never read the revisions the attempt's existing effects pinned. Three escapes were admitted. **A1:** dev-1 by principal-A under the pairing, then `set_policy` without the key (rev 1), then rev-1 by principal-A at `policy_revision` 1. **A2:** rev-1 under a second `policy_id` that has no key. **A4:** dev-1 and rev-1 admitted, the policy dropped, then principal-A's first `append_inbox` to execution-rev-1. | Fixed in `49485dc3`. The pairings are now the union over the new operation's policy and every pinned `(policy_id, policy_revision)` in the attempt, read from `root_policy_history`. A1, A2 and A4 are probe tests in `review_independence_test.exs`, and each is refused with `principal_not_independent`. Red control: with `related_roles([policy], role)`, all three fail. |
| I2 | Recorded | The scope is the controller-supplied `(ticket_id, attempt_id)`. `attempt_open` refuses only closed attempts, so Core admits a reviewer relabelled into another attempt. | Recorded as a limit in the design doc and in the enforcement-matrix row. "Exact candidate" rests on the kernel's `require_active_attempt` in `review_planned`. FR-13 must re-check attempt identity at acceptance. |
| I3 | Recorded | The declared read sets of `append_inbox` and `create_effect` omit the sibling effects, inboxes and policy history they now read. | Recorded as a limit in the design doc and in the matrix row. The reads happen inside the commit transaction, so none is stale. The gap is one of read-set honesty. |
| I4 | — | Not restated here. | No resolution was assigned in this batch. Open. |
| I5 | — | Not restated here. | By the kernel fix commit "reviewer allocation decisions CAS-bind the ledger". |
| S1 | Blocker | Not restated here. | By the kernel fix commit "reviewer allocation decisions CAS-bind the ledger". |
| S1b | — | Not restated here. | By the same kernel fix commit. |
| S5 | — | Not restated here. | By the same kernel fix commit. |
| S8 | — | Not restated here. | By the same kernel fix commit. |
| sc2-doc SHAs | Documentation | Commit SHAs cited in the subcommit 2 documentation. | By the same kernel fix commit. |

This record was written by the agent that resolved I1 to I3. It gives the detail of those
three only. The kernel fix commit's message and diff carry the detail of the others.
