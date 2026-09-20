# FR-15aA executable provisioning specification

**Status:** specification complete; host provisioning and production execution blocked.

**Frozen input:** repository commit `f5067d96d67a9ec3193a9b8bbadfa54c16525aa3`,
tree `f19af86efd775fa0debd75868f571b13feaa748d`.

**Checkpoint evidence:** corrected checkpoint-F candidate
`148476c93497653abbbc52fb040cf76927478d3f`, independently reviewed **PASS for
checkpoint F only** at `ca8c6d0b5edc9a5cfb9c265e710b29f3210f5cbe`.

This is the FR-15aA provisioning and executable-path specification. It does not install
accounts, change packet-filter policy, inspect credentials, start Foundry, invoke a model,
operate Herdr, or prove FR-15aB/FR-09 conformance. OMP remains the governing harness.
Pi is an evaluated, blocked replacement candidate and is not selected by this document.

The machine-readable source of truth is
[`provisioning-manifest.exs`](provisioning-manifest.exs). From `foundry/`, validate it
without Mix, a provider or a daemon:

Candidate commands/results and remaining gates are frozen in
[`evidence.md`](evidence.md). The initial frozen candidate received an independent
[`BLOCKER` review](independent-review.md); its focused
[`rereview`](independent-rereview.md) retains the residual B2 identity and duplicate-ID
controls corrected here. This revision addresses only those bounded B1–B3 findings.

```sh
elixir ci/validate_fr15aa.exs
```

The validator requires every executable category, principal, channel, credential policy,
network policy and acceptance probe, rejects unknown or duplicate security identities,
and requires every blocked or unavailable route to fail closed. Each pin is bound to its
exact ID, kind, version, path, disposition and digest. Repository-pin bytes are selected
from that frozen identity beneath the source root, never from a manifest-directed path.
Its ExUnit controls include erased and redirected pin identities, contradictory duplicate
auth-channel and shell declarations, deletion of a required route, removal of a route
mapping, fail-open promotion and attempted Pi selection.

## 1. Frozen facts and present limits

Checkpoint F safely established the following, using only synthetic credentials and a
loopback fixture:

- Pi `0.85.1` raw RPC can start, observe, acknowledge a prompt before settlement, abort,
  reopen an isolated session and terminate a verified PID. Its direct RPC Bash ran
  `elixir bin/check_docs.exs` and observed `80 passed`.
- That useful path is not conforming: Bash ran in the same Unix principal as Pi, without
  a typed effect capability or protected R1/R5 mediation.
- Pi sent the synthetic bearer directly. Both synthetic requests had no Foundry claim or
  reservation handshake.
- Ambient/project discovery controls worked in the fixture, but a CLI-explicit extension
  executed despite `--no-extensions`, saw its allowlisted environment and read deliberately
  opened FD 9. Bundled inline extension code remained registered.
- The corrected `/usr/bin/env -i` fixture removed hostile provider, proxy, auth-agent,
  Git-helper and runtime variables from Pi, Bash and the extension, and contained all
  Pi/Jiti/npm/XDG/session/temp/cache writes beneath one owned root. That proves fixture
  containment only, not production principal separation.
- Same-user Bash could signal the probe parent and read the worktree's shared Git `HEAD`.
  Pi, OMP and Herdr currently share user-level process, config, session and IPC authority.
- Pi direct network configuration, proxy denial, process-memory denial, Git custody,
  cross-assignment denial, descendant cleanup, subscription entitlement, quota/fallback
  behavior and hidden retries remain unproved.

The installed pins are recorded without opening credential/configuration contents:

| Item | Version / identity | SHA-256 or limitation |
|---|---|---|
| governing OMP | `/Users/raymondluong/.local/bin/omp`, `omp/18.2.2` | `e0302a99643efefb62bf3d0601d5d84ebab6ed1f3ad105cc2874c8274af448a9` |
| Pi candidate | `/opt/homebrew/bin/pi`, `0.85.1` | `e6d7fcf36a239cf3746e67ddf4222081ac01a601b85a3ee688bdfe9c161d754c` |
| Pi package manifest | installed `package.json` | `f1738e4b42203e5f22bcb513f13fb2fb224f1e98d1f129ff042f87048665a94c` |
| Pi production inventory | 186 offline `npm ls` manifests | `661ce1b6472d947977928059d6c6ae155dbd2941eee3affad2d922c29313f816`; inventory, not lock provenance |
| Node / npm | Node `26.8.2`; npm `11.19.1` | Node `902b6a6984d5d825829ea9064ab73b734548df37bc0683990dca31c8dc2a9253`; npm digest not recorded at F |
| Herdr presentation | `/opt/homebrew/bin/herdr`, `0.9.0` | `7257396b19a082193cbf39b4805341eaddabb489d4dbbecaccbba00164339b87` |
| Foundry CI toolchain policy | Elixir `1.20.3`, OTP `29.0.5`, ERTS `17.0.5` | `foundry/ci/toolchain.exs` `06d9fbb6ea92206dff68d705b2cae885b44a08b21495c1c5db620b456aecacc1` |
| Foundry packages | exact `mix.lock` at the frozen input | `bf2a61f815533a96b2abec87b1690ae49145bec56e60703a22b4db178c56e954` |
| current legacy config | `config/config.exs` at the frozen input | `d38fca63c3463b4bbbb5c56afcd66a900d4f6e4d5c5434bf3ec0157f372a7b16`; not the provisioning config |
| assignment schema | v1 at the frozen input | `3042a56aa668c2852a4fdcf21c35eb70bd36d350e210e05f151177b60449ba8f` |

