# FR-03 renewed independent review

Verdict: **PASS for the immediate FR-03 containment contract. No implementation blocker found.**

Reviewed 2026-09-13 UTC against base
`7aecf31c541ab1b1f3de4045ac3c487f6ef0708f`, in the isolated candidate
`/tmp/pramana-fr03.YeVMZP/tree`. This supersedes the implementation disposition in
review v1 for the exact bytes inventoried below. It does not certify FR-07/08/10/15a,
authorize activation, or turn the existing component suite into lifecycle acceptance.
Shared completion documentation must still accompany integration; the current root
PLAN and REPAIR-PLAN correctly do not yet declare this uncommitted candidate complete.

The original review SHA-256 independently matches
`8488281e04f347590b94d482bbc9929536e5d0255b5b3dec2e92f44ae5f293f0`.
The correction response independently matches
`9b41e8c41505e5f6200a96c1fe004137d9b2ffe6cabcd54bd4b3a2b7a5a227e4`.
No implementation or test file was edited by this reviewer.

## B1–B4 disposition

**B1 resolved.** Import rejects nonempty history without a terminal newline before
replay. EventLog independently checks the existing final byte before writing, including
a complete JSON object lacking only its delimiter. Executed tests cover useful prefix
plus incomplete JSON, useful prefix plus complete JSON without newline, direct append
refusal, malformed/schema-version/oversize/directory failures, and real application
startup into visible recovery. Tested input bytes remain unchanged. This is preservation
and refusal, not automatic tail repair or a claim of transactionality/power-loss testing.

**B2 resolved for conservative successor admission.** RuntimeOwner now contains the
effectful supervisor, including assignment and task supervisors, Coordinator, Improver
and HardeningPM. Its clean termination synchronously stops that subtree before removing
the marker and releasing the POSIX fence. An independent slow-child probe held the child
inside shutdown while attempting acquisition: `{:error, :owned}`. After the child was
explicitly released, shutdown completed, acquisition succeeded and the marker was absent.
This challenges the ordering rather than merely checking that a child eventually exited.

The supplied application subprocess tests passed for two real BEAM owners, misleading
lock text, clean successor startup, SIGKILL of the actual owning BEAM process, bridge
loss with an effect child, and effect-free client startup. An additional independent
same-OS-process `Process.exit(owner, :kill)` probe left the marker and refused successor
RuntimeOwner startup with `{:unclean_runtime_owner, path}`. The unclean marker, not a
possibly stale/reused PID, prevents admission after uncertain loss. Bridge-loss tests
observe child quiescence before the owner-down handshake and refuse takeover afterward.
The code also conservatively retains the marker on subtree-loss exits and when a bounded
outer supervisor shutdown kills RuntimeOwner before its clean termination finishes.

There is intentionally no automatic unclean-marker clearing protocol. Obtaining a free
raw Fence is insufficient to start the runtime: RuntimeOwner must pass the marker check.
No claim is made that OS fencing alone cancels already-issued remote provider operations;
owned external effects and protected claims remain FR-10/15a. Arbitrary candidate code
with direct filesystem/process access is likewise not isolated by this interim fence.

**B3 resolved at the requested replay error boundary.** The existing Transition reducer
now validates records and halts on projection errors, unknown event types, schema errors,
exceptions and caught failures. Coordinator converts failure to recovery before ticks,
startup reconciliation or public mutations. Executed tests exercise unknown-assignment
prompt authority, role/run mismatch, missing identity, invalid terms and retained bytes.
Same-identity admissions remain explicitly projectable and retained. No second startup
reducer was added. This does not establish full live/replay equivalence: historical
projection semantics, clock-derived fields, PM/control reconstruction and stale lifecycle
events remain FR-08 obligations, including event branches that deliberately retain a
record without changing an absent assignment.

**B4 resolved.** Public status and health now carry `status` and `recovery_error`.
Executed public append-failure tests and the real startup recovery subprocess expose the
reason, rather than presenting inaccessible history as ordinary empty healthy work.
Board/offline projections are not thereby certified; FR-18 remains responsible for them.

