# H0 accepted-FR-07 boundary independent rereview — PASS

Reviewed 2026-09-19 (Hawaii). **PASS for the corrected H0 evidence checkpoint.**
The two blockers in the [prior independent review](h0-boundary-review.md) are
resolved at the exact candidate below. The seven-capability result remains
honestly blocked: 4 passed, 0 failed, 3 unavailable and `ready=false`.
This does not establish FR-08A completion, FR-08B readiness or execution authority.

## Subject and review boundary

- Final candidate: `4c8734c6473be97da77f299bc4b42cd720cdf0b6`, tree
  `f120fcaff6967f6dc3a734200d2e797b2ed9c2ed`.
- Correction/adapter: `a23482de566dcd7be567dff49985ff8c97536df9`, tree
  `939c8f96f451594fb391ffc17ed9073a6531f5ad`.
- Prior BLOCKER review: `b5abb5eab4d16c0075e5e2180a5ff059b51c9a70`.
- Accepted FR-07 v9: `af0c51b4682c50080e67194dd853fbaa1eebace7`, tree
  `e4aed492d5973d185a7e772d1b764e1117df11c1`; accepted review
  `8d7223b79cb237d3406f156c7d1a06a8bcb48d81`, tree
  `894e47756305f1b0fb615c6471f2dfdc644f16f3`.
- Worktree: `/Users/raymondluong/dev/pramana-h0`, branch
  `repair/h0-fr07-boundary`; clean before review.

