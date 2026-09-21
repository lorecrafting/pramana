# Guard mutation sweep.
#
# Neutralises each guard call site in turn and reports the ones whose removal no test
# notices. A surviving mutation is a guard nothing exercises — which this repair has
# shipped repeatedly, each time found by a reviewer reading code or by a hand sweep that
# only covered the guards someone thought to check.
#
#   cd foundry && bin/guard_mutation_sweep.exs [path/to/module.ex]
#   SWEEP_SINCE=<rev>   sweep only guards whose lines changed since <rev>
#   SWEEP_SITES=<file>  sweep only the call sites listed in <file>, one per line
#   SWEEP_WORKERS=<n>   parallel workers (default 6)
#
# Guards are neutralised at their CALL SITE, never at their definition. Renaming a
# definition breaks the build and measures nothing — a lesson from the first hand sweep.
#
# Parallelism is safe here and was verified rather than assumed: eight concurrent runs of
# the workflow suites against unmutated source returned eight identical greens. This
# repository's concurrency flakiness is in the physical fault tests, which simulate ENOSPC
# and sync failures; the workflow suites are pure computation. Each worker still gets its
# own source tree and build path, because they mutate the same file.

target = System.argv() |> List.first() || "lib/pramana_foundry/workflow/kernel.ex"
# Four rather than six: six oversubscribed the cores badly enough that per-task wall clock
# was roughly three times its solo cost, and the measured speedup against serial was about
# 2.5x rather than the 6x the worker count suggests.
workers = String.to_integer(System.get_env("SWEEP_WORKERS") || "4")

# Ordered cheapest first so a mutation can be judged as soon as anything catches it. Phase
# one is broad and seconds long; phase two adds the two suites that each run a full state
# search and cost a minute apiece, and is only reached by mutations phase one missed.
fast = ~w(
  test/pramana_foundry/workflow/kernel_test.exs
  test/pramana_foundry/workflow/r4_coverage_test.exs
  test/pramana_foundry/workflow/r4_exhaustive_test.exs
)
slow = ~w(
  test/pramana_foundry/workflow/kernel_properties_test.exs
  test/pramana_foundry/workflow/r4_guard_reachability_test.exs
)

sentinel = "/private/tmp/guard-mutation-sweep.running"

if File.exists?(sentinel) do
  IO.puts("""
  A sweep is already running, or one died without cleaning up.

    #{sentinel}

  If no sweep is running, the tree may hold a mutation. Compare the target against the
  last known-good revision before deleting this file — do not assume it is clean.
  """)

  System.halt(2)
end

File.write!(sentinel, "#{System.pid()} #{DateTime.utc_now()} #{target}\n")
System.at_exit(fn _ -> File.rm(sentinel) end)

original = File.read!(target)

