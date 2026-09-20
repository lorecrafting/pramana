# FR-08A + FR-19A combined critical review — PASS

Independent Astra-high review snapshot, 2026-09-20 (Hawaii). **PASS for the exact
combined candidate below.** No integration blocker was reproduced. The protected
authority and operational-storage behaviors compose in the reviewed source and
executed model-free cases. This is not FR-08B, FR-19B, activation, deployment or
provider-execution acceptance.

## Exact subject and provenance

| Layer | Commit | Tree |
|---|---|---|
| Explicit two-parent merge | `1d0b128ff7c78bf72577d23658e267d7508e4763` | `f06d664214c65c435b0d8633bee845731e825e20` |
| Combined core/tests | `240d16f6823a8b9118c4d2b52d305314c6a97203` | `d9f97d8e0b03f32d03884f4f21ceeab36ee297bb` |
| Rebound gate/report | `b05f8342fbb83cb26a0fa157472bee15a020ad7e` | `91810f46acc152acd17e5c4a42cf42faff1b9c4f` |
| Frozen candidate/catalog | `176dab44354b5bbdde5b488f44766849c9d8927d` | `4e0d44410994a7c816ec4d87228603494d69e786` |

Worktree `/private/tmp/pramana-fr08-integration.NfvG46`, branch
`repair/fr08a-fr19-integration`. All four trees match direct Git inspection. The
merge's ordered parents are accepted FR-19A main
`c53801245fac71c7e6de9f321947f2a9403c4745` and reviewed FR-08A
`5851c9be9b6d0cfb7f3fad5d41e06fa139b852bd`. Independent `git merge-tree --write-tree`
reproduces the exact merge tree without conflicts. The subsequent core commit adds
only the integration test; the evidence commit changes only the provider, report
and binding assertions. Authority, Database and ProtectedPrimitives are byte-identical
to the reviewed FR-08A parent.

Read shared workflow, Foundry orientation/strategy summary, H0/FR-08A and FR-19A/B
criteria, R1/R5 and protected/recovery contracts, H0 PASS, the FR-08A residual review
chain and final [carrier PASS](fr08a-carrier-rereview.md), accepted FR-19A
[final PASS](../fr-19a/final-rereview.md) at `95eccd6b160b6f339376cfd79e7de81f997c4ba6`,
the [combined candidate](fr08a-fr19a-integration-candidate.md), changed source and
relevant tests. Earlier green reports were treated as evidence to recheck.

All eight candidate source/report/test manifest entries and all five original local
artifact hashes match. Original CI provenance names clean `b05f834` before and after;
fresh reviewer CI names clean `176dab4` before and after. The worktree remained clean
through runtime verification. Only this review, its probe and catalog routing changed
afterward; no implementation, shared plan/log, provider, daemon, push or main integration
was changed or performed.

## Semantic composition

The combined ready state carries capability and writer epoch alongside FR-19A's
probe callback, timeout, maintenance seam and request map. Every init recovery route
uses the common bounded recovery shape, and protected reads/commands refuse before
accessing ready-only fields. Ordinary termination cancels owned probes; the independent
controller also monitors untrappable Gateway death. In the new death cases, caller,
actual probe and controller all terminate, and evidenced reopen retains the full authority
view under a successor epoch.

`Authority.read(:all)` checks legacy schema/relations/reconstruction, invokes protected
validation, and digests the complete legacy and root table registry. Checkpoint compares
the pre/post complete content and reconstructed domain state. Backup validates both
source and destination through that same authority path; offline `Maintenance.verify`
therefore includes protected replay validation without modifying Maintenance itself.
The FR-19A health/controller, checkpoint, backup and sync functions are unchanged by
the merge. The inherited FR-08A page-limit fixture adjustment remains visible in the
diff; operational health reports the effective SQLite limit.

