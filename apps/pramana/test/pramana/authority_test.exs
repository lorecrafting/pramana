defmodule Pramana.AuthorityTest do
  @moduledoc """
  A wrong authority link merges two people into one identity, and every later question about
  "the same translator" inherits the error silently. So the tests are mostly about what this
  refuses.
  """
  use Pramana.DataCase, async: true

  alias Pramana.Authority
  alias Pramana.Corpus.AuthorityPerson
  alias Pramana.Corpus.AuthorityPlace
  alias Pramana.Corpus.AuthorityRelation
  alias Pramana.Corpus.Work
  alias Pramana.Repo

  defp idx(people), do: Authority.index(people)

  # No default on `dynasty`: every caller passes one, and a default nobody uses is a warning
  # on every compile of this file.
  defp person(id, names, dynasty),
    do: %{id: id, names: names, dynasty: dynasty}

  describe "link_byline/2" do
    test "resolves a byline containing exactly one authority name" do
      index = idx([person("A000636", ["求那跋陀羅", "求那跋陁羅"], "劉宋")])

      # `name_and_dynasty` even though the name was unique: the dynasty is checked either
      # way, because whether a name is ambiguous says nothing about whether it is right.
      assert %{authority_id: "A000636", matched_name: "求那跋陀羅", method: "name_and_dynasty"} =
               Authority.link_byline("劉宋 求那跋陀羅譯", index)
    end

    test "matches an alternative spelling, which is the point of an authority file" do
      index = idx([person("A000636", ["求那跋陀羅", "求那跋陁羅"], "劉宋")])

      assert %{authority_id: "A000636"} = Authority.link_byline("劉宋 求那跋陁羅譯", index)
    end

    # 254 of the corpus's bylines need this. Both sides carry a dynasty and it is the only
    # discriminator available without a model.
    test "uses the dynasty to choose between namesakes" do
      index =
        idx([
          person("A000100", ["道隆"], "宋"),
          person("A000200", ["道隆"], "唐")
        ])

      assert %{authority_id: "A000100", method: "name_and_dynasty"} =
               Authority.link_byline("宋 道隆述", index)
    end

    # THE INTERESTING REFUSAL. A name matched and no person of that name comes from the
    # byline's dynasty — usually a coincidence of characters rather than a person. 235 of
    # the corpus's bylines land here, and accepting them would raise the number and lower
    # the truth.
    test "refuses when no namesake comes from the byline's dynasty" do
      index = idx([person("A000200", ["道隆"], "唐")])
      assert Authority.link_byline("宋 道隆述", index) == nil
    end

    test "refuses when the dynasty leaves several namesakes" do
      index =
        idx([
          person("A000100", ["道隆"], "宋"),
          person("A000101", ["道隆"], "宋")
        ])

      assert Authority.link_byline("宋 道隆述", index) == nil
    end

    test "prefers the longest name, so a substring cannot win" do
      index =
        idx([
          person("A000636", ["求那跋陀羅"], "劉宋"),
          person("A009999", ["求那"], "唐")
        ])

      assert %{authority_id: "A000636"} = Authority.link_byline("劉宋 求那跋陀羅譯", index)
    end

    # An authority record with no dynasty cannot disagree with one, so the link stands and
    # `method` records that the weaker rule ran.
    test "links on the name alone when the authority states no dynasty" do
      index = idx([person("A000636", ["求那跋陀羅"], nil)])

      assert %{method: "name_match_no_dynasty"} =
               Authority.link_byline("劉宋 求那跋陀羅譯", index)
    end

    # THE REFUSAL THAT WAS COSTING THE MOST IMPORTANT LINKS. CBETA and DILA name the same
    # dynasty differently — 姚秦 for 後秦, named for the ruling Yao family rather than by
    # sequence — and asserting the strings would match refused 竺佛念, 天息災 and 維祇難,
    # three of the translators this corpus most depends on.
    test "accepts a dynasty named differently by the two sources" do
      index = idx([person("A000435", ["竺佛念"], "後秦")])

      assert %{authority_id: "A000435", method: "name_and_dynasty"} =
               Authority.link_byline("姚秦 竺佛念譯", index)
    end

    test "accepts a byline that names the era less precisely than the record" do
      # 宋 against 北宋: the record distinguishes a period the byline did not bother to.
      index = idx([person("A000146", ["天息災"], "北宋")])

      assert %{authority_id: "A000146"} = Authority.link_byline("宋 天息災譯", index)
    end

    # The synonym table must never map two DIFFERENT dynasties together, which is the
    # mistake that would silently merge people. Saṅghadeva really did work under both, and
    # DILA records only one — so this stays a refusal.
    test "still refuses two genuinely different dynasties" do
      index = idx([person("A001589", ["瞿曇僧伽提婆", "僧伽提婆"], "前秦")])

      assert Authority.link_byline("東晉 瞿曇僧伽提婆譯", index) == nil
    end

    test "ignores one-character names, which appear in almost every byline" do
      index = idx([person("A000001", ["宋"], "宋")])
      assert Authority.link_byline("宋 道隆述", index) == nil
    end

    test "is nil for an empty or missing byline" do
      index = idx([person("A1", ["道隆"], "宋")])
      assert Authority.link_byline(nil, index) == nil
      assert Authority.link_byline("", index) == nil
    end

    test "never claims certainty" do
      index = idx([person("A000636", ["求那跋陀羅"], "劉宋")])
      # The name is certainly in the byline; that it denotes this person rather than a
      # namesake the authority does not record is an inference.
      assert %{confidence: "probable"} = Authority.link_byline("劉宋 求那跋陀羅譯", index)
    end
  end

  describe "parse_places/1" do
    @place """
    <listPlace>
    <place xml:id="PL000000047987">
     <placeName xml:lang="zho-Hant">于闐</placeName>
     <placeName type="alternative" xml:lang="zho-Hant">瞿薩怛那</placeName>
     <location><place key="PLD003112">和田縣</place><geo cert="high">79.828 36.9881</geo></location>
     <district>中國-新疆維吾爾自治區-和田地區-和田縣</district>
     <country>西突厥</country>
     <note>在安西府南二千里。</note>
    </place>
    <place xml:id="PL000000000001">
     <placeName xml:lang="zho-Hant">闊悉多國</placeName>
     <placeName xml:lang="eng-Latn">Khost</placeName>
     <location><place key="PLA000002">阿富汗</place><geo>67.868089 36.555275</geo></location>
     <district>阿富汗</district>
    </place>
    <place xml:id="PL000000099999">
     <placeName xml:lang="zho-Hant">邊界</placeName>
     <district>中國;蒙古;俄羅斯-遠東聯邦管區-Sakhalin</district>
    </place>
    </listPlace>
    """

    test "reads both region schemes, and every spelling" do
      [khotan | _] = Authority.parse_places(@place)

      assert khotan.id == "PL000000047987"
      assert khotan.name == "于闐"
      assert khotan.names == ["于闐", "瞿薩怛那"]
      # The MODERN administrative path...
      assert khotan.district_path == ~w(中國 新疆維吾爾自治區 和田地區 和田縣)
      # ...and the HISTORICAL unit, which is the one a scholar means.
      assert khotan.country == "西突厥"
      assert khotan.region_id == "PLD003112"
      assert khotan.region_name == "和田縣"
    end

    test "geo is LONGITUDE first, which is the reverse of what TEI documents" do
      [khotan | _] = Authority.parse_places(@place)

      # Khotan is 37.1°N 79.9°E. Read as TEI documents `<geo>` — latitude first — every
      # place in this corpus lands in the Arctic Ocean.
      assert khotan.lon == 79.828
      assert khotan.lat == 36.9881
      assert khotan.geo_cert == "high"
    end

    test "matches the tag WITH its attributes, and without them" do
      places = Authority.parse_places(@place)

      # `<geo cert="high">` and bare `<geo>` both occur in the file. A pattern written for
      # the bare form reports absence rather than erroring — it measured this field at 0.0%
      # when the truth is 100%. Rule 62.
      assert Enum.at(places, 0).lon
      assert Enum.at(places, 1).lon == 67.868089
      assert Enum.at(places, 1).geo_cert == nil
    end

    test "an English name is read when present and nil when not" do
      places = Authority.parse_places(@place)

      assert Enum.at(places, 1).name_en == "Khost"
      # 1.2% of the file carries one. Absent is the normal case and must not be an empty
      # string, which would sort and compare as a name.
      assert Enum.at(places, 0).name_en == nil
    end

    test "a semicolon means several regions, so no path is offered" do
      border = Enum.at(Authority.parse_places(@place), 2)

      # Splitting `中國;蒙古;俄羅斯-…` on `-` yields fragments that look like a hierarchy and
      # are not. The raw string is always kept, so refusing the path loses nothing.
      assert border.district == "中國;蒙古;俄羅斯-遠東聯邦管區-Sakhalin"
      assert border.district_path == []
    end

    test "a place with no coordinates has neither end" do
      border = Enum.at(Authority.parse_places(@place), 2)

      assert border.lon == nil
      assert border.lat == nil
    end
  end

  describe "parse_people/1" do
    test "reads names, alternatives and dynasty out of DILA's TEI" do
      xml = """
      <person xml:id="A000001" ana="historical">
        <persName xml:lang="zho-Hant">金總持</persName>
        <persName type="alternative" xml:lang="zho-Hant">寶輪大師</persName>
        <note type="dynasty">
          北宋
        </note>
      </person>
      """

      assert [%{id: "A000001", names: ["金總持", "寶輪大師"], dynasty: "北宋"}] =
               Authority.parse_people(xml)
    end

    test "a record with no dynasty parses, and simply cannot disambiguate" do
      assert [%{dynasty: nil}] =
               Authority.parse_people(~s(<person xml:id="A1"><persName>某</persName></person>))
    end
  end

  describe "works/2" do
    test "returns works attributed to an authority person with pagination" do
      Repo.insert!(%Work{
        id: "T0001",
        title: "長阿含經",
        attributed_author: "後秦 竺佛念譯",
        composition_origin: "indic",
        text_role: "root",
        authority_id: "A001234",
        authority_method: "name_and_dynasty",
        authority_confidence: "probable"
      })

      Repo.insert!(%Work{
        id: "T0002",
        title: "七佛父母姓字經",
        attributed_author: "後秦 竺佛念譯",
        composition_origin: "indic",
        text_role: "root",
        authority_id: "A001234",
        authority_method: "name_and_dynasty",
        authority_confidence: "probable"
      })

      Repo.insert!(%Work{
        id: "T0003",
        title: "別譯雜阿含經",
        attributed_author: "失譯",
        authority_id: "A999999"
      })

      res = Authority.works("A001234")
      assert res.authority_id == "A001234"
      assert res.count == 2
      assert res.returned == 2
      assert res.bylines == ["後秦 竺佛念譯"]
      assert length(res.works) == 2

      # Test pagination limit
      paged = Authority.works("A001234", limit: 1)
      assert paged.count == 2
      assert paged.returned == 1
    end
  end

  defp insert_person!(attrs) do
    %AuthorityPerson{}
    |> Ecto.Changeset.change(Map.put_new(attrs, :source, "dila-authority"))
    |> Repo.insert!()
  end

  defp insert_place!(attrs) do
    %AuthorityPlace{}
    |> Ecto.Changeset.change(Map.put_new(attrs, :source, "dila-authority"))
    |> Repo.insert!()
  end

  defp insert_relation!(attrs) do
    %AuthorityRelation{}
    |> Ecto.Changeset.change(Map.put_new(attrs, :source, "dila-authority"))
    |> Repo.insert!()
  end

  describe "person/1" do
    test "returns nil for nonexistent authority id" do
      assert Authority.person("A_NONEXISTENT") == nil
    end

    test "returns detailed person record with place, dates, and lineage" do
      insert_place!(%{
        id: "PL0001",
        name: "長安",
        name_en: "Chang'an",
        district: "中國-陝西-西安",
        district_path: ["中國", "陝西", "西安"],
        country: "關內道",
        region_name: "關中",
        lon: 108.9,
        lat: 34.2,
        geo_cert: "high"
      })

      insert_person!(%{
        id: "A001000",
        name: "玄奘",
        names: ["玄奘", "三藏法師"],
        dynasty: "唐",
        place_id: "PL0001",
        place_of_origin: "洛州緱氏",
        birth_earliest: ~D[0602-01-01],
        birth_latest: ~D[0602-12-31],
        birth_note: "約生於仁壽二年",
        death_earliest: ~D[0664-03-07],
        death_latest: ~D[0664-03-07],
        death_note: "麟德元年二月五日示寂",
        sect: "法相宗",
        active_at: ["長安", "洛陽"],
        monk: true,
        concise: "唐代著名高僧、佛經翻譯家",
        external_ids: %{"wikidata" => "Q42057"}
      })

      Repo.insert!(%Work{
        id: "T0220",
        title: "大般若波羅蜜多經",
        attributed_author: "唐 玄奘譯",
        authority_id: "A001000"
      })

      p = Authority.person("A001000")
      assert p != nil
      assert p.authority_id == "A001000"
      assert p.name == "玄奘"
      assert p.also_known_as == ["三藏法師"]
      assert p.dynasty == "唐"
      assert p.monk == true
      assert p.sect == "法相宗"
      assert p.external_ids == %{"wikidata" => "Q42057"}
      assert p.works_in_bake == 1

      # Dates range
      assert p.birth.earliest == ~D[0602-01-01]
      assert p.birth.latest == ~D[0602-12-31]
      assert p.birth.exact == false
      assert p.death.exact == true

      # Place record
      assert p.place != nil
      assert p.place.place_id == "PL0001"
      assert p.place.name == "長安"
      assert p.place.historical_region == "關內道"
      assert p.place.lon == 108.9
      assert p.place.lat == 34.2
    end

    test "handles person with nil place_id, unresolvable place_id, and unrecorded dates" do
      insert_person!(%{
        id: "A002000",
        name: "無名",
        place_id: nil,
        birth_earliest: nil,
        birth_latest: nil,
        death_earliest: nil,
        death_latest: nil
      })

      p = Authority.person("A002000")
      assert p.place == nil
      assert p.birth == nil
      assert p.death == nil

      # Unresolvable place_id
      insert_person!(%{
        id: "A003000",
        name: "佚名",
        place_id: "PL_MISSING"
      })

      p3 = Authority.person("A003000")
      assert p3.place == nil
    end
  end

  describe "lineage/1" do
    test "retrieves recorded teachers and students" do
      insert_person!(%{id: "A10", name: "戒賢"})
      insert_person!(%{id: "A20", name: "玄奘"})
      insert_person!(%{id: "A30", name: "窺基"})

      Repo.insert!(%AuthorityRelation{
        person_id: "A20",
        related_id: "A10",
        type: "teacher",
        related_name: "戒賢",
        source: "dila"
      })

      Repo.insert!(%AuthorityRelation{
        person_id: "A20",
        related_id: "A30",
        type: "student",
        related_name: "窺基",
        source: "dila"
      })

      lineage = Authority.lineage("A20")
      assert length(lineage.teachers) == 1
      assert hd(lineage.teachers).id == "A10"
      assert hd(lineage.teachers).name == "戒賢"

      assert length(lineage.students) == 1
      assert hd(lineage.students).id == "A30"
      assert hd(lineage.students).name == "窺基"
    end
  end

  describe "teacher_chain/2" do
    test "walks teacher lineage upward until no teacher is recorded" do
      insert_person!(%{id: "T1", name: "師父"})
      insert_person!(%{id: "T2", name: "徒弟"})

      insert_relation!(%{
        person_id: "T2",
        related_id: "T1",
        type: "teacher",
        related_name: "師父"
      })

      res = Authority.teacher_chain("T2")
      assert res.stopped == :no_teacher_recorded
      assert res.branched == false
      assert Enum.map(res.chain, & &1.id) == ["T1"]
    end

    test "stops at max depth limit" do
      insert_person!(%{id: "L1", name: "一代"})
      insert_person!(%{id: "L2", name: "二代"})
      insert_person!(%{id: "L3", name: "三代"})

      insert_relation!(%{person_id: "L3", related_id: "L2", type: "teacher"})
      insert_relation!(%{person_id: "L2", related_id: "L1", type: "teacher"})

      res = Authority.teacher_chain("L3", depth: 1)
      assert res.stopped == :depth
      assert length(res.chain) == 1
      assert hd(res.chain).id == "L2"
    end

    test "detects cycles and flags branching" do
      insert_person!(%{id: "C1", name: "甲"})
      insert_person!(%{id: "C2", name: "乙"})

      # Cycle: C1 taught C2, C2 taught C1
      insert_relation!(%{person_id: "C1", related_id: "C2", type: "teacher"})
      insert_relation!(%{person_id: "C2", related_id: "C1", type: "teacher"})

      res = Authority.teacher_chain("C1")
      assert res.stopped == :cycle

      # Branching: person has 2 teachers
      insert_person!(%{id: "B0", name: "學人"})
      insert_person!(%{id: "B1", name: "師父一"})
      insert_person!(%{id: "B2", name: "師父二"})

      insert_relation!(%{person_id: "B0", related_id: "B1", type: "teacher"})
      insert_relation!(%{person_id: "B0", related_id: "B2", type: "teacher"})

      res_branched = Authority.teacher_chain("B0")
      assert res_branched.branched == true
    end
  end
end
