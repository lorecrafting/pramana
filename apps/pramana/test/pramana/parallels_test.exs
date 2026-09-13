defmodule Pramana.ParallelsTest do
  @moduledoc """
  Cross-tradition parallels from curated scholarship.

  Two things carry the weight. **Anchoring**: SuttaCentral records `sa1` as
  "T ii 001a06", which is the same coordinate system our URNs use, so a mis-parse does
  not fail loudly — it produces a valid URN pointing at the wrong passage. And
  **relation strength**: `full` and `mentions` are different claims and must never be
  flattened into "related".
  """
  use Pramana.DataCase, async: true

  alias Pramana.Corpus.Segment
  alias Pramana.Corpus.Source
  alias Pramana.Corpus.Text
  alias Pramana.Corpus.TextAnchor
  alias Pramana.Corpus.Witness
  alias Pramana.Corpus.Work
  alias Pramana.Parallels
  alias Pramana.Parallels.Anchor

  describe "relations/0" do
    test "returns SuttaCentral relation types ordered by strength" do
      assert Parallels.relations() == ["full", "resembling", "sections", "mentions", "retells"]
    end
  end

  describe "Anchor.from_entry/1" do
    test "reads a plain Taishō volpage" do
      anchor =
        Anchor.from_entry(%{
          "uid" => "sa1",
          "acronym" => "SA 1",
          "alt_acronym" => "T 99.1",
          "volpage" => "T ii 001a06"
        })

      assert anchor.work_id == "T0099"
      assert anchor.volume == 2
      assert Anchor.locator(anchor) == "p0001a06"
    end

    test "pads a three-digit page to four, as the Taishō citation is written" do
      # "001a06" against our "p0001a06". Getting this wrong yields a well-formed URN
      # that resolves to nothing.
      anchor = Anchor.from_entry(%{"acronym" => "T 99", "volpage" => "T ii 001a06"})
      assert Anchor.locator(anchor) == "p0001a06"
    end

    test "pads the DIGITS of a suffixed text number, not the whole string" do
      # "150A" is already four characters, so padding it whole leaves T150A — valid,
      # and matching nothing. This silently lost 71 anchors.
      anchor = Anchor.from_entry(%{"acronym" => "T 150A", "volpage" => "T ii 875b08"})
      assert anchor.work_id == "T0150A"
    end

    test "skips the sub-text number in a volpage" do
      anchor =
        Anchor.from_entry(%{"acronym" => "T 765", "volpage" => "T xvii 765.1 0663a03"})

      assert anchor.work_id == "T0765"
      assert Anchor.locator(anchor) == "p0663a03"
    end

    test "keeps a range as a range" do
      # Narrowing it to the first line would claim less than the source states.
      anchor =
        Anchor.from_entry(%{"acronym" => "T 1442", "volpage" => "T xxiii 692b01–694a27"})

      assert Anchor.locator(anchor) == "p0692b01"
      assert Anchor.locator_end(anchor) == "p0694a27"
    end

    test "handles the en dash, which is what the source actually prints" do
      # U+2013. A byte-mode regex splits it into three class members and never matches —
      # it parsed 1 range instead of 80, silently.
      dash = Anchor.from_entry(%{"acronym" => "T 1", "volpage" => "T i 001b11–002a01"})
      hyphen = Anchor.from_entry(%{"acronym" => "T 1", "volpage" => "T i 001b11-002a01"})

      assert Anchor.locator_end(dash) == "p0002a01"
      assert Anchor.locator_end(hyphen) == "p0002a01"
    end

    test "reads Roman volume numerals" do
      for {roman, expected} <- [{"i", 1}, {"ii", 2}, {"xvii", 17}, {"xxiii", 23}, {"lxxxv", 85}] do
        anchor = Anchor.from_entry(%{"acronym" => "T 1", "volpage" => "T #{roman} 001a01"})
        assert anchor.volume == expected, "#{roman} read as #{anchor.volume}"
      end
    end

    test "returns nil for a Pāli reference rather than inventing a Taishō page" do
      assert Anchor.from_entry(%{
               "uid" => "dn1",
               "acronym" => "DN 1",
               "alt_acronym" => nil,
               "volpage" => "PTS DN 1.1"
             }) == nil
    end

    test "returns nil for a composite reference rather than guessing which half" do
      assert Anchor.from_entry(%{
               "acronym" => "EA2 1(*) + 3(*)",
               "volpage" => "T ii 875b04–c16 + 876b01–c07"
             }) == nil
    end
  end

  describe "flatten/1" do
    test "turns a relation group into directed pairs" do
      pairs = Parallels.flatten(%{"an1.1-5" => %{"full" => ["t792", "ea9.7"]}})

      assert length(pairs) == 2
      assert %{source_uid: "an1.1-5", target_uid: "t792", relation: "full"} = hd(pairs)
    end

    test "unpacks the nested `sections` form into passage-level pairs" do
      # `sections` nests a SUB-PASSAGE with its own relation types. Flattening it to
      # "an1.43 sections iti20" would lose both the precision and the real relation.
      nested = %{
        "an1.43" => %{
          "sections" => %{
            "an1.43#1.1" => %{"full" => ["iti20#2.1"], "mentions" => ["ne37#29.1"]}
          }
        }
      }

      pairs = Parallels.flatten(nested)

      found = Enum.map(pairs, &{&1.source_uid, &1.target_uid, &1.relation})

      assert {"an1.43", "iti20", "full"} in found
      assert {"an1.43", "ne37", "mentions"} in found
    end

    test "records the source's own hedge that a reference is indirect" do
      pairs = Parallels.flatten(%{"mn1" => %{"full" => ["~sa1"]}})
      assert hd(pairs).partial
    end

    test "strips the sub-passage suffix from the stored uid but keeps the text id" do
      pairs = Parallels.flatten(%{"sn1.20#28.1" => %{"full" => ["sag#sag1.1"]}})

      assert hd(pairs).source_uid == "sn1.20"
      assert hd(pairs).target_uid == "sag"
    end

    test "ignores a relation type the schema does not know" do
      # An unknown relation is not silently coerced into a known one.
      assert Parallels.flatten(%{"mn1" => %{"vibes" => ["sa1"]}}) == []
    end
  end

  describe "storage and queries" do
    setup do
      {:ok, _} =
        Parallels.store_anchors([
          %{
            uid: "sa1",
            work_id: "T0099",
            urn: "pramana:cbeta.T:T0099_001@p0001a06",
            acronym: "SA 1",
            volpage: "T ii 001a06"
          }
        ])

      {:ok, _} =
        Parallels.store([
          %{source_uid: "sa1", target_uid: "sn22.51", relation: "full", partial: false},
          %{source_uid: "sa1", target_uid: "mn10", relation: "mentions", partial: false},
          %{source_uid: "an1.1", target_uid: "sa1", relation: "resembling", partial: false}
        ])

      :ok
    end

    test "resolves the side that is in this corpus and leaves the other null" do
      # The Pāli side is real scholarship about a text we do not hold. Null is the
      # honest answer, not an error.
      parallels = Parallels.for_uid("sa1")
      by_uid = Map.new(parallels, &{&1.uid, &1})

      assert by_uid["sn22.51"].urn == nil
      assert by_uid["sn22.51"].relation == "full"
    end

    test "queries both directions, because the data records a pair only once" do
      uids = Parallels.for_uid("sa1") |> Enum.map(& &1.uid) |> Enum.sort()
      assert uids == ["an1.1", "mn10", "sn22.51"]
    end

    test "finds parallels by work id via the resolved anchor" do
      parallels = Parallels.for_work("T0099")
      assert length(parallels) == 3
    end

    test "filters by relation type" do
      assert [%{uid: "sn22.51"}] = Parallels.for_work("T0099", relations: ["full"])
    end

    test "is idempotent per (source, target, relation)" do
      {:ok, _} =
        Parallels.store([
          %{source_uid: "sa1", target_uid: "sn22.51", relation: "full", partial: false}
        ])

      assert length(Parallels.for_uid("sa1")) == 3
    end

    test "the same pair under two relation types is kept as two claims" do
      {:ok, _} =
        Parallels.store([
          %{source_uid: "sa1", target_uid: "sn22.51", relation: "resembling", partial: false}
        ])

      relations =
        Parallels.for_uid("sa1")
        |> Enum.filter(&(&1.uid == "sn22.51"))
        |> Enum.map(& &1.relation)
        |> Enum.sort()

      assert relations == ["full", "resembling"]
    end

    test "anchor/1 returns the stored TextAnchor or nil" do
      assert %TextAnchor{uid: "sa1", work_id: "T0099"} = Parallels.anchor("sa1")
      assert Parallels.anchor("nonexistent") == nil
    end

    test "stats separate what is quotable from what is merely known" do
      stats = Parallels.stats()

      assert stats.parallels == 3
      assert stats.anchors == 1
      assert stats.resolvable_one_end == 3
      assert stats.by_relation["full"] == 1

      # Add an anchor for the target to test resolvable_both_ends
      {:ok, _} =
        Parallels.store_anchors([
          %{
            uid: "sn22.51",
            work_id: "sn22.51",
            urn: "pramana:sc.ms:sn22.51@1.1",
            acronym: "SN 22.51",
            volpage: "PTS SN iii 51"
          }
        ])

      {:ok, _} =
        Parallels.store([
          %{source_uid: "sa1", target_uid: "sn22.51", relation: "full", partial: false}
        ])

      updated_stats = Parallels.stats()
      assert updated_stats.resolvable_both_ends >= 1
    end
  end

  describe "resolve_anchor/1" do
    defp setup_cbeta_segment! do
      Repo.insert!(%Work{id: "T0099", title: "雜阿含經"})
      Repo.insert!(%Witness{id: "w-cbeta-T", name: "Taisho"})

      Repo.insert!(%Source{
        id: "cbeta",
        name: "CBETA",
        license_spdx: "CC0-1.0",
        license_class: "cc0",
        commercial_use: true,
        redistributable: true
      })

      text =
        Repo.insert!(%Text{
          work_id: "T0099",
          witness_id: "w-cbeta-T",
          source_id: "cbeta",
          urn_prefix: "pramana:cbeta.T:T0099"
        })

      Repo.insert!(%Segment{
        urn: "pramana:cbeta.T:T0099_001@p0001a06",
        text_id: text.id,
        content: "如是我聞",
        content_sha256: "abc",
        char_start: 0,
        char_end: 4,
        byte_start: 0,
        byte_end: 12,
        page: "0001",
        register: "a",
        line: 6,
        ordinal: 1
      })
    end

    test "resolves SuttaCentral entry against existing text segments" do
      setup_cbeta_segment!()

      # Point anchor
      entry = %{
        "uid" => "sa1",
        "acronym" => "SA 1",
        "alt_acronym" => "T 99.1",
        "volpage" => "T ii 001a06"
      }

      assert %{
               uid: "sa1",
               work_id: "T0099",
               urn: "pramana:cbeta.T:T0099_001@p0001a06",
               acronym: "SA 1",
               volpage: "T ii 001a06"
             } = Parallels.resolve_anchor(entry)

      # Range anchor
      range_entry = %{
        "uid" => "sa1_range",
        "acronym" => "SA 1",
        "alt_acronym" => "T 99.1",
        "volpage" => "T ii 001a06-001a10"
      }

      assert %{
               uid: "sa1_range",
               work_id: "T0099",
               urn: "pramana:cbeta.T:T0099_001@p0001a06-p0001a10",
               acronym: "SA 1",
               volpage: "T ii 001a06-001a10"
             } = Parallels.resolve_anchor(range_entry)

      # Missing segment returns nil
      missing_entry = %{
        "uid" => "sa999",
        "acronym" => "SA 999",
        "alt_acronym" => "T 99.999",
        "volpage" => "T ii 999a01"
      }

      assert Parallels.resolve_anchor(missing_entry) == nil

      # Invalid entry returns nil
      assert Parallels.resolve_anchor(%{}) == nil
    end
  end
end
