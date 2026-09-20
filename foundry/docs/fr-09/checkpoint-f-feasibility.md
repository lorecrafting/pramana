# Checkpoint F: Pi-first FR-09/FR-15aA feasibility

**Date:** 2026-09-19

**Source base:** `fa636fb592eacf4ebd31b72fa377b0a86a6d3e3e`
(`cef94fcad2cd5e169aaef2ef720f1253ec2b64c6`)

**Scope:** synthetic, provider-free local feasibility and executable-path inventory.

This record completes checkpoint F's bounded provider-free supported/blocked inventory.
It does **not** select Pi, replace OMP, close FR-09 or FR-15aA, enable automatic
execution, or establish provider/subscription conformance.
OMP remains the governing harness and Herdr the initial presentation backend. No
provider was invoked, no credential value was read or printed, no software was
installed, and the live Foundry daemon and Herdr runtime were not queried or altered.

## Frozen local inventory

| Component | Observed executable/version | SHA-256 / disposition |
|---|---|---|
| Pi | `/opt/homebrew/bin/pi`, `0.85.1`; symlink to global `@earendil-works/pi-coding-agent/dist/bundle/cli.js` | `e6d7fcf36a239cf3746e67ddf4222081ac01a601b85a3ee688bdfe9c161d754c`; installed but not bound by a controller-owned Foundry manifest |
| OMP | `/Users/raymondluong/.local/bin/omp`, `omp/18.2.2` | `e0302a99643efefb62bf3d0601d5d84ebab6ed1f3ad105cc2874c8274af448a9`; governing candidate, not exercised |
| Herdr | `/opt/homebrew/bin/herdr`, `0.9.0`; Homebrew `Cellar/herdr/0.9.0` | `7257396b19a082193cbf39b4805341eaddabb489d4dbbecaccbba00164339b87`; presentation only, not exercised |
| Pi runtime | Node `v26.8.2`, npm `11.19.1` | Node SHA-256 `902b6a6984d5d825829ea9064ab73b734548df37bc0683990dca31c8dc2a9253`; no Foundry candidate manifest exists |
| Foundry test runtime | Elixir `1.20.4`, OTP `29`, ERTS `17.0.6` | differs from CI policy Elixir `1.20.3`, OTP `29.0.5`, ERTS `17.0.5` |
| LSP candidate | `expert` absent | unavailable; no installation attempted |
| terminal helpers | `tmux` and `wezterm` absent | unavailable; Herdr is present |

Pi's installed `package.json` SHA-256 is
`f1738e4b42203e5f22bcb513f13fb2fb224f1e98d1f129ff042f87048665a94c`.
An offline `npm ls --omit=dev --all --json` inventory covered 186 installed production
package manifests and hashed to
`661ce1b6472d947977928059d6c6ae155dbd2941eee3affad2d922c29313f816`.
This is reproducible local inventory evidence, not a reviewed lockfile or provenance
chain. The design document's upstream Pi source reference is commit
`46c9de402bddf46b03c3b9f46487b777aaa41861`; this checkpoint did not establish that
the installed `0.85.1` bundle is that revision.

## Immediate Pi-first result

The installed Pi is **blocked** as a governed Foundry replacement candidate. Its raw RPC
surface is usable against a loopback-only synthetic endpoint, but it does not supply the
required authority/isolation boundary. `pi --help` advertises RPC output, explicit session roots,
`--offline`, and switches disabling tools, extensions, skills, prompt templates, themes
and context-file discovery. Those are useful adapter inputs, not isolation or authority.

The same help invocation tried to load the ambient user settings file and acquire
`~/.pi/agent/settings.json.lock` before printing help. The write failed only because the
investigation sandbox denied it. This is direct evidence that an ordinary invocation is
not yet a neutral, controller-owned loadout and that even version/help probing needs an
explicit isolated `PI_CODING_AGENT_DIR` in later fixtures.

The reproducible `foundry/docs/fr-09/pi_rpc_probe.exs` used a disposable home, config,
session and workspace; a synthetic bearer; `PI_OFFLINE=1`; telemetry disabled; and an
HTTP server bound to `127.0.0.1` on an ephemeral port. Two requests reached only that
fixture. No real provider/model or live daemon was contacted.

The probe established raw RPC start/state, prompt acknowledgement versus later
settlement events, observation/statistics, abort-to-idle, same-session restart and bounded
controller termination with verified process exit. It also executed the repository's model-free documentation check via
Pi's direct RPC `bash` command and observed `80 passed`. This proves a useful local path,
but the shell ran in Pi's same-user harness principal and is therefore evidence of the
missing tool-isolation boundary, not production conformance.

