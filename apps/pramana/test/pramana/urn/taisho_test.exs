defmodule Pramana.URN.TaishoTest do
  use ExUnit.Case, async: true

  alias Pramana.URN.Taisho

  describe "parse_locator/1" do
    test "decomposes page, register, and line" do
      assert {:ok, %{page: "0037", register: "a", line: 13}} = Taisho.parse_locator("p0037a13")
      assert {:ok, %{page: "0783", register: "b", line: 12}} = Taisho.parse_locator("p0783b12")
      assert {:ok, %{page: "0001", register: "c", line: 1}} = Taisho.parse_locator("p0001c01")
    end

    test "keeps the page zero-padded as a string" do
      # Round-tripping the page through an integer would rewrite "0037" as "37" and
      # silently produce a citation that does not match the printed volume.
      assert {:ok, %{page: page}} = Taisho.parse_locator("p0037a13")
      assert page == "0037"
      assert is_binary(page)
    end

    test "rejects malformed locators" do
      for bad <- ["0037a13", "p37a13", "p0037d13", "p0037a", "p0037axx", "px037a13", ""] do
        assert {:error, :bad_taisho_locator} = Taisho.parse_locator(bad),
               "expected #{inspect(bad)} to be rejected"
      end
    end
  end

  describe "format_locator/1" do
    test "round-trips" do
      for s <- ["p0037a13", "p0783b12", "p0001c01"] do
        assert {:ok, anchor} = Taisho.parse_locator(s)
        assert Taisho.format_locator(anchor) == s
      end
    end
  end

  describe "parse_work/1" do
    test "splits work id from juan" do
      assert {:ok, {"T0262", 9}} = Taisho.parse_work("T0262_009")
      assert {:ok, {"T2688", 1}} = Taisho.parse_work("T2688_001")
    end

    test "juan is optional" do
      assert {:ok, {"T0262", nil}} = Taisho.parse_work("T0262")
    end

    test "rejects a non-numeric juan" do
      assert {:error, :bad_juan} = Taisho.parse_work("T0262_abc")
    end
  end

  describe "provenance_for_volume/1 — the Taishō 56-84 rule" do
    test "vols 56-84 are mechanically Japanese-composed commentary" do
      for vol <- [56, 70, 84] do
        assert {:ok, %{composition_origin: "japanese", text_role: "commentary"}} =
                 Taisho.provenance_for_volume(vol)
      end
    end

    test "vols 1-55 and 85 are left indeterminate rather than guessed" do
      for vol <- [1, 9, 55, 85] do
        assert {:ok, %{composition_origin: nil, text_role: nil}} =
                 Taisho.provenance_for_volume(vol)
      end
    end

    test "the boundaries are exact" do
      # 55 is the last CBETA-covered volume before the Japanese block; 85 is the
      # Dunhuang/apocrypha volume that CBETA covers again.
      assert {:ok, %{composition_origin: nil}} = Taisho.provenance_for_volume(55)
      assert {:ok, %{composition_origin: "japanese"}} = Taisho.provenance_for_volume(56)
      assert {:ok, %{composition_origin: "japanese"}} = Taisho.provenance_for_volume(84)
      assert {:ok, %{composition_origin: nil}} = Taisho.provenance_for_volume(85)
    end

    test "rejects volumes outside the canon" do
      assert {:error, :volume_out_of_range} = Taisho.provenance_for_volume(0)
      assert {:error, :volume_out_of_range} = Taisho.provenance_for_volume(86)
    end
  end
end
