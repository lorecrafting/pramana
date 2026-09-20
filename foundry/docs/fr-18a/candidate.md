# FR-18A minimal honest observations candidate

> Historical pre-B5 freeze. The exact current bounded-query candidate and canonical
> evidence are recorded in
> [FR-18A B5 bounded effect-query candidate](bounded-effect-query-candidate.md). The
> revision and CI identities below are retained as earlier evidence, not the current
> candidate.

Frozen implementation candidate, 2026-09-20 (Hawaii). This candidate supplies the
read-only canonical observation/query slice required by FR-09/15a trials and later
activation. It does not repair the legacy board or telemetry producer chain, create any
activation pointer, authorize provider execution, or claim FR-18B/FR-22 completion.

## Exact subject and dependency

- Base: `d0059b03757a73085f430895304244afaec79ce2`.
- Candidate: `fa74cabb7ce8c4d12cf94e756c92b7310733192a`, tree
  `6228757bd34a1d639ebb693413dd45b43d50fc0c`.
- Branch/worktree: `repair/fr18a-honest-observations`,
  `/private/tmp/pramana-fr18a.8plkoi`.
- Accepted combined FR-08A/FR-19A review:
  [`fr08a-fr19a-integration-review.md`](../fr-08/fr08a-fr19a-integration-review.md),
  PASS at frozen record `176dab44354b5bbdde5b488f44766849c9d8927d`.

Direct ancestry checks established that both accepted combined review commit `176dab4`
and protected evidence commit `b05f834` are ancestors of the base. The protected
dependency bytes also match the accepted integration manifest exactly:

```text
9a6481b1fd09cdafc0a37cc5fa5bfb032b6993088ea8063d09a55cc002725929  foundry/lib/pramana_foundry/durable_store/gateway.ex
d0b94ba108f8a1be0b3c17db4478bcbe25783991ceb17bc5ca3bb8edd886d99c  foundry/lib/pramana_foundry/durable_store/authority.ex
bf21cc2dc37b58cdec0de191025a7753529fc08d66b887f15331d8bdf026e464  foundry/lib/pramana_foundry/durable_store/database.ex
eea13e7e9d463aca24e2e32e14e249bd99ede6f4c1df5f008bd003e7b3297fef  foundry/lib/pramana_foundry/durable_store/protected_primitives.ex
6a92c29174127f7a689a9933faf8d831c90fc069a0c8f67fb2fd27dd2528c276  foundry/lib/pramana_foundry/repair/fr08a_protected_boundary.ex
0506e031b5af50b43c1d0cc03a8f4553cb6bccb52135b1c4930e9001070e0800  foundry/docs/fr-08/fr08a-protected-report.txt
```

## Interface and honesty boundary

`PramanaFoundry.Observations.query/4` accepts a typed
`PramanaFoundry.Observations.Query` and returns a typed page. The live adapter calls only
FR-08A's capability-authenticated `Gateway.protected_snapshot/2` and
`Gateway.protected_query/3`; it does not read Coordinator state, legacy board state,
telemetry files, SQL tables or domain projections.

Each successful page binds all its items to one protected source identity, writer epoch,
domain/protected sequence frontier, protected schema version, projection version,
observation time, freshness result and canonical quality. A before/after protected
snapshot must match; concurrent movement yields typed unavailability instead of mixing
frontiers.

The page reports accepted source, selected deployment and healthy build as three separate
root pointer observations. Their only current producer status is `absent`, exactly as
seeded and validated by FR-08A. No projection label, repository revision or runtime label
is converted into pointer health. A protected effect observation correlates its ticket,
attempt, execution, effect and control identities, then reports a minimal allowlisted
control/execution summary. Missing execution evidence remains `absent`; outcome and usage
without protected evidence remain explicit `unknown` values.

Unavailable storage/process/capability results and corrupt/malformed source results have
different typed page statuses. Both differ from an `:ok`, canonical page with an empty
item list. Raw failure reasons, effect request bodies, inbox payloads, receipt proof/payload
and control values other than the allowlisted status never enter the DTO. A final recursive
redaction pass also removes conventional secret keys and bearer/API-key-shaped values.

Requests are bounded to 200 unique explicit effect IDs of at most 256 bytes, 50 logical
targets per page, and an 8 KiB–256 KiB serialized page limit. Related claim/reservation
identities are capped at 20 with explicit truncation flags. The cursor advances over the
stable request order, including absent effects, so absence cannot cause an infinite page.

## Acceptance evidence

