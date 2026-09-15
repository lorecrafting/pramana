# Audit verification — 2026-09-12

Source audit baseline and limitations are in [the report](../AUDIT-2026-09-12.md).
These results characterize the inspected working tree, not the deployed release.

## Commands and outcomes

From `foundry/`:

```sh
MIX_ENV=test mise exec -- mix compile --force --warnings-as-errors
MIX_ENV=test mise exec -- mix format --check-formatted
HERDR_ENV=0 COORDINATOR_TICK=0 MIX_ENV=test mise exec -- \
  mix run --no-start docs/audit-2026-09-12/probes.exs
```

Compilation passed. Formatting failed on pre-existing files. The probes reported
`Result: 19 passed`; they assert defects deliberately and must not become ordinary
acceptance tests unchanged.

Existing suite isolation, equivalent to the clean audit run:

```sh
export FOUNDRY_AUDIT_ROOT="$(mktemp -d)"
mkdir -p "$FOUNDRY_AUDIT_ROOT/tmp"
export TMPDIR="$FOUNDRY_AUDIT_ROOT/tmp"
HERDR_ENV=0 COORDINATOR_TICK=0 MIX_ENV=test mise exec -- mix run --no-start -e '
  Application.put_env(:pramana_foundry, :runtime_root,
    Path.join(System.fetch_env!("FOUNDRY_AUDIT_ROOT"), "runtime"))
  Application.put_env(:pramana_foundry, :enable_tick, false)
  {:ok, _} = Application.ensure_all_started(:pramana_foundry)
  Mix.Task.run("test", ["--no-start", "--exclude", "integration", "--seed", "12092026"])
'
```

Fresh-directory outcome: `Result: 304 passed, 2 excluded`, ExUnit elapsed 52.3 seconds.
The initial run, with isolated runtime but the normal system temporary directory,
reported `Result: 294/304 passed, 2 excluded`, `Failed: 10 tests`. All ten were relocation
setup failures at an initial Git commit reporting `nothing to commit`, consistent with
retained directories named using VM-local unique integers. A fresh audit `TMPDIR`
resolved them without changing production or existing test source.

The two excluded integration-tagged tests are in `daemon_recovery_test.exs`; neither
establishes its advertised real lifecycle. Read the audit before running the companion
shell script, which truncates the fixed live log and closes all visible panes.

Read-only interface checks: `omp --help`, `herdr agent start --help`, compiler
`mix xref graph --format plain`, and one aggregate-state RPC to the existing daemon.
No model calls, release activation, or live fault injection were performed.

## Reproduction mapping

| Probe | Observed defect |
|---|---|
| A01 | Enqueue acknowledges failed append |
| A02 | Malformed tail erases valid history from recovered state |
| A03 | Pause/stop/public admission not durable |
| A04 | Exhausted handoff budget requeues on replay |
| A05 | Approved review artifact lost on replay |
| A06 | Valid rejected review crashes replay |
| A07 | PM-created work lost on replay |
| A08 | Old run timeout completes current attempt |
| A09 | Reviewer overwrites developer pane; coordinator telemetry rejected |
| A10 | CLI substitutes stale review identity; nonexistent candidate integrated |
| A11 | Ticket auto-approve creates synthetic approval |
| A12 | CLI block requeues instead of blocking |
| A13 | Tick admits work blocked by scheduler dependency policy |
| A14 | Execution defaults to paid OpenRouter |
| A15 | Startup requeues before inflight reconciliation |
| A16 | Board event-log mode drops recovered tickets |
| A17 | JSON argument encoding allows Elixir interpolation (arithmetic only) |
| A18 | Oversize valid history starts empty |
| A19 | Real Git handoff accepts omitted out-of-scope modification |

Local command logs, retained for this session, are under
`/tmp/pramana-foundry-audit-20260912/`: `suite.log`, `suite-clean.log`, `compile.log`,
`format.log`, `probes.log`, `xref.txt`, and `runtime.txt`. Temporary logs are supplemental;
the durable reproduction source, inventory, report and this result record are in the
repository. Inventory hashes identify the final audited source snapshot; modified docs
are labeled separately from production code. No raw provider credentials or live
transcripts were collected.
