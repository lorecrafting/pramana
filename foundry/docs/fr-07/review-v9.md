# FR-07 v9 bounded independent correctness review — PASS

Reviewed 2026-09-19 (Hawaii). The residual earlier-carrier binding defect from the
exact v8 review is corrected. Its independent required-behavior reproduction now
passes, including absent and mismatched carriers. The previously credited v8
closure and complete local recovery evidence remain intact. No blocker remains
in this bounded FR-07 recheck; this verdict does not accept downstream activation
or physical durability obligations.

## Exact identity

- Reviewed revision: `8d7223b79cb237d3406f156c7d1a06a8bcb48d81`.
- Reviewed tree: `894e47756305f1b0fb615c6471f2dfdc644f16f3`.
- Implementation: `af0c51b4682c50080e67194dd853fbaa1eebace7`;
  tree `e4aed492d5973d185a7e772d1b764e1117df11c1`.
- Checkout: `/Users/raymondluong/dev/pramana-fr07-worktree`.
- All **56 candidate manifest hashes** independently match.
- `candidate-v9.md`: `223aac42be3a823561d37a083f9e5da614002b9bb5c96151e32ba79c9c13873b`.
- Exact v8 review: `60353069c5b144f21f0124d5d59b2c3912e18f8eb8d335ec0561c7fb63b3d72b`;
  repository copy equals the original `/tmp/fr07-v8-review.md`.
- Exact v8 response: `1fc573ec536a885e703778c1106a7ca189df2179d533dbed7701506f762c28ba`.

HEAD/tree and all 56 hashes were rechecked after execution; the worktree remained
clean. No repository or live-system writes, network access, provider calls or
credential use occurred. Probe mutations were confined to disposable local SQLite
fixtures. Existing dependency sources were reused; no dependency provenance or
network revalidation is claimed.

## Residual blocker closed

`authority.ex:334` supplies shared bound event-row decoding for global and scoped
reads. The indexed chain now selects the complete event row, including its carrier
columns (`authority.ex:1041`). Before extracting a transition or doing arithmetic,
the fold invokes `decode_projection_carrier/2` (`authority.ex:974`, definition at
1063), which checks the event envelope, stored carrier binding and requested
namespace/entity. Absent or mismatched carriers return typed retained corruption.
The relevant entity index, shared pure reducer and explicit internal `:stored`
materialization behavior are preserved.

The independent trace commits A at entity revision 0 and B at revision 1, then
canonically changes only A's event body while retaining its indexed columns.
Three damage forms (absent carrier, wrong entity, wrong namespace) were crossed
with public command lookup, projection-dependent mutation and dependency-dependent
mutation. All nine cases passed:

- Global and both scoped reads return
  `{:authority_corrupt, "events", "event-A", :relational_binding_mismatch}`.
- Public lookup returns typed recovery mode; dependent mutation returns typed
  corruption and fences. No callback exception occurs; the monitored gateway stays
  alive and queryable, and another valid mutation is refused.
- Exact contents of all 18 actual tables remain unchanged, including no dependent
  command/result/effect rows. The independent snapshot enumerates actual SQL tables
  and does not derive its inventory from the production authority registry.

Positive controls also pass: a legal carrier-free event retains NULL carrier
columns and remains readable; creation plus a same-transaction ordered update
materializes correctly, can be read globally through backup validation, and does
not acquire a false corruption fence. The permanent earlier-carrier regression
at `authority_test.exs:799` passes as well.

## No regression of credited closure

The unchanged independent v8 closure probes pass four required-behavior tests:
missing completed projections fence both dependency families without dependent
rows; genuine absence and multi-step internal materialization remain valid;
projection/dependency/ledger owners reject impossible watermarks and rejected or
blocked dispositions with retained events/effects without raising; legal eventless
historic results and same-ID retry with obsolete malformed inputs remain valid.
The fifteen owner-semantic corruption cases retain exact 18-table equality.

