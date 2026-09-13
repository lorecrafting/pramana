# FR-04 independent review v9 — PASS

Reviewed 2026-09-13. Narrow acceptance of the frozen v8 correction and requested regressions; no implementation edits or commit.

## Freeze verified

- Response: `review-response-v8.md`, SHA-256 `ff22d148d3e67d4e2dacf6af17092f0a18659604ed19bb938690457e96a60c20`.
- Prior review: `review-v8.md`, SHA-256 `559728790b3f1819e89360f8b2d145eaeca136911448cf8a27119dd17239b1bf`.
- All 22 implementation/test manifest entries matched current bytes before execution and at handoff. Base `5c69e6c73f572e60a6c2015e955ad841bf504517`, branch `repair/fr04`. No implementation/test drift observed; `git diff --check` passed. This review writes only this artifact.

```sh
shasum -a 256 foundry/docs/fr-04/review-response-v8.md foundry/docs/fr-04/review-v8.md
awk '/^[a-f0-9]{64}  foundry\// {print}' foundry/docs/fr-04/review-response-v8.md | shasum -a 256 -c
git status --short
git diff --check
```

## Executed evidence

Fresh `mktemp` TMPDIR/operator roots; pinned Elixir `1.20.3-otp-29` / OTP `29.0.5`; `MIX_ENV=test`; unset `HERDR_ENV`, `COORDINATOR_TICK`, inherited runtime-root/fresh/startup settings. Runtime tests create their own isolated roots and inject fake adapters.

```sh
mix test test/pramana_foundry/coordinator_test.exs \
  test/pramana_foundry/transition_test.exs \
  test/pramana_foundry/runtime_startup_boundary_test.exs --seed 40459
```

**43 passed**, 11.8 seconds, exit 0. Inspected the checked-gateway sibling helper and reran both orderings:

- unverified developer registration before verified reviewer registration/closure;
- verified reviewer registration/closure before unverified developer registration.

Both use actual Coordinator checked resource/pending/result calls. Tests assert the live and public inventories retain both resources, replay retains the unverified developer and outstanding flag, actual Tick suspends a competing queued ticket, and the exact developer enrichment/pending/closed sequence releases the fence only after both resources are terminal. Existing identity-conflict and stale/sibling settlement tests pass.

The same run regresses PID-only and missing-generation initial capture through the actual isolated runtime topology: receipt before capture, no start/close, unresolved resource retained in live/replay, marker retained. It also exercises registration append failure, bounded drain and two-resource terminal-marker scenarios.

An additional independent `mix run --no-start -e` projection probe reconstructed the v8 counterexample in both registration orders, then:

1. recorded reviewer pending;
2. attempted the reviewer's terminal result under developer role and observed rejection;
3. applied the exact reviewer closed result;
4. asserted the assignment remains outstanding and the all-resource terminal predicate remains false;
5. forcibly changed only the stored `cleanup_outstanding` flag to false;
6. invoked the actual `Tick.process_queue/9` with an empty queue and asserted the admission-suspended diagnostic still appears.

Result, exit 0:

```text
V9_BOTH_ORDERS_PASS sibling close cannot release unverified resource;
wrong-role result rejected; stale false flag cannot bypass Tick
```

## Conclusion

The concrete v8 blocker is resolved. `assignment_outstanding?/1` derives the fence from all registered resources and pending obligations, rather than the most recent registration or result. Registration/result projection, Coordinator decisions and Tick now share this predicate. A verified but nonterminal resource also remains outstanding; the clean-marker predicate still requires exact valid terminal evidence for every resource. No remaining contradiction was found within the requested narrow review.

## Limits

Model-free only; no live Herdr, provider/model, credentials, production state or activation accessed. No fresh exhaustive architectural/destructive-path audit, full focused-suite run, force compile or shell-wrapper run in this narrow review. Earlier audit scope and downstream limitations remain: non-atomic backend compare/close, richer reconciliation, and FR-03 startup/integration suspensions are not resolved or activated by this PASS. No new blocker or suggestion is added beyond those retained boundaries.