## Append ordering and suspended work

Source inspection covered public enqueue, successful/rejected handoff, successful/rejected
review including reviewer retry, PM proposals, asynchronous pane/retry/park/completion/
crash handling, startup recovery helpers and Tick. The checked continuations occur after
successful append. Public handoff/review/PM fault tests return recovery errors, retain the
pre-command state apart from explicit recovery metadata, and send no tested notification.
Tick fault tests make zero fake backend calls for initial and later prelaunch append
failures. The later case attempts two appends and fails before child creation.

Tick now handles one queue item and has no authoritative post-effect summary append.
Its summary is diagnostic. Thus a successful first child's launch cannot be followed by
a second ticket's append failure in the same batch. The legacy integration entry point
refuses before intent append, Git runner or cleanup; its test verifies those boundaries.
Startup dispatched/crashed reconciliation is suspended before its old multi-write and
pane-recovery paths. These are bounded suspensions permitted by FR-03, not purported
atomic operations. Earlier successfully written records can remain when a later write
fails; recovery is explicit and no rollback is claimed.

Existing memory-only reset/pause/resume/stop/admission/reset-PM controls are not newly
durable. The recovery guard denies mutating public calls once an error is recorded, but
FR-07/08 must replace the legacy acknowledgment/replay contract, and FR-10 must reconcile
previously started effects. Actual storage-full/fsync faults were not injected; the
tests combine real directory/read/delimiter errors with injected append failures.

The F01–F24 routing matrix and WORKFLOW-CONTRACT are unchanged. Integration restoration
still requires FR-05 containment and FR-13/14 evidence, with FR-07/08 durability; startup
recovery requires FR-07/08/10. Scheduler progress/capacity remains FR-12, observability
FR-18, execution isolation FR-15a, and final lifecycle closure FR-22. Neither these
suspensions nor this PASS erase those obligations or permanently remove autonomy.

## Aggregate failures: independently diagnosed

The response's four Board failures are **pre-existing terminal-dependent failures**, not
evidence of an FR-03 regression. They also are not inherently aggregate-only: both the
candidate and clean base reproduce all four in the Board file alone at PTY width 80,
seed `424210`, max-cases `1` (11/15 in each). The failed assertions are all columns,
card titles, refresh ticket visibility and detail `Priority: P0`.

The unchanged rendering code uses ambient `Owl.IO.columns()` instead of the width
configured by the test. At 80 columns it displays only the selected backlog column;
queued cards therefore are absent from the rendered frame even when refreshed data is
correct. ANSI styling also separates the detail label and value, defeating the raw
substring assertion. Explicit ANSI enablement without a PTY reproduces only the detail
failure in both full suites. This provides a concrete cause and clean-base comparison;
passing a differently configured targeted run was not used as proof.

| Independently executed check | Candidate | Clean base |
|---|---|---|
| Full suite, seed 424210, max-cases 1, non-TTY default | 349/350, exit 2; repeated with same result | 324/325, exit 2 |
| Full suite, same seed/max-cases, ANSI explicitly enabled | 348/350, exit 2 | 323/325, exit 2 |
| Board only, same seed/max-cases, PTY columns 80 | 11/15, exit 2; four Board failures | 11/15, exit 2; identical four failures |
| Focused root/startup/persistence/transition/stress/status/schema files, seed 424209, max-cases 1 | 53 passed, exit 0 | Not run |
| Independent slow clean-child and same-OS owner-kill probe | Expected containment results, exit 0 | Not applicable |
| `git diff --check` | Exit 0 | Not applicable |

The common non-TTY full-suite failure is the unchanged Projections.BenchmarkTest:
the explicit Python PATH lacks `tiktoken`, so fallback token counts differ from its
saved result. Both exact-base and candidate runs fail that same assertion. No dependency
was installed and no saved benchmark was rewritten. Full-suite green is **not claimed**.
Board test isolation/rendering and benchmark executable provenance belong in FR-18/21/22
follow-up, retaining the existing F24 audit routing.

