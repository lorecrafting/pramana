defmodule Pramana.Derge.GenreTest do
  @moduledoc """
  Reading a Tibetan title's genre suffix.

  Every fixture is a real Degé title. The rules here are claims about how Tibetan names
  its commentarial literature, and a claim of that kind is only worth what it was checked
  against — so the Pramāṇavārttika family, whose shape is independently known, is the
  case that has to come out right.
  """
  use ExUnit.Case, async: true

  alias Pramana.Derge.Genre

  describe "classify/1" do
    test "reads the root's own genre — verses are a genre too" do
      # This is why a family cannot be found by title alone: the ROOT names a genre, so
      # its title is longer than the stem its commentaries share.
      assert {"ཚད་མ་རྣམ་འགྲེལ", :karika, 0} =
               Genre.classify("ཚད་མ་རྣམ་འགྲེལ་གྱི་ཚིག་ལེའུར་བྱས་པ")
    end

    test "reads a commentary and its subcommentary at different depths" do
      assert {"ཚད་མ་རྣམ་འགྲེལ", :vrtti, 1} = Genre.classify("ཚད་མ་རྣམ་འགྲེལ་གྱི་འགྲེལ་པ")
      assert {"ཚད་མ་རྣམ་འགྲེལ", :tika, 2} = Genre.classify("ཚད་མ་རྣམ་འགྲེལ་གྱི་འགྲེལ་བཤད")
    end

    test "strips the genitive, so a stem matches a title that has none" do
      # `…གྱི་འགྲེལ་པ` must reduce to `ཚད་མ་རྣམ་འགྲེལ` and not `ཚད་མ་རྣམ་འགྲེལ་གྱི`. The
      # first version trimmed the tsheg AFTER testing for the particle, so every stem
      # kept its `གྱི` and no family ever matched.
      assert {"ཚད་མ་རྣམ་འགྲེལ", _, _} = Genre.classify("ཚད་མ་རྣམ་འགྲེལ་གྱི་འགྲེལ་པ")
    end

    test "strips the 'called' particle that can follow the genre" do
      assert {"ཚད་མ་རྣམ་འགྲེལ", :vrtti, 1} =
               Genre.classify("ཚད་མ་རྣམ་འགྲེལ་གྱི་འགྲེལ་པ་ཞེས་བྱ་བ")
    end

    test "a longer suffix wins over one contained in it" do
      # `འགྲེལ་བཤད` must not be read as `བཤད་པ`, and `རྒྱ་ཆེར་འགྲེལ་པ` not as `འགྲེལ་པ`.
      assert {_, :tika, 2} = Genre.classify("ཚད་མ་རྣམ་འགྲེལ་གྱི་འགྲེལ་བཤད")
      assert {_, :tika, 1} = Genre.classify("དཔྱིད་ཀྱི་ཐིག་ལེའི་རྒྱ་ཆེར་འགྲེལ་པ")
    end

    test "a deeper stem is kept, so the nearest parent can be found" do
      # `…གྱི་རྒྱན་གྱི་འགྲེལ་བཤད` explains the alaṃkāra, not the root three layers below.
      # The stem has to keep `རྒྱན` for that to be discoverable.
      assert {"ཚད་མ་རྣམ་འགྲེལ་གྱི་རྒྱན", :tika, 2} =
               Genre.classify("ཚད་མ་རྣམ་འགྲེལ་གྱི་རྒྱན་གྱི་འགྲེལ་བཤད")
    end

    test "a ritual text is not a commentary" do
      # `སྒྲུབ་ཐབས` appears about 700 times, more than every commentarial suffix combined.
      # A sādhana shares its stem with every other sādhana for the same deity, so reading
      # these as commentary would manufacture a chain out of a liturgy.
      assert Genre.classify("འཇམ་དཔལ་གྱི་སྒྲུབ་ཐབས") == :none
      assert Genre.classify("རྡོ་རྗེ་སེམས་དཔའི་ཆོ་ག") == :none
    end

    test "a title naming no genre is not forced into one" do
      assert Genre.classify("ཤེས་རབ་ཀྱི་ཕ་རོལ་ཏུ་ཕྱིན་པ") == :none
    end
  end

  describe "relation_to/1" do
    test "explaining a commentary is a subcommentary" do
      assert Genre.relation_to(1) == "subcommentary_of"
      assert Genre.relation_to(2) == "subcommentary_of"
    end

    test "explaining a root, or something whose genre is unknown, is commentary" do
      # Unknown is deliberately the weaker claim: `comments_on` is true of a
      # subcommentary too, while the reverse is not.
      assert Genre.relation_to(0) == "comments_on"
      assert Genre.relation_to(nil) == "comments_on"
    end
  end

  describe "comparable/1" do
    test "two spellings of one title compare equal" do
      assert Genre.comparable("རྡོ་རྗེའི་གླུ་ཞེས་བྱ་བ") == Genre.comparable("རྡོ་རྗེའི་གླུ")
    end
  end
end
