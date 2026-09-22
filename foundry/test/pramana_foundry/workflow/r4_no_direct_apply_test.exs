defmodule PramanaFoundry.Workflow.R4NoDirectApplyTest do
  @moduledoc """
  The harness only judges what routes through it, and nothing obliges a new test to.

  EV-3's claim is that the relational oracle judges *every* accepted transition the suite
  drives. That claim decays silently: subcommits 2–5 each add tests to this kernel, and a
  new `WorkflowKernel.apply/2` call site would leave the claim standing while making it
  false. This is the check that fails instead.

  It is the same shape as the citation check in `r4_coverage_test.exs` — read the artifact,
  do not transcribe it — applied to call sites rather than contract quotations.
  """
  use ExUnit.Case, async: true

  # The wrapper itself, which must call the kernel, and the one exemption.
  #
  # `kernel_search.ex` is exempt because routing it through the harness adds no coverage:
  # the oracle is a function of the successor state alone, and `r4_exhaustive_test.exs`
  # already asserts it over every state the search reaches, so per-transition assertion is
  # the same set of judgements at the highest cost in the suite. The exemption is by exact
  # path, and the test below fails if that file is renamed rather than widening silently.
  @harness "test/support/kernel_harness.ex"
  @exempt ["test/support/kernel_search.ex"]

  # Assembled rather than written, so this file contains neither a direct call nor a literal
  # that looks like one. Spelling it out made the first run flag this file as its own
  # offender — a source scanner that reads the file it is written in has to keep the needle
  # out of the haystack, and self-exemption would have been a hole instead of a fix.
  @needle "WorkflowKernel" <> "." <> "apply("

  test "every test call site reaches the kernel through the harness" do
    assert direct_callers(Path.wildcard("test/**/*.{ex,exs}")) == []
  end

  test "the exemption names a file that exists" do
    for path <- [@harness | @exempt], do: assert(File.exists?(path), "#{path} is gone")
  end

  # Red control. A scan that reports nothing is indistinguishable from a scan that reads
  # nothing, and five mechanisms in this subcommit shipped in exactly that condition — so
  # the scan has to be shown finding the thing it exists to find, through the same File.read
  # and regex path the real run uses rather than against a literal in this file.
  test "the scan sees a direct call" do
    path =
      Path.join(
        System.tmp_dir!(),
        "r4_direct_apply_control_#{:erlang.unique_integer([:positive])}.exs"
      )

    File.write!(path, "    case " <> @needle <> "state, event) do\n")
    on_exit(fn -> File.rm(path) end)

    assert direct_callers([path]) == [path]
  end

  test "the scan does not fire on the harness or an exempt file" do
    assert direct_callers([@harness | @exempt]) == []
  end

  # The harness's assertions can also be skipped from inside it, by `apply_unchecked/2`.
  # That is a quarantine for a real defect this change does not fix (see the function's own
  # doc), and a quarantine nothing counts is a quarantine that spreads because it is
  # convenient. One call site, named here so widening it is a deliberate edit to this test.
  test "the unchecked escape hatch has exactly one call site" do
    needle = "apply" <> "_unchecked("

    callers =
      "test/**/*.{ex,exs}"
      |> Path.wildcard()
      |> Enum.reject(&(&1 == @harness))
      |> Enum.flat_map(fn path ->
        count = length(String.split(File.read!(path), needle)) - 1
        List.duplicate(path, count)
      end)

    assert callers == ["test/pramana_foundry/workflow/kernel_test.exs"]
  end

  defp direct_callers(paths) do
    paths
    |> Enum.reject(&(&1 in [@harness | @exempt]))
    |> Enum.filter(&String.contains?(File.read!(&1), @needle))
  end
end
