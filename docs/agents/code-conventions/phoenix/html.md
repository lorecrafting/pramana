# Phoenix HTML and HEEx conventions

Applies to Pramāṇa HEEx templates, components and forms. Also read the shared
[Elixir conventions](../elixir.md). Add the [LiveView conventions](liveview.md) when
the template participates in live behavior, and [Phoenix core](core.md) when generated
layout/authenticated-route conventions apply.

- Use `~H` or `.html.heex` for Phoenix templates, not legacy `~E`.
- Build forms with `Phoenix.Component.form/1` and `inputs_for/1`, not the retired
  `Phoenix.HTML.form_for` or `Phoenix.HTML.inputs_for` APIs.
- Build form assigns with `to_form/2`, pass them as `<.form for={@form} ...>`, and
  access fields through `@form[:field]`.
- Give key elements such as forms and buttons unique, stable DOM IDs so tests and
  LiveView behavior can target them reliably.
- Put app-wide template imports/aliases in the web module's `html_helpers` block.
- Elixir has `if/else` but no `else if`/`elseif`; use `cond` or `case` for multiple
  branches.
- For literal `{` and `}` inside code/preformatted HEEx content, annotate the parent
  with `phx-no-curly-interpolation`.
- Use HEEx list syntax for conditional class values:

      <a class={["px-2 text-white", @some_flag && "py-5"]}>Text</a>

- Generate repeated template content with `<%= for ... do %>`, not `<% Enum.each %>`.
- HEEx comments use `<%!-- comment --%>`.
- Use `{...}` for attribute/value interpolation and `<%= ... %>` for block constructs
  inside tag bodies.

[Code convention router](../README.md)
