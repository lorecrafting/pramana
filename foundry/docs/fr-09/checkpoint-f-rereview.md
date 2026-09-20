# Checkpoint F correction independent rereview — PASS

Reviewed 2026-09-19 (Hawaii). The exact correction candidate resolves the two
evidence-fixture blockers in the prior independent review. The corrected synthetic
probe is acceptable as checkpoint-F evidence: Pi, RPC Bash and the explicit startup
extension receive only the fixed launch allowlist, and Pi/Jiti/config/session/temp/cache
state remains beneath the probe-owned root and is removed after the processes exit.

This is a **PASS for checkpoint F only**. Pi remains blocked as a governed Foundry
execution harness. This review does not select Pi, replace OMP, close FR-09, FR-15aA or
FR-15aB, establish subscription conformance, authorize a provider smoke, or enable
automatic execution. OMP remains governing and Herdr remains the initial presentation
backend.

## Exact identity and bounded delta

- Correction candidate: `148476c93497653abbbc52fb040cf76927478d3f`;
  tree `e23217f94f295c115b893ac936c86ab719331647`.
- Candidate parent/original evidence candidate:
  `6582c9a79671af926bf49eb44b7faee54401ae74`;
  tree `beb34f73dd83bf07b31a0e6e78f4136841d71b14`.
- Original candidate parent: `5604afc4540e1bbab34bfbeec327f64ac0f6d8fc`;
  tree `5ac34ecb7375087916a6accaf8a6a4ecf04cbdea`.
- Prior BLOCKER review: `a306a59af850cb439628c70b261de516d583c078`;
  tree `2b6be59a2b4da25af7d927c32e1f703fecdfd86e`.
- Correction patch SHA-256:
  `8495626d470fd6b51cbb49adbc9b106ad26ed2da5302bcfa64db59a66ab95439`.
- Corrected feasibility report SHA-256:
  `b8e882c1feef7e1a22ae9f6e132ebb82f4db6dd2c5ed36037b78ba19d67d9e1e`.
- Corrected probe SHA-256:
  `c9a91bad8417314ce3ba0080562de4574425211d4fe25d3e68447a535cd83eea`.

The correction is the one direct child commit of the original candidate. Its delta
modifies only the feasibility record, its Elixir probe, and the Foundry documentation
route. It adds the empty-environment launcher and state/cache controls required by B1
and B2, adjusts only the corresponding claims, and leaves the credited raw lifecycle,
tool/path failures and production-blocked disposition intact. No Foundry runtime source,
provider adapter, model route, daemon, Herdr operation, installer or host configuration
is added or changed.

## B1 — resolved for the evidence fixture

`CheckpointF.RPC.start/3` now opens absolute `/usr/bin/env` with `-i`, supplies a fixed
list of `NAME=value` argv entries, and then invokes absolute `/bin/sh` with a constant
wrapper that immediately opens the deliberately synthetic FD 9 and `exec`s absolute
`/opt/homebrew/bin/pi`. `PATH` is fixed. Generated paths and the endpoint remain argv or
quoted environment data; Pi arguments are forwarded through `"$@"`. A strict rerun with
spaces and a literal quote in the outer `HOME` and `TMPDIR` passed, so the containment
does not depend on simple path spelling.

Before launch, the parent BEAM overwrites named provider, proxy, SSH-agent, Git-helper,
package/runtime and operator-root variables with synthetic hostile sentinels without
reading prior values. The explicit extension, executing in the actual Pi process, found
none of them and found the exact allowlisted synthetic values. RPC Bash independently
proved the same negative and positive environment cases. Because `/usr/bin/env -i`
clears all inherited names, the generic parent-only sentinel also covers unlisted
environment names; the category-specific names make the security-relevant cases visible.

An additional reviewer-owned descriptor probe started Elixir with synthetic inherited
FD 8 and exercised the same `/usr/bin/env -i` Port shape. Its child reported
`closed-fd8`; the BEAM Port did not forward that unlisted descriptor. The committed
probe still positively demonstrates the intended counterexample: its fixed wrapper
opens FD 9, the Pi-process extension reads it, and RPC Bash does not inherit it. The
report therefore correctly keeps unintended-descriptor closure and real principal
separation as production obligations instead of misstating the fixture as FR-15aB.

No real credential value was read. The outer review launches used `env -i`; the only
credential-like values were the committed synthetic bearer, allowlisted synthetic
secret and hostile synthetic sentinels.

## B2 — resolved for the evidence fixture

