defmodule PramanaNativeTest do
  use ExUnit.Case, async: true

  doctest PramanaNative

  describe "the FFI boundary preserves bytes exactly" do
    test "round-trips Han variants that Unicode normalization would collapse" do
      original = "戶户戸 說説 兔兎"
      assert PramanaNative.echo(original) == original
    end

    test "round-trips plane-2 rare glyphs" do
      original = "𤦲𧂐𩑔㝹"
      assert PramanaNative.echo(original) == original
    end
  end

  describe "segment/1" do
    test "splits Classical Chinese, which has no whitespace" do
      words = PramanaNative.segment("如是我聞一時佛住王舍城")

      assert is_list(words)
      assert length(words) > 1
      # Whatever the segmentation, it must be lossless.
      assert Enum.join(words) == "如是我聞一時佛住王舍城"
    end

    test "is lossless on a passage containing rare glyphs" do
      text = "阿㝹樓馱劫賓那"
      assert PramanaNative.segment(text) |> Enum.join() == text
    end

    test "handles the empty string" do
      assert PramanaNative.segment("") == []
    end
  end

  describe "segment_for_search/1" do
    test "search mode emits compound subwords that normal segmentation omits" do
      text = "中国科学院"
      plain = PramanaNative.segment(text)
      search = PramanaNative.segment_for_search(text)

      assert Enum.join(plain) == text
      assert "中国科学院" in plain
      refute "科学" in plain
      assert "科学" in search
      assert "学院" in search
      assert "科学院" in search
    end
  end
end
