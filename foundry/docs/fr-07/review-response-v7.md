# FR-07 v7 renewed review response

Date: 2026-09-19

Review: `review-v7.md`, SHA-256
`d7a2f287b463d7abc2dd5ec72205b8849e759d2737d376cc8385546a71379c86`.

The implementation owner accepts V7-R1 and V7-R2. This bounded correction preserves the
v7 review's passing disposition for B3–B6 and makes no independent acceptance claim.

## V7-R1

A completed projection or dependency absence read now performs a bounded lookup through
the entity carrier index. No carrier returns genuine absence; any retained carrier with a
missing projection returns typed `authority_corrupt`, fences the gateway and prevents the
dependent command from writing any rows. The explicit transaction-only `:stored` scope
still permits pre-materialization absence after a new command's events have been inserted;
it is not reachable through the Gateway caller protocol.

The permanent regression reproduces the review trace: commit A, delete only A's
projection, observe typed corruption on the scoped read, attempt eventless B with an
`"absent"` precondition, then prove recovery mode and zero B command rows.

## V7-R2

`read_command_owner/2` now validates the complete bounded owner closure: authenticated
input, command and result bindings; owned event and effect decoding; global event
watermark bounds; per-command event contiguity/final sequence; and the rule that rejected
or blocked results retain no domain events or effects. Direct command reads, projection
carrier owners and ledger/effect owners all use this one semantic check. Projection
recursion remains outside the owner primitive and is applied only by the caller that owns
that closure.

All `with` fallthroughs in scoped effect/reservation traversal now return typed retained
corruption. They cannot escape as `WithClauseError` or be relabeled as storage failure.
Permanent regressions cover impossible `committed_seq=999` owners through both projection
and ledger dependencies, plus a rejected owner retaining an effect. Every case fences and
proves zero dependent-command rows.

The indexed entity scan, shared reducer, total ingress, exclusive import staging, exact
schema contract, 18-table backup and WAL xSync evidence are unchanged. FR-08, FR-15a,
FR-17, FR-19 and FR-22 remain downstream.

## Implementation-owner verification

Pinned Elixir 1.20.3 / OTP 29.0.5, isolated build and temporary state:

- `MIX_ENV=test mix compile --force --warnings-as-errors`: exit 0; 90 project files.
- Durable-store, legacy-containment and checkpoint tests, seed 9192: exit 0;
  91 passed.
- Full model-free suite, seed 9193: 510 of 511 passed. The sole failure is the existing
  projections benchmark environment check because Python `tiktoken` is unavailable; its
  isolated failure reports `ModuleNotFoundError`. This is recorded as an exclusion, not a
  passed FR-07 check.

These are implementation-owner results. V8 remains subject to renewed independent review.
