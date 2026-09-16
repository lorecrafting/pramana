# Pramāṇa web

Phoenix MCP transport and LiveView reader over the core research domain.
Run the server from the repository root after [setup](../../docs/DEV_ENV.md).

| Route | Purpose |
|---|---|
| `/` | Search grouped by provenance |
| `/inventory` | Corpus inventory and gaps |
| `/survey` | Scoped occurrence counts |
| `/passage` | Source context, renderings and related evidence |
| `/works/:work_id` | Work structure and provenance |
| `/check` | Citation and declared-replay checking |
| `/mcp` | MCP transport, outside the browser pipeline |

The development dashboard is separate and enabled only with development routes.
The LiveViews call domain functions directly rather than reimplementing retrieval or
calling their own HTTP MCP endpoint.

[Reader](../../docs/READER.md) · [MCP](../../docs/MCP.md) · [Testing](../../../docs/TESTING.md)
