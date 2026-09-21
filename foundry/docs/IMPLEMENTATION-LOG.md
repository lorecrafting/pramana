# Foundry repair implementation log

This supplements [REPAIR-PLAN.md](REPAIR-PLAN.md), which remains the authoritative
ticket, status, and dependency backlog. It records candidate provenance, independent
review, integration decisions, executable evidence, limitations, and resumable next
steps.

## Read this log efficiently

This is append-only historical evidence, not required linear reading. On resume:

1. Inspect Git/worktree state and the repair plan's dependency table/current ticket.
2. List this file's headings (for example `rg -n '^## |^### '`) and read only the newest
   coordination/integration entries plus the active ticket's named sections.
3. Follow exact candidate/review links when validating provenance; read older ticket
   history only when a current finding crosses that interface.

## Which branches are live

A branch is live if it is **not** reachable from an `archive/` tag. Consolidating on
2026-09-20 tagged every branch tip as `archive/<date>/<branch>` before deleting any
branch, so an archived line of work is recoverable with
`git branch <name> archive/<date>/<name>` and is not lost by being absent from
`git branch`.

```sh
git for-each-ref --format='%(refname:short)' refs/heads/   # live
git for-each-ref --format='%(refname:short)' 'refs/tags/archive/**'  # archived
```

This convention is deliberately mechanical rather than a maintained list of current
branches. Such a list is accurate for about an hour in an active repair and then
misleads, which is the failure this repository already avoids by generating evidence and
pinning it by hash rather than describing it in prose. Each entry below names the branch
its work lived on at the time it mattered; that, plus the tag convention, is the durable
form of the same information.

A complete offline copy of every ref as of that consolidation exists outside the
repository as a Git bundle; `git bundle verify` reports it records a complete history. It
is a backstop, not a substitute for the tags.

Do not preload this whole log, all of `docs/PLAN.md`, the full audit or the full workflow
contract for a bounded ticket. Read the Foundry portion of `docs/PLAN.md`, the relevant
contract anchors and the exact evidence packet. Targeted patches can append or update an
entry without loading the rest of this file into model context. `REPAIR-PLAN.md`, not the
latest prose here, remains authoritative for status and dependencies.

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

- Current coordinator disposition, 2026-09-19: Sol-medium remains the implementation
  default and Sol-high handles routine independent review. Use Astra-high for the first
  critical review of authority, persistence/schema, replay/recovery, budgets, isolation/
  credential routing, Git custody/CAS and activation/rollback. Use Astra-medium for a
  narrow critical re-review that reruns the exact reproduced defect and relevant positive/
  regression controls. Re-escalate to Astra-high when another invariant family changes or
  repeated failures expose an abstraction problem. FR-22 receives Astra-high whole-
  lifecycle review; xhigh is only an explicit choice for a concrete cross-cutting audit.
- This changes current review compute, not independence or acceptance rigor. Every earlier
  model/effort label below remains the historical identity actually used and is not rerun
  or relabelled merely to match current policy.

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
  reviewed, **not deployed**.
- Integrated commit `5c69e6c` received an independent Astra-medium post-integration
  [attestation](fr-03/integration-attestation.md), SHA-256
  `c48e89224c93a64fd1e612005b8c6beefbfa2019a2d6c9ee8955a0c3c00db258`:
  **PASS**. All 24 reviewed candidate paths match the commit and detached checkout; only
  the three required completion documents were added during integration. The attestor
  independently reran 23 replay/persistence tests, all passing. The uncommitted unblock
  additions are absent from the integrated tree. FR-03 completion evidence is final and
  FR-07 is ready; deployment and FR-22 lifecycle acceptance remain open.

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
- `/root/fr04_impl` produced frozen candidate v1 on isolated branch `repair/fr04`, base
  `5c69e6c`; candidate artifact SHA-256
  `cfe3b2a6ff3becec6bcb86a2b5eb8dd1402ff7294a8dbdf5ff8cb341da47cebe`.
  It removed CWD/hard-coded orphan scans and default-adapter closes, retained FR-03
  suspensions, routed cleanup data toward checked persistence, and replaced the destructive
  daemon-recovery fixture. Implementer compile/focused/compatibility evidence passed.
- Independent Astra-medium reviewer `/root/fr04_review` returned **FAIL**; review SHA-256
  `369db5d8c513034d4a2aba9eb616177ef03b281f2eb14df81877fb1605d0e124`.
  All eleven hashes matched and 29 focused tests passed, but adversarial probes reproduced
  four authority/lifecycle blockers: any nonempty/PID-only/null/CWD process map could
  authorize close; a post-start-error snapshot could adopt and close a replacement;
  submit-review and shutdown cleanup could stop without a checked durable receipt; and
  unresolved cleanup was removed from active state and treated as completed/released.
- V2 correction is assigned to the same implementer. It must require stable incarnation
  evidence and exact native session identity, bind fresh cleanup to a pre-start snapshot,
  durably retain every cleanup obligation/result, and keep unresolved resources visible
  and capacity-blocking without absorbing FR-10's full reconciliation redesign.
- Candidate v2 draft response SHA-256
  `f00880a5c1a9ed312428d33e2f05676d0e105513b022e7fe85f4b996d2910640`
  added strict shell-generation/session identity, pre-start capture, checked pending/result
  cleanup events and replayed blocking state; its expanded isolated suite passed 83 tests.
- Renewed Astra-medium review still returned **FAIL**; review-v2 SHA-256
  `3e145afbec9f725222ef8913ef565f7ad49d5f6f268fd4b2301b7b1c8a6247c2`.
  Exact hashes matched, but independent probes found three residuals: foreground process
  identity/generation was discarded so a replacement under the same shell could close;
  production shutdown deadlocked through RuntimeOwner → subtree → Coordinator →
  RuntimeOwner ownership verification, wrote no cleanup event, then removed the unclean
  marker; and cleanup replay restored a stale pre-cleanup status over a newer approved
  verdict while actual admission did not reserve capacity for unresolved cleanup.
- V3 correction must retain foreground incarnation evidence, keep the fence query responsive
  while effect children drain (without early release), preserve the latest independent work
  verdict, remove blocked work from the ordinary queue and conservatively block admission
  while cleanup is outstanding. FR-04 remains active and unintegrated.
- The next freeze announcement was invalid: the implementer corrected two additional
  AgentServer exits after drafting the response and reported its stale digest. Review
  stopped before executable attestation. The refreshed response SHA-256 was
  `1d5f4e0b01a4579c6095fa7f5919aa7bfcd4b9e8a24aff5d7279ea8a55badcf1`,
  and all 20 refreshed manifest entries then matched independently. This provenance error
  is retained; no review is claimed for the stale identity.
- Independent review v3 still returned **FAIL**; artifact SHA-256
  `131b848c17fb95308b501f12b9752e97592abd32cbdaa891d2c54ad37fcc8fa2`.
  Foreground-incarnation checks and the former synchronous owner deadlock were corrected,
  and 96 focused tests passed. Two bounded residuals were reproduced with actual isolated
  runtime components: a shutdown deadline on a `handoff_received` AgentServer could yield
  no cleanup event, remove the unclean marker and admit a successor because clean-state
  validation was status-specific; and Coordinator lacked a clause for Tick's deliberate
  cleanup admission suspension, producing a function-clause error on every blocked tick.
- The same implementer is making only those status-independent marker and Tick-result
  corrections, after which a new exact manifest and renewed review are required.
- Response v3 SHA-256
  `5ecccd64bc98f7421364665a2b35fed9d5d57d7fd93f4e6124604a0bf1ea09a9`
  made terminal-resource checks status-independent and handled suspended ticks. Independent
  review v4 SHA-256
  `9bcc9d294c27bd2ad42462442e460081b8d3ba03222d970bd2dddb38ab81db29`
  verified those fixes and 99 focused tests, but returned **FAIL** on one remaining
  multi-role ownership gap: reviewer launch overwrote the assignment-level developer pane;
  reviewer closure could then hide a developer cleanup deadline and allow clean-marker
  removal.
- The bounded next correction must retain separate legacy cleanup entries per role/run/resource,
  require every owned entry terminal before clean release, and prove sibling/stale receipts
  cannot settle another entry. Full effect-ledger reconciliation remains FR-10.
- Reviews v5–v8 each retained a concrete newly reproduced residual rather than accepting
  test totals: mismatched pending could overwrite a sibling; a successful split followed
  by start timeout lacked pre-start registration; malformed first process identity lost
  the split obligation; and a closed reviewer could clear the global flag while an
  unverified developer resource remained. Their artifact SHA-256 values are respectively
  `35e66ef185e9943768d11268de73fab5a709a219110cf18754133c50674be4de`,
  `3f6a61921cff8a301540a8790acba34329207520ce581f8a85a9c2be0bd90f76`,
  `a1cc23f5f1ffcdc94edaa1a322bbf8b79daba1faa1647d35fd25d294fbd73559`
  and `559728790b3f1819e89360f8b2d145eaeca136911448cf8a27119dd17239b1bf`.
- Final response v8 SHA-256
  `ff22d148d3e67d4e2dacf6af17092f0a18659604ed19bb938690457e96a60c20`
  centralizes outstanding-resource calculation across registration, pending/result,
  replay, Coordinator and Tick. Final independent review v9 SHA-256
  `27bd38279004dac58896358ce74f0ff5677d91ba287fb36ea114cb9a411f19c0`
  returned **PASS**: all 22 implementation/test hashes matched and 43 focused adversarial
  cases passed, including both multi-role ordering permutations and stale/sibling refusal.
- The reviewed candidate commit is `cd77de43475b1fbb4ef600384817b3f2434c6b4d`, tree
  `0f6e75a1a5abf258d25b0f9d45749c29e7231b30`, containing the 22 paths and full
  review provenance. Implementer final evidence included 115 focused tests, a forced
  warnings-as-errors 76-file compile and the isolated recovery wrapper.
- Applied to main with the unrelated dirty CLI/Coordinator unblock additions excluded from
  the commit and restored afterward. FR-04 is implemented and independently reviewed,
  **not deployed**. FR-10 retains durable reconciliation, FR-09/15a backend conformance,
  and FR-22 full lifecycle acceptance.
- Integrated main commit `7d8874a` received independent Astra-medium
  [attestation](fr-04/integration-attestation.md), SHA-256
  `63adbbc1d20a2d6e711151eebc1ca2ebd33c3354c21c2b27665e6d36f53fe97c`:
  **PASS**. All 22 reviewed implementation/test paths and 18 provenance documents are
  byte-identical between the candidate commit, integrated commit and detached checkout;
  only the three completion documents were added for integration. Fourteen transition
  tests independently passed, and the dirty unblock additions are absent from the commit.

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
- `/root/fr05_impl` produced candidate v1 on isolated branch `repair/fr05`, base
  `64c226c`; candidate artifact SHA-256
  `b20fcc14863864523f70ea67daf8ec5bb3881037b5239decc9524a97addc1d9c`.
  It centralizes real Git evidence, removes CLI evidence synthesis, rejects automatic
  approval and production Git bypasses, suspends promotion/integration/activation, labels
  historical success unverified, and disables the mutable watcher. Implementer evidence
  included focused 21/21 and full model-free 420/420 runs plus production compilation.
- Independent Astra-medium review SHA-256
  `8324ecbe8c194b056d6b5a8ae5b8e7fafdab77ccc88640d8a771def46b369991`
  returned **FAIL** despite 61 focused passes. Direct Pipeline `validate_readiness/3`
  still accepted invented revisions, empty review, auto-approval and nonexistent checkout;
  public `run_gate_checks/3` still invoked its runner. Direct CLI ticket creation also
  silently discarded `--auto_approve` and created an event, although the fixed wrapper
  rejected that shape. The same implementer is correcting only these direct boundaries;
  FR-05 remains active and unintegrated.
- Corrected candidate artifact SHA-256
  `45c2b19413cb4f4eb32469c35cf4a1c1bc0fd90e8e4f982cb58783c6a4386c5d`;
  response SHA-256
  `66a1a3bdcc95e3b262e1ef1d7e6f66a65e6e9dd2ac1dcddf4b40afb16db3fee9`.
  All six public Pipeline operations now suspend before effects, and direct ticket-create
  parsing rejects forbidden, unknown, duplicate, missing and normalized auto-approve
  options before Coordinator access.
- Renewed independent review v2 SHA-256
  `d6f3a0be3e09522e015c87c50c94dd8f45ae214f39a6cb71d83b74677c54fc5e`
  returned **PASS for FR-05 containment**. All 26 hashes matched; 83 focused tests,
  production no-start probes covering six Pipeline and fourteen CLI refusals, both Git
  bypass refusals, and isolated real-Git identity/ancestry/staleness probes passed.
- Reviewed candidate commit `5bc8c1ca81bfe65dff2b40a164ea8e12e2424f80`, tree
  `7e698647144b055a850142601b1cd46cf803af05`, contains exactly the 26 paths plus
  four provenance artifacts. Implementer evidence includes focused `63 passed`, full
  model-free `422 passed`, and forced 77-file warnings-as-errors compilation.
- Applied precisely to main; the unrelated dirty CLI/Coordinator unblock additions were
  excluded from the commit and restored afterward. FR-05 is implemented and reviewed,
  **not deployed**. FR-13/14/17 retain artifact, Git integration and immutable activation;
  FR-22 retains lifecycle acceptance.
- Integrated commit `7fa3519d633375eec66767be02d3b20de0bc0cdd`, tree
  `928a59e594c4cf6788b58a3ca393f636a75f8e52`, received independent Astra-medium
  [integration attestation](fr-05/integration-attestation.md), SHA-256
  `a6e5facd13a8a764aefff4e7a7c6302e644a96f2cf5fd3e9f4c539efa58eaafa`:
  **PASS**. All 26 frozen paths and four provenance artifacts match the candidate;
  only the three expected completion documents differ. The reviewer independently ran
  23 focused tests with fresh compilation. Coordinator clean-checkout validation ran the
  wider nine-file set: the first attempt exposed nested Elixir 1.19.5 selection
  (67/83), the pinned-PATH/external-build attempt exposed two tests' checkout-local
  `_build` assumption (81/83), and the corrected pinned-PATH/fresh checkout-local build
  passed **83/83**, seed 507. These superseded attempts did not expose product failures.

### FR-07

- **Active owner:** `/root/fr07_impl` (Sol-medium), isolated branch/worktree from main
  commit `debba64`. Prerequisite evidence is satisfied: FR-03 implementation/integration
  containment and FR-06's independently verified R4a design gate are complete.
- Scope is the FR-06 SQLite WAL/FULL durable-store and compatibility boundary: pinned
  in-process binding, protected single write gateway separated from an updatable pure
  kernel interface, versioned authoritative tables, checked atomic commits, recovery
  mode, and offline legacy import that retains originals and reports every invalid row.
  Required evidence includes idempotent before/after-commit lost-reply cases, constraint
  failures, injected write/capacity/torn/unknown-version failures, oversized import,
  transactional command/event/projection/intent consistency, and migration rerun safety.
- Permitted ownership: `foundry/mix.exs`, `foundry/mix.lock`, new store/kernel/import
  modules and tests, and the minimum application/Coordinator/EventLog/Checkpoint boundary
  changes required to install the compatibility writer. Documentation/candidate evidence
  belongs under `foundry/docs/fr-07/`. Existing dirty root CLI/Coordinator unblock work is
  outside the ticket and must not enter its candidate. Excludes FR-08's complete transition
  migration, FR-15a protected process isolation, FR-19 operating limits and any live
  deployment/provider activity.
- `/root/fr07_impl` froze candidate
  `d99799e46577d24ca178ac67dea12ce2b250ee87`, tree
  `2fc76e2316ddef5ab2c27b0879bbf0ee90d28757`; implementation commit
  `53738a005eefac1cd30376243767ccbcd9b472db`, tree
  `a6ddde723739ddb7aaf26391fc469d54fc803193`. Candidate artifact SHA-256
  `79a5ded644517b294a67e3e3e7a214b97f3ee518d448b8e39929e846e794b4e9`
  records 15 verified path hashes, 31 focused/compatibility passes and an 84-file
  warnings-as-errors compile. A fresh-root full run returned 439/440 due to one unrelated
  telemetry scheduler-timing assertion; its immediate isolated rerun passed. An earlier
  fresh-root run passed 440/440 before the final protected-read check, so it is retained
  only as superseded evidence. Dependency source directories remain untracked/excluded.
- The candidate pins Exqlite 0.40.0 and implements the store/gateway/kernel/import in
  Elixir over the required in-process SQLite NIF. It explicitly does not claim a
  controllable VFS fsync/power-loss test, host isolation, full mutation migration,
  operational retention or deployment. `/root/fr07_review_prep` (Astra-medium), which
  prepared its adversarial checklist without seeing the candidate, now owns independent
  review of this exact frozen revision.
- Independent review SHA-256
  `bba396dd837ad06018c460a4dd68223792d536542b7fbdb53cfaea2092597f30`
  returned **FAIL** with all 15 hashes matched and 31 focused tests passing. Executable
  probes nevertheless reproduced nine blockers: candidate-forged issued authority;
  unchecked expected revisions and rejected-event mutation; wrong protected retry lookup
  ordering; corrupt result bodies that do not fence later writes; import source/manifest
  alias overwrite and uncaptured-source race; multiple simultaneous store owners; omitted
  backup tables/reconstruction; incomplete real sync/multi-table crash evidence; and
  nonconforming control-character/domain-tag canonical bytes. The candidate remains
  unintegrated and frozen. `/root/fr07_impl` is addressing the exact findings; renewed
  independent review is required.
- Corrected candidate `b88918dd54094e657f8c6aae839878327c75e4d6`, tree
  `4f2e7b5c6d17cc80749fb6ad331ff0dffabe633c`, implementation commit
  `bda425ab6666f367ef6ef1966a6d688d2bd6127f`, is frozen for renewed review.
  Candidate-v2 SHA-256
  `5dc0c7bbe8bcf21943b03b27aec092116e602ea515c319a54d7b29b995d26b9a`;
  response SHA-256
  `d089de9abaca36e65674218844634944cf33a082734666a8a343ce06cbb65f39`;
  all 22 implementation-manifest hashes matched. Implementer evidence is 44 focused
  passes and a fresh full 452/453 run whose sole telemetry timing failure passed its
  isolated rerun. R1–R7/R9 have claimed behavioral corrections; R8 adds every-table
  failpoints, multi-table process exits, import interruption/rerun, migration rerun and a
  real RLIMIT_FSIZE SQLite COMMIT I/O error with prior-state preservation. A deterministic
  failed-fsync syscall remains explicitly unproved because Exqlite exposes no VFS fault
  hook. Fresh Astra-high review owns both the corrections and that narrow disposition.
