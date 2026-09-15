# PramanaWeb

Phoenix web application for the Pramāṇa corpus — MCP endpoint, LiveView reader, and
the `/check` citation verification screen.

## Starting the server

```bash
mix phx.server                  # http://localhost:4000
PRAMANA_EMBEDDING=1 mix phx.server  # enables BGE-M3 hybrid search (~80 s load, ~2.2 GB)
```

## Key routes

- `/` — search, bucketed by composition origin and text role
- `/inventory` — what is in this bake, and what is not
- `/survey?q=…` — every occurrence counted, with concentration
- `/passage?urn=…` — a line in its context, with variants, translations, parallels
- `/works/:id` — a work's structure, leading with provenance
- `/check` — paste a claim, get a verdict list (`verify_report` surface)

See [`docs/READER.md`](../../docs/READER.md) for full documentation.
