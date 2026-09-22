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

  # The wrapper itself, which must call the kernel. Nothing else is exempt.
  #
  # `kernel_search.ex` was exempt on the argument that routing it added no coverage. That
  # argument was false — the search's final frontier expansion drives roughly 790,000 accepted
  # transitions it then discards — and the cost it traded against had never been measured.
  # Measured: cost between noise and ~20% across four single samples, for 4.2x the DISTINCT
  # transitions judged. The exemption is gone rather than corrected, and this list is empty
  # rather than merely shorter.
  @harness "test/support/kernel_harness.ex"
  @exempt []

  # Assembled rather than written, so this file contains neither a direct call nor a literal
  # that looks like one. Spelling it out made the first run flag this file as its own
  # offender — a source scanner that reads the file it is written in has to keep the needle
  # out of the haystack, and self-exemption would have been a hole instead of a fix.
  #
  # The needle was the `WorkflowKernel` spelling alone — ONE of them — and independent review
  # found a call it could not see, the fully-qualified `PramanaFoundry.Workflow.Kernel` one
  # (written in slash form here on purpose, because this comment is inside the haystack), live in
  # `r4_exhaustive_test.exs` in the very commit that introduced this scanner. That is the
  # declared-reason inventory's defect reproduced in a new mechanism: it scanned for one of
  # two spellings for three reviews. Matching on the module's last segment catches every
  # qualified spelling, and both are now red controls below.
  @needle "Kernel" <> "." <> "apply("

  test "every test call site reaches the kernel through the harness" do
    assert direct_callers(Path.wildcard("test/**/*.{ex,exs}")) == []
  end

  test "the harness and every exemption name a file that exists" do
    for path <- [@harness | @exempt], do: assert(File.exists?(path), "#{path} is gone")
  end

  # An empty exemption list is the claim; this is what keeps it from quietly refilling.
  test "nothing is exempt but the harness itself" do
    assert @exempt == []
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

    File.write!(path, "    case Workflow" <> @needle <> "state, event) do\n")
    on_exit(fn -> File.rm(path) end)

    assert direct_callers([path]) == [path]
  end

  # The spelling the first version of this scanner could not see. Separate from the control
  # above rather than folded into it: one fixture proving "the scan matches something" is
  # what let a live call site sit unseen.
  test "the scan sees a fully-qualified direct call" do
    path =
      Path.join(
        System.tmp_dir!(),
        "r4_qualified_apply_control_#{:erlang.unique_integer([:positive])}.exs"
      )

    File.write!(path, "    assert {:ok, _} = PramanaFoundry.Workflow." <> @needle <> "bad, e)\n")
    on_exit(fn -> File.rm(path) end)

    assert direct_callers([path]) == [path]
  end

  test "the scan does not fire on the harness itself" do
    assert direct_callers([@harness | @exempt]) == []
  end

  # The harness's assertions can also be skipped from inside it, by `apply_unchecked/2`, and
  # an escape hatch nothing counts is one that spreads because it is convenient. Two call
  # sites, each named here so widening the set is a deliberate edit to this test: the B1
  # totality probe, which drives malformed payloads past the closure defect that is
  # quarantined rather than fixed, and the harness's own wiring control, which has to ask the
  # kernel for its verdict before showing the harness rejecting the same event.
  test "the unchecked escape hatch has exactly the call sites it is allowed" do
    needle = "apply" <> "_unchecked("

    callers =
      "test/**/*.{ex,exs}"
      |> Path.wildcard()
      |> Enum.reject(&(&1 == @harness))
      |> Enum.flat_map(fn path ->
        count = length(String.split(File.read!(path), needle)) - 1
        List.duplicate(path, count)
      end)

    assert callers == [
             "test/pramana_foundry/workflow/kernel_test.exs",
             "test/pramana_foundry/workflow/r4_exhaustive_test.exs",
             "test/pramana_foundry/workflow/r4_exhaustive_test.exs"
           ]
  end

  defp direct_callers(paths) do
    paths
    |> Enum.reject(&(&1 in [@harness | @exempt]))
    |> Enum.filter(&String.contains?(File.read!(&1), @needle))
  end
end
