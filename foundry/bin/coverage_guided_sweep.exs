# Coverage-guided guard mutation sweep (EV-1).
#
# Same mutations as bin/guard_mutation_sweep.exs, same verdict vocabulary, a fraction of
# the tests per trial. Two phases, per docs/COVERAGE-GUIDED-SWEEP.md:
#
#   1. MAP. One instrumented run of the workflow suites. Every `require_*(` call site is
#      prefixed with `(PramanaFoundry.EV1Probe.hit(site); <call>)`, which records the site in
#      an ETS table BEFORE the call runs, so a call that raises is still attributed; an injected `setup` snapshots the table around every test. Result: site ->
#      the tests that evaluated it. Hits that land between tests belong to a `setup_all`
#      and go to every test of the module that owns it.
#   2. TRIAL. Each site is neutralised (`:ok` spliced over the call, exactly as the old
#      sweep does) and only its mapped tests run. A site no test evaluates gets no trial and
#      is reported as `no_tests`, never as `survived`.
#
# Soundness rests on one property: a test that never evaluates site S is bit-identical
# under S's mutant, so it cannot change verdict. That needs (a) every evaluation of S to be
# recorded against the right test, which is why the mapping run is serial (`--max-cases 1`)
# and probes are inserted by the same scanner that mutates, and (b) a deterministic suite,
# which `--seed 0` and the walks' own seeds give.
#
# Two ways the soundness property fails, one checked and one not:
#
#   * A test that observes the kernel by READING its source rather than running it.
#     `KernelSearch.declared_reasons/0` does. Checked every run: each site's mutant is fed to
#     that function's own `reasons_in/1`, and a site whose mutant changes it is flagged.
#   * A test whose EXISTENCE depends on the kernel at compile time (tests generated in a
#     `for` over kernel output). Its window never sees the site; the hits land before any
#     window and are charged to whichever module runs first. Not checked; none of the five
#     suites does it today.
#
# The map is test-granular, and the three suites with a setup_all search evaluate almost
# every site in that setup_all, so every trial that reaches them pays for a whole search.
# That, not the per-test scoping, is where the remaining time goes.
#
# Every run prints its red controls, its denominators and the diff against the committed
# 2026-09-21 answer key, and re-judges each disagreement against the whole workflow set
# (the old sweep's judgement). Nothing below writes to the repository.
#
#   cd foundry && TMPDIR=/private/tmp elixir bin/coverage_guided_sweep.exs
#   EV1_WORKERS=<n>     parallel trial workers (default 2)
#   EV1_SITES=<file>    only these sites, one per line: a call text (same key as SWEEP_SITES)
#                       selects every site with that text; a full label, `<text> <file>:<line>`,
#                       selects that one site. The two red-control sites always run.
#
# The kernel is kernel.ex plus one module per event family under kernel/ (split by family on
# 2026-09-23). The sweep reads them as ONE source, the files joined by a boundary line no
# splice can touch, so every offset, splice and probe below works on one binary exactly as it
# did on one file; `write_kernel/2` splits it back into files. The answer key's revisions
# predate the split and are single-file sources, which carry no boundary.
#
# Worker roots live under /private/tmp/ev1-*. They are not the old sweep's roots, and the lock
# is this tool's own, /private/tmp/ev1-coverage-sweep.lock (see EV1.lock!/0). Stop a run with
# SIGTERM (`kill <pid>`), which releases the lock and kills the running `mix test` children;
# Ctrl-C and SIGKILL leave both behind.

