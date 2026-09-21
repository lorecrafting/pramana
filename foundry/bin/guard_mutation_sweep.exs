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

fast = ~w(
  test/pramana_foundry/workflow/kernel_test.exs
  test/pramana_foundry/workflow/r4_coverage_test.exs
  test/pramana_foundry/workflow/r4_exhaustive_test.exs
  test/pramana_foundry/workflow/r4_guard_reachability_test.exs
)
slow = fast ++ ["test/pramana_foundry/workflow/kernel_properties_test.exs"]

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
}

run = fn files ->
  {out, _} =
    System.cmd("mix", ["test" | files] ++ ["--seed", "0"],
      env: [{"TMPDIR", "/private/tmp"}, {"MIX_BUILD_PATH", "/private/tmp/mutation/_build"}],
      stderr_to_stdout: true
    )

  cond do
    String.contains?(out, "test(s)") and String.contains?(out, ", 0 failure") -> :all_passed
    Regex.match?(~r/\n\s*\d+ (doctests?, )?\d* ?tests?, 0 failures/, out) -> :all_passed
    String.contains?(out, "failure") -> :caught
    String.contains?(out, "error") -> :build_error
    true -> :all_passed
  end
end

sites = call_sites.(original)
IO.puts("guard call sites found: #{length(sites)}\n")

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

        other ->
          IO.puts("#{i}/#{length(sites)} #{String.slice(site, 0, 60)} -- #{other} SURVIVED")
          [site | acc]
      end
    end
  end)

File.write!(target, original)

IO.puts("\nre-checking #{length(survivors)} survivors against every suite")

final =
  Enum.filter(survivors, fn site ->
    File.write!(target, String.replace(original, "<- " <> site, "<- :ok", global: true))
    verdict = run.(slow)
    File.write!(target, original)
    verdict != :caught
  end)

File.write!(target, original)

IO.puts("\n=== #{length(final)} guards no test exercises ===")
Enum.each(final, &IO.puts("  #{&1}"))
IO.puts("\nsource restored byte-identical: #{File.read!(target) == original}")
