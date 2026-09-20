# FR-18A independent critical review — BLOCKER

Independent review snapshot, 2026-09-20 (Hawaii). **BLOCKER for the exact
candidate below.** The implementation preserves the protected-source boundary and
passes its focused suite, but it does not yet meet FR-18A's honest corrupt/outcome,
redaction or bounded-query acceptance. No implementation was changed by this review.

## Exact subject and provenance

- Source candidate: `fa74cabb7ce8c4d12cf94e756c92b7310733192a`, tree
  `6228757bd34a1d639ebb693413dd45b43d50fc0c`.
- Candidate evidence/router commit: `8f266ea087791345f1318785e80fa2f754a15b00`,
  tree `e924b746eddf7f04097946cc7be91c39aa4d8399`.
- Base: `d0059b03757a73085f430895304244afaec79ce2`.
- Worktree/branch: `/private/tmp/pramana-fr18a.8plkoi`,
  `repair/fr18a-honest-observations`.

Direct Git inspection reproduced both subject trees and established that accepted
combined FR-08A/FR-19A record `176dab44354b5bbdde5b488f44766849c9d8927d`
and its evidence revision `b05f8342fbb83cb26a0fa157472bee15a020ad7e`
are ancestors of the base. The six declared protected dependency hashes match the
candidate record. An exact diff from the source candidate through the evidence commit
changes only `foundry/docs/README.md` and `foundry/docs/fr-18a/candidate.md`; the seven
implementation/test paths are byte-identical to the source candidate.

I read the shared workflow, Foundry index, FR-18A and relevant FR-08A/FR-19A/B repair
criteria, the workflow contract's authority/identity/observation/recovery sections,
the accepted combined FR-08A/FR-19A review, the candidate evidence, all changed source
and tests, and the protected Gateway/query/schema paths. Earlier green results were
treated as evidence to verify, not as the verdict.

## B1 — A corrupt reopened store is reported as unavailable

`GatewaySource.read/1` maps every `{:recovery_mode, reason}` to `:unavailable`, without
classifying the reason. The probe changes only the stored projection version to an
unsupported value and reopens the Gateway. FR-19A correctly starts in recovery with
`{:authority_corrupt, "metadata", "versions", :unsupported_version}`, but the public
observation is:

```elixir
%Page{
  status: :unavailable,
  quality: :unavailable,
  error_code: :source_unavailable,
  items: []
}
```

This is an actual protected Gateway/reopen path, not a fake adapter. It fails the
explicit requirement that corrupt and unavailable sources remain distinct. The existing
test proves malformed fake pointer data maps to corrupt, but does not cover the real
startup/recovery boundary where FR-19A exposes corruption.

Minimal correction: classify recovery reasons without exposing their payload. Protected,
authority, schema and physical corruption must produce the typed corrupt envelope;
missing stores, dead processes, bad capabilities and operational storage failure may
remain unavailable. Add fresh-start, corrupt-reopen, dead-process and unauthorized
capability cases through `Observations.query/4`.

## B2 — A reconciled success is contradicted as an unknown outcome

The accepted protected lifecycle permits a first `unknown` receipt followed by an
attributable terminal reconciliation. The live probe executes that exact sequence. The
root effect and claim end at `succeeded`, but `canonical_outcome/1` de-duplicates all
historical receipt outcomes, sees both `unknown` and `succeeded`, and emits:

```elixir
%{
  "status" => "succeeded",
  "outcome" => %{"status" => "unknown", "reason" => "conflicting_receipts"}
}
```

Those fields describe the same protected effect and cannot both be an honest canonical
summary. The receipts are not conflicting: FR-08A explicitly accepted the second receipt
as reconciliation and made the terminal protected state authoritative.

Minimal correction: derive the observation outcome from the validated protected terminal
effect/claim state and use receipt history as provenance. Preserve `unknown` only while
the protected state is genuinely unknown or reconciliation-required. Add live
unknown-to-success and unknown-to-failure cases, plus a true conflict/quarantine case.