defmodule EV1 do
  @kernel "lib/pramana_foundry/workflow/kernel.ex"
  @boundary "\n# EV1 file boundary: "
  @raw "docs/fr-08/fr08b-sweep-2026-09-21-raw.txt"
  @suites ~w(
    test/pramana_foundry/workflow/kernel_test.exs
    test/pramana_foundry/workflow/r4_coverage_test.exs
    test/pramana_foundry/workflow/r4_exhaustive_test.exs
    test/pramana_foundry/workflow/kernel_properties_test.exs
    test/pramana_foundry/workflow/r4_guard_reachability_test.exs
  )
  # The two suites with no setup_all search; measured 0.6s of tests against ~230s of
  # setup_all across the other three in the 2026-09-22 baseline.
  @cheap_suites ~w(
    test/pramana_foundry/workflow/kernel_test.exs
    test/pramana_foundry/workflow/r4_coverage_test.exs
  )
  @probe "PramanaFoundry.EV1Probe"
  @probe_path "lib/pramana_foundry/ev1_probe.ex"

  # Event and State hold no guard call and are not the reducer's; KernelSearch excludes them too.
  def targets,
    do:
      [@kernel | Path.wildcard("lib/pramana_foundry/workflow/kernel/**/*.ex")] --
        ~w(lib/pramana_foundry/workflow/kernel/event.ex lib/pramana_foundry/workflow/kernel/state.ex)

  def read_kernel(root \\ "."),
    do: Enum.map_join(targets(), &(@boundary <> &1 <> "\n" <> File.read!(Path.join(root, &1))))

  # Writes only the files whose content differs, so a trial recompiles the one it mutated.
  def write_kernel(root, source) do
    for chunk <- String.split(source, @boundary, trim: true) do
      [file, content] = String.split(chunk, "\n", parts: 2)
      path = Path.join(root, file)
      if File.read!(path) != content, do: File.write!(path, content)
    end

    :ok
  end

  def suites, do: @suites

  # ── Lock and children ──
  #
  # One run at a time: make_root/1 rm_rf's /private/tmp/ev1-*, so a second run would delete
  # the first one's roots mid-trial. The lock is this tool's own, not the old sweep's
  # sentinel, and bin/preflight.sh does not read it. It is taken before anything is touched
  # and released by every exit this script controls: halt/1 (never a bare System.halt,
  # which skips at_exit and is how the old sweep leaked its sentinel), a crash or normal end
  # (at_exit), and SIGTERM (the trap below, which also kills the running `mix test`
  # children). Ctrl-C and SIGKILL cannot be trapped: they leave the lock and the children.
  @lock "/private/tmp/ev1-coverage-sweep.lock"
  @children :ev1_children

  def lock! do
    case File.open(@lock, [:write, :exclusive]) do
      {:ok, io} ->
        IO.write(io, "#{System.pid()}\n")
        File.close(io)

      {:error, :eexist} ->
        IO.puts(
          "another coverage-guided sweep holds #{@lock} (pid #{String.trim(File.read!(@lock))}). " <>
            "If `ps -p <pid>` shows no such process it was stopped by Ctrl-C or SIGKILL: " <>
            "kill any orphaned `mix test` under /private/tmp/ev1-*, then delete the lock."
        )

        System.halt(5)
    end

    :ets.new(@children, [:named_table, :public, :set])
    System.at_exit(fn _ -> release() end)
    {:ok, _} = System.trap_signal(:sigterm, fn -> release() end)
    :ok
  end

  def release do
    if :ets.whereis(@children) != :undefined do
      for {pid} <- :ets.tab2list(@children), do: System.cmd("kill", ["-TERM", "#{pid}"])
    end

    File.rm(@lock)
    :ok
  end

  def halt(status) do
    release()
    System.halt(status)
  end

  # ── Scanner: verbatim from bin/guard_mutation_sweep.exs, including its red control ──

  def call_sites(source) do
    Regex.scan(~r/(?<![a-z_])(require_[a-z_]+\()/, source, return: :index)
    |> Enum.reject(fn [_, {start, _len}] ->
      line_start =
        case :binary.matches(binary_part(source, 0, start), "\n") do
          [] -> 0
          matches -> matches |> List.last() |> elem(0) |> Kernel.+(1)
        end

      # `def` too: a guard several families share is public in the family that owns it.
      String.trim(binary_part(source, line_start, start - line_start)) in ~w(def defp)
    end)
    |> Enum.map(fn [_, {start, len}] ->
      {depth, stop} =
        Enum.reduce_while((start + len)..(byte_size(source) - 1)//1, {1, start + len}, fn i,
                                                                                          {d, _} ->
          case binary_part(source, i, 1) do
            "(" -> {:cont, {d + 1, i}}
            ")" -> if d == 1, do: {:halt, {0, i}}, else: {:cont, {d - 1, i}}
            _ -> {:cont, {d, i}}
          end
        end)

      if depth == 0, do: {binary_part(source, start, stop - start + 1), start}, else: nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  def line_of(source, offset),
    do: source |> binary_part(0, offset) |> :binary.matches("\n") |> length() |> Kernel.+(1)

  # `<text> <file>:<line>` in the joined kernel; `<text> :<line>` in a single-file source,
  # which is the shape the 2026-09-21 answer key's labels were printed in.
  def label(source, {text, offset}) do
    before = binary_part(source, 0, offset)

    case :binary.matches(before, @boundary) do
      [] ->
        "#{text} :#{line_of(source, offset)}"

      matches ->
        {at, len} = List.last(matches)
        rest = binary_part(before, at + len, byte_size(before) - at - len)
        [file, body] = String.split(rest, "\n", parts: 2)
        "#{text} #{Path.basename(file)}:#{length(:binary.matches(body, "\n")) + 1}"
    end
  end
  # What the old sweep printed: the first 64 characters of the label.
  def label64(source, site), do: String.slice(label(source, site), 0, 64)

  @scanner_fixture """
  defp require_defined(x), do: :ok
  def require_public(x), do: :ok
  defp handler(t, e) do
    with :ok <- require_one(t),
         :ok <- require_two(t, e["payload"]["k"]),
         :ok <-
           require_multiline(
             t,
             e
           ) do
      {:ok, t}
    end
  end
  defp dispatch(t, d) do
    case d do
      "x" -> require_tail(t)
      "y" -> with :ok <- require_one(t), do: require_nested(t)
      "z" -> if true, do: require_inline(t), else: :ok
    end
  end
  """

  def scanner_red_control! do
    expected =
      ~w(require_one require_two require_multiline require_tail require_one require_nested
         require_inline)
      |> Enum.sort()

    found =
      @scanner_fixture
      |> call_sites()
      |> Enum.map(fn {text, _} -> text |> String.split("(") |> hd() end)
      |> Enum.sort()

    if found != expected do
      IO.puts(
        "RED CONTROL FAILED - scanner: expected #{inspect(expected)}, found #{inspect(found)}"
      )

      halt(4)
    end

    IO.puts("red control (scanner sees every guard shape): ok")
  end

  # ── Splicing ──

  def splice(source, {text, offset}, replacement) do
    binary_part(source, 0, offset) <>
      replacement <>
      binary_part(source, offset + byte_size(text), byte_size(source) - offset - byte_size(text))
  end

  def mutate(source, site), do: splice(source, site, ":ok")

  # Probes are inserted last-offset first so earlier offsets stay valid. No newline is
  # added, so kernel line numbers are unchanged in the instrumented copy. The hit is recorded
  # before the call is evaluated: `hit(i, call)` evaluated the call first, so a guard that
  # raised (apply/2 rescues it as :kernel_raised) was never attributed to its test.
  def instrument(source, sites) do
    sites
    |> Enum.with_index()
    |> Enum.sort_by(fn {{_, offset}, _} -> -offset end)
    |> Enum.reduce(source, fn {{text, _} = site, index}, acc ->
      splice(acc, site, "(#{@probe}.hit(#{index}); #{text})")
    end)
  end

  # ── Roots ──

  # Hard links for the read-only parts, a real copy of the build so a worker's compiler
  # output never lands on an inode the repository's own _build shares.
  def make_root(name) do
    root = "/private/tmp/#{name}"
    File.rm_rf!(root)
    File.mkdir_p!(root)

    {_, 0} =
      System.cmd("cp", [
        "-al",
        "lib",
        "test",
        "config",
        "docs",
        "mix.exs",
        "mix.lock",
        "deps",
        root
      ])

    if File.dir?("_build/test"),
      do: {_, 0} = System.cmd("cp", ["-R", "_build/test", Path.join(root, "_build")])

    # Break the links on the files this tool rewrites, so writing them cannot reach the repo.
    for rel <- targets() ++ ["test/test_helper.exs" | @suites] do
      path = Path.join(root, rel)
      content = File.read!(path)
      File.rm!(path)
      File.write!(path, content)
    end

    root
  end

  # A port rather than System.cmd, for the child's OS pid: release/0 kills it on SIGTERM.
  def mix_test(root, args) do
    port =
      Port.open({:spawn_executable, System.find_executable("mix")}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args: ["test" | args] ++ ["--seed", "0"],
        cd: root,
        env: [
          {~c"TMPDIR", ~c"/private/tmp"},
          {~c"MIX_BUILD_PATH", String.to_charlist(Path.join(root, "_build"))}
        ]
      ])

    {:os_pid, pid} = Port.info(port, :os_pid)
    :ets.insert(@children, {pid})
    out = collect(port, [])
    :ets.delete(@children, pid)
    out
  end

  defp collect(port, acc) do
    receive do
      {^port, {:data, data}} -> collect(port, [acc | data])
      {^port, {:exit_status, _}} -> IO.iodata_to_binary(acc)
    end
  end

  # This repository's formatter prints one `Result:` line, in one of these shapes:
  #
  #   Result: 85 passed[, 113 excluded]          green
  #   Result: 3/4 passed[, 1 invalid]            a test failed
  #   Result: 0 tests, 1 invalid[, 197 excluded] every selected test invalid: a setup_all
  #                                              failed and --max-failures stopped there
  #
  # An invalid test is one whose setup_all failed, which a mutation can cause and which is a
  # catch. The third shape was read as a build error by the first version of this parser,
  # and three sites the answer key caught came back "not a verdict" on the first full run.
  # Anything without a Result line is a build error, reported as such rather than read as a
  # pass — the old sweep once reported every guard untested because nothing matched and the
  # catch-all said pass. Returns {:ok, ran, failed} or {:error, why}. Pinned at startup by
  # `summary_red_control!/0`.
  def summary(out) do
    with [_, line] <- Regex.run(~r/^Result: (.*)$/m, out) do
      invalid =
        case Regex.run(~r/(\d+) invalid/, line) do
          [_, n] -> String.to_integer(n)
          nil -> 0
        end

      cond do
        m = Regex.run(~r/^(\d+)\/(\d+) passed/, line) ->
          [_, passed, total] = Enum.map(m, &int_or_self/1)
          {:ok, total, total - passed + invalid}

        m = Regex.run(~r/^(\d+) passed/, line) ->
          [_, passed] = Enum.map(m, &int_or_self/1)
          {:ok, passed, invalid}

        m = Regex.run(~r/^(\d+) tests?\b/, line) ->
          [_, ran] = Enum.map(m, &int_or_self/1)
          {:ok, ran, invalid}

        true ->
          {:error, {:unparsed_result, line}}
      end
    else
      nil -> {:error, :no_result_line}
    end
  end

  defp int_or_self(s), do: if(s =~ ~r/^\d+$/, do: String.to_integer(s), else: s)

  def summary_red_control! do
    cases = [
      {"Result: 85 passed, 113 excluded", {:ok, 85, 0}},
      {"Result: 3/4 passed", {:ok, 4, 1}},
      {"Result: 0/36 passed, 1 invalid", {:ok, 36, 37}},
      # ExUnit 1.20 counts an invalid test in neither tests nor failures: a failing setup_all
      # beside passing tests prints this, and it is a catch.
      {"Result: 36 passed, 1 invalid", {:ok, 36, 1}},
      {"Result: 0 tests, 1 invalid", {:ok, 0, 1}},
      {"Result: 0 tests, 1 invalid, 197 excluded", {:ok, 0, 1}},
      {"== Compilation error in file lib/x.ex ==", {:error, :no_result_line}}
    ]

    for {out, want} <- cases, summary("noise\n" <> out <> "\nmore") != want do
      IO.puts("RED CONTROL FAILED - summary(#{inspect(out)}) is not #{inspect(want)}")
      halt(4)
    end

    IO.puts("red control (result parser, #{length(cases)} shapes): ok")
  end

  # ── Phase 1: map ──

  @probe_source """
  defmodule PramanaFoundry.EV1Probe do
    @moduledoc false
    @table :ev1_hits
    @log "LOG_PATH"

    def start do
      :ets.new(@table, [:named_table, :public, :set])
      File.write!(@log, "")
    end

    def hit(site) do
      if :ets.whereis(@table) != :undefined, do: :ets.insert(@table, {site})
      :ok
    end

    # Runs in the test process before every test. Whatever is in the table now was
    # evaluated between the previous test's end and this one's start: a setup_all, so it
    # belongs to every test of this module. on_exit runs after the test and before ExUnit
    # starts the next one, so the window is exact.
    def window(ctx) do
      record("module", ctx, take())
      ExUnit.Callbacks.on_exit(fn -> record("test", ctx, take()) end)
      :ok
    end

    defp take do
      hits = @table |> :ets.tab2list() |> Enum.map(&elem(&1, 0)) |> Enum.sort()
      :ets.delete_all_objects(@table)
      hits
    end

    defp record(kind, ctx, hits) do
      File.write!(
        @log,
        Enum.join([kind, inspect(ctx.module), ctx.file, ctx.test, Enum.join(hits, ",")], "\\t") <>
          "\\n",
        [:append]
      )
    end
  end
  """

  def map_sites(root, original, sites) do
    log = Path.join(root, "ev1_hits.log")
    File.write!(Path.join(root, @probe_path), String.replace(@probe_source, "LOG_PATH", log))
    write_kernel(root, instrument(original, sites))

    helper = Path.join(root, "test/test_helper.exs")
    File.write!(helper, File.read!(helper) <> "\n#{@probe}.start()\n")

    rewritten =
      for suite <- @suites do
        path = Path.join(root, suite)
        source = File.read!(path)
        marker = ~r/^(\s*)use ExUnit\.Case(.*)$/m

        unless Regex.match?(marker, source) do
          IO.puts("cannot inject the probe window into #{suite}: no `use ExUnit.Case` line")
          halt(4)
        end

        File.write!(
          path,
          Regex.replace(
            marker,
            source,
            "\\1use ExUnit.Case\\2; setup(ctx, do: #{@probe}.window(ctx))",
            global: false
          )
        )

        suite
      end

    started = System.monotonic_time(:millisecond)
    out = mix_test(root, @suites ++ ["--max-cases", "1"])
    elapsed_ms = System.monotonic_time(:millisecond) - started

    {tests_ran, failures} =
      case summary(out) do
        {:ok, t, f} ->
          {t, f}

        {:error, why} ->
          IO.puts("mapping run produced no test summary (#{why}); output:\n#{out}")
          halt(4)
      end

    if failures != 0 do
      IO.puts(
        "mapping run is red (#{failures} failures) on unmutated source; nothing measured:\n#{out}"
      )

      halt(4)
    end

    rows =
      log
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.map(fn row ->
        # A test is {file, name}, not {file, line}: r4_coverage_test generates one test per
        # contract row inside a `for`, so dozens of tests share one line and `file:line`
        # selected all of them (measured: 125 ran for 58 asked).
        [kind, mod, file, name, hits] = String.split(row, "\t")
        file = Path.relative_to(file, root)
        hits = hits |> String.split(",", trim: true) |> Enum.map(&String.to_integer/1)
        {kind, mod, {file, name}, hits}
      end)

    tests = for {"test", _, test, _} <- rows, do: test
    windows = length(tests)

    if windows != tests_ran do
      IO.puts(
        "RED CONTROL FAILED - #{tests_ran} tests ran but #{windows} test windows were recorded"
      )

      halt(4)
    end

    tests_of_module =
      rows
      |> Enum.filter(&match?({"test", _, _, _}, &1))
      |> Enum.group_by(&elem(&1, 1), &elem(&1, 2))

    # site index -> set of tests
    direct =
      for {"test", _, test, hits} <- rows, hit <- hits, reduce: %{} do
        acc -> Map.update(acc, hit, MapSet.new([test]), &MapSet.put(&1, test))
      end

    via_setup_all =
      for {"module", mod, _, hits} <- rows, hits != [], hit <- hits, reduce: %{} do
        acc ->
          Map.update(
            acc,
            hit,
            MapSet.new(tests_of_module[mod] || []),
            &MapSet.union(&1, MapSet.new(tests_of_module[mod] || []))
          )
      end

    site_tests =
      for index <- 0..(length(sites) - 1), into: %{} do
        {index,
         MapSet.union(
           Map.get(direct, index, MapSet.new()),
           Map.get(via_setup_all, index, MapSet.new())
         )}
      end

    %{
      site_tests: site_tests,
      tests_total: tests_ran,
      rewritten: length(rewritten),
      elapsed_ms: elapsed_ms,
      setup_all_sites: via_setup_all |> Map.keys() |> length(),
      # Which modules had hits outside any test window, and how many distinct sites. Read
      # against the suites: a module with no setup_all appearing here means hits landed
      # from somewhere else (compile time, a previous module's teardown) and were charged
      # to it, which is sound only in the over-approximating direction.
      setup_all_modules:
        for({"module", mod, _, hits} <- rows, hits != [], do: {mod, length(hits)})
    }
  end

  # ── Phase 2: trial ──

  # `file:l1:l2` per file, one mix invocation, stopping at the first failure. The count
  # of tests that ran must equal the number requested, or the selection failed and the
  # result is not a verdict.
  def trial(_root, _original, _site, []), do: {:no_tests, 0, 0}

  # Cheapest first, as the old sweep does with whole files: the two suites without a
  # setup_all search run alone, and the three that each run a search only if nothing has
  # caught the mutation yet. The mutant is compiled once; the second invocation reuses it.
  def trial(root, original, site, tests) do
    write_kernel(root, mutate(original, site))
    started = System.monotonic_time(:millisecond)

    {cheap, searching} = Enum.split_with(tests, fn {file, _} -> file in @cheap_suites end)

    verdict =
      case run_selected(root, cheap) do
        :survived -> run_selected(root, searching)
        other -> other
      end

    write_kernel(root, original)
    {verdict, length(tests), System.monotonic_time(:millisecond) - started}
  end

  defp run_selected(_root, []), do: :survived

  defp run_selected(root, tests) do
    files = tests |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> Enum.sort()
    # A nil name is the whole file: the arbiter's old-sweep judgement.
    only =
      Enum.flat_map(tests, fn {_, name} -> if name, do: ["--only", "test:#{name}"], else: [] end)

    wanted = Enum.count(tests, fn {_, name} -> name end)

    # Running MORE tests than mapped is sound (an extra failing test is a real failure under
    # the mutant); running fewer means the selection lost a test and the result is not a
    # verdict. Two files sharing a test name is the only way ran exceeds wanted.
    out = mix_test(root, files ++ only ++ ["--max-failures", "1"])

    case summary(out) do
      {:ok, _ran, failures} when failures > 0 -> :caught
      {:ok, ran, 0} when ran >= wanted -> :survived
      {:ok, ran, 0} -> {:selection_error, ran, wanted}
      # The tail is kept: a build error is not a verdict, and the reason decides whether it
      # is the mutant (a real compile failure) or the harness.
      {:error, why} -> {:build_error, why, out |> String.split("\n") |> Enum.take(-12)}
    end
  end

  # ── Answer key: the 2026-09-21 raw output, keyed to today's sites ──

  # Verdicts per label64, later runs overriding earlier ones (runs 2 and 3 re-swept sites
  # whose tests were added after run 1). A label64 shared by several sites of one long
  # text carries a list; it is unambiguous only if every verdict in it agrees.
  def raw_verdicts do
    @raw
    |> File.read!()
    |> String.split(~r/^=== run \d/m)
    |> Enum.drop(1)
    |> Enum.reduce(%{}, fn run, acc ->
      run
      |> String.split("\n")
      |> Enum.flat_map(fn line ->
        case Regex.run(~r/^\s+sweep-w\d+ (.{1,64}?) — (caught|survived|build_error)$/, line) do
          [_, l64, v] -> [{l64, String.to_atom(v)}]
          nil -> []
        end
      end)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Enum.reduce(acc, fn {l64, verdicts}, acc -> Map.put(acc, l64, verdicts) end)
    end)
  end

  # The revision the raw output was produced from is not written in it. Find it: the
  # kernel revision whose scanned labels reproduce every label the raw run 1 printed.
  def answer_key_revision(raw) do
    {log, 0} = System.cmd("git", ["log", "--format=%h", "-20", "--", @kernel])
    labels = Map.keys(raw) |> MapSet.new()

    Enum.find(String.split(log, "\n", trim: true), fn rev ->
      case System.cmd("git", ["show", "#{rev}:./#{@kernel}"], stderr_to_stdout: true) do
        {source, 0} ->
          scanned = source |> call_sites() |> Enum.map(&label64(source, &1)) |> MapSet.new()
          MapSet.subset?(labels, scanned) and MapSet.subset?(scanned, labels)

        _ ->
          false
      end
    end)
  end

  # old site -> verdict, then old -> new by (text, occurrence order). Line numbers moved
  # since 2026-09-21, occurrence order did not; a text whose count changed is reported.
  # The 2026-09-23 family split DID move it for a text that now occurs in several family
  # files (e.g. `require_phase(ticket, ~w(developing))`): such a pairing can be wrong, which
  # surfaces as a disagreement, and every disagreement goes to the full-set arbiter below.
  def answer_key(new_source, new_sites) do
    raw = raw_verdicts()
    rev = answer_key_revision(raw)

    if rev == nil do
      IO.puts("no kernel revision in the last 20 reproduces the raw answer key's labels")
      halt(4)
    end

    {old_source, 0} = System.cmd("git", ["show", "#{rev}:./#{@kernel}"])
    old_sites = call_sites(old_source)

    old_verdicts =
      Map.new(old_sites, fn site ->
        verdict =
          case Enum.uniq(raw[label64(old_source, site)]) do
            [v] -> v
            vs -> {:ambiguous, vs}
          end

        {site, verdict}
      end)

    by_text = fn sites -> Enum.group_by(sites, &elem(&1, 0)) end
    old_by_text = by_text.(old_sites)
    new_by_text = by_text.(new_sites)

    expected =
      Map.new(
        for {text, news} <- new_by_text,
            olds = Map.get(old_by_text, text, []),
            pair <-
              if(length(olds) == length(news),
                do: Enum.zip(news, Enum.map(olds, &old_verdicts[&1])),
                else: Enum.map(news, &{&1, {:no_key, length(olds), length(news)}})
              ),
            do: pair
      )

    gone =
      for {text, olds} <- old_by_text,
          not Map.has_key?(new_by_text, text),
          do: {text, length(olds)}

    %{
      revision: rev,
      old_sites: length(old_sites),
      expected: expected,
      gone: gone,
      new_source: new_source
    }
  end
end

# ── main ──

EV1.lock!()
EV1.scanner_red_control!()
EV1.summary_red_control!()

original = EV1.read_kernel()
all_sites = EV1.call_sites(original)
workers = String.to_integer(System.get_env("EV1_WORKERS") || "2")

sites =
  case System.get_env("EV1_SITES") do
    nil ->
      all_sites

    file ->
      wanted = file |> File.read!() |> String.split("\n", trim: true) |> Enum.map(&String.trim/1)

      keys =
        Enum.flat_map(all_sites, fn {text, _} = site -> [text, EV1.label(original, site)] end)

      case Enum.reject(wanted, &(&1 in keys)) do
        [] ->
          :ok

        unknown ->
          IO.puts("no such call site: #{inspect(unknown)}")
          EV1.halt(2)
      end

      Enum.filter(all_sites, fn {text, _} = site ->
        text in wanted or EV1.label(original, site) in wanted
      end)
  end

IO.puts("guard call sites: #{length(all_sites)} (sweeping #{length(sites)})")

# Soundness hole, measured rather than assumed. The design's argument ("a test that never
# evaluates S cannot see S's mutant") holds for tests that observe the kernel by running it.
# It is false for a test that observes the kernel by READING it: `KernelSearch.declared_
# reasons/0` regex-scans kernel.ex and the family modules under kernel/, and
# r4_coverage/r4_guard_reachability assert on it. A
# mutant whose splice changes that scan can turn such a test red without the test evaluating
# S, so the map would not select it. Every site's mutant is scanned here with the suite's own
# `reasons_in/1`; a site that changes it is reported, and its verdict is not a verdict.
{_, _} =
  Code.with_diagnostics([log: false], fn ->
    Code.require_file("test/support/kernel_search.ex")
  end)

reasons = &PramanaFoundry.Test.KernelSearch.reasons_in/1
fixture = "with :ok <- require_x(t, {:error, :sweep_control}), do: :ok"

if reasons.(EV1.mutate(fixture, hd(EV1.call_sites(fixture)))) == reasons.(fixture) do
  IO.puts("RED CONTROL FAILED - a call site carrying an error atom did not change the scan")
  EV1.halt(4)
end

declared = reasons.(original)

source_dependent =
  Enum.filter(all_sites, fn site -> reasons.(EV1.mutate(original, site)) != declared end)

IO.puts(
  "source-read check (red control ok): #{length(source_dependent)} of #{length(all_sites)} " <>
    "site mutants change what declared_reasons/0 reads"
)

Enum.each(
  source_dependent,
  &IO.puts("  UNSOUND for this site, reported as not a verdict: #{EV1.label(original, &1)}")
)

key = EV1.answer_key(original, all_sites)

IO.puts(
  "answer key: #{key.old_sites} sites at #{key.revision}, from #{length(Map.keys(EV1.raw_verdicts()))} raw labels"
)

started = System.monotonic_time(:millisecond)

# ── Phase 1 ──
IO.puts("\n=== phase 1: mapping run (all #{length(all_sites)} sites instrumented, serial) ===")
map_root = EV1.make_root("ev1-map")
map = EV1.map_sites(map_root, original, all_sites)
File.rm_rf!(map_root)

mapped = Enum.count(map.site_tests, fn {_, tests} -> MapSet.size(tests) > 0 end)

IO.puts(
  "mapped #{mapped} of #{length(all_sites)} sites to tests; #{map.tests_total} tests in the suite; " <>
    "#{map.setup_all_sites} sites reached from a setup_all; #{map.rewritten} test files carried the window; " <>
    "#{div(map.elapsed_ms, 1000)}s"
)

Enum.each(map.setup_all_modules, fn {mod, n} ->
  IO.puts("  hits outside a test window, charged to every test of #{mod}: #{n} sites")
end)

# Red control on the map: a site the old sweep caught was necessarily evaluated by some
# test (an unevaluated site cannot turn anything red), so every caught site must be mapped.
unmapped_caught =
  all_sites
  |> Enum.with_index()
  |> Enum.filter(fn {site, i} ->
    key.expected[site] == :caught and MapSet.size(map.site_tests[i]) == 0
  end)

if unmapped_caught != [] do
  IO.puts(
    "RED CONTROL FAILED - #{length(unmapped_caught)} sites the answer key caught map to no test:"
  )

  Enum.each(unmapped_caught, fn {site, _} -> IO.puts("  #{EV1.label(original, site)}") end)
  EV1.halt(4)
end

IO.puts(
  "red control (every answer-key caught site is mapped): ok, #{Enum.count(key.expected, fn {_, v} -> v == :caught end)} caught sites"
)

# Red control on the trial: a deliberately empty mapping is `no_tests`, never a verdict.
{control_verdict, _, _} = EV1.trial(nil, original, hd(all_sites), [])

if control_verdict != :no_tests do
  IO.puts("RED CONTROL FAILED - an empty mapping produced #{inspect(control_verdict)}")
  EV1.halt(4)
end

IO.puts("red control (empty mapping reports no_tests): ok")

histogram =
  map.site_tests
  |> Map.values()
  |> Enum.map(&MapSet.size/1)
  |> Enum.frequencies()
  |> Enum.sort()

IO.puts(
  "tests per site (count: sites): " <>
    Enum.map_join(histogram, "  ", fn {n, c} -> "#{n}: #{c}" end)
)

# ── Phase 2 ──
IO.puts("\n=== phase 2: #{length(sites)} trials on #{workers} workers ===")
roots = for w <- 1..workers, do: EV1.make_root("ev1-w#{w}")
index_of = all_sites |> Enum.with_index() |> Map.new()

# Red control on the trial itself (rule 1): before any verdict is trusted, one site the
# answer key caught must come back caught and one it recorded surviving must come back
# survived, through the same trial path. A trial that selects no tests, or selects the
# wrong ones, fails one half or the other. The controls are the mapped keyed sites with
# the fewest tests, so this costs as little as the key allows; their results are reused.
controls =
  for want <- [:caught, :survived] do
    all_sites
    |> Enum.filter(fn site -> key.expected[site] == want end)
    |> Enum.map(fn site -> {site, map.site_tests[index_of[site]] |> MapSet.to_list()} end)
    |> Enum.reject(fn {_, tests} -> tests == [] end)
    |> Enum.min_by(fn {_, tests} -> length(tests) end, fn -> nil end)
    |> case do
      nil ->
        IO.puts("RED CONTROL FAILED - no mapped site the answer key calls #{want}")
        EV1.halt(4)

      {site, tests} ->
        {verdict, ran, ms} = EV1.trial(hd(roots), original, site, tests)

        IO.puts(
          "red control (known #{want} reproduced): #{EV1.label(original, site)} — " <>
            "#{inspect(verdict)} (#{ran} tests, #{div(ms, 1000)}s)"
        )

        if verdict != want do
          IO.puts("RED CONTROL FAILED - the answer key says #{want}")
          EV1.halt(4)
        end

        {site, {site, verdict, ran, ms}}
    end
  end
  |> Map.new()

sites = Enum.reject(sites, &Map.has_key?(controls, &1))

# Same slicing as the old sweep: a worker owns a slice and walks it, so no two tasks share
# a root.
results =
  sites
  |> Enum.chunk_every(max(1, ceil(length(sites) / workers)))
  |> Enum.zip(roots)
  |> Task.async_stream(
    fn {slice, root} ->
      Enum.map(slice, fn site ->
        tests = map.site_tests[index_of[site]] |> MapSet.to_list()
        {verdict, ran, ms} = EV1.trial(root, original, site, tests)

        IO.puts(
          "  #{Path.basename(root)} #{EV1.label(original, site)} — #{inspect(verdict)} " <>
            "(#{ran}/#{map.tests_total} tests, #{div(ms, 1000)}s)"
        )

        {site, verdict, ran, ms}
      end)
    end,
    max_concurrency: workers,
    timeout: :infinity,
    ordered: false
  )
  |> Enum.flat_map(fn {:ok, r} -> r end)
  |> Kernel.++(Map.values(controls))
  # The map cannot judge a site whose mutant changes what a test READS; its trial result is
  # kept for display but is not a verdict, and the arbiter below judges it on the full set.
  |> Enum.map(fn {site, verdict, ran, ms} = result ->
    if site in source_dependent,
      do: {site, {:source_dependent, verdict}, ran, ms},
      else: result
  end)

Enum.each(roots, &File.rm_rf!/1)
wall_s = div(System.monotonic_time(:millisecond) - started, 1000)

if EV1.read_kernel() != original do
  IO.puts("\nFAIL: the kernel sources changed while the sweep ran; trust nothing above.")
  EV1.halt(3)
end

# ── Report ──
counts =
  results
  |> Enum.map(&elem(&1, 1))
  |> Enum.map(fn
    v when is_atom(v) -> v
    {k, _, _} -> k
    {k, _} -> k
  end)
  |> Enum.frequencies()

IO.puts(
  "\n=== verdicts === " <> Enum.map_join(Enum.sort(counts), "  ", fn {k, v} -> "#{k}: #{v}" end)
)

IO.puts("\n=== survivors (trial ran, nothing red) ===")
for {site, :survived, _, _} <- results, do: IO.puts("  #{EV1.label(original, site)}")

IO.puts("\n=== no_tests (no test evaluates the site; no trial) ===")
for {site, :no_tests, _, _} <- results, do: IO.puts("  #{EV1.label(original, site)}")

others = for {site, v, _, _} <- results, not is_atom(v), do: {site, v}

if others != [] do
  IO.puts("\n=== not a verdict ===")
  for {site, v} <- others, do: IO.puts("  #{EV1.label(original, site)} — #{inspect(v)}")
end

IO.puts("\n=== answer-key diff against #{key.revision} (2026-09-21 runs 1-3) ===")

{unkeyed, keyed} =
  Enum.split_with(results, fn {site, _, _, _} -> match?({:no_key, _, _}, key.expected[site]) end)

disagreements =
  for {site, verdict, _, _} <- keyed,
      expected = key.expected[site],
      # no_tests is a survivor with no trial; the old sweep would have said survived.
      normalised = if(verdict == :no_tests, do: :survived, else: verdict),
      expected != normalised do
    {site, expected, verdict}
  end

for {site, expected, got} <- disagreements do
  IO.puts("  #{EV1.label(original, site)}: old #{inspect(expected)}, new #{inspect(got)}")
end

IO.puts("  #{length(disagreements)} disagreements over #{length(keyed)} keyed trials")

for {site, verdict, _, _} <- unkeyed do
  IO.puts(
    "  no key (site count changed since #{key.revision}): #{EV1.label(original, site)} — #{inspect(verdict)}"
  )
end

for {text, n} <- key.gone, do: IO.puts("  gone since the key: #{text} x#{n}")

# Arbiter for every disagreement and every non-verdict: the old sweep's own judgement, the
# whole workflow set against the same mutant, today. If it agrees with the scoped trial the
# key is stale (tests or kernel moved since 2026-09-21); if it disagrees, the map missed a
# test and the design is unsound at that site. Nothing is reconciled by hand.
arbitrate =
  Enum.map(disagreements, &elem(&1, 0)) ++
    for({site, v, _, _} <- results, not is_atom(v), do: site)

if arbitrate != [] do
  IO.puts("\n=== arbiter: full workflow set per mutant (the old sweep's judgement) ===")
  root = EV1.make_root("ev1-arbiter")

  for site <- Enum.uniq(arbitrate) do
    all = for suite <- EV1.suites(), do: {suite, nil}
    {verdict, _, ms} = EV1.trial(root, original, site, all)
    scoped = Enum.find_value(results, fn {s, v, _, _} -> if s == site, do: v end)

    IO.puts(
      "  #{EV1.label(original, site)}: scoped #{inspect(scoped)}, full set #{inspect(verdict)} " <>
        "(#{div(ms, 1000)}s)"
    )
  end

  File.rm_rf!(root)
end

trial_tests = results |> Enum.map(&elem(&1, 2)) |> Enum.sum()
trial_ms = results |> Enum.map(&elem(&1, 3)) |> Enum.sum()

IO.puts("""

=== denominators ===
  sites: #{length(all_sites)} total, #{mapped} mapped to at least one test, #{length(results)} tried (including the 2 red-control trials)
  tests selected across all trials: #{trial_tests} of #{length(results) * map.tests_total} the full workflow set per trial would be
  trial cpu-seconds (sum over workers): #{div(trial_ms, 1000)}s; mapping run: #{div(map.elapsed_ms, 1000)}s
  wall time, mapping + trials: #{wall_s}s on #{workers} workers
  2026-09-21 full sweep for comparison: 5047s over 116 sites on 4 workers
repository target unchanged: true
""")
