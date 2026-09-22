# `apply/2` closure (253d9467): independent review findings and dispositions

Reviewer: a fresh Fable agent, not a fork, delta only (253d9467 against 1c02b6a5), 40-minute
budget, eight enumerations named up front. Verdict: **PASS**, with one FIX to land before the
next candidate. Dispositions below are the integrating session's; the findings are the
reviewer's, kept verbatim in substance.

| # | severity | finding | disposition |
|---|---|---|---|
| 1 | FIX | `@validation` in `r4_guard_reachability_test.exs` is an excuse list, not an absence assertion: atoms in it are only subtracted from `never`, nothing asserts they are absent from `fired`. Before 253d9467 a handler bug producing a malformed post-state on a proposer-reachable path raised the harness's shape assertion inside the depth-7 search; after it the kernel refuses, `KernelSearch.expand/5` treats any `{:error, _}` as a pruned non-edge, and the reachability test excuses the atom. The deleted assertion carried information the kernel check does not: an assertion fails loudly, a refusal fails silently. | **Landed.** `refute MapSet.member?(fired, :malformed_post_state)` in the first reachability test, with a message naming what to do. |
| 2 | FIX | The "by construction" wording ("with well-formed payloads no accepted transition can produce a malformed state") is bounded evidence, not an inductive argument, and rule 3 says record it as such. | **Landed.** Comment rewritten: the search at depth 7 is *required* not to provoke it, and says why the refute exists. |
| 3 | NOTE | `state.ex` module doc still describes `apply/2` refusing on input only. | **Landed.** One sentence added. |
| 4 | NOTE | EV-3's "Resolved" block in the tickets doc still says the harness asserts both validators. | **Landed.** Pointer clause added; history kept. |
| 5 | NOTE | `bin/closure_cost.exs` reproduces 16.7% but now times a second post-check against a kernel that already includes the first; without saying so the number will be quoted as the incremental cost. | **Landed.** Header paragraph added. |

Enumerations attacked and found clean, per the reviewer: the bare `next = commit(...)` match
inside the `with` (total, nothing written on refusal, `apply/2` has no production caller outside
the kernel directory); `commit/4` output is exactly what the kernel returns; `:malformed_post_state`
is constructed at one site and the `reason: nil` control proves every earlier guard passes from the
same state; the only `{:error, _}` matches in tests are the two totality probes, and the
`{:error, reason} -> flunk` branches in `kernel_test.exs` and `r4_coverage_test.exs` are where a
legitimate transition refused by the new guard would fail loudly; the `apply_unchecked(` pin
matches the two remaining sites exactly; no doc describes the defect as open; the probe reads 0
with the bound line unchanged.

What the review did not do: run the sweep (forbidden to it; the integrating session ran it on
the one site, caught) or the gate (passed at 253d9467: 952 passed, 13 skipped, 1 excluded, six
commands, dirty_paths empty, format_debt six all matched).
