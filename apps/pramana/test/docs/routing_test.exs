defmodule Docs.RoutingTest do
  @moduledoc """
  The documentation's routing layer, checked mechanically.

  `CLAUDE.md` is the only file always in an agent's context. `docs/RULES.md` holds 58 rules
  learned from real defects here, and for most of this project's life the only pointer to
  them said *"before writing a new source pipeline"* — so a rule about mix tasks, thresholds
  or Ecto queries never fired, because you are not writing a pipeline when you do those.

  The evidence that this matters is rule 8, "a scripted patch that reports success may have
  done nothing": recorded after five occurrences, then hit twice more in a single session
  **while writing rules about not doing it**. The rule was written down and not routed to.

  So the trigger table is now load-bearing, and a load-bearing table needs a test. These
  assert the two ways it can rot: a rule nobody is sent to, and a pointer to a rule that
  does not exist.
  """
  use ExUnit.Case, async: true

  @claude "CLAUDE.md"
  @rules "docs/RULES.md"

  # `__DIR__`-relative, NOT `:project_root`. That key is global application state and other
  # async tests repoint it at temp directories — the flake this repo records as
  # "async: true plus put_env(:project_root) invalidates the corpus tests". Reading it here
  # made both assertions below pass vacuously against an empty file, which is the failure
  # mode a test about routing must not have.
  @root Path.expand("../../../..", __DIR__)

  defp read!(path), do: @root |> Path.join(path) |> File.read!()

  defp rule_numbers do
    ~r/^(\d+)\. \*\*/m
    |> Regex.scan(read!(@rules))
    |> Enum.map(fn [_, n] -> String.to_integer(n) end)
    |> MapSet.new()
  end

  # The table runs from its header row to the first blank line. The obvious non-greedy
  # pattern — `\| about to….*?\n\n(.*?)\n\n` — captures the paragraph AFTER the table
  # instead, because the rows have no blank line between them, and then reports every rule
  # as unrouted. Capture the table itself.
  defp trigger_table do
    [_, table] = Regex.run(~r/(\| about to….*?)\n\n/s, read!(@claude))
    table
  end

  defp cited_numbers do
    ~r/\b(\d{1,2})\b/
    |> Regex.scan(trigger_table())
    |> Enum.map(fn [_, n] -> String.to_integer(n) end)
    |> MapSet.new()
  end

  describe "the trigger table in CLAUDE.md" do
    test "points only at rules that exist" do
      dangling = MapSet.difference(cited_numbers(), rule_numbers())

      assert MapSet.size(dangling) == 0,
             "CLAUDE.md routes to rule(s) #{inspect(Enum.sort(dangling))}, which docs/RULES.md " <>
               "does not contain. A pointer to a rule that is not there is worse than no pointer: " <>
               "it costs a lookup and returns nothing."
    end

    # THE ONE THAT ACTUALLY BITES. A rule can be written, numbered, committed — and never
    # read, because nothing sends anyone to it at the moment it applies.
    test "reaches every rule from at least one trigger" do
      unrouted = MapSet.difference(rule_numbers(), cited_numbers())

      assert MapSet.size(unrouted) == 0,
             "rule(s) #{inspect(Enum.sort(unrouted))} exist in docs/RULES.md and no trigger in " <>
               "CLAUDE.md points at them. Add a row to the trigger table — a rule nobody is " <>
               "routed to fires after the defect rather than before it."
    end

    test "is not empty, so a failed regex cannot pass both tests vacuously" do
      # Both assertions above are satisfied by two empty sets, which is what a renamed
      # heading would produce.
      assert MapSet.size(rule_numbers()) > 40
      assert MapSet.size(cited_numbers()) > 40
    end
  end

  describe "the document routing table" do
    test "reaches every document in docs/" do
      # The same rule as rules, tools and tasks: a document nobody is routed to is one the
      # next session does not know exists. Four were unreachable when this was written —
      # `CLOUD.md` among them, which is what a session needs BEFORE renting a GPU.
      #
      # The count is deliberately not asserted. `CLAUDE.md` said "Twenty-six documents" over
      # twenty-seven, which is the written-down number this project has corrected more often
      # than any other; the table now says every document is in it, and this makes that true.
      claude = File.read!(Path.join(@root, "CLAUDE.md"))

      missing =
        @root
        |> Path.join("docs/*.md")
        |> Path.wildcard()
        |> Enum.map(&Path.basename/1)
        |> Enum.reject(&String.contains?(claude, &1))

      assert missing == [],
             "not routed from CLAUDE.md: #{Enum.join(missing, ", ")}"
    end

    test "names only documents that exist" do
      missing =
        ~r/`(docs\/[A-Za-z_]+\.md)`/
        |> Regex.scan(read!(@claude))
        |> Enum.map(fn [_, path] -> path end)
        |> Enum.uniq()
        |> Enum.reject(&File.exists?(Path.join(@root, &1)))

      assert missing == [],
             "CLAUDE.md points at #{inspect(missing)}, which do not exist. The routing table " <>
               "is the answer to \"where is that written down\"; a wrong answer sends someone " <>
               "to grep, which finds the file that mentions a thing rather than the one that " <>
               "owns it."
    end
  end
end