## B3 — Representative secrets leak through canonical identities

The final recursive redaction is applied only to `Observation.fact`. The separately
constructed `Observation.identity` and page `source` maps bypass it. FR-08A accepts any
nonempty valid UTF-8 identity; it does not reject secret-shaped values. The live Gateway
probe creates an otherwise valid effect whose ticket identity has a representative
API-key shape. The duplicate value in `fact` becomes `[REDACTED]`, while the exact raw
value remains in `item.identity` and therefore in `inspect(page)`.

The fake-source variation independently reproduces the same split. The probe prints only
the boolean verdict and never prints the representative value. The candidate test's raw
request, receipt and control payloads are usefully omitted, but its ordinary identity
values cannot detect this path.

Minimal correction: apply the public redaction policy to the complete output envelope,
including identity and source metadata, or reject sensitive-shaped identity/source values
without echoing them. Add live protected facts carrying representative values in every
emitted string-bearing region and assert against the complete serialized page.

## B4 — The source contract accepts malformed revision identity as canonical

`canonical_source/1` validates installation/repository/writer identities and sequence
frontiers, but copies `protected_schema_version` and `projection_version` without type or
supported-version checks. The probe supplies `projection_version: nil`; the result is an
`:ok`, `:canonical` page whose source retains that nil revision. Similar validation gaps
exist in the execution summary, where revision/sequences/status are copied without their
declared types or vocabularies.

The live Gateway normally validates metadata on open, which contains the blast radius,
but FR-18A's own claim is that malformed source results become corrupt. A source adapter
or future version mismatch cannot be allowed to manufacture canonical quality merely
because its pointers and sequence integers happen to parse.

Minimal correction: validate the complete emitted source and execution shapes, including
supported versions and status vocabularies, before assigning canonical quality. Add
one-field-at-a-time malformed-source cases.

## B5 — The declared public bounds sit after an unbounded protected materialization

The candidate caps returned claim/reservation IDs at 20 and rejects an oversized final
page, but `ProtectedPrimitives.effect_fact/2` first loads every claim, every receipt and
every reservation for the requested effect and constructs their complete public maps.
The root schema and `create_effect` command enforce no reservation-count limit. A request
can name 200 effect IDs, so neither the public page limit nor truncation flag bounds work
inside the sole-writer Gateway. A slow materialization can also outlive the caller's
default `GenServer.call` timeout while keeping the Gateway busy.

This is a blocker rather than a later optimization: the workflow contract calls this a
bounded root-derived query, and FR-18A exposes it as the read path intended for trials.
An output-size check after allocation is not an end-to-end resource bound. No throughput
or failure threshold is inferred here; the defect is the absence of any enforced input,
row or byte limit.

Minimal correction: impose an accepted protected write bound on associated identities,
or add a protected summary/cursor query that fetches at most the public cap plus one and
does not decode an unbounded effect blob. Preserve an explicit truncation signal and test
the exact boundary and boundary-plus-one through the live adapter.

## Correct behavior retained

The review did not find a projection/manufactured-authority bypass. The production adapter
uses only capability-authenticated protected snapshot/query APIs; it does not consult
Coordinator, the legacy board, telemetry files, domain projections or SQL. Before/after
snapshot equality covers installation/repository/writer identity, both sequence frontiers,
versions and pointer slots, so ordinary concurrent protected/domain movement refuses as
unavailable instead of mixing revisions. Requests use explicit effect IDs, reject
duplicates/oversize IDs and out-of-range cursors, and advance the cursor over missing IDs.
Wrong capabilities and missing/dead Gateways do not become healthy empty pages.

Freshly initialized accepted-source, selected-deployment and healthy-build slots remain
three distinct protected facts and remain absent; no domain projection can populate them.
The current root pointer table reserves `absent`, `unavailable` and `present`, while
FR-18A currently accepts `absent` and the non-schema word `available`. Because FR-17 owns
the first real pointer producer, positive pointer production remains deferred, but FR-17
must not be asked to repair an incompatible FR-18A enum after this interface is accepted.

