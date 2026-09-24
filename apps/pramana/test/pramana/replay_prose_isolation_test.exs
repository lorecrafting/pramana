defmodule Pramana.ReplayProseIsolationTest do
  @moduledoc "Replay JSON is data, not an extra quotation or a repair target."
  use Pramana.DataCase, async: true

  alias Pramana.Repair
  alias Pramana.Report

  @unknown "pramana:cbeta.T:T9999_001@p0001a01"

  defp fenced(record), do: "```pramana-replay\n" <> Jason.encode!(record) <> "\n```"

  test "addresses in arguments and assertions are checked only by the replay" do
    markdown =
      fenced(%{
        tool: "inspect",
        arguments: %{urn: @unknown, query: "T. 262, 99a1"},
        assert: %{anchor: @unknown}
      })

    result =
      Report.verify(markdown,
        executor: fn "inspect", _ -> {:ok, %{anchor: @unknown}} end,
        bake_id: "b"
      )

    assert result.status == :verified
    assert result.citations.checked == 0
    assert result.foreign == []
    assert result.resolved_text == markdown
  end

  test "masking multibyte replay data preserves offsets of following prose citations" do
    replay = fenced(%{tool: "count", arguments: %{query: "བོད་漢 é"}, assert: %{n: 1}})
    markdown = replay <> "\nSee " <> @unknown <> "."

    result =
      Report.verify(markdown,
        executor: fn "count", _ -> {:ok, %{n: 1}} end,
        bake_id: "b"
      )

    assert result.status == :failed
    assert [finding] = result.citations.findings
    assert finding.urn == @unknown
    assert finding.source_offset == byte_size(replay <> "\nSee ")
    assert result.resolved_text == markdown
  end

  test "repair preserves replay addresses while editing only the following prose" do
    replay = fenced(%{tool: "get_passage", arguments: %{urn: @unknown, query: "བོད་ é"}})
    original = replay <> "\nSee [" <> @unknown <> "]."
    result = Repair.repair(original)

    assert result.text == replay <> "\nSee ."
    assert [edit] = result.edits
    assert edit.range.byte_start == byte_size(replay <> "\nSee ")
    assert edit.before == "[" <> @unknown <> "]"
    assert [%{state: :no_sources}] = result.actions
  end
end
