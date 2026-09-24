defmodule Pramana.CitationTest do
  @moduledoc """
  Reading citations written in somebody else's scheme.

  The failure this closes is not inconvenience. `Pramana.Guard` scans for `pramana:` URNs,
  so a report citing the Taishō the way every article cites it contained **no citations at
  all** — the guard reported zero checked and `/check` rendered that as a document with
  nothing wrong with it. An absence of findings and a clean bill of health looked the same.

  So the tests are about two things: that ordinary scholarly forms are found, and that
  nothing is *invented* when they cannot be placed.
  """
  use Pramana.DataCase, async: false

  alias Pramana.Citation
  alias Pramana.Corpus.Loader
  alias Pramana.Normalize.CBETA

  @xml """
  <TEI xmlns="http://www.tei-c.org/ns/1.0" xmlns:cb="http://www.cbeta.org/ns/1.0">
  <teiHeader><fileDesc><titleStmt>
    <title level="m" xml:lang="zh-Hant">妙法蓮華經</title><author>姚秦 鳩摩羅什譯</author>
  </titleStmt></fileDesc></teiHeader>
  <text><body>
  <milestone n="1" unit="juan"/>
  <lb n="0006a21"/>第一行
  <lb n="0006a22"/>第二行
  <lb n="0006a23"/>如是我聞一時佛住
  </body></text></TEI>
  """

  setup do
    {:ok, ir} = CBETA.normalize(@xml, work_id: "T0262", canon: "T", volume: 9, number: "0262")

    {:ok, _} =
      Loader.load(ir,
        source: "cbeta",
        witness: "T",
        provenance: %{composition_origin: "indic", text_role: "root"}
      )

    :ok
  end

  describe "the Taishō as an article prints it" do
    test "T. 262, 6a23 resolves to the line it names" do
      assert [%{scheme: :taisho, urn: urn, reason: nil}] = Citation.scan("see T. 262, 6a23 here")
      assert urn == "pramana:cbeta.T:T0262_001@p0006a23"
    end

    test "the separators vary and none of them is the citation" do
      for form <- ["T262 6a23", "T.262:6a23", "T 262, 6a23", "T. 262. 6a23"] do
        assert [%{urn: "pramana:cbeta.T:T0262_001@p0006a23"}] = Citation.scan(form),
               "failed on #{form}"
      end
    end

    test "SAT's own fully-specified form" do
      assert [%{urn: "pramana:cbeta.T:T0262_001@p0006a23"}] =
               Citation.scan("T0262_.09.0006a23")
    end

    # From the foot of the register, verified against the text in `Glossary.Anchors`.
    # This fixture's page 6 register a ends at line 23, so `-1` is 23.
    test "a minus sign counts from the foot" do
      assert [%{urn: "pramana:cbeta.T:T0262_001@p0006a23"}] = Citation.scan("T. 262, 6a-1")
      assert [%{urn: "pramana:cbeta.T:T0262_001@p0006a22"}] = Citation.scan("T. 262, 6a-2")
    end

    # THE POINT. Not resolving is a finding; inventing a URN is a fabrication.
    test "a line this bake does not hold is reported, never invented" do
      assert [%{urn: nil, reason: {:no_such_line, "T0262", "0099", "a", 1}}] =
               Citation.scan("T. 262, 99a1")
    end
  end

  describe "SuttaCentral segment ids" do
    test "an id naming a segment we do not hold does not become a URN" do
      assert [%{scheme: :suttacentral, urn: nil}] = Citation.scan("as mn1:1.1 says")
    end

    # THE AMBIGUITY GUARD. No regex separates a segment id from a chapter-and-verse
    # reference, so the corpus does. A checker that invents findings is worse than one
    # that misses them.
    test "prose that merely looks like a segment id is not claimed" do
      assert Enum.all?(Citation.scan("Matthew 3:16 and Genesis 1:1"), &is_nil(&1.urn))
    end
  end

  describe "rewrite/1" do
    test "replaces what resolved and leaves the rest exactly as written" do
      {text, found} = Citation.rewrite("Compare T. 262, 6a23 with T. 262, 99a1.")

      assert text =~ "pramana:cbeta.T:T0262_001@p0006a23"
      # Unresolvable, and left alone: rewriting it to something that does not resolve
      # would turn a citation nobody could place into one that looks fabricated.
      assert text =~ "T. 262, 99a1"
      assert length(found) == 2
    end

    test "text with no foreign citation comes back untouched" do
      original = "A passage at pramana:cbeta.T:T0262_001@p0006a23 says something."

      assert {^original, []} = Citation.rewrite(original)
    end
  end

  describe "complete coordinates and ambiguity" do
    test "a supplied wrong volume cannot resolve through the matching work and page" do
      assert [%{urn: nil, reason: {:no_such_line_in_volume, "T0262", 10, "0006", "a", 23}}] =
               Citation.scan("T0262_.10.0006a23")

      assert [%{urn: "pramana:cbeta.T:T0262_001@p0006a23"}] =
               Citation.scan("T0262_.09.0006a23")
    end

    test "volume omission stays supported without manufacturing a coordinate" do
      assert [%{urn: "pramana:cbeta.T:T0262_001@p0006a23"}] =
               Citation.scan("T0262.0006a23")

      assert [%{urn: nil, reason: :invalid_volume}] = Citation.scan("T0262_.00.0006a23")
    end

    test "two printed locations with the same short address are ambiguous" do
      load_repeated_page!()

      assert [%{urn: nil, reason: {:ambiguous_address, "T0262", "0006", "a", 23}}] =
               Citation.scan("T. 262, 6a23")

      assert [%{urn: nil, reason: {:ambiguous_register, "T0262", "0006", "a"}}] =
               Citation.scan("T. 262, 6a-1")
    end

    test "per-segment volume disambiguates a text spanning printed volumes" do
      load_repeated_page!()

      assert [%{urn: "pramana:cbeta.T:T0262_001@p0006a23"}] =
               Citation.scan("T0262_.09.0006a23")

      assert [%{urn: "pramana:cbeta.T:T0262_002@p0006a23"}] =
               Citation.scan("T0262_.10.0006a23")

      assert {:ok, "pramana:cbeta.T:T0262_002@p0006a23"} =
               Citation.taisho_urn(%{
                 work_id: "T0262",
                 volume: 10,
                 page: "0006",
                 register: "a",
                 line: 1,
                 from_foot: true
               })
    end

    test "a volume does not turn duplicate matches within that volume into one result" do
      load_repeated_page!()
      Repo.update_all(Pramana.Corpus.Segment, set: [meta: %{"volume" => 9}])

      assert [%{urn: nil, reason: {:ambiguous_address, "T0262", "0006", "a", 23}}] =
               Citation.scan("T0262_.09.0006a23")
    end

    defp load_repeated_page! do
      xml =
        String.replace(@xml, "</body>", """
        <milestone n="2" unit="juan"/>
        <lb n="0006a23"/>另一印本頁面
        </body>
        """)

      {:ok, ir} = CBETA.normalize(xml, work_id: "T0262", canon: "T", volume: 9, number: "0262")
      {:ok, _} = Loader.load(ir, source: "cbeta", witness: "T")
      Repo.update_all(Pramana.Corpus.Text, set: [volume: "9-10"])
      Repo.update_all(Pramana.Corpus.Segment, set: [meta: %{"volume" => 9}])

      Repo.update_all(from(s in Pramana.Corpus.Segment, where: s.juan == 2),
        set: [meta: %{"volume" => 10}]
      )
    end
  end

  test "rewriting repeated foreign citations preserves unrelated Unicode and wrong coordinates" do
    input = "🙂 e\u0301: T0262_.09.0006a23, T0262_.10.0006a23; T0262_.09.0006a23."
    urn = "pramana:cbeta.T:T0262_001@p0006a23"
    assert {rewritten, [first, wrong, repeated]} = Citation.rewrite(input)
    assert rewritten == "🙂 e\u0301: #{urn}, T0262_.10.0006a23; #{urn}."
    assert first.urn == repeated.urn
    assert wrong.urn == nil
    assert first.source_offset < wrong.source_offset
    assert wrong.source_offset < repeated.source_offset

    for item <- [first, wrong, repeated] do
      assert binary_part(input, item.source_offset, item.source_length) == item.matched
    end
  end
end
