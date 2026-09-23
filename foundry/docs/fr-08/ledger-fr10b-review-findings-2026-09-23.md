# Ledger L1–L4 and FR-10 B fixes — independent review findings

**Reviewer:** Fable 5.1 (`claude-fable-5-1`), fresh agent, read-only. **Subjects:** `3cb470e6`
(L1), `13650882` (FR-10 B), `5f021010` (L2), `5b701a57` (L3), `d67eeac2` (L4), fixing the
states in [the ledger model](../../spec/ledger/README.md) and
[FR-10 finding B](../../spec/fr10/README.md) that committed and then failed the restart check.

| Commit | Verdict |
|---|---|
| L1, FR-10 B, L2, L3 | PASS |
| L4 | PASS WITH CHANGES |

**What was attacked and held.** FR-10 B's live predicate (`receipts != []`) and its replay
predicate (`claim.status != "issued"`) agree on every reachable history, because a claim is
`issued` exactly when it has no receipts. A second `unknown` on an `unknown` claim is now
stored; no consumer relied on the old quarantine. Finding C stays open: known-vs-known still
quarantines. L1 refuses only `claimed`/`cancelled` claims, which were never issued, so no
real receipt can race the cancel. L2: the contract charges one step to one dimension of one
ledger, and the kernel builds one `reserve` per launch. L3: no flow reserves after its effect
exists. L4's old `cancel_effect` records without `ledgers` still pass (the schema keys are
optional).

**Finding (high, fixed).** L4 was placed on the direct caller only. `set_control`
`cancel_requested` cascades through the same `cancel_effect` (`fence_control_descendants`),
released holds, and recorded no ledger snapshot, so an accepted operator cancel over a
pending or claimed effect left a store that refused to reopen
(`{:protected_corrupt, "root_ledgers", :transition}`). Fixed: `set_control` returns the
cascaded ledgers (last snapshot per ledger) and its restart schema declares them. Probe:
`set_control_cascade_restart_probe_test.exs`; red control 0/2 with the ledgers dropped.

**Corrections.** The ledger README pinned the L2/L3 fixes to worktree SHAs; it now names the
branch commits.