# Every `<- require_foo(...)` call, with balanced parentheses so nested calls survive.
#
# A line-anchored regex was tried here and rejected by measurement: it found 47 call sites
# where this finds 67, because a `with` clause that wraps across lines has no closing paren
# on the line the call starts. Twenty guards would have gone unswept while the sweep
# reported success, which is the failure this tool exists to catch.
#
# Each occurrence is kept with its byte offset, and mutation splices at that offset. It
# used to `Enum.uniq` the text and mutate every match of it at once, which made the tool
# coarser than the name "call site" promises: `require_phase(ticket, ~w(developing))`
# appears in four handlers and `require_active_attempt(ticket, event["payload"]["attempt_
# id"])` in six, so one red test anywhere cleared all of them and up to nine untested
# siblings could hide behind one tested handler. Found while writing the review briefing
# that was about to ask a reviewer to check exactly this.
call_sites = fn source ->
  Regex.scan(~r/<- (require_[a-z_]+\()/, source, return: :index)
  |> Enum.map(fn [_, {start, len}] ->
    {depth, stop} =
      Enum.reduce_while((start + len)..(byte_size(source) - 1)//1, {1, start + len}, fn i, {d, _} ->
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

# The line a byte offset falls on, so a survivor can be opened rather than searched for.
line_of = fn offset ->
  original |> binary_part(0, offset) |> :binary.matches("\n") |> length() |> Kernel.+(1)
end

label = fn {text, offset} -> "#{text} :#{line_of.(offset)}" end

all_sites = call_sites.(original)
all_texts = all_sites |> Enum.map(&elem(&1, 0)) |> Enum.uniq()

# Incremental mode: only the guards whose lines changed since a revision. A subcommit
# usually touches ten guards, not sixty-five. Full sweep stays the default, because
# "unchanged" is a claim about a diff and a diff can be wrong.
since = System.get_env("SWEEP_SINCE")

# Re-sweeping the previous run's survivors is the common case after adding tests, and
# `SWEEP_SINCE` cannot express it: the fix for an untested guard is a new *test*, so the
# target's diff is empty and the incremental filter selects nothing. Sites are matched
# against the parsed list rather than trusted, so a stale or mistyped entry is reported
# instead of silently sweeping fewer guards than asked.
only = System.get_env("SWEEP_SITES")

sites =
  if only do
    wanted = only |> File.read!() |> String.split("\n", trim: true) |> Enum.map(&String.trim/1)

    case Enum.reject(wanted, &(&1 in all_texts)) do
      [] -> :ok
      unknown ->
        IO.puts("no such call site in #{target}:")
        Enum.each(unknown, &IO.puts("  #{&1}"))
        System.halt(2)
    end

    # Every occurrence of a listed text, not one of them.
    listed = Enum.filter(all_sites, fn {text, _} -> text in wanted end)
    IO.puts("listed sites: #{length(listed)} occurrences of #{length(wanted)} guards, " <>
              "of #{length(all_sites)} total")
    listed
  else
    if since do
      {diff, 0} = System.cmd("git", ["diff", "-U0", since, "--", target], stderr_to_stdout: true)
      touched = Enum.filter(all_sites, fn {text, _} -> String.contains?(diff, text) end)
      IO.puts("incremental against #{since}: #{length(touched)} of #{length(all_sites)} guards")
      touched
    else
      IO.puts("guard call sites: #{length(all_sites)}")
      all_sites
    end
  end

# Each worker needs its own tree, because they mutate the same file. Hard links make the
# copy near-free; the mutated file's link is broken so a worker's edit cannot reach the
# repository. `docs` is required: the row harness reads the contract at test time rather
# than holding a copy of it, which is the property that makes it drift-proof.
IO.puts("preparing #{workers} workers")

roots =
  for w <- 1..workers do
    root = "/private/tmp/sweep-w#{w}"
    File.rm_rf!(root)
    File.mkdir_p!(root)

    {_, 0} =
      System.cmd("cp", ["-al", "lib", "test", "config", "docs", "mix.exs", "mix.lock", "deps", root])

    File.rm!(Path.join(root, target))
    File.write!(Path.join(root, target), original)
    root
  end

run = fn root, files ->
  {out, _} =
    System.cmd("mix", ["test" | files] ++ ["--seed", "0"],
      cd: root,
      env: [{"TMPDIR", "/private/tmp"}, {"MIX_BUILD_PATH", Path.join(root, "_build")}],
      stderr_to_stdout: true
    )

  # This repository's formatter prints "Result: N passed" when green and "Result: N/M
  # passed" when not. Matching ExUnit's default "N tests, 0 failures" instead is how an
  # earlier version of this tool reported every guard as untested: nothing matched, and the
  # catch-all called it a pass.
  cond do
    Regex.match?(~r/Result: \d+\/\d+ passed/, out) -> :caught
    Regex.match?(~r/Result: \d+ passed/, out) -> :survived
    true -> :build_error
  end
end

# Cheapest suites first, stopping as soon as anything catches the mutation. A mutation only
# needs one test to notice it, so running the slow suites after a catch buys nothing.
judge = fn root, {text, offset} ->
  path = Path.join(root, target)
  len = byte_size(text)

  mutated =
    binary_part(original, 0, offset) <>
      ":ok" <>
      binary_part(original, offset + len, byte_size(original) - offset - len)

  File.write!(path, mutated)

  verdict =
    case run.(root, fast) do
      :caught -> :caught
      :build_error -> :build_error
      :survived -> run.(root, slow)
    end

  File.write!(path, original)
  verdict
end

started = System.monotonic_time(:second)

# Each worker owns a slice and walks it sequentially. Assigning roots by `rem(index,
# workers)` inside an async_stream looks equivalent and is not: the stream starts a new
# task whenever *any* task finishes, not in index order, so task 6 could take root 0 while
# task 0 was still using it. Two tasks then mutated and restored the same file, and
# whichever was mid-test measured unmutated source and reported the guard as surviving.
#
# It produced 24 survivors against the serial run's 13 on a kernel that had gained eleven
# tests in between - the contradiction is what exposed it. A tool for finding false
# evidence generating false evidence, for the third time.
results =
  sites
  |> Enum.chunk_every(ceil(length(sites) / workers))
  |> Enum.zip(roots)
  |> Task.async_stream(
    fn {slice, root} ->
      Enum.map(slice, fn site ->
        verdict = judge.(root, site)
        IO.puts("  #{Path.basename(root)} #{String.slice(label.(site), 0, 64)} — #{verdict}")
        {site, verdict}
      end)
    end,
    max_concurrency: workers,
    timeout: :infinity,
    ordered: false
  )
  |> Enum.flat_map(fn {:ok, slice_results} -> slice_results end)

File.write!(target, original)
Enum.each(roots, &File.rm_rf!/1)

survivors = for {site, :survived} <- results, do: site
errors = for {site, :build_error} <- results, do: site

IO.puts("\n=== #{length(survivors)} call sites no test exercises ===")
Enum.each(survivors, &IO.puts("  #{label.(&1)}"))

# Deduplicated, so the list can be fed straight back in via SWEEP_SITES.
IO.puts("\n=== the #{survivors |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> length()} distinct guards behind them ===")
survivors |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> Enum.each(&IO.puts("  #{&1}"))

if errors != [] do
  IO.puts("\n=== #{length(errors)} did not compile, so nothing was measured ===")
  Enum.each(errors, &IO.puts("  #{label.(&1)}"))
end

IO.puts("\nelapsed: #{System.monotonic_time(:second) - started}s")
IO.puts("source restored byte-identical: #{File.read!(target) == original}")
