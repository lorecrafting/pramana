defmodule Pramana.ReportParseTest do
  use ExUnit.Case, async: true
  alias Pramana.Report
  defp fenced(json), do: "```pramana-replay\n#{json}\n```"

  describe "parse/1" do
    test "pulls out every replay record with the line it sits on" do
      markdown = """
      A claim about frequency.

      #{fenced(~s({"tool":"survey_corpus","arguments":{"query":"一切眾生"},"assert":{"total":36775}}))}
      """

      assert %{replays: [replay], malformed: []} = Report.parse(markdown)
      assert replay.tool == "survey_corpus"
      assert replay.arguments == %{"query" => "一切眾生"}
      assert replay.assert == %{"total" => 36_775}
      assert replay.line == 3
    end

    test "a malformed block is REPORTED, never skipped" do
      # A record nobody can parse is a claim nobody checked. Dropping it silently would let
      # a report read as fully verified because its evidence was unreadable.
      markdown = fenced("{not json at all")

      assert %{replays: [], malformed: [%{reason: :invalid_json}]} = Report.parse(markdown)
    end

    test "a block missing tool or arguments is malformed, not a replay" do
      assert %{malformed: [%{reason: :missing_tool_or_arguments}]} =
               Report.parse(fenced(~s({"assert":{"total":1}})))
    end

    test "a report with no replay records parses cleanly" do
      assert %{replays: [], malformed: []} = Report.parse("Just prose.")
    end
  end
end
