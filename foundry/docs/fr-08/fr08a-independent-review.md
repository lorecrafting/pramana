# FR-08A first independent critical review — BLOCKER

Reviewed 2026-09-19 (Hawaii), independently of implementation and support-matrix design.
**BLOCKER.** The protected API performs real positive transactions, but does not yet
enforce the R1/R5 boundary it claims. Its seven passing capability labels cannot establish
FR-08A completion or permit FR-08B to start. No implementation was repaired in this review.

## Exact subject and evidence boundary

- Candidate: `523f803642dcc601c9bf873ff217aedba93ea60d`, tree
  `957319e47c36fb921dbc35c18eef897794e82d9b`.
- Protected core: `aacbd1c407eb5f76afdfaf09e6793f7ecb19c8da`, tree
  `d0e3d258fef13915b78080cd484c68d84f5337c4`.
- Baseline: `fa636fb592eacf4ebd31b72fa377b0a86a6d3e3e`.
- Worktree: `/private/tmp/pramana-fr08a`, branch `repair/fr08a-protected-primitives`.
- The candidate was clean before and after every executable check. The only subsequent
  repository edits are this report and catalog routing. Source, tests, frozen candidate
  record, report, shared repair plan, implementation log and shared plan remain unchanged.

I read the governing shared workflow, Foundry index, FR-08A/H0/shared completion and
F07/F16 requirements, R1–R5/encoding/identity/compatibility contract, accepted FR-07 v9,
the H0 candidate/blocker/PASS evidence, the [candidate](fr08a-candidate.md), all new
protected implementation, affected tests and the diff against the baseline. All **9**
candidate manifest entries match the exact candidate. The H0 frozen revision's **12
distinct** entries (13 matching lines, one duplicate report path) and accepted-v9's
**56** entries also match their named revisions. Both candidate and core trees match.
An initial H0 manifest check used its implementation revision for later frozen evidence;
the corrected check uses frozen `4c8734c6473be97da77f299bc4b42cd720cdf0b6` and passes.

The tests use public Gateway APIs for every functional authority claim. Recovery damage
is deliberately injected through disposable SQLite files only after the Gateway stops;
those mutations are negative corruption fixtures, never positive capability evidence.
No provider, credential, live daemon, deployment or integration was exercised.

## Blocking findings

### B1 — The new report regresses H0's loaded-implementation binding

