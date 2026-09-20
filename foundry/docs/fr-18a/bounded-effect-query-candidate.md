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
  original `fd774c3b1dbf01c6a9ea8d64c18653b660388c11`.
- B5a–B5d correction implementation and tests:
  `98b6ef9fe4236d4741d54888845f64049d8ba738`, tree
  `92607c146bd3bfca6d27ed498710e77390ddb40e`.
- Corrected revision-bound FR-08A evidence:
  `aa173780365d732e1b6fe8ea07b86ca9348c863e`, tree
  `94fa3654e46bee4eb888e7cb5a7b9664126199f6`.

The FR-08A report is bound to the corrected implementation commit, not to the later
evidence record. Its protected-primitives source identity is SHA-256
`df93af4558f98742913c8195763349ade952ca6201f9176314b59fe081f2d420`
and BEAM MD5 `bf52660f7228f46993d8db997a4587f6`; all seven public probes remain ready.

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

The correction also derives control and execution summaries inside that transaction.
Fixed SQL selects only control status/revision and inbox metadata plus ordered aggregate
result/exit sequences. The public observation path therefore never invokes the legacy
unbounded control or inbox materializers. All summary bytes count toward the protected
page budget.

Every settlement scalar is checked against bounded authoritative effect, receipt,
accepted-operation and predecessor-lineage values. A historical non-start settlement
remains valid after a durable quarantined conflicting receipt moves the current claim and
effect to `reconciliation_required`; the public outcome is then explicitly
`unknown/reconciliation_required`. Unsupported transitions and any one-field mismatch
remain corruption.

Continuation binds effect scope, installation/repository identity, global protected
sequence and effect revision. A mutation between pages returns stale/unavailable rather
than mixing snapshots. Clean reopen and a verified backup continue an unchanged cursor;
a different source or post-page append does not. Oversized supported facts, malformed
cursors, healthy absence, unavailable sources and corruption remain distinct. Public
correlation precedes recursive redaction of facts, identities, source, nested keys and
continuation data.

Before assigning canonical quality, the public layer validates the response/source
schema, installation/repository/frontier and effect revision against the surrounding
snapshot, all nested schema versions, relation count, encoded page size, and continuation
frontier/shape.

No atomic write operation, Gateway mutation route, Authority, Database schema, workflow
reducer, Coordinator, FR-08B path, pointer producer or activation path changed in the B5
implementation commit.

## Checks

Focused checks on the corrected candidate:

- warnings-as-errors compilation: passed;
- maintained observations, protected primitives, atomic settlement and FR-08A/FR-19A
  integration matrix: `44 passed`, no failures;
- corrected independent hostile probes: `26 passed`, no failures;
- rebound FR-08A source/BEAM identity and all seven public capabilities: `4 passed`, no
  failures.

Canonical Foundry CI ran from clean evidence commit `aa17378` / tree `94fa365` with pinned
Elixir 1.20.3, OTP 29.0.5 and ERTS 17.0.5:

- result: passed, exit 0;
- model-free suite: `646 passed`, `13 skipped`, `1 excluded`;
- locked dependency restore, dependency policy, warnings-as-errors compile, format gate,
  dependency inventory and escript build: all passed;
- source postflight: the same clean commit and tree;
- provenance: `/private/tmp/fr18a-b5-correction-ci-aa17378/provenance.json`, SHA-256
  `8381d68e96c556030e4e705d5f8c38ab912b5f44efba8f0c4eb300ce6f8a41ab`;
- generated escript SHA-256:
  `760dcf8ec70b1c39d5cd95eb27bd37a940db511884315e981747324053d9c677`.

An earlier correction CI ran before the mandatory FR-08A revision-bound identity was
rebound. Its runtime suite reached `644/646 passed` and failed exactly the two stale
source/report identity assertions. That run is diagnostic only; the clean rebound run
above is the credited canonical evidence.

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

Independent rereview must inspect the B5a–B5d correction, especially fixed SQL summary
selection, settlement conflict provenance/lineage, source/schema correlation and the
corrected hostile probes. This candidate does not claim FR-18A PASS; acceptance remains
with the independent reviewer/coordinator.
FR-18B, FR-09/15a, FR-17, FR-19B and FR-22 ownership is unchanged.