The manifest also pins the inspected host profile (macOS `26.6.2`, build `25G83`,
`arm64`) and exact hashes for the shell, environment scrubber, Python, Git, process
observers/signaller, packet filter, launch service, directory service, Elixir and Mix.
The validator binds every route to its complete declared dependency list; a package lock
alone cannot stand in for an executable, adapter or helper. npm's standalone executable
digest was not recorded at checkpoint F, so that pin is explicitly blocked rather than
treated as implemented provenance.

The proposed workflow kernel, launcher, request gateway, effect bridge and acquisition
service have no artifact yet. Their required paths are pinned in the manifest with SHA-256
`unimplemented`; provisioning must refuse them until FR-15aB supplies independently
reviewed artifacts and replaces those markers with real digests. The absent `expert` LSP
is unavailable, not an implied dependency to install.

### Current OMP/Herdr and Pi executable routes

The current route inventory is complete for the surfaces inspected at the frozen input:

1. Automatic developer scheduling enters `Coordinator.Tick`; reviewer launch also enters
   from `Coordinator`. Both construct an `AgentServer` after static launch-eligibility
   checks. `AgentServer` asks Herdr to split a pane with the candidate checkout as CWD,
   starts agent kind `omp`, and passes `--profile`, `--provider`, `--model`, `--thinking`
   and `--approval-mode` as native OMP arguments. It then prompts, reads, interrupts and
   cleans up through Herdr. This route does not supply a remote isolated tool bridge or a
   per-model-request claim.
2. `Herdr.Argv` constructs inert argv. `Herdr.Adapter` performs presentation/agent
   identity checks. `Herdr.Runner.System` resolves and `Port.open`s the configured
   `/opt/homebrew/bin/herdr`; it reports subscription-route enforcement as unsupported and
   does not scrub the environment or descriptors. `Effects.Launch` and
   `Effects.PromptDelivery` provide legacy checkpoint/reconcile paths around the same
   adapter. Pane/process identity is useful containment but is not the R1/R5 or principal
   topology specified here.
3. The configured execution/presentation path and its controlling source hashes are pinned
   in the machine manifest: Coordinator
   `925c54dba022a06213f0d33eb26c6b352fbde53c713796e3587d96640e9db7e6`, Tick
   `8df097027896c88bb55f03f50a6cb6f5592c64a8c201f41aa1bf186754143ee0`,
   AgentServer `ec7e1ea88b26afc0f5b6ef3912479828334c32b16030ba6113aec1639aa360de`,
   Herdr Adapter `404406087170a1e37fcaaa3a6bc0ea9528cc659a689260ac2664bf1e5e846189`,
   Argv `e58e0d7c6f9701388ed1ce3c7d78e7984836677a027883f181a717bbbf303bfc`,
   Runner `1df506bc0444df2326de7fd9328e72038d990e2bbc36f5c9e038abbbc0fa2650`,
   Launch `b76aa1650acdfac03b35e2e498f5260c1f23081c682007f7a80b26fa89c9da22`
   and PromptDelivery
   `f4e4c49c24498141495e02ce0d696788f276701151e6e1a22df686ffbd6961e9`.
4. `Checks.Runner` can launch arbitrary admitted check argv through a Python trampoline
   and currently overlays its supplied environment on the parent environment. Its hash is
   `22610624df6102f59579808048581e7e947eab19dfcc34cbaf3661d7255af8fc`;
   `Effects.ProcessGroup` is
   `1250c2bee6d43751ac5f483224c0506e3670bf25a8c7f85cd0848d106d8dce17`.
   Build hooks, child processes, inherited environment and background jobs therefore stay
   blocked until moved into the build/slot principals and complete cleanup protocol.
5. `CLI.RPC` (`617fb1dc018a70abb9ffd7f97bc7e886db6d217c16ae06ea15ef233d5829b11d`)
   transports a bounded command shape as inert data, but its own module documentation
   correctly says the release still exposes general evaluation. It is not an authority
   credential and must be replaced by the scoped Unix-socket protocol.
6. Current Git evidence, relocation and status paths execute `git`; candidate worktrees
   lead to shared common metadata. The pinned `GitEvidence` path is
   `4f044446b3559e8635da488e2d9f9f1047c1b665f56f4c84cb8fad43394fc7ce`.
   The proposed disposable view/mediated Git boundary applies equally to shell, checks,
   build hooks, LSPs and subprocesses.
7. Pi has no current Foundry production route. The accepted provider-free probe
   (`c9a91bad8417314ce3ba0080562de4574425211d4fe25d3e68447a535cd83eea`)
   directly starts pinned Pi/Node, activates a CLI-explicit extension, directs its
   synthetic model traffic at a loopback fixture and invokes Bash. It is evidence only;
   none of those direct edges becomes an accepted production edge.

The manifest additionally enumerates file read/write, custom tools, discovered and
explicit extensions, startup code, build hooks, language services, every subprocess,
environment, descriptors, direct/proxy network, IPC/process memory, Git/shared state,
presentation, role/slot reuse, cleanup, acquisition, build and runtime. Absence of an
installed executable is recorded as unavailable; it never removes the category.

## 2. Actual proposed host topology

The target is one dedicated macOS host using separate non-login service accounts. Merely
changing directory modes under the operator's account cannot satisfy this topology.