## Reproduction and safety boundary

All runtime roots and TMPDIR were beneath freshly exclusive
`/tmp/fr03-review-v2.o7Hbrt`. A clean base Foundry was extracted there with `git archive`
at the exact base SHA and used a private copy of the existing dependency source. No
live-root, daemon, credentials, real Herdr/provider, activation or generated escript was
accessed or changed. HERDR_ENV and COORDINATOR_TICK were cleared before each invocation.
Application configuration set Herdr to `/nonexistent/fr03-v2-herdr` before application
startup. Fake-runner tests retain their existing fake adapter identities.

The explicit PATH began with installed Elixir `1.20.3-otp-29/bin` and Erlang `29.0.5/bin`
under `/Users/raymondluong/.local/share/mise/installs`, followed by
`/opt/homebrew/bin:/usr/bin:/bin`. Main test runs used `MIX_ENV=test`, explicit private
operator/active roots and `PRAMANA_RUNTIME_ROOT_FRESH=1`. Tests were invoked with:

```elixir
Application.load(:pramana_foundry)
Application.put_env(:pramana_foundry, :herdr_command, "/nonexistent/fr03-v2-herdr")
Mix.Task.run("test", ["--seed", "424210", "--max-cases", "1"])
```

For clean base only, the bootstrap additionally sets `:runtime_root` to the private
environment root, since base does not implement the new resolver. ANSI probes additionally
set `Application.put_env(:elixir, :ansi_enabled, true)`. PTY probes use `stty cols 80 rows 24`
and add the Board test filename. Focused runs list the seven filenames described above.
Each invocation uses pinned `mix run --no-start`; no production application is implicitly
started before the overrides. The temporary `FR03_MIX_EXECUTABLE` wrapper adds the same
nonexistent-Herdr bootstrap to the supplied startup tests' independent BEAM subprocesses.
Those tests themselves select private dev-mode roots and explicit daemon/client modes.

The new candidate test helpers are Elixir/BEAM. The former Python bogus-lock fixture and
absolute installed Mix path are gone. The existing production Fence Python bridge remains
the POSIX-lock boundary. The literal `/tmp/fr03-checkout` in a fake ticket is an unused
fixture value, not a dependency on this review checkout or an external checkout's files.

Retained evidence under the private parent (SHA-256):

| Artifact | Hash |
|---|---|
| owner-probe.exs | `cf5d005c6ed375ac62ec73b92758e41d81cccea9e224d78a0ea9959b222a5438` |
| mix-wrapper | `264585fa9554b63432229913a694bb441b18dc9e357c0cf741f99f2454ff9661` |
| candidate.log | `623f8cfdd37f5745059b91a8a9aa21f33177fa549c09d25c50242b826a511b5f` |
| base.log | `7f8de057a8ef036be52d012689b35e2970c5d925c28dd94dc3aa69ade5addbaf` |
| candidate-color.log | `71c7ff14884fb312cb9f9b3c4f05577e5ac41b282fab2afecb949d20330c287f` |
| base-color.log | `8889946d9243d0963c4818e8060b290585a67dc69d2118b5f3c920569826cbf4` |
| focused.log | `085bb7fd776cad8eedc19197eb519db9e5966c9dd7c19e5e3981c27c09e0525d` |

The probe's first attempt lacked exit trapping and terminated on the expected failed
successor start; the retained corrected probe reran under a new private root and completed
all assertions/handshakes. No failed probe is presented as passing evidence. PTY Board
output is retained in the review tool transcript, not the files above.

## Exact candidate inventory

Paths relative to `foundry/`. Independently enumerated: 16 modified tracked files,
five untracked implementation/test files, and the two input review documents. This
new review is excluded from its own input inventory. Hashes below are SHA-256.

