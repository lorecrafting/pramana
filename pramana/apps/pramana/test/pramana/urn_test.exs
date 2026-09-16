defmodule Pramana.URNTest do
  use ExUnit.Case, async: true

  alias Pramana.URN

  describe "parse/1" do
    test "parses a Taishō URN with a range locator" do
      assert {:ok, urn} = URN.parse("pramana:cbeta.T:T0262_009@p0037a13-p0037b02")
      assert urn.source == "cbeta"
      assert urn.witness == "T"
      assert urn.work == "T0262_009"
      assert urn.locator == "p0037a13"
      assert urn.locator_end == "p0037b02"
      assert URN.range?(urn)
    end

    test "parses a single-anchor Taishō URN" do
      assert {:ok, urn} = URN.parse("pramana:sat.T:T2688_001@p0783b12")
      assert urn.source == "sat"
      assert urn.locator_end == nil
      refute URN.range?(urn)
    end

    test "parses a SuttaCentral URN preserving their native segment id" do
      assert {:ok, urn} = URN.parse("pramana:sc.pali:mn1@1.1")
      assert urn.work == "mn1"
      assert urn.locator == "1.1"
    end

    test "parses a Derge folio URN" do
      assert {:ok, urn} = URN.parse("pramana:84000.kangyur:toh113@F.1.b.1")
      assert urn.work == "toh113"
      assert urn.locator == "F.1.b.1"
    end

    test "parses a locally-added source whose namespace contains hyphens" do
      assert {:ok, urn} = URN.parse("pramana:local.huang-nianzu-wlsj:jie@sec12.p3")
      assert urn.source == "local"
      assert urn.witness == "huang-nianzu-wlsj"
      assert urn.work == "jie"
      assert urn.locator == "sec12.p3"
    end

    test "parses a work-only URN with no locator" do
      assert {:ok, urn} = URN.parse("pramana:cbeta.T:T0262")
      assert urn.locator == nil
    end

    test "rejects malformed input without raising" do
      for bad <- [
            "dharma:cbeta.T:T0262@p1",
            "pramana:cbetaT:T0262",
            "pramana:cbeta.T",
            "pramana:.T:T0262@p1",
            "pramana:cbeta.:T0262@p1",
            "pramana:cbeta.T:@p1",
            "",
            "nonsense"
          ] do
        assert {:error, _} = URN.parse(bad), "expected #{inspect(bad)} to be rejected"
      end
    end

    test "rejects non-string input" do
      assert {:error, :not_a_string} = URN.parse(nil)
      assert {:error, :not_a_string} = URN.parse(123)
    end
  end

  describe "to_string/1" do
    test "round-trips every supported shape" do
      for s <- [
            "pramana:cbeta.T:T0262_009@p0037a13-p0037b02",
            "pramana:sat.T:T2688_001@p0783b12",
            "pramana:sc.pali:mn1@1.1",
            "pramana:84000.kangyur:toh113@F.1.b.1",
            "pramana:local.huang-nianzu-wlsj:jie@sec12.p3",
            "pramana:cbeta.T:T0262"
          ] do
        assert {:ok, urn} = URN.parse(s)
        assert URN.to_string(urn) == s, "round-trip failed for #{s}"
      end
    end
  end

  describe "locator grammars and the hyphen assumption" do
    # This test used to assert that no locator grammar contained a hyphen, which made
    # range splitting unambiguous. **That assumption was already false when it was
    # written**: SuttaCentral numbers a merged section `53-55.1`, and 749 Pāli segments
    # are addressed that way. The test passed because its list of grammars was written by
    # hand and did not include one.
    test "most grammars have no internal hyphen, and one does" do
      for locator <- ["p0037a13", "F.1.b.1", "1.1", "sec12.p3", "p0783b12"] do
        refute String.contains?(locator, "-")
      end

      assert String.contains?("53-55.1", "-")
    end

    test "a range is built from the locator text, not from parsed halves" do
      # Parsing first and rejoining produced `mn12@53-53`: `53-55.1` reads as a range from
      # `53` to `55.1`, so both endpoints collapsed to `53`. 412 chunks were addressed
      # that way, none of them resolved, and two in one insert violated a unique index.
      assert URN.range("pramana:sc.ms:mn12@53-55.1", "pramana:sc.ms:mn12@53-55.9") ==
               "pramana:sc.ms:mn12@53-55.1-53-55.9"
    end

    test "an unambiguous grammar is unaffected" do
      assert URN.range("pramana:derge.D:toh113@51.1b.1", "pramana:derge.D:toh113@51.1b.7") ==
               "pramana:derge.D:toh113@51.1b.1-51.1b.7"
    end

    test "every division of an ambiguous range is offered, so a resolver can try them" do
      assert URN.splits("53-55.1-53-55.9") == [
               {"53", "55.1-53-55.9"},
               {"53-55.1", "53-55.9"},
               {"53-55.1-53", "55.9"}
             ]
    end

    test "a locator with no hyphen has no division to try" do
      assert URN.splits("1.1") == []
    end
  end

  describe "namespace/1" do
    test "returns source.witness for grammar dispatch" do
      assert {:ok, urn} = URN.parse("pramana:cbeta.T:T0262_009@p0037a13")
      assert URN.namespace(urn) == "cbeta.T"
    end
  end

  describe "addresses?/2" do
    # THE BUG. A CBETA text is `T0099`; its lines are addressed `T0099_015@p0103c13`,
    # with the juan between the two. `Pramana.Chunk.Vectors` tested for the prefix
    # followed immediately by `@`, so every range-anchored English rendering of the
    # Chinese canon was excluded from being embedded — silently, with the count of
    # vectors built the only sign anything had happened.
    test "a CBETA line is inside its work even though the juan comes first" do
      assert URN.addresses?("pramana:cbeta.T:T0099_015@p0103c13", "pramana:cbeta.T:T0099")

      assert URN.addresses?(
               "pramana:cbeta.T:T0099_015@p0103c13-p0103c14",
               "pramana:cbeta.T:T0099"
             )
    end

    # And the reason a bare `String.starts_with?/2` is not the fix.
    test "one sutta is not inside another whose id is a prefix of it" do
      refute URN.addresses?("pramana:sc.ms:mn10@1.1", "pramana:sc.ms:mn1")
      assert URN.addresses?("pramana:sc.ms:mn1@1.1", "pramana:sc.ms:mn1")
    end

    test "a Derge line is inside its work" do
      assert URN.addresses?("pramana:derge.D:toh113@51.1b.1", "pramana:derge.D:toh113")
      refute URN.addresses?("pramana:derge.D:toh1130@51.1b.1", "pramana:derge.D:toh113")
    end
  end
end
