# H0 accepted-FR-07 public-boundary independent review — BLOCKER

Reviewed 2026-09-19 (Hawaii). The bounded [H0 candidate](h0-boundary-candidate.md) has two evidence defects:
its frozen import receipt does not reproduce across fresh VMs, and its report does
not verify the implementation to which it attributes the probes. These block H0
acceptance. They do not reopen accepted FR-07 or justify implementing FR-08A early.

The capability disposition itself is correct: four supported cases pass, three
capabilities remain unavailable, and `ready=false`. Neither this review nor a
corrected H0 inventory establishes FR-08A completion, FR-08B readiness, provider
authorization or activation.

## Exact reviewed identity

- Candidate HEAD: `3e1ed8bb643e6f68cf604cb497f3c0f41770e7b0`;
  tree `3380ca565b8e433d0b9f03c7dffc7183f67e31b8`.
- Supplied base: `25e109730bdb31fa475215813030d9b01ec43675`;
  tree `e45118398763c22aa33a3544ad3b6c6366f6e69d`.
- Adapter/probe revision: `800d200687fa4af2d5a08711c5a1e853df4d36a7`;
  tree `c6884159ec8048b3b4fb26375c6a28088be1b586`.
- Accepted FR-07 implementation: `af0c51b4682c50080e67194dd853fbaa1eebace7`;
  tree `e4aed492d5973d185a7e772d1b764e1117df11c1`.
- Accepted FR-07 reviewed revision: `8d7223b79cb237d3406f156c7d1a06a8bcb48d81`;
  tree `894e47756305f1b0fb615c6471f2dfdc644f16f3`.
- Branch/worktree: `repair/h0-fr07-boundary`,
  `/Users/raymondluong/dev/pramana-h0`.

The checkout was clean before review and still at the candidate HEAD after all
probes. Only this report is committed by the reviewer. No implementation, frozen
candidate record or frozen report was edited. The in-memory negative control
described below ended with its disposable VM; it wrote no source or BEAM file.

I independently verified all 56 FR-07 v9 manifest entries against `git show` at
the accepted implementation, all seven H0 manifest entries against the checkout,
and the commit/tree identities above. The four named public API blobs match the
accepted implementation. There is no delta in DurableStore source/tests or
`mix.exs`/`mix.lock` from accepted v9, nor in implementation/tests/dependencies
from the named adapter revision to this candidate. The unchanged handoff gate is
not an H0 implementation delta.

| Evidence | SHA-256 |
|---|---|
| `h0-boundary-candidate.md` | `dc4cd92b1ec5ac3f79dec463905bef0aa71ae0eef914000fbd05012c4a60f115` |
| `h0-accepted-fr07-report.txt` | `a6ff9b7a33ab1ebe15edb2378d58281039fb6ee676b522cfd7e1963a493570f8` |
| H0 provider source | `442c659c0cc7631a4f61e1083114ce94406453c005f2d000069d5993b809324e` |
| H0 provider tests | `e3cbce816ad7fa34588122ea8a8eee588647541db926013d1b13bcfa9ca88bd3` |
| `../fr-07/candidate-v9.md` | `223aac42be3a823561d37a083f9e5da614002b9bb5c96151e32ba79c9c13873b` |
| `../fr-07/review-v9.md` | `08379ffd3315ec2724c4578a0a14e690f535238104107c778bd8d777efbf8638` |

## B1 — Frozen receipts are not canonical across fresh VMs

`h0_accepted_fr07_boundary.ex:181` constructs an atom-keyed map for the selected
import result; `receipt/2` at line 312 hashes `:erlang.term_to_binary/1` without
canonicalization. That map's serialized order varies with atom loading. The
repository test compares two reports within one VM and checks only the receipt's
shape; it never compares the result against the frozen report.

An independent fresh-VM comparison against all seven frozen rows failed only the
import receipt. The frozen receipt is
`8f183f57a3b73b6b086f831f706295f414541eac6358e862c9979b2b5207ff9a`;
the independently executed provider returned
`b414c3728b4e4f020a7f4f9dc50b92eeef4815782aac5e55df97a1cc4c768abe`.
A second script that compiles a literal containing the same semantic-result keys
before executing the provider returned
`acc1515163ef6e0c8bc187ebb97ffe50974a2bb24dd6cda9b78a4d6b344a0638`.
Its independently reconstructed result yielded that same digest and exposed the
serialized key order. Both scripts use the unchanged provider and pinned toolchain.

The selected semantics remain identical: fixture SHA-256
`6457c72cfb6ac9ed8ed575b2d32ff36e8a8e6f30337d715bdaa5f4cbb327fe45`,
123 source bytes, two lines, zero valid records and two invalid records. The
archive-byte comparison still passes. This is unstable evidence encoding, not
evidence that import changed or became unavailable.