| Principal | Purpose | May hold | Must never hold |
|---|---|---|---|
| `root` | verifier, durable store, policy, R1/R5 transitions, accepted refs and activation root | root signing/verification material, store, policy, recovery authority | model-visible checkout or candidate-loaded code |
| `_pramana_kernel` | autonomously repairable workflow kernel: pure decide/apply, scheduling, recovery proposals and domain projections | exact admitted kernel artifact, canonical command/receipt inputs, versioned bundle capability, kernel-owned cache | SQLite/OS/root/provider credential or authority to assert protected fields |
| `_pramana_launcher` | fixed root-installed launcher and slot lifecycle broker | one-operation launch/cleanup capability | provider credential, steering credential, arbitrary argv authority |
| `_pramana_auth` | fixed-route provider adapter and authentication refresh | reusable provider authentication, fixed provider/account/profile route | candidate checkout, shell/build tools, general proxy service |
| `_pramana_harness` | pinned OMP process; later Pi only after explicit selection | execution capability, assignment session, request capability | reusable provider authentication, operator home, direct project shell |
| `_pramana_present` | Herdr and sanitized optional presentation | presentation IDs and redacted event/control view | steering, root, request or tool capabilities; raw operator shell |
| `_pramana_fetch` | controlled artifact acquisition | exact root-admitted URL/host/digest/size request | provider authentication or generic proxy permission |
| `_pramana_slot01` | one untrusted developer tool slot | execution-scoped workspace and typed invocation | auth/root/presentation/other-slot state, protected Git metadata |
| `_pramana_slot02` | one untrusted reviewer tool slot | read-only candidate plus review-output grant | candidate mutation, developer lineage/token |
| `_pramana_slot03` | one untrusted PM tool slot | read context and proposal-output grant | candidate mutation, admission/policy mutation |
| `_pramana_build` | untrusted build/check hooks | immutable source input and new output root | integration refs, provider auth, accepted release store |
| `_pramana_runtime` | restricted accepted release | immutable accepted release and service-specific runtime state | source/build roots, integration/provider/root credentials |

Three slot accounts are the initial capacity, not role identities. Each assignment binds
one role, execution, candidate generation and revocation generation to one slot. Reviewer
independence is checked from durable principal/lineage evidence; renaming a session or
reusing an account does not create independent review. A slot cannot change role while
any process, descriptor, socket, mount, capability or uncertain issued effect from its
previous assignment remains.

The root derives these maximum capability sets; a request may narrow but never enlarge
them:

| Role / service | Maximum operations | Explicit denials |
|---|---|---|
| root verifier/store | verify/admit, R1 claim/issue/settle, R5 reserve/settle, capability issue/revoke, protected evidence/ref/activation decisions | candidate-loaded code and model-directed arbitrary execution |
| workflow kernel | query canonical retained inputs; propose supported domain events/projection CAS, effects, schedules and recovery bundles | SQL/filesystem root, arbitrary event/command evaluation, budgets/claims/policy/receipts/acceptance/integration/deployment fields |
| launcher | one fixed manifest launch, observe exact incarnation, owned cleanup/quarantine | arbitrary argv, policy mutation, provider request, candidate/Git mutation |
| auth gateway | one exact claimed model request and attributable reconciliation/receipt | arbitrary URL/header, CONNECT, tool execution, new grant/session/route |
| harness | start/observe/prompt/interrupt/reconcile/close its exact session; submit typed tool/request calls | reusable auth, direct provider/IP, local shell/file/build, grant minting |
| developer slot | admitted workspace read/write/search/edit, bounded shell/job/check request, candidate handoff output | protected refs/store/policy, other roles/slots, acceptance or provider route |
| reviewer slot | exact candidate/evidence read, bounded checks, review artifact write | candidate mutation, developer identity, self-acceptance, integration/provider route |
| PM slot | admitted status/spec/context read and proposal artifact write | candidate/policy/admission mutation, execution grant, acceptance/integration |
| build | one registered check/build specification over immutable input and new output | source/integration mutation, provider/root credentials, undeclared network |
| runtime | start/stop/health for one accepted immutable release and scoped service state | build/source/Git/provider/root access or activation decision |
| fetch | one admitted URL/host/redirect/digest/size acquisition | generic proxy, provider auth, caller-selected destination path |
| presentation | sanitized attach/read and interrupt request against exact presentation ID | workflow completion/verdict, direct signal, operator shell, raw secret/capability |

Child/delegated execution receives a separate identity, claim, reservation and capability
set no broader than its parent. No caller-supplied role, path, provider or model string is
authorization.

### Protected paths and listeners

