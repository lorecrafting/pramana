# Foundry repair implementation log

This supplements [REPAIR-PLAN.md](REPAIR-PLAN.md), which remains the authoritative
ticket, status, and dependency backlog. It records candidate provenance, independent
review, integration decisions, executable evidence, limitations, and resumable next
steps.

## Implementation-language constraint

- Operator direction, 2026-09-12: because this backlog repairs the Elixir supervisor,
  implement Foundry transport, persistence, orchestration, validation and test fixtures
  in Elixir wherever technically possible. Do not introduce Python or another language
  for an internal repair convenience.
- External processes are permitted only where the contract itself crosses that boundary
  (for example Git, OS-process acceptance, or the existing Herdr provider CLI), and each
  use must be explicit, bounded and justified in ticket evidence. FR-02's initial
  in-progress Python encoder was rejected before candidate freeze/review and is being
  replaced with an Elixir `System.argv/0` encoder; it is not accepted implementation.

## Review-model policy

- Operator cost/effort adjustment, 2026-09-12: Sol-medium remains the implementation
  default; use Sol-high for routine independent review, Astra-medium for the first review
  of authority/persistence/recovery/budget/Git/activation changes, and Astra-high only for
  FR-22, a cross-cutting contract contradiction, or materially different repeated
  failures. A narrow isolated recheck may use Sol-medium.
- This changes review compute, not independence or acceptance rigor. The already completed
  FR-01/FR-02 Astra-high evidence remains valid and is not rerun merely to relabel effort.

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

### FR-02 candidate v1 — frozen

- Implementer: `/root/fr02_investigate` (Sol-medium), base HEAD
  `7aecf31c541ab1b1f3de4045ac3c487f6ef0708f`. Ownership remained disjoint from
  dirty CLI/Coordinator files.
- Exact hashes: `bin/pramana`
  `e836621bc5d92c152f7eed2f3c00a4fb93d30b55460955abdc953704a3383e54`;
  `lib/pramana_foundry/cli/rpc.ex`
  `eec9bec3224207dec43df31fcc0620aae2f071572305c6b37f119bf9d7df4c59`;
  `test/pramana_foundry/cli/rpc_test.exs`
  `7bb444196993fa00af64393045b9f22ca3873f17815706c6a9566ba3f94520e5`;
  `test/pramana_foundry/rpc_wrapper_test.exs`
  `5b596d76f71764df51526d7418ca1de8c9c173c9e409987f5e81b3afe40ee26f`.
- The wrapper now uses Elixir `System.argv/0` to encode a versioned JSON envelope and
  canonical URL-safe base64 token; user text never enters source. The daemon-side Elixir
  module enforces size, canonical encoding, UTF-8/NUL, exact envelope and a closed command
  grammar before dispatch. No Python remains in the candidate.
- Evidence: warnings-as-errors compile of 72 files; focused RPC/wrapper plus existing CLI
  suite `59 passed`; owned formatting, shell syntax and whitespace checks passed. Actual
  wrapper fixtures cover literal metacharacters/Unicode/empty values, 60-KiB and over-limit
  payloads, malformed shapes, byte-exact streams, status 42, invalid release 69, missing
  Elixir 127 and unexecutable Elixir 126.
- No live daemon/provider was used. General release `rpc` remains FR-15a; equivalent
  interpolation in `tickets_from_review.sh` and `test_daemon_recovery.sh` remains routed
  to FR-03/04/05. Candidate is frozen for Astra-high authority-boundary review.

### FR-02 independent review v1

- Reviewer: `/root/fr02_review` (Astra-high); review SHA-256
  `911baf8618cc3853268e383b302bb9dc009e2a33460e0e89e0e126af7ba15340`.
  Verdict: **FAIL** on two bounded grammar issues; all four hashes matched.
- The original source-injection defect is corrected. Independent evidence passed 59
  focused tests, a forced warnings-as-errors compile, formatting/shell syntax and six
  actual-wrapper/evaluated-dispatch probes.
- R1: OTP JSON map decoding accepts duplicate envelope members, so ambiguous duplicate
  `version` or `argv` keys can pass exact-shape validation. R2: the allowlist includes
  `ticket unblock`, which exists only in preserved dirty user work and not candidate base
  `7aecf31`; the candidate may not depend on it.
- Next: detect/reject duplicate JSON object keys using the OTP/Elixir decoder callback
  interface (not a non-Elixir parser), remove `unblock` from the grammar/tests, rerun the
  boundary matrix, and obtain renewed independent review.

### FR-02 candidate v2 — frozen correction