Required correction: use a specified deterministic encoding for receipt inputs,
add fresh-VM checks with different loading orders, compare the generated report
against its frozen artifact, and refreeze the affected receipt/report/manifests.
Do not change the import capability to unavailable to hide this failure.

## B2 — Subject identity is asserted rather than verified by the report

`identity/0` returns constant SHA/tree/API labels. `report/0` supplies the constant
accepted SHA to the gate. The guard at lines 64–65 rejects a different supplied
string, but no report/probe entry point verifies the source or loaded code it
actually calls. The separate test at line 68 checks four checkout blobs, not the
loaded implementation used by a report invocation. The candidate's statement
that this prevents reuse against later source is therefore too strong.

The independent negative control first executes the real provider, then compiles
an in-memory variant of `Gateway` adding a new `command/2` clause for the sentinel
`REVIEW-NON-V9`. It checks that the loaded module MD5 changed and that the added
public behavior executes. Running the unchanged H0 provider again produces an
identical report, including accepted-v9 identities, four passed capabilities and
three unavailable capabilities. All report probes still call real Gateway and
LegacyImport implementations; no synthetic passing provider or SQL is involved.

This does not allege that the frozen checkout secretly differs from v9: its
relevant blobs were independently verified above. It establishes that the
executable report can attribute observations of different loaded code to v9.
Arbitrary hostile-VM resistance is not requested. An integrated report runner
that verifies the accepted implementation and builds/loads it in a fresh isolated
VM would also satisfy this boundary; a constant subject label alone does not.

Required correction: bind report execution to the verified accepted source and
the code built/loaded from it, retain adapter/probe provenance, and refuse to
produce accepted-v9 positive evidence on a mismatch. Preserve the seven-result
fail-closed routing. A label-mismatch unit test is insufficient regression proof.

## Credited public behavior and honest unavailable facts

The provider calls only public Gateway initialization/start/status/transaction/
command/count operations and the documented offline LegacyImport operation.
It uses no SQL, private table mutation, `Authority`, `Database`,
`ProtectedVerifier`, `transact_verified/6` or extracted connection. The independent
positive/hostile acceptance probes use the same public boundary. Existing
DurableStore regression tests have broader protected/internal fixtures; their
passing counts are not substituted for H0 public lifecycle evidence.

The independent hostile matrix tests nine protected fields with both atom and
string keys: claims, receipts, leases, ledger generations, policy revisions,
control revisions, artifact references, balances and accepted refs. All 18
attempts return `:unknown_field`, leave their command IDs absent and preserve the
public count map after a real committed control transaction. The control's retry
returns its original result despite an empty malformed proposal; changed actor
and changed command payload each return idempotency conflict. The provider's own
positive lookup fixture additionally exercises a real projection creation and
retry of its now-obsolete absent precondition.

These are structural refusal and lookup observations. Public counts cover only
the API's exposed subset; they do not certify every private table or supply
positive receipt/lease/ledger lifecycle evidence. Generic nested domain JSON
would likewise not create protected authority. No such inference is credited.

The missing-store probe honestly observes `:not_initialized`, refused transaction
and count access, and no created database. Its pass is bounded to that public
recovery case, not a new full durability certification. Import observes archive
byte preservation and explicit invalid-record counts; B1 concerns its evidence
digest, not its successful semantic assertions.

Complete evolving policy/control/allocation CAS, atomic receipt/lease/claim
issue/settlement and ledger evolution, and authenticated inbox sequence/seal
facts remain unavailable. No schema/table presence or empty-state inference
upgrades them. Wrong supplied revision gives seven unavailable results. The
unchanged gate's unit tests retain failed-versus-unavailable routing and malformed,
exception and timeout containment. Four pass/zero fail/three unavailable yields
`blocked`, and `ready?/1` correctly returns false. H0 acceptance still fails for
B1/B2; those evidence defects must not be confused with expected unavailable
FR-08A capabilities.

## Independent commands, artifacts and verification limits

Commands ran from candidate `foundry/` using Elixir 1.20.3 / OTP 29.0.5 through
`mise exec --`, with this prefix:

```sh
env -u HERDR_ENV -u PRAMANA_RUNTIME_ROOT -u PRAMANA_STARTUP_MODE \
  MIX_ENV=test \
  MIX_DEPS_PATH=/private/tmp/pramana-foundry-ci-VAYKRbmQCUqdoK6-TuKHEdj9/deps \
  MIX_BUILD_PATH=/private/tmp/pramana-h0-independent.R4aXMv/build \
  TMPDIR=/private/tmp/pramana-h0-independent.R4aXMv \
  PRAMANA_OPERATOR_RUNTIME_ROOT=/private/tmp/pramana-h0-independent.R4aXMv/operator \
  PRAMANA_RUNTIME_ROOT_FRESH=1 COORDINATOR_TICK=0 mise exec --
```

