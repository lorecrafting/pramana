# Batch D: the thin dogfood lane

**Date:** 2026-09-23. **Type:** design for T3–T7 of
[dogfood readiness §4](../DOGFOOD-READINESS-2026-09-23.md#4-the-thin-dogfood-option). It
changes no code. **Taken at `8ed8d233`** (`repair/fr08b-kernel`). Code paths are under
`foundry/lib/pramana_foundry/` and test paths are under `foundry/test/pramana_foundry/`. Line
numbers are at that commit.

**Operator decisions, 2026-09-23.**

- **M1.** The dogfood gate is FR-08B subcommits 2 and 3 (reviewer) plus this lane.
- **M2.** The FR-10 → FR-09 → FR-15aB edges bind the full lane only.
- **M3.** The reviewer subcommit is reviewed without waiting for subcommit 4.
- **M4.** A1–A6 are accepted. A3 is now mostly closed by Core's predicate on recorded
  principals.
- **M5.** Dogfood on Foundry is not a ROADMAP G0 product build.

## 1. Scope

**In scope.** The execution channel is a human, or an agent session a human starts. Foundry
does five things:

1. It admits a ticket.
2. It issues one claimed effect per launch through `decide/3`, and writes a work packet.
3. It records the result as a receipt.
4. It binds an independent review to the exact candidate.
5. It replays all of the above after a restart.

The lane ends at `ready_to_integrate`. Integration is manual Git (A5).

**Non-goals.** The lane does not include:

- scheduling, timers, crash budgets or automatic review (FR-11, FR-12);
- check workers (subcommit 4);
- scope or artifact verification (FR-13, A4);
- a boot reconciler, monitors or AgentServer routing (FR-10 commits 5–9);
- a quarantine exit (A2);
- PM;
- any change to the legacy CLI.

**Must stay disabled.** This is readiness §4's list, unchanged, and the lane touches none of
it: `COORDINATOR_TICK` (`application.ex:17-19`); the Herdr System runner's subscription
capability; AgentServer launch and prompt; `ticket integrate`, `pramana-live.sh`,
`tickets_from_review.sh` and `live_test.exs`; `auto_approve`; PM proposals acting as
admission; paid profiles.

The lane's policy also makes Core refuse two of these
(`durable_store/protected_primitives.ex:3240-3253`):

- `allowed_roles` is `["developer","reviewer"]`, which refuses PM effects.
- `allowed_profiles` is left unset, so only `"unspecified"` passes.

**Non-launch test** (`manual_lane/non_launch_test.exs`, owned by W2). This is a
module-graph test:

- **Start set.** Every file under `lib/pramana_foundry/manual_lane/`, plus `work_packet.ex`.
- **Walk.** References are followed transitively through every `lib/` module they reach,
  using the architecture gate's resolver (`test/support/ast_modules.ex`;
  `architecture_boundary_test.exs:187-196`).
- **Assertion.** The closure contains none of these:
  - `PramanaFoundry.Herdr.*`
  - `AgentServer`
  - `Coordinator`, `Coordinator.Tick`, `Coordinator.State`
  - `Effects.Launch`, `Effects.PromptDelivery`

Because the test globs the directory, it covers T5's CLI file as well.

**Red controls.** Each of these fixtures must fail the test: a fixture under
`System.tmp_dir!()` that references `PramanaFoundry.Herdr.Adapter`, following the pattern at
`architecture_boundary_test.exs:282`; a fixture that reaches `Coordinator` through one
intermediate module, which proves the walk is transitive.

## 2. T4: the work packet

`PramanaFoundry.WorkPacket` is a new file, `work_packet.ex`. It is pure: no I/O, Git,
Gateway or clock. It turns replayed store state into a packet and does nothing else.

```elixir
@spec build(ticket :: map(), effect :: map(), policy :: map()) :: {:ok, map()} | {:error, atom()}
@spec validate(term()) :: :ok | {:error, atom()}
@spec encode(map()) :: binary()   # canonical JSON: keys sorted, no whitespace, trailing "\n"
```

