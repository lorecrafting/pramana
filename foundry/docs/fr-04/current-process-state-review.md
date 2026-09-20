# FR-04/FR-10 current ProcessGroup correction review — PASS

Date: 2026-09-19 (Pacific/Honolulu)

## Exact review identity

- Reviewed candidate commit: `1495bca24e0d76b20fbbf633255e437df9783816`
- Reviewed candidate tree: `33cfb2fce1b8ef6b0541f691b2c5f15a399817b5`
- Implementation commit: `76f3a698e3bd5b733d44b065deda50cc1e44d941`
- Implementation tree: `b17d208ea8619c69f542c4c44f098f4cecb772eb`
- Comparison base: `25e109730bdb31fa475215813030d9b01ec43675`
- Comparison base tree: `e45118398763c22aa33a3544ad3b6c6366f6e69d`
- Branch: `repair/fr04-current-process-state`

The reviewed HEAD has the implementation commit as its parent and adds only
[`current-process-state-candidate.txt`](current-process-state-candidate.txt). This review
commit and report are review evidence on top of the candidate; they are not part of the
candidate verdict.

The four source/test path SHA-256 values in the candidate record were independently
recomputed and match. The requested `docs/CODE_CONVENTIONS.md` path does not exist in
this checkout. I followed the repository's current route through
`pramana/docs/CODE_CONVENTIONS.md`, `docs/agents/code-conventions/README.md`, and the
applicable Elixir/ExUnit conventions.

## Verdict

**PASS for the bounded current-revision FR-04 correction. No blocking finding.**

The candidate removes command-substring death inference and makes absence/zombie
decisions against the caller-bound PID, process-group ID, and start time. It fixes both
the failed-`kill` recheck and the `Checks.Runner.terminate/3` stale-identity recheck.
Observation failures and recycled/mismatched identities remain non-successful. The
change does not claim or implement FR-10 reconciliation.

This is not a full Foundry-suite pass. The independent standalone CI runs at both the
candidate and base exited 2 with the same 74 pre-existing macOS host-path failures.

## Correctness review

### State and identity

`ProcessGroup.identity/1` now asks `ps` for `state` and preserves it in the observation.
`presence/1` has the necessary three-way result:

- `:gone` only for an empty exit-1 observation (`:not_found`) or a `Z...` state whose
  PID, PGID, and start time match the bound incarnation;
- `:present` for a matching non-zombie observation, regardless of command text; and
- `:unknown` for an observation error, malformed observation, or any incarnation-field
  mismatch.

This distinction is fail-closed for cancellation success. The original base defect was
independently reproduced with a live BEAM argv containing `defunct`: base reported
`gone?: true`. The exact candidate reported state `Ss`, presence `:present`, and
`gone?: false` for the same positive control.

The committed real-process tests cover a live marker process, a forked and unreaped
zombie, and an absent PID. Injection tests cover a changed start time and observation
failure. An additional review probe varied each bound field independently: PID, PGID,
and start-time mismatches all returned `{:unknown, false}`, while the matching live and
matching `Z+` observations returned `{:present, false}` and `{:gone, true}` respectively.

### Observation failure versus absence

The exit-status handling no longer maps every `ps` failure to absence. An independent
PATH-controlled probe exercised the production `identity/1` command boundary:

- exit 1 with `ps: permission denied` produced `{:error, {:ps_failed, 1}}`, presence
  `:unknown`, and `gone?: false`;
- exit 1 with empty output produced `{:error, :not_found}`, presence `:gone`, and
  `gone?: true`.

Exit statuses other than 1 and parse failures also remain observation errors, hence
unknown rather than absent.

### Signal and cancellation callers

`signal/2` still requires the stronger PID/PGID/start-time/command equality immediately
before invoking `kill`. If `kill` then loses the race, its recheck now receives the
original expected identity rather than a bare PID. A replacement leader or failed
observation therefore cannot turn a failed signal into `:ok`.

`Checks.Runner.terminate/3` likewise changed its stale-identity fallback from
`gone?(identity.pid)` to `gone?(identity)`. Its regression test uses a live process whose
argv contains `defunct`, forges a different start time, obtains
`{:error, :stale_identity}`, and confirms the live incarnation remains. Existing real
runner tests still exercise successful cancellation of an owned session/process group.
No production caller outside this module currently invokes `Runner.terminate/3`.

### Scope

The diff from base is limited to the ProcessGroup predicate/identity implementation,
the one Runner caller, their regression tests, and the frozen candidate record. It adds
no backend activation, cleanup permission, daemon launch, provider use, or durable
effect state.

Leader absence or zombie state does not establish descendant, whole-process-group,
issuer, or delivery-channel quiescence. PID/PGID/start-time observation is still a
userspace `ps` snapshot rather than a kernel process handle. Those limitations are
accurately retained for FR-10; this PASS must not be used as FR-10 acceptance or as
permission for blind retry.

## Independent checks

All commands were run from the exact revisions named above with the repository-pinned
Elixir 1.20.3 / OTP 29.0.5 toolchain. Focused runs used an independent build, temp, and
runtime root under `/private/tmp/pramana-fr04-independent-1495`; the focused build reused
the already resolved locked dependency checkout. The standalone CI runs created their
own dependency and build roots.

1. `git diff --check 25e1097..1495bca` — exit 0.
2. `mix compile --force --warnings-as-errors` with isolated build/temp/runtime paths —
   exit 0.
3. `mix test test/pramana_foundry/effects/process_group_test.exs test/pramana_foundry/checks test/pramana_foundry/daemon_recovery_test.exs --seed 8021`
   — exit 0, `32 passed`.
4. `mix format --check-formatted` over the four changed source/test files — exit 0.
5. Detached-base live-argv reproduction — base reported the live marker gone; candidate
   positive control reported it present.
6. PATH-controlled diagnostic/absence probes and injected PID/PGID/start-time matrix —
   results as recorded above, all exit 0.
7. Exact-candidate standalone model-free CI:
   `mise exec -- elixir ci/run.exs --output /private/tmp/pramana-fr04-independent-ci-head1495`
   — exit 2; `478/552 passed, 1 excluded, 74 failed`; provenance SHA-256
   `8e3ecc2d3dacf0711daa613301b2f8d9642e5d375eba48a335294b48f7aa8346`.
8. Detached-base standalone model-free CI with the same harness — exit 2;
   `471/545 passed, 1 excluded, 74 failed`; provenance SHA-256
   `8d70e95fe52ad8ea14bb0d2c2f82c5bd7865708c9e719d8b18484192b0199274`.

For both CI logs, an independent block-by-block check found 74 failure blocks and zero
blocks lacking `:database_parent_symlink_not_allowed`. The CI runner's temporary root is
under macOS `/var/folders/...`; the durable-store guard rejects the symlink-traversing
parent. The candidate adds seven passing tests and no new failure. Because the model-free
suite failed, the escript stage did not run, and no complete-CI-pass claim is made.

## Limitations

- No provider, harness, live daemon, deployment, activation, or foreign-process signal
  was exercised. Real signals in the focused tests target only processes created by the
  test suite.
- The complete model-free suite remains red for the pre-existing macOS temporary-path
  issue described above.
- The zombie fixture requires the repository's existing POSIX/Python process boundary;
  no non-POSIX portability claim is made.
- Full descendant/effect reconciliation, issued-operation settlement, hard-kill recovery,
  and issuer/delivery-channel quiescence remain open under FR-10 and its prerequisites.