| FR-18A obligation | Executable evidence |
|---|---|
| Empty healthy differs from unavailable/corrupt | Controlled source cases assert three distinct typed envelopes; a missing live Gateway store is unavailable, never empty success. |
| Separate protected pointers; no manufactured health | Live freshly initialized FR-08A store returns exactly accepted-source, selected-deployment and healthy-build, each `absent`. |
| Ticket/attempt/execution/effect/control correlation | A live protected policy/control/ledger/reservation/effect sequence is queried through the public Gateway and returns the exact five-way identity binding. |
| Source, sequence, freshness and quality | Deterministic fresh/stale controls plus live snapshots assert the envelope and stable source frontiers. |
| Unknowns and redaction | Missing usage is `unknown/not_produced`; an unknown protected receipt stays unknown; representative request, inbox, receipt and control secrets do not appear in the inspected page. |
| Bounded typed DTOs | Struct validation, duplicate/oversize/invalid bounds, two-page pointer traversal and measured serialized size are asserted. |

Focused verification used the pinned dependency sources and an isolated build root:

```text
mix compile --warnings-as-errors
  exit 0; 116 files at the candidate

mix test test/pramana_foundry/observations_test.exs --seed 1802
  exit 0; 7 passed

mix test test/pramana_foundry/observations_test.exs \
  test/pramana_foundry/durable_store/protected_primitives_test.exs \
  test/pramana_foundry/durable_store/fr08a_critical_corrections_test.exs \
  test/pramana_foundry/durable_store/fr08a_fr19a_integration_test.exs --seed 1818
  exit 0; 22 passed
```

Full clean CI used absolute pinned Elixir 1.20.3 / OTP 29.0.5 / ERTS 17.0.5 binaries
and a canonical non-symlink temporary root:

```text
TMPDIR=/private/tmp PATH=<pinned-erlang-bin>:<pinned-elixir-bin>:/usr/bin:/bin \
  elixir ci/run.exs \
  --output /private/tmp/fr18a-ci-fa74cab-pinned-canonical-tmp

exit 0; 619 passed, 13 skipped, 1 optional Python/tiktoken recomputation excluded
```

Every CI stage passed: isolated locked dependencies, forced warnings-as-errors compile,
format enforcement outside the unchanged pinned debt, full model-free tests, dependency
inventory and fresh escript build. Preflight and postflight both record the clean exact
candidate commit/tree above. Evidence hashes:

```text
de22881c1cd800dfb0cdcdf350eaa77c40380506b97f413e7f7ff3f73f026305  provenance.json
39afe87487d8a76dd8c503aa005b2aedfe2f2a451adb0b3ab00c888c3a4d4897  pramana_foundry
```

An earlier invocation was refused before tests because the shell resolved Homebrew
OTP/ERTS instead of the repository pins. A subsequent pinned run rooted beneath macOS's
`/var` symlink compiled and formatted successfully but had 74 existing path-identity
fixtures correctly refuse symlinked database parents (545/619 passed). The successful
run above changed only the outer `TMPDIR` to canonical `/private/tmp`; no source changed.
Neither refused/failed invocation is credited as acceptance evidence.

## Candidate manifest and limits

```text
a83e80b9a670a5dde18ec8e97f55e72c659e9b4eba789fe8baca66befba033c6  foundry/lib/pramana_foundry/observations.ex
8c1c05a77612649e8b7f654748adf6aa0e6e9f3108a51e2db6c068660ec43239  foundry/lib/pramana_foundry/observations/gateway_source.ex
89a4e130fd41f581af902021e3d8ae4f49fa699747b495ef9efdbebdf277cb80  foundry/lib/pramana_foundry/observations/observation.ex
bd2520c1338b7975565717ab0132087dd85683a8bca578df0392fd554c030783  foundry/lib/pramana_foundry/observations/page.ex
790304a35da5a4084d8a5fdd97076a57c6b71bd5363801272713d26383eac143  foundry/lib/pramana_foundry/observations/query.ex
5593ca21e267d66d529a9d8459c82206a19ed2e256030e5fdac211e969f37e68  foundry/lib/pramana_foundry/observations/source.ex
44da8603ede58cd669af7432349b0433a2717f1a4cea9e905a6680bfcd7ab7ef  foundry/test/pramana_foundry/observations_test.exs
```

The later B5 correction replaces this historical limitation with an exact-effect query
whose relation rows and control/execution summaries are bounded before runtime
materialization; see the current candidate linked above. It deliberately provides
explicit-ID lookup rather than unbounded store enumeration. FR-17 still owns pointer
producers and activation receipts.
FR-18B still owns producer-to-store-to-board/classifier/usage wiring, lifecycle telemetry
and board behavior. No provider, daemon, credentials, deployment, activation or push was
used, changed or tested.
