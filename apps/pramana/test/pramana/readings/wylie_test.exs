defmodule Pramana.Readings.WylieTest do
  @moduledoc """
  Tibetan to Wylie, which is computed rather than looked up.

  The cases here are real words, and most of them exist to pin one orthographic rule
  each. The reason the test set is words rather than syllable fragments is that every
  interesting failure in this module is a **placement** error — the letters are almost
  always right and the implicit vowel lands in the wrong slot, producing something that
  looks plausible and is wrong.
  """
  use ExUnit.Case, async: true

  alias Pramana.Readings.Wylie

  doctest Pramana.Readings.Wylie

  describe "letters and vowels" do
    test "an explicit vowel is written where it stands" do
      assert Wylie.transliterate("ཀུན") == "kun"
      assert Wylie.transliterate("ཆོས") == "chos"
    end

    test "ཱ followed by ུ is the long U, not A then u" do
      assert Wylie.transliterate("ཧཱུྃ") == "hU~M"
    end

    test "ཨ is a vowel carrier, not a consonant" do
      # ཨོཾ is oM. Treating ཨ as a letter gives aoM, and the mantra stops being findable.
      assert Wylie.transliterate("ཨོཾ") == "oM"
      assert Wylie.transliterate("ཨ") == "a"
    end

    test "the tsheg is a separator, and becomes a space" do
      assert Wylie.transliterate("བོད་ཡིག") == "bod yig"
    end

    test "a shad becomes a slash" do
      assert Wylie.transliterate("བཀྲ་ཤིས། བདེ་ལེགས།") == "bkra shis/ bde legs/"
    end

    test "non-Tibetan text passes through" do
      assert Wylie.transliterate("hello") == "hello"
      assert Wylie.transliterate("") == ""
    end
  end

  describe "where the implicit vowel goes" do
    test "after the root, not at the end of the syllable" do
      # The whole reason this module needs orthographic rules. Appending the a would
      # give sngsa and thmsa — letter-perfect and unreadable.
      assert Wylie.transliterate("སངས") == "sangs"
      assert Wylie.transliterate("ཐམས") == "thams"
    end

    test "a stack with a native subscript is the root" do
      # ག carries the a even though two consonants follow it, because ར is subjoined to
      # it rather than standing beside it.
      assert Wylie.transliterate("གྲངས") == "grangs"
      assert Wylie.transliterate("བརྟགས") == "brtags"
    end

    test "ག ད བ མ འ before a consonant are prefixes, so the root is second" do
      assert Wylie.transliterate("གསལ") == "gsal"
      assert Wylie.transliterate("དཀར") == "dkar"
      assert Wylie.transliterate("བཟང") == "bzang"
      assert Wylie.transliterate("མཁས") == "mkhas"
    end

    test "a letter that cannot be a prefix is itself the root" do
      assert Wylie.transliterate("ནས") == "nas"
    end

    test "two letters: the second is a suffix, so the first is the root" do
      assert Wylie.transliterate("བག") == "bag"
    end

    test "an explicit vowel settles the root outright" do
      # བདེ is bde. The positional rules would read ད as a suffix and give bade, so the
      # vowel has to be consulted first — it sits on the root by definition.
      assert Wylie.transliterate("བདེ") == "bde"
      assert Wylie.transliterate("རྡོ་རྗེ") == "rdo rje"
    end
  end

  describe "stacks" do
    test "a superscript is written plainly" do
      assert Wylie.transliterate("སྐུ") == "sku"
      assert Wylie.transliterate("ལྔ") == "lnga"
    end

    test "superscript and subscript together" do
      assert Wylie.transliterate("བརྒྱད") == "brgyad"
      assert Wylie.transliterate("སྤྱན་རས་གཟིགས") == "spyan ras gzigs"
    end

    test "a Sanskrit conjunct is joined with + and carries its own vowel" do
      # པདྨ is pad+ma: དྨ is neither a superscript nor a subscript pair, so it is a
      # conjunct, and BOTH པ and the stacked མ take an a.
      assert Wylie.transliterate("པདྨ") == "pad+ma"
    end

    test "a conjunct does not become the root just because it is stacked" do
      # པདྨེ is pad+me. Treating the stacked དྨ as the root — which the native-stack rule
      # would — gives pd+me, losing པ's vowel.
      assert Wylie.transliterate("པདྨེ") == "pad+me"
    end

    test "the mantra, which exercises all of it at once" do
      assert Wylie.transliterate("ཨོཾ་མ་ཎི་པདྨེ་ཧཱུྃ") == "oM ma Ni pad+me hU~M"
    end
  end

  describe "the one genuine ambiguity" do
    test "ག before ཡ takes a disambiguating dot" do
      # གཡ and གྱ are different words and Unicode distinguishes them, but plain `gya`
      # would not — so EWTS puts a dot after the prefix.
      assert Wylie.transliterate("གཡང") == "g.yang"
      assert Wylie.transliterate("གྱང") == "gyang"
    end
  end

  describe "real titles" do
    test "the Prajñāpāramitā" do
      assert Wylie.transliterate("ཤེས་རབ་ཀྱི་ཕ་རོལ་ཏུ་ཕྱིན་པ") == "shes rab kyi pha rol tu phyin pa"
    end

    test "bodhisattva" do
      assert Wylie.transliterate("བྱང་ཆུབ་སེམས་དཔའ") == "byang chub sems dpa'"
    end

    test "the Buddha" do
      assert Wylie.transliterate("སངས་རྒྱས") == "sangs rgyas"
    end
  end
end
