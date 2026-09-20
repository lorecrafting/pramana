# FR-15aA independent review — BLOCKER

Review date: 2026-09-19. Independent review of the frozen specification candidate,
not FR-15aB isolation or FR-09 installed-harness acceptance.

| Binding | Exact identity |
|---|---|
| Base commit | `f5067d96d67a9ec3193a9b8bbadfa54c16525aa3` |
| Base tree | `f19af86efd775fa0debd75868f571b13feaa748d` |
| Substantive candidate | `ca4094e2d43212c3399ab5458e9af64c40640c14` |
| Substantive tree | `8b027b4ef29c830215461cd7e3a89df81e8f4971` |
| Evidence tip reviewed | `9b9b0984166dd25e736b7da0767520fc34f973b5` |
| Evidence-tip tree | `3bb5246dc2015437679399bdeb04af2b94c498f4` |

The exact diff from the base contains only the validator, manifest, specification,
focused test, evidence record and Foundry index link. The evidence tip changes only
`evidence.md` relative to the substantive candidate. I independently checked the
recorded SHA-256 values of the validator, manifest, specification and focused test.
No runtime implementation changed. This review adds only this record and the
[reproduction script](independent-review-probes.exs).

## Verdict and boundary

**BLOCKER for FR-15aA completion.** The document correctly keeps OMP governing, Pi
unselected, all production routes blocked, and the useful checkpoint-F path explicitly
unisolated. It supplies substantial inventory and useful future denial cases. However,
the kernel boundary is missing, the executable validator accepts contradictory and
unsafe specifications, and the proposed provisioning/rollback checks do not reliably
stop on failed observations. These are A-level inventory/procedure defects; closing
them does not require creating accounts or proving actual isolation early.

I do not require FR-08A/B primitives, FR-15aB adapters or host proofs, real subscription
entitlement, or OMP/Pi/Herdr conformance to exist in A. Their blocked dispositions are
appropriate. The existing tests prove a small structural validator, not that the
provisioning specification is complete or fails closed under the contract it declares.

## Blocking findings

### B1 — The repairable workflow kernel has no isolation/protocol/provisioning route