## Contract disposition

| Required capability | Result at this freeze | Exact evidence and required change |
|---|---|---|
| `start` / fresh execution identity | **Supported raw; blocked contract** | A disposable RPC process returned session state. The fixture supplied a session ID; Pi did not create a Foundry execution identity or R1 claim/receipt. Add the strict adapter, opaque execution/incarnation binding and issued-effect protocol. |
| `observe` | **Supported raw** | Events distinguished prompt response, agent settlement and idle state; session statistics were queryable. Add source/quality labels and bind every observation to execution/request/claim identity. |
| Subscription routing | **Unavailable / blocked** | A mock cannot establish subscription entitlement. Pi sent the synthetic bearer directly to the selected loopback endpoint. Add a protected fixed-route request adapter; then separately authorize a bounded real subscription smoke with fail-closed quota/fallback evidence. |
| `prompt` | **Supported raw; blocked contract** | Prompt returned success before later `agent_settled`, correctly demonstrating acknowledgement is not completion. Lost acknowledgement, duplicate request semantic idempotency and R1 request claims are not supplied by raw Pi. |
| `interrupt` | **Supported raw; blocked contract** | `abort` during a deliberately stalled loopback response returned only after idle. Queued messages, active tools, process loss, child work and attributable external non-delivery still require adapter tests and R1 reconciliation. |
| `reconcile` / session persistence | **Supported narrow; blocked contract** | Restart with the isolated session root recovered the same session ID/file. Live-process reattachment, incarnation proof, foreign-session denial and unknown possible provider outcomes remain unimplemented. Conversation continuity is not execution authority. |
| `close` / cleanup | **Supported narrow; blocked contract** | Controller `SIGTERM` ended the verified Pi PID and the probe observed process absence. Idempotent owned cleanup, tool/background descendants, uncertain resources and Herdr presentation cleanup remain separate requirements. |
| Credential separation | **Blocked** | The fixture's synthetic bearer was sent directly by Pi. A synthetic inherited environment secret was readable by RPC Bash; an explicit startup extension read an inherited FD. Real credential contents were never read. Put reusable authentication in another protected principal/gateway, scrub environment, close descriptors and deny auth files/keychains/process memory/IPC by OS policy. |
| Pre-request R5 reservation | **Blocked** | Both fixture prompts reached the endpoint without any Foundry reservation/claim handshake. Add protected per-request claims covering first prompt, continuations, retry and compaction, retaining unknown holds after possible issue. |
| Tool/extension/startup isolation | **Blocked** | Discovery flags denied synthetic ambient-user and project extensions, but a CLI-explicit extension executed despite `--no-extensions` and read an inherited FD. `get_commands` also exposed bundled inline `llama` extension code. RPC Bash read inherited environment, could signal the same-user probe parent and could read shared Git metadata. Add a manifest-enforced launcher and separate restricted worker principal; CLI flags alone cannot pass. |
| Useful local model-free build/test path | **Supported raw; blocked isolation** | Direct RPC Bash ran `elixir bin/check_docs.exs` and observed `80 passed`. This is technically useful but runs shell in the Pi principal, bypasses typed capability/R1/R5 mediation and therefore cannot be the production path. |

## Candidate-controlled execution-path inventory

The following paths must all be denied, mediated, or explicitly proved inert before
FR-15aA can pass. Current disposition is **blocked unless noted**.

- **Harness and startup configuration:** Pi is a Node program with ambient user settings;
  CLI permits provider/model/API-key selection, explicit extensions, skills, prompts,
  themes, file attachments and session selection. Discovery-disable flags are promising
  but not an OS boundary. The fixture denied ambient/project extension discovery, while
  a CLI-explicit extension still ran under `--no-extensions`; a bundled inline `llama`
  extension command also remained registered.
- **Built-in/custom tools:** direct file read/search/write/edit and Bash are advertised.
  `--no-builtin-tools` explicitly leaves extension/custom tools enabled. A malicious or
  mistaken extension can therefore execute in the credential-bearing Pi principal unless
  the bridge/loadout and OS topology prevent it.
- **Build hooks, language services and subprocesses:** Bash can spawn arbitrary children;
  candidate tests/builds can run hooks. `expert` is absent. These paths require the
  restricted worker and bounded argv/path/environment protocol; absence of Expert does
  not remove build-hook or subprocess risk.