The launcher binds `HOME`, `TMPDIR`, `TMP`, `TEMP`, every XDG root, npm cache, Pi config
and Pi sessions beneath the single probe-owned root. The explicit extension executed as
before, and the probe positively found regular compiled Jiti output under owned
`TMPDIR/jiti`. Both Pi incarnations and the extension incarnation were closed before the
post-run cache comparison. The probe then removed only its exact root and asserted that
the root no longer existed.

The reviewer ran the probe inside a macOS sandbox that denied all file writes except the
review-owned temporary root, `/dev/null`, and the repository `test/` directory needed by
the deliberately invoked documentation check. It passed. The outer home and temporary
directories were empty afterward; no Pi process remained; and `git status --short`
remained empty. The test-directory exception did not hide retained state: the docs test's
known `.pilot-preflight-untracked-*` fixture was removed and the checkout stayed clean.

Exact pre/post name, type, mode, size, modification-time and file SHA-256 inventories
were identical for the three known ambient Jiti locations:

- `/private/tmp/jiti` retained the same five pre-existing files with the same metadata
  and content hashes;
- `/Users/raymondluong/.cache/jiti` remained absent;
- the installed Pi package's `node_modules/.cache/jiti` remained absent.

The sandbox's write denial additionally rules out an unobserved Pi/Jiti/config/session/
temp/cache write elsewhere during the successful run. No descendant survived the probe,
so there was no observed late writer after the snapshot or cleanup.

## Preserved evidence and governing boundary

The corrected probe again observed exactly two loopback requests at
`/v1/chat/completions`, both for `fixture-model` with the synthetic bearer. It preserved
the credited raw start/state, prompt acknowledgement before settlement, observation and
statistics, abort-to-idle, same-session restart, verified PID termination and direct RPC
Bash execution of `elixir bin/check_docs.exs` with `80 passed`.

It also preserved every material negative result: CLI-explicit startup code executes
despite `--no-extensions`; that Pi-process extension reads deliberately passed FD 9;
bundled inline command code remains visible; same-user process signalling and shared Git
metadata remain reachable; Pi sends the synthetic bearer directly; and neither request
has an R1/R5 claim or reservation handshake. These are expected blocked production
capabilities, not checkpoint-evidence failures.

The feasibility report still states that OMP governs, Pi is not selected, and the mock
cannot establish entitlement, quota, billing class, hidden-retry accounting or
subscription conformance. It leaves FR-09, FR-15aA and FR-15aB open and routes the real
principal, credential gateway, network/IPC, tool bridge, Git custody and slot-cleanup
work to those governing tickets.

## Commands, results and limitations

Representative commands ran from `/private/tmp/pramana-checkpoint-f`:

```sh
git status --short --branch
git rev-parse HEAD
git rev-parse HEAD^{tree}
git diff --name-status 6582c9a 148476c
git diff --check 6582c9a 148476c

env -i HOME=<owned-home> TMPDIR=<owned-tmp> \
  PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin LANG=C.UTF-8 \
  elixir foundry/docs/fr-09/pi_rpc_probe.exs

env -i HOME=<owned-home> TMPDIR=<owned-tmp> \
  PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin LANG=C.UTF-8 \
  sandbox-exec -p \
  '(version 1) (allow default) (deny file-write*)
   (allow file-write* (subpath "<owned-root>")
    (subpath "/private/tmp/pramana-checkpoint-f/test") (literal "/dev/null"))
   (deny network-outbound)
   (allow network-outbound (remote ip "localhost:*"))' \
  elixir foundry/docs/fr-09/pi_rpc_probe.exs

cd foundry && mix format --check-formatted docs/fr-09/pi_rpc_probe.exs
elixir bin/check_docs.exs
```

The plain empty-environment probe exited 0 with two loopback requests and `80 passed`.
The first write-denial attempt correctly exposed the docs check's intentional repository
test fixture and exited 1 at `79/80`; after granting only that test directory, the strict
probe exited 0 with the same JSON evidence. The strict quoted-path rerun also exited 0.
Formatting, the independent docs check (`80 passed`) and correction diff check exited 0.

The successful sandbox runs establish that these executions required no non-loopback
outbound connection and retained no write outside their stated allowances. They do not
prove a general OS network policy for future production, and an optional denied request
could have failed silently. The mock still cannot prove provider entitlement, billing,
quota, fallback or hidden retry behavior. No real provider/model, real credential,
process-memory read, live daemon, Herdr session, installation, host-account change or
full Foundry CI run was involved. Full CI was not repeated because the correction changes
only the standalone evidence probe and documentation, not Foundry runtime source.

**Verdict: PASS for checkpoint F correction candidate
`148476c93497653abbbc52fb040cf76927478d3f`.** B1 and B2 are resolved for the synthetic
evidence fixture. All named production capabilities remain blocked behind their existing
FR-09/FR-15a contracts.
