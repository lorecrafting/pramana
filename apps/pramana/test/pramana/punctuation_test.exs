defmodule Pramana.PunctuationTest do
  @moduledoc """
  Tests editorial punctuation stripping and comparison.
  """
  use ExUnit.Case, async: true

  doctest Pramana.Punctuation

  alias Pramana.Punctuation

  describe "pattern/0" do
    test "returns the editorial punctuation regex" do
      assert %Regex{} = Punctuation.pattern()
      assert Regex.match?(Punctuation.pattern(), "，")
      assert Regex.match?(Punctuation.pattern(), "。")
      assert Regex.match?(Punctuation.pattern(), "「")
      assert Regex.match?(Punctuation.pattern(), " ")
      # Does not match Tibetan tsheg
      refute Regex.match?(Punctuation.pattern(), "་")
    end
  end

  describe "strip/1" do
    test "removes punctuation and whitespace from Chinese text" do
      assert Punctuation.strip("如是我聞，一時佛住。") == "如是我聞一時佛住"
      assert Punctuation.strip("「一切眾生」【皆有】佛性！") == "一切眾生皆有佛性"
    end

    test "leaves unpunctuated text unchanged" do
      assert Punctuation.strip("如是我聞") == "如是我聞"
    end
  end

  describe "same_but_for_punctuation?/2" do
    test "returns true when passages differ only in punctuation" do
      assert Punctuation.same_but_for_punctuation?("如是我聞，一時佛住。", "如是我聞 一時佛住")
      assert Punctuation.same_but_for_punctuation?("【摩訶般若】", "摩訶般若")
    end

    test "returns false when passage characters differ" do
      refute Punctuation.same_but_for_punctuation?("如是我聞", "如是我見")
      refute Punctuation.same_but_for_punctuation?("色即是空", "空即是色")
    end
  end
end
