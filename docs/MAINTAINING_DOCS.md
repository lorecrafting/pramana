# Keeping documentation accurate and small

## One owner for each kind of fact

| Fact | Owner |
|---|---|
| Agent entry and task routing | [AGENTS.md](../AGENTS.md), [shared workflow](agents/WORKFLOW.md) |
| System boundaries | [Repository map](REPO_MAP.md) and each actual Mix project |
| Current public research API | [MCP](../pramana/docs/MCP.md), registered tools, tool schemas and tests |
| Operating checks | [Testing](TESTING.md), then the implementation of each check |
| Corpus counts | Generated blocks in [STATUS](../pramana/docs/STATUS.md) / [PLAN](PLAN.md), from a named database |
| Next work | [PLAN](PLAN.md); Foundry repair ordering belongs to [REPAIR-PLAN](../foundry/docs/REPAIR-PLAN.md) |
| Foundry investment direction and cross-project lessons | [Foundry strategy brief](../foundry/docs/STRATEGY.md); not ticket status or execution authority |
| Historical observations | [History](../pramana/docs/HISTORY.md), [proxy studies](../pramana/docs/PROXIES.md), dated review evidence |
| Product choices under discussion | [PRODUCT_STRATEGY](PRODUCT_STRATEGY.md); not a shipped-feature inventory |

Do not maintain a second authoritative copy in a model-specific instruction file.
Link to the owner and load it only when relevant. A table of contents is not an eager
import list. Counts of files, tools, tests and dependency versions should be derived
or linked, not repeated in onboarding prose.

## Document types

Label current reference, executable runbook, snapshot, design/proposal and historical
evidence distinctly. Claims such as "implemented", "verified" and "live" require
specific code and evidence, not only a plan checkbox. If a design became stale, keep
its rationale under a historical/design label and replace the operating instructions.
Prices, quotas, third-party capabilities and legal terms require fresh verification
before use; old tables are not current recommendations.

Prefer an index plus focused chapters to a long mixed-purpose file. Aim for roughly
100–300 lines per reference chapter, but keep a coherent contract or evidence record
intact when splitting would obscure it. The root agent router has a stricter tested
budget. During concurrent repair work, preserve the shared plan and repair evidence;
provide an index instead of reorganizing another worker's authority files.

## Editing checklist

Read the relevant source, schema, config and tests. Preserve stable rule numbers and
legacy heading bookmarks when moving content. Rebase relative links, including links
inside retained historical sections; do not silently drop the limitations or negative
results surrounding a positive measurement.

Run `elixir bin/check_docs.exs` after changes. Its checks cover routing, links,
fragments, entry-point budgets, rule triggers, and registered task/tool documentation.
They do not prove scientific truth, prose accuracy, external URL availability or
runtime guarantees. Historical exceptions must name a specific link and reason.

The figure generator scans only top-level `docs/*.md` and rewrites only its marked
blocks. It does not update arbitrary prose or regenerate framework conventions.
**There is no `pramana.docs.framework` task.** Framework guidance is maintained by
hand against the code and upstream documentation.

When a command can be destructive, paid or unavailable, state that beside the command.
A command mentioned in a proposal is not necessarily implemented. Link a documented
operating command to its task source or [the CLI index](../pramana/docs/CLI.md).

## Audits

An audit should name its baseline commit, coverage and exclusions, source evidence,
verified corrections, unresolved risks and actual checks run. A file inventory proves
coverage of the inventory, not verification of every statement inside every file.
See [the 2026-09-15 audit](audits/2026-09-15/README.md).
