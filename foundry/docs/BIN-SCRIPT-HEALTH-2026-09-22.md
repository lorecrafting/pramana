# Bin script health check — 2026-09-22

Baseline: `6bc015ed` on `repair/fr08b-kernel`. Every file in `foundry/bin/` and the repository
root's `bin/` was checked, run where that was cheap, and grepped for callers.

**Why.** [`a47613e7`](IMPLEMENTATION-LOG.md) found that `bin/refusal_sites.exs`'s red control
pinned absolute line numbers in `kernel.ex`. When the file shifted, the control went red on a
correct scanner. Nobody noticed, because the script is not in the gate. This pass looks for the
same shape everywhere else: a script's own self-check pinned to something that drifted.

**Result: no script's self-check had drifted.** Nothing in `foundry/bin/` needed that fix.
Other drift was found and is recorded below. None of it was changed except two stale restated
counts, which now point at the script.

**Who calls these.** `foundry/ci/run.exs` invokes **no** `foundry/bin/` script. The repository
gate for `bin/` is `.github/workflows/docs.yml`. It runs `bin/check_docs.exs`, the three
`check_pilot_*.exs --validate` checks and `sync_agent_conventions.exs --check`. "Test" below
means an ExUnit file that names the script. A comment that only mentions a script is not a
caller.

Commands were run one at a time. Mix scripts were run from `foundry/` with
`TMPDIR=/private/tmp`, `MIX_DEPS_PATH=<main checkout>/foundry/deps` and a scratch
`MIX_BUILD_PATH`.

## Foundry — `foundry/bin/`

| Script | Claims to measure (header) | How to run | Invoked by | Result on this tree |
|---|---|---|---|---|
| `refusal_sites.exs` | How many refusal sites in `kernel.ex` + `kernel/event.ex` are inside `require_*` definitions (sweepable), and how many are not | `elixir bin/refusal_sites.exs` | Nothing. `r4_coverage_test.exs` mentions it in a comment | **pass.** The red control passed (3 pins, by function and atom). It printed 75 sites: 48 inside `require_*`, 27 outside (9 in `do_transition`, 18 elsewhere). The control was also shown to fire: in a copy with `ok_or` renamed, it exits 1 with `RED CONTROL FAILED` |
| `contract_annotation_diff.exs` | That an ID-annotation pass changed no text in `WORKFLOW-CONTRACT.md` | `elixir bin/contract_annotation_diff.exs [rev]` | Nothing. `r4_rows.ex` and `r4_coverage_test.exs` mention it in comments | **pass.** Both red controls passed. 196 markers at HEAD and in the tree; `CONTENT PRESERVED` |
| `closure_probe.exs` | Which `(type, key)` corruptions `apply/2` accepts while producing a state `well_formed?/1` rejects. It is now a regression check: the result must be 0, with the BOUND line at "15 of 37 at depth 5" | `TMPDIR=/private/tmp mix run bin/closure_probe.exs` (depth 5; about 77 s here) | Nothing. `kernel_harness.ex` moduledoc names it as the regression | **pass, judged by reading the output; the exit code says nothing.** It printed `accepted-but-malformed: 0` and float control 0. BOUND was `15 of 37`, which matches the header. It tried 6,781,980 corruptions over 2,736 seeds. **It exits 0 whatever the count**, so a regression would not fail anything |
| `closure_cost.exs` | The cost of kernel property 6: `well_formed?/1` over accepted outputs, as a share of `apply/2` | `TMPDIR=/private/tmp mix run bin/closure_cost.exs` (about 6 s) | Nothing | **no self-check** (a timing). It printed 358 ms over 2,439 ms, **14.7%**. The header's figure (348 / 2,053 ms, 17%) is labelled as the recorded pre-change run, so the script does not reproduce it. The load average was about 10 during this run |
| `assessor_eval.exs` | Offline comparison of baseline and assessor orderings (usage line only; there is no descriptive header) | Documented: `mix run bin/assessor_eval.exs -- INPUT.json` | `assessor/evaluator_test.exs` only parses the file as Elixir; it never runs it | **fail as documented.** Run with `--` as documented, it exits 2 and prints the usage message, because `mix run` passes `--` through to `System.argv()`. Without `--`, it produced the expected JSON from the test's own case. It has no self-check. The same invocation is in the script's usage message and in [ASSESSOR.md](ASSESSOR.md). **Not fixed**: this is a usage error, not a self-check |
| `preflight.sh` | The cheap gate checks a focused `mix test` skips: sweep sentinel, clean tree, forced compile, test-file compile, format, machine quiet, TMPDIR | `bin/preflight.sh` | Nothing (by design). `freeze-evidence.sh` calls it | **pass** (exit 0). Two WARNs. One: 4 test-file warnings, all present before this pass. Two: 1 other suite process was running. Its logs go to fixed `/tmp/preflight-*.log` paths, which parallel sessions share |
| `test_daemon_recovery.sh` | Runs the FR-04 ownership/recovery fixture in isolation | `bin/test_daemon_recovery.sh` | Nothing. The test file it runs is in the suite | **pass.** Result: 1 passed at seed 40423. Its pinned mise paths (elixir 1.20.3-otp-29, erlang 29.0.5) match `mise.toml` and exist |
| `freeze-evidence.sh` | Preflight, then the full suite, delta check and an evidence block | `bin/freeze-evidence.sh [prev]` | Nothing | **not run.** It runs the full model-free suite, which this task excluded |
| `guard_mutation_sweep.exs` | Guard call sites whose neutralisation no test notices | `TMPDIR=/private/tmp elixir bin/guard_mutation_sweep.exs` | Nothing (by design; see [evidence tools](EVIDENCE-TOOLS.md)) | **not run.** It writes a global sentinel and takes about 1 hour. Read statically: its red control is a self-contained fixture, not pinned to `kernel.ex`. All 5 test paths it names exist. Its `Result: N passed` regex matches the formatter output seen today. Header drift: see below |
| `live_test.exs` | Nothing. Disabled by FR-05 | — | Nothing | **no self-check.** It raises as intended (exit 1) |
| `pramana-live.sh` | Nothing. Disabled pending FR-17 | — | `fr05_containment_test.exs` | **no self-check.** It refuses as intended (exit 78) |
| `tickets_from_review.sh` | Nothing. Disabled by FR-05 | — | Nothing | **no self-check.** `bash bin/tickets_from_review.sh` refuses as intended (exit 78). The file is tracked as mode 644, so `bin/tickets_from_review.sh` exits 126 (permission denied) instead |
| `pramana` | Not evidence: a CLI that RPCs into the running daemon | — | Nothing | **not run.** It would reach a live daemon |

