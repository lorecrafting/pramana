defmodule Pramana.EvidenceInputTest do
  @moduledoc "Resource refusals are explicit; region and edit offsets refer to untouched input bytes."
  use ExUnit.Case, async: true

  alias Pramana.EvidenceInput
  alias Pramana.Guard
  alias Pramana.Repair
  alias Pramana.Report

  test "the shared input budget refuses without querying or executing a partial report" do
    limit = EvidenceInput.max_bytes()
    assert :ok = EvidenceInput.check(String.duplicate("x", limit))
    original = String.duplicate("x", limit + 1)
    result = Report.verify(original, executor: fn _, _ -> flunk("must not execute") end)
    assert result.status == :incomplete
    refute result.ok?
    assert result.refusal.code == :input_too_large
    assert result.citations.checked == 0
    assert result.replays == []

    assert %{text: ^original, repaired?: false, edits: [], refusal: %{code: :input_too_large}} =
             Repair.repair(original)
  end

  test "invalid UTF-8 and misordered or splitting regions are rejected" do
    assert {:error, %{code: :invalid_utf8}} = EvidenceInput.check(<<255>>)

    assert_raise ArgumentError, fn ->
      EvidenceInput.regions("漢", regions: [%{byte_start: 1, byte_end: 3}])
    end

    assert_raise ArgumentError, fn ->
      EvidenceInput.regions("abc",
        regions: [%{byte_start: 2, byte_end: 3}, %{byte_start: 0, byte_end: 1}]
      )
    end
  end

  test "occurrence ranges do not borrow wrappers or quotes from another region" do
    urn = "pramana:cbeta.T:T0262_001@p0001a01"
    prefix = "「漢 e\u0301」 [\nprotected\n"
    text = prefix <> urn <> "]"

    [found] =
      Guard.occurrences(text,
        regions: [%{byte_start: byte_size(prefix), byte_end: byte_size(text)}]
      )

    assert found.quoted == nil
    assert found.unpaired_wrapper?
    assert found.citation_range == found.urn_range
    assert found.urn_range.byte_start == byte_size(prefix)
  end

  test "4000 ordinary wrappers retain exact ranges in a bounded document" do
    token = "[pramana:cbeta.T:T0262_001@p0001a01] "
    occurrences = Guard.occurrences(String.duplicate(token, 4_000))
    assert length(occurrences) == 4_000

    assert List.last(occurrences).citation_range == %{
             byte_start: 3_999 * byte_size(token),
             byte_end: 4_000 * byte_size(token) - 1
           }
  end

  test "different-length edits assemble once from original byte coordinates" do
    original = "漢ABCDE🙂"

    edits = [
      %{range: %{byte_start: 6, byte_end: 8}, before: "DE", after: ""},
      %{range: %{byte_start: 3, byte_end: 4}, before: "A", after: "longer"}
    ]

    assert EvidenceInput.apply_edits(original, edits) == "漢longerBC🙂"

    assert_raise ArgumentError, fn ->
      EvidenceInput.apply_edits(original, [%{hd(edits) | before: "wrong"}])
    end

    assert_raise ArgumentError, fn ->
      EvidenceInput.apply_edits(original, edits ++ [hd(edits)])
    end
  end
end