## Deferred ownership and exclusions

These blockers are within FR-18A: they concern the canonical read adapter, result
classification, protected outcome interpretation, redaction and query bounds. They do
not require implementing later tickets.

- FR-18B still owns the real producer-to-store-to-board/classifier/usage chain, lifecycle
  telemetry, invalid-record surfacing and board behavior.
- FR-09 and FR-15aB still own installed harness behavior, scoped transport and actual OS/
  credential isolation.
- FR-17 still owns accepted/build/deployment pointer production, activation receipts and
  immutable release switching. Its future `present`/`unavailable` pointer values must use
  the already protected vocabulary rather than FR-18A's current `available` spelling.
- FR-19B still owns broader diagnostic retention/compaction and relocation closure.
- FR-22 still owns full live lifecycle and operating-document reconciliation.

No provider, credential, daemon, mutation route, deployment, activation, push or external
effect was inspected, changed or claimed by this review.

## Checks and reproducibility

The committed [review probe](fr18a-review-probes.exs) uses disposable databases and
synthetic representative values. From `foundry/`, after compiling the candidate:

```sh
MIX_ENV=test \
MIX_BUILD_PATH=/private/tmp/fr18a-review-build \
MIX_DEPS_PATH=/Users/raymondluong/dev/pramana/foundry/deps \
COORDINATOR_TICK=0 \
mix run --no-start --no-compile docs/fr-18a/fr18a-review-probes.exs
```

Observed result: exit 0, `FR-18A review probes reproduced 4 defects`. The four executable
cases cover corrupt reopen classification, identity redaction, malformed revision quality
and live unknown-to-success reconciliation. B5 is established by the named source path;
the review deliberately makes no unmeasured scale claim.

The independent focused matrix used the same isolated build/dependency paths:

```sh
MIX_ENV=test \
MIX_BUILD_PATH=/private/tmp/fr18a-review-build \
MIX_DEPS_PATH=/Users/raymondluong/dev/pramana/foundry/deps \
COORDINATOR_TICK=0 \
mix test test/pramana_foundry/observations_test.exs \
  test/pramana_foundry/durable_store/protected_primitives_test.exs \
  test/pramana_foundry/durable_store/fr08a_critical_corrections_test.exs \
  test/pramana_foundry/durable_store/fr08a_fr19a_integration_test.exs \
  --seed 28181
```

Observed result: exit 0; 22 passed. The first isolated invocation stopped before tests
because no dependencies existed under its default path; the successful invocation above
explicitly selected the accepted local dependency sources.

The reviewer host exposed Homebrew Elixir 1.20.4 / OTP 29 / ERTS 17.0.6, not the policy
pins, so full CI was not rerun under a mismatched toolchain. The candidate's saved full-CI
artifacts were credited only after independent inspection: both provenance source
snapshots name clean exact commit `fa74cab`, tree `6228757`, result `passed`, exit 0 and
the policy-matching Elixir 1.20.3 / OTP 29.0.5 / ERTS 17.0.5 toolchain. Their hashes match
the candidate record:

```text
de22881c1cd800dfb0cdcdf350eaa77c40380506b97f413e7f7ff3f73f026305  provenance.json
39afe87487d8a76dd8c503aa005b2aedfe2f2a451adb0b3ab00c888c3a4d4897  pramana_foundry
```

That recorded run passed 619 tests with 13 intentional skips and one optional Python/
tiktoken exclusion. It confirms the frozen source ran cleanly; it cannot negate the
hostile cases absent from that suite.

**Disposition:** correct B1–B5, align the pointer vocabulary while the surface is still
unaccepted, refreeze the exact source/tree and request a fresh independent review. FR-18A
must not be marked complete and its query surface must not be used as FR-09/15a acceptance
evidence from this candidate.
