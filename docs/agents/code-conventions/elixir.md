# Elixir, Mix and ExUnit conventions

Applies to Elixir changes in both Pramāṇa and Foundry. These rules are adapted from
the Phoenix usage rules recorded in [`UPSTREAM.exs`](UPSTREAM.exs), with repository
exceptions retained deliberately.

## Elixir guidelines

- Elixir lists do not support index-based access via access syntax. Use `Enum.at/2`,
  pattern matching or `List` functions instead.
- Elixir variables are immutable but may be rebound. Bind the result of `if`, `case`,
  `cond` and similar expressions when the result is needed later:

      socket =
        if connected?(socket) do
          assign(socket, :val, val)
        end

- Prefer one independently maintained module per file. Existing grouped schemas and
  nested helper modules are exceptions; multiple modules in a file are not inherently
  a compilation error.
- Do not assume an arbitrary struct implements `Access`. Use direct fields
  (`my_struct.field`) or the struct's supported API; use
  `Ecto.Changeset.get_field/2` for changeset fields.
- Do not use `String.to_atom/1` on user input.
- Predicate function names should normally end in `?`; reserve `is_` names for guards.
- Named OTP processes require names in child specs, for example
  `{DynamicSupervisor, name: MyApp.MyDynamicSup}`.
- Use bounded concurrency and an explicit timeout/cancellation policy with
  `Task.async_stream/3`. Choose `timeout: :infinity` only when another justified
  lifecycle bound exists; it is not a universal default.

## Mix and project guidelines

- Read task documentation and options before invoking unfamiliar tasks with
  `mix help task_name`.
- To debug test failures, run a specific file with `mix test test/my_test.exs` or
  rerun previously failed tests with `mix test --failed`.
- `mix deps.clean --all` is almost never needed; avoid it unless there is a specific
  reason.
- **Pramāṇa only:** prefer the existing `Req` dependency for HTTP rather than adding a
  second HTTP client or using `:httpc` ad hoc without a documented need.
- **Pramāṇa only:** the umbrella has a `mix precommit` convenience alias, but validation
  is governed by [`docs/TESTING.md`](../../TESTING.md). Do not treat `mix precommit` as
  proof of corpus, live-provider or other checks it does not run.

## ExUnit and process-test guidelines

- Use `start_supervised!/1` for processes started by tests so cleanup is guaranteed.
- Avoid `Process.sleep/1` and `Process.alive?/1` as synchronization or death checks.
  Prefer `Process.monitor/1` and assert on the `:DOWN` message:

      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}

- To establish that a process handled earlier messages, prefer `_ = :sys.get_state(pid)`
  or another explicit synchronization boundary rather than sleeping.

[Code convention router](README.md)