| Path / listener | Owner and mode | Rule |
|---|---|---|
| `/Library/PramanaFoundry/bin` | `root:wheel`, directory `0555`, files `0555` | reviewed launcher/gateway/bridge/fetch artifacts only; no candidate writes |
| `/Library/PramanaFoundry/manifests` | `root:wheel`, `0555`; files `0444` | active artifact/loadout/policy digests; candidate proposals never become active in place |
| `/Library/PramanaFoundry/releases` | `root:wheel`, `0555` | immutable accepted release objects; activation pointer root-owned |
| `/var/db/pramana-foundry` | `root:wheel`, `0700` | durable store, R1/R5, policy, capability digests, accepted Git custody |
| `/var/empty/pramana-foundry/kernel` | `_pramana_kernel`, `0700` | neutral kernel home and disposable cache only; no protected database or candidate checkout |
| `/var/run/pramana-foundry/root.sock` | root with a dedicated peer ACL, `0660` | scoped local commands only; no BEAM distribution/eval |
| `launch.sock` | root/launcher peer pair, `0660` | fixed launch/cleanup operations |
| `auth.sock` | auth/harness peer pair, `0660` | fixed model requests only; never CONNECT or caller-supplied auth headers |
| `effect.sock` | controller/harness peer pair, `0660` | typed invocation requests; workers receive a fixed operation over an owned pipe |
| `fetch.sock` | root/fetch peer pair, `0660` | admitted immutable acquisition only |
| `presentation.sock` | root/presentation peer pair, `0660` | one-way sanitized events and bounded presentation controls |
| `kernel.sock` | root/kernel peer pair, `0660` | versioned R3 transaction bundles and canonical queries only; never SQL, eval or shell |
| `/var/empty/pramana-foundry/<principal>` | matching service account, `0700` | neutral homes; harness CWD is a controller-owned empty directory |
| `/var/tmp/pramana-foundry/slots/<slot>/<execution>` | matching slot, `0700` | execution-scoped home, session, cache, temp and disposable Git/object view |
| `/var/tmp/pramana-foundry/build/<build-id>` | `_pramana_build`, `0700` | untrusted hooks and build outputs |
| `/var/lib/pramana-foundry/runtime/<release-id>` | `_pramana_runtime`, `0700` state; release read-only | accepted runtime only |

Socket servers must verify kernel-derived peer credentials before capability validation.
Capabilities bind actor, role, execution, allowed operation/resource, candidate generation,
policy/control revision, revocation generation and expiry; only digests persist. The
operator steering credential is absent from every service account above.

### R3 kernel bundle protocol

Root never loads a candidate scheduler, reducer, replay implementation or recovery planner
into its BEAM. The exact admitted kernel artifact runs as `_pramana_kernel`, with IP
network denied, and connects only to `kernel.sock`. Its capability binds kernel artifact,
candidate, policy/control revision and current writer epoch. The versioned
`fr06-r3-bundle/v1` protocol permits only canonical-input queries and proposals for a
supported domain event, projection CAS, effect, schedule or recovery action.

The verifier retains the authenticated original command and raw receipts before kernel
interpretation, validates the complete revision read set and current writer epoch, and
derives protected values itself. A bundle containing budget balances, claim state, policy,
receipt/review/check validity, accepted/integrated/deployed pointers, activation pointer or
writer epoch is rejected before mutation. Unknown bundle/event/write versions fail closed.
A stale kernel connection cannot mint a new claim after epoch takeover. A valid exact-
candidate kernel repair can be independently checked and activated behind unchanged root
gates; bad kernel logic can block progress but cannot manufacture authority.

FR-15aB must prove a valid supported bundle commits and that forged budget/acceptance/
receipt fields, direct store access and a stale writer epoch are denied with no protected
mutation. FR-17/22 retain actual kernel upgrade/rollback acceptance. This section specifies
that boundary; no kernel artifact, protocol or OS isolation is implemented by FR-15aA.

## 3. Request reservation and settlement

Every first prompt, tool-loop continuation, retry, compaction/summarization request and
child request uses this authenticated sequence. A generic execution bearer is insufficient.

1. Root receives an admitted immutable assignment and atomically reserves one
   `model_requests` unit under R5 for `(execution_id, request_id)`. Insufficient, stale,
   unknown-quota or cancelled state returns blocked before contacting the harness.
2. Root creates the exact pending effect and moves it to R1 `claimed`, binding route,
   provider, account, billing class, profile, model, reasoning, endpoint operation,
   execution incarnation, semantic request ordinal, reservation and policy/control
   revisions. The harness receives only an opaque one-request capability.
3. The pinned harness connects to `auth.sock`. The gateway checks peer UID, capability
   digest, request body digest and immutable route. It rejects arbitrary URLs, headers,
   provider/model/profile changes, new sessions and duplicate/mismatched request IDs.
4. Immediately before the gateway may write provider bytes, it asks root to CAS R1
   `claimed→issued` and R5 `reserved→issued_unknown`. That commit is the one-request
   authorization boundary. A crash before it proves non-issue; a crash after it is
   ambiguous and must not retry blindly.
5. The gateway adds reusable authentication internally, strips it from response/logs and
   emits an attributable receipt. Confirmed delivery settles R5 to `consumed` regardless
   of response success. Proved non-delivery after issuer/channel quiescence releases the
   hold. Ambiguity remains `issued_unknown`/held while R1 is `unknown`.
6. A retry or hidden harness/provider retry needs a new request ID, ordinal, R1 claim and
   R5 reservation. Provider idempotency may improve reconciliation only after it is
   explicitly proved; it never bypasses reservation.

Authentication refresh is internal to `_pramana_auth` and conveys no model-execution
permission. Root loss stops new issues. Killing the local process cannot prove provider
non-delivery or refund a hold.

## 4. Tool, build, runtime and Git boundary

OMP starts from a neutral control directory with a fixed empty environment plus named
locale, time, session and socket values. It loads no candidate/user/project extension,
startup hook, executable project configuration, MCP server, skill, prompt library, prior
session or tool implementation. Candidate `AGENTS.md`, skills and prompts are input data
until separately admitted. A future Pi manifest must also reject CLI-explicit extensions
and account for bundled inline execution paths; discovery-disable flags are insufficient.

