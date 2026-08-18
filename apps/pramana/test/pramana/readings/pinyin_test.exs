defmodule Pramana.Readings.PinyinTest do
  @moduledoc """
  Syllable notation, where the two source dictionaries have to be made comparable.

  Every entry in the reading dictionary is derived by comparing Unihan's `bō` against
  CC-CEDICT's `bo1`. Convert those wrongly and every entry looks like a disagreement, or
  worse, entries that genuinely disagree look identical and are silently dropped.
  """
  use ExUnit.Case, async: true

  alias Pramana.Readings.Pinyin

  doctest Pramana.Readings.Pinyin

  describe "toned" do
    test "marks a, o and e wherever they appear" do
      assert Pinyin.toned("ban1") == "bān"
      assert Pinyin.toned("bo1") == "bō"
      assert Pinyin.toned("re3") == "rě"
    end

    test "marks the SECOND vowel in iu and ui" do
      # The folk rule "mark the first vowel" gets both of these wrong, and they are
      # common enough that the error would show up on nearly every page.
      assert Pinyin.toned("liu4") == "liù"
      assert Pinyin.toned("dui4") == "duì"
    end

    test "keeps ü distinct from u" do
      assert Pinyin.toned("lu:4") == "lǜ"
      assert Pinyin.toned("lu4") == "lù"
    end

    test "tone 5 is neutral and takes no mark" do
      assert Pinyin.toned("de5") == "de"
    end

    test "returns unparseable input rather than raising" do
      # A third-party dictionary of 125,000 lines will contain something unexpected;
      # one odd line must not stop a build that has 9,000 good entries in it.
      assert Pinyin.toned("Q") == "q"
      assert Pinyin.toned("xyz") == "xyz"
    end

    test "output is NFC, so comparison against Unihan works" do
      # A combining macron appended to "a" is not the same binary as "ā", and a string
      # comparison between them fails silently — which would reject every entry.
      assert Pinyin.toned("ba1") == :unicode.characters_to_nfc_binary("bā")
      assert byte_size(Pinyin.toned("ba1")) == byte_size("bā")
    end
  end

  describe "toneless" do
    test "strips tone marks" do
      assert Pinyin.toneless("bō") == "bo"
      assert Pinyin.toneless("rě") == "re"
    end

    test "does NOT strip the diaeresis of ü" do
      # ü decomposes to u + combining diaeresis, which sits in the same Unicode block as
      # the tone marks. Stripping the block turns lǜ into lu and makes two different
      # syllables compare equal.
      assert Pinyin.toneless("lǜ") == "lü"
      refute Pinyin.toneless("lǜ") == Pinyin.toneless("lù")
    end
  end

  describe "neutral_tone_only?" do
    test "recognises modern 輕聲 erosion" do
      # CC-CEDICT records spoken Mandarin. 知識 as zhī shi is a fact about twentieth-
      # century speech, not about a seventh-century text, and must not enter a dictionary
      # for Literary Chinese.
      assert Pinyin.neutral_tone_only?("zhī shi", "zhī shí")
      assert Pinyin.neutral_tone_only?("zhǒng zi", "zhǒng zǐ")
    end

    test "a real reading difference is not neutral-tone erosion" do
      assert Pinyin.neutral_tone_only?("bō rě", "bān ruò") == false
      assert Pinyin.neutral_tone_only?("jiā shè", "jiā yè") == false
    end

    test "different lengths are never the same word eroded" do
      assert Pinyin.neutral_tone_only?("bō rě", "bō") == false
    end
  end
end
