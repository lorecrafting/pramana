# Foundry repair implementation log

This supplements [REPAIR-PLAN.md](REPAIR-PLAN.md), which remains the authoritative
ticket, status, and dependency backlog. It records candidate provenance, independent
review, integration decisions, executable evidence, limitations, and resumable next
steps.

## Coordination baseline — 2026-09-12

- Coordinator branch: `main`; starting HEAD
  `a3fa302342238ae3d5a133b35bd86f4fa4f13710`.
- The starting working tree was not clean. Tracked edits already existed in
  `docs/PLAN.md`, `foundry/README.md`,
  `foundry/lib/pramana_foundry/cli.ex`, and
  `foundry/lib/pramana_foundry/coordinator.ex`. The audit, repair/design documents,
  `foundry/docs/audit-2026-09-12/`, `foundry/docs/fr-06/`, and three review JSON
  artifacts were untracked. These inputs belong to earlier work and must not be
  absorbed, reset, or represented by HEAD alone.
- FR-06 v3 manifest SHA-256:
  `27e8315697ad84db96dfbcf985f2055014b3065c91561c5c6cba7067d307dd38`.
  `shasum -a 256` plus a `jq`-generated entry check verified every listed file
  against `foundry/docs/fr-06/manifest.json`; no unexplained drift was present.
- Active ownership: `/root/fr06_r4a_verify` is a fresh Astra-high independent,
  read-only-in-place reviewer whose only permitted write is
  `foundry/docs/fr-06/r4a-focused-review.md`. It is reviewing the frozen v3 input
  set and only R4a plus necessary R1/R5 interactions.
- FR-06 focused review completed **PASS** against all 15 exact v3 manifest inputs.
  Review: `foundry/docs/fr-06/r4a-focused-review.md`; SHA-256
  `51b40e94e097ceb9de581901ca7187d1ace8593907718f924b6a0d910861f32f`.
  It found no design blocker and two nonblocking implementation-precision suggestions.
  Status-only edits now record the design gate complete; FR-07 still waits for FR-03.
  Those documented status edits intentionally advance manifest-listed files after the
  review: current SHA-256 values are REPAIR-PLAN
  `01d649f331be44db27b5fd500c8cfaeac8aea427b9c3a9819745b3ec06af06a5`,
  WORKFLOW-CONTRACT
  `5d1621ff98fcb1aad2d6d37ba523b2a00c6bf90120873ffeb2518f23fd831488`,
  and root PLAN
  `1d887ddb995adc95818192766ea33da966004b6755ced053d1e0db2de8f3059f`.
  The unchanged v3 manifest remains the exact reviewed input inventory rather than
  being rewritten to make these later disposition edits appear pre-reviewed.
- FR-01 implementation owner: `/root/fr01_impl` (Sol-medium). Permitted production
  scope is the common launch-eligibility boundary and the three autonomous launch
  call paths in `agent_server.ex`, `coordinator/tick.ex`, and `coordinator.ex`, plus
  narrowly necessary configuration/support modules and FR-01 tests. It must not edit
  CLI/startup/persistence, activation, dynamic switching, live state, or coordination
  documents. Starting SHA-256 values: AgentServer
  `10c19bdf3c2ce4c526d5eac9765141404a35982e68e816c6045bb94498cd2bb6`, Tick
  `3a94a8eae4fae1408a2647d9a34b726a31fa7ee7814ac03bec19bc3b61c1bb78`,
  Coordinator working-tree bytes
  `1e184cf4c52f500ad2859f6e883a5508ec83e50da2ca1811a281673c7e1cf30`,
  quota fallback
  `be6842ec8999f273e5f257e630f00a321cfe0fab9c173d91b0994c021ed4e1fd`,
  HardeningPM
  `e1ec8812709b9fe374536481c1d4ba4c81edd1e238695a125cb4a72724eda3c4`,
  and config
  `a87273cd866e5eb6d4af90d74ea588d6a6585717245062e65e571a1e125a4440`.
  The Coordinator hash includes an earlier uncommitted `unblock_ticket` change that
  the FR-01 owner must preserve and not claim.
- No daemon, provider, credentials, live panes, deployment, or paid execution was
  touched while establishing this baseline.

### Resumable next steps

1. Receive and inspect the bounded FR-01 implementation candidate without changing it.
2. Independently review the exact FR-01 candidate after its acceptance checks.
3. Dispose the focused FR-06 verdict; update the authoritative plan only if its
   design gate genuinely passes.
