# Phoenix LiveView conventions

Applies to Pramāṇa LiveView pages, processes, streams, hooks, forms and LiveView tests.
Also read [Phoenix core](core.md), [Phoenix HTML](html.md) and the shared
[Elixir conventions](../elixir.md).

## LiveView behavior

- Use `<.link navigate={href}>` / `<.link patch={href}>` in templates and
  `push_navigate/2` / `push_patch/2` in LiveViews instead of deprecated
  `live_redirect` / `live_patch`.
- Avoid `LiveComponent` unless there is a strong, specific need.
- Name LiveViews with a `Live` suffix, such as `AppWeb.WeatherLive`.

## Streams

- Use LiveView streams for UI collections:

      stream(socket, :messages, [new_msg])
      stream(socket, :messages, [new_msg], reset: true)
      stream(socket, :messages, [new_msg], at: -1)
      stream_delete(socket, :messages, msg)

- The template parent must have a stable DOM ID and `phx-update="stream"`, and child
  elements must consume the IDs supplied by `@streams`:

      <div id="messages" phx-update="stream">
        <div :for={{id, msg} <- @streams.messages} id={id}>
          {msg.text}
        </div>
      </div>

- Streams are not enumerable. Refetch/filter the underlying data and re-stream with
  `reset: true` rather than calling `Enum.filter/2` or `Enum.reject/2` on a stream.
- Track counts separately. For an empty state, use a sibling block that is shown only
  when it is the sole non-stream item, or maintain an explicit empty-state assign.
- Re-stream an item with `stream_insert/3` when another assign changes how that stream
  item renders.
- Do not use deprecated `phx-update="append"` or `phx-update="prepend"`.

## JavaScript interop

- When a `phx-hook` manages its own DOM, pair it with `phx-update="ignore"`.
- Every `phx-hook` element needs a unique DOM ID.
- Colocated hooks use `<script :type={Phoenix.LiveView.ColocatedHook}>` and names
  beginning with `.`, for example `.PhoneNumber`.
- External hooks live under `assets/js/` and are passed to the `LiveSocket`
  constructor.
- Use `push_event/3` server-to-client with `this.handleEvent` on the client; use
  `this.pushEvent` for client-to-server events that need a reply.

## LiveView tests

- Use `Phoenix.LiveViewTest` helpers.
- Drive forms with `render_submit/2` and `render_change/2`.
- Assert through stable element IDs and `element/2`, `has_element?/2` or selectors
  rather than raw HTML/text when the behavior is structural.
- Test outcomes rather than implementation details.
- When a selector fails, inspect a narrow `LazyHTML` selection rather than dumping
  the entire page.

## Forms

- Keep `to_form/2` output in a LiveView assign and pass that form to `<.form>`.
- Drive inputs from `@form[:field]`; do not pass or access the changeset directly in
  the template.
- Do not use `<.form let={f} ...>` when the form assign can drive the component.

[Code convention router](../README.md) · [Phoenix HTML](html.md)
