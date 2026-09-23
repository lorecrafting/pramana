# Foundry boundary rules

Read before any Foundry code change. Core is `lib/pramana_foundry/durable_store/`; the
kernel is `lib/pramana_foundry/workflow/`; `kernel/software/` is the reference controller.
"Gate" means `test/pramana_foundry/architecture_boundary_test.exs` (paths below are under
`foundry/`); each rule names the test that fails, with the file and line of the offence.

1. **Core never references Workflow.** Gate: `rule 1 Core references no Workflow module`.
2. **The kernel never calls DurableStore; plans are data.** Gate: `rule 2 the workflow
   kernel references no DurableStore module`.
3. **Role vocabulary (`developer`, `reviewer`, `pm`) appears in Core only at the declared
   sites** listed in `@role_sites`. The list may shrink, never grow; a new site needs a
   reviewed reason, not an allowlist edit. Gate: `rule 3 role vocabulary appears in Core
   only at the declared sites`.
4. **The generic kernel never imports `kernel/software/`,** except the dispatcher's alias and
   `@families` table in `kernel.ex`. Gate: `rule 4 generic kernel modules name
   kernel/software only at the declared sites`.
5. **Every guarantee Core owns lives in an attestation-pinned file.** Pin:
   `test/pramana_foundry/repair/fr08a_protected_boundary_test.exs`.
6. **Foundry depends on no Pramāṇa app.** Gate: `rule 6 Foundry declares and locks no
   Pramāṇa app` and `rule 6 Foundry lib references no Pramāṇa app module`.
7. **A guarantee Core owns never depends on a controller checking it**
   ([O1](orchestrator/O1-SEQUENCING-PROPOSAL-2026-09-23.md)). Enforced through rule 8.
8. **Every protected operation has a row in the Core re-check vs controller-only
   enforcement matrix** ([workflow contract](WORKFLOW-CONTRACT.md#enforcement-matrix)); a new protected operation adds its row. Review-enforced.
9. **Observation is not authority** ([workflow contract, R3](WORKFLOW-CONTRACT.md#r3-autonomously-repairable-kernel-protected-verifier)).
   Prose only.
10. **No controller-specific state in the protected schema**
    ([orchestrator boundary](ORCHESTRATOR-BOUNDARY.md)). Prose only.
11. **Design test: replacing the methodology must not touch the ledger**
    ([planning strategies §2](PLANNING-STRATEGIES.md#2-kernel-invariants-versus-replaceable-methodology)).
    Prose only.
12. **`kernel/software/` is the replaceable reference controller, and deletable.** Prose
    only; rule 4 keeps the generic kernel from growing new dependencies on it.