Migration executes additive schema/marker work inside a transaction followed by complete
authority validation. The nonempty accepted-v1-shaped fixture retains all listed legacy
authority-table digests after migration and an idempotent rerun; metadata gains the
declared migration markers. Future metadata, a partial marker
and a corrupt current schema refuse, preserving the unsupported/damaged condition.
This is a disposable accepted-schema/domain-history migration test, not an old-build
rollback experiment or migration of an operator's store.

The unchanged typed replay derives ledger, reservation, effect and claim transitions
from ordered authenticated operations. Exact current values and revisions are checked;
result-carrier schemas separately enforce singular maps, flat unique plural lists and
opaque diagnostic payloads. Fresh reruns preserve rejection of issued rewinds, closed
credit reopening, hold reduction, epoch forgery, malformed/conflicting carriers and
deep quarantined ancestry. Legitimate reclaim, late receipt, closed-generation
settlement, same-ID recovery and opaque protected-shaped observations remain usable.
The legacy/root protected routes remain exclusive while ordinary domain history and
root authority coexist in the same store.

## Independent variations

The [review probe](fr08a-fr19a-integration-review-probes.exs) reuses public fixture
helpers and the six candidate cases, adding five separately asserted variations:

- Kill the Gateway during a stalled health request after issuing a claim and closing
  its ledger, for both issued and unknown outcomes. All owned processes terminate;
  the complete `Authority.read(:all)` view survives epoch-B reopen unchanged. New-epoch
  issue refuses. A late attributable epoch-A non-start settles the original hold into
  retired units: available remains zero, held becomes zero, retired becomes five.
  A subsequent verified backup retains the resulting authority.
- Fail after checkpoint, after backup snapshot creation, and at the backup-sync seam
  after issue, generation closure and a late successful receipt. Each enters recovery;
  health and protected snapshot calls refuse. The complete source view remains exact,
  with one consumed and four retired units. Both produced backup files remain present
  and pass offline full-content/replay verification. Reopen and a new verified backup
  preserve the same content and reconstructed domain state.

All eleven cases pass. The new failure controls inject explicit errors at named seams;
they do not claim a fresh physical EIO experiment. The unchanged operational suite
also runs its genuine interrupted nonempty-WAL checkpoint and VACUUM controls, and
the native sync fixture independently exercises its connection-scoped xSync failure.

## Revision-bound evidence and checks

Fresh report generation is byte-identical to the frozen artifact, SHA-256
`0506e031b5af50b43c1d0cc03a8f4553cb6bccb52135b1c4930e9001070e0800`: ready, seven
passed, zero failed/unavailable. Its nine source SHA-256/loaded-BEAM MD5 identities
bind the combined implementation. The separate negative fixture executes an altered
in-memory Gateway sentinel with unchanged source, then requires all seven capabilities
to become unavailable. It exits zero with `identity_mismatch_refused`.

H0's saved artifact is byte-identical to frozen `4c8734c`, retaining four passed and
three unavailable. The evolved live provider correctly returns zero passed and seven
unavailable because the accepted API identities no longer match.

Pinned Elixir 1.20.3 / OTP 29.0.5 / ERTS 17.0.5; review root
`/private/tmp/fr08a-combined-review.ATo238`. The saved `run.sh` selects the absolute
toolchain, isolated build/temp/runtime roots, disabled provider environment and existing
dependency sources. The canonical runner restores dependencies into its own fresh root.
The separate native sync run uses that isolated dependency/build root and its bundled
Exqlite `c_src` headers through `CPATH`.

| Check | Actual result |
|---|---|
| Forced warnings-as-errors compile | Exit 0; 110 files |
| Combined integration file, seed 20939 | Exit 0; 6 passed |
| Full focused matrix including sync fixture, seed 20935 | Exit 0; 46 passed |
| Independent combined variations, seed 20933 | Exit 0; 11 passed (6 existing + 5 new) |
| Prior acceptance/transition/typed-correction/carrier matrices | Exit 0 each; 41 / 39 / 57 / 98 passed |
| Native sync fixture with isolated CI dependencies, seed 20937 | Exit 0; 2 passed |
| Fresh report byte comparison and altered-loaded-code control | Exit 0 each |
| Exact trees, merge recreation, manifests and original artifact/provenance checks | Exit 0 |
| FR-19A host error-table/loop-identity shell regressions | Exit 0 |
| Clean frozen-candidate canonical CI | Exit 0; 612 passed, 13 skipped, 1 optional exclusion |
| Staged review documentation gate and whitespace check | Exit 0; 80 documentation tests passed |

