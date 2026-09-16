defmodule Pramana.Report.ForeignEvidenceTest do
  use ExUnit.Case, async: true

  alias Pramana.Report.ForeignEvidence

  test "unexpected rewrite bytes fail closed as unchecked evidence" do
    foreign = [
      %{
        matched: "T. 262, 6a23",
        urn: "pramana:cbeta.T:T0262_001@p0006a23",
        source_offset: 0,
        source_length: byte_size("T. 262, 6a23")
      }
    ]

    assert %{unchecked: 1, unresolved: 0, literal: 0} =
             ForeignEvidence.counts(foreign, "unexpected bytes", [])
  end

  test "an unresolved preserved token covered by a Guard quote is literal content" do
    matched = "T. 262, 99a1"
    quote_start = byte_size("「")

    foreign = [
      %{
        matched: matched,
        urn: nil,
        source_offset: quote_start,
        source_length: byte_size(matched)
      }
    ]

    findings = [
      %{
        occurrence: %{
          quote_range: %{
            byte_start: quote_start,
            byte_end: quote_start + byte_size(matched)
          }
        }
      }
    ]

    assert %{unchecked: 0, unresolved: 0, literal: 1} =
             ForeignEvidence.counts(foreign, "「#{matched}」", findings)
  end
end
