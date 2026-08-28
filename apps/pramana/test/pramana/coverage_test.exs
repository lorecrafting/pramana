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

  alias Pramana.Cbeta.Collections
  alias Pramana.Corpus.Loader
  alias Pramana.Coverage
  alias Pramana.Normalize.CBETA
  alias Pramana.Repo

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

    # The caveat said "an absence of Japanese-composed results means the material is not in
    # this bake", which was true while the Taishō was the only collection held and became
    # wrong when CBETA X arrived with 145 Japanese-composed works. A caveat that overstates
    # a gap is the same defect as one that understates it.
    test "says how many Japanese-composed works ARE held, rather than implying none" do
      load!("T0262", 9, "0262")

      assert Coverage.caveat() =~ "holds NO Japanese-composed work at all"

      {:ok, ir} =
        CBETA.normalize(
          """
          <TEI xmlns="http://www.tei-c.org/ns/1.0" xmlns:cb="http://www.cbeta.org/ns/1.0">
          <teiHeader><fileDesc><titleStmt><title level="m">日本撰述</title></titleStmt></fileDesc></teiHeader>
          <text><body><milestone n="1" unit="juan"/><lb n="0001a01" ed="X"/>文字</body></text></TEI>
          """,
          work_id: "X0967",
          canon: "X",
          volume: 57,
          number: "0967"
        )

      {:ok, _} =
        Loader.load(ir,
          source: "cbeta",
          witness: "X",
          provenance: %{composition_origin: "japanese", text_role: "commentary"}
        )

      caveat = Coverage.caveat()

      assert caveat =~ "does hold 1 Japanese-composed work"
      assert caveat =~ "partially present, not absent"
      # And it still says what is missing — the point was never to stop warning.
      assert caveat =~ "Taishō volumes 56–84"
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

    test "stops warning about the Taishō, because there is nothing left to warn about" do
      # A warning that never turns off is one nobody reads. This asserted a nil caveat
      # until the CBETA collections gap became reportable: a bake holding all 85 Taishō
      # volumes still holds 1 of 26 collections, and that IS something to warn about. The
      # assertion narrowed to the claim it was actually making.
      caveat = Coverage.caveat()

      refute caveat =~ "Taishō volumes 56–84"
      assert caveat =~ "CBETA publishes 26 collections"
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

  describe "missing divisions" do
    test "names the absent work-number ranges, not only the volumes" do
      # "volumes 56-84" requires a reader to already know which volumes those are.
      # T2185-T2731 is the thing they can act on, and the division table settles it
      # without a catalogue of texts we do not hold.
      divisions = Coverage.taisho().missing_divisions

      assert Enum.any?(divisions, &(&1.work_numbers == "T2185\u2013T2700"))
      assert Enum.any?(divisions, &(&1.work_numbers == "T2701\u2013T2731"))
    end

    test "classifies them, because origin is what makes the gap matter" do
      # An absence of JAPANESE-composed material is the specific thing a reader must not
      # mistake for the tradition being silent, so the classification travels with the
      # range. Asserted on the two Japanese divisions by name rather than over the whole
      # list: in an EMPTY test corpus every division is missing, which is correct
      # behaviour and would make a blanket assertion pass for the wrong reason.
      japanese =
        Coverage.taisho().missing_divisions
        |> Enum.filter(&(&1.work_numbers in ["T2185\u2013T2700", "T2701\u2013T2731"]))

      assert length(japanese) == 2
      assert Enum.all?(japanese, &(&1.composition_origin == "japanese"))
      assert Enum.sum(Enum.map(japanese, & &1.work_number_count)) == 547
    end

    test "a division whose volumes are all present is not reported missing" do
      # Seed a text in volume 1 and the Āgama division stops being missing, while the
      # Japanese ones stay — the report is computed, not asserted.
      load!("T0001", 1, "0001")
      load!("T0150", 2, "0150")

      divisions = Coverage.taisho().missing_divisions

      refute Enum.any?(divisions, &(&1.volumes == "1-2"))
      assert Enum.any?(divisions, &(&1.work_numbers == "T2185\u2013T2700"))
    end

    # THE NARROWER TRUE STATEMENT MUST NOT REPLACE THE WIDER ONE. This test asserted the
    # Taishō 56–84 note unconditionally, and it passed on a corpus holding NO Taishō at
    # all — where "volumes 56–84 are not loaded" implies volumes 1–55 are present. So it
    # is asserted with a Taishō text loaded, which is the situation the note describes.
    test "names the work numbers a reader would search for, once a Taishō is here" do
      load!("T0001", 1, "0001")

      assert Coverage.caveat() =~ "T2185\u2013T2731"
    end

    test "an empty bake says the canon is absent, not that a delta is missing" do
      caveat = Coverage.caveat()

      assert caveat =~ "NO Chinese Buddhist canon"
      refute caveat =~ "T2185\u2013T2731"
    end
  end

  # CBETA is 26 collections, not one canon. Holding two of them and calling it "the
  # Chinese canon" is the same lie by omission as the Taishō 56–84 gap, one level up: a
  # reader searching for a 嘉興藏 text gets nothing, and nothing reads as silence.
  describe "the CBETA collections that are not here" do
    defp load_x!(work_id) do
      xml = """
      <TEI xmlns="http://www.tei-c.org/ns/1.0" xmlns:cb="http://www.cbeta.org/ns/1.0">
      <teiHeader><fileDesc><titleStmt><title level="m">測試</title></titleStmt></fileDesc></teiHeader>
      <text><body><milestone n="1" unit="juan"/><lb n="0001a01" ed="X"/>文字</body></text></TEI>
      """

      {:ok, ir} = CBETA.normalize(xml, work_id: work_id, canon: "X", volume: 8, number: "0240")
      {:ok, _} = Loader.load(ir, source: "cbeta", witness: "X", provenance: %{})
    end

    test "an empty corpus claims no collection" do
      coverage = Coverage.cbeta()

      assert coverage.collections_held == 0
      assert coverage.works_held == 0
      assert coverage.collections_published == 26
    end

    test "counts the collections actually loaded, not the ones acquired" do
      load!("T0262", 9, "0262")
      load_x!("X0240")

      coverage = Coverage.cbeta()

      assert coverage.collections_held == 2
      assert Enum.sort(coverage.held) == ["T", "X"]
      assert coverage.works_held == 3707
    end

    # NAMED, not coded. A reader who knows this canon knows it as 嘉興大藏經; being told
    # "J (287)" is missing asks them to decode an abbreviation before they can judge
    # whether the gap matters. The names come from CBETA's own canons.json.
    test "names the largest absent collections and how to get them" do
      load!("T0262", 9, "0262")

      coverage = Coverage.cbeta()

      assert coverage.note =~ "25 collections"
      assert coverage.note =~ "卍新纂大日本續藏經"
      assert coverage.note =~ "嘉興大藏經"
      assert coverage.note =~ "does NOT mean the canon is silent"
      assert coverage.note =~ "mix pramana.acquire_all"
    end

    test "every collection carries the publisher's own name, in both languages" do
      for collection <- Collections.all() do
        assert is_binary(collection.name), "#{collection.id} has no Chinese name"
        assert is_binary(collection.name_en), "#{collection.id} has no English name"
      end
    end

    # The names were withheld until they could be sourced, and sourcing them proved the
    # withholding right: `YP` reads as 永樂北藏 and is actually 演培法師全集, while 永樂北藏
    # is `P`. Guessing would have swapped a 20th-century author's collected works for a
    # 15th-century imperial canon.
    test "an unacquired collection is reported with the publisher's name, not a guess" do
      load!("T0262", 9, "0262")

      jiaxing = Enum.find(Coverage.cbeta().missing, &(&1.id == "J"))
      yen_pei = Collections.get("YP")
      yongle = Collections.get("P")

      assert jiaxing.works == 287
      assert jiaxing.name == "嘉興大藏經（新文豐版）"

      assert yen_pei.name == "演培法師全集"
      assert yongle.name == "永樂北藏"
    end

    test "the caveat carries the collections gap alongside the Taishō one" do
      load!("T0262", 9, "0262")

      caveat = Coverage.caveat()

      assert caveat =~ "Taishō volumes 56–84"
      assert caveat =~ "CBETA publishes 26 collections"
    end

    # Nothing loaded at all is a different statement from a partial corpus, and pretending
    # otherwise would put a collections warning on a bake that has not started.
    test "says nothing about collections when no CBETA text is loaded" do
      refute Coverage.caveat() =~ "CBETA publishes"
    end
  end

  describe "the Tibetan half that is not here" do
    setup do
      Repo.insert!(
        %Pramana.Corpus.Source{
          id: "derge",
          name: "Derge",
          license_spdx: "CC-PDM-1.0",
          license_class: "public-domain",
          commercial_use: true,
          redistributable: true
        },
        on_conflict: :nothing
      )

      Repo.insert!(%Pramana.Corpus.Witness{id: "D", name: "Derge"}, on_conflict: :nothing)

      for id <- ["toh1", "toh113", "toh1108"] do
        Repo.insert!(%Pramana.Corpus.Work{id: id})

        Repo.insert!(%Pramana.Corpus.Text{
          work_id: id,
          source_id: "derge",
          witness_id: "D",
          urn_prefix: "pramana:derge.D:" <> id,
          body: "",
          body_sha256: "x",
          meta: %{}
        })
      end

      :ok
    end

    test "the Kangyur is counted and the Tengyur is reported absent" do
      coverage = Coverage.tibetan()

      assert coverage.kangyur_works == 3
      assert coverage.tengyur_works == 0
      assert coverage.tengyur_missing
    end

    test "the caveat says the commentators are not silent, the corpus is incomplete" do
      # Tohoku 1109-4569 is the Indian commentarial literature. A question about what
      # Vasubandhu says returns nothing, and nothing is not an answer to that question.
      assert Coverage.caveat() =~ "Tengyur"
      assert Coverage.caveat() =~ "does NOT mean the commentators"
    end

    test "a Tengyur work stops the claim" do
      Repo.insert!(%Pramana.Corpus.Work{id: "toh4090"})

      Repo.insert!(%Pramana.Corpus.Text{
        work_id: "toh4090",
        source_id: "derge",
        witness_id: "D",
        urn_prefix: "pramana:derge.D:toh4090",
        body: "",
        body_sha256: "x",
        meta: %{}
      })

      coverage = Coverage.tibetan()

      assert coverage.tengyur_works == 1
      refute coverage.tengyur_missing
      refute Coverage.caveat() =~ "Tengyur"
    end
  end

  describe "a bake holding no CBETA at all" do
    # THE PUBLIC ARTEFACT IS EXACTLY THIS, and it is the case the caveat used to stay
    # silent about. `collections_held: 0` returned nil, on the reading that a bake with no
    # CBETA was one CBETA had nothing to say about — exactly backwards. Holding none of it
    # is the largest gap there is.
    test "says so plainly rather than reciting 26 collections", %{} do
      note = Coverage.cbeta_note_for([], Collections.all())

      assert note =~ "NO Chinese Buddhist canon"
      assert note =~ "26 CBETA collections"
      # The list-shaped sentence renders as "holds 0: ." with nothing between.
      refute note =~ "holds 0"
    end
  end

  # 407,176 parallels and 24,717 open. The reader has always reported this per work —
  # T0099, 1,958 recorded and 1,661 resolvable — which reads as 85% resolution. Corpus-wide
  # it is 6.1%, and the difference had never been published.
  describe "the parallels that cannot be opened" do
    test "an empty bake says so rather than dividing by zero" do
      assert %{recorded: 0, openable: 0, percent: +0.0, note: note} = Coverage.parallels()
      assert note =~ "No parallel data"
    end

    test "counts a parallel we cannot open rather than dropping it" do
      Repo.insert_all("text_parallels", [
        %{
          source_uid: "mn1",
          target_uid: "sag123",
          relation: "full",
          partial: false,
          source_urn: "pramana:sc.ms:mn1@1.1",
          target_urn: nil,
          source_work_id: nil,
          inserted_at: NaiveDateTime.utc_now(:second),
          updated_at: NaiveDateTime.utc_now(:second)
        }
      ])

      assert %{recorded: 1, openable: 0, percent: +0.0, note: note} = Coverage.parallels()

      # Knowing a passage has a Sanskrit parallel is worth something even unopenable.
      assert note =~ "COUNTED and not dropped"
      assert note =~ "sag"
    end
  end

  # `text_role` is a retrieval FILTER. 1,640 texts have no role — every non-Taishō CBETA
  # collection, since the role comes from the 部 division table — so a query for ["root"]
  # returns the Taishō and says nothing about the 1,553 works that were never candidates.
  describe "what a role filter cannot reach" do
    test "is nil when every text carries a role" do
      load!("T0001", 1, "0001")
      Repo.update_all(Pramana.Corpus.Work, set: [text_role: "root"])

      assert %{without_role: 0, note: nil} = Coverage.roles()
    end

    test "names the witnesses whose texts a role filter can never return" do
      load!("T0001", 1, "0001")
      Repo.update_all(Pramana.Corpus.Work, set: [text_role: nil])

      assert %{without_role: 1, by_witness: [%{witness: "T", texts: 1}], note: note} =
               Coverage.roles()

      # An empty result under a filter and an empty corpus are different facts.
      assert note =~ "cannot return them at all"
      assert note =~ "not that the canon is silent"
    end
  end
end
