# Checkpoint F Pi feasibility independent review — BLOCKER

Reviewed 2026-09-19 (Hawaii). The exact checkpoint-F candidate has useful and
reproducible raw Pi RPC evidence, and its production-blocked disposition is correct.
It is not acceptable as the frozen checkpoint evidence yet because the committed probe
does not create the environment isolation it claims: the `Port` environment option is
additive, so unlisted parent variables continue into Pi, RPC Bash and startup
extensions. The probe also leaves Jiti's compiled extension cache outside its disposable
root. These are defects in the feasibility evidence itself, not the expected blocked
credential/tool/network capabilities that the report honestly records.

This review does not select Pi, replace OMP, close FR-09, FR-15aA or FR-15aB, establish
subscription conformance, authorize a provider smoke, or enable execution. OMP remains
the governing harness and Herdr remains the initial presentation backend.

## Exact reviewed identity and scope

- Candidate commit: `6582c9a79671af926bf49eb44b7faee54401ae74`;
  tree `beb34f73dd83bf07b31a0e6e78f4136841d71b14`.
- Candidate parent: `5604afc4540e1bbab34bfbeec327f64ac0f6d8fc`;
  tree `5ac34ecb7375087916a6accaf8a6a4ecf04cbdea`.
- Recorded source base: `fa636fb592eacf4ebd31b72fa377b0a86a6d3e3e`;
  tree `cef94fcad2cd5e169aaef2ef720f1253ec2b64c6`.
- Candidate report SHA-256:
  `ca7030c2131c2be0e6895616047fc8ca9f4e55b52e6f3684c84aa513a6285c90`.
- Candidate probe SHA-256:
  `11724c87efcb815604706ae62949d21ba1f5940753f2ceaf431859efe6c39094`.
- Candidate delta: only
  [`checkpoint-f-feasibility.md`](checkpoint-f-feasibility.md) and
  [`pi_rpc_probe.exs`](pi_rpc_probe.exs); the former was modified and the latter added.

The candidate checkout was clean at the named revision before review. The candidate
report and probe were not changed. This review branch adds only this review and its
documentation routes.

## B1 — the probe environment is an overlay, not an allowlist

`CheckpointF.RPC.start/3` passes a short list through `Port.open/2` as `{:env, env}`.
That option adds or replaces the named values; it does not clear unlisted variables from
the parent process. The `/bin/sh` wrapper then opens FD 9 and `exec`s Pi without an
intervening environment scrub. Consequently ambient provider credentials,
`SSH_AUTH_SOCK`, proxy settings and any other parent variables remain reachable by the
same Pi process in which the explicit extension executes and from which RPC Bash is
spawned.

A minimal reproduction using the same `Port.open` option set a synthetic variable only
in the parent and supplied a different one in `{:env, ...}`. `/usr/bin/env` in the child
reported both:

```text
CHECKPOINT_PARENT_ONLY=should-not-inherit
CHECKPOINT_CHILD_ONLY=set
status=0
```

No real credential value was inspected for this review. The candidate source does not
print a real credential value, and its controlled model configuration points at the
synthetic loopback bearer. Those facts do not prove that real credentials were absent
from the Pi/tool/extension environment during the recorded ordinary invocation
`elixir foundry/docs/fr-09/pi_rpc_probe.exs`. The report itself records that the earlier
investigation shell had a provider-secret variable name, but its command record contains
no parent scrub or negative control. Therefore the assertion that the fixture used
synthetic credentials in isolated state is not established safely enough to accept F.

Required correction: clear the environment in a trusted pre-Pi launcher, then pass only
the documented values. Add a synthetic parent-only sentinel and prove it is absent from
Pi, RPC Bash and an explicit startup extension. Explicitly remove provider, proxy,
keychain/agent and runtime override variables rather than assuming the `Port` option does
so. Refreeze the exact probe/report and repeat independent review. This correction is
about safe evidence collection; it does not convert credential separation into a pass.

