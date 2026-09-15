defmodule Pramana.InventoryTest do
  @moduledoc """
  The inventory exists to separate two answers that look identical from an empty result
  set: "the canon does not say that" and "that part of the canon is not loaded yet."
  These tests pin that it reports what is actually there, including the absences.
  """
  use Pramana.DataCase, async: true

  alias Pramana.Corpus.Loader
  alias Pramana.Inventory
  alias Pramana.Normalize.CBETA

  defp load!(work_id, volume, number, provenance) do
    xml = """
    <TEI xmlns="http://www.tei-c.org/ns/1.0" xmlns:cb="http://www.cbeta.org/ns/1.0">
    <teiHeader><fileDesc><titleStmt>
      <title level="m" xml:lang="zh-Hant">測試經</title>
    </titleStmt></fileDesc></teiHeader>
    <text><body>
    <milestone n="1" unit="juan"/>
    <lb n="0001a01"/>文字
    </body></text></TEI>
    """

    {:ok, ir} = CBETA.normalize(xml, work_id: work_id, canon: "T", volume: volume, number: number)
    {:ok, _} = Loader.load(ir, source: "cbeta", witness: "T", provenance: provenance)
  end

  describe "an empty corpus" do
    test "reports empty breakdowns rather than failing" do
      # This is exactly when a caller most needs the inventory — a fresh or partial
      # bake — so it must render before there is data.
      snapshot = Inventory.snapshot()

      assert snapshot.by_composition_origin == %{}
      assert snapshot.by_text_role == %{}
      assert snapshot.divisions == []
    end

    test "still carries the note explaining what absence means" do
      assert Inventory.snapshot().note =~ "not loaded"
    end
  end

  describe "with works loaded" do
    setup do
      load!("T0374", 12, "0374", %{
        composition_origin: "indic",
        text_role: "root",
        division: "涅槃部",
        division_en: "Nirvāṇa"
      })

      load!("T1767", 38, "1767", %{
        composition_origin: "chinese",
        text_role: "commentary",
        division: "經疏部",
        division_en: "Sūtra commentary"
      })

      :ok
    end

    test "counts works along each provenance axis" do
      snapshot = Inventory.snapshot()

      assert snapshot.by_composition_origin == %{"indic" => 1, "chinese" => 1}
      assert snapshot.by_text_role == %{"root" => 1, "commentary" => 1}
    end

    test "lists divisions with their English names" do
      divisions = Map.new(Inventory.divisions(), &{&1.division, &1})

      assert divisions["涅槃部"].works == 1
      assert divisions["經疏部"].division_en == "Sūtra commentary"
    end

    test "reports a null axis as unattributed rather than dropping the work" do
      # 古逸部 material recovered at Dunhuang records where a text was FOUND, not where
      # it was composed. Null is a considered answer; hiding it would overstate what
      # the corpus knows and lose the work from the totals.
      load!("T2865", 85, "2865", %{composition_origin: nil, text_role: nil})

      snapshot = Inventory.snapshot()

      assert snapshot.by_composition_origin["unattributed"] == 1
      assert snapshot.by_text_role["unattributed"] == 1
      assert Enum.sum(Map.values(snapshot.by_composition_origin)) == 3
    end

    test "a work with no division is absent from divisions but present in the totals" do
      load!("T9001", 85, "9001", %{composition_origin: "chinese", text_role: "root"})

      snapshot = Inventory.snapshot()

      refute Enum.any?(snapshot.divisions, &is_nil(&1.division))
      assert snapshot.by_composition_origin["chinese"] == 2
    end

    test "carries bake identity and embedding coverage" do
      snapshot = Inventory.snapshot()

      assert Map.has_key?(snapshot, :bake_id)
      assert snapshot.pipeline_version == Pramana.Bake.pipeline_version()
      assert %{total: _, embedded: _, percent: _} = snapshot.embedding_coverage
    end
  end
end