4. Continue ready containment tickets by dependency and shared-file ownership.

## FR-01 candidate v1 — frozen 2026-09-12

- Implementer: `/root/fr01_impl` (Sol-medium). Candidate base: HEAD
  `a3fa302342238ae3d5a133b35bd86f4fa4f13710` plus the recorded starting dirty
  tree. No commit represents this candidate; the following working-tree hashes bind it:
  `agent_server.ex` `43509a080f9f7b3d415364230e53293a9f35988f09f36f575da43aa212b09099`;
  `coordinator.ex` `396f648c6710b21d6d0e639fd06f374e5def7fdb29d5501b5625df562a1bbbe0`;
  `coordinator/tick.ex` `d0df5a69a4b6bff1ea1dc9a8aef2d70e10ba2d5881e66e90920926e8a911215a`;
  new `launch_eligibility.ex` `cd5fd0aafe88144da42d1cccaeeab30f06fb12931c5db564a48b610823afd11f`;
  `agent_server_test.exs` `e29997f9f340aec78687b227dcd30dfd4aa79672c5f54de455c4870ea37f61c1`;
  and new `autonomous_launch_test.exs`
  `8916a95b63a4bdb5e9df4c10ab441b6f97b484ba75f3e0d0ae41153dbd3f9f5a`.
- Scope disposition: common fail-closed eligibility plus developer Tick, initial
  reviewer, reviewer retry, and AgentServer defense in depth. No autonomous PM model
  caller exists; role `:pm` is guarded and exercised without inventing that path.
  No manual paid path was found or changed. FR-16 switching remains excluded.
- Acceptance evidence: focused model-free tests `14 passed`; supporting
  quota/review/recovery/state tests `18 passed`; compile with warnings as errors passed;
  new-file format and `git diff --check` passed. An application-started isolated suite
  using a fresh `/tmp/pramana-fr01-full.XXXXXX` root, explicit test-only subscription
  policy, tick disabled, provider environment removed, seed `424201`, and no exclusions
  passed `313` tests in `54.1s` (exit 0). The exact command is retained in the
  coordination transcript; no provider or live daemon was used.
- Limitations: repository-wide formatting remains red on pre-existing debt. A diagnostic
  `--no-start` sweep was not treated as acceptance because application-dependent tests
  cannot pass in that mode. Candidate v1 is frozen pending independent Astra-high review;
  any behavior change requires renewed review.

### FR-01 independent review v1

- Reviewer: `/root/fr01_review` (Astra-high); review SHA-256
  `aa3d332d6dd236b7539834ebd1bf0fd006623d1ad344a7b0cb6728097930e03e`.
  Verdict: **FAIL**. The six frozen candidate hashes remained exact.
- Blockers: B1, validated subscription/account/reasoning metadata did not bind the
  actual OMP argv and allowed a subscription-labeled OpenRouter model; B2, malformed
  nested policy values could authorize or raise instead of blocking; B3, retained
  developer timeout/crash messages could erase a reviewer-eligibility block and queue
  another developer.
- The review independently reran `14` focused tests and warnings-as-errors compilation,
  then reproduced all three blockers with model-free probes. No provider, daemon, live
  state, or credentials were used. Candidate v1 remains historical evidence and FR-01
  remains open. Next: bounded correction by the same implementer, new hashes/tests, and
  renewed independent review.

### FR-01 candidate v2 — frozen after correction

- Implementer corrected only review B1–B3. Current hashes: `agent_server.ex`
  `505ebd8a8e9de1b61c05dcac02e6597c0367b54df52c4f3800174b7b1a467057`;
  `coordinator.ex` `1f7f65a5ebb8b6690e7ae8ee1b2a402cb8eee4d4511ae6964719f6d0cc2f3b0d`;
  `coordinator/tick.ex` `8d06d93b001aef78928f0980eee940c2629ffadc4fc04fd27de14afe4b691f7c`;
  `launch_eligibility.ex` `89d8f2170a89f76c05173b298880919d4bf3b6b8f648c58168f8eab22f65f0e6`;
  `agent_server_test.exs` `914d266e4e48096076e2f412de601fb6a8aa68df444ccdf1195a8e41d0411f46`;
  and `autonomous_launch_test.exs`
  `5a47b10095d8734599eeab5f0092cb03fb01d01ef7f66719ac2db2abc8c26fec`.