## B2 — generated startup-code cache escapes the disposable root

After an otherwise successful isolated run, the candidate deleted its generated
`checkpoint-f-pi-*` root, but Jiti retained a compiled copy of `explicit.ts` at:

```text
<review TMPDIR>/jiti/checkpoint-f-pi-2595-explicit.8207b816.mjs
```

The residue contained only review-generated synthetic extension material; no real secret
was placed in the review environment. It is nevertheless an unreported write outside
the probe's `root`, so `File.rm_rf!(root)` does not make the run wholly disposable when
the caller uses its ordinary ambient temporary directory.

Required correction: bind `TMPDIR` and any candidate runtime/cache roots beneath the
owned probe root before Pi starts, inventory the post-run paths, and remove them after
the child has exited. Retain the useful finding that an explicit extension runs despite
`--no-extensions`; do not hide the extension to avoid its cache behavior.

## Credited raw protocol and isolation evidence

The exact probe passed repeatedly when the reviewer supplied an actually empty parent
environment. It also passed under a macOS sandbox profile that denied all outbound
network except localhost. The fixture received exactly two requests at
`/v1/chat/completions`, both for `fixture-model` and both with the synthetic bearer. This
establishes that the exercised path needs no non-loopback contact; it does not establish
general network isolation or prove that a denied optional request was never attempted.

| Claim | Independent disposition |
|---|---|
| start | Credited only as raw Pi process/state startup. The session ID is supplied by the fixture; there is no Foundry execution identity or R1 claim. |
| observe | Credited narrowly: an `agent_settled` event and a successful statistics response were observed. Statistics fields were not exhaustively validated and carry no authority. |
| prompt | Credited narrowly: the prompt response was observed before the later settlement event. Lost acknowledgement, duplicate semantic identity and R1 delivery remain untested. |
| interrupt | Credited narrowly: after the slow loopback request was observed, `abort` returned success and subsequent state was idle. Queued input, tools, descendants and remote non-delivery remain unproved. |
| reconcile | Credited narrowly: after terminating the first process, a new Pi process opened the same isolated session ID and file. This is not live reattachment, incarnation binding, foreign-session denial or execution authority. |
| close | Credited narrowly: `SIGTERM` was sent to the Port-owned Pi PID after RPC exchange and that PID became absent. Idempotent descendant cleanup and foreign/unknown preservation remain unproved. |
| useful model-free path | Credited as raw feasibility: direct RPC Bash ran `elixir bin/check_docs.exs` and reported `80 passed`. It is deliberately the same-user, unmediated path and therefore remains blocked for production. |

The discovery controls are also credible. Synthetic user and project extensions did not
write their markers, while the CLI-explicit extension did execute under
`--no-extensions` and read inherited FD 9. RPC Bash read its explicitly supplied
synthetic environment secret, could `kill -0` the reviewer-owned BEAM parent and could
read the checkout's shared Git `HEAD`. The Bash child did not inherit FD 9. The bundled
inline `llama` command remained listed. These observations support the report's blocked
extension, environment/FD, process and Git dispositions; they are not isolation passes.

The two synthetic model requests had no Foundry reservation/claim handshake. Current
Foundry source has no Pi adapter, protected request broker or isolated tool bridge, and
`PramanaFoundry.Herdr.Runner.System.subscription_route_capability/1` returns
`:unsupported`. The report therefore correctly keeps subscription routing, credential
separation, R1/R5 request authority and tool isolation blocked. A permissive loopback
server proves protocol feasibility only, not provider entitlement, subscription billing,
quota behavior, hidden retries or no-paid-fallback behavior.

## Executable inventory and governing-policy check

The installed identities reproduced without invoking a provider or live Herdr command:

