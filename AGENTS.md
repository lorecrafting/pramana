# Repository guide for agents

This repository holds Pramāṇa. Foundry moved out on 2026-09-23 and is no longer
a Pramāṇa workflow or pilot dependency.
These instructions apply to every provider.

## Start here

The repository root is the Pramāṇa Mix app: run Mix, asset, native and corpus
commands here. Read [the shared workflow](docs/agents/WORKFLOW.md), then follow one route:

| Task | Read next |
|---|---|
| Pramāṇa: corpus, retrieval, MCP, reader | [Pramāṇa invariants](docs/INVARIANTS.md), then the relevant topic in [the documentation index](docs/README.md) |
| Historical Foundry work | Moved to [lorecrafting/foundry](https://github.com/lorecrafting/foundry) on 2026-09-23; the pre-split history stays here. Current Pramāṇa work uses this repository's workflow |
| Documentation or repository orientation | [Documentation index](docs/README.md), [repository map](docs/REPO_MAP.md), [documentation maintenance](docs/MAINTAINING_DOCS.md) |

Load only the topic needed for the task. Do not preload the full plan, history,
rule book or tutorial. [Rule triggers](docs/agents/RULE_TRIGGERS.md) route to numbered
rules when relevant; [testing](docs/TESTING.md) separates documentation, application
and corpus checks.

`CLAUDE.md` and `GEMINI.md` are compatibility entry points to this file, not separate
policy. Other harnesses should be given this file explicitly when they do not load it.
Provider choice does not change repository rules.


<!-- phoenix-gen-auth-start -->
## Authentication

- **Always** handle authentication flow at the router level with proper redirects
- **Always** be mindful of where to place routes. `phx.gen.auth` creates multiple router plugs:
  - A plug `:fetch_current_scope_for_user` that is included in the default browser pipeline
  - A plug `:require_authenticated_user` that redirects to the log in page when the user is not authenticated
  - In both cases, a `@current_scope` is assigned to the Plug connection
  - A plug `redirect_if_user_is_authenticated` that redirects to a default path in case the user is authenticated - useful for a registration page that should only be shown to unauthenticated users
- **Always let the user know in which router scopes and pipeline you are placing the route, AND SAY WHY**
- `phx.gen.auth` assigns the `current_scope` assign - it **does not assign a `current_user` assign**
- Always pass the assign `current_scope` to context modules as first argument. When performing queries, use `current_scope.user` to filter the query results
- To derive/access `current_user` in templates, **always use the `@current_scope.user`**, never use **`@current_user`** in templates
- Anytime you hit `current_scope` errors or the logged in session isn't displaying the right content, **always double check the router and ensure you are using the correct plug as described below**

### Routes that require authentication

Controller routes must be placed in a scope that sets the `:require_authenticated_user` plug:

    scope "/", AppWeb do
      pipe_through [:browser, :require_authenticated_user]

      get "/", MyControllerThatRequiresAuth, :index
    end

### Routes that work with or without authentication

Controllers automatically have the `current_scope` available if they use the `:browser` pipeline.

<!-- phoenix-gen-auth-end -->