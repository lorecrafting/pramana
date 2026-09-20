# FR-18A final residual-B1 rereview — PASS

Independent narrow rereview, 2026-09-20 (Hawaii). **PASS for residual B1 at the
exact subject below.** Current physical and structured corruption are distinguished from
availability failures without phrase-substring overclassification. This result does not
review or waive B5; the bounded protected-query blocker remains open.

## Exact subject and scope

- Implementation: `ff6613cb81ac335d425ef460edc8994bc29448c4`, tree
  `0df8bc5ad6329897e1b463d558fa90e83345a644`.
- Parent narrow review: `022169c992279e0314ded6957415caee5d993a86`, tree
  `ed7ee452c5f89d163bb64e3742ecac368b248e9b`.
- Branch/worktree: `repair/fr18a-honest-observations`,
  `/private/tmp/pramana-fr18a.8plkoi`.

Direct Git inspection reproduced both identities. The exact parent-to-implementation
diff changes only:

```text
M foundry/lib/pramana_foundry/observations/gateway_source.ex
M foundry/test/pramana_foundry/observations_test.exs
```

The correction adds an exact allowlist for the two SQLite corruption messages observed
through the accepted Database/Gateway boundary. It does not use substring matching and
does not change the protected store, Gateway, provider, daemon, activation or deployment
paths. No implementation was changed by this review.

## B1 verdict — PASS

The updated [rereview probe](fr18a-correction-rereview-probes.exs) replaces its obsolete
physical-corruption failure expectation and independently exercises the following matrix:

| Recovery/input case | Required public classification | Result |
|---|---|---|
| Real initialized SQLite file, synchronized overwrite of 256 bytes at offset 100 | `corrupt/source_corrupt` | Pass |
| Real regular file containing non-SQLite bytes; Gateway reason `file is not a database` | `corrupt/source_corrupt` | Pass |
| Structured `authority_corrupt` | `corrupt/source_corrupt` | Pass |
| Structured three- and four-element `protected_corrupt` | `corrupt/source_corrupt` | Pass |
| Raw `disk I/O error` recovery | `unavailable/source_unavailable` | Pass |
| Missing store | `unavailable/source_unavailable` | Pass |
| Wrong protected capability | `unavailable/source_unavailable` | Pass |
| Dead Gateway PID | `unavailable/source_unavailable` | Pass |
| Phrase lookalikes containing either corruption sentence plus other text | `unavailable/source_unavailable` | Pass |
| Nested `storage_unavailable` containing corruption-like text | `unavailable/source_unavailable` | Pass |

The real offset-100 corruption now reopens fenced with Gateway reason
`database disk image is malformed` and yields the corrupt envelope. A real non-database
file yields the second exact allowlisted reason and the same corrupt envelope. Raw reasons
never enter either public DTO.

The exact membership check is neither underbroad for the two current engine results nor
overbroad for textual lookalikes. If the pinned SQLite adapter changes its corruption
message in a later dependency revision, the safe fallback is unavailable rather than a
false corruption claim; that revision must update its typed/error compatibility tests.
This review does not generalize the two current messages to every future SQLite version.

## Regression boundary

The focused matrix reran the observation suite together with the accepted FR-08A and
FR-08A/FR-19A integration files. It preserved the previously passed behaviors:

- authoritative unknown→success, unknown→failure and conflict/quarantine outcomes;
- whole-envelope identity/source/nested/key redaction;
- malformed-version and execution-quality refusal;
- `absent`, `unavailable` and `present` pointer vocabulary, with `available` rejected;
- existing protected authority and combined storage behavior.

These are regression checks only; their prior narrow PASS is not broadened here.

## Commands and results

From `foundry/`, the independent probe was compiled and run against the checked source:

```sh
MIX_ENV=test \
MIX_BUILD_PATH=/private/tmp/fr18a-final-b1-build \
MIX_DEPS_PATH=/Users/raymondluong/dev/pramana/foundry/deps \
COORDINATOR_TICK=0 \
mix run docs/fr-18a/fr18a-correction-rereview-probes.exs
```

Observed result: exit 0,
`corruption/availability classification passes; B2-B4/pointers preserved`.

The focused matrix used the same isolated build/dependency paths:

```sh
MIX_ENV=test \
MIX_BUILD_PATH=/private/tmp/fr18a-final-b1-build \
MIX_DEPS_PATH=/Users/raymondluong/dev/pramana/foundry/deps \
COORDINATOR_TICK=0 \
mix test test/pramana_foundry/observations_test.exs \
  test/pramana_foundry/durable_store/protected_primitives_test.exs \
  test/pramana_foundry/durable_store/fr08a_critical_corrections_test.exs \
  test/pramana_foundry/durable_store/fr08a_fr19a_integration_test.exs \
  --seed 18101
```

Observed result: exit 0; 28 passed. The reviewer host exposes Homebrew Elixir 1.20.4 /
OTP 29 / ERTS 17.0.6 rather than the repository's exact patch-level pins, so no full-CI
result is claimed. No provider, daemon, credential, mutation, deployment, activation or
external effect ran.

## Preserved blocker

B5 was outside this rereview. The public observation caps still do not establish a
bounded protected effect-query materialization path. It remains an explicit blocker
pending its own implementation and independent review; the B1 PASS cannot be used to
infer FR-18A completion.

**Disposition:** PASS B1 at `ff6613c`. Preserve the earlier B2–B4/pointer PASS and keep
B5 open and blocking.
