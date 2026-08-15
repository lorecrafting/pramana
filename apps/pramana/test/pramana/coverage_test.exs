defmodule Pramana.CoverageTest do
  @moduledoc """
  The corpus has to be able to say what it does not contain.

  The concrete failure this prevents, measured on the real bake: surveying 即身成佛
  (sokushin jōbutsu — *the* Shingon doctrine, Kūkai's 即身成佛義, Taishō vol. 77) returns
  11 segments, all Indic or Chinese and **none Japanese**, because vol. 77 is not
  loaded. A model reading that concludes the doctrine is Indic-Chinese and that Japanese
  Buddhism is silent on its own central teaching — the exact inverse of the
  mislabelling this project was built to prevent.
  """
  use Pramana.DataCase, async: true

  alias Pramana.Corpus.Loader
  alias Pramana.Coverage
  alias Pramana.Normalize.CBETA

  defp load!(work_id, volume, number) do
    xml = """
    <TEI xmlns="http://www.tei-c.org/ns/1.0" xmlns:cb="http://www.cbeta.org/ns/1.0">
    <teiHeader><fileDesc><titleStmt><title level="m">測試</title></titleStmt></fileDesc></teiHeader>
    <text><body><milestone n="1" unit="juan"/><lb n="0001a01"/>文字</body></text></TEI>
    """

    {:ok, ir} = CBETA.normalize(xml, work_id: work_id, canon: "T", volume: volume, number: number)
    {:ok, _} = Loader.load(ir, source: "cbeta", witness: "T", provenance: %{})
  end

  describe "an empty corpus" do
    test "reports every volume missing rather than claiming completeness" do
      coverage = Coverage.taisho()

      assert coverage.present == 0
      assert coverage.expected == 85
      assert length(coverage.missing) == 85
      assert coverage.japanese_delta_missing
    end
  end

  describe "the Taishō 56–84 gap" do
    setup do
      # Volumes either side of the delta, so the gap is a genuine hole rather than a
      # truncation at the end of the range.
      load!("T0001", 1, "0001")
      load!("T1911", 46, "1911")
      load!("T2865", 85, "2865")
      :ok
    end

    test "identifies the missing volumes exactly" do
      coverage = Coverage.taisho()

      assert coverage.present == 3
      assert 56 in coverage.missing
      assert 84 in coverage.missing
      refute 46 in coverage.missing
      refute 85 in coverage.missing
    end

    test "collapses contiguous runs into ranges, not bare integers" do
      # Only 1, 46 and 85 are loaded here, so the holes either side of the delta are
      # real and must both be reported.
      assert Coverage.taisho().missing_ranges == "2–45, 47–84"
    end

    test "warns that absence of Japanese results is not silence" do
      caveat = Coverage.caveat()

      assert caveat =~ "56–84"
      assert caveat =~ "NOT loaded"
      # The distinction is the entire point, so it must be stated, not implied.
      assert caveat =~ "does NOT mean the tradition is silent"
    end

    test "names the schools, so the gap is recognisable to someone who knows the canon" do
      caveat = Coverage.caveat()

      for school <- ~w(Shingon Tendai Nichiren Zen) do
        assert caveat =~ school
      end
    end
  end

  describe "the real CBETA shape — volumes 1–55 and 85" do
    setup do
      for v <- Enum.to_list(1..55) ++ [85], do: load!("T#{v}", v, Integer.to_string(v))
      :ok
    end

    test "reports the gap as exactly 56–84" do
      # This is the production case: the 56 volumes CBETA ships, and the 29 it does not.
      coverage = Coverage.taisho()

      assert coverage.present == 56
      assert coverage.missing_ranges == "56–84"
      assert length(coverage.missing) == 29
      assert coverage.japanese_delta_missing
    end
  end

  describe "when the delta is present" do
    setup do
      for v <- 1..85, do: load!("T#{v}", v, Integer.to_string(v))
      :ok
    end

    test "reports full coverage" do
      coverage = Coverage.taisho()

      assert coverage.present == 85
      assert coverage.missing == []
      refute coverage.japanese_delta_missing
      assert coverage.note =~ "All 85"
    end

    test "issues no caveat, because there is nothing to warn about" do
      # A warning that never turns off is one nobody reads.
      assert Coverage.caveat() == nil
    end
  end

  describe "a gap outside the Japanese delta" do
    setup do
      for v <- [1, 2, 5] ++ Enum.to_list(56..84), do: load!("T#{v}", v, Integer.to_string(v))
      :ok
    end

    test "is reported as ranges without the Japanese warning" do
      coverage = Coverage.taisho()

      refute coverage.japanese_delta_missing
      assert coverage.note =~ "Missing Taishō volumes"
      assert coverage.note =~ "3–4"
      refute coverage.note =~ "Shingon"
    end
  end
end
