# Pramāṇa agent route

Read the [shared workflow](../docs/agents/WORKFLOW.md), then
[Pramāṇa invariants](docs/INVARIANTS.md) and the relevant topic in
[Pramāṇa documentation](docs/README.md). This directory is the Mix umbrella root.

Run project commands here, not from the Git root. Raw corpus/model data has a
separate location contract: [migration guide](../docs/LAYOUT_MIGRATION.md).
[Testing](../docs/TESTING.md) distinguishes code, corpus and provider evidence.

Foundry is the independent sibling at `../foundry/`; do not add it to `apps/`,
share its state or change its repair authority as part of a Pramāṇa task.
