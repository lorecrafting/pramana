# Whole-Foundry alignment disposition candidate

Frozen 2026-09-19 as a documentation-only candidate against pushed main
`2f603675e3feb1a65f0ce57a3bd69aa93deec29d` (tree
`73bc4bd386cf67d61cf8563814a45d1c1c9e0af0`). This record does not review or
self-approve the candidate. It changes no source, runtime, provider, credential, policy,
Git ref, deployment or activation permission.

[Authoritative repair plan](REPAIR-PLAN.md) ·
[workflow contract](WORKFLOW-CONTRACT.md) ·
[implementation log](IMPLEMENTATION-LOG.md) ·
[exact independent audit](ALIGNMENT-AUDIT-2026-09-19.md) ·
[FR-08 investigation](fr-08/investigation.md)

## Provenance and substantive candidate digest

The independent read-only audit is byte-identical to
`/tmp/foundry-alignment-audit-2f60367.md`; both have SHA-256
`c825b22bb857ccccd08171d79fae3b2d33ce76025fdf7dcb5db91ecc3ff63fe7`.

The canonical substantive inventory is the following ordered `sha256sum` output. Its
SHA-256 is `026900912764211a5735fda51bd7a7d8230d73d068f0d774d0855741ef96d19c`.
This evidence record is excluded to avoid a recursive self-hash.

| SHA-256 | Path |
|---|---|
| `9dcb85fae83d93c5a63e9e10d6262db5cfafc6d35c26ec18013757683f4a1a7d` | `README.md` |
| `904e4f4d94add68616d2489bf65c22831570cee2075e10cbdbba19a3cd048a94` | `docs/CATALOG.md` |
| `1f61fcaa5e38034dfd39e6c95fe71056a49eeb889825c99376bad8229fcc5da6` | `docs/PLAN.md` |
| `69fec8b3ec4d23aba00a56b88a51a0e83a0432fe14a20fc7693b6fb04d4f5098` | `docs/README.md` |
| `4494de03bbc6357a2e94e64ce0c908beba4626d4500986201a49f772fb461365` | `foundry/README.md` |
| `c825b22bb857ccccd08171d79fae3b2d33ce76025fdf7dcb5db91ecc3ff63fe7` | `foundry/docs/ALIGNMENT-AUDIT-2026-09-19.md` |
| `72c6775a9d616ab806c7c2c52aed260827c2736ea3ac0c4446d56ea00a20e40c` | `foundry/docs/IMPLEMENTATION-LOG.md` |
| `f81c804defe1d13189394d083813d22ba1834e8cfdea6ec1c1c4e7a5dbf836a9` | `foundry/docs/README.md` |
| `fdb7f4908704e1412ffe643ee3105ef2eeb8a673e521df90c651fa32606d508f` | `foundry/docs/REPAIR-PLAN.md` |
| `2e010531114d42ca99763bb12a441bc21ac21439621df023d2bfa87ce79271a5` | `foundry/docs/WORKFLOW-CONTRACT.md` |
| `0e44207ab6b00feb1a5a5f976bad70f3249d9215192d24171d75a997df610cb8` | `foundry/docs/fr-08/investigation.md` |

The Git binary diff over those 11 substantive paths has SHA-256
`53727b23723121c03c230df72cc7c0c875cb426cd5b0843a83e3f37a2f5d140c`.
Its exact stat is: 11 files changed, 994 insertions, 89 deletions. The preserved audit
accounts for 596 insertions.

## Disposition checksum

- REPAIR-PLAN remains the sole backlog. There are 23 parent ticket nodes: FR-01–FR-22
  plus FR-15a. H0/F are evidence checkpoints and A/B labels are parent slices; FR-23 and
  FR-24 do not exist. F23/F24 retain their existing owners.
- FR-07 remains complete for its accepted foundation. H0 reports supported/unavailable
  public capabilities honestly; FR-08A adds missing protected primitives and the
  substantive full handoff proof; FR-08B owns every-ingress one-reducer migration.
- Historical FR-04 PASS remains unchanged. The current ProcessGroup false-death defect is
  a bounded FR-04/10 correction before reuse for quiescence.
- FR-15a, FR-18 and FR-19 retain their parent acceptance while being split into A/B
  delivery slices. Bounded Pi-first feasibility moves early; OMP remains governing until
  explicit reviewed substitution.
- FR-17 depends on FR-18A/FR-19A, FR-20 depends on FR-17, and FR-13's FR-15 edge is
  removed only while core steering/policy/grant ownership is explicit in FR-08A/B and
  FR-15aB. The parsed graph is acyclic and has no unknown dependency.
- Current review tiers are Sol-medium implementation, Sol-high routine independent
  review, Astra-high first critical review, Astra-medium narrow critical re-review, and
  Astra-high re-escalation for invariant-family or abstraction changes. FR-22 is
  Astra-high; xhigh requires an explicit concrete cross-cutting audit choice. Historical
  labels remain unchanged.

## Model-free checks and limitations

- `elixir bin/check_docs.exs`: 80/80 passed after staging the exact audit and navigation.
- Dependency/routing parser: 29 table nodes/checkpoints/slices, 78 edges, acyclic, zero
  unknown dependencies; 24/24 F01–F24 rows retain exact owners and nonempty acceptance.
- `git diff --cached --check` scoped to the final changed paths: exit 0.
- Audit `cmp` and SHA-256: byte-identical, exit 0.
- Staged-path inspection: documentation/README paths only; unrelated untracked `apps/`
  remains untouched.

No Foundry suite, daemon, listener, host provisioning, provider call, credential check,
Git promotion, activation or physical storage-fault test was run. Source inspection and
documentation checks do not establish deployed/live truth. No independent review is
claimed. The next implementation candidate is separately owned: bounded ProcessGroup
correction and H0 report first; no FR-08 or ProcessGroup code is part of this candidate.
