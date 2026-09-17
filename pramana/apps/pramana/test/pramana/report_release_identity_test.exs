defmodule Pramana.ReportReleaseIdentityTest do
  @moduledoc """
  A changed retrieval layer is unavailable evidence, not a false assertion. These tests
  separate source identity, selected release, returned receipt and the historical format.
  """
  use Pramana.DataCase, async: true

  alias Pramana.EvidenceInput
  alias Pramana.Release
  alias Pramana.Report

  defp document(fields \\ %{}) do
    record =
      Map.merge(
        %{
          "tool" => "survey_corpus",
          "arguments" => %{},
          "bake_id" => "source-A",
          "release_id" => "release-A",
          "assert" => %{"total" => 7}
        },
        fields
      )

    "```pramana-replay\n" <> Jason.encode!(record) <> "\n```"
  end

  defp verify(markdown, executor, opts \\ []) do
    Report.verify(
      markdown,
      Keyword.merge([bake_id: "source-A", release_id: "release-A", executor: executor], opts)
    )
  end

  defp receipt(fields \\ %{}),
    do: Map.merge(%{"bake_id" => "source-A", "release_id" => "release-A", "total" => 7}, fields)

  test "the same source with a different selected release refuses before executing" do
    result =
      verify(document(), fn _, _ -> flunk("must not execute against the replacement index") end,
        release_id: "release-B"
      )

    assert result.status == :incomplete
    assert result.counts.unverifiable_replays == 1
    assert result.counts.replay_failures == 0

    assert [%{status: :unverifiable, identity_field: :release_id, release_id: "release-A"}] =
             result.replays

    refute result.ok?
  end

  test "an unavailable selection cannot silently downgrade a release-bound report" do
    result =
      verify(document(), fn _, _ -> flunk("no selected release") end, release_id: nil)

    assert [%{status: :unverifiable, identity_field: :release_id}] = result.replays
    assert result.checked_identity == %{bake_id: "source-A", release_id: nil}
    assert result.status == :incomplete
    assert Release.current_id() == nil
  end

  test "matching selected and returned identities verify only the asserted values" do
    for payload <- [receipt(), %{bake_id: "source-A", release_id: "release-A", total: 7}] do
      result = verify(document(), fn "survey_corpus", %{} -> {:ok, payload} end)
      assert result.status == :verified
      assert [%{identity_scope: :retrieval_release, status: :verified}] = result.replays
    end

    changed = verify(document(), fn _, _ -> {:ok, receipt(%{"total" => 8})} end)
    assert changed.status == :failed
    assert [%{mismatches: [%{expected: 7, actual: 8}]}] = changed.replays
  end

  test "matching release does not excuse a different or unavailable named source" do
    for bake <- ["source-B", nil] do
      result = verify(document(), fn _, _ -> flunk("source mismatch") end, bake_id: bake)
      assert [%{status: :unverifiable, identity_field: :bake_id}] = result.replays
    end
  end

  test "a changed response receipt cannot produce either a false failure or a false pass" do
    for total <- [7, 999] do
      result =
        verify(document(), fn _, _ ->
          {:ok, receipt(%{"release_id" => "release-B", "total" => total})}
        end)

      assert result.status == :incomplete
      assert [%{status: :unverifiable, detail: detail} = replay] = result.replays
      assert detail =~ "replay response"
      assert detail =~ "not refuted"
      refute Map.has_key?(replay, :mismatches)
      assert result.counts.verified_replays == 0
      assert result.counts.replay_failures == 0
    end
  end

  test "missing or malformed returned identity is unavailable evidence, not an execution pass" do
    for invalid <- [nil, "", false, 17, [], %{}] do
      result = verify(document(), fn _, _ -> {:ok, receipt(%{"release_id" => invalid})} end)
      assert [%{status: :unverifiable, identity_field: :release_id}] = result.replays
      assert result.status == :incomplete
    end

    for payload <- [Map.delete(receipt(), "release_id"), %{"total" => 7}] do
      result = verify(document(), fn _, _ -> {:ok, payload} end)
      assert [%{status: :unverifiable}] = result.replays
    end

    result = verify(document(), fn _, _ -> {:ok, receipt(%{"bake_id" => "source-B"})} end)
    assert [%{status: :unverifiable, identity_field: :bake_id}] = result.replays
  end

  test "a malformed recorded release is not dropped and its executor is never called" do
    for invalid <- ["", " \t", false, 17, [], %{}] do
      report = document(%{"release_id" => invalid})
      assert %{replays: [], malformed: [%{reason: :invalid_release_id}]} = Report.parse(report)

      result =
        verify(report, fn _, _ -> flunk("invalid identity must not become a legacy replay") end)

      assert result.status == :incomplete
      assert result.counts.malformed_replays == 1
    end
  end

  test "opaque historical release ids are compared literally, never upgraded" do
    old = String.duplicate("a", 64)
    report = document(%{"release_id" => old})
    assert %{replays: [%{release_id: ^old}], malformed: []} = Report.parse(report)

    result =
      verify(report, fn _, _ -> {:ok, receipt(%{"release_id" => old})} end, release_id: old)

    assert result.status == :verified

    result =
      verify(report, fn _, _ -> flunk("prefixes are not interchangeable") end,
        release_id: "v2:" <> old
      )

    assert result.status == :incomplete
  end

  test "omitted and null releases retain legacy behavior with explicit provenance limits" do
    omitted =
      "```pramana-replay\n" <>
        Jason.encode!(%{
          tool: "survey_corpus",
          arguments: %{},
          bake_id: "source-A",
          assert: %{total: 7}
        }) <>
        "\n```"

    for report <- [omitted, document(%{"release_id" => nil})] do
      result = verify(report, fn _, _ -> {:ok, %{"total" => 7}} end, release_id: "new-selection")
      assert result.status == :verified
      assert [%{identity_scope: :source_bake_only, identity_note: note}] = result.replays
      assert note =~ "No retrieval release was recorded"
    end

    result =
      verify(
        document(%{"release_id" => nil, "bake_id" => nil}),
        fn _, _ -> {:ok, %{"total" => 7}} end
      )

    assert [%{identity_scope: :unrecorded, status: :verified}] = result.replays
  end

  test "a release alone is supported, but no assertions still means incomplete" do
    report = document(%{"bake_id" => nil, "assert" => %{}})
    result = verify(report, fn _, _ -> {:ok, %{"release_id" => "release-A"}} end)
    assert [%{status: :executed, identity_scope: :retrieval_release}] = result.replays
    assert result.status == :incomplete
  end

  test "a stale record cannot disappear behind a matching record in the same report" do
    report = document(%{"release_id" => "old"}) <> "\n\n" <> document()
    result = verify(report, fn _, _ -> {:ok, receipt()} end)
    assert result.status == :incomplete
    assert result.counts.unverifiable_replays == 1
    assert result.counts.verified_replays == 1
    assert Enum.map(result.replays, & &1.status) == [:unverifiable, :verified]
  end

  test "input refusal keeps identities absent and never stamps or executes" do
    result =
      verify(
        String.duplicate("x", EvidenceInput.max_bytes() + 1),
        fn _, _ -> flunk("oversized input") end
      )

    assert result.status == :incomplete
    assert result.checked_identity == %{bake_id: nil, release_id: nil}
    assert Release.current_id() == nil
  end
end