| Component | Independent result |
|---|---|
| Pi | `0.85.1`; executable SHA-256 `e6d7fcf36a239cf3746e67ddf4222081ac01a601b85a3ee688bdfe9c161d754c` |
| Pi package | `package.json` SHA-256 `f1738e4b42203e5f22bcb513f13fb2fb224f1e98d1f129ff042f87048665a94c` |
| Pi production inventory | 186 manifests; offline `npm ls --omit=dev --all --json` SHA-256 `661ce1b6472d947977928059d6c6ae155dbd2941eee3affad2d922c29313f816` |
| Node / npm | Node `v26.8.2`, SHA-256 `902b6a6984d5d825829ea9064ab73b734548df37bc0683990dca31c8dc2a9253`; npm `11.19.1` |
| OMP | `omp/18.2.2`; SHA-256 `e0302a99643efefb62bf3d0601d5d84ebab6ed1f3ad105cc2874c8274af448a9` |
| Herdr | installed path is Homebrew `Cellar/herdr/0.9.0`; executable SHA-256 `7257396b19a082193cbf39b4805341eaddabb489d4dbbecaccbba00164339b87` |
| Review BEAM | Elixir `1.20.4`, OTP `29.0.6`, ERTS `17.0.6`; not the pinned CI patch level |

`expert`, `tmux` and `wezterm` remained absent. The offline npm inventory was run with
network denied. Herdr was not executed or connected; only its executable path/hash and
existing socket names were inspected. The auth and settings files were inspected only
for metadata (`0600` and `0644` respectively), never content. No provider/model account,
credential value, live Foundry daemon, live Herdr runtime, software installation, host
account, repository source or protected plan/log was changed.

The candidate and strategy language consistently leave OMP governing. The report does
not select Pi, close FR-09/15aA/15aB or treat the loopback fixture as subscription
conformance. Its supported/blocked distinctions are appropriately narrow apart from B1
and B2. The owning Foundry index still called the now-expanded candidate “partial”; this
review route replaces that stale label without changing the frozen candidate.

## Commands, checks and limits

Representative commands ran from `/private/tmp/pramana-checkpoint-f`:

```sh
git rev-parse HEAD
git rev-parse HEAD^{tree}
git diff --name-status 6582c9a^ 6582c9a

env -i HOME=<review-home> TMPDIR=<review-tmp> \
  PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin LANG=C.UTF-8 \
  elixir foundry/docs/fr-09/pi_rpc_probe.exs

env -i HOME=<review-home> TMPDIR=<review-tmp> \
  PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin LANG=C.UTF-8 \
  sandbox-exec -p \
  '(version 1) (allow default) (deny network-outbound) \
   (allow network-outbound (remote ip "localhost:*"))' \
  elixir foundry/docs/fr-09/pi_rpc_probe.exs

elixir bin/check_docs.exs
cd foundry && mix format --check-formatted docs/fr-09/pi_rpc_probe.exs
git diff --check 6582c9a^ 6582c9a
```

The two exact probe runs exited 0 and each reported the same supported/blocked JSON with
two loopback requests and `80 passed`. The independent docs check passed 80 tests; the
probe formatting and candidate diff checks exited 0. The npm inventory ran with
`npm_config_offline=true` and outbound network denied. Full Foundry CI was not rerun: no
Foundry runtime source changed, and this host's BEAM patch level differs from policy.

The sandbox run establishes no actual non-loopback connection for that run, not a general
Pi network-denial control. The mock cannot establish a real provider request, entitlement
or billing class. No process-memory read, foreign-process signal, live-session attach,
queued prompt case, tool-in-flight abort, crash recovery or real credential denial was
attempted. Review-owned temporary roots, including the observed Jiti cache, were removed
after recording their paths.

**Verdict: BLOCKER for B1 and B2.** Preserve the raw protocol results and every reported
production blocker. Correct only the probe's own environment/cache containment and the
corresponding evidence claims, refreeze the candidate, and request a new exact-candidate
review. The expected absence of production isolation is not itself a checkpoint-F
blocker; an unsafe, non-self-contained synthetic evidence fixture is.