- Renewed Astra-high review SHA-256
  `4dab766e7616e40630d2000499319f37ee8216851f5a73f25cf74f6a2c9e8ad4`
  returned **FAIL** after matching all 22 hashes, independently passing 44 focused tests
  and reproducing eight defects. R1, ordinary R3 ordering and R9 are corrected; full
  backup table coverage and real COMMIT I/O failure are also material improvements.
  Remaining blockers are idempotent-path corruption that does not fence; incompatible
  admission/start/read body validation; symlink store aliases bypassing gateway/import
  ownership; stale semantic rejection not retained as an idempotent durable result;
  unconserved caller-supplied child allocation; a purported reconstruction digest that
  does not reconstruct projection state; and the still-required attributed sync-failure
  case. Candidate `b88918d` remains unintegrated. The same implementation owner is making
  bounded corrections; renewed exact-candidate review remains mandatory.
- V3 candidate `f4a77de4ab3795716b00f807b4cd659e602654c4`, tree
  `8a38dcae936d536a71b55a1327836087fb51e4b9`, implementation commit
  `5f3af472a3c59f2ad3dcbaae6d448145869ba9ca`, is frozen. Candidate-v3 SHA-256
  `00400c9d445fd96287e5a6848362e3519cad75087f19dc16c235968856b9ff6a`;
  exact preserved review-v2 SHA-256
  `4dab766e7616e40630d2000499319f37ee8216851f5a73f25cf74f6a2c9e8ad4`;
  response-v2 SHA-256
  `9e0e2be78603b2069961d8b363cd50715a0d58d53f48910ceaa8790f8ac92556`.
  Implementer evidence is 49 focused passes and a genuinely fresh **458 passed** full
  suite. V2-R4a/R4b/R6/R2a/R2b/R7 claim executable corrections and R8 prior/full-content
  assertions were strengthened. The attributed failed-fsync case remains explicitly
  unavailable/unpassed. Astra-high renewed review is active against this exact revision.
- V3 review SHA-256
  `b5f7fe402404d8d8e9a41d55a779b56035ce1c39faf4515b82874d88cd9489e6`
  returned **FAIL** after all 25 hashes matched, 49 focused tests passed independently and
  seven targeted probes ran. Three narrower blockers remain: an omitted optional result
  field commits but fails first read/reopen; an event-only projection transition commits
  but fails reconstruction; and a symlink-parent plus `..` path can bind the owner lock to
  a different database identity than SQLite, allowing a second writer/importer. The
  attributed failed-fsync acceptance remains separately unavailable. Because compatible
  validation and path-identity failures have recurred across three reviews, further patching
  is paused for `/root/fr07_schema_path_diagnosis` to define unified write/read/recovery
  schemas and one canonical store-identity algorithm before the next candidate.
- Focused diagnosis SHA-256
  `5f1d7d7113a47e5db07219d933b7f60c491ef130e29054b5b36dc040e591c6f7`
  found no contract ambiguity: admission, write, read, startup and reconstruction must use
  one record codec and one reducer; store ownership must use one strict path identity that
  rejects dot-segment and symlink aliases. `/root/fr07_impl` resumed a bounded v4 correction
  on that design; no candidate is frozen yet.
- `/root/fr07_fsync_design` (Astra-high) separately established that Exqlite 0.40 can load a
  connection-scoped test extension on this host. Its report SHA-256 is
  `d3c2da810a3d44068ed38fdfc878323168e34005dad3c30b0ab3fac4a6a394d7`.
  The recommended fixture wraps the actual SQLite WAL `xSync` method and returns
  `SQLITE_IOERR_FSYNC`; this can satisfy FR-07's expressly permitted VFS-fault route if it is
  implemented, executed and independently reviewed. It proves an attributed VFS sync fault,
  not a failed physical kernel `fsync` syscall. FR-07 remains unaccepted meanwhile.
- Unified v4 candidate `8d2447e73dd29fdacc797ddea7fd47ab32299efe`, tree
  `2c8467430faf53d0aa676048ddd963ed727296db`, is frozen for Astra-high review; implementation
  commit/tree are `257671e083908901390d622b6c6bfd4df2f3b9a8` /
  `ea6f7c10b19e42dea61c341f0a8ee51a40b07d09`. Candidate-v4 SHA-256 is
  `8f61ce89e14cadd0827c812aa64da9cab3876ccf409d0978ea85c6262a262f65`; all 37 manifest
  entries matched for the implementer. Fetched dependency directories are untracked and
  excluded from the candidate.
- Pinned warnings-as-errors compilation passed, a fresh focused suite passed 60 tests, and
  the exact frozen-source fresh full suite passed 469. The test-only native shim loaded into
  the actual Exqlite connection and produced one attributed WAL `xSync`
  `SQLITE_IOERR_FSYNC (1034)` in ordinary and hard-exit fixtures, with no acknowledgment,
  recovery fencing, complete reconstruction/backup and ambiguity-safe retry. This remains
  VFS-fault evidence, not a physical-medium or kernel-`fsync` claim.
- Prepared Astra-high reviewer `/root/fr07_v4_review_prep` owns exact-candidate review using
  checklist SHA-256 `4e3b5a2c00708a99830b951d86e26a0e344a9f7ea808f3e6e46cab3dceaabda2`.
  After freeze, the implementer disclosed that startup may lack a typed semantic validator
  for an injected unsupported child ledger-generation row. The candidate was not changed;
  the reviewer must independently probe and disposition this risk.
- The implementer then withdrew v4 before verdict after finding a second definite mismatch:
  the sync fixture exercised an ordinary transaction rather than the required complete
  protected claim/reservation/ledger bundle, and its ordinary reopen branch omitted the
  same-command retry. Review was interrupted without a verdict. V5 must add both protected
  ordinary/hard-exit fixtures, full-table outcomes and retry, plus the typed ledger startup
  validator; v4 remains immutable rejected history.
- V5 candidate `ff9cbb725a32e13d4062b570521574f01e00af17`, tree
  `5055e3687feac8e5a60499b920d8f8b565d07597`, is frozen for the prepared Astra-high
  reviewer. Implementation commit/tree are `d25a51f8b219a8a49ed9e83b3d97d972058254f3` /
  `b454a2fd0f4af1669ad02d616bacfd3148630738`; candidate-v5 SHA-256 is
  `5eb42bbbe4a27e4d58f0c570f532483b23d395730bf733007116dd744011975f`, and all 39
  implementation-manifest entries matched.
- Exact-candidate evidence passed warnings-as-errors compilation, 62 focused tests and a
  fresh 471-test full model-free suite. V5 adds typed ledger-generation validation plus
  ordinary/hard-exit complete protected-bundle VFS `xSync` fixtures with every authority
  table checked, no acknowledgment, fencing/recovery and same-command ambiguity-safe retry.
  The evidence remains explicitly a SQLite VFS error through Exqlite, not a failed kernel
  `fsync(2)`, power-loss or physical-media claim.
- Astra-high v5 review SHA-256
  `e5d838581d3dd76156798ec4423cba99a3b21090037afa2d90ebc653cd6811fa`
  returned **FAIL** after matching all 39 hashes, passing 62 focused tests and running nine
  characterization probes. Six blockers remain: missing result/invalid committed-sequence
  authority can reopen or continue unfenced; a non-map proposal result crashes before codec
  validation; backup accepts an owner-journal sidecar pathname later removed by SQLite;
  typed ledger semantics are not shared with live revision reads; import rerun can certify a
  manifest after its retained records disappear; and live projection SQL does not share the
  diagnosis-required reducer with reconstruction.
- The review independently strengthened and **passed** the protected VFS `xSync` evidence:
  both absent and complete recovery outcomes were observed, retried and matched a full-row
  18-table oracle. The separate full suite passed 470/471; its sole saved-benchmark equality
  failure is unchanged pre-FR-21 code and is not attributed to storage. Candidate `ff9cbb7`
  remains rejected and unintegrated.
- Because the same validator/fencing boundary remained incomplete after the prior diagnosis,
  `/root/fr07_v6_diagnosis` (fresh Astra-high) is performing a read-only exhaustive closure
  map across all authoritative reads, startup, backup, import certification, sidecar names and
  live/reconstruction reducer calls before another implementation attempt.
- Focused v6 diagnosis SHA-256
  `fc6013eaf46ae39c6966397d4feb1c8d9fb35b8137800e05a0dcd6d88cfea74e` found no contract
  ambiguity. It specifies one `Authority` retained-read/validation boundary, one common
  corruption/storage fence, one complete authority/owner/publication path namespace and the
  existing projection reducer shared by live CAS and reconstruction. Its exhaustive matrix
  covers all 18 tables, required relations, result/event sequence bounds, every revision
  family, importer retained-byte completeness and every SQLite sidecar family.
- The current format cannot detect a coordinated, internally consistent rewrite that erases
  every protected-membership row; doing so would require a new externally anchored membership
  witness. The current FR-06/FR-07 contract requires atomic bundles, typed authority,
  relational completeness and recovery on detected corruption, not resistance to arbitrary
  trusted raw-SQL history replacement. V6 therefore adds no table or acceptance amendment and
  records this evidence limit explicitly.
- `/root/fr07_impl` resumed as the single v6 owner with the diagnosis's bounded production,
  test and documentation paths. It must implement the entire call-site matrix and Rule-41
  sweep, retain the independently credited full-row VFS sync proof, and freeze only after
  format, warnings-as-errors compile, focused and honest full-suite evidence.
- Two read-only Sol-medium implementation-support probes ran concurrently against the mutable
  v6 tree without editing it. The relation probe report SHA-256 is
  `961bc020e70d0219e1b6cf2c9e55a8a64e3965c690ec7b86a2de258aa73577ed`; its executable
  probe SHA-256 is `af73ddc42830d0e385e223bada28fb1f0f5da7e5fc2ccc1246b1d1641473dd52`.
  It passed targeted codec/global-relation/reducer behavior but reproduced three scoped-read
  gaps: unknown `sqlite_sequence`, a corrupt earlier projection carrier, and a second related
  reservation could remain invisible to live reads while global backup validation caught them.
- The path/import probe passed 29 of 30 targeted cases and reproduced pre-existing recovered-
  artifact namespace admission, deterministic publication-temp rerun failure, broad recovery
  deletion of an unrelated matching temp file, direct `Database.initialize/2` sidecar removal,
  and unbounded retained legacy materialization. Its session then terminated under a platform
  cybersecurity safety filter before producing a formal report; these are recorded as delivered
  implementation findings, **not** as a completed independent review. The sole writer owns
  exact regression coverage and resolution before freeze.

### FR-08 preparation

- `/root/fr08_investigate` completed a read-only mutation/replay inventory while FR-07
  implementation proceeds. The concise durable [investigation](fr-08/investigation.md)
  records the FR-07 handoff capabilities, duplicated mutation paths, acceptance risks and
  implementation order. FR-08 remains blocked and no FR-08 implementation owner exists.

### FR-21

- **Active owner:** `/root/fr21_impl` (Sol-medium), isolated from main commit `8830027`.
  FR-01, FR-04 and FR-05 have reviewed implementation and clean-checkout integration
  attestations, so the explicit prerequisites are satisfied. This work may proceed beside
  FR-07 because ownership is disjoint.
- Permitted ownership is a Foundry-only CI workflow, a new isolated local CI/provenance
  runner, FR-21-specific tests and documentation/evidence. It must not edit
  `foundry/mix.exs`, `foundry/mix.lock`, Coordinator, CLI, startup, durable-store files or
  the live daemon. The runner must use fresh runtime/TMPDIR state, run twice from a clean
  checkout without corpus services, name exclusions, identify source/tool/dependency
  inputs, and prohibit paid/provider/live-pane behavior. Later tickets extend the job;
  FR-21 must not claim FR-22 lifecycle completion.
- `/root/fr21_impl` froze candidate
  `85a74492959e6db51f4a0f03c218990afb97b0c3`, tree
  `cc730c6bf3cd7b62a66cc59b754176b16ad98521`; candidate record SHA-256
  `b3a6e5bb95afbc8032e98afddd44d302cfd41f664767c750dcf8767c94d6c7c2`.
  Two detached clean-checkout runs each completed all six stages and 426 tests with
  distinct isolated roots. Provenance manifests SHA-256
  `577ffa434d86d2cbe934eaf0ce3354ec70f74d52093f4275468b5f1ee64f394e`
  and `8fbf87e9572c9bf490012e3a63b6315c1b1df57ba3dd1e90224fbe4cade54099`
  bind each run's source/tree, toolchain, lock entries, receipts, exclusions and generated
  escript. The first pre-correction clean run exposed two RPC tests' hard-coded build path;
  the frozen candidate derives the ebin from `Mix.Project.build_path/0` and its focused
  eight-test non-default-build run passed.
- The candidate adds a Foundry-only workflow/Elixir runner, pins seven existing format-debt
  files by byte hash, removes the tracked generated escript and duplicate vendored OWL,
  retires the absent Python diagnostic, and makes obsolete Python-migration parity fail
  closed. It does not modify Mix inputs, Coordinator, CLI, startup, durable store or live
  state. `/root/fr21_review` (Sol-high) is independently reviewing the frozen deletion,
  portability, isolation and provenance boundary.
- Independent Sol-high review SHA-256
  `da11d18a4cfe7f7842ccb9309e63f6dbb8319b41967c5f0e30fb723c86eac36c`
  returned **FAIL**, despite independently reproducing two clean 426/426 six-stage runs.
  Five concrete blockers remain: an undeclared ambient Python/tiktoken dependency in the
  default suite; dirty/untracked source can enter a passing escript without byte identity;
  setup failures may omit or materially truncate provenance; OTP 29.0.1 is accepted as
  the exact 29.0.5 policy; and path/unlocked dependency sources can evade the stated
  lockfile-only policy. Candidate `85a7449` remains frozen and unintegrated. The same
  implementation owner is correcting these exact portability/provenance failures before
  renewed review.
- V2 implementation commit `4e4acf784742381127bfd54fef49faf957d1c256`, tree
  `4e95b891f23d8822122acb3d919605b793c64491`, addresses B1–B5. The frozen evidence-bearing
  candidate is `1bd381d96d6c58379d1a9586888fca56811bdc4f`, tree
  `b460f67a25ff19eb71f87234b4b160911b983598`; candidate-v2 and acceptance-v2 SHA-256 are
  `c2df8bf68a739a453f50980b56e91302c99d4a0b8c04300d936acfdace7ca3a3` and
  `572412b6bc7805f3c1bb17c6d1b93079eff1c881d88c546ae739c1eecf76d69c`.
  Focused checks passed 13 tests with one optional historical tokenizer recomputation
  excluded. Two exact-final detached runs each passed 431 tests with that one exclusion,
  clean pre/post source and independent roots; manifest SHA-256 values are
  `f9cfc6da6b95962c60bd721dba42daf88f94e560e158679bd4cf1f6f3aa9d51e` and
  `890c0ba7e7d8a327eee48850cc226f4fe71929b264eaef9e92d29e5c04e845a8`.
  Exact-final dirty-source and missing-executable probes, plus clean committed toolchain,
  missing-project and path-dependency probes, failed at their intended gates with
  attributable manifests. Generated escript bytes differed between clean builds; each is
  individually hash-bound and no byte-reproducible packaging claim is made.
- `/root/fr21_v2_review` (fresh Sol-high) independently owns review of exact candidate
  `1bd381d`; it must reproduce clean execution, challenge B1–B5 and decide whether the
  per-build artifact identity satisfies FR-21. Candidate files are frozen meanwhile.
- Fresh independent review SHA-256
  `f9477b3497dc925eabd97a05b5af4806c523c071ef5f1f071fe10f87a124c64f`
  returned **FAIL** with one remaining FR-21/F24 blocker in the B3 family. The reviewer
  independently passed 431 tests with one declared exclusion and found B1, B2, B4 and B5
  resolved. Per-build artifact hashes satisfy FR-21; differing escript bytes remain an
  honest non-blocking reproducible-build limitation.
- The remaining case creates the requested output directory but makes `provenance.json`
  itself an unwritable directory. The runner fails closed, but retries the impossible write,
  returns setup exit 2 and omits the destination path, contradicting its documented exit-70
  infrastructure contract. The same implementation owner is making the smallest correction:
  return 70, identify path/reason once, add the executable boundary regression, and obtain
  renewed independent review. Candidate `1bd381d` remains unintegrated.
- Focused v3 correction `f76be70955452e378274e1784886b57bf618f033`, tree
  `c49c7fc89f4aab6c561c61df4936192424100390`, is frozen. Its delta from reviewed v2 is
  only `ci.ex`, `ci_test.exs` and three FR-21 review/evidence documents; the nonblocking
  CLI wording suggestion was excluded because main carries unrelated CLI edits. The v2
  review is preserved byte-for-byte at SHA-256 `f9477b3497dc925eabd97a05b5af4806c523c071ef5f1f071fe10f87a124c64f`.
- Exact-candidate focused/non-regression evidence passed 14 tests with the optional Python
  recomputation excluded. The adversarial pre-existing `provenance.json/` directory now
  exits 70, reports the exact destination and `:eisdir` once, leaves no regular manifest or
  artifact, and preserves clean source. The same independent Sol-high reviewer is checking
  only this correction and regressions of already accepted B1/B2/B4/B5 behavior.
- Renewed focused review [record](fr-21/review-v3.md), SHA-256
  `de1cf2bbe9cefdf391850a005fc54cf6b75d673095fca7fa486a355c9ebc9b42`, returned
  **PASS** for exact candidate `f76be70`. Its detached reproducer returned 70, printed the
  full manifest path and `:eisdir` exactly once, left no manifest/artifact/temp file and
  retained clean source. Independent focused evidence passed 14 tests with one declared
  exclusion, the CI file passed 10, and compile/format passed. Existing B1/B2/B4/B5 behavior
  remained intact. Provider/live/activation/integration/FR-22 evidence remains excluded.
- The reviewed net candidate is being integrated without its no-net intermediate CLI history;
  exact candidate-owned implementation/test/workflow hashes match `f76be70`, while the
  pre-existing dirty root CLI and Coordinator edits remain unstaged and untouched. The ticket
  is not complete until the actual integration commit passes clean-checkout validation.
- Reviewed FR-21 was integrated as `a0c7a72c173d7d8e9929e6ee235d9ce138afa703`, tree
  `0437785f9395f7ea261e0d1421cb4aef3fb03ee6`. Its clean detached CI manifest SHA-256
  `dd63583f406c31369563dee0ebccf6e917e246cc7bef585f3367a95d1cd9c047` binds that exact
  source/tree before and after, the reviewed runner/workflow hashes, pinned toolchain,
  locked Hex dependency and generated artifact SHA-256
  `bea5d7d4187fb15c9cb3a245112a51ba3a25c0468a3db162acf4cf27483b0110`.
  All six stages passed with 432 tests and one explicit optional recomputation exclusion.
  Independent post-integration [attestation](fr-21/integration-attestation.md), normalized
  repository SHA-256 `166ad3620d88af9adff408ec3c62736a916769e4f4d8b308c209413c49752b0a`, returned
  **PASS**. It matched every candidate runtime/workflow/test blob, the exact 27-path deletion
  set and the four-doc-only candidate-to-integration delta; CLI was byte-unchanged and no
  Coordinator/local artifact entered. Its independent full gate also passed 432 tests with
  one exclusion, manifest SHA-256
  `63d6989f95aa0eac975aef57fbfa0530ea5934dc49749d550578cea170c86357`.
  The reviewer's `/tmp` artifact SHA-256 was
  `7977fa645e08a40d4ccba3546449685b42ce5abb83ffc82de58f975b42714d6e`;
  repository normalization removed only one extra blank line at EOF and changed no content.
  FR-21 is implemented, reviewed and integrated; **not deployed**. Provider/live/activation,
  byte-reproducible escripts and FR-22 lifecycle evidence remain explicitly unclaimed.

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