`build/3` takes three inputs:

- `ticket` is the kernel ticket rebuilt by replay (§3).
- `effect` is `protected_query %{"type" => "effect"}` for the launch effect, with its
  `claims` (`protected_primitives.ex:5137-5160`; public shape at `:3860-3885`).
- `policy` is the policy fact at the effect's `policy_revision`.

`build/3` runs `validate/1` on its own output before returning it. No field is a literal, and
no field comes from a CLI argument to `packet`.

| Field | Type | Source |
|---|---|---|
| `schema_version` | `1` | constant |
| `packet_id` | string | equal to `execution_id` |
| `role` | `"developer"` \| `"reviewer"` | `effect["role"]` |
| `ticket_id`, `attempt_id` | string | `effect[...]`. Must equal the ticket's id and its `active_attempt_id` |
| `execution_id`, `effect_id`, `request_id` | string | `effect[...]`. Derived from the launch `command_id` by `Plan.id/2` (`workflow/kernel/plan.ex:52`, `:105-154`) |
| `claim_id`, `writer_epoch` | string | the effect's single claim, whose status must be `issued` |
| `issuer` | string | `effect["issuer"]`, the recorded principal (`protected_primitives.ex:1304`) |
| `base_revision` | 40-hex | `ticket["spec"]["base_revision"]`, written at `admit` (§4). Read from the store only. There is no fallback (contrast `cli.ex:362-363`) |
| `base_ref`, `title`, `spec_revision_id` | string | `ticket["spec"]` and `ticket["spec_revision_id"]` |
| `scope` | non-empty `[string]` of path globs | `ticket["spec"]["scope"]` |
| `acceptance_criteria` | non-empty `[string]` | `ticket["spec"]["acceptance_criteria"]` |
| `checks` | `%{"policy_empty" => true}` | the policy's `check_set`, which must be `[]` (§7) |
| `candidate` | `nil` for a developer. For a reviewer, `%{"candidate_id", "producer_execution_ids"}` | the active attempt's `candidate_id` and its developer executions |
| `independence` | `%{"policy_id", "policy_revision", "independent_of_roles", "excluded_principals"}` | `policy["value"]["independent_of_roles"][role]`. For a reviewer, `excluded_principals` lists the issuers of the attempt's developer effects |
| `return` | `%{"command" => "submit" \| "review", "ticket_id"}` | derived from `role` |

**Independence** is informational in the packet. Core enforces it itself, at `create_effect`
(`protected_primitives.ex:1344`, `:3302-3323`; decisions (a)–(c) in the
[independence design](../fr-08/FR08B-REVIEWER-INDEPENDENCE-DESIGN-2026-09-23.md)).

**Refusal atoms.** Grouped by the input they concern:

- **Ticket:** `:ticket_not_found`, `:no_active_attempt`.
- **Effect:** `:effect_ticket_mismatch`, `:execution_not_in_attempt`, `:effect_not_issued`,
  `:unsupported_role`.
- **Spec:** `:base_revision_missing`, `:base_revision_not_sha`, `:scope_missing`,
  `:acceptance_missing`.
- **Candidate:** `:candidate_missing`, when a reviewer packet has no frozen candidate.
- **Policy:** `:independence_policy_missing`, `:check_set_not_empty`.
- **Packet:** `:invalid_packet`, for a missing or extra field or a wrong type.

**Tests** (`work_packet_test.exs`):

- A developer packet and a reviewer packet each round-trip through `validate/1`.
- Each refusal atom has one case that asserts that exact atom.
- `encode/1` is byte-stable across key order.
- **Red controls:**
  - A `spec` without `base_revision` refuses. This proves there is no default.
  - A reviewer policy without `independent_of_roles` refuses.

## 3. T3: the manual execution backend

`PramanaFoundry.ManualLane.Backend` is a new file, `manual_lane/backend.ex`. Every function
takes `ctx = %{gateway, capability, path, writer_epoch}`, so it runs against a Gateway a test
started, before T6 exists.

