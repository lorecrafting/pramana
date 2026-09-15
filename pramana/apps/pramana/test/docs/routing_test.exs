defmodule Docs.RoutingTest do
  @moduledoc """
  Documentation routing checks without application, database or model dependencies.

  The root is a router, not an eager copy of every reference. Reachability, relative
  inline links, ATX/explicit anchors, rule coverage and entry budgets are checked.
  This intentionally is not a full Markdown renderer or external-link availability test.
  """
  use ExUnit.Case, async: true

  @root Path.expand("../../../../..", __DIR__)
  @triggers "docs/agents/RULE_TRIGGERS.md"
  @historical_exception {"foundry/docs/AUDIT-2026-09-12.md", "../pramana_diagnose.py#L116"}

  defp read!(path), do: @root |> Path.join(path) |> File.read!()

  defp documents do
    {output, status} = System.cmd("git", ["ls-files", "-z"], cd: @root)
    assert status == 0

    output
    |> String.split(<<0>>, trim: true)
    |> Enum.filter(&(Path.extname(&1) in [".md", ".mdx"]))
  end

  defp unfenced(text) do
    {lines, _fence} =
      text
      |> String.split("\n")
      |> Enum.map_reduce(nil, &unfenced_line/2)

    Enum.join(lines, "\n")
  end

  defp unfenced_line(line, fence) do
    case Regex.run(~r/^\s{0,3}(`{3,}|~{3,})/, line) do
      [_, marker] ->
        {"", next_fence(fence, String.first(marker), String.length(marker))}

      nil ->
        {if(fence, do: "", else: line), fence}
    end
  end

  defp next_fence(nil, char, width), do: {char, width}
  defp next_fence({char, opened}, char, width) when width >= opened, do: nil
  defp next_fence(fence, _char, _width), do: fence

  defp anchors(text) do
    explicit =
      ~r/<a\s+(?:id|name)=["']([^"']+)["']/
      |> Regex.scan(unfenced(text))
      |> Enum.map(fn [_, id] -> id end)

    {ids, _seen} =
      text
      |> unfenced()
      |> String.split("\n")
      |> Enum.reduce({[], %{}}, &heading_anchor/2)

    MapSet.new(explicit ++ ids)
  end

  defp heading_anchor(line, {ids, seen}) do
    case Regex.run(~r/^\#{1,6}\s+(.+?)(?:\s+\#+)?\s*$/u, line) do
      [_, heading] ->
        slug =
          heading
          |> String.replace(~r/<[^>]+>/u, "")
          |> String.replace(~r/!?\[([^\]]+)\]\([^)]*\)/u, "\\1")
          |> String.downcase()
          |> String.replace(~r/[^\p{L}\p{N}_\- ]/u, "")
          |> String.replace(" ", "-")

        count = Map.get(seen, slug, 0)
        id = if count == 0, do: slug, else: "#{slug}-#{count}"
        {[id | ids], Map.put(seen, slug, count + 1)}

      nil ->
        {ids, seen}
    end
  end

  defp links(path) do
    ~r/\[[^\]\n]*\]\(([^\s)]+)\)/u
    |> Regex.scan(unfenced(read!(path)))
    |> Enum.map(fn [_, target] -> target end)
    |> Enum.reject(&Regex.match?(~r/^(?:[a-zA-Z][a-zA-Z0-9+.-]*:|\/)/, &1))
  end

  defp destination(path, target) do
    [file | fragment] = String.split(target, "#", parts: 2)
    file = URI.decode(file)

    absolute =
      Path.expand(
        if(file == "", do: Path.basename(path), else: file),
        Path.join(@root, Path.dirname(path))
      )

    {Path.relative_to(absolute, @root), List.first(fragment)}
  end

  defp line_fragment?(fragment, text) do
    case Regex.run(~r/^L(\d+)(?:-L(\d+))?$/, fragment) do
      nil ->
        false

      [_, first] ->
        String.to_integer(first) in 1..length(String.split(text, "\n"))

      [_, first, last] ->
        start = String.to_integer(first)
        finish = String.to_integer(last)
        start >= 1 and finish >= start and finish <= length(String.split(text, "\n"))
    end
  end

  defp link_problem(path, target) do
    {dest, fragment} = destination(path, target)
    absolute = Path.join(@root, dest)

    cond do
      not File.exists?(absolute) ->
        {path, target}

      fragment in [nil, ""] or Path.extname(dest) not in [".md", ".mdx"] ->
        nil

      true ->
        text = File.read!(absolute)
        decoded = URI.decode(fragment)

        if MapSet.member?(anchors(text), decoded) or line_fragment?(decoded, text),
          do: nil,
          else: {path, target}
    end
  end

  defp visit([], reached, _docs), do: reached

  defp visit([path | rest], reached, docs) do
    if MapSet.member?(reached, path) do
      visit(rest, reached, docs)
    else
      next =
        path
        |> links()
        |> Enum.map(fn target -> elem(destination(path, target), 0) end)
        |> Enum.filter(&MapSet.member?(docs, &1))

      visit(next ++ rest, MapSet.put(reached, path), docs)
    end
  end

  defp rule_numbers do
    @root
    |> Path.join("pramana/docs/rules/*.md")
    |> Path.wildcard()
    |> Enum.flat_map(fn path ->
      ~r/^(\d+)\. \*\*/m
      |> Regex.scan(File.read!(path))
      |> Enum.map(fn [_, number] -> String.to_integer(number) end)
    end)
  end

  defp trigger_numbers do
    [_, table] = Regex.run(~r/(\| about to….*?)\n\n/su, read!(@triggers))

    ~r/\b(\d{1,2})\b/
    |> Regex.scan(table)
    |> Enum.map(fn [_, number] -> String.to_integer(number) end)
    |> MapSet.new()
  end

  test "the provider-neutral entry remains a small router" do
    text = read!("AGENTS.md")
    assert length(String.split(text, "\n")) <= 60
    assert byte_size(text) <= 4000
    assert String.contains?(text, "docs/agents/WORKFLOW.md")
    assert String.contains?(text, "foundry/docs/README.md")
  end

  test "provider shims import only the shared router" do
    for file <- ["CLAUDE.md", "GEMINI.md"] do
      text = read!(file)
      assert length(String.split(text, "\n")) <= 12
      assert byte_size(text) <= 800
      assert Regex.scan(~r/^@([^\n]+)$/m, text) == [["@AGENTS.md", "AGENTS.md"]]
    end
  end

  test "every tracked Markdown document is reachable from the shared router" do
    docs = MapSet.new(documents())
    assert MapSet.size(docs) > 100
    reached = visit(["AGENTS.md"], MapSet.new(), docs)
    assert MapSet.difference(docs, reached) == MapSet.new()
  end

  test "relative links and fragments resolve, with one named historical exception" do
    problems =
      for path <- documents(),
          target <- links(path),
          problem = link_problem(path, target),
          problem != nil,
          do: problem

    # This audit record intentionally points to a removed legacy diagnostic.
    # Keep the exception narrow; remove it if the record acquires a valid historical link.
    assert Enum.uniq(problems) == [@historical_exception]
  end

  test "numbered rules remain unique, contiguous and routed" do
    numbers = rule_numbers()
    assert length(numbers) > 40
    assert Enum.sort(numbers) == Enum.to_list(1..Enum.max(numbers))
    assert MapSet.new(numbers) == trigger_numbers()
  end

  test "rule links retain stable IDs" do
    index = anchors(read!("pramana/docs/RULES.md"))
    for number <- rule_numbers(), do: assert(MapSet.member?(index, "rule-#{number}"))
  end

  test "current top-level docs do not state an undated wrong pipeline version" do
    [_, current] =
      Regex.run(
        ~r/@pipeline_version\s+"(\d+)"/,
        read!("pramana/apps/pramana/lib/pramana/bake.ex")
      )

    pattern = ~r/pipeline[_ ]?version[^0-9\n]{0,16}(\d+)|pipeline \| \*{0,2}v(\d+)/i

    wrong =
      ["docs/*.md", "pramana/docs/*.md"]
      |> Enum.flat_map(fn pattern -> Path.wildcard(Path.join(@root, pattern)) end)
      |> Enum.reject(&(Path.basename(&1) in ["HISTORY.md", "PROXIES.md", "PRODUCT_STRATEGY.md"]))
      |> Enum.flat_map(fn path ->
        for line <- String.split(File.read!(path), "\n"),
            captures = Regex.run(pattern, line),
            captures != nil,
            stated = Enum.find(tl(captures), &(&1 not in [nil, ""])),
            stated != current,
            not Regex.match?(~r/\d{4}-\d{2}-\d{2}/, line),
            do: {Path.relative_to(path, @root), stated, line}
      end)

    assert wrong == []
  end
end
