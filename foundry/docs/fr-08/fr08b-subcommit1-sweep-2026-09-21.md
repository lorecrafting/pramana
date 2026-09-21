# Guard mutation sweep — full run and confirmations, 2026-09-21

Machine-generated from the sweep's own output. **Not transcribed** — assembled by script
from `bin/guard_mutation_sweep.exs` logs, because every previous hand-carried count from
this tool has been weaker than its claim, five times running.

Kept for two reasons. It is the evidence for the FR-08B subcommit 1 claim that every guard
call site is either exercised or dispositioned. And it is the **answer key** for the
coverage-guided rebuild recorded in EVIDENCE-TOOLS.md: a replacement tool must reproduce
every verdict below exactly, and any disagreement names the site to open.

## Run 1 — full sweep, all sites

Command: `TMPDIR=/private/tmp elixir bin/guard_mutation_sweep.exs`

```
guard call sites: 116
elapsed: 5047s
repository target unchanged: true
caught:    102
survived:  14
```

Site count is **116**, not the 114 last recorded. The difference is exactly the two guard
calls added by `028b4965` — `require_no_recorded_verdict` and `require_check_unsettled`,
one occurrence each — verified by per-name diff against `34d6833`, not assumed.

### Survivors

```
  require_attempt_phase(ticket, ~w(active)) :500
  require_attempt_phase(ticket, ~w(integrating)) :1557
  require_attempt_phase(ticket, ~w(reviewing)) :1574
  require_no_candidate(attempt) :1586
  require_attempt_phase(ticket, ~w(active)) :1595
  require_checks_passed(ticket) :714
  require_reviewer_open(ticket) :772
  require_attempt_phase(ticket, ~w(reviewing)) :818
  require_phase(ticket, ~w(queued blocked)) :289
  require_phase(ticket, ~w(queued blocked)) :302
  require_resume_target(ticket) :337
  require_no_active_attempt(ticket) :365
  require_attempt_phase(ticket, ~w(active)) :461
  require_attempt_phase(ticket, ~w(active)) :483
```

### Disposition of each

| Site | Handler | Disposition |
|---|---|---|
| `:289` `require_phase(~w(queued blocked))` | `ticket_amended` | **gap — closed this session**, test pinned to `:wrong_source_phase` |
| `:302` `require_phase(~w(queued blocked))` | `ticket_parked` | **gap — closed this session**, test pinned to `:wrong_source_phase` |
| `:1595` `require_attempt_phase(~w(active))` | `require_settlement_source`, `"blocked"` | **gap — closed this session**, test pinned to `:wrong_attempt_phase` |
| `:1557` `require_attempt_phase(~w(integrating))` | `require_settlement_source`, `"integrated"` | **unwitnessed** — shadowed by `require_receipt_for_integration`; 0 of 58,324 reachable states at depth 7 have an active attempt holding a ref receipt |
| `:1574` `require_attempt_phase(~w(reviewing))` | `require_settlement_source`, `"rejected"` | **unwitnessed** — shadowed by the verdict check; 0 of 58,324 have an active attempt with any recorded verdict |
| `:461`, `:483`, `:500` `require_attempt_phase(~w(active))` | `artifact_frozen`, `artifact_blocked`, `freeze_failed` | redundant given an invariant, recorded in `028b4965` |
| `:337` `require_resume_target` | `ticket_unblocked` | recorded unable to fire |
| `:365` `require_no_active_attempt` | `ticket_reset` | recorded unable to fire |
| `:714` `require_checks_passed` | `review_planned` | recorded unable to fire |
| `:772` `require_reviewer_open` | `review_recorded` | recorded unable to fire |
| `:818` `require_attempt_phase(~w(reviewing))` | `reviewer_closed` | recorded unable to fire |
| `:1586` `require_no_candidate` | `require_settlement_source` | recorded unable to fire |

The two `unwitnessed` entries are deliberately **not** asserted as `SemanticInvariants`
relations. With zero witnesses in the reachable set, such an assertion runs over 58,324
states none of which can trip it — a vacuous mechanism of the kind this subcommit shipped
five of. A seeded search is what would settle them. See EVIDENCE-TOOLS.md rules 2 and 3.

## Runs 2 and 3 — neutralisation confirmations

A test going green does not show a guard is exercised; only a neutralisation turning it red
does. These re-sweeps are that evidence for the three gaps closed above.

```
# run 2: require_phase(~w(queued blocked)) + require_attempt_phase(~w(active))
  sweep-w1 require_phase(ticket, ~w(queued blocked)) :289 — caught
  sweep-w1 require_phase(ticket, ~w(queued blocked)) :302 — caught
  sweep-w3 require_attempt_phase(ticket, ~w(active)) :500 — survived
  sweep-w4 require_attempt_phase(ticket, ~w(active)) :1595 — survived
  sweep-w2 require_attempt_phase(ticket, ~w(active)) :461 — survived
  sweep-w3 require_attempt_phase(ticket, ~w(active)) :1585 — caught
  sweep-w2 require_attempt_phase(ticket, ~w(active)) :483 — survived

# run 3: require_attempt_phase(~w(active)), after retargeting the :1595 row
  sweep-w3 require_attempt_phase(ticket, ~w(active)) :1595 — caught
  sweep-w2 require_attempt_phase(ticket, ~w(active)) :500 — survived
  sweep-w1 require_attempt_phase(ticket, ~w(active)) :461 — survived
  sweep-w2 require_attempt_phase(ticket, ~w(active)) :1585 — caught
  sweep-w1 require_attempt_phase(ticket, ~w(active)) :483 — survived
```

Run 2 is also why the `:1595` row exists in its present form. Its first version settled
`failed` from `checking`, which exercises the failed/timed_out branch at **`:1585`** — a
site the full sweep had already caught — while the row's name claimed `:1595`. The test was
green, `kernel_test` went 109 to 112, and the site it named was still a survivor. Run 2
caught that; nothing else in the suite compares a test's claim against the site it actually
exercises.