[FR-06 R3](../WORKFLOW-CONTRACT.md#r3) requires the candidate workflow kernel to run
under a separate restricted account and submit bounded bundles to the protected
verifier. Root must not load that candidate into its own BEAM. The FR-15aB acceptance
also explicitly requires isolated-kernel forged budget/acceptance-event denial.

The principal table in `provisioning-specification.md:141`, maximum-capability table
at line 165, manifest principal list at line 250, and validator's required principal
list at `ci/validate_fr15aa.exs:13` have no workflow kernel. No route describes its
command ingress, projection/bundle protocol, protected write gateway, old writer epoch
fencing, admission/rejection probes, installation or rollback. The runtime row does
not supply this implicitly: its declared maximum is start/stop/health of an accepted
release, and its listed route is launcher access, not the R3 transaction protocol.

Required correction: explicitly bind the kernel executable/config, restricted
principal (or an explicitly justified restricted runtime mapping), owned state,
transport/peer authorization, maximum proposal operations and forbidden root-derived
fields. Include its provisioning/lifecycle/rollback and positive/forged-event/stale-epoch
probe requirements in the manifest and validator. Preserve autonomous exact-candidate
kernel repair under root gates. This specifies the B work; it need not implement it.

### B2 — The manifest gate accepts loss of its essential boundaries

The validator checks principal/channel IDs and route string presence, but never checks
principal account/trust/login or channel path/transport. Its route status check allows
`supported` without evidence and stops requiring `fail_closed` for that status. Pin
references need only name any existing pin, even a package lock. Source identity and
host profile are ignored. Digest validation checks hexadecimal shape, not the frozen
repository files or an explicit unresolved-artifact disposition.

The independent reproduction script invokes the actual candidate validator. All seven
hostile mutations return `:ok`:

| Mutation | Observed result |
|---|---|
| Set every principal's account to `root` and login to `true` | `:ok` |
| Remove every channel's transport and path, retaining only IDs | `:ok` |
| Mark every route supported and fail-open while adapters remain unimplemented | `:ok` |
| Assign shell execution to root over the model-request channel | `:ok` |
| Remove source provenance and host profile | `:ok` |
| Replace every non-placeholder pin digest with 64 zeroes | `:ok` |
| Replace every route's executable dependencies with only the package lock | `:ok` |

These do not enable current production execution: the global disposition still says
blocked. They demonstrate that the claimed machine-readable source of truth cannot
enforce even its own proposed principal/channel/dependency separation, or distinguish
an unsupported specification from a supported one. The four existing negative tests
exercise deletion of a category, one empty string, one boolean and one authority label;
they do not challenge these relationships.

Required correction: encode and validate the protected relationships as structured
data: principal identity/separation, approved channel endpoints and caller/callee grants,
route-to-principal/channel/dependency constraints, capabilities and evidence/status
consistency, and source/config pin binding. Explicitly unresolved artifacts may remain
blocked. Add negative controls for the mutations above and the missing kernel. Do not
equate a `fail_closed: true` assertion with actual host denial; the latter remains B.

### B3 — Provisioning and rollback contain false-success and ownership gaps

The proposed procedure has several concrete defects independent of unavailable B
artifacts:

- `provisioning-specification.md:332` requires the base checkout, then runs a validator
  at line 336 that does not exist in that checkout. `git show
  f5067d9:foundry/ci/validate_fr15aa.exs` exits 128 with that exact absence. Distinguish
  the frozen source-input identity from the reviewed specification/tool artifact.
- The account preflight at lines 362–364 does not check group-name collisions; an
  existing `/Groups/_pramana_*` with a different numeric ID passes the listed checks
  before the procedure writes that record. The loop also does not aggregate failure
  or explicitly stop at a failed check. Directory-service command failure can be
  mistaken for absence by negation/pipelines.
- The rollback loop at lines 489–491 returns the last principal's result. An earlier
  live principal followed by a final absent principal yields success. Negating an
  observer error also yields success. The socket check at line 492 discards observer
  failure with `|| true`, so failure to inspect sockets can satisfy the empty-output
  test. The independent script reproduces all three with shell functions; no actual
  host processes or sockets are inspected.
- Rollback requires a recorded pre-provision packet-filter backup, but provisioning
  never specifies creating/verifying that backup or a ledger of resources actually
  created by this attempt. A partial installation therefore lacks a precise ownership
  record for deciding which account/group/path/label may be removed.

Required correction: provide an explicit stop-on-error procedure whose observer
results distinguish present, absent and unknown; check both names and numeric IDs;
bind specification and source revisions separately; record preexisting state and
exact created resources before mutation; preserve that record for partial-install
rollback. Exercise these decisions with synthetic observers and no privileged host
changes. Prose saying to stop on failure does not repair a check that reports success
on an unknown observation.

## Surface review and deferred proof

| Surface | A-level assessment |
|---|---|
| OMP/Pi/Herdr launch and presentation | Current legacy paths and Pi failure evidence named; OMP correctly governs. Remote tools and presentation remain explicitly blocked. |
| Root/kernel/auth/harness separation | Root/auth/harness are described; kernel omitted (B1). Non-root launcher is assigned cross-account launch/cleanup, but the fixed privileged executor and exact allowed operation channel still need an explicit mapping. |
| Request auth, R1/R5 and retries | Reserve/claim/issue/unknown-settlement sequence, immutable provider route and per-continuation/retry claims are specified. Actual enforcement belongs to B/FR-09. |
| Shell/file/custom tools/extensions/startup | Typed bridge, path escape denials, explicit and bundled extensions, MCP/skills and neutral startup are addressed in prose. Machine relationships are unenforced (B2). |
| Hooks/LSP/subprocesses/env/FD | Hostile cases and unavailable LSP disposition are present. Full descendant cleanup remains a B proof; no same-user fixture is claimed to prove it. |
| Network/proxy/IPC/process memory | Denials and positive auth/fetch probes are named; actual macOS filter/peer/process enforcement remains unproved and blocked. |
| Git and shared state | Disposable views and protected common metadata are specified. Exact controller import/object verification remains implementation work; shared worktree evidence is correctly treated as a failure. |
| Acquisition/build/runtime | Scoped immutable fetch, isolated build inputs/outputs, accepted runtime and no direct credential route are specified. The machine inventory does not enforce their relationship to policy/pins (B2). |
| Allocation/cleanup/reuse | Quarantine on uncertainty and issued-effect reconciliation are good requirements. Rollback observations violate the same principle (B3). |
| Provisioning/rollback | Commands exist but are not reproducible/fail-closed as written (B3). No host commands were executed during this review. |

## Suggestions, separate from blockers

- In the next inventory revision, add explicit host OS/build/architecture and helper
  executable pins or blocked pin-acquisition requirements for Python, shell, Git,
  process observers and packet-filter/launchd tooling. Current source pins identify
  callers but not all their resolved binaries. This is particularly useful for the
  check trampoline, `Effects.ProcessGroup`, and controller-side Git operations.
- Spell out how `_pramana_launcher` requests the fixed privileged UID switch/cleanup
  operation while the verifier is the only root service; a capability token alone is
  not the OS mechanism. Also resolve the mismatch between worker `effect.sock` access
  in the manifest's IPC route and the prose's harness-only socket plus worker pipe.
- Preserve the honest distinction between manifest validation, raw useful feasibility,
  and conformance. A future gate should emit which tier it checked, with exact inputs.
- Correct the OMP digest transcription at specification line 62: it starts
  `e0302a99643efb62`, whereas the machine manifest starts `e0302a99643efefb62`.
  Generate or check this repeated pin so the human procedure cannot compare against
  a different value from the declared machine-readable source of truth.

## Checks and limitations

All checks ran in `/private/tmp/pramana-fr15aa` at evidence tip `9b9b098`, with only the
two review files added afterward. Working tree was initially clean.

| Command | Result |
|---|---|
| From `foundry/`: `elixir ci/validate_fr15aa.exs` | Exit 0, manifest valid |
| From `foundry/`: `MIX_ENV=test elixir -r test/test_helper.exs test/pramana_foundry/repair/fr15aa_provisioning_test.exs` | Exit 0, 5 passed, seed 284860 |
| From `foundry/`: `mix format --check-formatted ci/validate_fr15aa.exs docs/fr-15a/provisioning-manifest.exs test/pramana_foundry/repair/fr15aa_provisioning_test.exs` | Exit 0 |
| `elixir bin/check_docs.exs` | Exit 0, 80 passed, seed 496428 |
| `elixir bin/check_docs.exs` after adding review evidence | Exit 0, 80 passed, seed 157559 |
| `git diff f5067d9..9b9b098 --check` | Exit 0 |
| `MIX_ENV=test elixir foundry/docs/fr-15a/independent-review-probes.exs` | Exit 0 reproducing seven accepted hostile mutations and three false-success shell checks |
| `git show f5067d9:foundry/ci/validate_fr15aa.exs` | Expected exit 128: validator absent at the required preflight base |

The reproduction script is historical review evidence: its success means the frozen
defects reproduced, **not** that hostile inputs were denied. It should not be used as
an acceptance gate after correction.

I read AGENTS, the shared workflow, Foundry index/working strategy summary, the FR-15a
ticket and relevant FR-06 authority/identity/protocol sections. The requested legacy
`docs/CODE_CONVENTIONS.md` does not exist; the current Elixir convention router and
file were used. I inspected the full candidate specification/manifest/validator/test
and bounded current launch/check/Git/process source paths. No provider, credentials,
daemon, paid execution, network acquisition, host provisioning or sudo command was
used. Full Foundry CI and the checkpoint-F provider fixture were not rerun. No actual
isolation, subscription or deployment claim follows from these checks.

FR-15aA remains blocked pending correction and independent re-review. FR-15aB, FR-09,
Pi selection and automatic execution remain gated exactly as before.
