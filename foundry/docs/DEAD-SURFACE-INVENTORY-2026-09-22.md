# Dead surface inventory — 2026-09-22

**This is an inventory only. It was taken at `6bc015ed` on `repair/fr08b-kernel`, and nothing was removed.**
It is input to the dead-surface part of
[FR-23](REPAIR-PLAN.md#fr-23--retire-legacy-surfaces-decompose-god-modules-and-restore-code-hygiene).
FR-23 says an identifier is removed only on "a recorded search showing no dispatch, not by
inspection alone". Every row below records that search. The rows are candidates, not
decisions: each still needs its owner's decision. Removal must also meet FR-23's other
conditions: the full suite passes before and after, and any revision-bound attestation is
rebound in the same commit.

**Ownership.** FR-08B owns legacy JSONL, `events.jsonl`, `EventLog`, all of `durable_store/`
and the Coordinator/State ingress it is routing through the kernel. FR-19B owns offline
relocation. A row owned by FR-10, FR-11 or FR-12 sits in a module that ticket rewrites.
FREE means the row sits outside every one of those scopes, so an early hygiene pass could
remove it.

## Method

Everything ran from the worktree's `foundry/` directory at `6bc015ed`, with
`TMPDIR=/private/tmp`, `MIX_DEPS_PATH` pointed at the main checkout's `deps` and a scratch
`MIX_BUILD_PATH`. `mix compile` succeeded on 121 files. No test ran.

1. **Call graph.** `Mix.Tasks.Xref.calls/0` lists every remote call edge in `lib/`, with
   its file and line. On Elixir 1.20.3 it prints a deprecation warning but still works.
   `mix xref callers` takes only a module on this Elixir, not an `M.f/a`. A function
   with an edge from another module counts as dispatched.
2. **Text search over every other caller surface.** Each exported function or macro with
   no remote edge was searched with ripgrep PCRE across `lib test bin ci config mix.exs
   ../bin`. The search looked for call shapes: `name(`, `&name/`, `|> name`, `.name`
   and the atom `:name`.
   - A hit in the defining file counts as a local caller unless the line is the
     `def`/`@spec`/`@doc` or a comment.
   - An atom-only hit in another file counts, because it covers `apply/3`, config atoms
     and function lists.
   - A bare hit in another file counts only if that file also names the module.

   The scan excluded:
   - `module_info`, `__info__` and `__struct__`;
   - protocol and exception functions;
   - every callback of every `@behaviour` the module declares, read from
     `behaviour_info(:callbacks)`. Callbacks count as dispatched.
3. **Manual confirmation.** Each survivor was re-searched with plain `rg -nwF '<name>'`
   over the same roots plus `rel/`. It was also checked against the xref edge list,
   including edges from the same module. The results are in the tables.
4. **Modules.** `mix xref graph --format dot` exported the whole file graph. Files with
   no inbound edge were then searched for their full module name and their short alias
   across every caller surface. The short-alias search catches `alias Foo.{Bar, Baz}`.
5. **List literals.** Every `@attr ~w(...)` and `@attr [:a, ...]` in `lib/` was expanded
   into its members. A member was reported when neither its string form `"x"`, its atom
   form `:x`, the keyword `x:` nor another `~w` list mentions it outside the defining lines.
6. **GenServer messages.** Every `handle_call`, `handle_cast` and `handle_info` message
   atom was checked for a sender. Every `GenServer.call` or `GenServer.cast` message atom
   was checked for a handler.

**Dynamic-dispatch sites checked.** `rg 'apply\(|String\.to_(existing_)?atom|Module\.concat|:erlang\.apply|function_exported\?|Code\.ensure_loaded|:rpc|erpc|Code\.eval'`
over every caller surface found the sites listed below. None of them reaches a FREE row.

- `apply(__MODULE__, :relocation_status, [])` at `relocation.ex:461`. This site takes
  `relocation_status/0` off the candidate list.
- `apply(PramanaFoundry.Coordinator, :receive_review | :receive_handoff, …)` in
  `agent_server.ex:335,369`.
- The adapter and transport modules held in config: `assessor.ex:20`, `assessor/jev.ex:198`
  and `herdr/adapter.ex:43`.
- The `FR08HandoffGate` provider probe at `fr08_handoff_gate.ex:149`.
- `String.to_atom` on relocation step kinds, and `Import.read/2` with
  `String.to_existing_atom` in `cli.ex:565`.
- The release `rpc` in `bin/pramana`. It evaluates only the fixed string
  `PramanaFoundry.CLI.RPC.run("…")`.
- The escript `main_module` and the application `mod` in `mix.exs`.

`config/config.exs` names no module or function atoms that dispatch. No Mix task is
defined under `lib/`.

**Known limits.**
- The text search leans conservative. A function whose name appears as a word in a file
  that also names its module is kept as used. The tables can therefore undercount dead
  surface, but a row that is listed is not overstated.
- A hand-written call such as `PramanaFoundry.Board.inspection()` from an operator remote
  shell can't be searched. No document instructs one for any FREE row.
- An attestation binds a file by its source SHA-256 and its BEAM MD5. That binding matters
  more for the owned rows than for the FREE rows.

## FREE — removable in an early hygiene pass

| File:line | Identifier | Search and result | Dynamic-dispatch risk checked | Owner |
|---|---|---|---|---|
| `lib/pramana_foundry/assessor/result.ex:89` | `Assessor.Result.statuses/0` | xref edges: none. `rg -nwF statuses lib test bin ci config mix.exs ../bin rel` finds only the `@statuses` attribute (line 12), this def and the `when status in @statuses` guard (line 91). Every other hit is a local variable in `workflow/kernel.ex` or test prose. No `Result.statuses` or `:statuses` appears anywhere | The assessor adapter is chosen dynamically (`assessor.ex:20`), but the dispatch goes to `assess/2`, not to this function | FREE |
| `lib/pramana_foundry/assignments/handoff.ex:96` | `Assignments.Handoff.max_blocked_bytes/0` | xref edges: none. `rg -nwF max_blocked_bytes …` gives 1 hit, the def itself. The attribute `@max_blocked_handoff_bytes` stays in use inside the module | No atom, `apply` or reflection. Note: the file sits on the handoff ingress that FR-08B and FR-11 will touch. Removing the accessor changes no behaviour | FREE |
| `lib/pramana_foundry/board.ex:118` | `Board.inspection/0,1` (one def with a default) | xref edges: none. `rg -nwF inspection …` finds prose, test names and this def. `rg -n 'Board\.inspection'` over the whole repo, docs included, finds nothing | The CLI and `bin/pramana` RPC table don't dispatch it. It is reachable only by a hand-typed remote-shell call, and none is documented. Not a GenServer message | FREE |
| `lib/pramana_foundry/board.ex:125` | `Board.inspection_status/0,1` | xref edges: none. `rg -nwF inspection_status …` gives 1 hit, the def | Same as the row above | FREE |

**Removed 2026-09-22 (FR-23a).** `Board.inspection/0,1`, `Board.inspection_status/0,1`
and `Assessor.Result.statuses/0` were removed at `4aa7ef30`, together with the
`Board.Inspection` alias that only they used. The searches were re-run on that tree first
and are quoted in the commit message: no xref edge, and no call shape anywhere in the
repository, docs included, outside this inventory. `Assignments.Handoff.max_blocked_bytes/0`
stays; its file is on the handoff path FR-08B and FR-11 rewrite.

What removing these rows leaves behind: `Board.Inspection.format/1` and `status/1` become
test-only (see [test-only callers](#test-only-callers--not-candidates)). Those tests would
then be the only evidence that attach instructions still work.

## FR-08B — durable store, kernel and Coordinator/State ingress

| File:line | Identifier | Search and result | Dynamic-dispatch risk checked | Owner |
|---|---|---|---|---|
| `lib/pramana_foundry/coordinator.ex:31` | `Coordinator.replace_projection/1` | xref edges: none. `rg -nwF replace_projection …` gives 1 hit, the def. **It sends `{:replace_projection, records}`, and no `handle_call` clause matches that message.** The recovery catch-all at line 277 matches only while `recovery_error` is set, so on a healthy server the call would crash the Coordinator. FR-08B has already recorded this in [the ingress inventory](fr-08/fr08b-ingress-inventory.md) | GenServer message: the sender side exists, the handler side is absent | FR-08B. This is a recorded defect, not only dead surface |
| `lib/pramana_foundry/coordinator/state.ex:350` | `Coordinator.State.integrate_candidate/2,3` | xref edges: none. `rg -nwF integrate_candidate …` gives 2 hits, the `@spec` and the def. `Coordinator.handle_call({:integrate, …})` (line 564) returns its own suspension error and never calls it. `EVENT_SOURCING.md:142` still names it as a suspended path | No atom or `apply`. Its message names FR-13 and FR-14 as the restorers of verified promotion | FR-08B (Coordinator/State ingress). Removing it also needs FR-13/14 and the `EVENT_SOURCING.md` route updated |
| `lib/pramana_foundry/durable_store/kernel.ex:6-7` | `@callback decide/2`, `@callback apply/2` on `DurableStore.Kernel` | `rg -n '@behaviour' lib test`: no module declares `@behaviour PramanaFoundry.DurableStore.Kernel`. The behaviour has no implementer | These are callbacks, so they count as dispatch surface. But nothing implements them, so nothing can dispatch through them | FR-08B. The file is attested by `FR08AProtectedBoundary` and `H0AcceptedFR07Boundary` |
| `lib/pramana_foundry/durable_store/kernel.ex:9` | `DurableStore.Kernel.validate_bundle/1` | xref edges: none. `rg -nwF validate_bundle …` gives 1 hit, the def. `DURABLE-STORE.md:24` and `fr-07/diagnosis-v3.md:19` still describe it | None | FR-08B. The file is attested, and a doc route needs updating |
| `lib/pramana_foundry/durable_store/database.ex:362` | `DurableStore.Database.protected_schema_version/0` | xref edges: none. `rg -nwF protected_schema_version …` finds only the metadata key string and the `@protected_schema_version` attribute. No call to the function exists | The name also appears as a SQL key and a map key. Those are strings, not calls | FR-08B. The file is attested by `FR08AProtectedBoundary` |
| `lib/pramana_foundry/durable_store/owner.ex:70` | `DurableStore.Owner.sidecars/1` | xref edges: none. `rg -nwF sidecars …` finds the def and two test names that are prose | None | FR-08B |
| `lib/pramana_foundry/durable_store/record_codec.ex:591` | `DurableStore.RecordCodec.reduce_projection_plan/2` | xref edges: none. `rg -nwF reduce_projection_plan …` gives 1 hit, the def | None | FR-08B. The file is attested by both boundaries |
| `lib/pramana_foundry/durable_store/transition_plan.ex:267` | `DurableStore.TransitionPlan.discriminator_kinds/0` | xref edges: none. `rg -nwF discriminator_kinds …` finds the attribute, the `@spec`, the def and the attribute's use in a guard. Its sibling accessors (`operation_types/0` and others) are test-only | None | FR-08B |
| `lib/pramana_foundry/workflow/kernel/state.ex:84` | `Workflow.Kernel.State.attempt_phases/0` | xref edges: none. `rg -nwF attempt_phases …` finds the attribute, the def and the attribute's use in a guard | Its siblings are used by `kernel.ex` and the property tests, so this one belongs to a uniform accessor set | FR-08B, kernel under active review |
| `lib/pramana_foundry/workflow/kernel/state.ex:87` | `Workflow.Kernel.State.execution_results/0` | xref edges: none. `rg -nwF execution_results …` finds the attribute, the def and the attribute's use in a guard | Same as `attempt_phases/0` | FR-08B |
| `lib/pramana_foundry/workflow/kernel/state.ex:90` | `Workflow.Kernel.State.roles/0` | xref edges: none. `rg -nwF roles …` finds no call to `State.roles`. Every hit is another module's `@roles` or a local variable | Same as `attempt_phases/0` | FR-08B |
| `lib/pramana_foundry/durable_store/record_codec.ex:19` | `@command_types` members `reset`, `propose`, `submit_artifact`, `submit_review`, `steer`, `cancel`, `record_receipt` | For each member v, `rg -c -F '"v"' lib` = 0 and `rg -l -F '"v"' test bin ci` = 0. Nothing produces a command of these types anywhere | These are validation vocabulary for persisted command records, so dropping one changes which stored records validate. That is a persisted-format change, which FR-23 excludes. The atom `:reset` is live as a Coordinator message and a CLI command, but it belongs to a different vocabulary | FR-08B |
| `lib/pramana_foundry/durable_store/record_codec.ex:19` | `@command_types` members `enqueue`, `pause`, `resume`, `request_effect` | `rg -c -F '"v"' lib` = 0 for each. Test files contain them: `enqueue` 1, `pause` 2, `resume` 1, `request_effect` 7. **These are test-only.** `legacy_event_append` is produced in `lib/` by `compatibility_writer.ex` | Same as the row above | FR-08B |
| `lib/pramana_foundry/durable_store/record_codec.ex:28` | `@legacy_event_types` members `ticket_steered`, `ticket_paused`, `ticket_resumed`, `ticket_cancelled`, `receipt_recorded` | The list-literal scan found no string, atom or keyword use outside line 28 | The code comment says: "Never remove, rename or re-point a member; stored histories depend on these names". The list is required compatibility and already says so | FR-08B (legacy JSONL). Not removable |
| `lib/pramana_foundry/durable_store/record_codec.ex:48` | `@intent_types` members `activate`, `git_update` | The list-literal scan found no use outside line 48 | These are validation vocabulary for persisted intents, used at line 150, so removing one is a format change | FR-08B |

**Plan claim, reconciled.** The FR-23 evidence taken at `9dd30c3` says `reset`, `propose`,
`submit_artifact` and `submit_review` have zero uses. At `6bc015ed` that holds for their
command-type string form, and three more members are also unused anywhere: `steer`,
`cancel` and `record_receipt`. Four others are used only by tests.

## FR-19B — offline relocation

| File:line | Identifier | Search and result | Dynamic-dispatch risk checked | Owner |
|---|---|---|---|---|
| `lib/pramana_foundry/relocation/digest.ex:17` | `Relocation.Digest.hash_file/1` | xref edges: none. `rg -nwF hash_file …` finds the `@spec` and the def. `MIGRATION-TICKETS.md:327` names it historically | Relocation turns step kinds into atoms with `String.to_atom`, but only as data, never as function names | FR-19B |
| `lib/pramana_foundry/relocation/local_exclude.ex:174` | `Relocation.LocalExclude.tracked_ignore_present?/1,2` | xref edges: none. `rg -nwF 'tracked_ignore_present?' …` finds the `@spec` and the def. `MIGRATION-TICKETS.md:334` names it historically | Same as the row above | FR-19B |

## FR-10, FR-11 and FR-12

No function candidate falls in a module those tickets rewrite. That means launch and
effects, AgentServer and correction, and Tick, scheduler and admission.

## Kept off every list because something dispatches them

| File:line | Identifier | Why it is not dead |
|---|---|---|
| `lib/pramana_foundry/relocation.ex:465` | `Relocation.relocation_status/0` | It has no static caller and xref shows no edge. It is called through `apply(__MODULE__, :relocation_status, [])` at line 461, a deliberate indirection. It belongs to FR-19B |
| `lib/pramana_foundry/launch_eligibility.ex:18-19` | `@reasoning_levels` members `minimal` and `auto`, `@approval_modes` member `yolo` | Nothing in the repo produces these values. They are allowlists for operator profile input, matched at lines 178–179. Removing one changes admission, which FR-12 owns |
| `lib/pramana_foundry/reviews/matrix.ex:6` | `@high_risk_classes` member `p0_correctness_security` | This allowlist classifies ticket `risk` input. Removing the member changes reviewer derivation |
| `lib/pramana_foundry/telemetry/forecast.ex:4` | `@comparison_fields` member `correction_behavior` | A field compared on observation maps at line 112. Removing it changes which observations count as comparable |
| All `handle_call`, `handle_cast` and `handle_info` clauses | — | Every handled message atom has a sender. The only mismatch runs the other way: `replace_projection` has a sender and no handler |
| Every `@behaviour` callback implementation | — | Callbacks count as dispatched. The only behaviour with no implementer is `DurableStore.Kernel`, listed under FR-08B |

**Modules.** No module under `lib/` is unreferenced. The xref graph shows 23 files with
no inbound edge from other `lib/` files. Every one is reached in one of these ways:
- through `mix.exs`, for `Application` and the escript;
- through `bin/` or `ci/`, for `CI`, `CLI.RPC`, `Assessor.Evaluator` and `Workflow.Kernel`;
- only through tests. That group is `DurableStore.Maintenance`, `Effects.Launch`,
  `Effects.PromptDelivery`, `Effects.SilenceWatchdog`, `Preparation`, `SchemaReference`,
  `Assessor.ContextSelector`, `Assessor.Fake`, `Assessor.FixtureHTTP`, `Assessor.Jev`,
  `Checks.Adoption` and `Checks.Runner`.

## Test-only callers — not candidates

A test caller counts as a caller. These exports have no caller in `lib/`, `bin/`, `ci/`,
`config/`, `mix.exs` or `rel/`, and at least one in `test/`. The list comes from the same
scan with `test` dropped from the roots. It is heuristic, and it includes some false
positives: `child_spec/1` is dispatched by supervisors that name the module, which xref
does not record as a call.

- **FR-08B:**
  - `Gateway.transact_verified/6`, `atomic_bundle/4`, `backup/2`, `checkpoint/1`,
    `migrate/1,2`, `operational_health/1` and `recent_events/2`;
  - `Authority.registry/0`;
  - `RecordCodec.event_types/0`, `legacy_event_types/0` and `lifecycle_event_types/0`;
  - `TransitionPlan.operation_types/0`, `output_kinds/0`, `producer_operations/0` and
    `slot/1`;
  - `Coordinator.reset/0,1` and `AgentServer.submit_review/2,3`.
- **FR-10 and FR-11:**
  - `Effects.Launch.to_expected_identity/1`;
  - `Effects.PromptDelivery.deliver/7,8`;
  - `Effects.SilenceWatchdog.exempt?/1` and `expired?/3`;
  - `Checks.Runner.read_completion/1` and `sanitize_env/1`;
  - `Checks.Adoption.reconcile/1`.
- **FR-19B:**
  - `Relocation.rollback/1,2`;
  - `LocalExclude.protected?/1,2` and `verify_protection/1,2`;
  - `Manifest.to_map/1`;
  - `PathMap.chain/3` and `reverse_resolve/2`.
- **Unowned:**
  - `Board.get_data/0,1`, `refresh/0,1` and `render_lines/0,1`;
  - `Board.Inspection.formatted_status/0,1`;
  - `Assessor.ContextSelector.select/2,3` and `Assessor.Jev.pinned_model/0`;
  - `AtomicFile.recover/1`;
  - `CI.command_probe/3`;
  - `CLI.Validators.validate_directory/1`, `validate_review/1` and `validate_ticket/1`;
  - `Improver.analyze/0,1`;
  - `Parity.compare_fixture/2`;
  - `Projections.Projection.authority_subset?/2` and `canonical_digest/1`;
  - `FR08AProtectedBoundary.report_artifact/0` and `H0AcceptedFR07Boundary.report_artifact/1`;
  - `Status.report/1,2`;
  - `Telemetry.Forecast.critical_path/2,3` and `recalculate/3,4`;
  - `Telemetry.Store.compact/3,4`;
  - `Telemetry.Telemetry.observe/2`.

## Counts

- FREE: 4 function identifiers (6 arities).
- FR-08B: 10 function identifiers, 1 behaviour with no implementer, and 18 list-literal
  members. Five of those members are required compatibility and cannot be removed.
- FR-19B: 2 function identifiers.
- FR-10, FR-11 and FR-12: 0.
- Unreferenced modules: 0.
