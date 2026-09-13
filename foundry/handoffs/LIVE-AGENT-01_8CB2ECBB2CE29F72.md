# Handoff: LIVE-AGENT-01 — Verify & finalize release module integration

**RUN_ID**: 8CB2ECBB2CE29F72
**Checkout**: `/Users/raymondluong/dev/pramana`
**Date**: 2026-09-11
**Branch**: `english-over-chinese-and-check-screen`
**HEAD**: `6f085ad` — "E1: there is no identity-free validation in this corpus, by any route"

---

## Assignment

Verify the `Pramana.Release` module integration implemented by AGENT-TEST-01 (RUN_ID BF5EFBADF9181DFC), confirm the stamp is current, and produce this handoff. The previous session implemented the identity split (`source_bake_id`, `translation_set_id`, `vector_set_id`, `release_id`) and left its work in the working tree as uncommitted modifications.

## State summary

### Release stamp status

| field | value |
|---|---|
| `release_id` | `a637b0ffc72bddac` |
| stamped | 2026-09-05 01:47:36 UTC |
| covers | 273,334 renderings, 1,066,026 vectors |
| drift | **current** — stamp describes the live corpus |

The stamp predates this session; it was created by a prior run of `mix pramana.release.stamp`. No re-stamp needed.

### Working tree state (vs HEAD 6f085ad)

**Modified files (unstaged):**

| file | change |
|---|---|
| `apps/pramana/lib/pramana/corpus/schemas.ex` | Adds `Pramana.Corpus.Release` Ecto schema — fields: `release_id`, `source_bake_id`, `translation_set_id`, `vector_set_id`, `translations_count`, `vectors_count`, `embedding_models`, `translators`, `stamped_at`, timestamps |
| `apps/pramana/lib/mix/tasks/pramana.doctor.ex` | Adds `release()` and `report_drift/1` sections — reports stamp status + drift in `mix pramana.doctor` output |
| `apps/pramana_web/lib/pramana_web/mcp/reply.ex` | Stamps `release_id` on every MCP tool response alongside existing `bake_id` |
| `docs/OBSERVABILITY.md` | Documents `mix pramana.release.stamp` |

**Untracked files:**

| file | change |
|---|---|
| `apps/pramana/lib/pramana/release.ex` | `Pramana.Release` — stamp, current, drift, ids |
| `apps/pramana/lib/mix/tasks/pramana.release.stamp.ex` | `mix pramana.release.stamp` CLI |
| `apps/pramana/priv/repo/migrations/20260904120001_create_releases.exs` | `releases` table migration |
| `apps/pramana/test/pramana/release_test.exs` | 7 tests (stamp, drift, ids) |
| `GEMINI.md` | Provider-specific entrypoint for Gemini/Antigravity |
| `automation/` | roles/steerer.md, handoffs/, pramana_diagnose.py |

## Verification

| check | result |
|---|---|
| `mix compile --warnings-as-errors` | clean, 0 warnings |
| `mix test apps/pramana/test/` | **1445 passed** (29 doctests, 1416 tests), 0 failed |
| `mix test apps/pramana_web/test/` | **239 passed**, 0 failed |
| `mix test test/pramana/release_test.exs` | **7 passed** |
| `mix test apps/pramana_web/test/pramana_web/mcp/reply_test.exs` | **5 passed** |
| `mix credo --strict` | **clean, 0 issues** |
| `mix pramana.doctor` (release section) | stamp current, no drift |

## Residual risks

- `mix pramana.release.stamp` is a manual step — must be run after any import/embed/chunk to keep `release_id` current. Idempotent (same digest → same row).
- The working tree changes are **uncommitted**. These should be committed after review.
- `Pramana.Release` migration (20260904120001) must have been run for the stamp or tests to work — confirmed by the database returning a stamp record.