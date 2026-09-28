defmodule Pramana.Chunk.GroupTest do
  use ExUnit.Case, async: true
  alias Pramana.Chunk.Builder

  describe "the chunk size for a script" do
    test "each script has its own, and an unknown source takes the Chinese default" do
      # Not a preference. The embedder truncates at 320 BGE-M3 tokens, and these are the
      # largest sizes whose 95th percentile fits: Pāli tokenizes at 0.425 tokens per
      # character and Tibetan at 0.151, so the same window holds very different amounts
      # of each. See the table in `Pramana.Chunk.Builder`.
      assert Builder.max_chars_for_source("sc") == 700
      assert Builder.max_chars_for_source("derge") == 1_200
      # Both halves of the Degé are the same script; a source missing here silently takes
      # the Chinese 300, which for Tibetan is a fifth of the window.
      assert Builder.max_chars_for_source("derge-tengyur") == 1_200
      assert Builder.max_chars_for_source("cbeta") == 300
    end
  end

  test "grouping preserves content and order, splits juan, and retains an oversized segment" do
    a = %{content: "一二三", juan: 1}
    b = %{content: "四五六", juan: 1}
    c = %{content: "七八九", juan: 2}
    long = %{content: "甲乙丙丁戊己庚辛壬癸", juan: 2}
    assert Builder.group([a, b, c, long], 6) == [[a, b], [c], [long]]
    assert Builder.group([a, b, c, long], 100) == [[a, b], [c, long]]
    assert Builder.group([], 6) == []
  end
end
