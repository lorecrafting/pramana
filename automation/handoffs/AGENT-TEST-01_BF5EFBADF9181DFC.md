# Handoff: AGENT-TEST-01 — `release_id` stamping

**RUN_ID**: BF5EFBADF9181DFC
**Checkout**: `/Users/raymondluong/dev/pramana`
**Date**: 2026-09-11

---

## Assignment

Implement and integrate `Pramana.Release` — a recorded identity for what answered a query,
separate from `bake_id` which identifies only the source text.

## Change summary

### New modules and files

| file | purpose |
|---|---|
| `apps/pramana/lib/pramana/release.ex` | `Pramana.Release` — stamp, current, drift, ids |
| `apps/pramana/lib/mix/tasks/pramana.release.stamp.ex` | `mix pramana.release.stamp` CLI |
| `apps/pramana/priv/repo/migrations/20260904120001_create_releases.exs` | `releases` table |
| `apps/pramana/test/pramana/release_test.exs` | 7 tests (stamp, drift, ids) |
| `automation/roles/steerer.md` | Steerer role definition |
| `GEMINI.md` | Provider-specific entrypoint for Gemini/Antigravity |

### Modified files

| file | change |
|---|---|
| `apps/pramana/lib/mix/tasks/pramana.doctor.ex` | Added `release()` and `report_drift()` sections; reports stamp state + drift |
| `apps/pramana/lib/pramana/corpus/schemas.ex` | Added `Pramana.Corpus.Release` schema |
| `apps/pramana_web/lib/pramana_web/mcp/reply.ex` | Stamps `release_id` on every MCP tool response |

### Defect fixed

`bake_id` was being asserted as "what answered". On 2026-09-03, **27,751 renderings and
27,751 vectors landed under an unchanged `bake_id`**, so two scalings of the same corpus
could answer the same query differently while claiming the same identity.

The fix introduces three ids resolved at stamp time:
- `source_bake_id` — stable source-text identity
- `translation_set_id` — digest of the English layer
- `vector_set_id` — digest of the index
- `release_id` — composite digest of all three

### Drift detection

`Pramana.Release.drift/0` compares the stamped facts against the live corpus. `mix
pramana.doctor` reports whether the stamp is current or stale, and if stale, names exactly
what moved. This makes a stale stamp **visible** rather than silent — the property `bake_id`
lacked.

## Verification

| check | result |
|---|---|
| `mix compile --warnings-as-errors` | clean, 0 warnings |
| `mix test` (pramana) | **1445 passed** (29 doctests, 1416 tests), 0 failed |
| `mix test` (pramana_web) | **239 passed**, 0 failed |
| `mix credo --strict` | clean, 0 issues |
| `mix test test/pramana/release_test.exs` | **7 passed** (stamp idempotency, layer movement, drift, ids) |

### Items fixed during verification

1. **DocsTasksTest**: `mix pramana.release.stamp` was undocumented. Added mention in
   `docs/OBSERVABILITY.md` near the `mix pramana.doctor` section.
2. **Credo F warning**: `release/0` had nesting depth 3 in the drift-reporting branch.
   Extracted `report_drift/1` to flatten it.

## Residual risks

- `mix pramana.release.stamp` is a manual step — must be run after any import/embed/chunk
  to keep release_id current. The stamp task is idempotent (same digest → same row), so
  re-running is safe.
- `definitions_test.exs` has a pre-existing type comparison (empty_list vs !=) — unrelated
  to this change, not introduced here.

## Handoff to next session

Next session should run `mix pramana.release.stamp` after stamping post-bake to establish the
first release record. All work in this checkout compiles, tests pass, credo is clean, and
docs are current.