## Repository root — `bin/`

| Script | Claims to measure | How to run | Invoked by | Result on this tree |
|---|---|---|---|---|
| `check_docs.exs` | Repository doc, layout, pilot and wrapper tests. No Mix deps, DB or models | `elixir bin/check_docs.exs` | `docs.yml` | **pass.** Run after this document was added; see the log entry |
| `check_pilot_preflight.exs` | The pilot preflight manifest is valid | `elixir bin/check_pilot_preflight.exs --validate` | `docs.yml`; `test/pilot_preflight_test.exs` | **pass.** `declared_status=blocked; readiness=not_evaluated` |
| `check_pilot_acceptance.exs` | The pilot acceptance contract is valid | `elixir bin/check_pilot_acceptance.exs --validate` | `docs.yml`; `test/pilot_acceptance_test.exs` | **pass.** revision 1, `frozen_pre_execution` |
| `check_pilot_participants.exs` | The participant protocol is valid | `elixir bin/check_pilot_participants.exs --validate` | `docs.yml`; `test/pilot_participants_test.exs` | **pass.** revision 1, `frozen_pre_recruitment` |
| `check_pilot_scope.exs` | A saved pilot scope artifact is structurally valid | `elixir bin/check_pilot_scope.exs --validate PATH` | `test/pilot_scope_artifact_test.exs`, which `check_docs.exs` runs against a generated artifact | **not run on data.** No saved artifact is tracked. The usage path exits 2 as intended |
| `check_local_layout.exs` | A read-only inventory of legacy-layout paths | `elixir bin/check_local_layout.exs [--root DIR]` | `test/local_layout_test.exs` | **pass** on the worktree, but vacuously: a worktree has no legacy data. With `--root` set to the main checkout it **exits 2 with 5 REVIEW paths**: `raw`, `priv/models`, `priv/embed/.venv`, `priv/plts` and `sources/local/huang-nianzu-jie/text`. The script is working; those paths are an operator finding for [LAYOUT_MIGRATION.md](../../docs/LAYOUT_MIGRATION.md) |
| `sync_agent_conventions.exs` | The agent conventions match the locked Phoenix | `elixir bin/sync_agent_conventions.exs --check` | `docs.yml`, `upstream-agent-rules.yml` | **pass.** Phoenix 1.8.11, reviewed 2026-09-16. Not run: `--review` and `--watch-main`, which need the network |
| `pilot_{preflight,acceptance,participants}.exs` | Libraries, not entry points | — | Loaded by `check_docs.exs` and the `check_pilot_*` CLIs | **no self-check.** Exercised through the rows above |
| `pramana-{mcp,mix,modal,tranche}` | Not evidence: `exec` wrappers into `pramana/` | — | `test/wrappers_test.exs` | **not run.** Covered by that test |

