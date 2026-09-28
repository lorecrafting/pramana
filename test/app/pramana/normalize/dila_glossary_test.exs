defmodule Pramana.Normalize.DilaGlossaryTest do
  @moduledoc """
  A glossary of a polysemous language has one failure mode that matters: **quietly
  reporting a word as having settled.** Every test here is about a distinction the parser
  could collapse — two senses into one, a non-correspondence into a correspondence, a
  Chinese quotation into the Sanskrit column.

  Two of them are regressions from real bugs found while writing the ingest, and both
  produced *plausible* output, which is why they needed a test rather than a glance.
  """
  use ExUnit.Case, async: true

  alias Pramana.Normalize.DilaGlossary

  # Karashima's real shape, reduced. The first parallel's Sanskrit witness is a
  # NON-correspondence — `K. not found` with no reading — and the second carries the
  # actual one. This is 法 in Kumārajīva's Lotus, which is where both bugs surfaced.
  @karashima """
  <entry>
    <form><orth>法</orth><pron notation="pinyin">fǎ</pron></form>
    <def><quote type="translation">as a rule, normally</quote></def>
    <cit type="parallels">
      <cit type="parallel">
        <cit type="T.262"><bibl>6a23</bibl><quote>諸佛語無異</quote></cit>
        <cit type="sa-witness"><bibl><abbr>K.</abbr>not found at 32.16</bibl></cit>
      </cit>
      <cit type="parallel">
        <cit type="T.262"><bibl>7b4</bibl><quote>如來但以一佛乘故</quote></cit>
        <cit type="sa-witness"><bibl><abbr>K.</abbr>40.15</bibl><quote>dharmatā</quote></cit>
      </cit>
    </cit>
  </entry>
  <entry>
    <form><orth>法</orth></form>
    <def>name of a kiṃnara king</def>
    <cit type="parallels"><cit type="parallel">
      <cit type="sa-witness"><bibl><abbr>K.</abbr>4.1</bibl><quote>Druma</quote></cit>
    </cit></cit>
  </entry>
  <entry>
    <form><orth>輩</orth></form>
  </entry>
  """

  describe "one row per sense" do
    # THE POINT OF THE WHOLE EXERCISE. 法 in Kumārajīva is an ordinary adverb in one place
    # and a kiṃnara king's name in another. A `gloss_id` keyed on the headword alone keeps
    # whichever was parsed last and reports a polysemous word as settled.
    test "a headword appearing twice becomes two entries, not one" do
      entries = DilaGlossary.parse(@karashima, :karashima, "kumarajiva")
      senses = Enum.filter(entries, &(&1.chinese == "法"))

      assert length(senses) == 2
      assert Enum.map(senses, & &1.gloss_id) == ["kumarajiva:法:1", "kumarajiva:法:2"]
      assert Enum.any?(senses, &(&1.definition =~ "as a rule"))
      assert Enum.any?(senses, &(&1.definition =~ "kiṃnara"))
    end
  end

  describe "the Sanskrit witness" do
    # REGRESSION. `<cit type="sa-witness">.*?<quote>` is unbounded, so a witness recording
    # that the Sanskrit has NO counterpart — `K. not found at 32.16`, no `<quote>` — let
    # the match run on into the next parallel's Chinese quotation. A line of the Lotus
    # Sūtra was stored in the `sanskrit` column and the entry counted as attested.
    test "a 'not found' witness does not capture the next Chinese quotation" do
      [entry | _] = DilaGlossary.parse(@karashima, :karashima, "kumarajiva")

      refute entry.sanskrit =~ "如來"
      refute entry.sanskrit =~ "諸佛"
    end

    # REGRESSION, the over-correction. Bounding the search to the FIRST witness block then
    # reported 法 as unattested, because its first parallel is the "not found" one and the
    # real reading is in the second. Karashima lists one witness per parallel passage.
    test "a reading in a later parallel is still found" do
      [entry | _] = DilaGlossary.parse(@karashima, :karashima, "kumarajiva")

      assert entry.sanskrit == "dharmatā"
      assert entry.chinese_attestation == "source"
    end

    test "an entry with no reading anywhere is dictionary-attested, never source" do
      entries = DilaGlossary.parse(@karashima, :karashima, "lokaksema")
      bare = Enum.find(entries, &(&1.chinese == "輩"))

      assert bare.sanskrit == nil
      assert bare.chinese_attestation == "dictionary"
    end
  end

  describe "the Taishō citations, which are what make a gloss checkable" do
    test "are kept as the edition prints them" do
      [entry | _] = DilaGlossary.parse(@karashima, :karashima, "kumarajiva")

      assert entry.citations == ["T.262:6a23", "T.262:7b4"]
    end
  end

  describe "the other two shapes" do
    test "Soothill-Hodous is Chinese-headed and never claims a witness" do
      xml = """
      <entry><form>空</form><sense><term xml:lang="san-Latn">śūnya</term>, empty, void.</sense></entry>
      """

      [entry] = DilaGlossary.parse(xml, :soothill, "shh")

      assert entry.chinese == "空"
      assert entry.sanskrit == "śūnya"
      assert entry.definition =~ "empty, void"
      # It is a dictionary reporting other dictionaries. Calling it `source` would claim a
      # witness nobody looked at.
      assert entry.chinese_attestation == "dictionary"
    end

    test "the Mahāvyutpatti is Sanskrit-headed and bridges Chinese to Tibetan" do
      xml = """
      <entry key="1">
        <form><orth xml:lang="san-Latn">buddhaḥ</orth></form>
        <cit type="translation" xml:lang="zho-Hant"><quote>正覺</quote></cit>
        <cit type="translation" xml:lang="bod-Tibt"><quote>སངས་རྒྱས་</quote></cit>
      </entry>
      """

      [entry] = DilaGlossary.parse(xml, :mahavyutpatti, "mvy")

      assert entry.sanskrit == "buddhaḥ"
      assert entry.chinese == "正覺"
      assert entry.tibetan == "སངས་རྒྱས་"
      assert entry.gloss_id == "mvy:正覺:1"
    end
  end
end