Model-directed read, search, edit, shell, build, test, language-service, background-job and
custom-tool actions cross `effect.sock` as bounded typed requests. Server-side policy
derives scope from the authenticated execution. It canonicalizes the resource beneath the
owned workspace, refuses traversal/absolute/symlink/hardlink/swap escapes, and sends one
fixed operation to the assigned worker. Untrusted tool output is data and cannot select a
route, request another capability or become an acceptance receipt.

Candidate and build workers receive a disposable clone/object view without the protected
common repository, refs, remotes, hooks, credentials or integration checkout. A candidate
commit or diff is rebound to exact controller-observed objects before it becomes evidence.
The build account receives immutable inputs and a new output root. The runtime account
receives only a root-selected immutable accepted release and service-specific state.

Acquisition is a separate R1/R5-governed operation. `_pramana_fetch` accepts only a
root-admitted immutable request containing URL, final host, redirect policy, expected
SHA-256, maximum bytes and destination object ID. It is not a forward proxy. Redirect,
host, digest or size mismatch fails closed; the root-owned object is exposed read-only to
the intended build. No installation or acquisition is authorized by FR-15aA.

## 5. Network, environment, descriptors and IPC

The host packet filter denies IP traffic by default for harness, presentation, slot,
build and runtime UIDs. The auth account may reach only the protected policy's provider
TLS address set and named resolver; the fetch account may reach only separately admitted
artifact destinations. Loopback IP is not a capability channel. Local services use the
listed Unix sockets, peer credentials and scoped capabilities. General HTTP CONNECT,
SOCKS, SSH agents, Git credential helpers, operator proxies and BEAM distribution are
absent.

Every launch uses an empty environment, never an overlay. The allowlist excludes all
provider/API variables, proxy variables, `SSH_AUTH_SOCK`, Git helper/config overrides,
package/runtime injection (`NODE_OPTIONS`, language startup files and loader variables),
operator-root variables and inherited temp/config/session roots. Homes, XDG roots, temp,
cache and session directories are inside the execution's owned root.

The launcher closes every descriptor except enumerated standard streams and the one
owned control descriptor; all others are `CLOEXEC`. Tests must repeat checkpoint F's
parent-only environment sentinels and FD 8/9 controls in OMP/Pi, explicit-extension,
shell, build-hook, LSP and runtime paths. Different UIDs plus absence of debugging
entitlements must deny signalling, inspection, task ports, shared memory and process
memory across root/auth/harness/presentation/other-slot processes.

## 6. Herdr presentation

Herdr remains the initial optional presentation backend. `_pramana_present` consumes a
sanitized one-way event feed and receives presentation identities independent of workflow
execution/session identities. Attach, pane liveness, pane closure and displayed completion
never establish an R1 outcome, ticket completion or acceptance. Presentation controls may
request an interrupt through the root protocol but cannot signal a harness/tool directly.

The presentation principal receives no operator shell environment, steering credential,
provider authentication, auth socket, effect capability, raw transcript store or candidate
write grant. Logs/status/crash output use bounded schemas and redact prompts, credentials,
capabilities and raw artifacts. FR-09 must prove installed Herdr attach/inspect/close
behavior and owned cleanup; the current same-user installation is not evidence.

## 7. Slot allocation, quiescence and cleanup

Allocation is a protected CAS from `free→preparing→assigned`, recording slot UID, role,
execution/incarnation, process group, owned paths/sockets, candidate generation, capability
digests and revocation generation. Preparation verifies a clean neutral home, empty owned
root, no processes/descriptors/listeners, packet-filter policy loaded and no prior session.
Any unknown observation quarantines the slot.

Cleanup first blocks new claims and revokes unissued capabilities. Already-issued R1
effects remain outstanding. The launcher requests cooperative stop, then bounded TERM and
KILL only for the recorded process group after rechecking its incarnation. It inventories
descendants, open files, sockets/listeners and owned roots. The slot becomes reusable only
after all issued work is terminal or explicitly reconciled, every process and descriptor
is absent, session/capability generations are revoked, and the exact execution root is
removed and observed absent. Foreign, recycled or uncertain identities are preserved and
the slot stays quarantined. Cleanup never scans or deletes a broad user/temp root.

## 8. Provisioning commands — operator/host authority required

These commands are a reproducible proposed procedure, not commands run by this ticket.
They require a maintenance window, root authority, reviewed FR-15aB artifacts and a host
whose UIDs/GIDs are still unused. Stop if any preflight fails. Replace no placeholder by
guessing: provider/fetch address sets and artifact hashes come from protected operator
policy and independent review.

### 8.1 Preflight and artifact verification

```sh
set -eu
source_checkout=/path/to/exact/source-at-f5067d9
spec_checkout=/path/to/independently-reviewed-fr15aa-candidate

# Source input and specification/tool provenance are deliberately separate.
test "$(git -C "$source_checkout" rev-parse HEAD)" = f5067d96d67a9ec3193a9b8bbadfa54c16525aa3
test "$(git -C "$source_checkout" rev-parse HEAD^{tree})" = f19af86efd775fa0debd75868f571b13feaa748d
test "$(shasum -a 256 "$source_checkout/foundry/mix.lock" | awk '{print $1}')" = bf2a61f815533a96b2abec87b1690ae49145bec56e60703a22b4db178c56e954
test -f "$spec_checkout/foundry/ci/validate_fr15aa.exs"
test -f "$spec_checkout/foundry/docs/fr-15a/provisioning-manifest.exs"
(cd "$spec_checkout/foundry" && elixir ci/validate_fr15aa.exs)

# Record the exact reviewed specification separately; operator approval supplies these.
test "$(git -C "$spec_checkout" rev-parse HEAD)" = "$APPROVED_FR15AA_COMMIT"
test "$(git -C "$spec_checkout" rev-parse HEAD^{tree})" = "$APPROVED_FR15AA_TREE"

# Must fail today: do not continue until reviewed FR-15aB artifacts exist.
test -x /staging/pramana-kernel
test -x /staging/pf-launch
test -x /staging/pf-auth-gateway
test -x /staging/pf-effect-bridge
test -x /staging/pf-fetch
shasum -a 256 /staging/pramana-kernel /staging/pf-launch /staging/pf-auth-gateway /staging/pf-effect-bridge /staging/pf-fetch
```

