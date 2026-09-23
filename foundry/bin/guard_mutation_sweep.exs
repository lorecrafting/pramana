# Guard mutation sweep.
#
# Neutralises each guard call site in turn and reports the ones whose removal no test
# notices. A surviving mutation is a guard nothing exercises — which this repair has
# shipped repeatedly, each time found by a reviewer reading code or by a hand sweep that
# only covered the guards someone thought to check.
#
#   cd foundry && TMPDIR=/private/tmp elixir bin/guard_mutation_sweep.exs [path/to/module.ex ...]
#   SWEEP_SINCE=<rev>   sweep only guards whose lines changed since <rev>
#   SWEEP_SITES=<file>  sweep only the call sites listed in <file>, one per line
#   SWEEP_WORKERS=<n>   parallel workers (default 4)
#
# Guards are neutralised at their CALL SITE, never at their definition. Renaming a
# definition breaks the build and measures nothing — a lesson from the first hand sweep.
#
# Parallelism is safe here and was verified rather than assumed: eight concurrent runs of
# the workflow suites against unmutated source returned eight identical greens. This
# repository's concurrency flakiness is in the physical fault tests, which simulate ENOSPC
# and sync failures; the workflow suites are pure computation. Each worker still gets its
# own source tree and build path, because they mutate the same file.

# The reducer is kernel.ex plus one module per event family under kernel/ (split by family on
# 2026-09-23), so the default is every one of those files. Event and State hold no guard calls.
targets =
  case System.argv() do
    [] ->
      dir = "lib/pramana_foundry/workflow"

      [Path.join(dir, "kernel.ex") | Path.wildcard(Path.join(dir, "kernel/**/*.ex"))] --
        [Path.join(dir, "kernel/event.ex"), Path.join(dir, "kernel/state.ex")]

    given ->
      given
  end

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

File.write!(sentinel, "#{System.pid()} #{DateTime.utc_now()} #{Enum.join(targets, " ")}\n")
System.at_exit(fn _ -> File.rm(sentinel) end)

originals = Map.new(targets, &{&1, File.read!(&1)})

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
# `<- require_foo(` was the shape for as long as every guard sat in a `with` chain. Six do
# not: `require_settlement_source/2` dispatches on disposition and each branch calls a
# guard directly or in tail position, e.g. `"cancelled" -> require_cancel_requested(ticket)`.
# Those six were invisible, so neutralising the outer `require_settlement_source` measured
# all six collectively and one disposition branch could vouch for another. 108 was reported;
# there are 114 across 70 distinct texts. Fifth time this tool's number has been weaker than
# its claim, and the second time in one day.
#
# Any `require_*(` that is not a definition now counts, wherever it appears.
call_sites = fn source ->
  Regex.scan(~r/(?<![a-z_])(require_[a-z_]+\()/, source, return: :index)
  |> Enum.reject(fn [_, {start, _len}] ->
    # A definition, not a call: `defp require_foo(`.
    line_start =
      case :binary.matches(binary_part(source, 0, start), "\n") do
        [] -> 0
        matches -> matches |> List.last() |> elem(0) |> Kernel.+(1)
      end

    # `def` too: a guard the family modules share is public in the family that owns it.
    String.trim(binary_part(source, line_start, start - line_start)) in ~w(def defp)
  end)
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
line_of = fn file, offset ->
  originals[file] |> binary_part(0, offset) |> :binary.matches("\n") |> length() |> Kernel.+(1)
end

label = fn {text, offset, file} -> "#{text} #{Path.basename(file)}:#{line_of.(file, offset)}" end

# Red control, run before anything else. Every shape a guard call takes in this kernel,
# including the ones that were invisible for five runs. A scanner that quietly matches
# fewer shapes than it should produces a clean report about a smaller population, which is
# this tool's single recurring failure. It now has to demonstrate it can see them first.
red_control = """
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

expected_control =
  ~w(require_one require_two require_multiline require_tail require_one require_nested
     require_inline)
  |> Enum.sort()

found_control =
  red_control
  |> call_sites.()
  |> Enum.map(fn {text, _} -> text |> String.split("(") |> hd() end)
  |> Enum.sort()

if found_control != expected_control do
  IO.puts("""
  RED CONTROL FAILED - the site scanner cannot see every guard shape, so any number it
  reports is about a smaller population than the kernel has.

    expected: #{inspect(expected_control)}
    found:    #{inspect(found_control)}
  """)

  System.halt(4)
end

all_sites =
  for file <- targets, {text, offset} <- call_sites.(originals[file]), do: {text, offset, file}
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
        IO.puts("no such call site in #{Enum.join(targets, ", ")}:")
        Enum.each(unknown, &IO.puts("  #{&1}"))
        System.halt(2)
    end

    # Every occurrence of a listed text, not one of them.
    listed = Enum.filter(all_sites, fn {text, _, _} -> text in wanted end)
    IO.puts("listed sites: #{length(listed)} occurrences of #{length(wanted)} guards, " <>
              "of #{length(all_sites)} total")
    listed
  else
    if since do
      diffs =
        Map.new(targets, fn file ->
          {diff, 0} = System.cmd("git", ["diff", "-U0", since, "--", file], stderr_to_stdout: true)
          {file, diff}
        end)

      touched = Enum.filter(all_sites, fn {text, _, file} -> String.contains?(diffs[file], text) end)
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

    for {file, original} <- originals do
      File.rm!(Path.join(root, file))
      File.write!(Path.join(root, file), original)
    end

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
judge = fn root, {text, offset, file} ->
  path = Path.join(root, file)
  original = originals[file]
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

Enum.each(roots, &File.rm_rf!/1)

# This used to be `File.write!(target, original)`, restoring a file the sweep never
# modifies: mutations happen only in the worker trees. A "restore" of an unmodified file is
# a silent clobber of anything legitimately written to it during the hour this runs, and
# parallel sessions in this repository do write. The sweep now VERIFIES instead, and fails
# loudly if the target moved under it.
moved = Enum.reject(targets, &(File.read!(&1) == originals[&1]))

if moved != [] do
  IO.puts("""

  FAIL: #{Enum.join(moved, ", ")} changed while the sweep ran.

  The sweep does not write to the repository, so this is someone else's edit - or a
  crashed worker. Nothing has been overwritten. Compare against the last known-good
  revision before trusting any result above.
  """)

  System.halt(3)
end

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
IO.puts("repository target unchanged: true")
