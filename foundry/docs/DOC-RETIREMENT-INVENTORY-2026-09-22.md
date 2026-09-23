# Documentation retirement inventory — 2026-09-22

Baseline: `e374322b` on `repair/fr08b-kernel`. Input to FR-23's documentation-retirement
part; it decides nothing on its own.

**Rule applied** ([FR-23](REPAIR-PLAN.md#fr-23--retire-legacy-surfaces-decompose-god-modules-and-restore-code-hygiene)):
evidence of a check is preserved; description of a mechanism is retired when the mechanism
is gone. A superseded but instructive design stays, with a banner at the top naming what
replaced it. When the two are in one file, split the file instead of choosing.
FR-08B owns retiring legacy JSONL from live workflow truth. FR-19B owns repairing or
retiring offline relocation. This pass does not pre-empt either.

**Nothing was retired, moved or deleted by this pass, and no banner was applied.**
No file both lacked a banner and had an unambiguous replacement. Every row below
still needs the user's approval before anything is acted on.

**Coverage.** All 183 Markdown files under `foundry/docs/` at the baseline. This file is
not counted. Repo `docs/` files are covered only where they route into Foundry.
**Method.** I read the opening of every file and opened every design, specification
and plan file past its header. I also checked each backticked `lib/`, `test/`, `ci/`,
`roles/` or `bin/` path, and each `Module.fun/arity` reference, against the tree.
Standard-library functions and helpers under `test/support/` came back as false misses
and were set aside. A clean reference check does not show that a document's prose is
accurate.

| Class | Files |
|---|---|
| KEEP-EVIDENCE | 147 |
| KEEP-CURRENT | 32 (5 have stale status lines, and one README route is stale; both listed below) |
| BANNER | 1 (banner already present) |
| OWNED-ELSEWHERE | 3 |
| RETIRE | 0 whole files; 2 sections, both inside OWNED-ELSEWHERE files |

## RETIRE

No whole file qualifies. Two sections describe code that is absent from this repository's
history at the baseline. The code exists only on commits that are not ancestors of `HEAD`,
such as `f06087c0` and `c8ede6a1`. Both sections sit inside migration documents that FR-23
gates on FR-08B, so retiring them means splitting those files after FR-08B. It must not be
done in place now.

| Section | Mechanism described | Evidence the code is gone (run from repo root at `e374322b`) |
|---|---|---|
| [MIGRATION.md](MIGRATION.md) §"Cutover and cutover interfaces" and §"Cutover-to-retirement checklist" | `PramanaWorkflow.Cutover.{SupervisorControl,Import,Release,Rollback,Soak,Retire}`, Python wrappers, `automation/` scripts | `git grep -n -e "Cutover\." -e "SupervisorControl" -e "defmodule .*Cutover" -- foundry/lib foundry/test foundry/bin bin foundry/ci` → **empty, exit 1**. `git grep -n -e "bin/pramana-supervisor" -e "bin/pramana-board" -e "bin/pramana-retire-smoke" -- ':!*.md'` → **empty, exit 1**. `ls bin/pramana-supervisor bin/pramana-board bin/pramana-retire-smoke automation` → all four absent |
| [MIGRATION-TICKETS.md](MIGRATION-TICKETS.md) §"Cutover contract: WF-ELIXIR-CUTOVER-02", §"Retirement boundary" | Same `Cutover.*` modules and `test/pramana_workflow/cutover*` tests | Same greps. No `test/pramana_foundry/cutover*` exists (`ls foundry/test/pramana_foundry`) |

The parity matrix in MIGRATION.md is labelled "Historical executable parity matrix (dated
2026-09-08)". It records what was checked on that date, so it is **evidence** and survives
any split.

## BANNER

| File | Superseded by | Banner present? | Verified |
|---|---|---|---|
| [fr-08/fr08b-closure-candidate-design.md](fr-08/fr08b-closure-candidate-design.md) | The post-condition in `advance/2`: `State.well_formed?/1` over the committed post-state, refusing with `:malformed_post_state` | **Yes**. The first line says "superseded on 2026-09-22" and names the replacement | `foundry/lib/pramana_foundry/workflow/kernel.ex:30–31, :110` |

**Considered and not bannered.** [fr-08/fr08b-subcommit1-correction-design.md](fr-08/fr08b-subcommit1-correction-design.md)
has no banner. [fr-08/fr08b-row-driven-coverage.md](fr-08/fr08b-row-driven-coverage.md)
says it "supersedes the guard-by-guard method used for `be1e19c` and `40ac559`". However,
the correction design's Defect A fix is live. Executions are now addressed by the owning
attempt: `require_execution(ticket, attempt_id, execution_id)` and
`close_execution(ticket, attempt_id, …)` in `workflow/kernel.ex:1166, :1343`. Only its
method was replaced, so the replacement is partial, and the file answers a review, which
makes it evidence. It is left unbannered. If the user wants a note, it should name the
row-driven design as the replacement **method only**.

Already-bannered evidence records, kept as evidence: `fr-04/candidate.md` (points to
`review-response.md`), `fr-18a/candidate.md` ("Historical pre-B5 freeze"),
`fr-19a/correction-checkpoint.md` ("superseded"), `fr-08/fr08b-ev6-ev2-review-briefing.md`
("FROZEN at the review point"). [fr-08/event-vocabulary-design.md](fr-08/event-vocabulary-design.md)
is the worked example in the rule. It keeps revision 1's failed mechanism under "What
revision 1 got wrong", and revision 2's mechanism is live, so it is KEEP-CURRENT.

## OWNED-ELSEWHERE

| File | Owner | Why not FR-23's to retire yet |
|---|---|---|
| [EVENT_SOURCING.md](EVENT_SOURCING.md) | FR-08B | Describes the live legacy JSONL path: `events.jsonl`, `Transition.rebuild/2` and `Checkpoint.append/6`. `Transition.rebuild` is defined at `foundry/lib/pramana_foundry/transition.ex:58`. `Checkpoint.append` is called from `coordinator.ex:1336`, `coordinator/tick.ex:32` and `effects/prompt_delivery.ex:53`. `git grep -l events.jsonl -- foundry/lib` → `application.ex`, `board.ex`, `consolidated_log.ex`, `coordinator.ex`. No banner; its replacement (the FR-08B kernel) has not finished migrating ingress, so any banner would pre-empt FR-08B |
| [MIGRATION.md](MIGRATION.md) | FR-08B (migration-era, JSONL), FR-19B (§"Workspace relocation and rollback") | FR-23 retires migration-era material only "once FR-08B has retired legacy JSONL". Relocation is live in `foundry/lib/pramana_foundry/relocation/` (six modules) and `relocation.ex`. The file already has a historical-status banner and naming note. Its cutover sections are listed under RETIRE |
| [MIGRATION-TICKETS.md](MIGRATION-TICKETS.md) | FR-08B (migration-era), FR-19B (WF-WORKSPACE-MOVE-01) | Same gate. Historical-status banner already present |

## KEEP-CURRENT

Current reference, governing contracts, and design or research that is not superseded.
Research and design notes are here because no mechanism has replaced them, not because
they describe running code.

| File | Basis |
|---|---|
| [README.md](README.md), [REPAIR-PLAN.md](REPAIR-PLAN.md), [WORKFLOW-CONTRACT.md](WORKFLOW-CONTRACT.md) | Governing index, backlog and contract |
| [CI.md](CI.md) | `foundry/ci/run.exs` exists |
| [DURABLE-STORE.md](DURABLE-STORE.md) | `Gateway`, `Kernel.validate_bundle/1` (`durable_store/kernel.ex:9`), `ProtectedVerifier`, `PathIdentity`, `LegacyImport` all present in `durable_store/` |
| [DURABLE-STORE-SCHEMA.md](DURABLE-STORE-SCHEMA.md) | Generated; `SchemaReferenceTest` enforces it |
| [EVIDENCE-TOOLS.md](EVIDENCE-TOOLS.md) | `foundry/bin/{refusal_sites,guard_mutation_sweep,contract_annotation_diff,closure_probe}.exs`, `preflight.sh` present |
| [COVERAGE-GUIDED-SWEEP.md](COVERAGE-GUIDED-SWEEP.md) | "Design note. Not implemented"; still the open proposal referenced by the evidence-reduction tickets |
| [ASSESSOR.md](ASSESSOR.md) | `foundry/lib/pramana_foundry/assessor/` present |
| [OBSERVABILITY.md](OBSERVABILITY.md) | Live inventory plus target; every backticked reference resolves |
| [STRATEGY.md](STRATEGY.md), [ECOSYSTEM-BOUNDARY.md](ECOSYSTEM-BOUNDARY.md), [ORCHESTRATOR-BOUNDARY.md](ORCHESTRATOR-BOUNDARY.md), [PROJECT-WORKFLOW-PROFILES.md](PROJECT-WORKFLOW-PROFILES.md), [PLANNING-STRATEGIES.md](PLANNING-STRATEGIES.md), [AX-SUBSTRATE.md](AX-SUBSTRATE.md), [CLOUDFLARE-OS.md](CLOUDFLARE-OS.md) | Dated research or design guidance; nothing supersedes them |
| [PI-HARNESS.md](PI-HARNESS.md), [JIDO-HARNESS.md](JIDO-HARNESS.md) | Two live candidates. JIDO-HARNESS says to compare both, so neither replaces the other |
| [fr-15a/provisioning-specification.md](fr-15a/provisioning-specification.md) | FR-15aA specification with machine-readable manifest; still governing |
| [fr-08/fr08b-kernel-correction-design.md](fr-08/fr08b-kernel-correction-design.md) | Accepted FR-08B design; already carries a "Current status route" note for its outdated sentences |
| [fr-08/fr08b-row-driven-coverage.md](fr-08/fr08b-row-driven-coverage.md) | Live method: `foundry/test/support/r4_rows.ex` |
| [fr-08/fr08b-ingress-inventory.md](fr-08/fr08b-ingress-inventory.md) | FR-08B's acceptance matrix for the outstanding ingress migration |
| [fr-08/fr08b-subcommit2-reads-inventory.md](fr-08/fr08b-subcommit2-reads-inventory.md), [fr-08/fr08b-subcommit2-control-inventory.md](fr-08/fr08b-subcommit2-control-inventory.md) | Subcommit 2 not started; README already warns to reconfirm against the kernel |
| [fr-08/fr08b-evidence-reduction-tickets.md](fr-08/fr08b-evidence-reduction-tickets.md) | Live ticket list; its order table records EV-6/EV-2 as landed. Its EV-2 section cites `bin/clause_unit_probe.exs`, removed in `1fcb8b63`. That is a dated measurement, left intact |
| [fr-08/workflow-definition-seam.md](fr-08/workflow-definition-seam.md) | Analysis for a future second workflow; not superseded |
| The five stale-status designs below | Mechanism live |

**Stale status lines (mechanism live, header says otherwise).** These are not superseded,
so they are not BANNER candidates. Each needs a dated status-route note like the one
in `fr08b-kernel-correction-design.md`. The dated body text should not be rewritten.
None was applied.

| File | Header says | Code shows |
|---|---|---|
| [fr-08/event-vocabulary-design.md](fr-08/event-vocabulary-design.md) | "no implementation, no accepted vocabulary" | Flat disjoint vocabulary live: `record_codec.ex:34–36` (`@legacy_event_types ++ @lifecycle_event_types`), `workflow/kernel/event.ex` |
| [fr-08/fr08b-event-vocabulary-enumeration.md](fr-08/fr08b-event-vocabulary-enumeration.md) | "specification … No implementation" | `workflow/kernel/event.ex` carries the enumerated types (e.g. `submission_rejected`, `objective_created`) |
| [fr-08/plan-binding-specification.md](fr-08/plan-binding-specification.md) | "no integrated behavior" | `durable_store/transition_plan.ex` cites this spec. REPAIR-PLAN marks FR-08A complete with all six subcommits integrated |
| [fr-08/plan-replay-revalidation-design.md](fr-08/plan-replay-revalidation-design.md) | "no implementation" | REPAIR-PLAN FR-08A row: replay revalidation integrated, attestation rebound at `e491e41` |
| [fr-18a/bounded-effect-query-design.md](fr-18a/bounded-effect-query-design.md) | "design only; B5 remains blocking" | `protected_primitives.ex:3952–4021` (`bounded_effect_*`). [B5 correction rereview](fr-18a/b5-correction-rereview.md) is PASS |
| [README.md](README.md) row "Resolve FR-08B protected-result/domain binding" | "none implements an end-to-end binding" | Same as plan-binding above |

## KEEP-EVIDENCE

Dated audits, independent reviews, briefings, candidates, responses, verdicts,
attestations, diagnoses and the append-only log. The rule says to preserve these always.
None was edited.

| Location | Files |
|---|---|
| top level (8) | ALIGNMENT-AUDIT-2026-09-19, alignment-disposition-2026-09-19, alignment-disposition-review-2026-09-19, AUDIT-2026-09-12, FR-06-DESIGN-REVIEW, FR-06-DESIGN-REVIEW-V2, IMPLEMENTATION-LOG, POSITIONING-AUDIT-2026-09-21 |
| audit-2026-09-12/ (1) | verification |
| fr-01/ (6) | integration-attestation, review-v1 … review-v5 |
| fr-02/ (3) | integration-attestation, review-v1, review-v2 |
| fr-03/ (4) | integration-attestation, review, review-response, review-v2 |
| fr-04/ (20) | candidate, current-process-state-review, integration-attestation, review, review-v2 … review-v9, review-response, review-response-v2 … v8 |
| fr-05/ (5) | candidate, integration-attestation, review, review-response, review-v2 |
| fr-06/ (4) | r4a-focused-review, review-response-v2, review-response-v3, verification |
| fr-07/ (28) | candidate, candidate-v2 … v9 (with v4-withdrawal, v6-supplement), diagnosis-v3, diagnosis-v6, review, review-v2/v3/v5–v9, review-response, review-response-v2/v3/v5–v8 |
| fr-08/ (38) | atomic-composition-{diagnosis, review, rereview, final-rereview, presence-review}; fr08a-{candidate, acceptance-review, carrier-rereview, final-critical-review, fr19a-integration-candidate, fr19a-integration-review, independent-review, independent-rereview, transition-replay-candidate, transition-review, typed-carrier-candidate, typed-replay-review}; fr08b-{closure-review-2026-09-22, ev6-ev2-review-briefing, ev6-ev2-review-findings, integration-issued-review-briefing, pure-kernel-review, r4a03f2-review-2026-09-22, root-fact-composition-diagnosis, subcommit1-correction-design, subcommit1-review-briefing, subcommit1-review-findings, subcommit1-rereview-briefing, subcommit1-review3-briefing, subcommit1-review4-briefing, subcommit1-review4-findings, subcommit1-review4-sol-findings, subcommit1-sweep-2026-09-21}; h0-boundary-{candidate, review, rereview}; investigation; plan-binding-candidate |
| fr-09/ (3) | checkpoint-f-feasibility, checkpoint-f-review, checkpoint-f-rereview |
| fr-15a/ (3) | evidence, independent-review, independent-rereview |
| fr-18a/ (7) | candidate, independent-review, correction-rereview, final-b1-rereview, bounded-effect-query-candidate, b5-review, b5-correction-rereview |
| fr-19a/ (7) | candidate, correction-checkpoint, linux-sync-eio-plan (dated plan bound to recorded runs; `foundry/ci/fr19a_*` still present), review, rereview, rereview-evidence, final-rereview |
| fr-21/ (10) | candidate, candidate-v2, candidate-v3, acceptance-v2, integration-attestation, review, review-v2, review-v3, review-response, review-response-v2 |

`AUDIT-2026-09-12.md` still names `bin/pramana-supervisor`, which is absent. That is
correct for a dated audit, and `test/docs/routing_test.exs` already carries its one
recorded link exception.

## Repo `docs/` routes into Foundry

Every repo `docs/` file that routes into Foundry points only at KEEP-CURRENT or
KEEP-EVIDENCE files. Most routes go to REPAIR-PLAN, WORKFLOW-CONTRACT, the design guidance
and CI. None points at the OWNED-ELSEWHERE or RETIRE material, except
[the catalog](../../docs/CATALOG.md), which lists every file by design. The files are:
`docs/agents/WORKFLOW.md`, `docs/README.md`, `docs/REPO_MAP.md`,
`docs/REPOSITORY_STRUCTURE.md`, `docs/MAINTAINING_DOCS.md`, `docs/PLAN.md`,
`docs/PLAN_INDEX.md`, `docs/PRODUCT_STRATEGY.md`, `docs/TESTING.md`, `docs/TEST_AUDIT.md`,
`docs/LAYOUT_MIGRATION.md` and `docs/strategy/{FOUNDRY,ROADMAP,VALIDATION}.md`.
`docs/audits/2026-09-15/` is dated evidence.