`ManualLane.Replay` (`manual_lane/replay.ex`) moves the e2e test's adapter pieces into
`lib`, almost line for line: `replay/1` (`decide_e2e_test.exs:242-275`), calling
`Kernel.apply/2` rather than `Harness.apply`; the prestate-read loop of `submit/3`
(`:200-228`), via `ProtectedPrimitives.required_bundle_prestate_revisions/3`
(`protected_primitives.ex:130`); the single `incomplete_read_set` retry of `root!/2`
(`:88-117`); `launch_facts/3` (`:160-174`), with `writer_epoch` taken from `ctx`.

```elixir
@spec state(ctx) :: map()                                     # Replay.state/1
@spec admit(ctx, ticket_id, spec) :: result
@spec launch(ctx, ticket_id, role, principal) :: {:ok, packet} | result
@spec deliver(ctx, ticket_id, role, principal, receipt_payload) :: result
@spec ingress(ctx, command_id, ticket_id, [{type, payload}], principal) :: result
@spec review(ctx, ticket_id, principal, verdict, candidate_id, receipt_payload) :: result
@spec settle(ctx, ticket_id, role, principal, :non_started | :unknown, attestation) :: result
# result :: {:ok, map()} | {:reject, atom()} | {:error, atom()}
```

**How the effect protocol maps.** The protocol runs claim, issue, adapter, settle
([FR-10 §4](../fr-10/FR10-DESIGN-2026-09-23.md#4-the-line-between-core-and-the-controller);
`ORCHESTRATOR-BOUNDARY.md:479-505`). Here the human is the adapter.

| Step | Backend | Existing surface |
|---|---|---|
| propose, verify, claim, issue | `launch/4` | `Kernel.decide/3` `plan_launch` with `%{"role" => role}` (`workflow/kernel.ex:147-155`; `software/developer.ex:76-87`, `software/review.ex:129-138`). It plans `reserve → create_effect → claim_effect → issue_claim` (`plan.ex:72-95`), sent via `Gateway.atomic_bundle/4` (`durable_store/gateway.ex:94`) with `actor_id = principal`. Then `WorkPacket.build/3` |
| adapter dispatch | the packet file | The CLI (T5) writes it. Foundry sends nothing |
| receipt: ran | `deliver/5` | `Gateway.protected_command/4` (`gateway.ex:90`) `settle_claim`, `succeeded`/`delivered` (`protected_primitives.ex:1519-1557`, `:4146`). This is e2e `delivered!` (`decide_e2e_test.exs:912-922`) |
| receipt: proved non-start | `settle(:non_started)` | `decide/3` `settle_nonstart` (`developer.ex:44-59`, `review.ex:98-113`; `plan.ex:163-192`). `facts["settle_claim"]` carries `proof: issuer_quiescent` and `payload.quiescence_epoch = claim.writer_epoch` (`protected_primitives.ex:1993-2003`) |
| receipt: unknown | `settle(:unknown)` | `protected_command` `settle_claim`, `unknown`/`outcome_unknown` (`:4145`). There is no domain event, because no decider exists. Units and leases stay held (`:4149`), which is A2 |
| verdict | `review/6` | `deliver` for the reviewer claim, then ingress `stream_sealed`, then `decide/3` `submit_review` (`review.ex:64-91`; correction and rejected go through `close_attempt`, `plan.ex:203-246`), then ingress `reviewer_closed` |

**Ingress without a decider.** At `8ed8d233`, `decide/3` decides only `plan_launch`,
`settle_nonstart` and `submit_review` (developer and reviewer), and `finalize_cancellation`
(`cancellation.ex:21-54`). Admission, freeze, seal, close and `checks_started` have no
decider.

The e2e test commits those through `Plan.unconditional/3` and `Plan.decision/2`, as
subcommit 4 and 5 ingress (`decide_e2e_test.exs:119-147`, `:614-635`). `ingress/5` does the
same, but only for a closed table of types: `ticket_admitted`; `artifact_frozen`,
`artifact_blocked`; `stream_sealed`; `developer_closed`, `reviewer_closed`;
`checks_started`.

Any other type returns `:ingress_type_not_allowed`. The reducer's guards still apply through
`Plan`'s dry run (`plan.ex:418-432`). See Q1.

**Principals.** The actor passed to `atomic_bundle` or `protected_command` is the principal.
Core records it as the effect issuer (`protected_primitives.ex:1304`), and only that actor may
settle the claim (`:1995`). Four rules follow:

- **One principal per execution.** `launch`, `deliver` and `settle` for an execution all take
  the same principal.
- **Reviewer independence.** The reviewer's principal must differ from every developer issuer
  in the attempt. Otherwise Core refuses with `principal_not_independent` (`:1344`; e2e
  `:757-781`). The backend returns `{:reject, :principal_not_independent}`, with no event and
  no retry. This is R4a's pre-intent denial (`review.ex:54-58`).
- **Operator.** Root setup and admission run as `"operator"`.
- **Recorded, not proved.** A principal is an opaque string such as `human:raymond` or
  `agent:fable:<session>`. It is not proved isolated (A3).

**Operator attestations (A1).** Every human-asserted receipt payload carries three keys:
`evidence_kind: "operator_attestation"`; `attested_by: <principal>`; `statement`, which must
not be empty.

A non-start receipt also carries `failure_class: "operator_attested_non_start"`,
`quiescence_epoch: claim.writer_epoch`, `issuer_gone: true` and `channel_quiet: true`.

Both booleans are required. FR-10 Quint finding A shows that either alone is unsafe
(`FR10-DESIGN-2026-09-23.md:9-12`). A missing or false value is refused with
`:quiescence_not_attested`.

**Backend refusals.** These come in addition to the ones from `decide/3` and Core:
`:attestation_required`; `:quiescence_not_attested`; `:no_issued_claim`;
`:ingress_type_not_allowed`; `:ticket_id_not_lane` (§4); `:effect_already_settled`, when
`settle(:unknown)` finds the effect already terminal. This guards against FR-10 finding B,
where a late `unknown` re-quarantines a settled effect.

**Idempotency.** Command ids are derived from state:

- **Launch:** `<ticket>/<role>/<ordinal>`, where the ordinal is the role's execution count in
  the attempt.
- **Ingress:** `<ticket>/<step>/<execution_id>`.
- **Retry predecessor:** `X/execution → X/effect`, by the `Plan.id/2` rule.

Every write replays first. If the step is already committed, the backend reports it and
submits nothing. The Gateway is the backstop:

- A byte-identical repeat returns `:idempotent` (`gateway.ex:572-586`).
- A changed repeat returns `:idempotency_conflict` (`:649-680`). The backend reads this as
  "already committed" and re-reads the state.

The backend never mints a new id.

**Tests** (`manual_lane/backend_test.exs`). A `start_supervised!` Gateway runs on a temporary
path, as in `decide_e2e_test.exs:22-37`.

- **Full path.** Admit, developer launch, deliver, freeze, reviewer launch under a second
  principal, approve, `ready_to_integrate`. After each step, `Replay.state/1` must equal the
  committed projection (the substitution law, `:277-290`).
- **Verdicts.** Correction and rejected.
- **Non-starts.** Developer and reviewer, each below and at the limit.
- **Unknown.** An `unknown` settlement keeps its units held.
- **Red controls.** Each of these must be refused:
  - a reviewer under the developer's principal;
  - an attestation without `channel_quiet`;
  - `settle(:unknown)` after `succeeded`;
  - an ingress of `review_recorded`.

  Separately, launching twice must create exactly one effect.

## 4. T5: the manual-lane CLI

`PramanaFoundry.ManualLane.CLI` is a new file, `manual_lane/cli.ex`, invoked as
`bin/pramana lane <cmd> …`.

- **Routing.** `CLI.RPC.run/1` (`cli/rpc.ex:29-34`) routes argv that begins with `"lane"` to
  `ManualLane.CLI.main/1` instead of `CLI.main/1`. `validate_command_shape` (`:127-152`) gains
  one clause per lane shape. `cli.ex` and `coordinator.ex` are not touched.
- **Ticket ids.** A lane id must match `^ML-[A-Za-z0-9-]+$`. Legacy ids are `T-<ts>-<hex>`
  (`cli.ex:368`), so the two cannot collide.
- **Output.** Each command prints one JSON object on stdout: `{"ok": true, …}`, or
  `{"ok": false, "error": "<atom>", "detail": …}` with a non-zero exit.
- **Principal.** `--principal` never defaults. Omitting it fails with `principal_required`.

| Command | Args | Calls | Output |
|---|---|---|---|
| `admit` | `ML-ID --base-ref REF --title T --scope G[,G…] --acceptance A` (repeatable) | (1) `git rev-parse --verify REF^{commit}` in the configured repo (§5). (2) As `"operator"`, `set_policy` adding `"ticket:ML-ID"` to `allowed_scopes`, because Core matches scopes exactly (`protected_primitives.ex:3243`, `:3248-3249`). (3) `ingress` `ticket_admitted` with `spec = {base_revision, base_ref, title, scope, acceptance_criteria}` and phase `queued` | `ticket_id`, `base_revision`, `spec_revision_id` |
| `packet` | `ML-ID --role developer\|reviewer --principal P [--out PATH]` | `Backend.launch/4`. If the role already has an issued, unsettled execution, it rebuilds that packet from the store instead | the packet (`WorkPacket.encode/1`), also written to `PATH` |
| `submit` | `ML-ID --principal P --candidate SHA --checkout DIR [--blocked REASON]` | (1) `GitEvidence.validate_checkout(DIR, SHA, base_revision)`: clean tree, HEAD and ancestry (`git_evidence.ex:19-64`). (2) `deliver` with `{candidate_id, evidence_kind, …}`. (3) `ingress` `artifact_frozen`, `stream_sealed`, `developer_closed`, `checks_started{policy_empty: true}`, as in `decide_e2e_test.exs:622-635`. With `--blocked`, `artifact_blocked{result: "blocked"}` instead | `awaiting_review`, `candidate_id` |
| `review` | `ML-ID --principal P --verdict approved\|correction\|rejected --candidate SHA --notes PATH` | `Backend.review/6`. The receipt carries the sha256 of the file at `PATH` | `ready_to_integrate`, `queued` or `rejected` |
| `settle` | `ML-ID --role R --principal P --outcome non_started\|unknown --attest TEXT [--issuer-gone --channel-quiet]` | `Backend.settle/6` | the phase and discriminator, or the `unknown` hold |
| `status` | `[ML-ID]` | `Replay.state/1`, `protected_query` for each execution's effect, and `Gateway.status/1` for the mode | per ticket: phase; attempt; executions (role, lifecycle, effect status, issuer); claims `issued`, `unknown` or `reconciliation_required` that await the operator; verdict. Writes nothing |

**Errors.** Every `{:reject, atom}` and `{:error, atom}` is printed by name. The CLI adds
four of its own: `:lane_disabled`; `:gateway_recovery`; `:git_ref_unresolved`; the
`GitEvidence` message.

**Tests** (`manual_lane/cli_test.exs`):

- a happy path and one refusal for each command;
- `RPC.decode/1` accepts each lane shape and still refuses unknown shapes;
- **red control:** `lane packet` without `--principal` is refused before any Gateway call.

## 5. T6: flagged Gateway start

**Flag.** `FOUNDRY_MANUAL_LANE=1`, or `config :pramana_foundry, :manual_lane, enabled: true`.
It is read the same way as `COORDINATOR_TICK` (`application.ex:17-19`). The default is off.

**Store.** The store is `Path.join(runtime_root, "state/manual-lane/authority.sqlite3")`,
overridable with `:manual_lane, store_path:`. It is disjoint from the legacy
`state/current/{events,coordinator,telemetry}.jsonl` (`application.ex:39-41`), which nothing
under `ManualLane` touches.

**Repo.** `:manual_lane, repo:` is an absolute path, used by `admit` and `submit`. It is
required when the flag is on. If it is unset, startup refuses with
`:manual_lane_repo_missing`.

**Child.** `PramanaFoundry.ManualLane.Server` is a new file, `manual_lane/server.ex`. Its
`init/1` does four things in order:

1. If the store file is absent, it calls `Gateway.initialize(path)` (`gateway.ex:27`).
2. It mints `capability = make_ref()` and a fresh `writer_epoch`.
3. It calls `Gateway.start_link(path:, protected_capability:, writer_epoch:)` and links to
   the result (`gateway.ex:69`, `:484-489`).
4. It seeds the store (Q3).

`Server.context/0` returns `ctx`. The capability never leaves this process tree.

**`application.ex`.** The child is appended to `runtime_children` only when the flag is set
and `mode != :client`: in production it runs under `RuntimeOwner` (`:72`), and in tests it
runs directly (`:68-69`); with the flag off, the child list is byte-identical to today's;
the Coordinator still starts with the tick off, and the lane never calls it.

**Tests** (`manual_lane/server_test.exs`):

- flag off: no Server process and no store file;
- flag on: a store is created at the configured path, and no legacy JSONL is touched;
- restart: a new `writer_epoch` over the same store;
- **red control:** `"0"` starts nothing.

## 6. T7: the restart drill

`manual_lane/restart_drill_test.exs` stops `ManualLane.Server` with `stop_supervised!` and
restarts it over the same path. It then asserts on the state rebuilt from the store alone.
No in-memory state crosses the restart.

| Stop after | Asserted after replay |
|---|---|
| `admit` | The ticket is `queued`, and its `spec` (base, scope, acceptance) is intact. The policy scope is present. No attempt exists |
| `packet` (issue) | `developing`, with one `pending` developer execution. Its effect is `issued`, and the claim holds the **old** `writer_epoch`. `status` shows it awaiting the operator. A second `packet` returns a byte-identical packet and creates no second effect: no blind relaunch (FR-10 A5). Both continuations then work: `submit`, whose old-epoch receipt settles only its own claim, and `settle non_started` with `quiescence_epoch` equal to the old epoch |
| `submit` | Ticket and attempt `awaiting_review`, with the same `candidate_id`. The developer effect is `succeeded`. The ledger shows `held` 0 and `consumed` 1. **Split:** a stop between `deliver` and the freeze ingress (injected by calling `Backend.deliver/5` alone) replays as `developing` with the effect `succeeded`. Rerunning `submit` then completes with one receipt, because the duplicate is idempotent |
| `review` | `ready_to_integrate`, `queued` or `rejected`. The verdict is on the exact candidate and the reviewer is closed. The reviewer's issuer differs from the developer's. No effect of the attempt is still `issued` |

The replay check follows `decide_e2e_test.exs:277-290`. The drill also runs one
`settle unknown` before a restart, and asserts that the hold survives it (A2).

## 7. Checks

The lane uses the explicit **policy-empty check set**, R4.12.o3 (`WORKFLOW-CONTRACT.md:523`).
When `policy_empty_checks` is true and no check exists, the reducer finishes checks at once
(`software/checks.ex:31-43`, `:135-144`).

That boolean is a payload field, so the lane ties it to protected policy:

- The seeded policy carries `"check_set" => []`.
- `WorkPacket.build/3` refuses any other value.
- `submit` emits `checks_started{policy_empty: true}` only on the strength of that policy.

Checks the human ran are evidence only. They go in the developer receipt payload as
`checks_run: [%{"command", "exit_status", "summary"}]`, labelled `operator_attestation`. They
produce no `check_recorded` events. Those belong to the subcommit 4 workers.

## 8. Build plan

Each file has one owner. No item touches FR-08B's files (readiness §6).

| Work | Owns (new unless marked edit) | Needs | Tests |
|---|---|---|---|
| **W1 = T4** | `work_packet.ex`; `test/…/work_packet_test.exs` | this doc | §2 |
| **W2 = T3** | `manual_lane/{backend,replay}.ex`; `test/…/manual_lane/{backend,non_launch}_test.exs` | W1's API only: tests may stub the packet until W1 lands | §3, §1 |
| **W3 = T6** | `manual_lane/server.ex`; `application.ex` (edit); `test/…/manual_lane/server_test.exs` | nothing | §5 |
| **W4 = T5** | `manual_lane/cli.ex`; `cli/rpc.ex` (edit); `test/…/manual_lane/cli_test.exs` | W1–W3 | §4 |
| **W5 = T7** | `test/…/manual_lane/restart_drill_test.exs` | W4 | §6 |

- **Order.** W1, W2 and W3 run in parallel on disjoint files. W4 follows them, then W5.
- **Review.** A fresh reviewer agent reviews the lane as one candidate (readiness §5, step 3).
- **Evidence.** Every guard carries a red control (`EVIDENCE-TOOLS.md` rule 1).
- **Attestation.** No file here is attestation-pinned, so `fr08a-protected-report.txt` needs
  no rebind.

## Open questions

Independent review of the built lane: [findings](thin-lane-review-findings-2026-09-23.md).

> **Resolved by the operator, 2026-09-23 (as recommended):** Q1 accept `Plan.unconditional`
> from a closed table, replaced by deciders as subcommits 4–5 land. Q2 read-only SQLite for
> the thin lane; no new Gateway read. Q3 as proposed: seed from the JSON file, refusing one
> whose pairing omits the developer. Q4 two commits, with the split covered by T7. Q5 settled
> by W2's first test, falling back to an `execution_observed` ingress. Q6 a `spec.supersedes`
> field is enough for the thin lane. Q7 one configured repository; packets name no worktree.

- **Q1. Ingress without a decider.** Admission, freeze, seal, close and `checks_started` go
  through `Plan.unconditional/3` from a closed table, as the e2e test does. Is that
  acceptable as this lane's slice of subcommit 5's public ingress, or must the lane wait for
  kernel deciders? *Recommendation:* accept it, and replace each entry with its decider when
  subcommit 4 or 5 lands.
- **Q2. Read path.** Replay and prestate reads open the store read-only over SQLite, as
  `decide_e2e_test.exs:201-215` and `:242-248` do. `Gateway.recent_events/2` is capped at
  1,000 (`gateway.ex:109-113`), and the Gateway has no read for the full event log. Should
  Batch D add one, or accept the read-only connection for the thin lane?
- **Q3. Seeding.** *Proposal:* the first time the Server starts with no root policy
  `manual-lane`, it seeds from a JSON file at `:manual_lane, policy_path:`. The seed creates
  the policy, the control, and the `starts.developer` and `starts.reviewer` ledgers. It
  refuses a file whose `independent_of_roles.reviewer` omits `"developer"`, because a missing
  key imposes nothing (independence design, Limits). The operator chooses the unit counts.
- **Q4. One bundle or two.** Can the developer's `settle_claim(delivered)` share one atomic
  bundle with the freeze events? `TransitionPlan` may demand a binding for it. *Default:* two
  commits, with the split point covered by T7.
- **Q5. Attestation keys.** Does `settle_claim` accept the extra attestation keys in an
  `issuer_quiescent` payload, or does the non-start settlement binding shape-check the
  payload? W2's first test settles it. If the keys are refused, the attestation moves to an
  `execution_observed` ingress.
- **Q6. Abandonment after `unknown` (A2).** The ticket can reach neither `close_attempt` nor
  cancellation. *Proposal:* `status` shows it as abandoned, and a successor is admitted with
  `spec.supersedes`, per R4's "explicit admission linked to predecessor". Is a spec field
  enough, or is a kernel link required?
- **Q7. Worktree.** `admit` and `submit` read one configured repo. Should a packet also name
  a worktree?