- **Environment and file descriptors:** the initial investigation shell inherited the
  name of a provider-secret variable plus `SSH_AUTH_SOCK`; no real values were read. In
  the synthetic fixture, RPC Bash read an inherited environment secret. Its child did
  close the deliberately passed FD, but a CLI-explicit startup extension in the Pi
  process read that FD. A future launcher must use an allowlist and close inherited
  descriptors, sockets and proxy variables before any extension/startup code can run.
- **Network:** Pi supports direct provider requests and `--offline` is a voluntary process
  setting, not worker egress enforcement. Even with offline mode it made the configured
  loopback model requests and attached the synthetic bearer. This positively proves
  configured direct egress; denial of unauthorized destinations, proxies and DNS/socket
  paths requires OS policy and remains blocked.
- **IPC/process memory:** Pi, OMP, Herdr and the investigation run as the same Unix user.
  Herdr's user-owned sockets exist under `~/.config/herdr`; same-user permissions do not
  isolate harness capability, transcripts, process inspection/signalling or presentation.
- **Git/shared state:** this checkout is a Git worktree whose common metadata is outside
  the candidate directory. RPC Bash resolved the shared common directory and read its
  `HEAD`. Use disposable/mediated Git custody and bind evidence back to
  controller-observed objects.
- **Sessions/caches/logs:** Pi, OMP and Herdr retain same-user session/config/log roots.
  Several ordinary OMP/Herdr metadata and log paths are world-readable (`0644`) and Pi's
  settings are `0644`; confidential contents were not inspected. Assignment-scoped roots,
  retention/redaction and cross-assignment denial remain required.
- **Foundry source path:** current execution modules implement Herdr-specific launch,
  prompt, inspect, interrupt and pane cleanup over legacy checkpoints. There is no
  harness-neutral Pi behaviour, protected request broker, R5 request reservation adapter,
  or isolated tool bridge in the inspected source. Herdr's system runner explicitly
  reports subscription routing as unsupported.

Same-user directory modes, CLI tool hiding, a permissive mock, copied credentials or a
direct provider call cannot change any blocked result above.

## Commands and limits

Executed from `/private/tmp/pramana-checkpoint-f`:

```text
git status --short --branch; git rev-parse HEAD; git rev-parse HEAD^{tree}
command -v <candidate>; <candidate> --version; shasum -a 256 <candidate>
pi --help; omp --help; herdr --help
stat/find metadata for ~/.pi, ~/.omp, ~/.config/herdr (names/modes only)
env | cut -d= -f1 | sort | restricted name filter (names only)
elixir foundry/docs/fr-09/pi_rpc_probe.exs
HOME=<temporary> npm_config_cache=<temporary> npm ls --prefix <installed-pi> \
  --omit=dev --all --json | shasum -a 256
shasum -a 256 <Pi executable> <Pi package.json> /opt/homebrew/bin/node
```

No real user configuration, credential, session or log content was opened. Help output is
self-reported behavior, not protocol conformance. The sandbox-caused Pi lock error is
evidence of attempted ambient settings access, but not proof of behavior under a future
properly isolated principal. The fixture intentionally read only generated synthetic
secrets. It did not attempt process-memory reads; `kill -0` established same-user process
visibility/signalling authority without sending a signal. It did not establish OS-level
network denial, protected Git custody, provider entitlement, quota visibility, hidden
retry accounting, or a pre-request reservation boundary. No daemon query or live Herdr
command was run.

## Checkpoint conclusion and required next work

Checkpoint F's bounded provider-free feasibility inventory is complete: installed Pi has
a useful RPC/session surface, but the candidate is **blocked** for governed execution by
credential custody, pre-request reservation, explicit startup-code authority, shell/tool
isolation, same-user process/Git access, and absent enforced network topology. OMP remains
governing; Pi is not selected or substituted. The synthetic endpoint does not and cannot
establish subscription conformance.

FR-15aA should turn these results into an operator-reviewed provisioning specification:
separate root/auth-harness/tool principals, protected fixed-route request gateway,
per-request R1/R5 handshake, environment/FD scrubbing, deny-by-default network and IPC,
mediated Git/workspace custody, manifest refusal of explicit/unexpected extensions and
bundled execution paths, assignment-scoped sessions, and verified slot cleanup. Only
after those mechanisms exist should a separately authorized FR-09 smoke test the intended
real subscription route, quota/fallback behavior and hidden retries. FR-15aB must then
prove the actual isolation; this report closes neither parent ticket.
