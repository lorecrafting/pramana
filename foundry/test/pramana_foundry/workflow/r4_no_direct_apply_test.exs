Code.require_file("../../support/ast_modules.ex", __DIR__)

defmodule PramanaFoundry.Workflow.R4NoDirectApplyTest do
  @moduledoc """
  The harness only judges what routes through it, and nothing obliges a new test to.

  EV-3's claim is that the relational oracle judges *every* accepted transition the suite
  drives. That claim decays silently: subcommits 2–5 each add tests to this kernel, and a
  new `WorkflowKernel.apply/2` call site would leave the claim standing while making it
  false. This is the check that fails instead.

  It is the same shape as the citation check in `r4_coverage_test.exs` — read the artifact,
  do not transcribe it — applied to call sites rather than contract quotations.

  It reads the AST, not the text. The first two versions matched call-site text: first one
  spelling (`WorkflowKernel.apply(`), which missed a fully-qualified call live in the same
  commit; then the module's last segment, which still let five spellings through — a capture,
  an alias rename, reflection, and the parenless and space-before-paren call forms. Text has
  as many spellings as the language allows; the AST has fewer shapes, and each one the scan
  reads is a red control below. The ones it does not read are listed above `@spellings`. Comments and strings are not code, so this file no longer has to keep its
  own needle out of its own haystack.
  """
  use ExUnit.Case, async: true

  import PramanaFoundry.Test.AstModules, only: [nodes: 1, bindings: 1, resolve: 2]

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

  @kernel PramanaFoundry.Workflow.Kernel

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

  # Red controls. A scan that reports nothing is indistinguishable from a scan that reads
  # nothing, and five mechanisms in this subcommit shipped in exactly that condition — so
  # the scan has to be shown finding each thing it exists to find, through the same File.read
  # and parse path the real run uses. One fixture per spelling, not one fixture: a single
  # control proving "the scan matches something" is what let a live call site sit unseen.
  #
  # `K.apply (s, e)` with two arguments is a syntax error, so the space-before-paren form
  # that compiles is `K.apply (s), e`; it parses to the same node as the plain call.
  #
  # Not covered, and not decidable statically: a module bound at runtime —
  # `mod = Kernel; mod.apply(s, e)`, a module passed as an argument, one read from config.
  #
  # Not covered, though static and compiling: `Function.capture(Kernel, :apply, 2)`,
  # `__MODULE__.Kernel` inside `defmodule PramanaFoundry.Workflow`, and any macro that
  # expands to a call (the scan reads unexpanded source). The scan resolves aliases and
  # module attributes, and reads remote calls, captures, `apply/3` and `:erlang.apply/3`
  # reflection, `import` and `defdelegate`; it is not "every spelling", and says which.
  @spellings [
    {"fully-qualified", "PramanaFoundry.Workflow.Kernel.apply(s, e)"},
    {"aliased", "alias PramanaFoundry.Workflow.Kernel\n Kernel.apply(s, e)"},
    {"alias renamed", "alias PramanaFoundry.Workflow.Kernel, as: K\n K.apply(s, e)"},
    {"multi-alias", "alias PramanaFoundry.Workflow.{Kernel, Other}\n Kernel.apply(s, e)"},
    {"parenless", "alias PramanaFoundry.Workflow.Kernel, as: K\n K.apply s, e"},
    {"space before paren", "alias PramanaFoundry.Workflow.Kernel, as: K\n K.apply (s), e"},
    {"capture", "alias PramanaFoundry.Workflow.Kernel, as: K\n f = &K.apply/2\n f.(s, e)"},
    {"reflection", "alias PramanaFoundry.Workflow.Kernel, as: K\n apply(K, :apply, [s, e])"},
    {"qualified reflection",
     "alias PramanaFoundry.Workflow.Kernel, as: K\n Kernel.apply(K, :apply, [s, e])"},
    {"module attribute", "@k PramanaFoundry.Workflow.Kernel\n @k.apply(s, e)"},
    {"atom literal", ":\"Elixir.PramanaFoundry.Workflow.Kernel\".apply(s, e)"},
    {"alias rebound by a later module",
     "defmodule A do\n alias PramanaFoundry.Workflow.Kernel\n def f(s, e), do: Kernel.apply(s, e)\nend\n" <>
       "defmodule B do\n alias PramanaFoundry.DurableStore.Kernel\nend"},
    {"renamed alias rebound later",
     "alias PramanaFoundry.Workflow.Kernel, as: K\n K.apply(s, e)\n alias PramanaFoundry.Test.Harness, as: K"},
    {"as: then warn: false",
     "alias PramanaFoundry.Workflow.Kernel, as: K, warn: false\n K.apply(s, e)"},
    {"warn: false then as:",
     "alias PramanaFoundry.Workflow.Kernel, warn: false, as: K\n K.apply(s, e)"},
    {"multi-alias with warn: false",
     "alias PramanaFoundry.Workflow.{Kernel, Other}, warn: false\n Kernel.apply(s, e)"},
    {"import", "import PramanaFoundry.Workflow.Kernel\n apply(s, e)"},
    {"import only:", "import PramanaFoundry.Workflow.Kernel, only: [apply: 2]\n apply(s, e)"},
    {"defdelegate", "defdelegate go(s, e), to: PramanaFoundry.Workflow.Kernel, as: :apply"},
    {"erlang reflection",
     "alias PramanaFoundry.Workflow.Kernel, as: K\n :erlang.apply(K, :apply, [s, e])"}
  ]

  for {name, source} <- @spellings do
    test "the scan sees the #{name} spelling of a direct call" do
      path = fixture(unquote(source))
      assert [{^path, _line}] = direct_callers([path])
    end
  end

  # The negative control: the module named in a comment and in a string, and `apply/2` called
  # on a different module, none of which is a call site. A scan that flagged this would be
  # matching text again.
  test "the scan does not fire on a mention or on another module's apply/2" do
    path =
      fixture("""
      # PramanaFoundry.Workflow.Kernel.apply(s, e) in a comment
      alias PramanaFoundry.Test.Harness
      _ = "PramanaFoundry.Workflow.Kernel.apply(s, e) in a string"
      Harness.apply(s, e)
      Kernel.apply(Enum, :count, [[1]])
      """)

    assert direct_callers([path]) == []
  end

  test "the scan does not fire on the harness itself" do
    assert direct_callers([@harness | @exempt]) == []
  end

  # The harness's assertions can also be skipped from inside it, by `apply_unchecked/2`, and
  # an escape hatch nothing counts is one that spreads because it is convenient. Two call
  # sites, each named here so widening the set is a deliberate edit to this test: the B1
  # totality probe, which drives hostile payloads and claims nothing about relations, and
  # the harness's relational wiring control, which has to ask the kernel for its verdict
  # before showing the harness rejecting the same event. A third site, the harness's shape
  # wiring control, went when the kernel took over shape (property 6): it is now the
  # kernel's own red control and routes through `Harness.apply/2` like everything else.
  #
  # Counted on the AST: any call or capture of a function named `apply_unchecked`, under any
  # module spelling or none, one entry per site. There is exactly one such function.
  test "the unchecked escape hatch has exactly the call sites it is allowed" do
    callers =
      "test/**/*.{ex,exs}"
      |> Path.wildcard()
      |> Enum.reject(&(&1 == @harness))
      |> Enum.flat_map(fn path ->
        path |> ast() |> nodes() |> Enum.filter(&unchecked_call?/1) |> Enum.map(fn _ -> path end)
      end)

    assert callers == [
             "test/pramana_foundry/workflow/kernel_test.exs",
             "test/pramana_foundry/workflow/r4_exhaustive_test.exs"
           ]
  end

  test "the unchecked pin sees a call under a renamed alias" do
    path = fixture("alias PramanaFoundry.Test.Harness, as: H\n H.apply_unchecked(s, e)")
    assert [_] = path |> ast() |> nodes() |> Enum.filter(&unchecked_call?/1)
  end

  defp unchecked_call?({{:., _, [_, :apply_unchecked]}, _, _}), do: true
  defp unchecked_call?({:apply_unchecked, _, args}) when is_list(args), do: true
  defp unchecked_call?(_), do: false

  # ── The scan ──────────────────────────────────────────────────────────────────────

  defp direct_callers(paths) do
    paths
    |> Enum.reject(&(&1 in [@harness | @exempt]))
    |> Enum.flat_map(fn path ->
      quoted = ast(path)
      bindings = bindings(quoted)

      for node <- nodes(quoted), kernel_apply?(node, bindings) do
        {path, Keyword.get(elem(node, 1), :line)}
      end
    end)
  end

  defp ast(path), do: path |> File.read!() |> Code.string_to_quoted!(file: path)

  # `Mod.apply(...)`, `Mod.apply ...`, `&Mod.apply/2` — one node shape, any arity — and
  # `Kernel.apply(Mod, :apply, args)` or `:erlang.apply(Mod, :apply, args)`, reflection
  # spelled with its module.
  defp kernel_apply?({{:., _, [mod, :apply]}, _, args}, b),
    do: kernel?(mod, b) or reflects?(mod, args, b)

  # `apply(Mod, :apply, args)`, the same reflection imported.
  defp kernel_apply?({:apply, _, args}, b), do: reflects?(Kernel, args, b)

  # `import` of the kernel, reported at the import: the bare `apply(s, e)` it enables is
  # indistinguishable from `Kernel.apply/2` without resolving imports, so the import is the
  # site. With or without `only:`.
  defp kernel_apply?({:import, _, [mod | _]}, b), do: kernel?(mod, b)

  # `defdelegate f(s, e), to: Kernel` — a call site under another name, reported where declared.
  defp kernel_apply?({:defdelegate, _, [_, opts]}, b) when is_list(opts),
    do: kernel?(Keyword.get(opts, :to), b)

  defp kernel_apply?(_, _), do: false

  defp kernel?(mod, b), do: @kernel in resolve(mod, b)

  defp reflects?(callee, [target, :apply | _], b) do
    callees = resolve(callee, b)
    (Kernel in callees or :erlang in callees) and kernel?(target, b)
  end

  defp reflects?(_, _, _), do: false

  # A fixture under the test tree, removed in `on_exit`. A VM killed mid-test skips `on_exit`
  # and can leave one behind; the next run's real scan then reports it, loudly, by path.
  defp fixture(source) do
    path = "test/r4_direct_apply_fixture_#{:erlang.unique_integer([:positive])}.exs"
    File.write!(path, source <> "\n")
    on_exit(fn -> File.rm(path) end)
    path
  end
end
