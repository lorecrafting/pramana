defmodule Pramana.AuthorityTest do
  @moduledoc """
  A wrong authority link merges two people into one identity, and every later question about
  "the same translator" inherits the error silently. So the tests are mostly about what this
  refuses.
  """
  use ExUnit.Case, async: true

  alias Pramana.Authority

  defp idx(people), do: Authority.index(people)

  defp person(id, names, dynasty \\ nil),
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
end
