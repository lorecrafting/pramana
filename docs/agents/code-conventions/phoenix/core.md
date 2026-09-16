# Phoenix core conventions

Applies to Pramāṇa Phoenix routing, endpoints, layouts and generated web structure.
Also read the shared [Elixir conventions](../elixir.md).

## Router and module guidelines

- Phoenix router `scope` blocks can provide an alias that is prefixed to routes in
  the scope. Account for that alias so route modules are not double-prefixed.
- Do not add a redundant route `alias` when the `scope` already supplies it.
- `Phoenix.View` is no longer needed or included in current Phoenix applications.

## Phoenix 1.8 project/layout guidelines

These project-shape rules come from the Phoenix 1.8 generator and apply only where
Pramāṇa retains that generated structure.

- Begin LiveView templates with `<Layouts.app flash={@flash} ...>` when the generated
  layout contract applies.
- `MyAppWeb.Layouts`-style layout modules are normally already aliased by the web
  module; use the project's actual alias rather than adding another one.
- A missing `current_scope` assign usually means the route is outside the appropriate
  authenticated `live_session` or `current_scope` was not passed to the layout.
- Phoenix 1.8 moved `<.flash_group>` into the layouts module; keep it there.
- Use the project's imported `<.icon>` component instead of reaching for a separate
  Heroicons module when that generated component is available.

[Code convention router](../README.md) · [LiveView](liveview.md)
