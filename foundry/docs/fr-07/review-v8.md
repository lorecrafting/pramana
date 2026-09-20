# FR-07 v8 bounded renewed correctness review — FAIL

Reviewed 2026-09-19 (Hawaii). The exact V7-R1 and V7-R2 reproductions are corrected.
One closely related retained-event validation case still crashes the gateway before the
shared owner validator runs. It is isolated below; the previously credited B3–B6 fixes
and complete recovery evidence are preserved.

## Exact identity

- Reviewed revision: `edd91cca8af35d5078808c3b1645077700b922e7`.
- Reviewed tree: `54d1f8a262a971aaa0eb88fe39dbce29fd5077cb`.
- Implementation: `c91a582b66b6a7f664f7685a463c2efd04026fce`;
  tree `cb257c9bce1436b5a7906e6f40da7cb76a69a7ff`.
- Checkout: `/Users/raymondluong/dev/pramana-fr07-worktree`.
- All **53 candidate manifest hashes** independently match.
- `candidate-v8.md`: `7f568715fa96ff7d95ba655fa439410a584e5bc8525163dca7f5fa32bc707cdc`.
- Exact v7 review: `d7a2f287b463d7abc2dd5ec72205b8849e759d2737d376cc8385546a71379c86`.
- Exact v7 response: `4ba1412d05960046fdd8926719967f902ec399b16292fe46deb988ce9aaaeca0`.
- Final HEAD/tree and all 53 hashes remained unchanged; the worktree remained clean.

Only the candidate document differs from the implementation revision. No repository files,
references, network resources or live systems were modified or used. All mutation probes
were local disposable database fixtures. This is a bounded review of V7-R1/R2 and their
necessary retained-event/recovery collateral, not a reopened audit of downstream tickets.

## One residual blocker: carrier decoding can raise before owner validation

`foundry/lib/pramana_foundry/durable_store/authority.ex:966` iterates the indexed entity
carrier rows. It calls `RecordCodec.decode_bound(:event, ...)`, which validates the event
envelope but does not bind the stored projection-index columns or require a projection
carrier. A valid carrier-free legacy event is legal to that decoder. The code then assumes
`event["payload"]["projection"]` exists and subtracts one from its revision at line 979.
The shared owner check at line 1018 is reached only after this unsafe reduction.

Executed trace:

1. Commit A creating `ticket-A` revision 0.
2. Commit B updating the same entity to revision 1.
3. Replace only A's stored event body with a canonically encoded valid `legacy_event`
   having `payload: %{}`, leaving A's indexed carrier columns and all other rows intact.
4. `Authority.read(conn, :all)` correctly returns
   `{:authority_corrupt, "events", "event-A", :relational_binding_mismatch}`.
5. The scoped projection reader raises `ArithmeticError` (`nil - 1`).
6. `Gateway.command(g, "B")` also raises in the callback: the caller exits and the
   monitored gateway terminates, rather than returning typed corruption and entering
   queryable recovery mode.

This is the preceding owner's event in the requested projection's own relevant history.
It does not involve unrelated history, unsupported external access or a new downstream
capability. It demonstrates a remaining gap in the requested full owner/event semantic
validation: the indexed reducer processes a malformed retained relation before the
validator capable of identifying it. The envelope itself is valid, so testing only
malformed JSON would not expose it.

Required correction: use the shared bound event/carrier validation for every row selected
by the indexed projection-chain query, before extracting or reducing its transition.
Require its carrier namespace/entity to match the indexed/requested entity and return the
same typed retained corruption on absent/mismatched carriers. Preserve carrier-free events
as legal outside a projection carrier set, the relevant index scan, and the explicit
intermediate materialization scope. Add the exact earlier-carrier trace to direct read,
projection/dependency read and mutation fencing tests; assert no callback exception.

## Credited closure of V7-R1/R2

Independent `closure_probes.exs` uses required-behavior assertions and passes four tests,
including the following matrices:

- Missing completed projections with retained carriers are rejected through both projection
  and dependency families. The gateway fences, refuses another valid mutation, and exact
  rows in all 18 tables remain unchanged; no dependent command commits.
- Genuine absence remains valid. New creation and two ordered updates in one transaction
  pass, demonstrating that internal pre-materialization checks remain usable.
- Projection, dependency and ledger reads reject owner watermarks beyond the store,
  before the owner's event, and at another command's event block. Rejected and blocked
  owners retaining events/effects return typed `authority_corrupt` without raising.
  Each of these fifteen cases fences and preserves every table's rows.
- Legal eventless results at sequence zero and at a historic nonzero watermark remain
  readable after later commits. Same-ID protected retry bypasses obsolete malformed
  proposal/facts, returns the original result, and preserves exact rows.