This is a fresh narrow review of B1/B2 and their preserved public controls under
[H0 and FR-08A requirements](../REPAIR-PLAN.md#h0--honest-accepted-fr-07-boundary-inventoryreport),
not a repeated architecture review. I inspected the provider, corrected tests,
both fresh-process fixtures, candidate record and prior review. I verified the
commit/tree identities, all 12 distinct corrected candidate manifest entries and
all 56 accepted-v9 manifest entries against their named Git revisions. An initial
manifest command incorrectly included illustrative `normal.txt` output and
failed; the corrected check selected repository paths and passed every entry.

The four API source blobs match accepted v9. DurableStore source/tests and
`mix.exs`/`mix.lock` have no delta from accepted v9. The final freeze has only
documentation changes after the correction. No protected primitive, SQL path,
private-table mutation or FR-08A semantic expansion was introduced.

| Reviewed evidence | SHA-256 |
|---|---|
| Corrected candidate record | `a202578ed52be9562a6b62d70a69dde426fc262934fe8c3fe63f1e089915d33f` |
| Prior blocker review | `0c95ee9fdcfaaf2c2d170ba7f727c0f5f574c3a530e01eb6262ccb71eef0c583` |
| Frozen report and both fresh-process reproductions | `c6806ec25a43b4f921501769c433cd98eacd77f6e5dcccaefd85df2f01ced6fd` |

## B1 and B2 regression results

**B1 resolved.** Receipts hash the documented versioned JSON envelope with
recursively sorted string keys. Inspection confirms supported primitive/list/map
values have deterministic encoding and unsupported values fail explicitly.
The corrected regression launches separate fresh BEAMs with opposite public API
loading orders. Both reports compare byte-for-byte against the frozen artifact.
I repeated those invocations explicitly, independently compared their bytes and
computed their SHA-256 values: both equal the frozen digest above. The test also
checks provider, tests and both fixtures against the recorded adapter revision.

**B2 resolved.** The report and each gate callback verify source SHA-256 from
loaded compile metadata plus loaded module MD5 for all four exercised API modules.
The fresh negative fixture compiles changed Gateway source in memory, adds a
public `command/2` clause, and asserts the sentinel returns
`{:ok, :changed_loaded_implementation}`. Thus the changed behavior actually
executes while the source file remains unchanged. The subsequent report records
binding mismatch and all seven capabilities become unavailable with
`h0:loaded_accepted_api_identity_mismatch`; it prints
`identity_mismatch_refused` and exits 0. I ran this both through the corrected
regression and an explicit fresh subprocess. No source or BEAM file was mutated.
The unchanged gate cannot be ready with seven unavailable results.

This is binding to the pinned source/toolchain and exercised public implementation,
not a claim of resistance to arbitrary hostile manipulation of the whole VM.

## Preserved public controls and limits

The independent public probe script from the prior review was rerun using an
in-memory adaptation of its obsolete `report/0` call to `report/1` with the exact
correction revision. Its source remains at
`/private/tmp/pramana-h0-independent.R4aXMv/public_probes.exs`; no saved probe
was edited. Both tests pass. One compares every frozen capability row and checks
wrong-revision refusal. The other commits a real control transaction, then tests
atom and string forms of all nine protected fields (18 hostile variants).
Every attempt returns `:unknown_field`, has no command result, and preserves the
public count map after that control. Malformed-proposal retry returns the original
result; changed actor and payload each cause idempotency conflict.

The real provider additionally reproduces projection lookup before stale revision
validation, missing-store recovery refusal without database creation, and immutable
import bytes with explicit invalid-record counts. Normal results remain exactly
4 passed / 0 failed / 3 unavailable, blocked and not ready. Complete evolving
read-set CAS, protected authority lifecycle, and authenticated inbox sequence/seal
facts remain unavailable and assigned to FR-08A. Empty tables are not credited
as positive lifecycle evidence.

## Executed checks and documentation integration

Pinned Elixir 1.20.3 / OTP 29.0.5, from candidate `foundry/`, with prefix:

```sh
env -u HERDR_ENV -u PRAMANA_RUNTIME_ROOT -u PRAMANA_STARTUP_MODE \
  MIX_ENV=test \
  MIX_DEPS_PATH=/private/tmp/pramana-foundry-ci-VAYKRbmQCUqdoK6-TuKHEdj9/deps \
  MIX_BUILD_PATH=/private/tmp/pramana-h0-rereview.ndRSLU/build \
  TMPDIR=/private/tmp/pramana-h0-rereview.ndRSLU \
  PRAMANA_OPERATOR_RUNTIME_ROOT=/private/tmp/pramana-h0-rereview.ndRSLU/operator \
  PRAMANA_RUNTIME_ROOT_FRESH=1 COORDINATOR_TICK=0 mise exec --
```

Build/runtime roots were fresh; existing dependency sources were reused.

- `mix compile --force --warnings-as-errors`: exit 0; 106 project files.
- H0 provider and handoff gate tests, `--seed 9251`: exit 0; 19 passed.
- Explicit normal/reverse fresh-process artifact comparisons and changed-loaded-code
  fixture through `mix run --no-start --no-compile`: exit 0; digests/refusal above.
- Independent public probe script through `mix run --no-start --no-compile -e`
  and `Code.eval_string/1`: exit 0; 2 passed (seed 834983).
- DurableStore authority, gateway, legacy import, path identity, record codec,
  review corrections and unified contract files, plus legacy containment,
  checkpoint, H0 provider and handoff gate tests, `--seed 9252`: exit 0; 109 passed.
- `mix format --check-formatted` for provider, provider tests and both fixtures:
  exit 0. Candidate `git diff --check 25e1097 HEAD`: exit 0.
- Root `mise exec -- elixir bin/check_docs.exs`: exit 0; 80 passed at candidate.

The existing native VFS `sync_fault_test.exs` exit-139 limitation is separate and
unchanged. This rereview excludes that file and does not rerun full CI, diagnose
the native cause or claim passing VFS recovery evidence. No provider, daemon,
credential, deployment or activation was exercised.

The candidate and prior review already route from the Foundry index and shared
catalog. The documentation gate requires every tracked Markdown document to be
reachable from the shared router (`test/docs/routing_test.exs`). To integrate this
new report, the only additional edit is one link in `docs/CATALOG.md` to
`foundry/docs/fr-08/h0-boundary-rereview.md`. That integration-only catalog edit is
outside the reviewed candidate and changes its catalog hash; the frozen candidate
manifest is intentionally preserved. No other index, plan or frozen evidence is
edited. The staged documentation gate passed: exit 0, 80 tests (seed 953130).
