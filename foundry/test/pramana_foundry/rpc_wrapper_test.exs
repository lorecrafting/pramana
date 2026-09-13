defmodule PramanaFoundry.RPCWrapperTest do
  use ExUnit.Case, async: true

  alias PramanaFoundry.CLI.RPC

  @wrapper Path.expand("../../bin/pramana", __DIR__)
  @rpc_pattern ~r/\APramanaFoundry\.CLI\.RPC\.run\("([A-Za-z0-9_-]+)"\)\z/

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "foundry-rpc-wrapper-" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
      )

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    fake_release = Path.join(root, "fake-release")
    capture = Path.join(root, "rpc-code")
    stream_runner = Path.join(root, "stream-runner")
    eval_recorder = Path.join(root, "eval-recorder.exs")

    File.write!(fake_release, """
    #!/bin/sh
    if [ "$1" != "rpc" ]; then
      printf 'unexpected release command: %s\\n' "$1" >&2
      exit 65
    fi
    if [ -n "${RPC_CAPTURE:-}" ]; then
      printf '%s' "$2" > "$RPC_CAPTURE"
    fi
    if [ "${RPC_RECORD_DISPATCH:-0}" = "1" ]; then
      RPC_CODE="$2"
      export RPC_CODE
      PATH="$RPC_REAL_PATH"
      export PATH
      exec "$RPC_REAL_ELIXIR" -pa "$RPC_EBIN" "$RPC_EVAL_RECORDER"
    fi
    if [ "${RPC_EVAL:-0}" = "1" ]; then
      exec elixir -pa "$RPC_EBIN" -e "$2"
    fi
    if [ -n "${RPC_STDERR:-}" ]; then
      printf '%s' "$RPC_STDERR" >&2
    fi
    if [ -n "${RPC_STDOUT:-}" ]; then
      printf '%s' "$RPC_STDOUT"
    fi
    exit "${RPC_EXIT:-0}"
    """)

    File.write!(stream_runner, """
    #!/bin/sh
    "$RPC_WRAPPER" "$@" > "$RPC_STDOUT_CAPTURE" 2> "$RPC_STDERR_CAPTURE"
    """)

    File.write!(eval_recorder, """
    Code.compiler_options(ignore_module_conflict: true)

    defmodule PramanaFoundry.CLI do
      def main(argv) do
        File.write!(System.fetch_env!("RPC_DISPATCH_CAPTURE"), :erlang.term_to_binary(argv))
      end
    end

    try do
      Code.eval_string(System.fetch_env!("RPC_CODE"))
    rescue
      error ->
        IO.puts(:stderr, Exception.message(error))
        System.halt(65)
    end
    """)

    File.chmod!(fake_release, 0o700)
    File.chmod!(stream_runner, 0o700)

    %{
      capture: capture,
      eval_recorder: eval_recorder,
      fake_release: fake_release,
      root: root,
      stream_runner: stream_runner
    }
  end

  test "actual wrapper round-trips hostile-looking and empty literal values", ctx do
    interpolation = <<35>> <> "{1 + 1}"
    title = "quote \" slash \\ newline\nUnicode प्रमाण literal #{interpolation}"

    argv = [
      "ticket",
      "create",
      "--title",
      title,
      "--priority",
      "P0",
      "--acceptance",
      ""
    ]

    assert {"", 0} = run_wrapper(ctx, argv)
    assert {:ok, ^argv} = ctx.capture |> File.read!() |> token!() |> RPC.decode()
    assert title =~ interpolation
    refute title =~ "literal 2"
  end

  test "actual wrapper carries a large payload below the bound", ctx do
    title = String.duplicate("界", 20_000)
    argv = ["ticket", "create", "--title", title, "--priority", "P2"]

    assert {"", 0} = run_wrapper(ctx, argv)
    assert {:ok, ^argv} = ctx.capture |> File.read!() |> token!() |> RPC.decode()
  end

  test "actual wrapper rejects an oversized payload before release invocation", ctx do
    title = String.duplicate("x", 65_537)

    assert {output, 64} =
             run_wrapper(ctx, ["ticket", "create", "--title", title, "--priority", "P0"])

    assert output == "Error: RPC argument payload exceeds 65536 bytes\n"
    refute output =~ "Traceback"
    refute File.exists?(ctx.capture)
  end

  test "actual wrapper preserves remote stderr and exact nonzero status", ctx do
    stdout = "remote standard output\n"
    stderr = "remote rejected this command\n"
    stdout_capture = Path.join(ctx.root, "stdout")
    stderr_capture = Path.join(ctx.root, "stderr")

    assert {"", 42} =
             System.cmd(ctx.stream_runner, ["ticket", "list"],
               env: [
                 {"RPC_WRAPPER", @wrapper},
                 {"RPC_STDOUT_CAPTURE", stdout_capture},
                 {"RPC_STDERR_CAPTURE", stderr_capture},
                 {"PRAMANA_RELEASE", ctx.fake_release},
                 {"RPC_CAPTURE", ctx.capture},
                 {"RPC_STDOUT", stdout},
                 {"RPC_STDERR", stderr},
                 {"RPC_EXIT", "42"}
               ]
             )

    assert File.read!(stdout_capture) == stdout
    assert File.read!(stderr_capture) == stderr
  end

  test "actual wrapper reaches server-side empty and unknown-shape rejection", ctx do
    ebin = Path.expand("../../_build/test/lib/pramana_foundry/ebin", __DIR__)

    Enum.each([[], ["unknown", "literal " <> <<35>> <> "{1 + 1}"]], fn argv ->
      {output, status} =
        run_wrapper(ctx, argv, env: [{"RPC_EVAL", "1"}, {"RPC_EBIN", ebin}])

      assert status != 0
      assert output =~ "invalid RPC payload: unknown_command_shape"
      refute output =~ "literal 2"
      refute output =~ "Traceback"
    end)
  end

  test "actual evaluated wrapper rejects duplicate keys without dispatch", ctx do
    raw = ~S({"version":1,"argv":["ticket","list"],"argv":["unknown"]})
    forged_token = Base.url_encode64(raw, padding: false)
    tool_dir = Path.join(ctx.root, "forged-encoder")
    dispatch_capture = Path.join(ctx.root, "dispatch")
    File.mkdir_p!(tool_dir)

    Enum.each(["bash", "dirname"], fn executable ->
      File.ln_s!(System.find_executable(executable), Path.join(tool_dir, executable))
    end)

    File.write!(Path.join(tool_dir, "elixir"), """
    #!/bin/sh
    printf '%s' "$RPC_FORGED_TOKEN"
    """)

    File.chmod!(Path.join(tool_dir, "elixir"), 0o700)

    {output, status} =
      System.cmd(@wrapper, ["ticket", "list"],
        env: [
          {"PATH", tool_dir},
          {"PRAMANA_RELEASE", ctx.fake_release},
          {"RPC_CAPTURE", ctx.capture},
          {"RPC_FORGED_TOKEN", forged_token},
          {"RPC_RECORD_DISPATCH", "1"},
          {"RPC_REAL_ELIXIR", System.find_executable("elixir")},
          {"RPC_REAL_PATH", System.fetch_env!("PATH")},
          {"RPC_EBIN", Path.expand("../../_build/test/lib/pramana_foundry/ebin", __DIR__)},
          {"RPC_EVAL_RECORDER", ctx.eval_recorder},
          {"RPC_DISPATCH_CAPTURE", dispatch_capture}
        ],
        stderr_to_stdout: true
      )

    assert {output, status} == {"invalid RPC payload: duplicate_json_key\n", 65}
    assert ctx.capture |> File.read!() |> token!() == forged_token
    refute File.exists?(dispatch_capture)
  end

  test "missing or unexecutable Elixir encoder fails without invoking the release", ctx do
    tool_dir = Path.join(ctx.root, "tools-without-elixir")
    File.mkdir_p!(tool_dir)

    Enum.each(["bash", "dirname"], fn executable ->
      File.ln_s!(System.find_executable(executable), Path.join(tool_dir, executable))
    end)

    {output, status} =
      System.cmd(@wrapper, ["ticket", "list"],
        env: [
          {"PATH", tool_dir},
          {"PRAMANA_RELEASE", ctx.fake_release},
          {"RPC_CAPTURE", ctx.capture}
        ],
        stderr_to_stdout: true
      )

    assert status == 127
    assert output =~ "elixir: command not found"
    refute output =~ "Traceback"
    refute File.exists?(ctx.capture)

    File.write!(Path.join(tool_dir, "elixir"), "not executable")
    File.chmod!(Path.join(tool_dir, "elixir"), 0o600)

    {output, status} =
      System.cmd(@wrapper, ["ticket", "list"],
        env: [
          {"PATH", tool_dir},
          {"PRAMANA_RELEASE", ctx.fake_release},
          {"RPC_CAPTURE", ctx.capture}
        ],
        stderr_to_stdout: true
      )

    assert status == 126
    assert output =~ "elixir: Permission denied"
    refute output =~ "Traceback"
    refute File.exists?(ctx.capture)
  end

  test "an explicit invalid release override fails instead of falling back", ctx do
    missing = Path.join(ctx.root, "missing-release")
    expected = "Error: PRAMANA_RELEASE is not executable: #{missing}\n"

    assert {^expected, 69} =
             System.cmd(@wrapper, ["ticket", "list"],
               env: [{"PRAMANA_RELEASE", missing}],
               stderr_to_stdout: true
             )
  end

  defp run_wrapper(ctx, argv, opts \\ []) do
    extra_env = Keyword.get(opts, :env, [])

    System.cmd(@wrapper, argv,
      env: [
        {"PRAMANA_RELEASE", ctx.fake_release},
        {"RPC_CAPTURE", ctx.capture}
        | extra_env
      ],
      stderr_to_stdout: true
    )
  end

  defp token!(rpc_code) do
    [_, token] = Regex.run(@rpc_pattern, rpc_code)
    token
  end
end