- Exact hashes: `bin/pramana`
  `c1c92fe1c25402d67e0ce6173e196e640e71b47c528878bb164f0318c83e5250`;
  RPC module `617fb1dc018a70abb9ffd7f97bc7e886db6d217c16ae06ea15ef233d5829b11d`;
  RPC test `083f11bf59e6f3954e168d8f939c0fe9aa8fbb165e59daf66894d7b95d366617`;
  wrapper test `77ccefd68a73ac180723591fbaf3c0075e7c9f8bcb5716061c05c8259ee6e761`.
- OTP `:json.decode/3` object callbacks now retain a per-object map/key set and throw one
  private exact tag on duplicates before map collapse. Tests cover both key orders,
  escaped-equivalent spellings and nested object/array cases; an evaluated forged-wrapper
  probe returns status 65 with no dispatch artifact. `ticket unblock` is now a negative
  shape and no candidate claim depends on dirty state.
- Evidence: forced warnings-as-errors compile of 72 files, focused/supporting `62 passed`,
  owned formatting, shell syntax and whitespace checks exited zero. No Python, live daemon,
  provider or new dependency. Frozen for narrow independent recheck.

### FR-02 independent review v2

- Reviewer: `/root/fr02_v2_review` (Sol-medium narrow recheck); review SHA-256
  `a1b80f698a224dd6a506a237bcf31de593a26e6d9498e4fe340ed541d3fbef4d`.
  Verdict: **PASS**; all four frozen hashes matched.
- The reviewer independently confirmed duplicate keys reject before dispatch across
  nested/escaped variants and `ticket unblock` is rejected both by the transport grammar
  and clean-base CLI. Focused `62 passed`; forced warnings-as-errors compile of 72 files,
  shell syntax, formatting, diff/whitespace and adversarial probes passed.
- FR-02 is ready to integrate as Elixir-only inert transport. General release RPC
  authority remains FR-15a and the two other dynamic-source scripts remain explicitly
  routed to FR-03/04/05; neither limitation is represented as closed.

### FR-02 integration

- Integrated commit `21ad6b99a262f143626746f271f1fc4c2256e319`, tree
  `c652a6b87905a7eb0f2c6447dcf3fae9031d1332`. All four runtime/test hashes match
  reviewed v2; dirty CLI/Coordinator blobs equal the parent and were excluded.
- Detached clean-checkout verification fetched pinned Foundry dependencies, force-compiled
  72 files with warnings as errors and passed the focused/supporting `62` tests at seed
  `424202`. A root-level `mix deps.get` was invoked once from the wrong working directory
  before this command; it reported unchanged umbrella dependencies/security notices and
  produced no tracked diff. It is not FR-02 evidence.
- Sol-medium post-integration [attestation](fr-02/integration-attestation.md), SHA-256
  `9f2f58500eb16315b3e05b0af92ae914f5c8d0f4722b3fa9f0811093317a3398`,
  returned **PASS**. Implemented/reviewed/integrated, not deployed; the running release
  was not rebuilt or changed by FR-02 integration.

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

#### FR-03 test-isolation incident

- During implementation in isolated Git worktree `/tmp/pramana-fr03.YeVMZP/tree`, Mix
  started the OTP application before ExUnit and the committed absolute
  `config :pramana_foundry, runtime_root: .../foundry/local/` bypassed filesystem/worktree
  isolation. Coordinator test resets preserve configured log paths. Five focused commands
  therefore read and may have appended the live `state/current/events.jsonl`; coordinator
  and telemetry JSONL may also have been written.
- Observed startup event counts were 1416, 1443, 1444, 1448 and 1452. These are not
  attributable deltas: the installed daemon was concurrently running, so test versus
  daemon writes remain **unknown**. A coordinator read-only check later observed 1482
  lines, 383856 bytes, SHA-256
  `b7a06bdf5af57350e2d999d9255761c188977bc15df474bb79e548ce9fa376a1`,
  modified 2026-09-12 21:54:34 local; this is a post-incident observation, not a baseline.
- The worker stopped immediately on discovery. Read-only process inspection found no
  FR-03 test process remaining and confirmed the pre-existing release daemon PID 32588
  had been running since 15:57. No daemon stop/reconfiguration, lock change, deletion,
  rollback, credential/provider operation or attempt to rewrite live logs occurred.
- Exact affected commands and limitations are retained in the worker incident report in
  the coordination transcript. FR-03 stays frozen. Before any further test, the Mix-test
  application boot itself must resolve a newly created per-process temporary runtime root,
  and a separate read-only review must prove the absolute configured root is unreachable.
- Operator authorized direct development-state remediation. The daemon was stopped
  cleanly; byte-for-byte backups were created as
  `events.jsonl.pre-fr03-incident-repair-20260912` (SHA-256
  `4f1eecd843c1354a118145dde0af5340f731a05f068c76f43204b7452e50978f`)
  and `coordinator.jsonl.pre-fr03-incident-repair-20260912` (SHA-256
  `7d1d492f3fd7d5d7787ab3616ca158f7cb8b59a09367f2ce246741ce676dc5ad`).
  Two exact timestamp windows plus the fixed test task IDs identified 44 event records;
  the same windows identified four off-cadence test `tick_start` coordinator records.
  Daemon-cadence ticks and three Improver findings were preserved.
