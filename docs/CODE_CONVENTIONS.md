# Framework Conventions

Repository coding conventions, not a claim that every guideline is mechanically enforced.
Elixir guidance applies to the relevant Elixir project; Phoenix, Ecto, HEEx and LiveView
guidance applies only where those frameworks are used, not to unrelated Foundry code.
This file is maintained by hand. See [testing](TESTING.md) for the actual checks.

<!-- phoenix:elixir-start -->
## Elixir guidelines

- Elixir lists **do not support index based access via the access syntax**

  **Never do this (invalid)**:

      i = 0
      mylist = ["blue", "green"]
      mylist[i]

  Instead, **always** use `Enum.at`, pattern matching, or `List` for index based list access:

      i = 0
      mylist = ["blue", "green"]
      Enum.at(mylist, i)

- Elixir variables are immutable, but can be rebound, so for block expressions like `if`, `case`, `cond`, etc
  you *must* bind the result of the expression to a variable:

      # VALID: we rebind the result of the `if`
      socket =
        if connected?(socket) do
          assign(socket, :val, val)
        end

- Prefer one independently maintained module per file. Existing grouped schemas and nested helper modules are exceptions; multiple modules in a file are not inherently a compilation error.
- Do not assume an arbitrary struct implements Access. Use direct fields (`my_struct.field`) or the struct's supported API; use `Ecto.Changeset.get_field/2` for changeset fields.
- Don't use `String.to_atom/1` on user input (memory leak risk)
- Predicate function names should not start with `is_` and should end in a question mark. Names like `is_thing` should be reserved for guards
- Named OTP processes require names in child specs: `{DynamicSupervisor, name: MyApp.MyDynamicSup}`
- Use bounded concurrency and explicit timeout/cancellation policy with `Task.async_stream/3`. Choose `timeout: :infinity` only when the operation has another justified lifecycle bound; it is not a universal default.

## Mix guidelines

- Read the docs and options before using tasks (by using `mix help task_name`)
- To debug test failures, run tests in a specific file with `mix test test/my_test.exs` or run all previously failed tests with `mix test --failed`
- `mix deps.clean --all` is **almost never needed**. **Avoid** using it unless you have good reason

## Test guidelines

- **Always use `start_supervised!/1`** to start processes in tests as it guarantees cleanup between tests
- **Avoid** `Process.sleep/1` and `Process.alive?/1` in tests
  - Instead of sleeping to wait for a process to finish, use `Process.monitor/1`:

      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}

   - Instead of sleeping to synchronize, use `_ = :sys.get_state/1` to ensure the process has handled prior messages
<!-- phoenix:elixir-end -->

<!-- phoenix:phoenix-start -->
## Phoenix guidelines

- Remember Phoenix router `scope` blocks include an optional alias which is prefixed for all routes within the scope. **Always** be mindful of this when creating routes within a scope to avoid duplicate module prefixes.
- You **never** need to create your own `alias` for route definitions — the `scope` provides the alias.
- `Phoenix.View` is no longer needed or included with Phoenix. Don't use it.
<!-- phoenix:phoenix-end -->

<!-- phoenix:ecto-start -->
## Ecto guidelines

- **Always** preload Ecto associations in queries when they'll be accessed in templates
- Schema fields always use the `:string` type, even for `:text` columns: `field :name, :string`
- `Ecto.Changeset.validate_number/2` **DOES NOT SUPPORT the `:allow_nil` option**. By default, Ecto validations only run if a change for the given field exists and the change value is not nil
- Use `Ecto.Changeset.get_field(changeset, :field)` to access changeset fields
- Fields set programmatically (like `user_id`) must not be in `cast` calls. Set them explicitly when creating the struct
- **Always** invoke `mix ecto.gen.migration migration_name_using_underscores` when generating migration files
<!-- phoenix:ecto-end -->

<!-- phoenix:html-start -->
## Phoenix HTML guidelines

- Phoenix templates **always** use `~H` or `.html.heex` files (HEEx), **never** `~E`
- **Always** use `Phoenix.Component.form/1` and `inputs_for/1`, **never** `Phoenix.HTML.form_for` or `Phoenix.HTML.inputs_for`
- When building forms, use `to_form/2` (`assign(socket, form: to_form(...))`) and `<.form for={@form} id="msg-form">`, then access fields via `@form[:field]`
- **Always** add unique DOM IDs to key elements (forms, buttons, etc.) — they can later be used in tests
- For "app wide" template imports, alias into the `my_app_web.ex`'s `html_helpers` block
- Elixir supports `if/else` but **does NOT support `else if` or `elseif`**. Use `cond` or `case` for multiple conditionals.
- HEEx literal curly brackets `{` `}` in `<pre>` or `<code>` blocks require `phx-no-curly-interpolation` on the parent tag
- HEEx class attrs support lists — always use `[...]` syntax:

      <a class={["px-2 text-white", @some_flag && "py-5"]}>Text</a>

