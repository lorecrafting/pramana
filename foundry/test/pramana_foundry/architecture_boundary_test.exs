Code.require_file("../support/ast_modules.ex", __DIR__)

defmodule PramanaFoundry.ArchitectureBoundaryTest do
  @moduledoc """
  The decoupling rules in `docs/BOUNDARY-RULES.md`, read from the AST.

  References are resolved with the same alias and module-attribute resolver the harness
  routing check uses (`test/support/ast_modules.ex`), so an alias, a renamed alias, a
  multi-alias or a module attribute is a reference, and a comment or a `@moduledoc`/`@doc`
  mention is not. What that resolver does not see is listed in
  `r4_no_direct_apply_test.exs`; this scan also reads `:"Elixir.…"` atom literals.
  """
  use ExUnit.Case, async: true

  alias PramanaFoundry.Test.AstModules, as: Ast

  @rules "foundry/docs/BOUNDARY-RULES.md"
  @core "lib/pramana_foundry/durable_store/**/*.ex"
  @workflow "lib/pramana_foundry/workflow/**/*.ex"
  @generic_kernel [
    "lib/pramana_foundry/workflow/kernel.ex",
    "lib/pramana_foundry/workflow/kernel/*.ex"
  ]

  # Rule 4's one declared exception. The kernel dispatcher routes each event type to its
  # family module, and six of those families are the software workflow's. The alias and the
  # `@families` table are the only places the generic kernel may name them; a Software
  # reference anywhere else in a generic kernel file fails. Deleting either site keeps this
  # green: the list may shrink, never grow.
  @software_sites [
    {PramanaFoundry.Workflow.Kernel, :alias},
    {PramanaFoundry.Workflow.Kernel, {:@, :families}}
  ]

  # Rule 3's declared sites: every place Core may spell a role (`developer`, `reviewer`,
  # `pm`, alone or as a dotted part such as `starts.developer`). Pinned by module and
  # attribute or function name, not by line or count, so removing a site stays green and a
  # role token at any new site fails.
  #
  # A generic role list is not attempted: Foundry's other role names — `check`, `build`,
  # `integration`, `activation`, `freeze` — are also ordinary words for Core's own
  # operations, dimensions and receipts, so a scan for them would flag Core's vocabulary
  # rather than a methodology leak. The three pinned here have no generic meaning in Core.
  # Snake-case compounds (`developer_closed`) are event-type names, not role tokens.
  @role_sites [
    {PramanaFoundry.DurableStore.TransitionPlan, {:@, :read_kinds}},
    {PramanaFoundry.DurableStore.ProtectedPrimitives, {:@, :dimensions}},
    {PramanaFoundry.DurableStore.ProtectedPrimitives, {:def, :persist_nonstart_settlement}},
    {PramanaFoundry.DurableStore.ProtectedPrimitives, {:defp, :required_dimension}}
  ]
  @role ~r/(?<![A-Za-z0-9_])(developer|reviewer|pm)(?![A-Za-z0-9_])/i

  @umbrella_apps [:pramana, :pramana_web, :pramana_native]
  @umbrella_roots ~w(Pramana PramanaWeb PramanaNative)

  @workflow_prefix ~w(PramanaFoundry Workflow)
  @store_prefix ~w(PramanaFoundry DurableStore)
  @software_prefix ~w(PramanaFoundry Workflow Kernel Software)

  describe "rule 1" do
    test "Core references no Workflow module" do
      assert_none(references(Path.wildcard(@core), &under?(&1, @workflow_prefix)), 1)
    end

    test "red control: an aliased Workflow module in a Core file is seen" do
      path =
        fixture(
          "defmodule C do\n alias PramanaFoundry.Workflow.Kernel, as: K\n def f, do: K.x()\nend"
        )

      assert [{^path, 2, _, _}, {^path, 3, _, _}] =
               references([path], &under?(&1, @workflow_prefix))
    end

    test "negative control: a comment or @moduledoc mention is not a reference" do
      path =
        fixture(
          "defmodule C do\n @moduledoc \"PramanaFoundry.Workflow.Kernel\"\n # PramanaFoundry.Workflow.Kernel\nend"
        )

      assert references([path], &under?(&1, @workflow_prefix)) == []
    end
  end

  describe "rule 2" do
    test "the workflow kernel references no DurableStore module" do
      assert_none(references(Path.wildcard(@workflow), &under?(&1, @store_prefix)), 2)
    end

    test "red control: a multi-alias of DurableStore is seen" do
      path = fixture("alias PramanaFoundry.DurableStore.{Gateway, Database}\nGateway.put(x)")
      assert [_ | _] = references([path], &under?(&1, @store_prefix))
    end
  end

  describe "rule 4" do
    test "generic kernel modules name kernel/software only at the declared sites" do
      @generic_kernel
      |> Enum.flat_map(&Path.wildcard/1)
      |> references(&under?(&1, @software_prefix))
      |> Enum.reject(fn {_, _, site, _} -> site in @software_sites end)
      |> assert_none(4)
    end

    test "red control: a Software reference outside the declared sites is seen" do
      path =
        fixture(
          "defmodule PramanaFoundry.Workflow.Kernel do\n" <>
            " alias PramanaFoundry.Workflow.Kernel.Software.Review\n" <>
            " @families [Review]\n def f, do: Review.x()\nend"
        )

      found =
        [path]
        |> references(&under?(&1, @software_prefix))
        |> Enum.reject(fn {_, _, site, _} -> site in @software_sites end)

      assert [{^path, 4, {PramanaFoundry.Workflow.Kernel, {:def, :f}}, _}] = found
    end
  end

  describe "rule 6" do
    test "Foundry declares and locks no Pramāṇa app" do
      deps = Enum.map(Mix.Project.config()[:deps], &elem(&1, 0))
      assert Enum.filter(deps, &(&1 in @umbrella_apps)) == []

      lock = File.read!("mix.lock")
      assert Enum.filter(@umbrella_apps, &String.contains?(lock, "\"#{&1}\":")) == []
    end

    test "Foundry lib references no Pramāṇa app module" do
      assert_none(references(Path.wildcard("lib/**/*.ex"), &umbrella?/1), 6)
    end

    test "red control: a Pramana module reference is seen" do
      path = fixture("Pramana.Corpus.get(x)")
      assert [{^path, 1, _, Pramana.Corpus}] = references([path], &umbrella?/1)
    end
  end

  describe "rule 3" do
    test "role vocabulary appears in Core only at the declared sites" do
      @core
      |> Path.wildcard()
      |> role_tokens()
      |> Enum.reject(fn {_, _, site, _} -> site in @role_sites end)
      |> assert_none(3)
    end

    test "red control: a role literal in a new Core function is seen" do
      path =
        fixture(
          "defmodule PramanaFoundry.DurableStore.ProtectedPrimitives do\n" <>
            " @moduledoc \"the reviewer\"\n # reviewer\n" <>
            " def new_site(r), do: r == \"reviewer\"\n def g, do: \"reviewer_closed\"\nend"
        )

      assert [
               {^path, 4, {PramanaFoundry.DurableStore.ProtectedPrimitives, {:def, :new_site}},
                "reviewer"}
             ] = role_tokens([path])
    end

    test "red control: a dotted role part in an attribute is seen" do
      path = fixture("defmodule M do\n @x ~w(starts.pm)\nend")
      assert [{^path, 2, {M, {:@, :x}}, "starts.pm"}] = role_tokens([path])
    end
  end

  # ── The scan ──────────────────────────────────────────────────────────────────────

  defp assert_none([], _rule), do: :ok

  defp assert_none(found, rule) do
    flunk(
      "rule #{rule} of #{@rules} forbids:\n" <>
        Enum.map_join(found, "\n", fn {path, line, site, what} ->
          "  #{path}:#{line} #{inspect(site)} #{inspect(what)}"
        end)
    )
  end

  defp under?(mod, prefix), do: Enum.take(Module.split(mod), length(prefix)) == prefix
  defp umbrella?(mod), do: hd(Module.split(mod)) in @umbrella_roots

  # {path, line, site, module} for every resolved module reference matching `pred?`.
  defp references(paths, pred?) do
    for path <- paths,
        quoted = ast(path),
        bindings = Ast.bindings(quoted),
        {node, line, site} <- sited(quoted),
        mod <- modules(node, bindings),
        pred?.(mod),
        uniq: true,
        do: {path, line, site, mod}
  end

  defp modules({:__aliases__, _, _} = node, b), do: Enum.filter(Ast.resolve(node, b), &elixir?/1)

  defp modules({:@, _, [{_, _, nil}]} = node, b),
    do: Enum.filter(Ast.resolve(node, b), &elixir?/1)

  defp modules(atom, _) when is_atom(atom), do: Enum.filter([atom], &elixir?/1)
  defp modules(_, _), do: []

  defp elixir?(atom), do: String.starts_with?(Atom.to_string(atom), "Elixir.")

  # {path, line, site, token} for every role token in a string or atom literal. A token is a
  # run of word characters and dots, so `starts.developer` is one token and `developer_closed`
  # is not a role token.
  defp role_tokens(paths) do
    for path <- paths,
        {node, line, site} <- sited(ast(path)),
        text <- literal(node),
        [token] <- Regex.scan(~r/[\w.]+/u, text),
        Regex.match?(@role, token) and not String.contains?(token, "_"),
        do: {path, line, site, token}
  end

  defp literal(s) when is_binary(s), do: [s]

  defp literal(a) when is_atom(a) and a not in [nil, true, false],
    do: if(elixir?(a), do: [], else: [Atom.to_string(a)])

  defp literal(_), do: []

  defp ast(path), do: path |> File.read!() |> Code.string_to_quoted!(file: path)

  # Every node with its nearest line and its site: `{module, :alias}`, `{module, {:@, name}}`
  # or `{module, {kind, name}}` for a def. `@moduledoc` and `@doc` bodies are prose, not code,
  # and are skipped. A call's own name is not a literal and is not yielded.
  defp sited(quoted), do: quoted |> walk(nil, nil, 0, []) |> Enum.reverse()

  defp walk({:defmodule, meta, [name, [do: body]]}, mod, _site, _line, acc) do
    mod = Module.concat([mod || Elixir | alias_segments(name)])
    walk(body, mod, {mod, :module}, meta[:line], acc)
  end

  defp walk({:@, _, [{doc, _, _}]}, _mod, _site, _line, acc) when doc in [:moduledoc, :doc],
    do: acc

  defp walk({:@, meta, [{name, _, [value]}]} = node, mod, _site, _line, acc) when is_atom(name),
    do:
      walk(value, mod, {mod, {:@, name}}, meta[:line], [
        {node, meta[:line], {mod, {:@, name}}} | acc
      ])

  defp walk({:alias, meta, args}, mod, _site, _line, acc),
    do: walk(args, mod, {mod, :alias}, meta[:line], acc)

  defp walk({kind, meta, [head | body]}, mod, _site, _line, acc)
       when kind in [:def, :defp, :defmacro, :defmacrop] do
    site = {mod, {kind, def_name(head)}}
    walk([head | body], mod, site, meta[:line], acc)
  end

  # A module name is a reference, and its segments are not literals.
  defp walk({:__aliases__, meta, _} = node, _mod, site, line, acc),
    do: [{node, Keyword.get(meta, :line, line), site} | acc]

  defp walk({f, meta, args} = node, mod, site, line, acc) when is_list(meta) do
    line = Keyword.get(meta, :line, line)
    acc = [{node, line, site} | acc]
    acc = if is_atom(f), do: acc, else: walk(f, mod, site, line, acc)
    if is_list(args), do: walk(args, mod, site, line, acc), else: acc
  end

  defp walk(list, mod, site, line, acc) when is_list(list),
    do: Enum.reduce(list, acc, &walk(&1, mod, site, line, &2))

  defp walk({a, b}, mod, site, line, acc),
    do: walk(b, mod, site, line, walk(a, mod, site, line, acc))

  defp walk(leaf, _mod, site, line, acc), do: [{leaf, line, site} | acc]

  defp alias_segments({:__aliases__, _, segs}), do: segs
  defp alias_segments(atom) when is_atom(atom), do: [atom]

  defp def_name({:when, _, [head | _]}), do: def_name(head)
  defp def_name({name, _, _}), do: name

  defp fixture(source) do
    path = "test/architecture_boundary_fixture_#{:erlang.unique_integer([:positive])}.exs"
    File.write!(path, source <> "\n")
    on_exit(fn -> File.rm(path) end)
    path
  end
end
