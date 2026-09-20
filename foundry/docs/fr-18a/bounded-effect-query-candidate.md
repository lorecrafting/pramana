# FR-18A B5 bounded effect-query candidate

Status: **implementation candidate; independent review required.** This record freezes
the B5 correction and its model-free evidence. It does not claim an FR-18A PASS, enable
FR-18B producers, manufacture activation pointers, authorize a provider or deployment,
or replace the outstanding independent review.

## Exact revisions

- Accepted atomic-core base: `057f2902580235d844679c43ece571056b60b8a5`.
- Deliberate merge preserving both histories:
  `cc33375` (`Merge commit '057f290' into repair/fr18a-honest-observations`).
- B5 implementation and tests: `6812e5e673aa8d38fc6a68940f89f2d800dd469b`,
  tree `884a64628672b8dc2a2909c27f42f9a5d43a81bf`.
- Integrated-schema design correction: `2e801ea66b186f8c6bdbe5156369ae5ac5d6333c`,
  tree `ab5b2b6594a71752a3eca0e1e13d7664f0804a99`.
- Revision-bound FR-08A read-boundary evidence:
  `fd774c3b1dbf01c6a9ea8d64c18653b660388c11`, tree
  `13ffc27489651349cd51573e50384d64bfbc35f1`.

The FR-08A report is bound to the B5 implementation commit, not to this later evidence
record. Its protected-primitives source identity is SHA-256
`4f0dd34f26ec1efe00e12f052aaa25804e45e82569eabbc432322abb42ccbb90`
and BEAM MD5 `870e4c17641ab3dce71bf92241c14349`; all seven public probes remain ready.

## Implemented boundary

The existing capability-authenticated `Gateway.protected_query/3` route now accepts only
the typed `effect_observation_page` request. The query names one exact effect and contains
hard item/byte limits plus a source-bound typed continuation. It exposes no generic SQL,
table, column or filter input.

The protected reader uses one SQLite transaction, bounded scalar prefixes and
`Database.fold/5` with SQL `LIMIT` before runtime materialization. Relations paginate in
the fixed claims, receipts, reservations and leases order. The optional authoritative
infrastructure settlement is a separately bounded singleton header, correlated to its
effect, claim and non-start receipt without returning the stored state blob.

Continuation binds effect scope, installation/repository identity, global protected
sequence and effect revision. A mutation between pages returns stale/unavailable rather
than mixing snapshots. Clean reopen and a verified backup continue an unchanged cursor;
a different source or post-page append does not. Oversized supported facts, malformed
cursors, healthy absence, unavailable sources and corruption remain distinct. Public
correlation precedes recursive redaction of facts, identities, source, nested keys and
continuation data.

No atomic write operation, Gateway mutation route, Authority, Database schema, workflow
reducer, Coordinator, FR-08B path, pointer producer or activation path changed in the B5
implementation commit.

## Checks

Focused checks on the candidate:

- warnings-as-errors compilation: passed;
- protected query, public observations, atomic settlement and rebound FR-08A boundary:
  `39 passed`, no failures;
- documentation gate: `80 passed`, no failures.

Canonical Foundry CI ran from the clean evidence commit/tree above with repository-pinned
Elixir 1.20.3, OTP 29.0.5 and ERTS 17.0.5:

- result: passed, exit 0;
- model-free suite: `643 passed`, `13 skipped`, `1 excluded`;
- locked dependency restore, dependency policy, warnings-as-errors compile, format gate,
  dependency inventory and escript build: all passed;
- source postflight: the same clean commit and tree;
- provenance: `/private/tmp/fr18a-b5-ci-fd774c3/provenance.json`, SHA-256
  `eb9b2245d675cf2fb86906915e20308b4d70dc337f1f143457494f791af3c378`;
- generated escript SHA-256:
  `6deec271a67375ee1a1971f47a50e9b1d805b3fff0f1c8a3d8b55c78f5dbd09a`.

The one excluded test is the already inventoried external Python/tiktoken recomputation.
Real-provider, live-daemon, activation, corpus and service evidence remain absent or out of
scope exactly as the canonical manifest records.

## Local runner incident

Before the successful pinned run, an attempted `mise install --force erlang@29.0.5` was
interrupted, but a subsequent shell hook completed replacement of the global local
`/Users/raymondluong/.local/share/mise/installs/erlang/29.0.5` directory. Its directory
ctime was 2026-09-20 02:36:48 HST and the `bin/erl`/`OTP_VERSION` ctime was 02:36:49;
packaged file mtimes remained 2026-08-04. No repository path changed from that incident.
The final CI invocation did not use a shell hook: it used an explicit non-login `PATH`
to the installed Erlang and Elixir binaries plus `TMPDIR=/private/tmp`, and the CI
manifest independently verified the exact expected toolchain.

## Remaining review boundary

Independent review must inspect the typed SQL allowlist, prefix/encoded-size accounting,
cursor stability and exhaustion semantics, infrastructure-settlement required-absence
check, public redaction and the new tests. FR-18A remains unaccepted until that review.
FR-18B, FR-09/15a, FR-17, FR-19B and FR-22 ownership is unchanged.