Compare the last five hashes with the independently reviewed manifest. The present
manifest says `unimplemented`, so the deliberate result is stop/blocked.

### 8.2 Accounts and protected directories

The fixed IDs below are part of host profile v1. First prove every name and numeric ID is
unused. The operator may approve a different collision-free table only by creating a new
profile revision and rerunning conformance.

```sh
set -eu

record_absent() {
  record_path=$1
  if record_output=$(dscl . -read "$record_path" 2>&1); then
    echo "collision: $record_path already exists" >&2
    exit 1
  else
    record_exit=$?
  fi
  if test "$record_exit" -ne 56 || ! printf '%s\n' "$record_output" | grep -q 'eDSRecordNotFound'; then
    echo "unknown: cannot prove $record_path absent (exit $record_exit)" >&2
    exit 1
  fi
}

if ! user_ids=$(dscl . -list /Users UniqueID); then
  echo "unknown: cannot list user numeric IDs" >&2
  exit 1
fi
if ! group_ids=$(dscl . -list /Groups PrimaryGroupID); then
  echo "unknown: cannot list group numeric IDs" >&2
  exit 1
fi

for pair in \
  _pramana_launcher:451 _pramana_auth:452 _pramana_harness:453 \
  _pramana_present:454 _pramana_fetch:455 _pramana_slot01:456 \
  _pramana_slot02:457 _pramana_slot03:458 _pramana_build:459 _pramana_runtime:460 \
  _pramana_kernel:461
do
  name=${pair%:*}; ident=${pair#*:}
  record_absent "/Users/$name"
  record_absent "/Groups/$name"
  if printf '%s\n' "$user_ids" | awk -v id="$ident" '$2 == id {found=1} END {exit !found}'; then
    echo "collision: user numeric ID $ident already exists" >&2
    exit 1
  elif test "$?" -ne 1; then
    echo "unknown: cannot evaluate user numeric ID $ident" >&2
    exit 1
  fi
  if printf '%s\n' "$group_ids" | awk -v id="$ident" '$2 == id {found=1} END {exit !found}'; then
    echo "collision: group numeric ID $ident already exists" >&2
    exit 1
  elif test "$?" -ne 1; then
    echo "unknown: cannot evaluate group numeric ID $ident" >&2
    exit 1
  fi
done
```

Before any account, policy or protected-path mutation, create a root-owned attempt ledger
in a newly allocated exact directory and record: attempt ID; source commit/tree;
specification commit/tree; operator policy revision; every account/group name and numeric
ID; every directory, file, launchd label, socket and packet-filter path; its observation as
`absent`, `present` or `unknown`; pre-change owner/mode/hash where present; backup path; and
later `created_by_attempt`/`modified_by_attempt` results. An unknown observation aborts.
The ledger directory records itself as newly created, is fsynced after each mutation, and
is copied into the final protected evidence store. Existing resources are never labelled
created by this attempt.

For `/etc/pf.conf` and an existing anchor, make root-owned same-filesystem backups, record
their hashes in the ledger and verify the copies before editing. Record absent launchd
labels and protected paths explicitly; if one is present, either stop or preserve it as a
preexisting resource under a separately reviewed migration—never overwrite and later
delete it as though this attempt created it.

After explicit operator approval and a complete all-known ledger, create all eleven
records with the exact name/ID table:

```sh
for pair in \
  _pramana_launcher:451 _pramana_auth:452 _pramana_harness:453 \
  _pramana_present:454 _pramana_fetch:455 _pramana_slot01:456 \
  _pramana_slot02:457 _pramana_slot03:458 _pramana_build:459 _pramana_runtime:460 \
  _pramana_kernel:461
do
  name=${pair%:*}; ident=${pair#*:}; short=${name#_pramana_}
  home="/var/empty/pramana-foundry/$short"
  sudo dscl . -create "/Groups/$name"
  sudo dscl . -create "/Groups/$name" PrimaryGroupID "$ident"
  sudo dscl . -create "/Users/$name"
  sudo dscl . -create "/Users/$name" UniqueID "$ident"
  sudo dscl . -create "/Users/$name" PrimaryGroupID "$ident"
  sudo dscl . -create "/Users/$name" UserShell /usr/bin/false
  sudo dscl . -create "/Users/$name" NFSHomeDirectory "$home"
  sudo dscl . -create "/Users/$name" IsHidden 1
  sudo mkdir -p "$home"
  sudo chown "$name:$name" "$home"
  sudo chmod 0700 "$home"
done
```

Then create protected roots:

