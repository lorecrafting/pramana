defmodule Pramana.Taisho.DivisionsTest do
  @moduledoc """
  The division table drives provenance for the entire Chinese canon, so a wrong
  boundary mislabels a swathe of it. These tests pin the boundaries and, above all,
  pin what the table deliberately DOES NOT claim.
  """
  use ExUnit.Case, async: true

  alias Pramana.Taisho.Divisions

  describe "for_number/1" do
    test "places well-known texts in their divisions" do
      assert {:ok, %{name: "法華部"}} = Divisions.for_number(262)
      assert {:ok, %{name: "阿含部"}} = Divisions.for_number(1)
      assert {:ok, %{name: "般若部"}} = Divisions.for_number(220)
      assert {:ok, %{name: "律部"}} = Divisions.for_number(1421)
      assert {:ok, %{name: "疑似部"}} = Divisions.for_number(2883)
    end

    test "boundaries are exact on both sides" do
      assert {:ok, %{name: "阿含部"}} = Divisions.for_number(151)
      assert {:ok, %{name: "本緣部"}} = Divisions.for_number(152)
      assert {:ok, %{name: "論集部"}} = Divisions.for_number(1692)
      assert {:ok, %{name: "經疏部"}} = Divisions.for_number(1693)
      assert {:ok, %{name: "古逸部"}} = Divisions.for_number(2864)
      assert {:ok, %{name: "疑似部"}} = Divisions.for_number(2865)
    end

    test "accepts CBETA's suffixed numbers for works split across volumes" do
      # 大般若波羅蜜多經 is 600 fascicles and ships as T0220a/b/c.
      assert {:ok, %{name: "般若部"}} = Divisions.for_number("0220a")
      assert {:ok, %{name: "諸宗部"}} = Divisions.for_number("1969A")
    end

    test "reports out of range rather than guessing" do
      assert {:error, :out_of_range} = Divisions.for_number(99_999)
      assert {:error, :out_of_range} = Divisions.for_number("nonsense")
    end

    test "the table is contiguous with no gaps or overlaps" do
      pairs = Divisions.all() |> Enum.sort_by(& &1.first) |> Enum.chunk_every(2, 1, :discard)

      for [a, b] <- pairs do
        assert b.first == a.last + 1,
               "gap or overlap between #{a.name} (ends #{a.last}) and #{b.name} (starts #{b.first})"
      end
    end
  end

  describe "provenance_for_number/1 — what it claims" do
    test "Indic scripture is root, not 'translation'" do
      # composition_origin already records that it arrived via translation; text_role
      # answers what the text IS.
      assert %{composition_origin: "indic", text_role: "root", division: "法華部"} =
               Divisions.provenance_for_number(262)
    end

    test "Chinese exegesis is chinese/commentary" do
      assert %{composition_origin: "chinese", text_role: "commentary", division: "經疏部"} =
               Divisions.provenance_for_number(1720)
    end

    test "apocrypha are Chinese compositions presenting as Indian scripture" do
      assert %{composition_origin: "chinese", text_role: "apocryphon"} =
               Divisions.provenance_for_number(2883)
    end

    test "Japanese sub-commentaries are japanese/commentary" do
      assert %{composition_origin: "japanese", text_role: "commentary"} =
               Divisions.provenance_for_number(2400)
    end

    test "non-Buddhist Indian works are indic, not chinese" do
      # 外教部 holds Sāṃkhya and Vaiśeṣika texts translated into Chinese.
      assert %{composition_origin: "indic"} = Divisions.provenance_for_number(2137)
    end
  end

  describe "what it deliberately does NOT claim" do
    test "Dunhuang-recovered works get no origin — found there, composed who knows where" do
      attrs = Divisions.provenance_for_number(2800)

      assert attrs.division == "古逸部"
      refute Map.has_key?(attrs, :composition_origin)
      refute Map.has_key?(attrs, :text_role)
    end

    test "encyclopedic compilations get an origin but no role" do
      attrs = Divisions.provenance_for_number(2122)

      assert attrs.composition_origin == "chinese"
      refute Map.has_key?(attrs, :text_role)
    end

    test "an unknown number yields nothing at all rather than a default" do
      assert Divisions.provenance_for_number(99_999) == %{}
    end
  end

  describe "check_against/1" do
    test "passes when numbers sit inside their division's volumes" do
      assert {:ok, 2} = Divisions.check_against([{262, 9}, {1, 1}])
    end

    test "catches a number whose volume contradicts its division" do
      # T0262 is 法華部, volume 9. Volume 40 would mean the table is wrong.
      assert {:error, [%{number: 262, volume: 40, division: "法華部"}]} =
               Divisions.check_against([{262, 40}])
    end

    test "catches a number in no division" do
      assert {:error, [%{problem: :no_division}]} = Divisions.check_against([{99_999, 1}])
    end
  end
end
