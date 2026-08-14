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
    # split_range/1 treats "-" as the range separator. That is only safe while no
    # source's locator grammar uses hyphens internally. If this test ever needs
    # changing, Pramana.URN.split_range/1 needs a per-namespace dispatch first.
    test "no in-use locator grammar contains an internal hyphen" do
      for locator <- ["p0037a13", "F.1.b.1", "1.1", "sec12.p3", "p0783b12"] do
        refute String.contains?(locator, "-"),
               "#{locator} contains a hyphen; URN range splitting is now ambiguous"
      end
    end
  end

  describe "namespace/1" do
    test "returns source.witness for grammar dispatch" do
      assert {:ok, urn} = URN.parse("pramana:cbeta.T:T0262_009@p0037a13")
      assert URN.namespace(urn) == "cbeta.T"
    end
  end
end