## Counts

These are counts of this table's rows, taken once at `6bc015ed`.

- Foundry (13 files): **pass 5** (`refusal_sites`, `contract_annotation_diff`, `preflight.sh`,
  `test_daemon_recovery.sh`, and `closure_probe` by reading its output only), **fail 1**
  (`assessor_eval` as documented), **no self-check 4** (`closure_cost` and the three disabled
  scripts), **not run 3** (`freeze-evidence.sh`, `guard_mutation_sweep.exs`, `pramana`).
- Root (14 files in 9 rows): **pass 6** (`check_docs`, the three `check_pilot_*` validators,
  `check_local_layout`, `sync_agent_conventions`), **no self-check 3** (the `pilot_*` libraries),
  **not run 5** (`check_pilot_scope` on data, and the four wrappers).
- **Self-check drift of `a47613e7`'s shape: 0 found, 0 fixed.**

## Header statements that no longer match what the script prints or does

- `closure_cost.exs` quotes 348 / 2,053 ms, 17%. That is labelled as the recorded pre-change
  run. The script printed 358 / 2,439 ms, 14.7%, under load.
- `guard_mutation_sweep.exs`, found by reading only (the script was not run):
  - Its usage line is `cd foundry && bin/guard_mutation_sweep.exs`, but the file is mode 644
    with no shebang. [Evidence tools](EVIDENCE-TOOLS.md) correctly uses `elixir bin/...`.
  - It says `SWEEP_WORKERS` defaults to 6. The code defaults to 4, and a comment beside that
    line explains why.
  - It copies trial trees with `cp -al ... deps`. In a checkout without `foundry/deps`, such as
    a fresh worktree, that fails.
- `assessor_eval.exs`: its usage message and ASSESSOR.md give an invocation that does not work
  (see the table).
- `closure_probe.exs`: "15 of 37 at depth 5" **matches**.
- `refusal_sites.exs`: the header states no count.
- `contract_annotation_diff.exs`: "32 from-cells" is not printed by the script and was not
  checked here.

## Restated counts

**Replaced with a pointer to `bin/refusal_sites.exs`.** The script printed 27 sites outside
`require_*` (9 / 18), so both of these were stale:

- The paragraph in [evidence tools](EVIDENCE-TOOLS.md) that followed `a47613e7`'s fix. It said
  "For those 24 … 9 are inline …; the other **15** …", with a list of functions, and "Two of the
  24". The history sentence "Then it was 24 with a disclaimer" was kept; it is history.
- A comment in `r4_coverage_test.exs` that said "One of 24 refusal sites outside that population".

**Recorded, not changed.** That paragraph also places `ok_or(:unknown_entity_kind)` at
`kernel.ex:80`; it is at `:89` on this tree. Line pins in prose, and in `r4_coverage_test.exs`
classification strings, drift the same way the red control did. Those are prose, not
self-checks, and were left alone.

## Gate candidates (recommendation only; nothing was added)

1. **`refusal_sites.exs`.** Pure Elixir, under a second, and its exit status comes from a red
   control. It is exactly the script whose control rotted unnoticed. Running it as an ExUnit test,
   or as a gate step, would have caught `a47613e7`'s breakage on the commit that caused it.
2. **`contract_annotation_diff.exs`.** Seconds long. Its red controls are what is worth gating.
   Against a clean HEAD its content check is trivially clean.
3. **`closure_probe.exs` at depth 5, only after it exits non-zero on a regression.** Today it
   exits 0 whatever `accepted-but-malformed` reads, so gating it would add 77 s that prove
   nothing. Its claim (0, with BOUND 15 of 37) belongs in an assertion.
4. **A test that runs each documented usage line once.** `assessor_eval`'s `--` would have
   been caught by one.
