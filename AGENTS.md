# Repository guide for agents

This repository contains two independent systems. Choose the system before loading
reference material or running commands. These instructions apply to every provider.

## Start here

Read [the shared workflow](docs/agents/WORKFLOW.md), then follow one route:

| Task | Read next |
|---|---|
| Pramāṇa: corpus, retrieval, MCP, reader | [Pramāṇa invariants](pramana/docs/INVARIANTS.md), then the relevant topic in [the Pramāṇa index](pramana/docs/README.md) |
| Foundry: agent coordination and lifecycle | [Foundry documentation](foundry/docs/README.md); use its repair plan and current ticket evidence before touching execution paths |
| Documentation or repository orientation | [Documentation index](docs/README.md), [repository map](docs/REPO_MAP.md), [documentation maintenance](docs/MAINTAINING_DOCS.md) |

Load only the topic needed for the task. Do not preload the full plan, history,
rule book or tutorial. [Rule triggers](docs/agents/RULE_TRIGGERS.md) route to numbered
rules when relevant; [testing](docs/TESTING.md) separates documentation, umbrella,
Foundry and corpus checks.

`CLAUDE.md` and `GEMINI.md` are compatibility entry points to this file, not separate
policy. Other harnesses should be given this file explicitly when they do not load it.
Provider choice does not change repository rules or authorize a Foundry launch.
