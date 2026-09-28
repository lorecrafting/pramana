defmodule Pramana.Tengyur.TitlesTest do
  @moduledoc """
  A Tengyur work names itself in its own opening line, so its title needs no catalogue.

  Every test here guards the same boundary: take what the edition prints, and when it
  prints nothing recognisable, say so rather than guess.
  """
  use ExUnit.Case, async: true

  alias Pramana.Tengyur.Titles

  describe "a work that names itself" do
    test "both titles are read from the opening" do
      # toh1114, verbatim: "In the Indian language: Buddhastotra-nāma. In Tibetan: ..."
      text =
        "༄༅༅། །རྒྱ་གར་སྐད་དུ། བུདྡྷ་སྱ་སྟོ་ཏྲ་ནཱ་མ། བོད་སྐད་དུ། " <>
          "སངས་རྒྱས་ཀྱི་བསྟོད་པ་ཞེས་བྱ་བ། འཇམ་དཔལ་གཞོན་ནུར་གྱུར་པ་ལ་ཕྱག་འཚལ་ལོ།"

      assert %{sa_bo: "བུདྡྷ་སྱ་སྟོ་ཏྲ་ནཱ་མ", bo: "སངས་རྒྱས་ཀྱི་བསྟོད་པ་ཞེས་བྱ་བ"} = Titles.extract(text)
    end

    test "the title stops at the shad, not at the homage that follows" do
      text = "༄༅། །རྒྱ་གར་སྐད་དུ། ཨ། བོད་སྐད་དུ། ཁྱད་པར། དཀོན་མཆོག་གསུམ་ལ་ཕྱག་འཚལ་ལོ།"

      assert Titles.extract(text).bo == "ཁྱད་པར"
    end

    test "a double shad closes a title too" do
      text = "རྒྱ་གར་སྐད་དུ། བུདྡྷ༎ བོད་སྐད་དུ། སངས་རྒྱས༎"

      assert %{sa_bo: "བུདྡྷ", bo: "སངས་རྒྱས"} = Titles.extract(text)
    end
  end

  describe "a work that does not" do
    test "no markers yields no titles, rather than the first words of the text" do
      # About 23% of the Tengyur opens without the formula. Guessing from the body would
      # produce a title for every work and a wrong one for hundreds.
      assert Titles.extract("སངས་རྒྱས་ལ་ཕྱག་འཚལ་ལོ། །དེ་ནས་བཅོམ་ལྡན་འདས་ཀྱིས།") == %{}
    end

    test "a marker with nothing after it yields nothing" do
      assert Titles.extract("རྒྱ་གར་སྐད་དུ།") == %{}
    end

    test "empty and non-binary input are safe" do
      assert Titles.extract("") == %{}
      assert Titles.extract(nil) == %{}
    end
  end

  describe "the guard against a missing shad" do
    test "a Sanskrit title running into the Tibetan marker is refused" do
      # Without the closing shad the Sanskrit would swallow "in Tibetan: ..." and be
      # recorded as the work's Sanskrit name — a plausible-looking, wholly wrong title.
      text = "རྒྱ་གར་སྐད་དུ། བུདྡྷ་སྟོ་ཏྲ བོད་སྐད་དུ། སངས་རྒྱས།"

      titles = Titles.extract(text)

      refute Map.has_key?(titles, :sa_bo)
      assert titles.bo == "སངས་རྒྱས"
    end
  end
end
