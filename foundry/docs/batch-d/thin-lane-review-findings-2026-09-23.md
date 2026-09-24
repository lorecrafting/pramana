# Thin lane and hardening — independent review findings

**Reviewer:** Fable 5.1 (`claude-fable-5-1`), fresh agent, read-only, at `c0466058`.
**Subject:** the [thin lane](THIN-LANE-DESIGN-2026-09-23.md) (work packet, manual backend,
server, CLI, restart drill) and the day's hardening (decide/3 binds the allocation key; the
reopen property and its fixes F1, F2, L1–L4).

| Part | Verdict |
|---|---|
| A. Lane | PASS WITH CHANGES |
| B. Hardening | PASS WITH CHANGES (code passes; the evidence claim was weaker than stated) |

| # | Severity | Finding | Resolution |
|---|---|---|---|
| A1 | Medium-high | At the receipt / second-commit split, `settle_root` returned idempotent on a committed command id without comparing the payload. After a crash, a rerun could freeze candidate B on a receipt attesting A, or record `rejected` on an `approved` receipt. | A rerun must attest the stored receipt, or it is refused as `receipt_mismatch`; the second commit takes the receipt's candidate and verdict. Drill tests rerun with different argv. |
| A2 | Low | The design claimed an unset `allowed_profiles` passes only `unspecified`; Core defaults it to the request's own profile. | Design corrected; the seed pins `["unspecified"]`. |
| A3 | Low | A seed interrupted after the policy was unrecoverable, and `:idempotent` read as rejected. | Each seed operation is individually idempotent; a restart completes a partial seed. |
| A4 | Low | `packet --principal B` printed A's open execution with ok. | Refused. |
| A5 | Low | `checks_started.policy_empty` was a literal. | Derived from the policy's check set at submit. |
| B1 | Medium | The generator's `set_control` arm was unreachable, and `return_allocation` was never accepted (0 of 46), so "green at 1500 runs" said nothing about returns. | Arms reordered; a delegate-then-return round trip; the test fails if any operation type is never accepted in the default run (red control: without the round trip, `return_allocation` is reported). Green at 1500 runs with returns accepted. |

**Held, per the reviewer:** the non-launch test is transitive and red-controlled; recovery mode
blocks every write and evidence cannot evict a live owner; launch retries cannot double-issue;
the lane store is disjoint and off by default; the 86c16e45, 676cd5b7, def4a9b7, 0bcc8dfc,
8a0bc471 and f201adc0 fixes are sound; no accepted risk A1–A6 was widened.

**Noted, not changed:** `Server.context/0` hands the protected capability to any process in the
node (a convention, not enforced); the `ctx[:work_packet]` module override is test-only.