`repair/fr08a_protected_boundary.ex:605` hashes four files under its compiled source
directory; it neither checks the loaded module MD5 nor derives the exercised module's
source from compile metadata. It also omits exercised Kernel/RecordCodec/LegacyImport
from the new identity set. This repeats the defect explicitly closed by
[H0's rereview](h0-boundary-rereview.md).

`binding.exs` runs the real report, recompiles Gateway in memory with one additional
public `command/2` clause, proves the changed behavior executes and the loaded MD5
changes, and confirms the source file is unchanged. The second report is byte-identical:
`verified:source-sha256/v1`, **7 passed, ready=true**. The diagnostic exits 2 as intended.
Restore loaded-code and complete exercised-input binding, including the negative control,
before attributing a gate result to this exact implementation. This is ordinary build
identity verification, not a request to defend against arbitrary manipulation of the VM.

### B2 — Claim/issue do not enforce the current epoch, control or complete read set

`gateway.ex:201` passes only connection, supplied actor and request to the new executor;
the Gateway's `writer_epoch` never reaches its authority checks. In
`protected_primitives.ex:667,699`, claim accepts a caller-chosen epoch and issue compares
against that same stored string, not the current owner epoch. The independent public
probe claims under epoch A, cleanly reopens under epoch B, verifies the snapshot says B,
then successfully issues the old A claim. No quiescence/reclaim transition exists.

Claim also omits policy/control/lease checks and dependencies (`:1183`). After a current
control changes to `cancel_requested`, a new claim still commits accepted. `set_control`
only replaces a map; it does not revoke pending/claimed effects or derive outstanding
issued claims. The cancel-after-issue helper returns an outstanding ID but does not
establish a durable descendant cancellation fence. Derive all claim/issue predicates and
read dependencies from protected current authority, with proper cancellation and takeover
ordering. FR-15a's future OS fence cannot repair incorrect durable issuance authorization.

### B3 — Random execution IDs and arbitrary dimensions bypass R1/R5 identity

`semantic_effect_available/2` (`:2039`) and its index use only `(execution_id, operation)`
for live uniqueness. A second execution ID for the same ticket, attempt and launch is
accepted while the first is issued. There is no owner/role/phase-generation/operation
ordinal or terminal predecessor check, no finite non-start infrastructure allowance, and
no root assignment/profile/deadline binding. Changing an execution ID bypasses the guard.

`allowed_effect?/3` (`:1962`) checks operation and scope strings only. Reservations are
checked for effect ownership/status, but never for the required operation dimension.
A launch backed solely by **validations** credit is created, claimed and issued accepted.
This is implicit unit conversion even though individual SQL ledgers conserve numbers.
Fixed operation-to-dimension mapping, admitted assignment identity, predecessor evidence
and semantic ownership belong in the protected boundary. Domain scheduling rows remain
FR-08B; the authority predicates they must consume cannot be deferred there.

The SQL ledger FK does include dimension and positive same-dimension delegation works.
However, `(ledger_id, generation)` is the primary/public identity, allowing only one
dimension per ledger generation. If dimension-specific ledger IDs are intentional, the
objective/allocation identity and mapping need an explicit enforced contract; current
opaque IDs do not provide the contract's dimensioned objective envelope/global ceiling.

### B4 — Closure/reset does not close the delegated authority tree

`close_generation` (`:498`) closes one row only. It neither revokes unissued claims nor
closes child generations. `issue_claim` checks reservation status but not ledger status.
Public probes demonstrate all three failures: a held claim issues after its ledger is
closed; a child remains open after its parent closes; returning a child allocation adds
**available=1** to a closed parent (`return_allocation`, `:369`).

`reset_generation` (`:519`) revokes only reservations directly in the named child;
descendants are omitted, and there is no current-generation/monotonic successor identity.
Root reset is not supported through this path because it requires a parent ledger.
The candidate's narrow child reset test passes, but does not prove recursive reset,
closed-tree conservation semantics or no reopening/refill. Close/reset must atomically
include the subtree, relevant reservations/effects/leases and complete CAS dependencies.
Late old-generation settlements must stay in their original held/consumed/retired totals.

### B5 — Receipt identity is not bound to the issued request; reconciliation conflicts

`settle_claim` (`:731`) accepts arbitrary `request_id`; effects store only a digest of
the supplied request, and no protected request-ID relation is checked. The proof is a
caller-selected string (`settlement_proof`, `:2387`), without bound issuer/channel or
non-delivery evidence. A receipt for `unrelated-request` with `issuer_quiescent` settles
the issued claim as non-started and refunds its hold. This is not attributable non-start.

Conversely, a legitimate unknown receipt followed by a terminal observation for the
**same request ID** hits global `UNIQUE(root_receipts.request_id)`, returns storage
unavailable and fences the store. The reconciliation branch therefore needs a different
request ID to advance, precisely the relation that should stay fixed. Cross-claim receipt
ID/request collisions are also SQL errors rather than durable reconciliations. Bind
observations to immutable issued requests and authenticated receipt provenance, separate
observation identity from request identity, and retain/quarantine conflicting evidence
without either refunding or relabelling a different request.

The existing same-claim conflicting terminal-receipt test does keep consumed credit
unchanged; credit that bounded control. It does not close these request-binding failures.
Released leases are not re-retained on a late conflict, and owner-level quarantine is
undermined by B3's new-execution bypass.

### B6 — Recovery validates selected shapes, not protected authority provenance

`validate_blob_rows` checks canonical JSON only. `validate_simple_history` (`:2711`)
compares latest head/history bytes and prior number, but never verifies their value against
the authenticated command, complete predecessor chain or retained result. A corruption
fixture changes a valid policy's head and history to allow activation/global scope while
leaving its original command intact. Reopen is **ready** and the public policy query
returns the forged policy.

Pointer validation is similarly incomplete. Changing a canonical healthy-pointer row to
`present`, revision 1, `build=not-built` makes reopen ready and the protected snapshot
report that nonexistent healthy build, despite there being no FR-17 producer or receipt.
The schema's allowance for `present` is not evidence that such a row can be valid today.

Other validators compare only limited aggregates/relations: reservations allow consumed
greater than their summed consumed records, ledgers without reservation rows escape that
aggregate comparison, inbox recovery does not recompute item digest/accepted-vs-late
binding, and effect validation checks only claim/effect status equality. Reconstruct or
validate all protected row/carrier/owner/provenance relationships before serving them.
These are local logical-corruption obligations; physical media/backup hardening remains
FR-19. No claim of administrator-resistant cryptographic storage is made.

### B7 — Migration silently rewrites unsupported/corrupt protected state

`database.ex:508` creates missing objects and upserts version/completion metadata before
validating the source version. An independently corrupted `protected_schema_version=999`
correctly fences normal open, but public `Gateway.migrate/1` returns **:ok**, overwrites
the version with 1 and makes it acceptable. Deleting a protected healthy-pointer row is
also silently repaired by migration's seed operation. This cannot distinguish a valid
old-v1 migration from damaged already-migrated authority.

Validate the precise supported starting schema/content/version before changing it, and
allow only explicit version transitions. Preserve exclusive owner locking and atomic
rollback. The candidate's migration test starts with empty legacy authority; it is not
proof that nonempty accepted-FR-07 claims/allocations are semantically retained or that
rollback builds can handle the new write set. The old accepted reader rejects the new
schema/metadata; any irreversible maintenance boundary and rollback compatibility must
be explicit, not inferred from the unchanged outer SQL version 1.

### B8 — Two mutable protected fact families remain behind the Gateway

The candidate says legacy authority tables are compatibility-only and `root_*` is the
sole mutable protected representation. `legacy_boundary.exs` disproves that through
public APIs: `Gateway.transact_verified/6` accepts a fresh legacy intent, allocation,
claim and reservation on the migrated store. Public counts report one claim/reservation;
the new root claim query returns `:not_found`, and its claim/ledger frontiers remain -1.
This uses one connection, but two mutable authority representations with different checks.

The inherited accepted-FR-07 route is not newly declared defective at its old scope.
FR-08A must now retire it from productive authorization or provide an explicit verified
bridge/compatibility mode that preserves one protected truth. Merely leaving both writable
and delegating reconciliation to the all-ingress migration contradicts the frozen claim.
Also, `reserve` and `create_effect` are separate transactions: the advertised reservation
API can debit a hold before any admitted intent exists. Its ordinary valid owner is an
arbitrary effect string; atomic admitted intent/reservation ownership remains unproved.

### B9 — Malformed/semantic conflicts are misclassified, and fault coverage misses root writes

A malformed policy ID map reaches `to_string` in read derivation, becomes a transaction
exception wrapped as storage unavailable and fences a healthy Gateway. An authenticated
different actor appending to an owned inbox similarly fences with `inbox_actor_conflict`.
Two pending effects can request the same resource; claiming the second after the first
hits the lease uniqueness constraint and fences instead of committing a semantic rejection.
The claim read set lacks the lease/resource dependency that would catch this normally.

The constraint case **does roll back atomically**: after restart, no second claim/lease
exists, the effect remains pending, its reservation is unbound/reserved, and the ledger
remains held=2/available=18. This credits actual rollback while retaining the availability
and durable-rejection defect. Validate malformed operations before transaction/history;
turn supported identity/resource conflicts into stable durable rejections or quarantine.

The new path never passes `state.fault` to its transaction executor. A Gateway started
with the valid `fault: :before_commit` option still acknowledges a new protected command.
Existing failpoint/native tests exercise the old bundle path; their green results cannot
stand in for failures between root command/receipt/lease/ledger mutations. Add meaningful
root-path pre/postcommit and lost-reply probes when correcting the implementation. The
reviewer's actual process-exit test below credits committed root recovery separately.

## Credited controls and remaining observation scope

The new semantic API does use the existing serialized Gateway and Database transaction;
ordinary domain proposals expose neither SQL nor a connection. Unknown protected bundle
fields remain rejected. Public root queries select protected rows, not domain projection
labels. Same actor/ID/digest lookup precedes current CAS, changed actor/payload conflicts,
root/domain command IDs cannot collide, and selected stale/incomplete reads reject durably.
The accepted H0 four controls and evolved historical report tests remain green in the
focused/full suites. They are preserved controls, not proof of every new root predicate.

Positive inbox sequencing/sealing/late evidence is real: a sealed result remains selected
after later evidence and restart. The independent lost-reply retry returns the original
command result. No stream-completeness proof or artifact-validity distinction exists yet;
the first item labelled result wins, and absent/open streams must not be interpreted as
failed/empty healthy work by FR-08B/18A.

Snapshot identity and distinct accepted/selected/healthy slots exist and are initially
honestly absent. However, `inbox_fact`, ledger, effect and claim queries materialize all
associated rows and raw payloads without pagination/size bounds/redaction. Policy/control
values are generic maps. Revision frontiers are maxima across different entities, not
freshness watermarks for a particular fact; responses lack observation source/quality and
root result sequence. FR-18A must not treat these as a completed canonical public DTO.
Bounded summaries versus controlled raw evidence access need an explicit interface.

The FR-18A/FR-17 dependency interpretation remains acyclic: FR-18A may expose typed absent
or unavailable pointer slots before FR-17 supplies authorized producers. It must not wait
for a healthy deployment to represent absence, or manufacture a healthy pointer from
projections. B6 prevents crediting the current recovery path for that guarantee.

## Executed verification and native-fixture disposition

All commands used pinned **Elixir 1.20.3 / OTP 29.0.5 / ERTS 17.0.5** through
`/private/tmp/fr08a-independent.YFHW86/run.sh`. A preliminary `mise exec` resolved Homebrew
OTP 29.0.6 despite the project pin; that was detected before testing and explicit PATH
selection corrected it. Build/runtime/temp roots are isolated. Focused compilation reuses
existing dependency sources; both complete CI runs independently restore locked Hex deps,
validate the entire selected graph and record source/toolchain/lock identities.

| Command/check | Independent result |
|---|---|
| `mix compile --force --warnings-as-errors` | exit 0; 108 project files |
| Explicit changed-file `mix format --check-formatted`; `git diff --check fa636fb HEAD` | exit 0 |
| DurableStore directory, FR08A/H0/handoff gate, legacy containment and checkpoint tests, `--seed 9282`, bundled header | exit 0; 118 passed |
| `mix run --no-start --no-compile public_probes.exs`, seed 9281 | exit 2; 1/12 passed, 11 required-behavior failures; rollback assertions passed |
| Same runner, `recovery_probes.exs`, seed 9283 | exit 2; 1/7 passed, 6 required-behavior failures |
| Same runner, `binding.exs` | exit 2; changed loaded code still yields identical ready report |
| Same runner, `legacy_boundary.exs` | exit 0 diagnostic; reproduced two mutable protected fact families |
| Same runner, `crash_probe.exs` plus real child | exit 0; child exits 73 after protected commit; ambiguous owner fences; observed-exit recovery and same-ID retry preserve one 3-unit grant |
| `elixir ci/run.exs --output .../ci-default` | exit 139 at native fixture; deps, policy, compile, formatting passed |
| Same full runner with bundled-header `CPATH`, output `.../ci-bundled-header` | exit 0; **565 passed, 1 external Python/tiktoken test excluded**; dependency inventory, escript and clean-source postflight passed |
| Frozen-source `elixir bin/check_docs.exs` | exit 2; 79/80 passed; only FR08A candidate lacks catalog routing |

The xSync fixture's `-I deps/exqlite/c_src` ignores isolated `MIX_DEPS_PATH`. Independent
`clang -E -H` traces show default selection of macOS SDK `sqlite3ext.h`/`sqlite3.h`, while
the same compilation with
`CPATH=/private/tmp/pramana-foundry-ci-VAYKRbmQCUqdoK6-TuKHEdj9/deps/exqlite/c_src`
selects Exqlite's bundled SQLite 3.53.4 headers. Those two header files are byte-identical
to this review's freshly restored full-CI Exqlite 0.40.0 dependency. Their SHA-256 values:
`sqlite3.h=919e7f2e8ed1d8f56ac17b412b8971c76aa5d1a879752cc6058f75e7d5910e1d`;
`sqlite3ext.h=ac9645e5c9ff0cf176efdd6e75cb5e98f46295d38e02db5c4d208826a39ab4be`.
No candidate fixture/source changed. The paired runs establish a fixture/header-selection
defect, not an FR-08A runtime regression or unavailable VFS evidence. Fixing its dependency
path is a follow-up suggestion; neither that diagnosis nor full green CI waives B1–B9.

## Probe artifacts and exact hashes

All artifacts below remain under `/private/tmp/fr08a-independent.YFHW86/`. Scripts are
reviewer-owned, external to the frozen checkout. Logs retain actual results and exit codes
are recorded above. Initial probe development used an unsupported fault tuple; it was
corrected to `:before_commit` and the listed final recovery log reproduces the defect.

| Artifact | SHA-256 |
|---|---|
| `run.sh` | `07192c3844fc9274ff7da89adc66e17889050c6a73888bea64fceceddb3b1569` |
| `manifest.exs` | `eac23d9b07f1e6cd5af3e1f035e1277f877dde5eddadfd3dd324262eb5e8adb1` |
| `binding.exs` | `98dc35dddab5cf73ca6a169e740a23487c564203961091b8766031004debaeca` |
| `public_probes.exs` | `dc36e1b127696ddef8a953cad0b79c0c1446f2a67dfa7e292eafe347d3484d53` |
| `recovery_probes.exs` | `4534e04244140604ca8e3a093bfae4129af2605cf57adce83ff2ad089765047d` |
| `legacy_boundary.exs` | `9835c34a8d3990ab2348b2dc63a65061d2362a865f1566cbbf5261643e8dde35` |
| `crash_child.exs` | `dec8c48ff95efb6c3a47df566fef2dfa7e01244c5d4692fd1707aca887ee4def` |
| `crash_probe.exs` | `97849863e04a0e3763b5f42a56c002ada3a620e38bff2cd50afb2bc03ed763ab` |
| `public-probes.log` | `67861aea07d523b551b5c20828bcd727441f8d84b3b574e351096c96cd29014c` |
| `recovery-probes.log` | `2ab3780c12c61663b8718c8a6b4a055de7c6b8c9b68eb01e2cfa63b734e5f847` |
| `binding.log` | `e0c6767661ac5ac982bcdd12e60a71928a042254bd774416867f72c6ce58264c` |
| `ci-default/provenance.json` | `849cbc1b363905ff630e8393e49310897bbf0a47fbcb17b80ddd0c6dd94190c6` |
| `ci-bundled-header/provenance.json` | `b32ffbb92b5be33acd2651a5c498afc0f58236ddd08972bf28f23b7781b4b7de` |

The reviewer adds catalog links for the frozen candidate and this report only, resolving
the discovered routing omission without rewriting the candidate or its manifest. The
staged documentation gate then passed: exit 0, 80 tests, seed 244513. The review commit is
separate evidence and does not replace the subject SHA/tree above.

**Disposition:** correct and refreeze FR-08A, then request another critical review across
these invariant families. Preserve the accepted H0/v9 history and credited positive
controls. FR-08B owns full ingress/live-replay/domain lifecycle migration; FR-15a owns
actual process/credential/transport isolation; FR-18 owns presentation/observation DTOs;
FR-19 owns physical storage/backup/retention operations; FR-17 owns actual acceptance and
activation pointer production; FR-22 owns whole-lifecycle acceptance. None is completed or
authorized by this review. The reproduced protected-authority defects stay in FR-08A.