## FR-07 v6 recovery and review handoff — 2026-09-19

- Main history advanced to `75a56c13ebafa0ab7e67f2cf12f47ad84aad2ebc` after the
  mutable FR-07 worktree and unreferenced v5/v6 Git objects were removed. The exact old
  base `8aa0ebddbfb5fa834bbefa53d1f84b992e4c25bd` survived. No newer main work was reset
  or overwritten.
- The implementation owner replayed the surviving rollout journal through its final v6
  patch, preserving successful edits and formatting boundaries and excluding failed patch
  attempts. The stable rollout prefix SHA-256 is
  `ecf3d05e03f059d67c0b80f95bfaf8dc7589e42e8c2e32b1f9c774c1d22562d1`.
  Recovered diagnosis/relation artifacts match their previously recorded SHA-256 values.
- The recovered current-main candidate is revision
  `103ee1de234af8929d504e78c51297b6d9907d71`, tree
  `89e7dbf935211b63dff3353c246eefd546fbbae1`, on
  `repair/fr07-v6-recovered` in `/Users/raymondluong/dev/pramana-fr07-worktree`.
  Runtime/review-input revision `940b8f710c661ef5f7ecd7c5c5ae9cc3fbed2ea6` has tree
  `2d1632ac183c19a50d87b74ddeb7332f9b7e6f08`. The worktree is clean.
- Fresh evidence on current main: pinned warnings-as-errors compilation passed for 90
  project files; the durable-store suite passed **68/68**. The full suite passed 500/501;
  its sole projection-benchmark failure reproduced alone as 1/2 because Python
  `tiktoken` is unavailable and the documented fallback count differs from the benchmark
  expectation. This is retained as an honest non-FR-07 exclusion, not a passing full run.
- Candidate v6 remains **unreviewed and unintegrated**. Attempts to spawn or resume the
  required independent Astra-high reviewer returned `agent thread limit reached`; no
  substitute review or verdict is claimed. FR-08 and every other dependent ticket remain
  blocked. Exact resumable next step: obtain a fresh Astra-high review of revision
  `103ee1de234af8929d504e78c51297b6d9907d71`, dispose any findings, then integrate and
  revalidate the reviewed candidate before marking FR-07 complete.

### FR-07 recovered v6 independent review

- Fresh Astra-high review SHA-256
  `7151d544e1d64e757d75f33428e361d668c84356631b09fed1d3daeda491f35f`
  returned **FAIL** after matching revision/tree and all 45 manifest hashes. Independent
  evidence passed warnings-as-errors compilation, 81 focused tests, a fresh 501-test full
  suite and both exact full-row VFS xSync recovery/retry branches.
- Six blockers/shortfalls remain: a rewound projection can be certified and used; scoped
  projection/ledger reads omit required owner/result relations and global reads miss orphan
  effects; malformed protected facts/lookups can crash or incorrectly fence; import can
  overwrite an unowned regular staging file; schema checks validate index names rather
  than required definitions; and scoped projection validation accumulates an unbounded
  unrelated event prefix.
- Candidate `103ee1de` remains rejected and unintegrated. The same implementation owner is
  applying the bounded B1–B6 correction with executable regressions. A changed candidate
  requires renewed independent review; credited 18-table, import-completeness, shared-reducer
  and VFS evidence must not be weakened.

### FR-07 candidate v7 and renewed review

- V7 review revision `c75bb340a4e94c8969df201b6d98cc0f35d56831`, tree
  `e15eaca44f7e744496654efb3424603e86bb79cd`, claimed B1–B6 corrections and added
  permanent regressions. Implementer evidence passed warnings-as-errors compilation and
  75 durable-store tests; its full run was 507/508 with only the known missing-`tiktoken`
  projection benchmark mismatch.
- Renewed Astra-high review SHA-256
  `d7a2f287b463d7abc2dd5ec72205b8849e759d2737d376cc8385546a71379c86`
  returned **FAIL** after matching all 50 hashes. Independent compile, 88 focused tests,
  508 full-suite tests and the full-row VFS oracle passed. B3–B6 are corrected.
- Two local retained-reader blockers remain: a missing projection row with retained carriers
  is accepted as an absent dependency, and projection/ledger owner traversal accepts an
  impossible committed sequence; a rejected retained effect owner also raises instead of
  returning typed corruption. V7 is rejected and unintegrated. The implementation owner is
  making only this bounded v8 correction before another renewed review.

### FR-07 candidate v8 and renewed review

- V8 review revision `edd91cca8af35d5078808c3b1645077700b922e7`, tree
  `54d1f8a262a971aaa0eb88fe39dbce29fd5077cb`, closed the exact V7-R1/R2 traces.
  Implementer evidence passed 91 focused tests; its full run was 510/511 with only the
  known missing-`tiktoken` benchmark mismatch.
- Renewed Astra-high review SHA-256
  `60353069c5b144f21f0124d5d59b2c3912e18f8eb8d335ec0561c7fb63b3d72b`
  returned **FAIL** after matching all 53 hashes. The exact target closure probes, build,
  91 focused tests and full-row VFS oracle passed. The review's full run was 510/511 due
  one unrelated telemetry timing assertion that passed alone.
- One local blocker remains: the indexed scoped projection reader can decode a legal
  carrier-free event whose retained index columns claim a carrier, then raise before shared
  binding validation. V8 remains rejected and unintegrated. V9 is restricted to validating
  bound carrier rows before reduction and adding the exact no-exception regression.

### FR-07 candidate v9, acceptance and current-upstream integration

- V9 freeze revision `8d7223b79cb237d3406f156c7d1a06a8bcb48d81`, tree
  `894e47756305f1b0fb615c6471f2dfdc644f16f3`, contains implementation revision
  `af0c51b4682c50080e67194dd853fbaa1eebace7`. Candidate-v9 SHA-256 is
  `223aac42be3a823561d37a083f9e5da614002b9bb5c96151e32ba79c9c13873b`; all 56
  manifest entries matched. Implementer evidence passed warnings-as-errors compilation,
  92 focused tests and 512 full-suite tests.
- Fresh Astra-high [review](fr-07/review-v9.md), SHA-256
  `08379ffd3315ec2724c4578a0a14e690f535238104107c778bd8d777efbf8638`, returned
  **PASS**. It independently reproduced the exact v8 residual and expanded absent/entity/
  namespace mismatch matrix, four prior closure probes, 92 focused tests and both normal-
  close and hard-exit full-row VFS recovery/retry branches. No bounded FR-07 blocker remains;
  physical power-loss/media guarantees and downstream lifecycle duties remain excluded.
- The reviewed linear candidate was integrated locally through
  `c4816b2e1ef5ae41943c98591246851b2672561f`, tree
  `2a488b7fc2a54ccf0059ddeb5038c251ffb9948b`. Initial post-integration validation first
  stopped before compilation because the main checkout lacked the newly locked Exqlite
  source. `mise exec -- mix deps.get` fetched the unchanged lockfile versions; the rerun
  compiled 90 project files with warnings as errors, passed 92 focused tests and passed
  512/512 full-suite tests. The preflight miss is not counted as a test pass.
- A fresh `git fetch origin --prune` showed GitHub `origin/main` had advanced from the
  recorded base `75a56c1` to `4c91bf7ef917e67c73574eb0246d8d57cc28806d` by 601
  commits. The histories were merged rather than rebased so every candidate/review identity
  remains stable. Only `foundry/README.md` overlaps the 56-path candidate manifest; no
  durable-store source/test, `mix.exs`, `mix.lock` or EventLog path changed upstream.
- On the combined merge tree, pinned warnings-as-errors compilation passed for 105 project
  files; the focused FR-07 suite passed 92/92 at seed 9241; the complete Foundry suite
  passed 546/546 at seed 9242. All commands exited zero under fresh isolated `/private/tmp`
  and build roots with provider/runtime variables removed. No daemon, credential, provider,
  deployment or activation path was used.
- Upstream adds a fail-closed executable FR-07→FR-08 handoff gate but intentionally no
  accepted-store adapter. Its own contract says a ready report is not FR-07 acceptance.
  The thin adapter and revision-bound ready report remain prerequisites to beginning FR-08;
  they are deferred until after the authorized whole-Foundry alignment audit.
- FR-07 is implemented, independently reviewed and locally integrated; **not deployed**.
  FR-19 retains operating/physical durability and FR-22 retains full lifecycle acceptance.
  Per operator direction, no FR-08 implementation starts before a fresh Astra-xhigh audit
  reviews the new strategy/direction documents, actual Elixir source, repair history,
  workflow contract and all F01–F24 obligations.

## Whole-Foundry alignment disposition and documentation candidate — 2026-09-19

- The requested independent read-only audit completed against pushed main
  `2f603675e3feb1a65f0ce57a3bd69aa93deec29d`, tree
  `73bc4bd386cf67d61cf8563814a45d1c1c9e0af0`. Its exact preserved report is
  [ALIGNMENT-AUDIT-2026-09-19.md](ALIGNMENT-AUDIT-2026-09-19.md), SHA-256
  `c825b22bb857ccccd08171d79fae3b2d33ce76025fdf7dcb5db91ecc3ff63fe7`;
  it is byte-identical to `/tmp/foundry-alignment-audit-2f60367.md`. The independent
  session changed no backlog, source, runtime, policy, credential, Git ref, deployment or
  activation permission. Coordinator disposition is recorded only in current authority
  documents; the report itself remains unchanged evidence.
- The disposition continues the existing repair. REPAIR-PLAN remains the sole backlog,
  with 23 ticket nodes (FR-01–FR-22 plus FR-15a). F23 and F24 remain findings under
  FR-04/21/22 and FR-21/22, not phantom FR-23/24 tickets. Every F01–F24 routing row and
  acceptance obligation remains present.
- FR-07 remains complete only for accepted v9 foundation evidence. H0 now produces an
  honest revision-bound supported/unavailable inventory and may remain blocked. The old
  full-seven-probe-before-any-FR-08 requirement is explicitly replaced by H0 → FR-08A
  protected primitives/full substantive handoff proof → FR-08B every-ingress one-reducer
  live/replay migration. Direct SQL, empty-table positive inference and synthetic adapters
  remain prohibited.
- Historical FR-04 PASS remains historical evidence. A newly demonstrated current-source
  defect—live argv containing `defunct` can satisfy `ProcessGroup.gone?/1`—is routed to a
  bounded FR-04/10 correction before reuse for quiescence. Required cases are live marker,
  zombie, absent, recycled identity, observation failure and `Checks.Runner` cancellation;
  FR-10 retains descendant/issuer/channel reconciliation.
- FR-15a is split into feasibility/provisioning specification and actual isolation/
  conformance; FR-18 into minimal honest observations and full producer/status/usage; and
  FR-19 into operational backup/recovery and later diagnostic retention/relocation. A
  bounded joint FR-09/15a feasibility checkpoint evaluates pinned Pi first, with synthetic
  credentials and controlled endpoints. OMP remains governing until explicit contract
  revision and independent review; automatic execution remains blocked.
- Dependency changes follow the audited acyclic graph. FR-17 now depends on FR-18A and
  FR-19A; FR-20 explicitly depends on FR-17. FR-13 omits full optional FR-15 only while
  FR-08A/B and FR-15aB explicitly own core steering/policy/grant interfaces; otherwise the
  edge must be restored before FR-13 starts.
- Exact known limitations are unchanged: the live/deployed release was not inspected;
  FR-07 lacks the protected lifecycle APIs assigned to FR-08A; the current JSONL live path
  and separate replay remain; no OMP/Pi subscription/isolation topology is proved; no
  source/runtime/provider/credential/policy/deployment/activation changed; no full suite,
  host provisioning, provider call, Git promotion, activation or physical fault test was
  run for this documentation candidate. The untracked root `apps/` tree remains untouched.
- Next resumable step: implement neither FR-08 nor ProcessGroup in this documentation
  change. After independent review of the frozen documentation candidate, assign the
  bounded ProcessGroup correction and H0 report under separate exact candidates; the
  Pi-first feasibility investigation may run in its bounded early lane without enabling
  execution or changing the OMP contract.

### Independent review and integration evidence

- The exact frozen 12-path documentation candidate received independent Astra-high
  [PASS](alignment-disposition-review-2026-09-19.md), SHA-256
  `5b0b8cba64edad3db669d84d86a9b28f97664a8efa74c4c97a4fbe4e4288e5f7`.
  The reviewer independently matched the candidate/diff/audit identities, all 24 finding
  routing rows and all 43 original acceptance paragraphs; parsed an acyclic 29-node,
  78-edge dependency table with full FR-22 reachability; and passed the 80-test docs check.
- The reviewed candidate was committed unchanged on main as
  `c6ec8d76e3aceffbf2660a2f516013718f452a9a`. This closes only the controlled
  documentation disposition. The review explicitly does not accept FR-08 implementation,
  certify current ProcessGroup cleanup, authorize provider/host work, or establish
  deployment/activation readiness. No source, runtime, policy or credential changed in
  this evidence-only follow-up.

## Durable execution acceleration strategy — 2026-09-19

- The operator accepted two explicit finish lines. The first is a supervised dogfood alpha:
  real ticket intake, durable tracking/replay, bounded work packets, durable independent
  review receipts and restart recovery, with execution still supervised/manual. The second
  is the full repaired system, ending only with the remaining isolation, automatic
  execution, conserved budgets, Git custody, immutable activation/rollback, maintenance,
  constrained improvement and FR-22 lifecycle acceptance.
- `REPAIR-PLAN.md` remains the sole backlog. The milestone overlay changes no ticket
  status, dependency, finding route or acceptance obligation and gives no authority to
  enable an unproved provider path.
- Work is grouped into coherent Batches A–E: current FR-04/H0/FR-19A; FR-08A + minimal
  FR-18A; FR-08B/10/11/12; supervised dogfood; then isolation/harness, artifact/Git,
  activation and final lifecycle. Per-ticket subcommits and acceptance matrices remain
  attributable even when a batch receives one frozen-candidate review.
- The durable review economy is Sol-medium implementation, Sol-high routine review,
  Astra-high at the four critical authority/isolation/Git/activation lifecycle gates,
  Astra-medium for narrow corrections, and Astra-xhigh only for a newly demonstrated
  whole-system contradiction. Tests run focused per subcommit, full at freeze and after
  integration, with reusable hostile probes and one evidence manifest per batch.

## FR-04 current-process-state correction integration — 2026-09-19

- The bounded implementation candidate `1495bca24e0d76b20fbbf633255e437df9783816`
  corrected the current-source false-death predicate by binding observations to PID,
  process-group ID and start time and treating only matching `Z` state or actual absence
  as gone. Live command text containing `defunct`, recycled identity and observation
  failure no longer become cancellation success.
- Independent Sol-high review commit
  `bf5ee29e207aabd5819147a21a09ad4180212a00` returned **PASS** for this bounded
  correction. It reproduced the base defect, reran the 32 focused checks and retained
  FR-10's descendant/issuer/channel and whole-group reconciliation as open work. Candidate
  and exact-base standalone CI reproduced the same 74 pre-existing macOS
  `:database_parent_symlink_not_allowed` failures, so neither report claims a full-suite
  pass.
- The candidate, evidence and review were integrated on current main as
  `861055043f903b0858e1777265b2d05914e59996`,
  `4ec47527ca6b954ef856b807032bb3ad37d8a36a` and
  `d48cb135ad121b64b3fa6b36298f24d1d9c4cd0e` (tree
  `b7a0e9ba3e1ee94272b98b62b01c495fd385f153`). The reviewed four source/test files
  remained byte-identical. An initial isolated validation stopped before compilation
  because its fresh dependency root was empty; after fetching the unchanged lockfile,
  warnings-as-errors compilation passed for 105 files and the focused suite passed 32/32
  at seed 8021. This changes no provider, daemon, deployment or activation state.

## H0 accepted-FR-07 boundary integration — 2026-09-19

- The first frozen H0 candidate `3e1ed8bb643e6f68cf604cb497f3c0f41770e7b0`
  correctly reported four supported and three unavailable capabilities but received an
  independent **BLOCKER** review at
  `b5abb5eab4d16c0075e5e2180a5ff059b51c9a70`: one receipt was not reproducible across
  fresh BEAM processes and the report did not bind its accepted identity to the actually
  loaded public implementation.
- Correction `a23482de566dcd7be567dff49985ff8c97536df9` replaced Erlang-term hashing
  with documented sorted-key canonical JSON and verifies source SHA-256 plus loaded BEAM
  MD5 before every probe. Separate opposite-load-order BEAMs reproduce the frozen report;
  a changed in-memory `Gateway.command/2` sentinel executes and forces all seven results
  unavailable with `identity_mismatch_refused`.
- Corrected candidate `4c8734c6473be97da77f299bc4b42cd720cdf0b6`, tree
  `f120fcaff6967f6dc3a734200d2e797b2ed9c2ed`, received narrow independent Astra-medium
  **PASS** at review commit `9715cf846f4485821482e7a5d929b58f1b9087ad`.
  The reviewer verified all corrected and accepted-v9 manifest entries, both blocker
  reproductions, 18 hostile protected-field variants, 19 focused tests, two independent
  public controls, 109 broader regressions and the 80-test documentation gate.
- The complete candidate→BLOCKER→correction→PASS chain was integrated on current main
  through `c3c11ac367e00b7f992a5c65e4c1aa99c291636e`, tree
  `074c408e73b27cf098f210c9fbca05e362bfc202`. Post-integration warnings-as-errors
  compilation passed for 106 files, the focused suite passed 19/19 at seed 9251 and the
  documentation gate passed 80/80. H0 is complete as an honest evidence checkpoint, not
  ready for migration: complete evolving policy/control/allocation CAS, atomic protected
  receipt/lease/claim/settlement/ledger transitions and authenticated inbox sequence/seal
  remain unavailable and are now FR-08A work. The existing native VFS exit 139 is excluded;
  no provider, daemon, credential, deployment or activation was exercised.

## FR-19A candidate and independent blocker review — 2026-09-19

- Implementation `0391468926bc8f9c1591e8a619d80d6661cf9a5d` and frozen
  candidate `d1ce73ee9da548a64a447106f83d3d7f8ce1b567`, tree
  `005ddf2ff0d241a71f4dbfe4d995c72e5983d35f`, remain unintegrated on
  `repair/fr19a-operational-storage`. Credited work includes bounded recent-event queries,
  explicit capacity/last-sequence health, content/replay-checked backup and checkpoint,
  offline owner-lock verification, corrupt-store fencing, retained claim/ledger recovery
  evidence and public relocation disablement pending FR-19B.
