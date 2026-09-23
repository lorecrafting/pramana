# Core boundary F1/F2 fix — independent review findings

**Reviewer:** Fable 5.1 (`claude-fable-5-1`), fresh agent, read-only. **Subject:** `c82e2076`
(bound-fact slots come only from a binding; proposals carry no slot-typed event), for
findings F1/F2 of the [core boundary model](../../spec/core_boundary/README.md).
**Verdict:** PASS WITH CHANGES.

| # | Severity | Finding | Resolution |
|---|---|---|---|
| 1 | Medium | A plan staging `settle_claim(non_started)` with **no** binding and no slot-typed event still committed under `unconditional_v1`: Core settled the claim, the domain recorded no settlement, and the controller chose the branch. The model's `stepFixed` refuses this input. | Gateway `plan_describes_operations/2` requires a `nonstart_settlement_v1` binding at the ordinal of every staged non-start (`:nonstart_settlement_unbound`). Test "a staged non-start must bind its settlement"; PLAN13 now meets the same refusal at ingress. Red control: guard removed, both fail. |
| 2 | Low | "rejects a marker carried by an event of another type" used `control_changed`, which now fails on its own empty slot, so the misplaced-marker path went untested. | Uses `check_recorded` (no slot) and expects `:binding_slot_absent` again. |
| 3 | Info | `stream_sealed.last_accepted_sequence` mirrors `seal_inbox`'s `sealed_sequence` and is read into the execution with no binding; not in the C3 list. | Open: recorded here for the enforcement matrix; out of this fix's scope. |

Enumerations the reviewer attacked and found to hold: the only `INSERT INTO events` is reached
through `commit_bundle` (after `normalize_candidate/1`) or the atomic path (after
`normalize_candidate/1` or `TransitionPlan.bind/3`); a literal copy outside the bound slot is
never read as authoritative. Commit-message correction: seven existing tests changed, not
five; three of them changed only the expected atom.