Source inspection confirms the owner primitive now owns command/input/result decoding,
owned event/effect decoding and result sequence/disposition semantics without recursively
calling projection reconstruction. The remaining exception above occurs in the caller's
earlier carrier reduction, not in the repaired result-disposition fallthrough.

B3 total malformed ingress, B4 exclusive/adopted staging, B5 exact schema definitions,
and B6 indexed relevant entity scans are unchanged in production. Their permanent tests,
the shared live/reconstruction reducer cases and the existing corruption/import/path
regressions pass in the focused suite. No additional issue was found in those bounded
rechecks. The two previously suggested documentation whitespace corrections are applied.

## Executed verification and recovery

Pinned Elixir 1.20.3 / OTP 29.0.5; fresh root
`/private/tmp/fr07-v8-review.x89Ljh`, `MIX_ENV=test`, build path `<root>/build`,
`TMPDIR=<root>`, `COORDINATOR_TICK=0`, external HERDR/operator/runtime-root variables removed.
Commands ran from candidate `foundry/` via `mise exec --`. Existing dependency sources
were reused; no network dependency revalidation is claimed.

- `mix compile --force --warnings-as-errors`: exit 0; 90 project files.
- `mix test test/pramana_foundry/durable_store test/pramana_foundry/legacy_persistence_containment_test.exs test/pramana_foundry/effects/checkpoint_test.exs --seed 9201`:
  exit 0; **91 passed**.
- Changed Elixir source/test format check and `git diff --check` from exact v7 candidate:
  exit 0.
- Independent closure probes: exit 0; four required-behavior tests passed.
- Independent earlier-owner event probe: exit 0; one characterization test reproduced
  the exception above. Its green characterization result is not an acceptance pass.
- Independent full-row VFS recovery oracle: exit 0; one test, both concrete branches passed.
- `mix test --seed 9202`: exit 2; **510/511 passed**. The sole failure was the unchanged
  telemetry test `test/pramana_foundry/telemetry/telemetry_test.exs:123`, which unexpectedly
  received `:emitter_delayed_action`. Its isolated location rerun with seed 9203 passed
  (one passed, six excluded). The fixture uses a 100 ms emitter timeout alongside the
  default `refute_receive` wait; a timing interaction is plausible, but no root-cause
  diagnosis or relationship to this patch is established. This is reported separately,
  not converted to a full-suite pass or counted as a new FR-07 blocker. The candidate's
  reported missing-tiktoken benchmark failure did not reproduce in this environment.

The recovery oracle separately constructs complete successful A/CONTROL/B protected
transactions and enumerates all 18 actual SQL tables independently of the production
registry. The actual engine is SQLite 3.53.4; loaded NIF SHA256 remains
`7b855b28389db2fd16f250184060231c2ae337bd73ee455e625212fac303de95`.
Both connection-scoped WAL xSync scenarios observed WAL/FULL/FK, an unrelated successful
connection while armed, 52 writes, write order 52 then sync order 53, flags 2 and SQLite
code 1034; COMMIT returned an error without success acknowledgment and later mutation
was fenced.

Ordinary close reopened to exact prior A/CONTROL with B absent, then B committed on retry.
Hard exit 75 required explicit observed-exit recovery and retained exact complete A/CONTROL/B;
retry with obsolete facts was idempotent. Both branches subsequently matched the full oracle,
malformed-obsolete retry, independently reopened backup and all three reconstructed
projections. Final row-map digest:
`c42a3972dce24a1eae549f9b1c2276969b8b2466a4066a284256a0551603c2d9`.
This remains bounded SQLite VFS evidence, without a physical power-loss/fsync/media claim.

## Evidence, suggestions and limits

Review artifacts remain in `/private/tmp/fr07-v8-review.x89Ljh/`:

| File | SHA256 |
|---|---|
| closure_probes.exs | `6aa2a8fb8e52f65bc696185fea56568bbf431e1235c66166a3fc4ac781b60ee8` |
| owner_event_probe.exs | `9be318cd41c1c783008dbb354a554d89ff0cd6e02fc58b6688b815510b567daf` |
| helpers.exs | `8111cd4cb8522d6b5b1b0dc0cafa78aa7c1399e316a401b70cb2a315482e50fd` |
| sync_child.exs | `a08460d3be91920a6c62f2aa66aea3948fd928eea594d1cdbabcc230c025e6ca` |
| sync_probes.exs | `d19505385f11d5485eb53abc4a5c4b232fab699765853b80cebac2e6904ee61d` |

The suggestion to retain the independent full-row recovery oracle as owned executable
support remains separate from the blocker. FR-08, FR-15a, FR-17, FR-19 and FR-22 remain
deferred; this review asks for no new downstream feature. Keep the exact V7-R1/R2 fixes
credited, correct this one retained carrier-validation ordering gap, and freeze the result
for a focused renewed check. FR-07 is not accepted by this verdict.
