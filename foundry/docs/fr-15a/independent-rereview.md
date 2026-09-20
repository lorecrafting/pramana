# FR-15aA focused independent rereview — BLOCKER

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