- Fresh Astra-high review `705e7b604483c631b2ac968c9a99ca627d8ad616` returned
  **BLOCKER**. B1 reproduces the default 5-second public `GenServer.call` expiring at the
  same deadline as a stalled capacity probe instead of returning explicit unknown state.
  B2 finds backup maintenance errors can leave the gateway ready and that in-operation
  checkpoint/backup failure recovery with retained protected rows is unproved. Physical
  filesystem ENOSPC and kernel-sync acceptance remains required and unproved; logical
  SQLite fullness, RLIMIT, injected VFS sync and post-operation hard exit are not substitutes.
- The reviewer resolved the native sync exit-139 attribution as a fixture/header-selection
  defect: the fixture ignored external `MIX_DEPS_PATH`; selecting Exqlite's bundled headers
  made the unchanged candidate pass 2/2. Canonical-temp/bundled-header full CI passed 542
  tests with 13 intentional FR-19B skips and one optional tokenizer exclusion. No candidate
  source was changed by review. Next action is the smallest B1/B2 correction plus physical
  acceptance disposition, a newly frozen candidate and renewed independent review.

## Safe coordination pause — 2026-09-19

- Coordinator baseline remains pushed `main`/`origin/main`
  `fa636fb592eacf4ebd31b72fa377b0a86a6d3e3e`; the unrelated untracked root
  `apps/` tree remains untouched. No candidate below is integrated or accepted.
- FR-19A correction worktree `/private/tmp/pramana-fr19a-correction`, branch
  `repair/fr19a-correction`, is clean at checkpoint
  `9bd19022a096409081b531a1911fb201d8089ac5`, tree
  `b4730b90349ce591538670d576acb9fab295734a`. This source-only checkpoint moves
  the capacity probe to an internally bounded monitored worker so the gateway can
  remain responsive, and classifies post-preflight backup failures for fencing.
  Formatting, warnings-as-errors compilation of 107 files and `git diff --check`
  passed. It is **not** a frozen candidate: default-deadline responsiveness and
  in-operation failure regressions, complete retained-authority checks, physical
  filesystem ENOSPC/kernel-sync evidence, candidate documentation and full CI remain.
- FR-08A worktree `/private/tmp/pramana-fr08a`, branch
  `repair/fr08a-protected-primitives`, is clean and unchanged at
  `fa636fb592eacf4ebd31b72fa377b0a86a6d3e3e`. Inspection confirmed the three H0
  unavailable areas and the additive implementation boundary: a versioned protected
  semantic API and migration through the existing Gateway, preserving the no-direct-SQL
  and single-store contract. Resume with migration/API plus focused read-set and
  idempotency tests before claim/receipt/lease/R5 lifecycle work.
- Checkpoint F worktree `/private/tmp/pramana-checkpoint-f`, branch
  `repair/checkpoint-f-feasibility`, is clean at partial evidence commit
  `5604afc4540e1bbab34bfbeec327f64ac0f6d8fc`, tree
  `5ac34ecb7375087916a6accaf8a6a4ecf04cbdea`. Its report records pinned local Pi,
  OMP and Herdr versions/digests and an honest blocked installed-Pi disposition.
  Documentation checks passed 80/80. No provider, RPC session, live daemon,
  installation, configuration contents or credential contents were used. The partial
  checkpoint still needs isolated synthetic Pi roots/endpoints, lifecycle/denial probes
  and a model-free useful build/test path before independent review or disposition.
- On resume, continue FR-19A regression/evidence work and FR-08A implementation in
  their existing isolated branches. Neither may be reviewed until newly frozen with
  exact acceptance evidence. Continue checkpoint F only inside its stated synthetic,
  provider-free boundary. Use Astra-medium for a genuinely narrow FR-19A critical
  rereview and Astra-high for FR-08A's first critical review.

## Coordination-efficiency policy made durable — 2026-09-19

- The operator requested that the token/speed recommendations survive goal resumption.
  `REPAIR-PLAN.md` now records the complete coordination discipline beside the existing
  two-level finish line, batches and review tiers: one writer per shared interface,
  compact evidence packets, focused-development/full-freeze validation, mechanically
  generated provenance, reusable hostile probes, stable implementer ownership, fresh
  frozen-candidate review, contradiction-first diagnosis, read-only downstream
  preparation and handle-based waiting instead of busy polling.
- These rules optimize execution only. They do not alter ticket status, dependencies,
  acceptance obligations, F01–F24 routing, provider/spending authority or FR-22's final
  lifecycle ownership. Future resumed coordination reads the authoritative repair plan
  and this log before dispatch.

## Checkpoint F provider-free feasibility integration — 2026-09-19

- Initial candidate `6582c9a79671af926bf49eb44b7faee54401ae74` received independent
  Sol-high **BLOCKER** review `a306a59af850cb439628c70b261de516d583c078`:
  `Port.open/2` overlaid the parent environment and Pi/Jiti wrote compiled extension
  state outside the owned root. Credited loopback lifecycle and denial findings were
  retained; no production capability was accepted.
- Corrected candidate `148476c93497653abbbc52fb040cf76927478d3f`, tree
  `e23217f94f295c115b893ac936c86ab719331647`, launches through fixed
  `/usr/bin/env -i`, proves hostile provider/proxy/auth/runtime variables and an extra
  inherited descriptor absent from Pi, RPC Bash and the explicit extension, and binds
  Pi/Jiti/npm/XDG/config/session/temp/cache state beneath one removed owned root.
- Fresh independent Sol-high rereview `ca8c6d0b5edc9a5cfb9c265e710b29f3210f5cbe`,
  tree `0f68389cb1f8ebea8536009ff65b6378c31ba52f`, returned **PASS**. Plain and
  restricted loopback-only probes passed, including quoted paths; documentation passed
  80/80. The review confirms only an honest F inventory: raw Pi RPC is feasible, while
  credential custody, R1/R5 request authorization/accounting, extension/tool/principal
  isolation, subscription conformance and governed execution remain blocked. OMP remains
  the selected contract.
- The complete partial-candidate, blocker-review, correction and PASS chain was integrated
  on current `main` through `2448599`. No provider/model, real credential content, live
  daemon, Herdr command, installation, deployment or activation was used. FR-15aA is now
  ready to turn the recorded blocked topology into a concrete provisioning specification;
  FR-09 and FR-15aB remain blocked by their other dependencies and actual conformance.

## FR-15aA provisioning specification integration — 2026-09-19

- Initial substantive candidate `ca4094e2d43212c3399ab5458e9af64c40640c14`
  received Astra-high **BLOCKER** review
  `edd22b21fe548bdf32818f78bc9119e205109a65`: it omitted the distinct R3 workflow-
  kernel principal, accepted seven hostile manifest mutations, and could confuse failed
  observations or pre-existing identities with safe provisioning/rollback state.
- Correction `5a7eb4633a0c63a12cd1bbf84c87be7ad9ef03a9` closed the kernel and
  ownership/preflight families. Focused Astra-medium rereview
  `5902944c065185ebbc3d716749cecd5eab0fdfdc` retained one B2 blocker: incomplete pin
  identity and last-write-wins duplicate security records.
- Final substantive candidate `9ed32575f2840e90fe3e1ebb1f1ebcd0bd54040b`, tree
  `1c5dd96f0da66286ecb47eec029c09b2f3733802`, makes every pin field mandatory,
  selects repository byte reads from trusted roots, and rejects duplicate principals,
  channels, pins, routes, callers, dependencies and kernel-authority lists before map
  construction. Final independent review `f093cbfabcd1be2b43eacf68fd42865f3d317c11`
  returned **PASS**.
- The complete attributable chain is integrated on `main` through
  `a1c66de64e7c4ec5d41a7d273bbdf54720710fef`. Integrated checks passed the
  manifest validator, 22 maintained hostile tests, independent mutation probes,
  formatting and the 80-test documentation gate. No host account, network, provider,
  credential, daemon, Herdr, installation or execution capability changed. FR-15aA is
  complete; FR-15aB still owns actual isolation and FR-09 owns installed-harness and
  subscription conformance.

## FR-19A operational storage integration — 2026-09-19

- Initial candidate `d1ce73ee9da548a64a447106f83d3d7f8ce1b567` received Astra-high
  **BLOCKER** review `705e7b604483c631b2ac968c9a99ca627d8ad616` for the default health
  deadline race, incomplete maintenance fencing/interruption, and missing physical
  ENOSPC/kernel-sync evidence. The correction retained all credited backup, corruption,
  authority and relocation-containment behavior.
- Linux workflow run `35498430877` supplies the bounded physical sync record: an exact
  owned device-mapper/loop/ext4 stack, unchanged Gateway backup descriptor returning
  `fsync EIO`, typed public failure and fencing, deterministic map restoration, orderly
  same-device remount, digest-stable complete destination/source authority and replay,
  and exact cleanup. The independently downloaded artifact ZIP hash is
  `ad315c15657068a921a1faeb73831a66c08bbecd252dc79145f539c7cca76959`.
  An owned Darwin filesystem separately proved physical ENOSPC. Neither result claims
  power-loss, failed-sync persistence, cache flush or media durability.
- Astra-high rereview `7ce0c65c0a4f72ec146abdbb26d8f0381f5e96d4` credited the physical
  evidence but retained B1 owner-death probe cleanup and B2 a zero-WAL interruption false
  positive. Implementation `6c1e5acb29b10e0cd40c692de87f05f1155804c8` added an independent
  controller/watchdog and a positive-frame, operation-scoped checkpoint/VACUUM fixture.
  Focused Astra-medium rereview `95eccd6b160b6f339376cfd79e7de81f997c4ba6` returned **PASS**.
- The complete chain is integrated through
  `efd8e89967ad90e7ea30dddd08864de5afadd4d1`. Composition exposed that H0's test
  incorrectly required the live post-FR-07 Gateway to remain byte-identical forever;
  reviewed compatibility commit `b7484482ac1305eb47d81be2787fc9a836683339` preserves the frozen
  accepted-v9 artifact while requiring the historical provider to refuse positive credit
  for evolved code. In a clean detached checkout with pinned Elixir 1.20.3 / OTP 29.0.5,
  bundled Exqlite headers and a canonical temporary root, integrated CI passed 590 tests,
  13 intentional skips and one optional exclusion. Provenance SHA-256:
  `76b45e0e364464e52919012acdf955b46516473163e15bebfeb1bcd4fa0be0dd`.
  No daemon, provider, credential, deployment or activation was used. FR-19B remains open.

## FR-08A protected authority and combined integration — 2026-09-20

- The initial protected-primitives candidates passed broad component suites but repeated
  Astra-high hostile review exposed loaded-code binding, epoch/control ordering, semantic
  launch identity, recursive ledger closure, receipt provenance, migration, dual-authority,
  rejection atomicity and recovery-provenance defects. Every blocker record and correction
  remains routed under `foundry/docs/fr-08/`; green test totals were never treated as a
  substitute for closing the reproduced invariant.
- Final branch correction `f9e35b42d2eb768f4407543ac0f84e2758409ab4`, gate binding
  `3ccbbc3639ae31cbb76daa08254523ecefe63aa7` and evidence
  `f2e4a9110d46bee19f3438e74e467335c60e677f` enforce typed command/result replay,
  contiguous revisions and exact singular/plural carrier schemas without recursively
  interpreting opaque payload data. Focused Astra-medium review
  `5851c9be9b6d0cfb7f3fad5d41e06fa139b852bd` returned **PASS** after maintained 57,
  prior 39 and 98 fresh carrier cases.
- A read-only merge inventory showed no textual conflict with accepted FR-19A but correctly
  invalidated revision-bound evidence. The reviewed branch was therefore combined with
  current main in explicit merge `1d0b128ff7c78bf72577d23658e267d7508e4763`; cross-feature
  tests `240d16f6823a8b9118c4d2b52d305314c6a97203` and rebound evidence
  `b05f8342fbb83cb26a0fa157472bee15a020ad7e` produced frozen candidate
  `176dab44354b5bbdde5b488f44766849c9d8927d`.
- Fresh Astra-high combined review `a22753569254ca42773f04632ca42a72573c9a2e`
  returned **PASS**. It independently recreated the merge tree, verified every manifest
  and artifact, passed combined 6, focused 46, independent 11, prior 41/39/57/98 and
  isolated native-sync 2, reproduced the exact 7/7 source/BEAM-bound report and rejected
  altered loaded code. Clean canonical CI passed 612 tests, 13 intentional skips and one
  optional exclusion. The exact reviewed branch fast-forwarded main with no post-review
  source change. No provider, daemon, credential, activation or deployment was used.
- FR-08A is complete. FR-08B and FR-18A are ready; FR-15aB still waits for FR-08B. The
  protected verifier is not a second workflow reducer, and completion does not claim live
  execution, presentation, activation or FR-22 acceptance.

## FR-08A atomic-composition handoff correction — 2026-09-20

- FR-08B implementation stopped before editing at base
  `d0059b03757a73085f430895304244afaec79ce2`. Source inspection showed that ordinary
  `Gateway.transact/4` commits domain records with no protected operations, while
  `Gateway.protected_command/4` executes one protected operation in a separate
  transaction and the legacy combined route refuses root-authority stores. Sequential
  calls cannot satisfy the workflow contract's atomic R4a/R5 settlement and restart
  obligations.
- A fresh read-only Astra-high diagnosis confirmed the contradiction and bounded the
  correction. [Its durable record](fr-08/atomic-composition-diagnosis.md) requires a
  versioned bundle through the one Gateway transaction, fixed non-committing protected
  operations, global command idempotency, complete prestate CAS, typed ordered history,
  v1 replay compatibility, validated domain/protected linkage and a protected
  once-per-non-start infrastructure settlement fact. FR-08B retains the role reducer and
  every-ingress migration; no acceptance obligation is waived.
- Active owner: Sol-medium `fr08a_atomic_bundle_impl`, isolated from the concurrent
  FR-18A observation slice. The correction requires a fresh Astra-high authority,
  persistence and replay review before integration. The historical FR-08A PASS remains
  valid only for its exact candidate and does not prove this new handoff surface.
- First frozen candidate `9a8a4912bcc86d1f58b50a65f9cc148982ac3915`, tree
  `325652033c56f582ea3102650770dd5a73b3c0bb`, added the one-transaction bundle route,
  typed operation journal, v1 backfill and infrastructure settlement record. Fresh
  Astra-high review `d1700a853e286428c315d9a26040c86a048cead8` returned **BLOCKER**:
  hostile probes reproduced cross-envelope rejected-operation reuse, non-durable early
  rejection, settlement/history mutation surviving reopen, partial migration acceptance,
  truncated/substituted v2 outcomes, missing bundle-prestate CAS and broken duplicate
  receipt settlement recovery. Independent probes passed 22/35; the affected suite
  passed 173/176. The exact-base ENOSPC fixture passed while the candidate fixture
  returned zero-frame success, so that difference remains an explicit diagnosis item.
  The original implementer owns the bounded B1–B7 correction; nothing is integrated.
- Runtime corrections `940ccfb3efbcfb533ebeec0f46d67c1f83d3681f`,
  `0cadb1f1c936304240c0b053503c45156c53f4e4` and
  `67a2b923ef58f98290457f4640561bc5d44f9db8` close the seven original blocker groups,
  copied settlement provenance/shape and mandatory non-start carrier presence. Evidence
  commit `721a9e86ed51b776785a7260890b39f894fc1c5a` binds the final corrected source.
  Astra-medium rereview PASS `bae065ba183833b3fb30c6f3c6326c00e49a1039`
  verified the final B3/B5 boundary after earlier blocker records were preserved.
- The ENOSPC discrepancy was traced to the new typed history crossing SQLite's default
  1,000-frame auto-checkpoint threshold, not a checkpoint implementation regression.
  The owned physical fixture now disables auto-checkpoint only for the test, asserts a
  nonempty wholly uncheckpointed WAL using `wal_checkpoint(NOOP)`, then proves physical
  ENOSPC. Production WAL behavior is unchanged.
- Current-main documentation and the exact reviewed branch were merged at
  `f3ef50340548fa1c430f922a0913f132bae9786f`. Runtime/test paths are byte-identical to
  the reviewed candidate. Exact clean integrated CI on pinned Elixir 1.20.3 / OTP 29.0.5
  passed 625 tests with 13 intentional skips and one optional exclusion; provenance is
  `/private/tmp/fr08a-atomic-integrated-ci-f3ef503/provenance.json`, tree
  `3c36362dc9d4b6a49bbd6fa8b0d41f20832dfa86`. Documentation passed 80/80. FR-08B is
  dependency-ready and FR-18A may now add its separately designed bounded read query.
  No provider, daemon, activation or deployment ran.

## FR-08B pure kernel and root-fact composition — 2026-09-20

- First pure-kernel candidate `a00deccbf4717ed6c3e4835bbdefed457dd6d637`, tree
  `21ec8b3c1cc64c490b325506682754bfa2cd7db5`, added only new workflow kernel/state/test
  files and passed 17 maintained tests. Fresh Sol-high review
  `a8ecf36b7032572ceba27c139c06c5f17d10a604` returned **BLOCKER**: generic snapshot
  replay was unguarded and non-total; closure/check/review/correction custody was lossy;
  R4a ignored control/allocation/generation cross-products; and the label matrix did not
  execute the 28 required rows.
- The review also exposed that the integrated atomic Gateway cannot bind protected facts
  derived during staging into its precomputed domain proposal. Fresh Astra-high diagnosis
  [`fr08b-root-fact-composition-diagnosis.md`](fr-08/fr08b-root-fact-composition-diagnosis.md)
  confirms this is a bounded FR-08A interface correction: a closed versioned transition
  plan with fixed typed result slots and finite kernel-authored alternatives selected by
  root-derived discriminants. Gateway performs only mechanical validated selection and
  substitution; it does not execute candidate code or become a lifecycle reducer.
- The FR-08B owner is correcting the pure semantic event/state/plan contract and exhaustive
  matrices without touching durable core. The protected-result/domain-plan binding must be
  implemented and critically reviewed after the active FR-18A protected read slice releases
  core ownership. No FR-08B runtime or adapter code is integrated.

## FR-18A minimal honest observations — 2026-09-20

- Sol-medium source candidate `fa74cabb7ce8c4d12cf94e756c92b7310733192a`, tree
  `6228757bd34a1d639ebb693413dd45b43d50fc0c`, adds only a typed observation surface,
  DTOs, a protected-Gateway adapter and tests. Candidate evidence commit
  `8f266ea087791345f1318785e80fa2f754a15b00` records 22 focused passes, exact-source
  pinned CI with 619 passes, 13 intentional skips and one optional exclusion, and an
  80/80 documentation gate. It changes no Coordinator, reducer or protected writer.
- Fresh Sol-high review `84848a1b13278d052ee590705a12fb384abbd5c6` returned
  **BLOCKER**. Hostile probes reproduced corrupt authority collapse to unavailable,
  contradictory unknown-to-success effect reporting, secret-shaped identity leakage,
  canonical quality on malformed versions and post-materialization limits that do not
  bound the protected query. It also found a protected pointer-vocabulary mismatch.
- The original implementer is correcting the disjoint observation defects. The bounded
  protected effect query is deliberately serialized behind the active FR-08A atomic
  bundle writer because both require the same Gateway/protected-core files. FR-18A is not
  complete, and its green component/full-suite counts do not override the hostile review.