```sh
sudo install -d -o root -g wheel -m 0555 /Library/PramanaFoundry/bin /Library/PramanaFoundry/manifests /Library/PramanaFoundry/releases
sudo install -d -o root -g wheel -m 0555 /Library/PramanaFoundry/releases/kernel /Library/PramanaFoundry/releases/kernel/CANDIDATE_SHA /Library/PramanaFoundry/releases/kernel/CANDIDATE_SHA/bin
sudo install -d -o root -g wheel -m 0700 /var/db/pramana-foundry
sudo install -d -o root -g wheel -m 0711 /var/run/pramana-foundry
sudo install -d -o root -g wheel -m 0711 /var/tmp/pramana-foundry /var/tmp/pramana-foundry/slots /var/tmp/pramana-foundry/build
sudo install -d -o _pramana_runtime -g _pramana_runtime -m 0700 /var/lib/pramana-foundry/runtime
sudo install -d -o _pramana_kernel -g _pramana_kernel -m 0700 /var/empty/pramana-foundry/kernel
sudo install -o root -g wheel -m 0555 /staging/pramana-kernel /Library/PramanaFoundry/releases/kernel/CANDIDATE_SHA/bin/pramana-kernel
sudo install -o root -g wheel -m 0555 /staging/pf-launch /Library/PramanaFoundry/bin/pf-launch
sudo install -o root -g wheel -m 0555 /staging/pf-auth-gateway /Library/PramanaFoundry/bin/pf-auth-gateway
sudo install -o root -g wheel -m 0555 /staging/pf-effect-bridge /Library/PramanaFoundry/bin/pf-effect-bridge
sudo install -o root -g wheel -m 0555 /staging/pf-fetch /Library/PramanaFoundry/bin/pf-fetch
```

Install reviewed root-owned launchd plists only after `plutil -lint` and digest comparison.
Each plist must set the exact `UserName`, neutral `WorkingDirectory`, explicit environment,
umask `077`, fixed executable/argv and no interactive shell. The root verifier/store is
the only root service. Never use `sudo -E`.

### 8.3 Packet filter and channel activation

Create a reviewed `/etc/pf.anchors/pramana-foundry` that blocks outbound traffic for
`_pramana_kernel`, `_pramana_harness`, `_pramana_present`, every `_pramana_slot*`,
`_pramana_build` and `_pramana_runtime`; permits `_pramana_auth` only to the protected provider TLS table and
resolver; and permits `_pramana_fetch` only to its separately admitted artifact table and
resolver. Add one `anchor "pramana-foundry"` and one matching `load anchor` line to
`/etc/pf.conf`. Before loading:

```sh
sudo pfctl -vnf /etc/pf.conf
sudo pfctl -a pramana-foundry -vnf /etc/pf.anchors/pramana-foundry
sudo pfctl -f /etc/pf.conf
sudo pfctl -E
sudo pfctl -a pramana-foundry -sr
```

Do not continue if this macOS release cannot parse, load and attribute the UID rules.
Hostname resolution at rule-load time is not a durable allowlist; protected policy must
maintain reviewed address tables and fail closed when stale/unknown. The actual denial
probes in section 9, not successful `pfctl` output, establish conformance.

Bootstrap services in dependency order: root verifier/store, launcher, restricted workflow
kernel, auth gateway, effect gateway, fetch service, then sanitized presentation. Verify socket owners/modes and
peer rejection before enabling any harness profile. OMP/Pi profiles remain disabled until
FR-15aB and FR-09 pass.

## 9. Required acceptance probes

FR-15aB must execute these with synthetic credentials and a deterministic fake provider
before any real subscription smoke. FR-09 separately owns the authorized installed-harness
subscription proof.

| Family | Positive probe | Required hostile probes |
|---|---|---|
| manifest/start | exact OMP digest starts from neutral CWD with assignment session | changed digest/config, candidate CWD, user/project config, startup loader, explicit extension and unknown setting refuse |
| workflow kernel | exact admitted kernel submits a supported versioned bundle and root commits it | direct SQL/root files, unknown schema/write, forbidden budget/claim/policy/receipt/acceptance fields and stale writer epoch refuse without protected mutation |
| request authority | one request has R5 reserve, R1 claim/issue and attributable fake-provider receipt | forged/duplicate ID, wrong peer/route/body, arbitrary URL/header, second OMP/curl, retry/continuation/compaction without a new reservation refuse |
| settlement | delivered consumes; proved non-delivery releases | gateway/root crash after possible issue stays unknown/held and cannot retry |
| tool bridge | developer read/edit and provider-free docs check complete in its slot | reviewer write, PM write, traversal, absolute/symlink/hardlink/swap, unknown tool/schema and oversized/ambiguous input refuse |
| extensions | admitted bridge schema is available | ambient/project/ancestor/CLI-explicit/bundled executable extension cannot run in harness |
| hooks/LSP/subprocess | declared build in `_pramana_build`; later pinned LSP in slot | hostile build/LSP hook cannot reach auth/root/Git/network; background/daemon descendant cannot survive cleanup |
| env/FD | exact allowlist and named channel present | checkpoint-F hostile variables and FD 8/9 absent in harness/tool/build/runtime; no inherited socket |
| network/proxy | auth fake endpoint and separately admitted fetch endpoint work | all slot/build/runtime/harness TCP/UDP/DNS/loopback/provider/proxy/SOCKS/CONNECT attempts fail |
| IPC/process | assigned capability socket operation works | root/auth/presentation/other-slot sockets, BEAM distribution, signal/debug/process-memory/shared-memory access fail |
| Git/state | disposable view supports scoped diff | common repo `HEAD`, refs, hooks, remotes, integration credentials, foreign sessions/caches/transcripts unavailable |
| role/reuse | developer, reviewer, PM, build and runtime get their exact scopes | renamed session/shared lineage cannot become independent; stale token/session/process cannot control reused slot |
| cleanup | owned descendants stop and exact root disappears | recycled/foreign/uncertain identity is preserved; uncertainty quarantines rather than reuses slot |
| presentation | sanitized attach/read/interrupt request works | pane closure is not completion; no operator shell, auth socket, raw secret or steering capability |

