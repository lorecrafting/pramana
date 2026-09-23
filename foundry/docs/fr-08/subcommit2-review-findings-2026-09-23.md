# FR-08B subcommit 2 (`decide/3`, developer) — independent review findings

**Reviewer:** Fable 5.1 (`claude-fable-5-1`), fresh agent, read-only. **Subject:** subcommit 2
as built, commits 2–6 (`147451dc`, `c6610489`, `80b0a2e9`, `ebd78c18`, `356b3265`) at
`3ca453e5`, against the [design](FR08B-SUBCOMMIT2-DECIDE-DESIGN-2026-09-23.md).
**Verdict:** PASS WITH CHANGES. F1 applied as operator-approved protected maintenance.

| # | Severity | Finding | Resolution |
|---|---|---|---|
| F1 | Medium, required | The exhaustion plan commits a terminal outcome on an un-CAS'd allocation read. It stages only `close_attempt`, whose Core read set is closure, effect and reservation keys. The command stated no ledger key, and a command-level `ledger/` key reads the legacy `ledger_generations` table, not `root_ledgers`. Failing input: seed(3,2); launch and non-start; delegate the ledger away (available 0); decide (exhaustion); return a unit before submit; the submit committed `exhausted`. | `93a20360`. Core: a command-level `root_ledger/<base64url id>/<generation>` key reads `root_ledgers` (`record_codec.ex` `decode_revision_key/1`, `authority.ex` `read({:revision, {:root_ledger, …}})`). `ledger/` keeps its legacy meaning, because it is still live: the `protected.ledger_generations` bundle path in `gateway.ex`, `authority_test.exs` and `review_corrections_test.exs` use it. Kernel: `Plan.root_ledger_key/2`; `developer.ex` `allocation/5` states the ledger revision on the exhaustion plan. The launch plan needs no key, because `reserve` carries the ledger in its own read set. Test: `decide_e2e_test.exs` "allocation returned after the exhaustion decision refuses it" (`revision_conflict`). Red control: without the stated key the same submit commits `accepted`. Matrix rows "CAS on every read revision" and "Exhaustion choice" updated. |
| F2 | Low | `gateway.ex` `expected_domain_revision/1`'s `_several -> :ambiguous` arm (two declared reads written) had no test. | `37e0fa52`: `domain_read_check_test.exs` "a plan writing two declared reads has no expected_domain_revision". Red control: with the arm mapped to `1`, the plan commits. |
| F3 | Low | `Plan.input(_, :atom)` refusals in `kernel.ex` were invisible to `KernelSearch.reasons_in/1`, which scanned only `{:error, :x}` and `ok_or(…:x)`. | `37e0fa52`: a third spelling, `Plan.input(…, :x)`, plus a fixture line in the extractor's red control. `invalid_command` and `unsupported_command` are exempted by name (`@decide` in `r4_guard_reachability_test.exs`). Red control: without the exemption, both are reported as undocumented. |
| F4 | Low | `Plan.expected_revisions/2`'s facts arm and `protected_key/2` had no lib caller. | `protected_key/2` is deleted (`93a20360`). The facts arm now carries the F1 root ledger key (keys must start with `root_ledger/`), so it has a caller. |
| F5 | Docs | The design still read "design proposal, not approved", and its read-set table listed policy, control and ledger for launch, which contradicted the build. | Design status block and read-set table corrected. The `phase_generation` note is recorded there as open. |

**Open:** `developer.ex` hardcodes `"phase_generation" => 0` in the launch's `create_effect`
request. That breaks after a policy-reset generation. It is not fixed here. FR-08A attestation
(`fr08a_protected_boundary_test.exs`) must be rebound for `record_codec.ex` and
`authority.ex`. It was already stale for `protected_primitives.ex` at `3ca453e5`.