| File | Hash |
|---|---|
| config/config.exs | `d38fca63c3463b4bbbb5c56afcd66a900d4f6e4d5c5434bf3ec0157f372a7b16` |
| lib/pramana_foundry/application.ex | `35654ad4d19228fea06fdbb47bb714636b3dfbae3a09fef49bba5e3794737c9c` |
| lib/pramana_foundry/board.ex | `57b097d4cb7ad4ca1e2a10dbb0ab1862ccbae1b1ae25c7c34dca3757e32ae2c6` |
| lib/pramana_foundry/board/findings_panel.ex | `aaa8190073b2dd81a41ddd9c6bf00bd81849195159a1a48bed57480334da9977` |
| lib/pramana_foundry/consolidated_log.ex | `ff7eebb85bd34f39b0bf345432de3ca1ed4e7f1b6b62cc1bfa4f1b991352137c` |
| lib/pramana_foundry/coordinator.ex | `8798a52a679d65a5c416156878ba6c030c81134b685f66740d5cbc48cbcb74a7` |
| lib/pramana_foundry/coordinator/tick.ex | `00af5820712d7d3d018dd110440f6173e7cf81c567b9d113f336580d2a8ce03e` |
| lib/pramana_foundry/event_log.ex | `99f2389985bcb094428636774aeb4d13f8188874bdbec200664a007c76ce167d` |
| lib/pramana_foundry/fence.ex | `59ab62c203d29b2f0bf56133743f9bc3f4e4e4ce91113573844a59a880b4efb7` |
| lib/pramana_foundry/import.ex | `3cd3f7dee6bc279d3f27f76fb057d98a21b76112dc66e778d13883e6eeb0c9f3` |
| lib/pramana_foundry/improver.ex | `eeb5c8a353bac57409527ef4d90b7c898725d11c5d7a18d578b5530f14df186d` |
| lib/pramana_foundry/runtime_owner.ex | `48dea9fb7e64b279e64ca280eea16833faf259099f11df078f9bd73f88a0bbbc` |
| lib/pramana_foundry/runtime_root.ex | `1bf3fe5bd5de23ce3dbac85ffff887b6f913afd64662ea4008826116267683d2` |
| lib/pramana_foundry/status/report.ex | `f6da2b96af21b92087ad119ade3ad7db7efb0991784f72815a1e5e51f48efef2` |
| lib/pramana_foundry/transition.ex | `387baa673e5084c86c9d9d7eefcd1b6e03a13fad9ca3fbfdbb60a0fbb62ce92b` |
| test/pramana_foundry/coordinator_test.exs | `3ab10ccfae88aa7647b650ed05e636fc8c214151e96c62c048abab1ae2735e31` |
| test/pramana_foundry/legacy_persistence_containment_test.exs | `d71837a516b38bc8abb888b34a8eb5b0d9f6bfc6a5ba70cbeb430d0e3fc8340a` |
| test/pramana_foundry/runtime_root_test.exs | `676bcae97d52c9a832cb6474680e3ca48a9d355b2c15e67b2d498c2f71b50e3b` |
| test/pramana_foundry/runtime_startup_boundary_test.exs | `7d4406e850c420ccafe3ecc019549e4e4ca9bfa6f8c47da8d80e3ca171cdd743` |
| test/pramana_foundry/stress_test.exs | `506768777068737c471ec5cea36d0f677c674edd3a89a9d74feaf3e7e3a2c6ec` |
| test/pramana_foundry/transition_test.exs | `847ab60d3d0d53ccc7f37c7458c9a83aa7d01e7e055218a65ba2796e537688aa` |

Input review-document hashes appear at the beginning. Context included project
AGENTS/orientation, applicable RULES and CODE_CONVENTIONS, Foundry README, audit F02/F14,
REPAIR-PLAN FR-03/shared requirements and routing, WORKFLOW-CONTRACT authority/durability
and supersession, original review and correction response. Completion documentation
should publish the actual suspensions and conservative unclean-owner recovery, replace
the response's aggregate-only Board diagnosis with the evidence above, and preserve all
downstream acceptance gates. No implementation correction is requested by this review.