The narrow production delta is event-row/carrier decoding. Previously credited
B3 total malformed ingress, B4 exclusive/adopted import staging, B5 exact schema
definitions and B6 bounded relevant entity scans are not weakened by it. Their
permanent regressions, shared reducer/reconstruction, path/import cases and store
recovery tests pass in the focused suite. This credits the previously reviewed
closure plus this regression run, not a new unbounded audit of every subsystem.

## Independently executed verification

Pinned Elixir 1.20.3 / OTP 29.0.5; fresh canonical root
`/private/tmp/fr07-v9-review.zzBPTu`, `MIX_ENV=test`, isolated build at `<root>/build`,
`TMPDIR=<root>`, `COORDINATOR_TICK=0`, external HERDR/operator/runtime-root variables
removed. Commands ran from candidate `foundry/` via `mise exec --`.

- `mix compile --force --warnings-as-errors`: exit 0; 90 project files.
- `mix test test/pramana_foundry/durable_store test/pramana_foundry/legacy_persistence_containment_test.exs test/pramana_foundry/effects/checkpoint_test.exs --seed 9221`:
  exit 0; **92 passed**.
- Independent `carrier_probes.exs`: exit 0; **2 passed**, including the nine-case matrix.
- Independent unchanged `closure_probes.exs`: exit 0; **4 passed**.
- Independent `sync_probes.exs`: exit 0; **1 passed**, both recovery branches.
- Changed authority source/test format check and `git diff --check` against exact
  v8 revision: exit 0.

The full project suite was not rerun for this final bounded correction. The
candidate reports 512 passing tests at seed 9215; that is implementation-owner
evidence, not an independently reproduced full-suite result in this review.

The independent recovery oracle constructs successful A/CONTROL/B protected
transactions and compares all 18 actual tables. Both connection-scoped WAL xSync
branches ran against SQLite 3.53.4 with WAL/FULL/FK enabled; an unrelated connection
committed successfully while the target was armed. Each observed 52 writes,
write order 52 then sync order 53, flags 2 and SQLite code 1034. Failed COMMIT gave
no success acknowledgment and fenced subsequent mutation.

Ordinary close reopened to the exact prior A/CONTROL bundle with B absent, then
retry committed B. Hard exit 75 required explicit observed-exit recovery and
retained the complete A/CONTROL/B bundle; obsolete-input retry was idempotent.
Both branches matched the complete oracle, malformed-obsolete retry,
independently reopened backup and all three reconstructed projections. Final
row-map digest: `c42a3972dce24a1eae549f9b1c2276969b8b2466a4066a284256a0551603c2d9`.
Loaded NIF SHA256: `7b855b28389db2fd16f250184060231c2ae337bd73ee455e625212fac303de95`.
This is bounded SQLite VFS evidence, not a physical power-loss or media guarantee.

## Evidence and remaining scope

Artifacts remain under `/private/tmp/fr07-v9-review.zzBPTu/`:

| File | SHA256 |
|---|---|
| helpers.exs | `92a5cd6b81fbd57847316fa5978657bf3e8df8801961b6125f9ea96b328be317` |
| carrier_probes.exs | `be721035eca4f0137bfa6ed0f07c1f959682f0cfbc151c9e48db6b529c978e3e` |
| closure_probes.exs | `6aa2a8fb8e52f65bc696185fea56568bbf431e1235c66166a3fc4ac781b60ee8` |
| sync_child.exs | `a08460d3be91920a6c62f2aa66aea3948fd928eea594d1cdbabcc230c025e6ca` |
| sync_probes.exs | `d19505385f11d5485eb53abc4a5c4b232fab699765853b80cebac2e6904ee61d` |

Blockers: none in the requested bounded recheck. Suggestion, not a blocker:
retain the independent full-row recovery oracle as owned executable support.
FR-08, FR-15a, FR-17, FR-19 and FR-22 remain deferred, including their workflow,
OS isolation, activation, physical durability/retention and full-lifecycle duties.
The outstanding reviewed FR-07 correctness blockers are closed for this exact
revision; no permission to activate or modify live systems follows from this verdict.