- The repaired logs validate line-by-line as JSON and contain zero matching incident
  records: events 1454 lines, SHA-256
  `14bcd1d45e4ecbf62a02ecc9d5c1086747f0cbd4c9ba27b54341c4ad2ff60817`;
  coordinator 1406 lines, SHA-256
  `fed299bb77ea18b195291f3a8f35702e9d8bbb5970220ac07c5b7d36e37d2767`.
  The development daemon restarted successfully as PID 50423. The backups make the
  cleanup recoverable; no credential, provider or unrelated log was changed.

#### FR-03 isolation preflight v1

- `/root/fr03_isolation_preflight` (Astra-medium) performed static inspection only and
  returned **FAIL**. The candidate selected a local temporary root but did not publish it
  to application configuration, so Improver/ConsolidatedLog and direct Coordinator init
  could still resolve the committed live root. PID-only temp names could collide;
  subprocesses inherited test mode/provider/tick environment; generated escript output
  was also present in the worktree diff.
- No test may resume until one validated exclusively-created root is installed before all
  child specs, every consumer uses it, subprocesses explicitly clear provider/tick state
  and exercise intended ownership mode, and a renewed static preflight passes. The
  generated binary is excluded from the candidate.

#### FR-03 isolation preflight v2

- Static-only renewed review confirmed child/root routing, 128-bit exclusive defaults and
  subprocess mode/environment controls were corrected, but still returned **FAIL**.
- Remaining blockers: publishing overwrote the configured operator-root rejection anchor;
  lexical `Path.expand/1` did not prevent an ancestor-symlink alias into operator state;
  `fetch!/0` had no resolved marker for direct/no-start consumers; and the generated
  escript still appeared in the unstaged worktree diff.
- Runtime remains paused. V3 must preserve an immutable operator anchor, canonicalize
  existing ancestors using Elixir filesystem primitives with bounded cycle handling,
  reject fetch-before-publication, and remove only the agent-generated binary diff before
  another static preflight.

#### FR-03 isolation preflight v3 and final hardening

- `/root/fr03_isolation_preflight` (Astra-medium) returned **PASS** for the exact
  fresh-parent execution protocol. Static inspection confirmed immutable operator and
  active roots, publication before child startup, exclusive cryptographically random
  test roots, bounded symlink-ancestor resolution, and explicit subprocess mode and
  environment isolation. The generated escript is absent from the candidate.
- A final narrow hardening invalidates `:runtime_root_resolved` as the first executable
  statement in `resolve_and_publish!/2`, before operator validation, initialization or
  mismatch checks. Exact frozen hashes are RuntimeRoot
  `ff8a863a82e835dca42240e66809ba3693dac26cde084d1e2e7bea1944aeea2b`
  and its test
  `e1a0846abcee49bcd7ebfa39178626f135eee848c239b8dcf75923d6095ce8f2`.
- The same reviewer performed a hash-only final static recheck and returned **PASS**:
  validation and mismatch failures leave `fetch!/0` rejected, including mismatch after
  a successful prior publication. No Mix task, application, test or live-state access
  occurred during either review.
- Limitations: this is static isolation evidence only. An unsupported `mix_env` fails
  the function guard before body-level invalidation; normal application callers use the
  supported environments. A private newly created parent mitigates, but cannot eliminate,
  filesystem symlink time-of-check/time-of-use races. Runtime validation resumes with one
  focused test under the exact fresh-parent protocol before broader checks.
- The first runtime command exited 1 before application startup because the ambient shell
  exposed Elixir 1.19.5 rather than the pinned 1.20.3. A retry through `mise exec` also
  exited 1 before Mix because mise does not trust the temporary worktree's config through
  the macOS `/tmp` alias. Neither run exercised candidate code. Subsequent commands used
  explicit already-installed Elixir 1.20.3/OTP 29 binary paths without changing trust.
- The first executable isolated check passed `8/8` RuntimeRoot tests, seed `424203`, exit
  zero. After formatting the 13 owned files, warnings-as-errors compilation passed and
  the three focused RuntimeRoot/startup/persistence files passed `15/15`, exit zero.
- Full model-free validation used a new private parent, separate `TMPDIR`, nonexistent
  Herdr command, tick/provider environment removed, integration excluded, seed `424203`
  and 120-second per-test timeout. Result: **338 passed, 2 excluded**, exit zero in 56.8
  seconds. Application startup reported zero recovered events. The development daemon
  remained alive as PID 50423, and the live state tree contained no fresh-root/test marker.