- B1 now binds configured account to OMP `--profile`, provider to `--provider`, model
  to an explicit `allowed_models` member, reasoning to `--thinking`, and approval mode
  to its actual flag. B2 validates nested profile/mapping/quota/cooldown shapes and
  refuses malformed explicit selections. B3 conservatively preserves reviewer blocks
  across developer completion/timeout/crash and prevents subsequent Tick launch.
- Evidence: focused suite `20 passed`, application-started supporting suite `46 passed`,
  and warnings-as-errors compilation passed. Fresh full suite: `316/317` passed with
  two integration-tag exclusions; its sole failure was a 60-second timeout in the
  pre-existing Python `tiktoken.get_encoding` projection benchmark, reproduced alone
  and not repeatedly retried. `git diff --check` and new-file formatting passed.
- Candidate v2 is frozen for renewed Astra-high review. Static configuration, real
  entitlement/quota refresh, protected policy, provider smoke, dynamic switching, and
  durable recovery remain explicitly deferred to their owning tickets.

### FR-01 independent review v2

- Reviewer: `/root/fr01_review` (Astra-high); review SHA-256
  `89ae66d382c3dc3f5dc5cf82b73cb9458c342c9731df522c3d00d8853373b06e`.
  Verdict: **FAIL**; all six v2 hashes remained exact.
- V1's ordinary B2 cases and named B3 timeout/completion/crash cases passed, but
  residuals remain: installed OMP profile selection does not exclude stored/environment
  API-key fallback and fuzzy model matching; non-enumerable struct maps can still raise;
  and a late `agent_launched` failure can requeue reviewer-blocked work.
- The safe containment disposition is to make route enforcement an explicit trusted
  backend capability: the current system Herdr/OMP runner remains unsupported and
  automatic launches stay blocked until FR-09/15a prove that route. Deterministic fake
  backends may advertise the contract for model-free acceptance. Next candidate must
  also reject noncanonical selectors/structs and preserve reviewer blocks against every
  launch callback before renewed review.

### FR-01 candidate v3 — frozen after strategy correction

- Candidate source/test hashes bind twelve files; combined reported diff digest:
  `92d6c10585c75b3db27c5c7d8943f92972ed627047bc8dadff2a9492873b876f`.
  Full SHA-256 inventory: AgentServer
  `1a8dbcd8d14a3f21034d50517bd797977f44a6c592d0940bbeaf0a16a80c7949`;
  Coordinator `241643abf3a1be26d808bfc26055ca9f66665297400ce93b517855f5fa2db0e7`;
  Tick `e4a40c7c9c056b9ca1801724ab5de40d10e0cf45a408f3c60e76238dac0669d5`;
  Herdr Adapter `4ec26d65483c3c5321cab05b14beb4573f39c3131d211dc18b44aa65970c49cf`;
  Herdr Runner `1df506bc0444df2326de7fd9328e72038d990e2bbc36f5c9e038abbbc0fa2650`;
  LaunchEligibility `26c747c2abc332df0e07f1f6f38342b57bd150370766de38129230b000e82e74`;
  AgentServer test `914d266e4e48096076e2f412de601fb6a8aa68df444ccdf1195a8e41d0411f46`;
  autonomous-launch test
  `2afdc9c2c4ee9636a5c64c14e7d9baf9a0bf8f0d50107131fffa9b2c166bb611`;
  board test `cd455afc307d9fd3b9794d2d8862d817b848016a632f7dc438f02f38c8ca6637`;
  Coordinator engine test
  `e0471669fc52ff8db46efebcb75bda90b9e4bba1e8a1cb610602c200da20fa7c`;
  Coordinator test `c2068847f4497e56a9c65180b670c7347e7fb2b925a1f2f8a2454e3e4b0b25a2`;
  and fake runner `c84f22d4f0e2abf518753f785f74a85682e423a8c4d58c42a9692ea37063cf7e`.
  Coordinator verification reproduced every value before review dispatch.
- The runner contract now exposes an optional trusted subscription-route capability.
  The production System runner explicitly returns `:unsupported`; absent, invalid, or
  raising capability callbacks fail closed. Consequently no current real automatic
  launch is possible. The deterministic fake advertises `:enforced` for model-free
  contract tests. Selector validation rejects whitespace/noncanonical/fuzzy model
  values and structs. Reviewer blocks survive launch success/failure as well as
  completion/crash callbacks.
