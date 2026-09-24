defmodule Pramana.Repair.QuoteTest do
  @moduledoc "A punctuation/glyph correction must identify one substantive source subspan."
  use ExUnit.Case, async: true

  alias Pramana.Repair.Quote

  test "full substantive equivalence keeps edition punctuation, without adding words" do
    assert {:ok, "如是我聞，一時佛住。"} =
             Quote.align("如是我聞，一時佛住。", "如是我聞一時佛住", :editorial_punctuation)
  end

  test "partial alignment preserves only the intended words and their internal punctuation" do
    assert {:ok, "唯我，獨尊"} =
             Quote.align("前文。天上天下，唯我，獨尊。後文。", "唯我獨尊", :editorial_punctuation)
  end

  test "empty, punctuation-only, repeated and overlapping matches do not authorize replacement" do
    assert {:error, :empty_quote} = Quote.align("佛說。", "……", :editorial_punctuation)
    assert {:error, :empty_quote} = Quote.align("佛說。", " \n", :editorial_punctuation)
    assert {:error, :ambiguous_quote} = Quote.align("佛說，佛說。", "佛，說", :editorial_punctuation)
    assert {:error, :ambiguous_quote} = Quote.align("哈哈哈", "哈哈", :editorial_punctuation)
    assert {:error, :unaligned_quote} = Quote.align("佛說。", "我聞", :editorial_punctuation)
  end

  test "variant matches map to exact original source bytes" do
    assert {:ok, "佛說"} = Quote.align("前文。佛說。後文。", "佛説", :orthographic_variant)
    assert {:error, :ambiguous_quote} = Quote.align("佛說。佛説。", "佛说", :orthographic_variant)
  end

  test "multibyte and combining-grapheme offsets are not normalized into invented source bytes" do
    actual = "前🙂 e\u0301，བོད་ 後"
    assert {:ok, "e\u0301，བོད་"} = Quote.align(actual, "e\u0301བོད་", :editorial_punctuation)
    assert {:error, :unaligned_quote} = Quote.align(actual, "éབོད་", :editorial_punctuation)
  end
end
