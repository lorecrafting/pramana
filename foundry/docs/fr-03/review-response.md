# FR-03 independent review response

Date: 2026-09-13 UTC (2026-09-12 Pacific/Honolulu)

This response addresses the four blockers in `review.md` (SHA-256
`8488281e04f347590b94d482bbc9929536e5d0255b5b3dec2e92f44ae5f293f0`).
The candidate remains based on `7aecf31c541ab1b1f3de4045ac3c487f6ef0708f`
and is intentionally uncommitted pending renewed independent review.

## Blocker disposition

### B1 — unterminated JSONL

Resolved at both read and write boundaries. `Import.read_jsonl/3` rejects every
nonempty JSONL file without a terminal newline. `EventLog.append/2` opens the
existing file for read/append, checks the byte immediately before EOF, and writes
nothing unless the boundary is empty or newline-terminated. Errors preserve the
original bytes and route Coordinator startup or mutation to recovery-required.

Tests cover a valid prefix followed by incomplete JSON and a valid prefix followed
by a complete JSON object lacking its delimiter. The latter also exercises direct
append refusal. A production-mode application subprocess verifies public recovery
status and retained useful prefix bytes.

### B2 — successor admission before old effects quiesce

Resolved by making `RuntimeOwner` own the complete effectful runtime subtree rather
than preceding it as a sibling. During clean shutdown, RuntimeOwner synchronously
stops that subtree, waits for termination, removes its unclean-owner marker, and only
then releases the OS fence. Any abrupt owner, subtree, or bridge loss leaves the
marker. A successor may obtain the now-free POSIX lock but must refuse admission on
that durable evidence; no PID text is treated as proof of ownership or cleanliness.
Clearing an unclean marker is deliberately not automated by FR-03 and requires the
later operator recovery protocol.

Tests prove clean quiescence before reacquisition using a trapping BEAM effect child,
kill the actual owning BEAM OS process with `SIGKILL`, and close the production
Fence bridge while an effect child is present. The hard-kill and bridge-loss cases
both reject automatic takeover; bridge loss observes the old child quiesce before
the owner-down handshake. The earlier Python bogus-lock helper was replaced with a
BEAM process using the existing production Fence. Fence's existing Python bridge
remains the sole external POSIX-lock boundary.

### B3 — permissive replay

Resolved in the single existing `Transition.rebuild/2` reducer. Schema failures,
unknown event types, projection errors, exceptions, and caught failures now halt
replay. Coordinator converts the result to visible recovery-required state before
ticks, mutations, startup appends, pane inspection, or cleanup can run. Exact
same-identity admission duplicates remain idempotently projectable and are retained
in the event projection; they are not discarded.

Tests cover unknown assignment prompt authority, run/role mismatches, missing
identity, schema-invalid terms, garbage terms, unknown event types, and retained
source bytes.

### B4 — hidden public recovery state

Resolved in the existing status and health projections. `Coordinator.status/1`
now includes `status` and `recovery_error`; `Coordinator.health/0` includes the same
fields alongside counts. Tests enter recovery through an injected authoritative
append failure and assert both public interfaces expose the state and reason.

## Multi-write containment and fault evidence

FR-03 does not claim transactionality for legacy multi-record operations:

- Tick handles at most one queue item per invocation. Its old post-effect
  `tick_processed` authoritative append is suspended and retained only as a
  diagnostic log entry. A later prelaunch append failure occurs before child start,
  enters the recovery boundary, and makes zero backend calls.
- Automatic startup re-enqueue/inflight reconciliation is suspended when replay
  finds dispatched or crashed authority. Startup enters recovery without appends or
  external pane operations; FR-07/FR-08 own transactional recovery.
- Legacy Git integration is suspended before intent append, runner invocation, or
  cleanup. FR-05/FR-07/FR-08 own truthful integration result settlement.
- Injected append failures cover accepted and rejected public handoff, accepted and
  rejected public review, and accepted PM proposal paths. None acknowledges new
  state, sends agent notifications, launches a child, or invokes a provider.

These suspensions do not implement the durable gateway, replay redesign, claims,
epochs, or Git activation work assigned to FR-07/FR-08/FR-10 and later tickets.

## Expanded implementation ownership

The original 13-file candidate remains owned. Review correction additionally owns:

- `config/config.exs`
- `lib/pramana_foundry/import.ex`
- `lib/pramana_foundry/event_log.ex`
- `lib/pramana_foundry/transition.ex`
- `lib/pramana_foundry/status/report.ex`
- `test/pramana_foundry/transition_test.exs`
- `test/pramana_foundry/stress_test.exs`
- `test/pramana_foundry/coordinator_test.exs`
- `docs/fr-03/review-response.md`

The config change permits an explicit `PRAMANA_OPERATOR_RUNTIME_ROOT` for isolated
validation while preserving the existing production default. Every executed test
set both immutable operator and active roots beneath a newly exclusive `/tmp`
parent, cleared `HERDR_ENV` and `COORDINATOR_TICK`, and used the pinned toolchain
directly. Runtime subprocess tests accept a checked `FR03_MIX_EXECUTABLE` or the
current checked PATH executable instead of embedding a workstation path.

## Executed evidence

All commands ran from the isolated FR-03 worktree with no live-root, daemon,
credential, Herdr, provider, activation, or remote operation.

- Fresh final-candidate compile parent `/tmp/fr03-final-compile.s4UIL0`:
  `MIX_ENV=test ... mix compile --warnings-as-errors` — exit 0, clean 73-file
  compile, generated application.
- Focused parent `/tmp/fr03-focused.1D7aBe`:
  runtime-root, startup-boundary, persistence-containment, transition, stress,
  status, and schema tests with seed `424209` — 56 passed, exit 0.
- Strict-replay follow-up parent `/tmp/fr03-replay.TtqyOz`:
  transition, stress, and persistence containment with seed `424211` — 32 passed,
  exit 0.
- Compatibility parent `/tmp/fr03-regression.FDFMAH`:
  autonomous-launch, Board, and Coordinator tests with seed `424208` — 39 passed,
  exit 0.
- Full-suite parent `/tmp/fr03-serial.H1qgUM`:
  `mix test --seed 424210 --max-cases 1` — 346 of 350 passed. The four failures are
  Board terminal rendering/refresh assertions that pass in the compatibility run
  above. This is recorded as an aggregate test-order/global-rendering limitation,
  not claimed as passing full-suite evidence.

The focused runs emit two pre-existing warnings in `stress_test.exs`; the clean
library compile has no warnings. No test process or PTY session remained after the
commands completed.

## Remaining limitations

- Unclean-owner evidence is intentionally fail-closed and has no automatic clearing
  path in FR-03. Operator-reviewed recovery remains required.
- No real Herdr/provider launch, credential flow, live daemon rollout, Git
  integration, or activation occurred.
- The full suite is not green because of the four aggregate-only Board failures
  described above; targeted Board coverage is green.
- This response is implementation evidence, not independent acceptance. The exact
  corrected bytes still require a fresh independent reviewer verdict.
