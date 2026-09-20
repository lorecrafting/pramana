# FR-08A typed transition-replay correction candidate

Frozen correction evidence, 2026-09-19 (Hawaii). This candidate corrects only the
residual transition-replay blockers in the focused review. It does not establish
independent acceptance, integration, FR-08B readiness, provider execution or activation.

## Exact subject

- Core correction: `e31e3d5700506ae3513958ef79134cabf481e684`, tree
  `20aed5781c56f169a1f6f9e2ec76080b11571cd2`.
- Revision-bound gate/report: `4c196fb78bbb5f93f279144e05000a13b840d965`, tree
  `0056e38cff64da1eac7620547f2ac4e24b4ee116`.
- Branch/worktree: `repair/fr08a-protected-primitives`, `/private/tmp/pramana-fr08a`.
- Focused blocker review: [transition review](fr08a-transition-review.md), with public
  [transition probes](fr08a-transition-review-probes.exs).

The correction replays ledger, reservation, effect and claim transitions from ordered,
authenticated root command types and canonical request bodies. It does not use result
payload maps as authority. Retained result facts remain independently checked through
explicit per-operation carrier fields; receipt payload diagnostics are opaque. Direct
duplicate carriers must agree with the operation's typed facts regardless of map/list
order. Current protected rows must equal the replayed state and exact contiguous
revisions, so a matching forged issue result cannot rewind an issued claim for a second
issue.

The maintained rereview test now executes both the prior 41-case acceptance matrix and
the 39-case typed-transition matrix, including both duplicate-order permutations,
diagnostic payload positives, unknown-to-terminal settlement, reset cancellation, late
non-start after close and lost-reply retry.

## Verification

All successful commands used `TMPDIR=/private/tmp`. The full CI run additionally used
the repository-pinned Elixir 1.20.3 / OTP 29.0.5 / ERTS 17.0.5 binaries explicitly.

| Check | Result |
|---|---|
| `mix compile --warnings-as-errors` | exit 0; 108 project files |
| `mix run docs/fr-08/fr08a-transition-review-probes.exs` | exit 0; 39 passed |
| Maintained focused protected/rereview tests | exit 0; 6 passed (41-case and 39-case subprocess matrices included) |
| Full model-free `ci/run.exs` at `4c196fb` | exit 0; 573 passed, 1 external Python/tiktoken test excluded; dependency inventory, fresh escript and clean-source postflight passed |
| CI provenance | `/private/tmp/fr08a-ci-4c196fb-pinned/provenance.json`; SHA-256 `1b20c0cf21d4a19e948bcbf3641bef9d58f8b95d677fc409b1bd94e18bbcd6c8` |

Two preliminary CI invocations are not acceptance evidence: one used the unpinned
Homebrew toolchain and was rejected at toolchain preflight; a pinned run without the
canonical temporary root reached the suite but correctly failed path-identity tests
because the macOS temporary parent was a symlink. A pinned run with canonical
`TMPDIR=/private/tmp` first exposed only the expected stale revision-bound report, which
was then rebound in `4c196fb`; the final clean-source CI above passed.

The root documentation check initially exposed one inherited routing failure for the
newly committed focused review record. This evidence commit adds the focused review and
candidate to the catalog; the corrected check passed all 80 cases.

## Scope boundary

No shared repair plan/log, provider, credential, daemon, deployment or integration path
was changed. FR-08B all-ingress/domain replay and later activation remain out of scope.
Independent Astra-medium focused rereview is still required before integration.
