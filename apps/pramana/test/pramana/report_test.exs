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

      assert [%{status: :executed, detail: detail}] = result.replays
      assert detail =~ "no value asserted"
      assert result.status == :incomplete
      refute result.ok?
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
      assert result.status == :no_checkable_evidence
      refute result.ok?
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

  describe "one authoritative status" do
    test "zero checkable evidence cannot be reported as verified" do
      result = Report.verify("A confident assertion.", executor: executor(%{}), bake_id: "b")
      assert result.status == :no_checkable_evidence
      refute result.ok?
      assert result.counts.verified_quotes == 0
      assert result.counts.verified_replays == 0
      assert result.summary =~ "not a pass"
    end

    test "a replay execution error is incomplete rather than a failed claim" do
      result =
        Report.verify(fenced(~s({"tool":"search","arguments":{},"assert":{"total":1}})),
          executor: fn _, _ -> raise "private failure details" end,
          bake_id: "b"
        )

      assert result.status == :incomplete
      assert result.counts.replay_errors == 1
      assert [%{status: :error, detail: detail}] = result.replays
      refute detail =~ "private failure details"
      refute result.ok?
    end

    test "recognized but unresolved foreign evidence prevents a mixed report from passing" do
      markdown =
        fenced(~s({"tool":"count","arguments":{},"assert":{"total":1}})) <>
          "\n\nSee T. 262, 99a1."

      result =
        Report.verify(markdown, executor: executor(%{"count" => %{total: 1}}), bake_id: "b")

      assert result.counts.verified_replays == 1
      assert result.counts.unresolved_foreign == 1
      assert result.status == :incomplete
      refute result.ok?
    end

    test "an asserted failure remains failed even when other evidence is incomplete" do
      markdown =
        fenced(~s({"tool":"count","arguments":{},"assert":{"total":2}})) <>
          "\n\nSee T. 262, 99a1."

      result =
        Report.verify(markdown, executor: executor(%{"count" => %{total: 1}}), bake_id: "b")

      assert result.status == :failed
      assert result.counts.unresolved_foreign == 1
      assert result.counts.replay_failures == 1
    end

    test "an unsourced-figure warning alone does not turn checked evidence into a failure" do
      markdown =
        "There are 7 possibilities.\n\n" <>
          fenced(~s({"tool":"count","arguments":{},"assert":{"total":1}}))

      result =
        Report.verify(markdown, executor: executor(%{"count" => %{total: 1}}), bake_id: "b")

      assert result.status == :verified
      assert result.ok?
      assert result.unsourced_figures != []
    end

    test "a recorded bake cannot replay against an unstamped database" do
      markdown = fenced(~s({"tool":"count","arguments":{},"bake_id":"old","assert":{"total":1}}))

      result =
        Report.verify(markdown, executor: fn _, _ -> flunk("must not run") end, bake_id: nil)

      assert result.status == :incomplete
      assert [%{status: :unverifiable}] = result.replays
    end
  end

  describe "untrusted replay assertions" do
    test "non-map assertions and invalid identity types are rejected before executing" do
      for value <- [nil, false, 1, "text", [], [1]] do
        markdown = fenced(Jason.encode!(%{tool: "count", arguments: %{}, assert: value}))

        result =
          Report.verify(markdown,
            executor: fn _, _ -> flunk("invalid assertion executed") end,
            bake_id: "b"
          )

        assert [%{reason: :invalid_assertions}] = result.malformed
        assert result.status == :incomplete
      end

      for id <- [1, %{}, []] do
        markdown = fenced(Jason.encode!(%{tool: "count", arguments: %{}, bake_id: id}))
        assert [%{reason: :invalid_bake_id}] = Report.parse(markdown).malformed
      end
    end

    test "empty path components are rejected" do
      for path <- ["", ".total", "total.", "nested..total"] do
        markdown = fenced(Jason.encode!(%{tool: "count", arguments: %{}, assert: %{path => 1}}))
        assert [%{reason: :invalid_assertion_path}] = Report.parse(markdown).malformed
      end
    end

    test "missing fields do not satisfy explicit null, including nested paths" do
      for payload <- [%{}, %{"nested" => nil}, %{"nested" => %{}}] do
        markdown = fenced(~s({"tool":"count","arguments":{},"assert":{"nested.value":null}}))
        result = Report.verify(markdown, executor: executor(%{"count" => payload}), bake_id: "b")
        assert result.status == :failed
        assert [%{mismatches: [%{actual_present: false, expected: nil}]}] = result.replays
      end
    end

    test "explicit null and false are preserved, with string keys taking precedence over atom keys" do
      markdown =
        fenced(~s({"tool":"count","arguments":{},"assert":{"nested.value":null,"enabled":false}}))

      payload = %{"nested" => %{"value" => nil}, "enabled" => false, enabled: true}
      result = Report.verify(markdown, executor: executor(%{"count" => payload}), bake_id: "b")
      assert result.status == :verified
      assert result.ok?
    end

    test "unterminated replay evidence cannot disappear beside valid evidence" do
      markdown =
        fenced(~s({"tool":"count","arguments":{},"assert":{"total":1}})) <>
          "\n\n```pramana-replay\n{unfinished"

      result =
        Report.verify(markdown, executor: executor(%{"count" => %{total: 1}}), bake_id: "b")

      assert result.counts.verified_replays == 1
      assert [%{reason: :unterminated_replay}] = result.malformed
      assert result.status == :incomplete
    end
  end
end