- Observation-layer correction `ff6613cb81ac335d425ef460edc8994bc29448c4` and final
  Sol-high rereview `e10c57b115f2c8b9a8aab2d04d3e5da1fa8cc330` pass corrupt-versus-
  unavailable classification, terminal reconciliation, whole-envelope redaction,
  malformed-version quality and protected pointer vocabulary. Focused checks passed 28;
  B5 remains explicitly unreviewed and blocking.
- Branch `origin/repair/fr18a-honest-observations` preserves the complete candidate and
  review chain. Documentation-only commit `3bc217e70ff3df359f9a68672e10f53bc9a3dfe7`
  records the future bounded exact-effect query: typed SQL-level item/byte caps, stable
  source-bound cursors, explicit truncation/unknown/error semantics and acceptance tests.
  It changes no runtime. Implementation waits for the FR-08A protected-core correction
  to pass and integrate, avoiding concurrent ownership of `ProtectedPrimitives`.

## FR-18A bounded effect query B5 correction integrated — 2026-09-20

- The B5a-B5d correction `98b6ef9fe4236d4741d54888845f64049d8ba738` and its rebound
  FR-08A evidence `aa173780365d732e1b6fe8ea07b86ca9348c863e` were frozen as candidate
  `f3f038809262963e5f26e1b2dd127bc89c6bd3c9`, tree
  `490cb434b3110b2eee987b7e3bbf57c6eb8d0c9e`.
- Independent narrow rereview `2f5a30817febc490eed3156c37ffdf80cabf86a6` returned
  **PASS** for all four blockers. Reviewer identity: Claude Opus 5, fresh session,
  separate from the implementer; recorded as the evidence identity actually used.
  [Its durable record](fr-18a/b5-correction-rereview.md) verified rather than accepted
  the diff: the new control/execution summaries never reach the legacy unbounded
  materializers and are charged to the byte budget by `effect_observation_size/3` before
  section reads; the closed `active|cancel_requested` vocabulary is enforced at the write
  boundary, so no healthy store can present a control value the reader calls corrupt;
  the reconciliation path admits only a durably quarantined conflicting receipt, and a
  duplicate non-start is refused before reaching that state; and the settlement binding
  is three-way across settlement row, authoritative effect/receipt scalars and the
  accepted operation record, verified from the authoritative side as well as the
  settlement side.
- Evidence: 23 independent [rereview probes](fr-18a/b5-correction-rereview-probes.exs)
  at seed 20926, of which 10 were authored by the reviewer; 42 maintained focused tests
  at seed 20927; 26 corrected B5 review probes at seed 18055; canonical CI at the frozen
  candidate with six stages passed and an empty dirty set; documentation gate 80/80.
- **Recorded gap, outstanding before FR-18A completion:**
  `bounded_execution_summary/1` enumerates four statuses, but the `exit` and
  `sealed_without_result_or_exit` branches have no executable coverage against a real
  store, and `sealed_without_result_or_exit` does not appear in `test/` at all. Those
  branches carry sequence-range validation whose failure would misreport terminal
  execution state. This is a coverage gap, not a reproduced defect, and did not block
  integrating the correction.
- Current-main documentation and the exact reviewed branch merged at
  `850489ca5fccaeafe5128fbf6500f5962c3e5e6c`. Runtime, test, CI-runner and lockfile paths
  are byte-identical to the reviewed candidate; only documentation differs. Exact clean
  integrated CI on pinned Elixir 1.20.3 / OTP 29.0.5 passed all six stages at tree
  `fa056dab9ccce5f1e63c46ddd3dc3736c2cfb2a3`; provenance is `/private/tmp/claude-501/-Users-raymondluong-dev-pramana/3cec5694-5089-47fb-a6c1-b782b0717815/scratchpad/ci-artifacts-integrated/provenance.json`. Documentation passed 80/80.
- Integration releases the `ProtectedPrimitives` ownership that the FR-08A
  protected-result/domain-plan binding correction was waiting on. FR-18A is not complete,
  and this integration claims no producer, board, activation, provider execution or
  FR-22 acceptance.

## FR-18A execution summary coverage gap closed — 2026-09-20

- The gap recorded by the B5 correction rereview is closed at
  `cb136fa`. `bounded_execution_summary/1` enumerates four statuses; against a real store
  only `result` and `absent` were covered, and `sealed_without_result_or_exit` appeared
  nowhere in `test/`. Three real-store cases now drive `append_inbox` and `seal_inbox`
  through the public protected command path to reach `open`, `exit` and
  `sealed_without_result_or_exit`, asserting the sealed sequence and the presence or
  absence of the accepted item sequence.
- All three pass against the unchanged implementation, so the gap closed without
  exposing a defect. The commit touches no runtime file. Observations suite 20 passed at
  seed 20930; full model-free suite 649 passed, 13 skipped and one optional exclusion at
  seed 0.
- **Operational finding for anyone running these checks.** The physical fault tests
  (`SyncFaultTest`, `OperationalStorageTest` ENOSPC/xSync/checkpoint cases) are not safe
  to run concurrently with another suite run on the same machine. Two concurrent runs
  produced two spurious failures each; both runs passed when rerun serially with nothing
  else running. Candidate and integration evidence must therefore come from a serial run.
- This closes one recorded obligation. FR-18A's other completion obligations are
  unchanged, and no producer, board, activation, provider execution or FR-22 acceptance
  is claimed.

## FR-08A protected-result/domain-plan binding, partial candidate — 2026-09-20

- The root-fact composition diagnosis assigns this interface correction to FR-08A.
  [Its implementation specification](fr-08/plan-binding-specification.md) records the
  confirmed defect at base `3f06a5a` with exact source lines: `commit_accepted_atomic_bundle/6`
  binds `proposal = envelope["proposal"]` and commits it unchanged, while
  `operation_results` — already carrying the authoritative settlement and its ordinal —
  reaches the durable record but never the domain proposal.
- Three attributable subcommits are complete. `24b8431` adds the trusted
  `DurableStore.TransitionPlan` codec: closed schema validation, discriminator selection,
  slot-enforced substitution and post-normalization carrier agreement. `aa0debe` adds
  `derive_outputs/2`, which resolves each binding against the staged protected result at
  its declared ordinal and projects facts into fixed shapes. `d1b190d` adds
  `ProtectedPrimitives.infrastructure_discriminator/3` and, with it, the first evaluation
  of `infrastructure_attempt_limits` anywhere in `lib/`.
- The codec deliberately does not depend on `Workflow.Kernel.Plan`. It also enforces the
  declared destination slot, which the candidate-side copy does not: a bound fact may
  occupy only the declared payload field of one event of the declared type, that event's
  embedded projection transition value, and the paired projection's value.
- **Subcommits 0, 4 and 5 are outstanding.** There is no Gateway wiring, no existing path
  changes behavior, and a bound lifecycle transition cannot commit. Subcommit 0 is a
  versioned durable event vocabulary extension, blocked on a decision belonging with the
  FR-08B kernel contract; subcommits 4 and 5 depend on it.
- Independent critical review by Claude Fable 5.1, fresh session, separate from the
  implementer; recorded as the evidence identity actually used. It returned **BLOCKER**
  twice before passing.
  - First: `bind/3` raised `KeyError` instead of rejecting a marker naming an undeclared
    binding, which the specification required and the implementation omitted. Corrected
    at `ce9b4a1` by `every_marker_is_declared/2`.
  - Second: that correction was incomplete. `marker_names/1` filtered on `is_binary`, so a
    marker named by an integer, `nil` or a list still reached `substitute/2` and raised.
    All three shapes were reproduced. Corrected at `1952ff4` by collecting names
    regardless of type.
  - **PASS** at `1952ff4`, after the reviewer re-ran its own reproductions and seven
    further marker shapes, including a marker-shaped value nested inside an authoritative
    output, which the pre-existing shape gate refuses.
- The review also established that `bind/3`'s output-kind check is a **shape gate, not a
  provenance gate**: a well-shaped but entirely fabricated settlement passes it. This is
  unexploitable at this candidate, which cannot commit anything, and is recorded as a
  binding requirement on subcommit 4 rather than deferred to discovery.
- Two operational findings. The revision-bound FR-08A attestation pins the source SHA-256
  and loaded BEAM MD5 of `protected_primitives.ex`, so adding one function there broke the
  frozen artifact and reported `ready=false`; the full suite at candidate freeze caught
  what focused runs did not, and `c7673b4` rebinds it. Separately, a build directory used
  for `mix run` and later reused for a full `mix test` produces stale-artifact failures in
  unrelated modules; this is distinct from the concurrency effect recorded above, and both
  were reproduced. Use a fresh `MIX_BUILD_PATH` for each full-suite validation run.
- Exact clean CI at each frozen revision on pinned Elixir 1.20.3 / OTP 29.0.5, run
  serially; full model-free suite 701 passed, 13 skipped and one optional exclusion at
  seed 0. No provider, daemon, credential, activation or deployment was used.
- Current-main documentation and the exact reviewed branch merged at
  `3de546c9d6bdafc9c6ec1f97983b794d48da1cb2`. Runtime, test, CI-runner and lockfile paths
  are byte-identical to reviewed candidate `1952ff4`; only documentation differs. Exact
  clean integrated CI, run serially, passed all six stages at tree
  `5c2c42e03c9257e78c4e99d40373ff998fdd8c2e`. Integration adds no caller: both new symbols
  remain unreferenced by production code, so no existing behavior changes.

## FR-08A durable event vocabulary, subcommit 0 — 2026-09-20

- The blocking prerequisite recorded against the binding correction is resolved. The
  [design](fr-08/event-vocabulary-design.md) required two revisions: revision 1 proposed
  versioning the durable event record and was returned **BLOCKER** because
  `events.schema_version` carries `CHECK (schema_version = 1)` on a STRICT table,
  `insert_events/3` writes that version as a SQL literal, and relaxing the CHECK without
  fixing the literal would have written a column and blob that disagree — a new way to
  manufacture the partial version state the repair exists to eliminate.
- Revision 2 replaced the mechanism outright. The constrained column was never the one
  that needed to change: `event_type` carries no CHECK, and within the durable store the
  vocabulary is enforced in exactly one place. Extending it needs no schema change, no
  migration and no version dispatch. Two disjoint vocabularies now share one flat
  namespace, so a name identifies exactly one contract and no stored record can disagree
  with its own type.
- Implementation `7fc5c46` seeds the lifecycle set with exactly the ten event types the
  transition-plan destination slots require, so every name is justified by a concrete
  binding; FR-08B adds the remainder. Disjointness is enforced at compile time, verified
  non-vacuous by introducing a collision and confirming the build fails.
- Evidence commit `a68fa8a` rebinds the FR-08A attestation, because `record_codec.ex` is
  pinned by source SHA-256 and loaded BEAM MD5. This was the second such break in one
  session and is the evidence behind FR-23's same-commit rebinding requirement.
- Independent review by Claude Fable 5.1 returned **PASS**, having re-derived every claim
  rather than accepting the summary: it broke the compile-time guard on purpose and
  reverted it, recomputed the pinned hash independently, and confirmed the recovered test
  coverage was intact after a bad bulk edit was restored from git. It also established a
  precision point now recorded in the test itself — the backup reconstruction is agnostic
  to the event type string, so the reconstruction assertions alone do not prove the name
  survived storage; the `recent_events` assertions are what establish that.
- **FR-08A is reopened, not complete.** Its row was marked complete before the binding
  correction reopened it. Subcommits 4 and 5, Gateway wiring and replay revalidation,
  remain outstanding, and subcommit 4 is additionally bound by its recorded structural
  provenance requirement.

## FR-08A transition plan codec R4a coverage — 2026-09-20

- A deliberately broad independent design review, asked to judge the FR-08B kernel design
  in context with the rest of Foundry rather than on its own terms, found two defects in
  the already-integrated FR-08A transition-plan codec. `launch_authority_v1` had **no
  producer**, so all five `.authority` slots were declarable but unbindable and R4's
  ordinary admission row was unreachable through the binding. `@slots` defined no
  `review_settled` and no check-worker settlement, so two of R4a's four domain-owner rows
  had no destination at all.
- **Both defects were in code that had already passed two independent reviews.** Each
  examined the codec's mechanism — authority, slot enforcement, fail-closed derivation —
  and each was correct on those terms. Neither was asked whether the mechanism covered
  R4a, so neither looked. That evidence produced the contract-coverage review requirement
  now recorded in [the repair plan](REPAIR-PLAN.md).
- `71e558b` adds the producer as `{"issue_claim", "effect"}`. `issue_claim` returns the
  authoritative issued effect, which carries every field the kind needs; the projection
  renames `assignment_id` to `work_owner` and `phase_generation` to
  `infrastructure_generation`. Reservation and ledger identities are deliberately
  excluded, because no single operation's facts carry them authoritatively and binding
  them would mean copying caller-supplied data on trust. It also adds `check_settled` and
  `review_settled` and their slots.
- `43ee08e` resolves the remainder of R4a's fourth domain-owner row three different ways
  after review asked for one sentence of reasoning. freeze/import is **subsumed by
  check**, because R5 states each freeze/import/mandatory-check worker charges
  `starts.check` and R4's freeze-failure row routes to a bounded `starts.check` retry.
  **build was a genuine gap**, not a documentation request: R5 gives it a distinct
  `starts.build` dimension, so `build_planned`/`build_settled` and their slots were added.
  activation gets no slot, being accounted as `operations.activation` rather than a start,
  with FR-17 owning immutable activation. The reasoning sits beside the slot table so it
  is not reconstructed later.
- The coverage assertions whose absence let this through are now maintained tests: every
  R4a domain owner must have a settlement slot, and every declared admission slot must
  actually derive an authority fact rather than merely naming a kind. They enumerate six
  owners, so a future missing slot fails a test rather than waiting for a reviewer.
- Independent review by Claude Fable 5.1 returned **PASS**, having traced `issue_claim`
  through `public_effect/1` to confirm every projected field is genuinely present in the
  authoritative record rather than invented, and confirmed the new assertions are real
  coverage rather than mechanism tests relabelled.
- Evidence commits `7b7c590` and `aae4424` rebind the FR-08A attestation, third and
  fourth rebinds of the session. Integrated at `b4044e3` with runtime byte-identical to
  the reviewed candidate; exact clean CI passed all six stages, and the full model-free
  suite passed 711 at seed 0 run serially.

## FR-08A Gateway plan resolution, subcommit 4 — 2026-09-20

- This is the change the whole binding correction exists for. Before it,
  `commit_accepted_atomic_bundle/6` bound `envelope["proposal"]` and committed it
  unchanged, so no protected fact derived inside the transaction could reach the domain.
- `9f1115d` makes a v2 envelope carry **either** a precomputed proposal **or** an
  unresolved transition plan, never both and never neither, and resolves a plan after
  staging and before commit: the protected layer derives the discriminator from the
  settlement staged in that same transaction, and the codec mechanically selects the
  matching alternative and substitutes. Proposal-bearing envelopes and stored histories
  are untouched.
- Three protocol decisions were recorded before implementation rather than discovered
  during it. The semantic digest covers the **unresolved** plan, because digesting the
  resolved proposal would make one command digest differently depending on which
  alternative the discriminator selected, so an idempotent retry after a lost reply could
  not find its original result. `discriminator_kind` is a closed vocabulary, so Gateway
  maps a name to one fixed protected function rather than dispatching on caller text.
  And `bind/3` takes the staged results rather than a pre-derived outputs map, so
  provenance is structural: a caller cannot supply a forged fact because the interface
  offers nowhere to put one.
- Independent critical review by Claude Fable 5.1 returned **BLOCKER** before passing,
  and both defects were reproduced against a real store.
  - A plan-binding failure crashed the **entire Gateway into permanent recovery mode**.
    The else clause recognised three error reasons, so every error the new resolution
    path could raise fell through the catch-all, was mapped to `storage_unavailable`, and
    made `transition_after_result/2` reject every subsequent call from every actor.
    Reachable by ordinary input, and nothing was persisted, so a lost reply for that
    command could never be found again. Corrected by tagging plan failures
    `{:plan_rejected, reason}`, which also covers error atoms neither test suite listed.
  - The selected discriminator was discarded and never persisted, which the specification
    required. It is not recoverable afterwards from the policy head row, so it is now
    recorded in the durable result.
  - A smaller defect: the persisted domain row always wrote the `proposal` key, recording
    `nil` for a plan-bearing bundle that had just committed one. The stored request is now
    keyed by the envelope's real carrier, and the protected validator delegates to
    Gateway's own shape function rather than mirroring it — a hand-copied rule would have
    diverged silently the moment a third carrier appeared.
- Review also found two tests that did not establish what their names claimed: the commit
  test read only the protected table, written before binding, and no test exercised a
  non-first alternative. Both corrected, plus an end-to-end exhausted-branch test.
- Integrated at `b9bfc85` with runtime byte-identical to the reviewed candidate; exact
  clean CI passed all six stages, run serially. Nine attestation rebinds were required
  across the session because `gateway.ex`, `protected_primitives.ex` and `record_codec.ex`
  are all pinned by source SHA-256 and loaded BEAM MD5; that repetition is the evidence
  behind FR-23's same-commit rebinding requirement.


## FR-08A plan replay revalidation, subcommit 5 — 2026-09-20

- This entry was missing when FR-08B resumed: the code landed on `main` and the ticket
  rows still said replay revalidation was outstanding. Recorded now from the commits and
  the attestation rather than from memory, and the rows are corrected in the same commit.
- Subcommit 4 resolved a plan and committed the result but never revalidated it
  afterwards. [The design](fr-08/plan-replay-revalidation-design.md) closes that on every
  path that validates protected authority — in-transaction, on reopen and during verified
  backup — by **re-running the binding** rather than inspecting fields. `b5d19e9`
  re-decodes the original plan from the canonical envelope, re-derives outputs from the
  persisted `durable_operations` rows through the commit path's own `derive_outputs/2`,
  re-runs `TransitionPlan.bind/3`, and requires the result to equal the committed carriers
  exactly. That subsumes field comparison instead of enumerating checks that need
  extending whenever a slot is added, and it reuses the commit path's code so the two
  cannot drift. Non-vacuity was verified rather than assumed: neutralising
  `valid_plan_binding?/4` makes the corruption test fail.
- Independent review returned **BLOCKER** on two defects, both reproduced by the reviewer
  and both verified against source before correction at `e491e41`.
  - Revalidation **trusted the recorded discriminator**, and the stated reason for trusting
    it was false. The claim was that `infrastructure_discriminator/3` reads the current
    policy head row and fails closed after a revision, so recomputation would turn a valid
    historical commit into a corruption report. But `root_policy_history` retains every
    revision under `PRIMARY KEY(policy_id, revision)` with a chain constraint validated on
    open, so the limit in force at the effect's recorded `policy_revision` is recoverable
    and integrity-checked. Because the recorded value was the only free input and nothing
    reconstructed it, a **coherently tampered store revalidated as valid**: flip the
    discriminator, regenerate the events from the trusted binder's own other alternative,
    set the projection to match, and reopen accepted a domain state the policy in force
    never authorized. `infrastructure_discriminator_at_revision/3` now reconstructs from
    history and revalidation requires equality; the policy-revision safety test still
    passes, because a history lookup does not depend on the head row.
  - The plan/operation coherence check added at `8379ba1` had **silently disabled half the
    codec**. `TransitionPlan` could not declare `issue_claim`, which `@producers` names as
    the sole producer of `launch_authority_v1`, so once declared-equals-staged became
    load-bearing no plan could bind any of the six admission slots. It also declared
    `consume_validation`, which is not a protected operation at all. Both vocabularies are
    corrected and two tests now enforce agreement in both directions.
