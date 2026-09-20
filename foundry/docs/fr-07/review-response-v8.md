# FR-07 v8 renewed review response

Date: 2026-09-19

Review: `review-v8.md`, SHA-256
`60353069c5b144f21f0124d5d59b2c3912e18f8eb8d335ec0561c7fb63b3d72b`.

The implementation owner accepts the residual carrier-validation blocker. The exact
V7-R1/V7-R2 corrections and the v8 review's credited B3–B6 and recovery evidence remain
unchanged. This response makes no independent acceptance claim.

## Residual correction

Every event selected by the indexed projection-chain query now passes through the same
bound event-row validator used by the complete authority reader before the transition is
extracted or reduced. The selected row includes its sequence, event identity, owner,
schema, type and stored carrier namespace/entity. The decoded event must contain a carrier
matching both those retained columns and the requested projection entity. Missing or
mismatched carrier data therefore returns typed `authority_corrupt` instead of reaching
projection arithmetic.

Carrier-free events remain legal when their retained carrier columns are both null, and
they remain outside the indexed carrier query. The explicit transaction-internal `:stored`
materialization path, relevant-entity index scan and shared reducer are unchanged.

The permanent regression constructs two ordered carriers, replaces the earlier event body
with a canonical carrier-free event while retaining its indexed columns, and exercises
direct projection, dependency, public command and mutation entry points. It asserts the
same typed corruption, a live/queryable recovery gateway, no callback exception, no
dependent command and exact unchanged rows in all 18 tables.

## Implementation-owner verification

Pinned Elixir 1.20.3 / OTP 29.0.5 with fresh canonical `/private/tmp` roots:

- `MIX_ENV=test mix compile --force --warnings-as-errors`: exit 0; 90 project files.
- Durable-store, legacy-containment and checkpoint tests, seed 9214: exit 0;
  92 passed.
- Full suite, seed 9215: exit 0; 512 passed.
- Changed source/test format and `git diff --check`: exit 0.

An initial authority-only invocation using macOS's symlinked default temporary path was
rejected by the existing parent-symlink defense. It was rerun with the required canonical
`/private/tmp` root and passed 29/29; it is not counted as acceptance evidence for the
failed invocation.

FR-08, FR-15a, FR-17, FR-19 and FR-22 remain downstream.