One representative useful conformance path is: developer performs a real scoped edit in
a disposable repository, `_pramana_build` runs the exact provider-free docs/compile/test
specification, root freezes an exact candidate, reviewer reads without write authority,
a correction is requested, a fresh developer execution produces a corrected candidate,
an independent reviewer returns a verdict, and cleanup proves every slot quiescent. This
is FR-15aB/FR-09 work. The checkpoint-F `80 passed` result is reusable raw feasibility
evidence, not this acceptance result.

## 10. Rollback procedure

Rollback is operator-owned and runs only after root has disabled new admissions, reconciled
or quarantined every issued effect, and archived the durable store/evidence. Never delete a
slot with an unknown issued provider, tool, build, Git or activation effect.

```sh
set -eu
ledger=/exact/root-owned/attempt-ledger.tsv
test -f "$ledger"

# Record exact state first. Every observer failure is unknown and blocks rollback.
sudo launchctl print system/org.pramana.foundry.root >/dev/null
sudo pfctl -a pramana-foundry -sr >/dev/null

# Boot out only labels recorded created_by_attempt=true, in reverse dependency order.
# The reviewed rollback helper reads the canonical ledger and refuses unknown ownership.
sudo /Library/PramanaFoundry/bin/pf-launch rollback-services --ledger "$ledger"

# Verify every account independently; present or observer error blocks removal.
for name in _pramana_launcher _pramana_auth _pramana_harness _pramana_present \
  _pramana_fetch _pramana_slot01 _pramana_slot02 _pramana_slot03 \
  _pramana_build _pramana_runtime _pramana_kernel
do
  if process_output=$(pgrep -U "$name" 2>&1); then
    test -n "$process_output" || {
      echo "unknown: pgrep returned success without identity for $name" >&2
      exit 1
    }
    echo "present: process remains for $name" >&2
    exit 1
  else
    process_exit=$?
  fi
  test "$process_exit" -eq 1 || {
    echo "unknown: pgrep failed for $name (exit $process_exit)" >&2
    exit 1
  }
done

if ! socket_inventory=$(sudo lsof -nP -U 2>&1); then
  echo "unknown: lsof could not inspect Unix sockets" >&2
  exit 1
fi
if printf '%s\n' "$socket_inventory" | grep -q /var/run/pramana-foundry; then
  echo "present: protected socket remains" >&2
  exit 1
else
  grep_exit=$?
fi
test "$grep_exit" -eq 1 || {
  echo "unknown: socket filter failed" >&2
  exit 1
}
```

Restore `/etc/pf.conf` and the anchor only from ledger-bound, hash-verified pre-change
backups, validate with `pfctl -vnf`, then reload. If the ledger says either file was absent,
remove only the exact file created by this attempt; if it was present, restore rather than
delete it. Move (do not destroy) newly created store/manifests/evidence into a root-owned
timestamped archive on the same filesystem. Preserve every preexisting path.

Only after verifying the archive and confirming no outstanding claim may the reviewed
rollback helper remove an exact resource whose ledger row says both `preexisting=false`
and `created_by_attempt=true`. Accounts/groups, paths and labels with any other or unknown
ownership remain untouched and produce `recovery_required`. Delete only the explicit
eleven user/group records actually created by this attempt; never use a wildcard or broad
recursive target. A partial install uses the same ledger, so it removes only completed
creation steps. If state migration prevents compatible restart, retain the archive and
report `recovery_required`; do not synthesize a healthy rollback.

## 11. Disposition and remaining authority

| Area | FR-15aA disposition |
|---|---|
| exact inventory, pins, topology, capability mapping, handshake, commands and rollback | **supported as validated specification** |
| checkpoint-F raw Pi lifecycle and provider-free docs path | **supported raw evidence only** |
| OMP subscription route, fixed gateway routing, disabled startup code and remote tools | **blocked; FR-09 after FR-15aB** |
| root/kernel/auth/harness/tool/build/runtime accounts, sockets, packet filter and protected paths | **blocked; requires operator/root host authority and FR-15aB artifacts** |
| R1 claims, R5 request reservations and settlement in accepted protected storage | **blocked; depends on FR-08A/B and FR-15aB** |
| actual environment/FD/network/proxy/IPC/process/Git/cross-slot denial | **blocked; FR-15aB conformance** |
| installed LSP (`expert`) | **unavailable; no installation attempted** |
| Herdr isolated presentation conformance | **blocked; FR-09/FR-15aB** |
| real provider entitlement, subscription billing, quota/fallback and hidden retry proof | **unavailable in provider-free work; separately authorized FR-09 smoke** |
| Pi adoption | **not selected; requires full candidate conformance, explicit contract revision and independent review** |

Until those gates pass, the safe operational result is no autonomous model execution.
Copied credentials, a same-user convention, a permissive mock, direct bearer calls or
paper-only claims cannot change any blocked result.
