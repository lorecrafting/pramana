# Guard mutation sweep.
#
# Neutralises each guard call site in turn and reports the ones whose removal no test
# notices. A surviving mutation is a guard nothing exercises - which this repair has now
# shipped four times, each found by a reviewer reading code or by a hand sweep that only
# covered the guards someone thought to check.
#
#   elixir bin/guard_mutation_sweep.exs [path/to/module.ex]
#
# Two phases, because the properties suite dominates the runtime: every mutation is run
# against the fast suites, then the survivors are re-run against all of them, so a guard
# covered only by a property is not reported falsely.
#
# Guards are neutralised at their CALL SITE, never at their definition. Renaming a
# definition breaks the build and measures nothing - a lesson from the first hand sweep.

target = System.argv() |> List.first() || "lib/pramana_foundry/workflow/kernel.ex"

# This tool edits a source file in place, so for the minutes it runs the working tree does
# not mean what it usually means. That is not hypothetical: a `git add -A` during a sweep
# committed a neutralised guard into the repository, and the mutation survived into a
# tagged candidate because every local check still passed - the suite was measuring the
# mutation, not the kernel.
#
# The sentinel makes the window visible. `bin/preflight.sh` refuses to pass while it
# exists, so a freeze cannot be taken from a mutated tree, and a second sweep cannot start
# on top of a first.
sentinel = "/private/tmp/guard-mutation-sweep.running"

if File.exists?(sentinel) do
  IO.puts("""
  A sweep is already running, or one died without cleaning up.

    #{sentinel}

  If no sweep is running, the tree may hold a mutation. Compare the target against the
  last known-good revision before deleting this file - do not assume it is clean.
  """)

  System.halt(2)
end

File.write!(sentinel, "#{System.pid()} #{DateTime.utc_now()} #{target}\n")
System.at_exit(fn _ -> File.rm(sentinel) end)

# Phase one is the suites that are broad and cheap. The exhaustive suite belongs here
# despite running a full state search: it takes three seconds and is the most sensitive
# thing available, so it converts survivors into catches at the best rate of anything in
# the set. Leaving it out of phase one left 46 of 67 mutations for the slow phase.
#
# The guard-reachability suite does not belong here. It re-proposes at every reached state,
# which costs a minute - cheap once and ruinous sixty-seven times. The exhaustive and
# guard-reachability suites each run a full state search, which is cheap once and ruinous
# sixty-six times - putting them here turned a twenty-minute sweep into a three-hour one.
# Phase two runs everything, but only for the mutations phase one did not catch.
fast = ~w(
  test/pramana_foundry/workflow/kernel_test.exs
  test/pramana_foundry/workflow/r4_coverage_test.exs
  test/pramana_foundry/workflow/r4_exhaustive_test.exs
)
slow = fast ++ ~w(
  test/pramana_foundry/workflow/r4_guard_reachability_test.exs
  test/pramana_foundry/workflow/kernel_properties_test.exs
)

original = File.read!(target)

# Every `<- require_foo(...)` call, with balanced parentheses so nested calls survive.
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

    if depth == 0, do: binary_part(source, start, stop - start + 1), else: nil
  end)
  |> Enum.reject(&is_nil/1)
  |> Enum.uniq()
end

run = fn files ->
  {out, _} =
    System.cmd("mix", ["test" | files] ++ ["--seed", "0"],
      env: [{"TMPDIR", "/private/tmp"}, {"MIX_BUILD_PATH", "/private/tmp/mutation/_build"}],
      stderr_to_stdout: true
    )

  # This repository uses a custom formatter: "Result: N passed" when green, and
  # "Result: N/M passed" when something failed. Matching ExUnit's default
  # "N tests, 0 failures" therefore matched nothing, and the catch-all reported every
  # mutation as surviving - a sweep that would have claimed 66 untested guards. A tool
  # built to find vacuous evidence produced vacuous evidence on its first run.
  cond do
    Regex.match?(~r/Result: \d+\/\d+ passed/, out) -> :caught
    Regex.match?(~r/Result: \d+ passed/, out) -> :all_passed
    true -> :build_error
  end
end

all_sites = call_sites.(original)

# Incremental mode: sweep only the guards whose lines changed since a given revision. A
# subcommit usually touches ten guards, not sixty-seven, and a full sweep of the untouched
# ones re-proves what the last freeze already proved. Full sweep stays the default, because
# "unchanged" is a claim about the diff and the diff can be wrong.
since = System.get_env("SWEEP_SINCE")

sites =
  if since do
    {diff, 0} = System.cmd("git", ["diff", "-U0", since, "--", target], stderr_to_stdout: true)
    touched = Enum.filter(all_sites, &String.contains?(diff, &1))

    IO.puts("incremental sweep against #{since}: #{length(touched)} of #{length(all_sites)} guards\n")

    touched
  else
    IO.puts("guard call sites found: #{length(all_sites)}\n")
    all_sites
  end

survivors =
  sites
  |> Enum.with_index(1)
  |> Enum.reduce([], fn {site, i}, acc ->
    mutated = String.replace(original, "<- " <> site, "<- :ok", global: true)

    if mutated == original do
      IO.puts("#{i}/#{length(sites)} #{site} -- could not apply, skipped")
      acc
    else
      File.write!(target, mutated)
      verdict = run.(fast)
      File.write!(target, original)

      case verdict do
        :caught ->
          IO.puts("#{i}/#{length(sites)} #{String.slice(site, 0, 60)} -- caught")
          acc

        :build_error ->
          IO.puts("#{i}/#{length(sites)} #{site} -- DID NOT COMPILE, nothing measured")
          acc

        :all_passed ->
          IO.puts("#{i}/#{length(sites)} #{site} -- SURVIVED")
          [site | acc]
      end
    end
  end)

File.write!(target, original)

IO.puts("\nre-checking #{length(survivors)} survivors against every suite")

final =
  survivors
  |> Enum.with_index(1)
  |> Enum.reduce([], fn {site, i}, acc ->
    IO.write("  phase 2 #{i}/#{length(survivors)} #{String.slice(site, 0, 58)} ... ")
    File.write!(target, String.replace(original, "<- " <> site, "<- :ok", global: true))
    verdict = run.(slow)
    File.write!(target, original)

    case verdict do
      :caught ->
        IO.puts("caught")
        acc

      other ->
        IO.puts("#{other} SURVIVED")
        [site | acc]
    end
  end)
  |> Enum.reverse()

File.write!(target, original)

IO.puts("\n=== #{length(final)} guards no test exercises ===")
Enum.each(final, &IO.puts("  #{&1}"))
IO.puts("\nsource restored byte-identical: #{File.read!(target) == original}")
