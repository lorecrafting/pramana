# Checkpoint F: Pi-first FR-09/FR-15aA feasibility (partial freeze)

**Date:** 2026-09-19

**Source base:** `fa636fb592eacf4ebd31b72fa377b0a86a6d3e3e`
(`cef94fcad2cd5e169aaef2ef720f1253ec2b64c6`)

**Scope:** read-only/local evidence checkpoint; stopped early at the operator's request.

This record does **not** select Pi, replace OMP, close checkpoint F, close FR-09 or
FR-15aA, enable automatic execution, or establish provider/subscription conformance.
OMP remains the governing harness and Herdr the initial presentation backend. No
provider was invoked, no credential value was read or printed, no software was
installed, and the live Foundry daemon and Herdr runtime were not queried or altered.

## Frozen local inventory

| Component | Observed executable/version | SHA-256 / disposition |
|---|---|---|
| Pi | `/opt/homebrew/bin/pi`, `0.85.1`; symlink to global `@earendil-works/pi-coding-agent/dist/bundle/cli.js` | `e6d7fcf36a239cf3746e67ddf4222081ac01a601b85a3ee688bdfe9c161d754c`; installed but not bound by a controller-owned Foundry manifest |
| OMP | `/Users/raymondluong/.local/bin/omp`, `omp/18.2.2` | `e0302a99643efefb62bf3d0601d5d84ebab6ed1f3ad105cc2874c8274af448a9`; governing candidate, not exercised |
| Herdr | `/opt/homebrew/bin/herdr`, `0.9.0`; Homebrew `Cellar/herdr/0.9.0` | `7257396b19a082193cbf39b4805341eaddabb489d4dbbecaccbba00164339b87`; presentation only, not exercised |
| Pi runtime | Node `v26.8.2`, npm `11.19.1` | locally present; neither runtime is pinned by Foundry's candidate manifest because no such manifest exists |
| Foundry test runtime | Elixir `1.20.4`, OTP `29`, ERTS `17.0.6` | differs from CI policy Elixir `1.20.3`, OTP `29.0.5`, ERTS `17.0.5` |
| LSP candidate | `expert` absent | unavailable; no installation attempted |
| terminal helpers | `tmux` and `wezterm` absent | unavailable; Herdr is present |

The design document's upstream Pi source reference is commit
`46c9de402bddf46b03c3b9f46487b777aaa41861`; this checkpoint did not establish that
the installed `0.85.1` bundle is that revision. The executable digest above is therefore
the only frozen installed-candidate identity currently available.

## Immediate Pi-first result

The installed Pi is **blocked** as a governed Foundry replacement candidate on the
evidence collected so far. `pi --help` advertises RPC output, explicit session roots,
`--offline`, and switches disabling tools, extensions, skills, prompt templates, themes
and context-file discovery. Those are useful adapter inputs, not isolation or authority.

The same help invocation tried to load the ambient user settings file and acquire
`~/.pi/agent/settings.json.lock` before printing help. The write failed only because the
investigation sandbox denied it. This is direct evidence that an ordinary invocation is
not yet a neutral, controller-owned loadout and that even version/help probing needs an
explicit isolated `PI_CODING_AGENT_DIR` in later fixtures.

No `pi --mode rpc` process was started before this partial freeze. Consequently the RPC
wire protocol, event routing, acknowledgement semantics, abort behavior, session
reattachment, usage fields and malformed-frame handling remain **unavailable evidence**,
not failures attributed to Pi.

## Contract disposition