- Evidence: focused `24 passed`; supporting `32 passed`; affected application-started
  fixtures `6 passed` with `23` nonselected tests excluded; compile, new-file format,
  and diff checks passed. The sole full run occurred before those fixture corrections:
  `316/321`, two integration exclusions, with exactly the six subsequently selected
  assertions represented by five obsolete fixture locations failing. No second full
  run was requested before review.
- Candidate v3 is frozen for a third Astra-high review. If it passes, the coordinator
  will run the integrated full suite and must not claim current OMP/provider conformance;
  that remains FR-09/15a acceptance.

### FR-01 independent review v3

- Reviewer: `/root/fr01_review` (Astra-high); review SHA-256
  `61cb17470cf0d35658050c34b7643d1ee0bc28418fd44a38cfd7aff330452f11`.
  Verdict: **FAIL**; all twelve frozen hashes matched.
- Earlier B1 production-route and B3 late-event blockers are resolved. The production
  System runner remains deliberately unsupported, and reviewer blocks survive every
  inspected launch/completion/crash callback.
- One bounded validation blocker remains: improper configured lists can raise during
  enumeration, and `$`-anchored selector regexes accept a terminal newline. Neither
  residual permits a production launch, but both violate the total/canonical validation
  contract.
- Independent evidence: focused `24 passed`, supporting `44 passed`, affected fixtures
  `29 passed`, warnings-as-errors compilation and diff checks passed. No provider, live
  daemon, credentials, activation or live state were used.
- Next: the same implementation owner will exhaustively correct proper-list and
  whole-string validation under Rule 41, add public-boundary probes, freeze v4, and
  return it to the same independent reviewer. No architecture or lifecycle change is
  authorized by this correction.

## Integration record

- Commit `5179f34` (`docs(foundry): establish repair baseline and FR-06 gate`) records
  the dated audit, authoritative repair plan and workflow contract, complete FR-06
  design/review chain, focused R4a PASS, project-plan/README routing, and this
  coordination log. It contains no FR-01 runtime source and no unrelated CLI or review
  scratch artifacts.
- The audit probe artifact retains one pre-existing trailing space at line 3, so a
  staged `git diff --check` reported that historical artifact. It was preserved byte for
  byte rather than silently rewriting the dated audit evidence; candidate runtime diffs
  remain subject to clean diff checks.

## Ready-ticket investigations (read-only)

### FR-02

- `/root/fr02_investigate` confirmed a disjoint implementation can own only
  `bin/pramana`, a new inert RPC decoder/dispatcher module, and new wrapper-boundary
  tests. The current `cli.ex` SHA-256 is
  `27728e8be65d71ba482ed97bb73700546ebafa85caed6a5d5e3fe7a73240beed`;
  its sole pre-existing `ticket unblock` diff remains excluded.
- The proposed boundary is a versioned JSON argv envelope encoded as canonical URL-safe
  base64, and passed to one fixed Elixir expression. The decoder must enforce exact
  keys, command shapes, a size bound and literal UTF-8/NUL rules before calling CLI.
  Actual-wrapper tests must preserve arbitrary inert bytes, stdout/stderr and exit status.
- Equivalent dynamic Elixir construction also exists in `bin/tickets_from_review.sh`
  and `bin/test_daemon_recovery.sh`; those overlap FR-03/04/05 and remain routed
  residuals rather than silently expanding FR-02. General release RPC authority remains
  FR-15a.

### FR-03

- `/root/fr03_investigate` confirmed FR-03 is ready but overlaps FR-01's Coordinator and
  Tick candidate, so implementation waits for FR-01 integration. FR-06 is complete;
  FR-03 completion will unblock FR-07.
- The trace found Fence unused by production startup, startup converting every event-log
  error to an empty history, and **21** unchecked authoritative checkpoint appends across
  Coordinator/Tick. FR-03 must use one startup owner/fence, effect-free direct/offline
  modes, visible recovery-required state, and persist-before-apply/ack/effect behavior.
- Acceptance requires two real isolated BEAM processes contending on one temporary root;
  held-lock and stale-text variants; malformed/oversized/version/I/O histories preserved
  byte-for-byte; and append-failure probes with no acknowledgment or downstream fake
  effect. This is legacy containment only—FR-07/08 retain storage/reducer ownership.

### FR-04

