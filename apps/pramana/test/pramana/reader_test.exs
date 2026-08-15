defmodule Pramana.ReaderTest do
  @moduledoc """
  Reader deep-links are the one place this project emits a reference it cannot verify,
  so the tests are about *not overclaiming*: no link for a source we have no confirmed
  template for, no partial linehead, and the honesty fields always present.
  """
  use ExUnit.Case, async: true

  alias Pramana.Reader

  @urn "pramana:cbeta.T:T0262_001@p0001a05"

  defp provenance(overrides \\ %{}) do
    Map.merge(
      %{
        source: "cbeta",
        witness: "T",
        work_id: "T0262",
        volume: "9",
        juan: 1,
        page: "0001",
        register: "a",
        line: 5
      },
      overrides
    )
  end

  describe "linehead/1" do
    test "matches CBETA's own citation string" do
      # T0262 is in Taishō volume 9; the printed citation for page 1, register a,
      # line 5 is T09n0262_p0001a05. Volume is zero-padded to two digits and the
      # canon letter is dropped from the work number.
      assert Reader.linehead(provenance()) == "T09n0262_p0001a05"
    end

    test "keeps two-digit volumes intact" do
      p = provenance(%{volume: "85", work_id: "T2837"})
      assert Reader.linehead(p) =~ "T85n2837_"
    end

    test "pads single-digit line numbers, as the printed citation does" do
      assert Reader.linehead(provenance(%{line: 3})) == "T09n0262_p0001a03"
      assert Reader.linehead(provenance(%{line: 17})) == "T09n0262_p0001a17"
    end

    test "returns nil rather than a partial citation when a component is missing" do
      # Half a citation is not a citation — it would look checkable and not be.
      for missing <- [:volume, :page, :register, :line, :work_id, :witness] do
        assert Reader.linehead(Map.delete(provenance(), missing)) == nil,
               "expected nil when #{missing} is absent"
      end
    end

    test "returns nil when the work id carries no number" do
      assert Reader.linehead(provenance(%{work_id: "T"})) == nil
    end
  end

  describe "reference/3" do
    test "links to the fascicle, taking the path segment from the URN verbatim" do
      ref = Reader.reference(@urn, provenance())

      assert ref.url == "https://cbetaonline.dila.edu.tw/en/T0262_001"
      assert ref.edition == "CBETA Online"
      assert ref.granularity == "juan"
      assert ref.linehead == "T09n0262_p0001a05"
    end

    test "never claims the link is verified" do
      # Both readers are SPAs that return 200 with an identical body for a real path
      # and for nonsense, so a link check is impossible, not merely skipped.
      ref = Reader.reference(@urn, provenance())

      assert ref.verified == false
      assert ref.note =~ "not verified"
      # The link must not be mistaken for the citation.
      assert ref.note =~ "URN is the citation"
    end

    test "says the link lands on the fascicle, not the cited line" do
      ref = Reader.reference(@urn, provenance())
      assert ref.note =~ "not the line"
    end

    test "honours the reader's UI language" do
      assert Reader.reference(@urn, provenance(), lang: "zh").url =~ "/zh/"
      assert Reader.reference(@urn, provenance(), lang: "klingon").url =~ "/en/"
    end

    test "returns nil for a source with no confirmed template" do
      # SAT arrives in Phase 2 (task #14) with a format checked against real ingested
      # identifiers. A plausible-looking link to the wrong passage is worse than none,
      # because nothing about it looks wrong.
      assert Reader.reference("pramana:sat.T:T2688_001@p0783b12", provenance(%{source: "sat"})) ==
               nil

      assert Reader.reference(
               "pramana:local.huang-nianzu-wlsj:jie@sec12.p3",
               provenance(%{source: "local"})
             ) == nil
    end

    test "returns nil for a malformed URN rather than building a link around junk" do
      assert Reader.reference("not-a-urn", provenance()) == nil
    end

    test "still returns a link when the line components are missing" do
      # The fascicle URL only needs the URN's work component, so a range URN or a
      # source without page/line data should keep its link and simply lose `linehead`.
      ref = Reader.reference(@urn, Map.delete(provenance(), :page))

      assert ref.url == "https://cbetaonline.dila.edu.tw/en/T0262_001"
      assert ref.linehead == nil
    end
  end
end