- Review also replaced a test that did not establish what its name claimed: the
  discriminator-mutation test mutated `command_results` rather than `atomic_bundles`, so
  it never touched the recorded discriminator and was caught by unrelated domain-result
  validation. The replacement performs the coherent tamper above.
- Why comparing events suffices is now recorded in the code: `Authority`'s
  `projection_matches_event` and `validate_reconstruction` run ahead of this check in the
  same read, so pinning events pins projections transitively. If that order ever changed,
  a projection comparison would be required here.
- Evidence `81e71a6` and `a32ebbd` rebind the FR-08A attestation, the ninth rebind of the
  session; `a32ebbd` commits a rebind that had been left in the working tree. The report at
  `foundry/docs/fr-08/fr08a-protected-report.txt` is bound to subject revision `e491e41`
  and reports `ready=true`, 7 mandatory capabilities passed, 0 failed, 0 unavailable.
- Suites at freeze: 56 transition plan tests at seed 20991; 37 atomic bundle tests at seed
  20990; full model-free suite 733 passed, 13 skipped and 1 excluded at seed 0, run
  serially.
- **FR-08A is complete.** Every subcommit of the binding correction that reopened it is
  integrated and independently reviewed. FR-08B's dependency is satisfied, which discharges
  the B4 blocker of the pure-kernel review; B1, B2 and B3 remain outstanding.


## FR-08B kernel, subcommit 1 corrections — 2026-09-20

- Independent review of `be1e19c` returned **BLOCK** with eight blocking findings, recorded
  in full at [the review findings](fr-08/fr08b-subcommit1-review-findings.md). Four were
  confirmed by the implementer by direct reading before the verdict was accepted.
- **The finding that mattered most was about the evidence, not the kernel.** The property
  suite's `@known_unreached` recorded three integration rows as unreached and justified it
  as a depth limit behind a `review_recorded:approved` → `reviewer_closed` sequence firing
  "about once across every walk". Measured on the suite's exact configuration, that
  sequence fires **zero** times and no walk reaches `ready_to_integrate`. Worse, all nine
  attempts that reached `review_planned` got there only because `check_recorded:passed`
  could overwrite a non-passed check, and `check_settled` permanently poisoned the attempt
  — two defects cancelling each other where a type-level ratchet could not see them. The
  briefing had asked the reviewer to test that claim precisely because every previous
  investigation of it had found a real defect. It did again.
- Sorting the nineteen findings gave **two abstraction defects**, not nineteen patches, and
  six of the guard corrections could not be written until they landed.
  - Executions were addressed through the active-attempt pointer, so every execution became
    permanently unreachable the instant `attempt_settled` cleared it — while R4 orders
    closure *after* settlement in four rows and R4a's restart sentence requires
    reconstructing "no live execution". Every integrated ticket reported a live execution
    forever. An execution now belongs to the attempt that created it. Two guards fell out
    of the same correction: `developer_closed` no longer requires a frozen candidate, which
    made R4's rows 8 and 9 unexpressible, and the terminal-ticket refusal narrows from all
    events to transitions, because recording a termination preserves a terminal fact.
  - The infrastructure ordinal was one counter per ticket where R4a sets
    `launch_non_start_limit` "per role and work owner", so a reviewer non-start spent the
    developer's allowance and the PM limit was unrepresentable. **This was subcommit 2's
    real blocker**: `decide/3` cannot evaluate "below the infrastructure limit" for a role
    whose consumption it cannot see, so subcommit 2 was gated on a state shape that could
    not answer its own central question.
- `attempt_settled` guarded only the `integrated` disposition, leaving eight of nine
  reachable from any phase. Each now has its R4 source row, and `timed_out` is confined to
  the developing row because R4's reviewer crash/timeout row says "Preserve candidate,
  close reviewer then bounded new reviewer execution" — it must not terminalise, and it
  did. `cancellation_finalized` never tested the condition stated in its own row, so
  `after_integration` produced an integrated ticket with no attempt, candidate, check,
  review or ref receipt: blocker B1's headline counterexample, reachable in three events.
- Two corrections of `202b8e4` had applied a right principle to one sibling and not the
  other — write-once to verdicts but not checks, execution binding to `reviewer_closed` but
  not `review_settled`. Both are now rules over the vocabulary rather than guards attached
  to whichever event a walk happened to reach.
- **The prober's own defects are corrected here**, because they are why six blockers were
  invisible. It admits a successor ticket, so deep walks no longer die with their single
  ticket — twenty of twenty-five ended cancelled — and idle hundreds of steps. It proposes
  every variant R4 names rather than a hand-picked subset. And it derives a park's resume
  target from R4 rather than from the ticket's current phase, which was the confirmed
  circularity: both sides had moved until they agreed on a blocked ticket with no reason
  and no resume target, a state R4's resume row forbids.
- `@known_unreached` is now **empty**; every declared type is reachable. A second,
  variant-level ratchet covers what a type-level one marked covered on its first variant,
  which is exactly where two blockers lived. Its single entry is **proved rather than
  asserted**: a table test drives R4's second cancel branch end to end in sixteen events,
  so the row is satisfiable and only the seeded ordering misses it. That is the standard
  the previous ratchet failed.
- Two properties that did not establish what their names claimed are corrected: the
  sequence property tested the walker's own counter, and the restart property cited an R4a
  sentence it did not test. Both now test the kernel, and a per-role allowance property was
  added for the ordinal correction.
- Every new guard was verified non-vacuous by neutralising it and confirming exactly the
  intended tests fail, then reversing the exact string rather than by `git checkout`.
- Recorded for subcommit 2: `ticket_resumed` collides with `RecordCodec`'s **legacy**
  vocabulary, and the codec raises at compile time when the two vocabularies share a name.
  It is the only collision among the 22 and it blocks the codec extension.
- The question of supporting other workflows was raised during this work and is analysed
  at [the mechanism/definition seam](fr-08/workflow-definition-seam.md). It is deliberately
  not scheduled. One step *is* scheduled inside Batch C on its own correctness merits:
  make R4's rows executable data and drive the prober from that table, so two
  hand-maintained encodings can no longer be tuned against each other.
- Suites at freeze: kernel 42 table tests and 13 properties, 55 at seed 0; full model-free
  suite **791 passed, 13 skipped at seed 0**, run serially with a fresh `MIX_BUILD_PATH`.
  That is the prior 776 plus the 15 tests added. `foundry/bin/preflight.sh` passes.


## FR-08B kernel, vocabulary collision resolved — 2026-09-20

- `ticket_resumed`, one of the kernel's 36 event types, is a member of
  `RecordCodec.@legacy_event_types`, where it is a record type carrying a projection
  payload. The codec raises a `CompileError` when the legacy and lifecycle vocabularies
  share a name, so subcommit 2's codec extension could not have compiled.
- **The collision was already recorded, and the mechanism already decided.**
  [The vocabulary design](fr-08/event-vocabulary-design.md) called it at FR-08A subcommit 0:
  "The legacy and lifecycle sets currently collide on one name, `ticket_resumed`. The
  lifecycle event takes a distinct name instead. Which name is FR-08B's call." The FR-08B
  enumeration then reintroduced the legacy name while asserting every one of its 36 types
  was justified by an R4 row. An earlier note in this repair described the collision as
  previously unrecorded; that was wrong, and the correction is recorded rather than quietly
  fixed, because the failure is a regression against a settled decision rather than a
  discovery.
- The lifecycle event is now **`ticket_unblocked`**. R4's resume row ends "explicit operator
  blocks require steering, not automatic **unblocking**", so this is the contract's own
  word. It is also more accurate than a decorated `resumed`: the source phase is always
  `blocked` however the ticket got there — a PM park, `blocked(check_infrastructure)`,
  `blocked(draining)` — so a name pairing it with `ticket_parked` would claim it only undoes
  a park. The asymmetry is the state machine's; parking is one of several ways into
  `blocked` and this is the only way out.
- Verified mechanically rather than by inspection: extending the codec's lifecycle
  vocabulary by the kernel's remaining 22 types now produces no shared name, and no durable
  lifecycle type is missing from the kernel.
- Two maintained assertions added, in both directions, so the next collision fails a test
  rather than a later build. Non-vacuity checked by restoring the legacy name, confirming
  exactly one test failed with the colliding name in its message, then reversing the exact
  string.
- Kernel suites: 44 table tests, 13 properties at seed 0.


## FR-08B kernel, subcommit 1 — the method changed — 2026-09-20

- The correction at `40ac559` was independently reviewed and returned **BLOCK**, the second
  block on this subcommit. The verdict's own summary is the important part: "the correction
  fixed the eight counterexamples. It did not fix the rows." Four of the eight blockers were
  answered by guards that refused the reported sequence while the row stayed unexpressible
  or its sibling stayed open.
- Two findings were about the implementer rather than the code, and are recorded as such.
  The first review's lesson was that a right principle had been applied to one sibling and
  not the other; the correction design claimed to have generalised the execution binding
  "as one rule over the vocabulary" and had applied it to `review_settled` alone, leaving
  four settlements able to close any execution they named — `build_settled` could close the
  developer's execution unsealed and let `checks_started` walk around the seal requirement.
  And the new variant ratchet's justification was false in the same way the old one had
  been: `cancellation_finalized:after_integration` was recorded as missed by ordering when
  it was unreachable by construction, because `admissible/1` — written in the same commit —
  drops a terminal ticket from the proposal set.
- **Two reviews, two blocks, one failure shape is evidence about the method.** Hand-writing
  one guard per event from a prose table has no step that asks whether a row can be driven,
  so a guard written to stop a counterexample and a guard derived from a row are
  indistinguishable by construction. Both times the gap was found by a reviewer reading
  prose against code, because that was the only mechanism capable of finding it: the table
  tests ask what the kernel accepts and the walks ask what the prober can reach, and
  neither asks what the contract requires.
- The third attempt therefore replaces the method. [The row-driven
  design](fr-08/fr08b-row-driven-coverage.md) records it. R4's transition table and R4a's
  domain-owner table are **parsed from the contract** and each row is driven through
  `Kernel.apply/2` with the outcome the contract states asserted; rows stating a
  prohibition assert the refusal too, since driving the happy path would pass while the
  kernel accepted every contradiction. The inventory holds only each row's verbatim
  from-state cell, so it cannot drift: the bijection is exact at 32 rows and fails if the
  contract gains, loses or edits one.
- Running it the first time found six undrivable rows — precisely what two reviews had been
  reporting in prose. Two more, `base_moved` and `reset`, had been marked unexpressible **by
  inspection** and drove on the first attempt. Two wrong calls in one hand-maintained list
  is the argument for the list being executable.
- Fixed with their rows driving them: every settlement bound to the execution of its own
  role; R4's integration row made atomic and exclusive, so once a ref receipt exists nothing
  further may be recorded, planned or settled; `attempt_settled(blocked)` requiring the
  blocked or partial result its row names; a retained attempt reused rather than orphaned;
  the reviewer crash row returning the attempt to `awaiting_review` with its candidate so a
  bounded new reviewer can launch; R4 rows 12 and 13 separated by the controller reason_code
  the contract makes load-bearing, so an infrastructure failure or timeout may be
  re-reserved and an assertion failure may not; `submission_rejected` recording a durable
  validation charge instead of accepting its event and changing nothing; and the R4a
  retained-attempt retry made launchable from the phase a resume actually lands in.
- Five clauses are recorded as **partial** rather than the rows being called driven or
  broken: the two R4a at-limit blocks and three "or exhausted" alternatives. All five turn
  on allocation, which is protected policy the kernel may not restate, so they need the R4a
  limit product — blocker B3, subcommit 2 — rather than vocabulary invented here. Widening
  `ticket_parked` to reach them would re-conflate R4's PM park row with R4a's infrastructure
  block, which is what narrowing it was for.
- The prober had the same custody defect it existed to detect: it could not propose closure
  for a settled attempt's executions and dropped terminal tickets from its proposals
  entirely, which is why R4's second cancel branch was unreachable. Both corrected, and the
  variant ratchet is now empty.
- Recorded boundary: a row driving here means the **reducer** can express it, not that the
  mechanism behind it works. `reset` drives while `reset_fact_v1` still has no producer.
- **The non-vacuity sweep found three of the six new guards untested**, and that is the most
  instructive result of this pass. Neutralising `require_running_developer`, the `exhausted`
  phase guard and the row-12/13 separation left all sixty tests green. The last is the
  sharpest: a scenario named `check_infrastructure_failed` existed, a commit message said
  the rows were "separated by the controller reason_code", and nothing in the scenario
  depended on `failed_check?/1` — it asserted the retry path and never asserted that a
  timeout is refused as correction evidence, which is the entire distinction between R4
  rows 12 and 13. A green suite and a true claim had come apart again, one level up from
  where the reviews had been finding it.
- The repair of that had the same defect one level up again: the edit adding the missing
  `exhausted` assertion was a string replacement that silently did not match, so a test was
  reported as added and did not exist. The second sweep caught it. Edits are now verified to
  have landed rather than assumed, and the first sweep's one `NO RESULT` was likewise an
  error in the probe — it matched a guard's definition line and renamed it, breaking the
  build rather than neutralising anything.
- All six guards are now confirmed non-vacuous, each turning exactly the intended test red,
  each reversed by exact string replacement rather than `git checkout`. The rule this leaves:
  no guard is described as working until a neutralisation has turned a test red.
- Suites: workflow 60 at seed 0 (3 coverage, 44 table, 13 properties); full model-free suite
  **796 passed, 13 skipped at seed 0**, serial, fresh `MIX_BUILD_PATH`, which is the prior
  791 plus exactly the tests added. `foundry/bin/preflight.sh` passes.


## FR-08B kernel, subcommit 1 — third review and the tools it forced — 2026-09-20

- The third independent review returned **BLOCK** on `4715c25`, with a judgement that
  mattered more than the verdict: the row-driven method is sound and should be kept, but it
  was not yet what its own design claimed. All nine findings are now closed.
- **The mechanism was half-built and the design note overstated it.** `R4Rows.outcome/1`
  was defined and called nowhere, so the harness pinned each row's *from-state* cell and
  nothing at all on the outcome side: edit a contract outcome from "Terminal rejected" to
  "Terminal integrated" and every test stayed green. The note's sentence "Nothing is
  duplicated, so nothing can drift" was true of the key and false of everything the key
  pointed at. Each scenario now cites its assertions verbatim from the outcome cell and a
  test checks those citations still exist; editing that cell now fails, naming the row, the
  citation and the new text. The bijection also compares lists rather than sets, because a
  duplicated from-cell with a contradictory outcome had collapsed into its twin.
- **The same-sibling pattern recurred twice more.** `apply_terminal_phase`'s `"blocked"`
  branch left the stale resume target that the branch directly below it had just been
  corrected to clear. And the settlement role binding, which the *previous* correction
  claimed to have generalised "as one rule over the vocabulary", had been applied to
  `review_settled` alone — `build_settled` could close the developer's execution unsealed
  and let `checks_started` walk around the seal requirement.
- Three R4 rows order a fresh developer after cleanup, in three phrasings of one rule, and
  none was a guard. R4 rows 12 and 13 were one row to this kernel, so a timed-out check
  terminalised an attempt row 13 says to preserve and its retry could never clear the old
  run. `submission_rejected` accepted its event and changed nothing. `base_moved` and
  `reset` had been recorded unexpressible **by inspection** and drove on first attempt —
  two wrong calls in one hand-maintained list, which is the argument for the list being
  executable.
- **R4a's infrastructure block was borrowing R4's PM park.** Narrowing `ticket_parked` to
  its own row broke the reviewer and worker at-limit clauses while the developer's kept
  working, because a developer non-start lands in `queued`, which the park accepts. The
  correction deferred the two that broke and kept the one that worked — incoherent, as the
  review said. `ticket_blocked` is now the block's own event and all three clauses drive.
  The durable extension is 23 types, not 22.

### The tools this produced, and what each found on its first run

Recorded because every one of them found something immediately, which says as much about
what was being asserted unchecked as it does about the tools.

- **Exhaustive bounded search.** Enumerates every reachable state — 22,180 at depth 7 in
  three seconds — so invariants are proved for the bound rather than sampled, and a
  violation returns its event sequence. First run produced a four-event counterexample to
  an invariant that was itself wrong (R4's cancel row legitimately holds phase while
  effects reconcile), then a five-event real defect introduced an hour earlier.
- **Dead-guard detection.** Compares refusals the search provokes against errors the module
  declares. Confirmed `require_reviewer_open` can never fire — it had been claimed in a
  commit message as a fix — and then found that the prober only ever proposed *cooperative*
  events, leaving every forged-reference guard unexercised. The prober now forges
  references; five such guards fire that never had.
- **Clause coverage.** The converse of citation: 54 clauses asserted, 59 not. The number was
  not knowable before and can only go down.
- **Guard mutation sweep.** Neutralises each guard at its call site and reports what no test
  notices.

### Two incidents, recorded rather than smoothed over

- **A mutation was committed.** `421c0b2` shipped `:ok <- :ok` in place of
  `require_cleanup_complete/1`, because `git add -A` ran while the sweep held the tree.
  Every check passed, since the suite was measuring the mutation. Restored by exact string
  and verified byte-identical to the last unmutated revision. The sweep now writes a
  sentinel and preflight fails while one exists, because a green preflight taken during a
  sweep is worse than no preflight.
- **The sweep's first two runs were themselves vacuous.** It reported all 66 guards as
  surviving, because this repository uses a custom formatter (`Result: N passed`) and the
  verdict matched ExUnit's default. A tool built to find vacuous evidence produced vacuous
  evidence. A second run mis-scoped its fast phase to include two full state searches,
  turning twenty minutes into three hours.
- The rule these leave: **no guard is described as working until a neutralisation has
  turned a test red**, and no tool's first result is trusted until a known-good input shows
  the expected colour.

## FR-08B kernel, subcommit 1 — the sweep was measuring less than it claimed — 2026-09-21

- Started from a supervisor correction, and that is the entry's point. A full mutation
  sweep reported **19 guards no test exercises**. The implementer explained the number away
  as a tooling artefact. The supervisor refused it, neutralised one guard by hand, and all
  five suites stayed green. The number was real. **A number being explained is not the same
  as a number being investigated**, and the explanation cost nothing to produce, which is
  exactly why it was wrong.
