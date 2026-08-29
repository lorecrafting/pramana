defmodule Pramana.ReportTest do
  @moduledoc """
  Verifying a report, not just the quotations in it.

  The interesting cases are all refusals. A checker that turns "the corpus changed" into
  "the report is false" teaches people to ignore it, and a checker that reports a pass rate
  over only what it could check is rule 44 wearing a badge. Both are asserted here.
  """
  use Pramana.DataCase, async: true

  alias Pramana.Report

  defp fenced(json), do: "```pramana-replay\n#{json}\n```"

  defp executor(payloads) do
    fn tool, args ->
      case Map.fetch(payloads, tool) do
        {:ok, fun} when is_function(fun, 1) -> {:ok, fun.(args)}
        {:ok, payload} -> {:ok, payload}
        :error -> {:error, {:unknown_tool, tool}}
      end
    end
  end

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

  describe "verify/2 — replay records" do
    test "an asserted figure that still holds is verified" do
      markdown =
        fenced(~s({"tool":"survey_corpus","arguments":{"query":"X"},"assert":{"total":36775}}))

      result =
        Report.verify(markdown,
          executor: executor(%{"survey_corpus" => %{"total" => 36_775, "works" => 1904}}),
          bake_id: "bake-1"
        )

      assert [%{status: :verified}] = result.replays
      assert result.ok?
    end

    test "a figure that no longer holds FAILS, and names both numbers" do
      markdown =
        fenced(~s({"tool":"survey_corpus","arguments":{"query":"X"},"assert":{"total":36775}}))

      result =
        Report.verify(markdown,
          executor: executor(%{"survey_corpus" => %{"total" => 12}}),
          bake_id: "bake-1"
        )

      assert [%{status: :failed, detail: detail}] = result.replays
      assert detail =~ "36775"
      assert detail =~ "12"
      refute result.ok?
    end

    test "a dotted path reaches into the payload" do
      markdown =
        fenced(~s({"tool":"search","arguments":{"query":"X"},"assert":{"coverage.dated":1515}}))

      result =
        Report.verify(markdown,
          executor: executor(%{"search" => %{"coverage" => %{"dated" => 1515}}}),
          bake_id: "bake-1"
        )

      assert [%{status: :verified}] = result.replays
    end

    test "a DIFFERENT bake is :unverifiable, never :failed" do
      # The corpus changed; the claim may well have been true when it was made. Calling that
      # a falsehood is how a checker teaches people to ignore it.
      markdown =
        fenced(
          ~s({"tool":"survey_corpus","arguments":{"query":"X"},"bake_id":"bake-OLD","assert":{"total":36775}})
        )

      result =
        Report.verify(markdown,
          executor: fn _, _ -> flunk("must not re-execute against a different corpus") end,
          bake_id: "bake-NEW"
        )

      assert [%{status: :unverifiable, detail: detail}] = result.replays
      assert detail =~ "not refuted"
      # ...and it does not pass either. Not shown wrong is not the same as shown right.
      refute result.ok?
    end

    test "an unknown tool is an error rather than a silent pass" do
      markdown = fenced(~s({"tool":"no_such_tool","arguments":{}}))

      result = Report.verify(markdown, executor: executor(%{}), bake_id: "bake-1")

      assert [%{status: :error}] = result.replays
      refute result.ok?
    end

    test "an empty assert still re-executes, and says that is all it proved" do
      markdown = fenced(~s({"tool":"survey_corpus","arguments":{"query":"X"}}))

      result =
        Report.verify(markdown,
          executor: executor(%{"survey_corpus" => %{"total" => 1}}),
          bake_id: "bake-1"
        )

      assert [%{status: :verified, detail: detail}] = result.replays
      assert detail =~ "no value asserted"
    end

    test "a malformed block prevents ok?, because its claim went unchecked" do
      result =
        Report.verify(fenced("{broken"), executor: executor(%{}), bake_id: "bake-1")

      refute result.ok?
      assert [%{reason: :invalid_json}] = result.malformed
    end
  end

  describe "verify/2 — the replay cap" do
    test "excess records are reported as skipped, and prevent ok?" do
      # A report is untrusted input and every replay is a query. Silently dropping the
      # overflow would let a document be declared verified on the first few of its claims.
      markdown =
        1..5
        |> Enum.map_join("\n\n", fn n ->
          fenced(~s({"tool":"survey_corpus","arguments":{"query":"q#{n}"}}))
        end)

      result =
        Report.verify(markdown,
          executor: executor(%{"survey_corpus" => %{"total" => 1}}),
          bake_id: "b",
          max_replays: 2
        )

      assert length(result.replays) == 2
      assert result.skipped == 3
      refute result.ok?
    end
  end

  describe "verify/2 — unsourced figures" do
    test "flags a paragraph carrying a figure and no citation" do
      markdown = """
      The phrase appears 36,775 times across 1,904 works.

      This paragraph cites pramana:cbeta.T:T0262_001@p0001c17 and carries a figure of 12.
      """

      result = Report.verify(markdown, executor: executor(%{}), bake_id: "b")

      assert [flagged] = result.unsourced_figures
      assert flagged =~ "36,775"
    end

    test "it is a warning list and not a verdict" do
      # A heuristic that failed the report would make the checker unusable on any prose
      # containing a page number. It reads, it does not judge.
      markdown = "A paragraph with the number 7 in it and nothing else."

      result = Report.verify(markdown, executor: executor(%{}), bake_id: "b")

      assert result.unsourced_figures != []
      assert result.ok?
    end
  end

  describe "verify/2 — citations" do
    test "carries the guard's own result through untouched" do
      # `Pramana.Guard` owns quotation checking and this module does not second-guess it.
      result = Report.verify("No citations here.", executor: executor(%{}), bake_id: "b")

      assert result.citations.checked == 0
      assert result.citations.ok?
    end

    test "a fabricated URN fails the report" do
      result =
        Report.verify("See pramana:cbeta.T:T9999_001@p0001a01.",
          executor: executor(%{}),
          bake_id: "b"
        )

      refute result.citations.ok?
      refute result.ok?
    end
  end
end
