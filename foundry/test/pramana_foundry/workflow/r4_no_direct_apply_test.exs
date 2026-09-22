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
  as many spellings as the language allows; the AST has three shapes, and each is a red
  control below. Comments and strings are not code, so this file no longer has to keep its
  own needle out of its own haystack.
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
  # The scan resolves aliases and module attributes, which are the two static bindings a
  # module name can have; a variable is not one.
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
    {"atom literal", ":\"Elixir.PramanaFoundry.Workflow.Kernel\".apply(s, e)"}
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

  defp nodes(quoted) do
    {_, acc} = Macro.prewalk(quoted, [], fn node, acc -> {node, [node | acc]} end)
    Enum.reverse(acc)
  end

  # `Mod.apply(...)`, `Mod.apply ...`, `&Mod.apply/2` — one node shape, any arity — and
  # `Kernel.apply(Mod, :apply, args)`, Elixir's reflection spelled with its module.
  defp kernel_apply?({{:., _, [mod, :apply]}, _, args}, b),
    do: resolve(mod, b) == @kernel or reflects?(mod, args, b)

  # `apply(Mod, :apply, args)`, the same reflection imported.
  defp kernel_apply?({:apply, _, args}, b), do: reflects?(Kernel, args, b)
  defp kernel_apply?(_, _), do: false

  defp reflects?(callee, [target, :apply | _], b),
    do: resolve(callee, b) == Kernel and resolve(target, b) == @kernel

  defp reflects?(_, _, _), do: false

  # Static module bindings in the file: `alias A.B`, `alias A.B, as: C`, `alias A.{B, C}` and
  # `@name A.B`. Collected file-wide rather than per lexical scope, which can only over-report.
  defp bindings(quoted) do
    quoted
    |> nodes()
    |> Enum.reduce(%{}, fn
      {:alias, _, [{{:., _, [prefix, :{}]}, _, targets}]}, acc ->
        Enum.reduce(targets, acc, fn {:__aliases__, _, segs}, acc ->
          bind(acc, List.last(segs), Module.concat([resolve(prefix, acc) | segs]))
        end)

      {:alias, _, [{:__aliases__, _, segs} = target | opts]}, acc ->
        name =
          case opts do
            [[as: {:__aliases__, _, [as]}]] -> as
            _ -> List.last(segs)
          end

        bind(acc, name, resolve(target, acc))

      {:@, _, [{name, _, [value]}]}, acc ->
        bind(acc, {:@, name}, resolve(value, acc))

      _, acc ->
        acc
    end)
  end

  defp bind(acc, _name, nil), do: acc
  defp bind(acc, name, module), do: Map.put(acc, name, module)

  defp resolve({:__aliases__, _, [first | rest]}, bindings) when is_atom(first) do
    case bindings do
      %{^first => module} -> Module.concat([module | rest])
      _ -> Module.concat([first | rest])
    end
  end

  defp resolve({:@, _, [{name, _, nil}]}, bindings), do: bindings[{:@, name}]
  defp resolve(module, _) when is_atom(module), do: module
  defp resolve(_, _), do: nil

  # A fixture under the test tree, gone when the test is, so a crash cannot leave the real
  # scan a file to report.
  defp fixture(source) do
    path = "test/r4_direct_apply_fixture_#{:erlang.unique_integer([:positive])}.exs"
    File.write!(path, source <> "\n")
    on_exit(fn -> File.rm(path) end)
    path
  end
end