The build and runtime roots were new. Existing dependency sources were reused;
no fresh network/dependency-source attestation is claimed. An initial compile
without the explicit dependency path exited 1 because dependencies were absent;
the corrected invocation below passed. No live daemon, provider, credential,
operator runtime or deployment was exercised.

- `mix compile --force --warnings-as-errors`: exit 0; 106 project files.
- `mix test test/pramana_foundry/repair/h0_accepted_fr07_boundary_test.exs test/pramana_foundry/repair/fr08_handoff_gate_test.exs --seed 9237`:
  exit 0; 17 passed.
- `mix run --no-start /private/tmp/pramana-h0-independent.R4aXMv/public_probes.exs`:
  exit 2; one of two tests failed because the frozen import receipt differs.
  The other test passed all 18 hostile cases and positive/conflict controls.
- `mix run --no-start /private/tmp/pramana-h0-independent.R4aXMv/receipt_probe.exs`:
  exit 0; exposed the same semantic result with the third digest above.
- `mix run --no-start /private/tmp/pramana-h0-independent.R4aXMv/binding_probe.exs`:
  exit 0; reproduced the identity-binding defect. This successful diagnostic exit
  is evidence of B2, not an acceptance pass.
- `mix test test/pramana_foundry/durable_store/authority_test.exs test/pramana_foundry/durable_store/gateway_test.exs test/pramana_foundry/durable_store/legacy_import_test.exs test/pramana_foundry/durable_store/path_identity_test.exs test/pramana_foundry/durable_store/record_codec_test.exs test/pramana_foundry/durable_store/review_corrections_test.exs test/pramana_foundry/durable_store/unified_contract_test.exs test/pramana_foundry/legacy_persistence_containment_test.exs test/pramana_foundry/effects/checkpoint_test.exs test/pramana_foundry/repair/h0_accepted_fr07_boundary_test.exs test/pramana_foundry/repair/fr08_handoff_gate_test.exs --seed 9239`:
  exit 0; 107 passed.
- `mix format --check-formatted lib/pramana_foundry/repair/h0_accepted_fr07_boundary.ex test/pramana_foundry/repair/h0_accepted_fr07_boundary_test.exs`:
  exit 0. Candidate `git diff --check` against the supplied base: exit 0.
- From the repository root, `mise exec -- elixir bin/check_docs.exs`: exit 2;
  79 of 80 tests passed. The candidate record is not reachable from the shared
  documentation router. This check ran before this new review was staged, so its
  tracked-document census did not include the review. The next candidate must
  route both records from the owning index; this reviewer does not edit that
  index or change the frozen candidate.

Independent probe files remain in `/private/tmp/pramana-h0-independent.R4aXMv/`:

| File | SHA-256 |
|---|---|
| `public_probes.exs` | `f14b8fe24f89ee1fd8456e4cb3a71af7f3789e35b67afa95aea9265ec9680e93` |
| `receipt_probe.exs` | `b0470f63665e7b783664843925ff7f6f885b06c1034b0fa74c52680e3c788b5c` |
| `binding_probe.exs` | `857a3d73a968a9a4e5b36556fe5273848e43b251e5645ca8fe23217f808b3226` |

Separately, `mix test test/pramana_foundry/durable_store/sync_fault_test.exs --seed 9238`
exited **139**, without a completed ExUnit summary. Its hard-exit subprocess
returned `{"", 139}` instead of the expected exit 73, and the overall test VM
also exited 139. The loaded Exqlite NIF SHA-256 was
`7b855b28389db2fd16f250184060231c2ae337bd73ee455e625212fac303de95`,
matching the NIF hash recorded in accepted FR-07 v9 review. This independently
reproduces the candidate's native-process limitation in the sync-fault file. It
does not determine the native root cause, prove a new H0 regression or provide
passing VFS recovery evidence.

I also verified the candidate's preserved full-CI provenance artifact SHA-256
`20f1a84180f4eb4f94965b57071d428421ff00650e8c5b60a82e5d44163bf430`
at `/private/tmp/pramana-h0-ci-canonical.QmMrdH/artifacts/provenance.json`.
It records earlier clean revision `2a55ebd156cdb90fcf92deb6bb5e984b24850e3e`,
passed dependency/compile/format stages and test exit 139; it is not a green run
at this candidate HEAD. I did not rerun full CI. The 107-test result explicitly
excludes the two sync-fault tests and does not erase that limitation.

**Verdict: BLOCKER for B1 and B2.** Preserve credited public behavior, the blocked
seven-capability disposition and the separate native-process limitation. Refreeze
and independently review the corrected H0 evidence before accepting this checkpoint.