- `/root/fr04_investigate` found Coordinator cleanup enumerating panes and closing every
  untracked pane under `/private/tmp`, while persisted legacy records carry only pane/name
  and AgentServer cleanup bypasses its injected adapter to close by pane ID. This cannot
  establish ownership and can destroy foreign resources.
- FR-04 should follow FR-03 because it overlaps Coordinator/AgentServer and unresolved
  cleanup reporting needs FR-03's checked persistence boundary. The bounded containment
  disables CWD-based orphan scans, requires full expected identity (or the exact fresh
  split receipt before launch completion), and records unresolved cleanup without a
  guessed close. FR-10 retains durable effect ownership/restart reconciliation.
- Acceptance must prove exact identity closes, changed terminal/session/name and missing
  identity do not close, foreign panes in the same temp directory survive, replacement
  processes survive, and the destructive fixed-root recovery script is replaced by an
  isolated model-free fixture. No live pane/daemon/provider probe is authorized.

### FR-05

- `/root/fr05_investigate` traced synthesized CLI artifact identities, production
  `skip_git_checks`, nonexistent checkout success, `auto_approve` in admission/runtime/
  replay, memory-only integration, legacy success replay into `accepted_revision`, and
  mutable-source restart in `bin/pramana-live.sh`.
- Containment must reject auto-approve, stop synthesizing evidence, reject production
  bypass/missing Git facts, suspend integration before intent/effect, preserve legacy
  success only as an unverified historical claim, and make the source watcher refuse
  activation. FR-13/14/17 own restoration of artifact verification, Git integration and
  immutable activation; status revision labels remain non-authoritative presentation.
- FR-05 overlaps dirty CLI/Coordinator files and waits for FR-01 integration. Isolated
  real-Git tests must prove stale/wrong/missing evidence and integration attempts change
  neither event/state/ref; a process fixture must prove the disabled watcher invokes no
  child command. No live daemon/provider/Git worktree mutation was performed.

### FR-01 candidate v4 — frozen validation correction

- Only the two files authorized for the v3 residual changed: LaunchEligibility SHA-256
  `f8cfdf6e15a106344d8c28f58648b91fe8a6ad4906f6684d5d70dc78d03e5c2a`
  and autonomous-launch test SHA-256
  `438e40876401d89c1d4ca28f139beb7c5f30abaa354880f5c18cd243920c4673`.
  The implementer's full twelve-file candidate diff digest is
  `4354806d15a8cf5dc6a0158fd15c0a533cc27988ca264478df9adbd4be1fa090`.
- The correction validates proper lists before enumeration and uses exact whole-string,
  valid-UTF-8, unchanged-trim identity checks. Boundary tests cover improper/nested
  lists, terminal-newline and invalid-UTF-8 selectors, arbitrary containers/options,
  stable denial, and zero fake calls through resolve, Tick, AgentServer, initial review,
  and retry review.
- Implementer evidence: focused `25 passed`, the reviewer's supporting set `44 passed`,
  warnings-as-errors compilation, focused formatting, and runtime diff checks all exited
  zero. Production automatic launches remain disabled pending FR-09/15a.
- Candidate v4 is frozen for renewed Astra-high review. The documentation-only baseline
  commit advanced HEAD from the v3 review to `5179f34`; it did not change any of the
  twelve candidate source/test files.

### FR-01 independent review v4

- Reviewer: `/root/fr01_review` (Astra-high); review SHA-256
  `4aa1ee7ab844c58bcca05c22ac0394be716af8be182183a7c53eedfdad688e91`.
  Verdict: **FAIL**; all twelve frozen hashes matched.
- The original improper-list/newline residuals are resolved, and an adversarial 460-call
  arbitrary-term matrix produced no raises. One strict-shape blocker remains:
  `only_known_fields/2` uses `nil` as both the `Enum.find/2` no-match sentinel and a
  possible unknown map key. An otherwise valid profile containing `nil => :invalid`
  therefore launches at every fake-backed application boundary and can mask a second
  unknown field.
- B1/B3 remain resolved and the production System runner remains unsupported. Independent
  focused `25 passed`, supporting `44 passed`, warnings-as-errors compilation and runtime
  diff checks passed. The residual is a malformed-policy rejection failure, not a real
  provider-spending path.
- Next: replace sentinel-based field discovery with an unambiguous total fold, sweep every
  analogous find/sentinel use in LaunchEligibility, add masking/boundary regressions, and
  obtain renewed independent review. This is the final focused parser-design correction;
  architecture and lifecycle changes remain out of scope.