- Three causes. **Loose assertions**: `{:error, _}` is satisfied by any guard in a `with`
  chain, so neutralising the one a test is named for still matches via whichever guard
  refuses next. That was review one's finding 9, deferred as cosmetic; it was hiding most of
  the rest. **Guards shipped without tests**: fifteen, several arriving with the corrections
  that closed review three. **Guards that cannot fire**: four.
- Pinning the assertions immediately reclassified one. `r4_coverage_test.exs` cited R4's
  "failed candidate never goes to approval" and was being refused on the attempt phase, not
  by `require_checks_passed`. `maybe_finish_checks` only advances an attempt to
  `awaiting_review` once every check has passed, and no event can add or relabel a check
  afterwards, so the guard's question is answered before it runs. Its recorded reason was
  not imprecise but wrong: it said "deeper than the bound", and raising the depth does not
  reach it.
- **Then the tool turned out to be understating itself, and this is the larger finding.**
  Writing the review briefing — in the sentence asking a reviewer to check whether the
  sweep's granularity was honest — it became clear it was not. The sweep neutralised by
  **global** string replacement, so identical call-site text was mutated in every handler
  holding it and one red test anywhere cleared all of them. It printed "guard call sites:
  66". There are **108**. `require_active_attempt(ticket, payload["attempt_id"])` occurs
  twelve times, `require_attempt_phase(ticket, ~w(active))` five. **42 call sites had never
  been individually exercised.** Fourth time this one tool has produced evidence weaker than
  its own claim.
- Swept per occurrence, 37 of the 42 had no test. Thirty-five now do, as one row per site
  naming its fixture, event and exact atom; the fixture is always the state in which every
  guard *before* the target passes, which is the whole difficulty and the reason a shared
  `{:error, _}` hid the class for three reviews. The other two cannot fire.
- **Four of the states the table needed were searched for rather than built.** The sharpest
  is a ticket back in `developing` whose attempt has already frozen its candidate:
  `launch_settled` stores resume_phase `developing`, `artifact_frozen` advances the ticket
  to `awaiting_review` without clearing it, a block may then honestly name the stale stored
  target, and the unblock returns a candidate_frozen attempt to `developing`. Three such
  states at depth 7. The guards refuse it, so nothing is broken; whether `artifact_frozen`
  should clear the stale target is R4 semantics and was left for review rather than changed
  at freeze. Same defect shape already recorded for `apply_terminal_phase`'s blocked branch.
- **The reachability claims were resting on almost nothing, and the measurement is the
  finding.** `@unreachable` asks whether an atom ever fired in the bounded search, which
  conflates "no sequence can trip this" with "the prober never offered it". Re-checking each
  claim by searching reachable *states* for the guard's trip condition meant first asking
  how far the search gets: at depth 8 over 238,000 states it reaches **45** states with an
  attempt in `reviewing`, **156** in `awaiting_review`, and **zero** with a recorded
  verdict. Two claims stood on 45 and 156 witnesses; anything past a verdict could not be
  bounded at all.
- `KernelSearch` gained `:from`, so a search starts from a driven state and spends its
  budget where the question is. Seeded from a sealed reviewer: 164,648 states, 13,846
  holding an approved verdict.
- **It returned a vacuous result on its first run** — one state, zero of every predicate —
  because proposals restarted sequence numbering at 1 against a seed at 10 and were all
  refused as `out_of_order_event`. It looked exactly like a proof that nothing was
  reachable. Fifth vacuous first run this session, and the only reason it did not survive is
  that a sealed reviewer obviously can accept a verdict.
- **Seeded, it overturned a hand argument within one run.** `reviewer_closed`'s approved
  branch had been reasoned unreachable; the loose form of that reasoning has 3,612
  witnesses. The conclusion survived on the exact precondition — zero across 164,648 seeded
  states — and the reasoning did not. Two wrong calls in one hand-maintained list, again.
- Two more unreachable call sites found and recorded at the site rather than in
  `@unreachable`, which is keyed by error atom and cannot express them:
  `ticket_reset`'s `require_no_active_attempt` (10,024 exhausted states, none with an
  attempt; its twins in `ticket_amended` and `cancellation_finalized` both fire) and
  `reviewer_closed`'s `require_attempt_phase(~w(reviewing))`. **The gap is open: a dead call
  site is invisible to everything except an hour-long sweep.** Named in the briefing as the
  question worth a reviewer's attention.
- A state probe reported 774 witnesses for "attempt phase is not active" by matching `nil` —
  no attempt at all. Caught by reading the counterexample it printed. Predicates over absent
  entities are the shape to distrust.
- The kernel diff across this whole pass is **comments only**. No behaviour changed.
- Two incidents. The gate was run while the working tree was being edited and failed at
  `source_postflight` — the mirror image of the sweep-holds-the-tree incident, and the rule
  generalises: no tracked file is edited while any tool holds the tree. And preflight's
  test-file warning count went 4 to 6, which is the only reason two dead dispatcher clauses
  were caught; that check reports a number rather than a pass precisely for this.
- Suites: workflow **166 at seed 0**, from 116. Full model-free suite measured at the gate:
  **901 passed, 13 skipped, 1 excluded**. The prior serial run with a fresh `MIX_BUILD_PATH`
  was 867 passed, 13 skipped, and 867 + 35 = 902 = 901 + 1 excluded, so the delta is exactly
  the tests added and nothing quietly stopped being loaded. Canonical gate `elixir
  ci/run.exs`: **passes, suite 302.0s, total 312s** — the first duration any entry records. `bin/preflight.sh`
  passes with the 4 pre-existing test-file warnings.
- Sweep, final: 108 call sites; all 62 previously-unmeasured occurrences re-swept; **6
  survive**, exactly the six recorded as unable to fire.

## FR-08B kernel, subcommit 1 — fourth review, and two reviewers who agreed — 2026-09-21

- Candidate `34d6833` was reviewed twice in parallel by independent sessions that did not
  see each other's work: one on the kernel, one commissioned specifically on the **evidence
  architecture**, with endorsement named in its brief as a failed answer. Both returned
  BLOCK. The four things they agreed on are worth more than either review alone.
- **They agreed the mutation sweep's site inventory was still wrong.** Its scanner matched
  `<- require_(` only, missing six guard calls that dispatch directly or in tail position
  inside `require_settlement_source/2`. 114 sites across 70 texts, not 108/66 — and 108 was
  itself yesterday's correction of 66. Fifth time this tool's number has been weaker than
  its claim. It now runs a **red control at startup** over every guard shape — normal,
  multiline, duplicated, nested, tail — and halts if it cannot see them all.
- **They agreed the stale resume target was a defect, not a semantics question.** Both
  reproduced it from the same seven-event sequence. The implementer had found that state,
  called it harmless because the guards refuse everything from there, and deferred it to
  review. Wrong twice over: a ticket from which no productive event is accepted is a
  livelock, and `launch_planned` **is** accepted — opening a third developer execution on
  an attempt that has already frozen its candidate.
- **They agreed on what all five mechanisms were blind to**, arriving from opposite
  directions: relational post-state correctness. Every oracle in the suite asked whether one
  event was admitted or refused; none asked whether the facts in the resulting state cohere.
  The exhaustive search had **reached** the bad state — three of them at depth 7 — and did
  exactly its job. `State.valid?/1` accepted it, correctly, being a well-formedness
  validator. The failure was not reachability but an absent oracle.
- **They agreed atom-keyed dead-guard detection is the wrong granularity.**
- Two kernel defects the evidence review did not need to find, because the kernel reviewer
  reproduced them: `review_settled` erased a recorded verdict in one event, and
  `check_settled` deleted a check receipt that had already recorded `passed`. Both fixes are
  **one line calling a guard that already existed**, and both are the sixth and seventh
  occurrences of partial generalisation — a rule applied to part of a vocabulary and
  described in a commit message as applied to all of it.
- `SemanticInvariants` is the oracle. Its **red control failed twice before passing**: the
  first fixture was hand-built and not well-formed, so it would have "passed" by tripping
  `State.valid?/1` instead; the second revealed that the invariant as written was stricter
  than the fix both reviewers proposed, asserting an obligation neither the contract nor the
  review states. It now builds from a real reachable state with one corrupted field, and the
  stale-resume *residue* is documented as permitted-and-inert rather than asserted away.
- Fixing the resume target made `developing` with a non-active attempt unreachable, removing
  the only witness three call sites had. Recorded as **redundant given an invariant**, not as
  unreachable: bounded absence is not proof, and the reviewers were explicit that treating it
  as one is the habit to drop.
- **An active data-loss hazard, found by the evidence review.** The sweep ended with
  `File.write!(target, original)` — restoring a file it never modifies. Any legitimate edit
  to `kernel.ex` during the hour it runs was silently overwritten. It verifies and fails
  loudly now. Parallel sessions in this repository do write.
- `integration_recorded:infrastructure_failed` left the variant ratchet. The guard the fix
  touches is called only from `ticket_parked` and `ticket_blocked`, neither on the
  integration path, so sampling regressed rather than coverage: the variant sits ~12 events
  deep and the ratchet stood at zero by walk luck. It now has a driven witness, and an entry
  in that ratchet requires one.
- **The tools had no home.** All five were described in exactly one place — a 1,667-line
  plan that `AGENTS.md` tells agents not to preload — and no entry document mentioned them.
  A fresh session in any harness routed straight past four review rounds of method.
  [EVIDENCE-TOOLS.md](EVIDENCE-TOOLS.md) records what the gate enforces automatically (four
  of five), what must be run by hand and when, the six rules that decide whether a green
  result means anything, and the known gaps. Routed from `AGENTS.md`, this index and
  `docs/TESTING.md`, and written against a guarded reducer judged by a written contract
  rather than against this kernel. Six orphaned FR-08B documents routed at the same time;
  the documentation gate is 80/80, having been 79/80 since before this session.
- The evidence review's central recommendation is recorded and **not** implemented here:
  reduce five mechanisms to two — contract-to-predicate conformance, and instrumented
  exploration with semantic invariants and first-failure witnesses — replacing the hour-long
  sweep with AST guard-site instrumentation that costs one run, and replacing clause
  fragmentation with semantic clause IDs in the contract itself. It also declined the
  guards-as-data idea as too much architecture for an evidence problem.
- Suites: workflow **172 at seed 0**.

## FR-08B kernel, subcommit 1 — the inventory that could not see one of its two spellings — 2026-09-21

- `KernelSearch.declared_reasons/0` claimed to inventory the kernel's declared error set
  mechanically and scanned for one of the **two** spellings a refusal is written in. It
  matched literal `{:error, :atom}` and could not see `kernel.ex:80`, where the reason is
  lifted from a fetch: `Event.entity_kind(...) |> ok_or(:unknown_entity_kind)`. It had read
  69 of 70 declared reasons for three reviews and reported a complete inventory. Extraction
  is now `reasons_in/1` over source text — separate from the file read so a fixture can be
  fed to it — and covers both `ok_or` call forms rather than only the piped one the kernel
  happens to use. Red control: a fixture carrying every declaration shape and both
  `ok_or/2` definition clauses, which must not be read as declarations. Neutralising the
  added spelling turns two tests red.
- `:unknown_entity_kind` surfaced as never-fired and is recorded as **dead by construction**
  with an inductive argument rather than as bounded absence. `@entity_kind_of` is
  `Map.new(@types, ...)`, so its key set *is* the type vocabulary, and `Event.validate/1`
  runs first in `apply/2` requiring `type in @types`. A total map looked up with a key proven
  to be in its domain cannot return `:error`. Both halves are already enforced mechanically —
  the map by its own construction, the totality by kernel_test's "every type has an exact
  payload key set and an entity kind" — so nothing new was added to assert it.
- **Full sweep: 116 call sites, 14 survivors, 84 minutes.** The count is 116 and not the
  recorded 114 because `028b4965` added two guard calls; confirmed by per-name diff against
  `34d6833` — `require_no_recorded_verdict` and `require_check_unsettled`, one each — rather
  than assumed. Nine survivors were already on the books: the six recorded as unable to fire,
  plus the three `require_attempt_phase(~w(active))` sites that lost their only witness to the
  stale-resume fix and are recorded as redundant-given-an-invariant. **Five were real**, three
  of them inside `require_settlement_source`, whose six sites had never been individually
  measured. That correction paid for itself on its first full run.
- Three are closed, each pinned to its exact atom and each **confirmed by scoped re-sweep
  rather than by going green**: `require_phase(~w(queued blocked))` in `ticket_amended` (:289)
  and `ticket_parked` (:302), and the `"blocked"` branch of `require_settlement_source` (:1595).
- **A test was written for the wrong site, and only the sweep caught it.** The first version of
  the :1595 row settled `failed` from `checking`, which exercises the failed/timed_out branch at
  :1585 — already covered — while the row's name claimed :1595, which stayed a survivor. The
  branch-to-line mapping was read by eye out of a `case` with six clauses. The test was green and
  `kernel_test` went 109 to 112. Nothing else in the suite compares a test's claim against the
  site it actually exercises, which is the strongest argument yet for the coverage-guided
  rebuild: that mapping is what an instrumented run emits as a by-product.
- **Two survivors are unwitnessed, and the denominator is why they are not invariants.** :1557
  (`integrated` needs `integrating`) and :1574 (`rejected` needs `reviewing`) are each shadowed
  at the call site — measured, not argued: the probes return `:no_ref_receipt` and
  `:no_rejected_verdict`. Reaching either phase guard needs a state the bound does not produce.
  At depth 7 over **58,324 states, 0** have an active attempt holding a ref receipt and **0**
  have one with any recorded verdict. Adding the implied relations to `SemanticInvariants` — the
  precedent this repo set for exactly this shape — would have asserted them over 58,324 states
  none of which can trip them. That is the sixth vacuous mechanism, avoided by measuring the
  denominator *before* writing the check rather than after.
  **Corrected by the fifth review, same day:** stopping at the label was the wrong exit — rule
  3 says label *then* prove or delete — and `SemanticInvariants` was the wrong precedent to
  name. The repo's precedent for a zero-witness claim is `kernel.ex`'s `reviewer_closed`
  comment, which seeded the search rather than declining to assert. Seeded and measured at
  depth 6: **29,109 states with 20,488 holding a ref receipt, 0 violating**, and **79,163 with
  39,024 holding a rejected verdict, 0 violating**. With the inductive argument recorded
  alongside, both sites are now *redundant given an invariant*, not unwitnessed.
- The sweep's full verdict table and both neutralisation confirmations are committed as
  [evidence](fr-08/fr08b-subcommit1-sweep-2026-09-21.md), assembled by script from the tool's own
  output. Every hand-carried count from this tool has been weaker than its claim five times
  running, so nothing in it is transcribed. It is also the **answer key** a coverage-guided
  replacement must reproduce exactly.
- `@sites` line numbers: **the field is deleted.** The claim originally recorded here — "stale by
  +11 below `review_settled` after `028b4965`" — was itself wrong, and the fifth review measured
  it: that commit's kernel hunks are +6, +7 and +20; the +11 came from `c71fc70d`, the commit that
  *introduced* the table and added 23 kernel lines in the same change, so the labels were wrong the
  day they were written. Drift at HEAD is piecewise (+0/+11/+17/+24/+36/+56), not uniform, and not
  confined below `review_settled`. "Renumbering would be guesswork" was also wrong: the offsets
  derive from two hunk headers, and every renumbered row lands on a `require_` line. Recording an
  unmeasured "+11" in an entry whose thesis is that hand-carried counts from this tooling have been
  weaker than their claim five times made it a sixth. Coverage was never affected — the sweep is the
  measurement and the row labels are not — so the field went rather than being renumbered into a
  claim that would rot again at the next kernel edit. `COVERAGE-GUIDED-SWEEP.md` derives site
  identity properly.
- The kernel diff across this pass is **empty**. No behaviour changed; every number below moved
  because tests were added.
