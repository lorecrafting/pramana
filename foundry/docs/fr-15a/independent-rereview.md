# FR-15aA focused independent rereview — BLOCKER

Historical verdict for `5a7eb463`; see the appended
[final residual-B2 review](#final-residual-b2-review--pass) for corrected candidate
`9ed32575`. The original findings and evidence below remain unchanged.

Review date: 2026-09-19. Scope: initial review B1–B3 and their necessary regression
interactions. This is specification review, not host isolation or provider conformance.

| Binding | Exact identity |
|---|---|
| Initial independent review | `edd22b21fe548bdf32818f78bc9119e205109a65` |
| Corrected substantive candidate | `5a7eb4633a0c63a12cd1bbf84c87be7ad9ef03a9` |
| Corrected substantive tree | `a4110079973c4bfdd81c44257f530f77a6daf0b6` |
| Evidence tip reviewed | `a1e05fc53ca31885407bcb2d537c3612e54b81f6` |
| Evidence-tip tree, verified with Git | `1c48f8823d2c6f6664b203c84a8233c6e3b63f9f` |

The supplied evidence-tree transcription omitted its final `f`; the table records the
full Git identity. The evidence tip changes only `evidence.md` relative to the corrected
candidate. The working tree was initially clean. The four corrected-file SHA-256 values
match the correction table in [evidence.md](evidence.md). No runtime source changed.

## Verdict

**BLOCKER: B2 remains partially open.** B1 is corrected at the required specification
level. B3's original false-success and ownership gaps have substantive corrections.
The maintained 16 tests pass, as do manifest validation, formatting and documentation
checks. However, independent mutations show the gate still accepts missing executable/
config identities and contradictory channel/route records. Those are bounded residuals
of B2's required source binding and authority relationships, not new host-proof demands.

## Residual blockers

### B2.1 — Pin metadata can erase or bypass source/config binding

`ci/validate_fr15aa.exs:326` freezes pin IDs and digest values, but does not validate
their path, kind or version. Repository-byte validation at line 355 is selected by the
manifest-supplied `foundry/` path prefix; the catch-all at line 369 accepts other cases.

The [independent reproduction](independent-rereview-probes.exs) invokes the real validator
and observes `:ok` for each of these mutations:

- Delete `path`, `kind` and `version` from every pin, keeping only IDs/digests/status.
- Change only the `foundry-config` path to `/tmp/unreviewed-config.exs`, retaining the
  expected digest. No file is created or read there; the repository-byte check is skipped.

Thus an exact digest string does not establish which executable/config artifact the
declared dependency denotes. The first mutation also removes all proposed adapter paths
while preserving a valid result. FR-15aA explicitly requires exact executable/config
versions and the original B2 correction required source/config pin binding.

Required correction: validate the expected identity tuple for each pin, including its
kind, version, path and exact disposition; select required repository-byte checks from
trusted pin identity rather than an optional caller-supplied prefix. Preserve explicit
blocked/unimplemented artifacts. Add negative controls for erased metadata and redirected
repository pins. Rehashing installed host/provider artifacts is not required by this review.

### B2.2 — Duplicate IDs silently discard unsafe channel and shell declarations

Channel validation at `ci/validate_fr15aa.exs:284`, pin validation at line 327 and route
validation at line 372 convert the lists using `Map.new/2`. No uniqueness check precedes
that conversion. Only the last declaration for a repeated ID is examined.

Independent mutations return `:ok` after prepending either:

- A `model-request` channel granting `slot_developer` access, followed by the original
  harness-only channel with the same ID.
- A `shell` route assigning `root` and `model-request`, followed by the original restricted
  shell declaration with the same ID.

The manifest is a list-based specification and declares no last-record-wins semantics.
Its gate therefore accepts contradictory authority instructions while claiming to reject
root shell and worker auth access. This finding does not claim a current runtime exploit;
all production routes remain blocked.

Required correction: reject duplicate IDs before reducing inventories to maps, including
channels, routes and pins. Retain tests that show both duplicate orderings are rejected,
so a future consumer cannot disagree with validation about the selected declaration.

## Corrections verified

| Original finding | Focused disposition |
|---|---|
| B1: missing kernel boundary | Corrected in principal, artifact, protocol, socket, capability, provision/rollback identity and required positive/forged/stale-epoch probes. Root never loads the candidate kernel; autonomous exact-candidate repair remains allowed under root gates. |
| B2: original seven mutations | Maintained tests reject account collapse/login, erased channels, unsupported promotion, root/auth shell reassignment, absent source/host profile, zero hashes and package-lock-only dependencies. The two residuals above prevent closure. |
| B3: source versus tool checkout | Separate source/specification checkouts and approved specification commit/tree checks replace the nonexistent base-validator invocation. |
| B3: collisions and unknown observations | The actual section 8.2 shell block, executed with synthetic `dscl` functions, accepts all-absent and rejects user-name, group-name, UID and GID collisions plus read/list observer errors. No directory-service command reaches the host. |
| B3: rollback and ownership | Pure checks reject earlier-present/final-absent and observer-error observations. Created-only selection preserves preexisting, modified-preexisting and absent-not-created records; missing ownership refuses. Prose now requires pre-change backups, attempt ownership and durable per-mutation records, with archive/recovery requirements for partial installs. |

Additional independent mutations reject removal of kernel forbidden fields, removal of
the current-writer-epoch check, a single worker auth-channel grant and declaring the
unimplemented kernel adapter implemented. These successful denials help distinguish the
remaining duplicate/metadata defects from wholesale failure of the correction.

## Suggestions, not blockers

- Reconcile the manifest's `ipc` route text, which still says the worker has an assigned
  `effect.sock` endpoint, with the channel's harness-only callers and the specification's
  worker-owned pipe. The structured channel and prose establish the intended separation.
- When implementing B, share observer parsing between procedure and tests. The pure
  process helper treats nonempty output with exit 1 as unknown; the rollback shell block
  only checks exit 1. No actual observer/isolation behavior is certified here.
- Keep the rollback selector explicitly scoped to deletion eligibility. Backup restoration,
  attempt identity, durable mutation recording and current resource identity still require
  implementation and host acceptance in B; the pure selector is not that proof.

## Checks and limits

Environment: `/private/tmp/pramana-fr15aa`, branch `repair/fr15aa-provisioning`,
Elixir 1.20.4, OTP 29 / ERTS 17.0.6. These standalone checks do not claim execution under
the pinned Foundry CI toolchain.

| Command | Result |
|---|---|
| From `foundry/`: `elixir ci/validate_fr15aa.exs` | Exit 0, manifest valid |
| From `foundry/`: `MIX_ENV=test elixir -r test/test_helper.exs test/pramana_foundry/repair/fr15aa_provisioning_test.exs` | Exit 0, 16 passed, seed 3393 |
| From `foundry/`: `mix format --check-formatted ci/validate_fr15aa.exs docs/fr-15a/provisioning-manifest.exs test/pramana_foundry/repair/fr15aa_provisioning_test.exs` | Exit 0 |
| `elixir bin/check_docs.exs` before review additions | Exit 0, 80 passed, seed 119662 |
| `elixir bin/check_docs.exs` after review additions | Exit 0, 80 passed, seed 260311 |
| From `foundry/`: `mix format --check-formatted docs/fr-15a/independent-rereview-probes.exs` | Exit 0; formatted reproduction rerun also exit 0 |
| `git diff f5067d96d67a9ec3193a9b8bbadfa54c16525aa3..HEAD --check` | Exit 0 |
| `elixir foundry/docs/fr-15a/independent-rereview-probes.exs` | Exit 0: four residual accepted mutations, four correct rejections, seven mocked preflight outcomes and rollback decisions reproduced |

The reproduction deliberately expects the residual defects to remain reproducible at
this exact candidate. Its exit 0 is not acceptance of those hostile inputs. The initial
review/probe files remain unchanged historical evidence.

I read AGENTS/shared workflow, Foundry index/strategy summary, the FR-15a ticket and
FR-06 R2/R3 authority/isolation requirements, initial review, corrected specification,
manifest, validator and maintained tests. No provider/model, credential, daemon, Herdr,
network acquisition, account creation, sudo, host provisioning or installation occurred.
Full Foundry CI and checkpoint-F provider fixture were not rerun. Actual isolation,
useful isolated build/test, FR-09 subscription conformance and deployment remain unproved
and gated. OMP remains governing; Pi remains unselected. Only review/evidence files are
added by this rereview; shared plans and ticket status are untouched.

## Final residual-B2 review — PASS

Review date: 2026-09-19. This renewed review is limited to B2.1/B2.2 above and
necessary B1/B3 regression interactions. **PASS for the corrected FR-15aA
specification candidate; no remaining blocker in this bounded review.**

| Binding | Exact identity |
|---|---|
| Prior focused review | `5902944c065185ebbc3d716749cecd5eab0fdfdc` |
| Corrected substantive candidate | `9ed32575f2840e90fe3e1ebb1f1ebcd0bd54040b` |
| Corrected substantive tree | `1c5dd96f0da66286ecb47eec029c09b2f3733802` |
| Evidence tip reviewed | `a5cb96b11131f356f638c34b693e9223f8f6f0d4` |
| Evidence-tip tree | `ffed42475ea65739ddf953152c02ce5e1dbb81e4` |

Git confirms these identities. The substantive diff changes only the validator,
specification introduction and maintained focused test; the evidence-tip diff changes
only `evidence.md`. The three corrected-file SHA-256 values match its residual-correction
table. The worktree was initially clean.

### B2.1 closed: complete pin identities and trusted repository reads

The validator now requires the complete frozen pin inventory and each pin's exact kind,
version, path, status and digest (`ci/validate_fr15aa.exs:461`). Repository reads at
line 509 are selected by the validator's trusted repository-pin ID set and use the
expected path/digest taken from its constants at line 477, not the manifest's path.
The repository root is anchored to the validator location. Removing or redirecting a
manifest path therefore cannot select or suppress a required repository-byte check.
Explicit unresolved/blocked artifacts remain supported as blocked specifications.

The [new independent probes](independent-final-review-probes.exs) reject individual
erasure and alteration of all six identity fields (`id`, `kind`, `version`, `path`,
`status`, `sha256`) for every pin. They also rerun the precise prior whole-inventory
metadata-erasure and redirected `foundry-config` mutations: both now return errors.
Trusted path selection was additionally verified by source inspection; no installed
host artifact was rehashed or provisioned for this review.

### B2.2 closed: uniqueness precedes indexing

`validate/1` now checks security-collection uniqueness before invoking semantic validation
or constructing inventory maps. This covers principal, channel, pin and route IDs, nested
channel callers and route dependencies, and kernel allowed-operation, forbidden-field
and root-check lists. The individual map-building functions also retain local guards.

Independent probes reject contradictory principal, auth-channel, pin and shell-route
records in **both declaration orders**, returning the explicit duplicate-ID error.
The exact earlier worker-auth and root-shell duplicate cases therefore cannot disappear
behind a later valid record. Nested duplicate grants, dependencies and each of the three
kernel authority lists are also rejected.

### Regression boundary and suggestions

The manifest, kernel protocol/principal definitions and provisioning/rollback procedure
are unchanged from the prior focused review. The pure B3 procedure module is unchanged;
the maintained suite continues to exercise its observer and ownership cases. The prior
B1/B3 dispositions and nonblocking suggestions above stand. There are no additional
blocking or scope-expanding requirements from this renewed review.

### Fresh checks and limitations

Commands ran in the same dedicated worktree with Elixir 1.20.4 / OTP 29 / ERTS 17.0.6.

| Command | Result |
|---|---|
| From `foundry/`: `elixir ci/validate_fr15aa.exs` | Exit 0, manifest valid |
| From `foundry/`: `MIX_ENV=test elixir -r test/test_helper.exs test/pramana_foundry/repair/fr15aa_provisioning_test.exs` | Exit 0, 22 passed, seed 621764 |
| From `foundry/`: `mix format --check-formatted ci/validate_fr15aa.exs docs/fr-15a/provisioning-manifest.exs test/pramana_foundry/repair/fr15aa_provisioning_test.exs` | Exit 0 |
| `elixir bin/check_docs.exs` before review updates | Exit 0, 80 passed, seed 659358 |
| `elixir bin/check_docs.exs` after staging review updates | Exit 0, 80 passed, seed 563532 |
| `elixir foundry/docs/fr-15a/independent-final-review-probes.exs` | Exit 0, all expected rejections observed |
| From `foundry/`: `mix format --check-formatted docs/fr-15a/independent-final-review-probes.exs` | Exit 0 |
| `git diff 5902944..a5cb96b1 --check` | Exit 0 |

The two earlier reproduction scripts remain historical and deliberately retain their
old expectations. The final probe expects rejection and is the renewed review evidence.
Full Foundry CI, installed host/provider artifacts and actual isolation were not tested.
No host accounts, credentials, network policy, provider/model, daemon, Herdr, acquisition,
installation, push or integration was used. Actual principal/channel/auth/network denial
and useful isolated execution remain FR-15aB; installed OMP/subscription conformance remains
FR-09. OMP remains governing, Pi remains unselected, and no production capability is enabled.
This PASS closes the reviewed specification blockers only; it does not change the shared
repair plan or grant operational authority.