### FR-01 candidate v5 — frozen sentinel correction

- Only the two authorized files changed from v4: LaunchEligibility SHA-256
  `ca331865be61be90e80d775631fff3e2fb3a94cccd12e30db6359bd221a8c70f`
  and autonomous-launch test SHA-256
  `8bc2350cd1e09c61a8c71e534786d49ee68c3447e24cd6c8ad94247bfca63391`.
  The implementer's twelve-file candidate diff digest is
  `ae9467860ab353b1c5a9d817af7246286117ef1efd08ad4654c98961b9cf713d`;
  coordinator verification reproduced both changed-file hashes.
- Unknown-field validation now uses an all-fields predicate and stable generic error, so
  no key value can collide with a search sentinel. Nil-alone, nil-plus-credential,
  tuple, struct and improper-list keys are covered through resolve and every launch
  boundary with zero fake calls.
- Rule-41 sweep: remaining finds over role mappings/cooldowns return `{key, value}`
  tuples, the required-field find searches a fixed non-nil string list, and profile
  reduction uses tagged `:ok` versus error tuples.
- Implementer evidence: focused `26 passed`, supporting `44 passed`, warnings-as-errors
  compilation, two-file formatting and runtime diff checks all exited zero. Candidate v5
  is frozen for renewed Astra-high review.

### FR-01 independent review v5 and coordinator acceptance

- Reviewer: `/root/fr01_review` (Astra-high); review SHA-256
  `88e23eeaf3d852df469fac85d7c97156cc4e32923e9ff1b832971df5583e4bf2`.
  Verdict: **PASS for static containment**; all twelve hashes matched. B1/B2/B3 are
  resolved and real automatic execution remains disabled pending FR-09/15a.
- Independent evidence: focused `26 passed`, supporting `44 passed`, 184 actual-boundary
  malformed-key checks, 138 resolver role checks and the prior 460-term-position matrix;
  all denials had stable reasons and zero fake-adapter calls. Compile and diff checks
  passed. The reviewer found no ambiguous sentinel in the new policy parser.
- Coordinator full run 1 used an isolated application but the default `/tmp`; result
  `316/323`, 2 exclusions, 7 failures. Six relocation fixtures collided with stale
  `crash-test-*` directories after VM unique-counter reuse, and the known Python token
  benchmark exceeded its 60-second timeout. This nonzero run is retained as harness
  evidence, not classified as FR-01 acceptance.
- Coordinator full run 2 changed the setup, not the candidate: fresh isolated `TMPDIR`,
  isolated runtime root, nonexistent Herdr command, tick disabled, integration tag
  excluded, seed `424201`, timeout 120 seconds. Result: **323 passed, 2 excluded**, exit 0
  in 79.8 seconds. No provider, live daemon, credentials or activation was used.
- FR-01 is complete only for static containment. Real subscription conformance and
  protected re-enablement remain FR-09/15a; durable quota/switching remains FR-16; FR-22
  retains lifecycle acceptance.
- The reviewer removed one extra EOF blank line after the verdict; no review content
  changed. The hash above is the normalized artifact hash and staged diff checks pass.

### FR-01 integration

- Integrated commit `55c6bf5f54649cad0294d8cff9c15f91ed2790c0`, tree
  `3ac924a02c7a2a370ec9efc2e6e3bdbeef482ace`. Precise staging excluded the pre-existing
  Coordinator `unblock_ticket` wrapper/handler and the matching dirty CLI changes.
- Detached clean-checkout verification fetched the pinned dependency set, compiled with
  warnings as errors, and passed focused `26` plus supporting `44` tests. This verifies
  the actual committed tree rather than the dirty working tree.
- Astra-high post-integration [attestation](fr-01/integration-attestation.md), SHA-256
  `b5349db7156f7c365153c3ab5e660939cc0f91faf333954cefd9a40f48df1753`,
  returned **PASS**. Eleven source/test files match v5 byte-for-byte; committed Coordinator
  differs only by omission of the unrelated unblock code, and that omission does not
  affect the FR-01 conclusions.
- Implemented, reviewed and integrated; **not deployed**. The running daemon was not
  stopped, replaced, reconfigured or inspected. FR-01's owning acceptance protocol is
  the only authority that may later restore its containment, through FR-09/15a evidence.