The initial focused selection omitted the two native sync tests and passed 44 cases;
the complete 46-case invocation above supersedes that coverage count. Full CI includes
locked dependency restore/inventory, forced compile, formatter enforcement and a fresh
escript. All seven format-debt identities match; no format-debt error is present.

Selected artifact SHA-256 values, relative to the review root:

```text
bf6c1929e171c10d7aa48025feed3af5ce13ea8a099aacf062adc02241a270d5  run.sh
e01ad513ec85669e134358947c939d8faccede28ce58e47b8f2008518252b3f7  combined-probes.exs
20abae543047acf87e201e1b79397069538dbded82c0fdb8f208a7244662c659  combined6.log
e93908a66c3ebe509e422fc0b44b499d1ff33a1e5b29d05b665e1a8134f120c6  focused46.log
f2622f5925fa156ce535e3b485e3e723010fd45ea0066433819d685b3af49533  combined-probes.log
f49251db5218825b6be149114b3a4749e84dfd0e47821e9ce777d0090877483c  acceptance41.log
81b3922a80ed11f3d86138678b893ef1ae7ebb11c68492f27b31bcc43a0f39c2  transition39.log
dbfd09e475bff66b8961d34c56fe7e71b21fb960ade84b2f71207e9a22c725e2  typed57.log
22b34aa1b1fc87a33a168ca616855482659bc7a6d493f839d3bd36e4be311638  carrier98.log
b3c5f42cf415f04746dc0431b27d602169198740166a57cf0bbb1865388a6448  sync-isolated.log
ecdf4f0458b19a52826c578766a0626aee0fb3df428d9e2f1d26c35049535ba5  identity-negative.log
d16dbc86544a11755136d2887b7ed442f021e21877f3d355c2a25ed20c8b91b7  evidence.log
c7c09798902e7450eae6d03a406429041d337268e12e87d988075eb83da49e2c  ci-artifacts/provenance.json
fcc619b9d621f370e14a12d0880b591f4254d9f58ad11ecfebe767ac51b3e962  ci-artifacts/pramana_foundry
```

Run the committed additional probe from `foundry/` after compiling the checked source:

```sh
sh /private/tmp/fr08a-combined-review.ATo238/run.sh mix run --no-start --no-compile docs/fr-08/fr08a-fr19a-integration-review-probes.exs
```

## Preserved limits and separate suggestions

An exact eleven-path diff confirms the Linux workflow, raw/host/orchestration/parser
helpers, Maintenance, Linux/maintenance-crash fixtures and orchestration/workflow tests
are unchanged from accepted FR-19A main. Its credited run `35498430877`, artifact
`10601228576`, remains historical evidence at revision
`5f4984be07c67de8515a26d953d4d5b7de907c05`; it was not rerun or attributed to the
combined binary. No contradiction requiring a new privileged Linux experiment appeared.

Neither that evidence nor this review proves failed-sync persistence, physical WAL
xSync media durability, power-loss survival, controller/cache flush or deployment.
Provider/OS isolation, actual external delivery, rollback-build compatibility, FR-08B's
complete domain ingress migration and FR-19B remain separately governed. Logical
corruption probes do not establish resistance to an administrator replacing all history.
The optional Python/tiktoken recomputation remains excluded.

Nonblocking suggestion: promote the five new closed-generation maintenance/owner-loss
variations into the maintained integration suite when that suite is next extended.
Keep the precise distinction between injected seam failure and physical fault evidence.