| Required capability | Result at this freeze | Exact evidence and required change |
|---|---|---|
| `start` / fresh execution identity | **Unavailable** | RPC exists in help only; no process fixture was started. Add a strict adapter fixture with an isolated config/session root, neutral CWD, exact executable digest and R1 start claim/receipt. |
| `observe` and subscription routing | **Blocked** | Help exposes direct `--provider`, `--model` and `--api-key` selection and many ambient provider environment variables; no Foundry route lock or positive subscription evidence was observed. Add a protected fixed-route request adapter and source-qualified observations; actual subscription proof remains a separately authorized smoke. |
| `prompt` and subscription/event routing | **Unavailable** | No RPC prompt was issued. Test accepted/queued versus completed events, request correlation, subscriptions, lost acknowledgement and duplicate request identity against the exact bundle. |
| `interrupt` / queued cancellation | **Unavailable** | No RPC abort was issued. Test active response, active tool, queued input, process loss and child/background work without equating an abort acknowledgement to closure. |
| `reconcile` / session persistence | **Blocked** | Pi exposes `--continue`, `--resume`, `--session`, `--session-id`, `--fork` and `--session-dir`; ambient `~/.pi/agent/sessions` exists under the same host user. Add assignment-scoped storage, incarnation binding, foreign-session denial and unknown-outcome handling. |
| `close` / cleanup | **Unavailable** | No Pi process was created. Add idempotent process/session/tool-worker cleanup with verified incarnation and preservation of unknown/foreign resources. Herdr cleanup must remain a separate presentation fact. |
| Credential separation | **Blocked** | `~/.pi/agent/auth.json` exists mode `0600`, but candidate tools currently share its owning Unix user; one provider-secret environment variable name was inherited by the investigation process. Contents were not read. Put reusable authentication in a different protected principal/gateway, scrub worker/harness environments, and deny auth files/keychains/process memory/IPC by OS policy. |
| Pre-request R5 reservation | **Blocked** | No Foundry Pi adapter or request broker exists in current source; Pi help offers direct provider calls. Add a protected per-request reservation/claim handshake covering first prompt, continuation, retry and compaction, with unknown holds after possible issue. |
| Tool/extension/startup isolation | **Blocked** | Built-ins include direct `read`, `bash`, `edit`, `write`, `grep`, `find`, and `ls`. Explicit extensions remain loadable even with discovery disabled; tools are selected by CLI flags, not an OS boundary. Add a pinned bridge/loadout and separate restricted worker principal; prove all model-visible resource paths cross it. |
| Useful local model-free build/test path | **Unavailable** | The stop request arrived before a Pi RPC/tool fixture or representative build/test path was run. A later fixture should run one registered Foundry check inside the restricted worker with synthetic secrets and controlled/no network, while Pi remains credential-free. |

## Candidate-controlled execution-path inventory

The following paths must all be denied, mediated, or explicitly proved inert before
FR-15aA can pass. Current disposition is **blocked unless noted**.

- **Harness and startup configuration:** Pi is a Node program with ambient user settings;
  CLI permits provider/model/API-key selection, explicit extensions, skills, prompts,
  themes, file attachments and session selection. Discovery-disable flags are promising
  but not an OS boundary and explicit extension paths remain active.
- **Built-in/custom tools:** direct file read/search/write/edit and Bash are advertised.
  `--no-builtin-tools` explicitly leaves extension/custom tools enabled. A malicious or
  mistaken extension can therefore execute in the credential-bearing Pi principal unless
  the bridge/loadout and OS topology prevent it.
- **Build hooks, language services and subprocesses:** Bash can spawn arbitrary children;
  candidate tests/builds can run hooks. `expert` is absent. These paths require the
  restricted worker and bounded argv/path/environment protocol; absence of Expert does
  not remove build-hook or subprocess risk.
- **Environment and file descriptors:** the investigation shell inherited the name of a
  provider-secret variable plus `SSH_AUTH_SOCK`; no values were read. A future launcher
  must use an allowlist and close inherited descriptors, sockets and proxy variables.
- **Network:** Pi supports direct provider requests and `--offline` is a voluntary process
  setting, not worker egress enforcement. Unauthorized direct egress, generic proxies and
  DNS/socket paths remain unproved and therefore blocked.
- **IPC/process memory:** Pi, OMP, Herdr and the investigation run as the same Unix user.
  Herdr's user-owned sockets exist under `~/.config/herdr`; same-user permissions do not
  isolate harness capability, transcripts, process inspection/signalling or presentation.
- **Git/shared state:** this checkout is a Git worktree whose common metadata is outside
  the candidate directory. A shell-capable same-user worker can potentially reach shared
  refs, hooks, remotes and other worktrees. Use disposable/mediated Git custody and bind
  evidence back to controller-observed objects.
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
```

No configuration, credential, session or log content was opened. Help output is
self-reported behavior, not protocol conformance. The sandbox-caused Pi lock error is
evidence of attempted ambient settings access, but not proof of behavior under a future
properly isolated principal. No network-denial probe, IPC/process-memory adversarial
probe, RPC fixture, build/test task, provider request, daemon query or live Herdr command
was run.

## Resume point

Next, create a temporary controller-owned Pi config/session root with synthetic secrets,
neutral CWD and controlled local endpoints; freeze the bundle plus transitive package
identity; then run the minimal RPC lifecycle fixture and executable-path denial matrix.
Do not proceed to a real subscription smoke until the protected route/reservation and OS
isolation topology exist and separate authorization is confirmed.