- **Never** use `<% Enum.each %>` in templates — always use `<%= for item <- @collection do %>`
- HEEx HTML comments: `<%!-- comment --%>`
- Use `{...}` for interpolation in tag attributes, `<%= %>` for block constructs within tag bodies

  **Always**:

      <div id={@id}>
        {@my_assign}
        <%= if @some_block_condition do %>
          {@another_assign}
        <% end %>
      </div>
<!-- phoenix:html-end -->

<!-- phoenix:liveview-start -->
## Phoenix LiveView guidelines

- **Never** use the deprecated `live_redirect` and `live_patch`. Use `<.link navigate={href}>` and `<.link patch={href}>` in templates, `push_navigate` and `push_patch` in LiveViews
- **Avoid LiveComponent's** unless you have a strong, specific need
- LiveViews should be named like `AppWeb.WeatherLive` with a `Live` suffix

### LiveView streams

- **Always** use LiveView streams for collections:

      stream(socket, :messages, [new_msg])           # append
      stream(socket, :messages, [new_msg], reset: true)  # reset/filter
      stream(socket, :messages, [new_msg], at: -1)        # prepend
      stream_delete(socket, :messages, msg)                # delete

- In templates, set `phx-update="stream"` on the parent and use `@streams.stream_name`:

      <div id="messages" phx-update="stream">
        <div :for={{id, msg} <- @streams.messages} id={id}>
          {msg.text}
        </div>
      </div>

- Streams are **not** enumerable — don't use `Enum.filter/2` or `Enum.reject/2` on them. Refetch and re-stream with `reset: true`
- Streams do not support counting or empty states natively. Use a separate assign for counts, or Tailwind for empty states:

      <div id="tasks" phx-update="stream">
        <div class="hidden only:block">No tasks yet</div>
        <div :for={{id, task} <- @streams.tasks} id={id}>
          {task.name}
        </div>
      </div>

- When updating an assign that affects stream items, re-stream the items with `stream_insert/3`
- **Never** use the deprecated `phx-update="append"` or `phx-update="prepend"`

### LiveView JavaScript interop

- When using `phx-hook="MyHook"`, **must** also set `phx-update="ignore"`
- **Always** provide a unique DOM id alongside `phx-hook`
- Colocated hooks use `<script :type={Phoenix.LiveView.ColocatedHook}>` with names starting with `.` prefix (e.g., `.PhoneNumber`)
- External hooks go in `assets/js/` and are passed to the LiveSocket constructor
- Use `push_event/3` server→client and `this.handleEvent` on the client
- Use `this.pushEvent` client→server for reply-capable events

### LiveView tests

- Use `Phoenix.LiveViewTest` module functions
- Use `render_submit/2` and `render_change/2` for form tests
- Use `element/2` and `has_element?/2` — never test against raw HTML
- Test for presence of key elements (by ID), not text content
- Add debug output with LazyHTML selectors when facing element selector failures:

      html = render(view)
      document = LazyHTML.from_fragment(html)
      matches = LazyHTML.filter(document, "your-complex-selector")

### Form handling

- Always use `to_form/2` in the LiveView: `assign(socket, form: to_form(params))` or `to_form(changeset)`
- In templates: `<.form for={@form} id="todo-form">` and `<.input field={@form[:field]} type="text" />`
- Never pass a changeset directly to `<.form>` — always use `to_form/2`
- Never use `<.form let={f} ...>` — always use `<.form for={@form} ...>`
<!-- phoenix:liveview-end -->

## Phoenix v1.8 layout guidelines

- Always begin LiveView templates with `<Layouts.app flash={@flash} ...>` which wraps all inner content
- The `MyAppWeb.Layouts` module is aliased in the `my_app_web.ex` file, so you can use it without needing to alias it again
- Anytime you run into errors with no `current_scope` assign: you failed to follow the Authenticated Routes guidelines, or failed to pass `current_scope` to `<Layouts.app>`
- Phoenix v1.8 moved the `<.flash_group>` component to the `Layouts` module. **Never** call `<.flash_group>` outside of `layouts.ex`
- Use the `<.icon name="hero-x-mark" class="w-5 h-5"/>` component from `core_components.ex` for icons, **never** `Heroicons` modules

## JS and CSS guidelines

- **Use Tailwind CSS classes and custom CSS rules** for polished, responsive interfaces
- Tailwind v4: use the `@import "tailwindcss" source(none)` syntax in `app.css`:

      @import "tailwindcss" source(none);
      @source "../css";
      @source "../js";
      @source "../../lib/my_app_web";

- **Never** use `@apply` when writing raw CSS
- **Always** write your own Tailwind-based components instead of using daisyUI
- Only the `app.js` and `app.css` bundles are supported — no external vendor script `src` or link `href`
- You must import vendor deps into `app.js` and `app.css`
- **Never** write inline `<script>` tags within templates