- The pinned formatter mechanically reformatted whole touched legacy files, expanding the
  tracked diff to 1376 additions/738 deletions even though only the same eight source files
  are owned. This is explicit candidate provenance; independent review must use both exact
  hashes and whitespace-insensitive views and decide whether the churn itself blocks
  integration. Candidate remains frozen during Astra-medium durable/startup review.

#### FR-03 independent review v1

- Independent reviewer `/root/fr03_review`; artifact
  `docs/fr-03/review.md`, SHA-256
  `8488281e04f347590b94d482bbc9929536e5d0255b5b3dec2e92f44ae5f293f0`.
  Verdict: **FAIL**. All 13 post-format candidate hashes matched; mechanical formatting
  churn was not itself classified as an integration blocker.
- B1: a complete final JSON object without its newline loaded as healthy; public enqueue
  acknowledged and concatenated the next object, making restart history malformed. The
  missing-delimiter tail must be rejected and preserved before writes are enabled.
- B2: stopping RuntimeOwner released the OS fence before the later `:rest_for_one` child
  quiesced. A successor acquired ownership while the old child still wrote. Abrupt bridge
  and owner loss need fail-closed takeover evidence; full durable epochs remain FR-10/15a.
- B3: `Transition.rebuild/2` discarded an unprojectable `prompt_intent`, so invalid
  authoritative replay became healthy empty running state. Startup must use the one replay
  implementation strictly and enter recovery rather than forgetting authority.
- B4: raw state denied mutations in recovery, but public health/status omitted the recovery
  status and reason. Existing operational inspection must expose both.
- Independent isolated evidence: supplied focused tests `15 passed`; a model-free Elixir
  adversarial probe reproduced all four blockers; actual default Mix client inference and
  explicit client child-free startup passed. The graceful stop test is not killed-owner
  evidence. Later-write failure branches and useful-prefix recovery still need executable
  coverage. The avoidable Python bogus-lock helper must become an Elixir fixture.
- The same implementation owner is correcting only these findings. FR-03 remains active,
  FR-07 remains blocked, and the changed candidate requires a fresh exact-hash review.

#### FR-03 corrected candidate, review v2 and integration

- Implementation candidate commit `69ede99128b14134cec9bddd728883e56f8cf62c`, tree
  `8f98de6715a5aa3f4d875a2b6f815bd6a8134c91`, contains exactly 21 reviewed
  implementation/test paths plus the original review, response and renewed review.
- The response artifact SHA-256 is
  `9b41e8c41505e5f6200a96c1fe004137d9b2ffe6cabcd54bd4b3a2b7a5a227e4`.
  It maps B1–B4, expands exact ownership to the correct Import/EventLog/Transition/status
  boundaries, records multi-write suspensions and preserves downstream ticket routing.
- `/root/fr03_v2_review` (fresh Astra-medium reviewer) returned **PASS for immediate
  FR-03 containment**. Review SHA-256:
  `2dc7c2ca8cd422fcc33368ec3d16983262f0cd747c54369be2f66550293e4b0e`.
  All 21 implementation/test hashes matched. Independent adversarial evidence includes
  same-OS owner kill refusing successor, a slow old child keeping the fence through clean
  shutdown, actual two-BEAM contention, SIGKILL/bridge-loss conservative recovery,
  delimiter preservation, strict replay and public recovery inspection.
- The candidate handles at most one queue item per tick and converts its old post-effect
  authoritative summary to diagnostics. Automatic legacy startup reconciliation and
  legacy Git integration are suspended before mutation/effect until FR-07/08 and FR-05
  supply their transactional owners. No F01–F24 obligation is removed by the suspension.
- Implementer evidence: clean 73-file warnings-as-errors compilation; focused `56 passed`;
  strict-replay `32 passed`; Board/Coordinator/FR-01 compatibility `39 passed`. Its serial
  full run was `346/350`; independent matched candidate/base diagnosis proved the four
  Board failures identical at PTY width 80. Independent non-TTY full runs were candidate
  `349/350` and base `324/325`; both failed only the same token benchmark because the
  deliberately minimal Python PATH lacked `tiktoken`. Full-suite green is not claimed.
- The implementation uses Elixir for the new runtime/test logic. The pre-existing Python
  Fence bridge remains the necessary external POSIX `flock` boundary; the duplicate new
  Python test helper and hard-coded Mix executable were removed.
- Candidate was applied to main with precise source control handling. The unrelated dirty
  CLI/Coordinator `unblock_ticket` work was excluded from the reviewed commit, preserved
  separately during integration and restored afterward. FR-03 is implemented and
  reviewed, **not deployed**. A clean integrated-tree attestation remains next.

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