- Suites: workflow **176 at seed 0**, from 172. Full model-free suite serial with a fresh
  `MIX_BUILD_PATH`: **912 passed, 13 skipped**, 451s. The delta is the check — 901 at `34d6833`
  plus 7 added by `028b4965` (counted in the diff; the brief's estimate of ~11 was wrong) plus 4
  this session = 912 exactly, so nothing quietly stopped being loaded. Canonical gate
  `elixir ci/run.exs` on `21b5cd77`: **passes**, 911 passed / 13 skipped / 1 excluded, suite
  **295.6s**, total **306s** (prior entry: 302.0s / 312s). The gate excludes three provider tags
  the serial run does not, so 912 serial and 911 + 1 excluded at the gate are the same set; that
  was predicted before the run rather than reconciled after. `bin/preflight.sh` passes with the 4
  pre-existing test-file warnings, none in the files this candidate touches. Provenance records
  `dirty_paths: []`.

## FR-08B kernel, subcommit 1 — fifth review, and two false numbers of my own — 2026-09-21

- Candidate `be407674` was reviewed by an independent session briefed on the **delta only**,
  with the settled numbers listed as not-to-recompute. It returned **BLOCK** on narrow
  grounds, no kernel change required, and every finding was verified here before being acted
  on rather than taken on the reviewer's word.
- **The sharpest finding was about this log.** The previous entry argued that hand-carried
  counts from the sweep tooling have been weaker than their claim five times running, and
  then carried a sixth: "`@sites` line numbers are stale by +11 below `review_settled` after
  `028b4965`". That was never measured. `028b4965`'s kernel hunks are +6, +7 and +20; the +11
  belongs to `c71fc70d`, the commit that **introduced** the table while adding 23 kernel
  lines, so the labels were wrong the day they were written. Drift at HEAD is piecewise, not
  uniform, and not confined below `review_settled`. "Renumbering would be guesswork" was also
  false — the offsets derive from two hunk headers, and six spot-checked renumberings each
  land on a `require_` line.
- **The field is deleted rather than renumbered.** Coverage was never affected: the sweep is
  the measurement and these labels are not. But a number with no check, in a table whose
  purpose is that claims get checked, rots again at the next kernel edit — and it had already
  misled once this session, when the `attempt_settled`/`blocked` row was written against a
  line read off a six-clause `case` by eye. Rows now key on fixture/type/atom, collision-free
  across all 35. `COVERAGE-GUIDED-SWEEP.md` derives site identity properly.
- **"Unwitnessed" was the wrong exit, and the vacuity argument named the wrong precedent.**
  Rule 3 says label *then* prove inductively or delete; labelling is the interim step. And the
  precedent for a zero-witness claim is not `SemanticInvariants` — whose `@legal_pairs` has
  witnesses in the thousands, which is why it was never vacuous — but `kernel.ex`'s
  `reviewer_closed` comment, which met the same problem by **seeding** the search rather than
  declining to assert. The delta named the seeded search three times without running it.
- Run, at depth 6 from `integrating_with_receipt` and from a rejected verdict: **29,109 states,
  20,488 holding a ref receipt, 0 violating**; **79,163 states, 39,024 holding a rejected
  verdict, 0 violating**. With the inductive argument beside it — `ref_receipt_id` is written
  at exactly one site, under `require_phase(~w(integrating))`, behind `require_no_ref_receipt`
  in all three integration handlers, and carried to the attempt by the `@legal_pairs` agreement
  already asserted over the reachable set — both sites are **redundant given an invariant**,
  not unwitnessed.
- `:unknown_entity_kind` survived the attack and is stronger than it was recorded: the decisive
  enforcement is `event.ex:192`, which performs the identical lookup after `:191` constrains
  the kind, so a missing key is refused before `kernel.ex:80` runs. Unlike the `reviewer_closed`
  argument that a looser predicate falsified with 3,612 witnesses, this one is local to a single
  `with` over an immutable event and a compile-time map; there is no state to evolve.
- The evidence document claimed "assembled by script, not transcribed" with neither script nor
  log committed — an unverifiable provenance claim in the document written to make provenance
  verifiable. The raw, unedited output of all three sweep runs is now committed beside it.
- **The confirmation pass found a seventh.** The remediation above treated the two sites as one
  argument, and for the receipt site the decisive link was itself a vacuous appeal. The receipt
  is written under `require_phase(~w(integrating))` — the *ticket's* phase — and lands on the
  active attempt, so the base case needs ticket-integrating implies attempt-integrating. The
  remediation cited `@legal_pairs` "already asserted over the reachable set": true, and worthless
  here, because that set holds **zero** integrating tickets — `@unreachable` says so itself, at
  "integration row: ~12 events". Thousands of witnesses for the `developing` row are not
  witnesses for this one. Worse, the seeded run starts from a state that *already holds* the
  receipt, so it measures preservation and could never have caught this. The argument that holds
  is structural coupling: ticket phase `integrating` is set at one site and the same pipe sets
  the attempt's phase on the next line, `integration_settled` moves both off together, and
  `attempt_settled` clears the slot — set together, cleared together, which is the form
  `semantic_invariants.ex` uses for developing/active. The verdict site never needed the link:
  `review_recorded` guards the attempt's own phase and writes to that attempt.
- **A reachable kernel defect, found by the confirmation pass and not fixed here.**
  `integration_recorded`'s `infrastructure_failed` branch moves the ticket to `blocked` with a
  `ready_to_integrate` resume target and **leaves the active attempt at `integrating`**.
  `ticket_blocked` never touches the attempt, `blocked` is not a key in `@legal_pairs`, so
  nothing complains while blocked — and on `ticket_unblocked` the ticket lands on
  `ready_to_integrate` with the attempt still `integrating`, which `@legal_pairs` calls a
  violation. Reproduced end to end:

      integration_planned    ticket=integrating        attempt=integrating        clean
      infrastructure_failed  ticket=blocked            attempt=integrating        clean
      ticket_unblocked       ticket=ready_to_integrate attempt=integrating        VIOLATION

  `State.valid?/1` accepts every step, correctly — nothing is malformed. This is the same class
  as the stale-resume defect that blocked review 4: a state the oracle would call illegal that no
  search reaches, here ~14 events from empty against a depth-7 bound. It is also the same shape
  as the six recorded partial generalisations — `integration_settled` moves ticket *and* attempt
  to `ready_to_integrate` in one pipe, and the `infrastructure_failed` branch beside it moves only
  the ticket. The likely fix is one line in that branch. **Not applied**: it is a behaviour change
  on a gate-validated candidate, it needs independent review of its own, and subcommit 1 was not
  scoped to it. Recorded for a scope decision.
- Follow-up recorded and not taken, also from the fifth review: key `@sites` rows on the guard
  **call text** rather than deleting the identifier outright. It is what the sweep prints and what
  `SWEEP_SITES` consumes, it does not drift, it distinguishes the sites sharing an atom by their
  branch, and it asserts cheaply — the kernel either still contains that text or the guard was
  renamed or removed, which is the one time a row should fail. Better than deletion or
  renumber-and-assert; deferred as out of scope for this candidate.
- Residual, recorded not fixed: `reasons_in/1`'s `ok_or` regex is single-line and greedy, so a
  formatter-wrapped call or a chained call on the same line would be missed. Today's kernel has
  three `ok_or` lines and none has that shape; it wants a fixture row when one appears.
- Two of my own claims this session read as measurements and were not, and a third test named a
  site it never exercised. The sweep caught one, the review caught two. That is the argument for
  mechanisms that derive their numbers rather than restate them.
- Rule 2 wants one clause, on the fifth review's recommendation and not yet applied: a claim of
  absence should report how many states were checked, **how many held the precondition**, and how
  many violated — a precondition count of zero is rule 1's vacuous mechanism with a number
  attached, not rule 2 compliance. `kernel.ex`'s `reviewer_closed` comment and this session's
  seeded runs already use that three-number format; the rule does not yet ask for it. Editing the
  rule list is a decision for the repository owner, not something to slip in beside a candidate.
- Gate on `1b9c660e`: **passes**, 911 passed / 13 skipped / 1 excluded, suite **284.0s**, total
  **295s**, provenance `dirty_paths: []`. Workflow suites **176 at seed 0**, unchanged — this
  pass adds and removes no tests. `bin/preflight.sh` passes with the 4 pre-existing warnings.

## FR-08B kernel, subcommit 1 — the defect the fifth review left recorded, fixed — 2026-09-21

- Taken as **its own candidate**, not folded into subcommit 1 or 2. Subcommit 1 is closed at
  seven commits and four green gates, and reopening it buys a sixth independent review of all
  seven; subcommit 2 is `decide/3`, a different surface, and shipping it on a kernel holding a
  recorded reachable violation makes its reviewer reason around one. One review of a two-file
  delta is the cheapest of the three.
- **The enumeration was grepped, and the grep matched one spelling.** Six sites write
  `phase => "blocked"` literally; the sixth review found a seventh writer the pattern cannot
  see — `ticket_admitted` (:268) writes `"phase" => payload["phase"]`, which is `"blocked"` on
  the blocked-admission path. Safe, because no attempt exists at admission, so the singleton
  conclusion survives; but "grepped, not asserted" was itself resting on a regex inventory,
  which is the known gap `EVIDENCE-TOOLS.md` already records for `declared_reasons/0`. The
  six literal writers:
  `ticket_parked` (:307) and `ticket_blocked` (:327) route through
  `require_honest_resume_target`, whose target is the ticket's own current phase, so the
  attempt is untouched and the pair is preserved. `artifact_blocked` (:487) and
  `freeze_failed` (:508) block from `developing` with resume `developing` and leave the attempt
  `active`, which is legal. `attempt_settled` (:1051) clears the active slot.
  `integration_recorded`'s `infrastructure_failed` branch is the only site whose resume target
  differs from the ticket's phase while an active attempt survives, and the only blocked-writer
  that bypasses the honesty guard entirely. So rule 4 does not force a vocabulary-wide edit
  here: it is a singleton, and the general path already routes through one guard. The previous
  entry called this a partial generalisation and was right about the shape; the grep is what
  establishes there is no sibling to carry the fix to.
- **Red before the fix existed, and red in the right place.** The regression drives
  `approved_and_closed` → `infrastructure_failed` → `ticket_unblocked` and failed at the final
  assertion only. The blocked-window assertion passed, which is the half worth recording: it
  confirms the oracle's silence at `blocked` is this defect's delay rather than a second defect.
  `State.valid?/1` accepts every step, so the shape validator was never going to see it.
- The assertion is `SemanticInvariants.violations(state) == []`, not the two phase strings, so
  the control covers the relation rather than the one field this branch got wrong.
  `kernel_test.exs` now requires `semantic_invariants.ex` the way `r4_exhaustive_test.exs` does.
- **No guard was added or changed**, so no sweep site moved and `SWEEP_SITES` has nothing to
  scope. This is precisely the class the sweep cannot see: it neutralises conditions, and here
  every guard was already correct and the post-state write was wrong. That is the standing
  argument for EV-3, now scoped rather than recorded.
- Sol's three undesigned proposals are scoped as work items in
  [the evidence-reduction tickets](fr-08/fr08b-evidence-reduction-tickets.md), with the two
  orderings that decide the sequence stated: payoff per unit cost runs EV-4, EV-3, EV-2, while
  cost-growth-if-deferred runs the reverse. They create no FR node; the namespace is closed at
  FR-23. **EV-4 first** — every "N states, M holding the precondition, 0 violating" recorded in
  this subcommit is computed over the quotient rather than the reachable set, so rule 2's
  denominators are conditional on a congruence nobody has proved.
- Measured while scoping EV-2, not transcribed: `r4_coverage_test.exs` stands at **57 clauses
  asserted and 57 uncited over 32 rows, with 4 `@partial` entries**. Its own comment says "54
  clauses are asserted and 59 are not". Left unedited, because a stale count inside the file
  whose purpose is that counts get checked is the argument for EV-2 rather than a footnote to it.
- Workflow suites **177 at seed 0**, from 176: one test added, no ratchet shifted. Gate on
  `4fa3bc96`: **passes**, **912 passed / 13 skipped / 1 excluded**, suite **298.3s**,
  provenance `result: passed`, `exit_code: 0`, `dirty_paths: []`. The count was predicted
  exactly before the run (911 + 1) — though the artifact records only an `output_sha256` for
  the test command, not pass/skip/exclude counts, so 912/13/1 is transcribed from the terminal
  and was independently reproduced by the sixth review at 912/13/1 in a clean worktree. The duration was predicted as 285–295s and came in at
  298.3s, outside the stated range — recorded rather than widened after the fact, since a
  prediction adjusted to its own result measures nothing.

## FR-08B kernel — sixth review blocked the fix, and the fix was mine — 2026-09-21

- `4fa3bc96` was reviewed independently, scoped to that delta, in a detached worktree at that
  commit. **BLOCK**, and the lead finding is a regression the candidate introduced. Verified
  here before acting, per the standing rule, by driving the sequence rather than reading it.
- **The fix made one oracle happy and broke a contract-backed refusal.**
  `require_settlement_source`'s `superseded_base` branch (:1565-1575) tests issuance only when
  `attempt["phase"] == "integrating"`, on the premise its own comment states: "From
  `ready_to_integrate` no integration effect exists yet, so the clause is satisfied by the
  phase." Moving the attempt to `ready_to_integrate` while it holds a running integration
  execution falsifies that premise, and R4's "accepted base moved **before issuance**" row
  then accepts a settlement made after issuance.
- **Nothing in the evidence architecture could have caught it.** `State.valid?/1` accepts the
  post-settle state, `SemanticInvariants` accepts it, no sweep site moved, and
  `:integration_already_issued` sits in guard reachability's `@unreachable` — so the ratchet
  had no witness to lose. "Shifts no ratchet" was true and meant nothing. Four green gates and
  a passing regression test would have shipped it.
- **The wrong field was `resume_phase`, not the attempt phase.** The branch stored
  `ready_to_integrate`. Storing `integrating` — a permitted `@resume_phases` value — restores
  the coupled pair on unblock, leaves the attempt where it is, and keeps the issuance guard
  live. One word, and strictly smaller than the change it replaces.
  **Corrected by the seventh review:** the warrant is `WORKFLOW-CONTRACT.md:493-494`, "A
  resumable resource or infrastructure block **retains its attempt phase** unless a row
  explicitly terminates it" — which settles it directly, since a retained `integrating`
  attempt makes `integrating` the only `@legal_pairs`-legal target. The commit cited row
  :486's "Same phase" instead, and that phrase attaches grammatically to the row's *retry*
  alternative, not to its blocked alternative. Right answer, over-read citation.
- **The obvious alternative is a trap, and the seventh review found the real reason.** Making
  `integration_issued?` phase-independent looks like the root-cause fix — delete the premise,
  keep the real test. It breaks a path that has always worked, because `integration_settled`
  is the *non-start* settlement and closes the integration execution, so a legitimately
  `ready_to_integrate` attempt holds one with lifecycle `closed`, which the predicate reads as
  issued. But that is the symptom. The defect is that `integration_issued?` (:1640) scans
  **any** integration execution rather than the **current** one, and it is already wrong today
  without any phase change: after a retry — I1 `closed`, I2 `pending`, attempt `integrating` —
  `attempt_settled(superseded_base)` is refused `:integration_already_issued` although the
  current effect is unissued, which makes contract row :484 unexpressible for a retried
  integration. Reachable before this delta via `no_ref_change` → `worker_closed` →
  `integration_planned`, and this remediation routes blocked tickets onto exactly that path.
  A "newest integration execution is pending" predicate would be phase-independent and correct
  on both cases. Recorded, not fixed: it is a separate defect and wants its own candidate.
- **The regression control was oracle-dependent.** The review showed that deleting one line
  from `@legal_pairs` — `"ready_to_integrate" => ~w(ready_to_integrate)` — turned the new test
  green with the defect present, and nothing else in the suite pins that pair. The test now
  asserts the attempt phase directly as well as through the oracle. Asserting only the relation
  was argued in the previous entry as a strength; it was a single point of failure.
- Two tests now pin `:integration_already_issued` by exact atom, from the blocked window and
  after unblock (rule 5). Rule 6, run and reversed by exact string: restoring
  `ready_to_integrate` as the target turns **three** tests red, including the review-4 witness
  for this row, which had asserted the old target.
- Doc corrections the review forced: the "six sites write `phase => \"blocked\"`" enumeration
  missed `ticket_admitted` (:268), which writes `payload["phase"]` — safe, no attempt exists at
  admission, but the grep matched one spelling, which is the gap already recorded for
  `declared_reasons/0`. The provenance artifact records `output_sha256` for the test command,
  not pass/skip/exclude counts, so 912/13/1 was transcribed from the terminal; the review
  reproduced it independently at 912/13/1. A comment in `kernel_test.exs` still described the
  branch as defective and is corrected.
- The pattern the previous entry named held again, one level up: the kernel defect was real,
  and so was the defect in the fix for it — but only the review found the second, because every
  mechanism was silent on both.
- **EV-4 landed in the same pass** (`96ad2f22`), the first of the three evidence-reduction
  tickets. The quotient it proves is not incidental: at depth 5, 16,289 tree states collapse to
  2,736 classes and 2,250 of those classes merge something. Enumeration runs under
  `identity_key/1`, because grouping `search/2`'s own output would return one state per class
  and compare nothing — using the quotient to check the quotient. Depth 4 in the suite: 1,388
  comparisons over 371 merging classes, 0 violations, 3.1s. Depth 5 run once: 13,553
  comparisons, 0 violations, 22s, left out because a 22-second permanent acceptance step that
  found nothing new at depth 4 is the sweep's cost mistake in miniature. Red control is
  permanent rather than a one-off: the same comparison under a phase-dropping key finds 25
  disagreements, and neutralising `key/1` itself turns the real test red at 25 of 1,399.
- Gate on `771d0d66`: **passes**, **915 passed / 13 skipped / 1 excluded**, suite **302.3s**,
  provenance `result: passed`, `exit_code: 0`, `dirty_paths: []` before and after. Both numbers
  were predicted before the run and both landed — 912 + 2 from EV-4 + 1 from the remediation,
  and 300–312s after the previous entry's duration prediction was too narrow. Workflow suites
  **180 at seed 0**. `bin/preflight.sh` passes with the 4 pre-existing warnings, in
  `stress_test.exs` and `jev_test.exs`, neither touched by this candidate — checked rather than
  restated from the previous entry, where the sampled warning text had changed while the count
  had not.
- **Seventh review: ACCEPT on both pieces**, with the two log corrections above, and it
  reproduced the gate count independently — 915 passed / 13 skipped / 1 excluded, 300.7s, in
  its own worktree with a fresh build path. It also verified what the previous entry only
  claimed: EV-4's depth-5 numbers (16,289 / 2,736 / 2,250 / 13,553 / 0) match exactly, and
  `outcomes/2` is a faithful model of the search's own event construction, because
  `state["last_sequence"] == length(path)` holds for all 1,898 depth-4 states. It strengthened
  EV-4's red control too: eleven further lossy keys all produce disagreement, and the four
  fields that produce none also merge no extra classes at depth 4, so they are determined by
  other fields rather than being a weakness in the control.
- **The review's largest finding is outside both pieces, and outranks them.**
  `r4_exhaustive_test.exs:141-148` — the test that applies `SemanticInvariants` to every state
  the search reaches — **cannot fail**. Its lambda returns `{:error, msg}` and `check/2` matches
  `{:violation, msg}`, so the `_ -> nil` clause swallows every violation. Verified here before
  acting: at depth 6 from empty, **190 of 13,290 reachable states violate**, the shortest four
  events from empty (`ticket_admitted:queued` → `launch_planned` → `cancellation_requested` →
  `attempt_settled:cancelled`, "ticket is developing with no active attempt"). Introduced in
  `028b4965`.
- That makes it the **seventh vacuous mechanism** in this subcommit, and the most expensive
  one, because the claim it supports has been repeated as settled: "`SemanticInvariants` now
  asserts over every state the search reaches" appears in this log and in a `kernel_test.exs`
  comment, and has been false since it was written. Rule 1 exists for exactly this and was not
  applied to the mechanism that enforces the other rules' oracle.
- Filed as **EV-5**, sequenced ahead of EV-3 rather than fixed here. The one-word fix turns the
  test red, so it is not a fix — it is the start of classifying 190 states, each of which is
  either an oracle gap or a kernel defect. `apply_terminal_phase` deliberately leaves a
  cancelled ticket in its working phase awaiting `cancellation_finalized`, and the oracle's nil
  clause calls that "a ticket nothing can move" while a sibling clause already encodes the
  cancel exception it lacks — so the likely answer is the oracle. Likely is not classified, and
  reading the first of 190 counterexamples is how six of this subcommit's defects were made.

## Unrelated to FR-08B: the Improver has never completed a cycle — 2026-09-21

Recorded, not fixed. It is outside every FR-08B candidate and wants its own, but it is a live
failure rather than hygiene, so it should not wait unrecorded behind a blocked ticket.

- `system_metrics.ex:43` computes `ets_table_count` as
  `length(:erlang.system_info(:ets_data) |> elem(0))`. **There is no `:ets_data` system info
  item.** Verified directly: the call raises `ArgumentError, "1st argument: invalid system info
  item"` on OTP 29.0.5. The expression is malformed twice over — even had the item existed,
  `length(elem(_, 0))` is not a table count. `:erlang.system_info(:ets_count)` returns it
  directly, as does `length(:ets.all())`; both report 21 here.
- So `SystemMetrics.system/0` raises on **every** call, unconditionally, and has since it was
  written. It is not a rare path: `improver.ex:138` calls `log_metrics/1` on the cycle path
  with no guard, and the Improver's interval is 300s. **The Improver has therefore crashed on
  every cycle and the `metrics_snapshot` record has never once been written.** The second
  caller is `cli.ex:106`, so the operator-facing metrics command fails the same way.
- **Nothing in the suite mentions `SystemMetrics`** — grepped, zero test files. That is why a
  function which raises on every call passes a gate with 915 tests. Same shape as the seventh
  vacuous mechanism recorded above, one layer out: the gate proves the suite passes, not that
  the suite looks at anything.
- The fix is one expression. The candidate is the fix plus the test that would have caught it,
  and the question of whether `log_metrics/1` should be allowed to take down a cycle at all —
  a metrics snapshot failing is not a reason to abandon an improvement cycle, and the crash has
  been masking whatever else that cycle does.
