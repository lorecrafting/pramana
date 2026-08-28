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

    # THE DEFECT NINE COLLECTIONS EXPOSED. The volume was padded to two digits for every
    # canon, which is right for T, X and J and wrong for A, P, L and U. `A91n1057_p0311b01`
    # looks exactly like a citation and CBETA's reader cannot find it. Each expectation
    # below is CBETA's own output, from the `id` attribute on the line in the juan its
    # website renders (`cbdata.dila.edu.tw/stable/juans`, fetched 2026-08-27).
    test "pads to the width the EDITION uses, which is not the same for every collection" do
      cases = [
        {"A", "A1057", 91, "0311", "b", 1, "A091n1057_p0311b01"},
        {"P", "P1519", 154, "0463", "a", 1, "P154n1519_p0463a01"},
        {"L", "L1557", 130, "0003", "a", 1, "L130n1557_p0003a01"},
        {"U", "U1368", 205, "0231", "b", 1, "U205n1368_p0231b01"},
        {"X", "X0488", 25, "0282", "a", 2, "X25n0488_p0282a02"},
        {"K", "K1402", 38, "0512", "a", 1, "K38n1402_p0512a01"},
        {"M", "M1540", 59, "0789", "b", 1, "M59n1540_p0789b01"}
      ]

      for {witness, work_id, volume, page, register, line, expected} <- cases do
        actual =
          Reader.linehead(%{
            witness: witness,
            work_id: work_id,
            volume: Integer.to_string(volume),
            page: page,
            register: register,
            line: line
          })

        assert actual == expected, "#{work_id}: expected #{expected}, got #{inspect(actual)}"
      end
    end

    # J numbers carry a letter of their own: work JB271 is CBETA's J31nB271. Stripping the
    # canon prefix rather than every non-digit is what keeps the B.
    test "keeps a letter that belongs to the work number" do
      p = provenance(%{witness: "J", work_id: "JB271", volume: "31", page: "0771", line: 1})
      assert Reader.linehead(p) == "J31nB271_p0771a01"
    end

    # A volume RANGE is what a volume-spanning work records on its text row, and it is a
    # description of the work rather than a coordinate. Emitting `130-133n1557_p0003a01`
    # is inventing a citation ID, which invariant #2 forbids outright.
    test "refuses to build a citation from a volume range" do
      p = provenance(%{witness: "L", work_id: "L1557", volume: "130-133"})
      assert Reader.linehead(p) == nil
    end

    # We hold none of these, so there is no page to check a guess against. `canons.json`
    # names them; nothing names their volume width.
    test "returns nil for a collection whose width has never been checked" do
      p = provenance(%{witness: "N", work_id: "N0001", volume: "1"})
      assert Reader.linehead(p) == nil
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
