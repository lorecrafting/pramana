defmodule Pramana.CommentaryTest do
  @moduledoc """
  The method is one rule — a window unique in the root — so the tests are about the two
  ways it can go wrong: anchoring a lemma that could belong anywhere, and firing on two
  texts that have nothing to do with each other.
  """
  use ExUnit.Case, async: true

  alias Pramana.Commentary

  describe "root coverage" do
    # `root_pct` is published as a percentage of the root, and summing span lengths
    # double-counts overlaps — so it could exceed 100%, which is not a coverage figure. It
    # did: 67 of 102 Tibetan pairs to a maximum of 1102%, and 4 of 184 Chinese pairs.
    test "never exceeds 100%, even when spans overlap heavily" do
      # A root whose every window is the same phrase repeated: the commentary's lemmas
      # match at many overlapping positions, which is what breaks the sum.
      root = String.duplicate("一二三四五六七八九十", 12)
      commentary = String.duplicate("一二三四五六七八九十", 12)

      spans = Commentary.spans(commentary, root)

      assert Commentary.covered_chars(spans) <= String.length(root)
    end

    test "two overlapping spans cover their union, not the sum of their lengths" do
      overlapping = [
        %{root_char_start: 0, root_char_end: 100},
        %{root_char_start: 50, root_char_end: 150}
      ]

      assert Commentary.covered_chars(overlapping) == 150
    end

    test "a span wholly inside another adds nothing" do
      nested = [
        %{root_char_start: 0, root_char_end: 100},
        %{root_char_start: 20, root_char_end: 40}
      ]

      assert Commentary.covered_chars(nested) == 100
    end

    test "disjoint spans are simply summed" do
      disjoint = [
        %{root_char_start: 0, root_char_end: 10},
        %{root_char_start: 90, root_char_end: 100}
      ]

      assert Commentary.covered_chars(disjoint) == 20
    end
  end

  describe "prepare_root/2" do
    @root "菩薩摩訶薩行深般若波羅蜜多時照見五蘊皆空度一切苦厄"
    @commentary "疏菩薩摩訶薩行深般若波羅蜜多時照見五蘊皆空度一切苦厄者總標也"

    # The expensive half of `spans/3` depends only on the root, and one run windows the
    # same root many times. This must be an optimisation and nothing else.
    test "a prepared root gives exactly the spans an unprepared one gives" do
      prepared = Commentary.prepare_root(@root)

      assert Commentary.spans(@commentary, @root, prepared_root: prepared) ==
               Commentary.spans(@commentary, @root)
    end

    # A prepared form of the WRONG text would align against the wrong work and nothing
    # downstream could detect it, so the body is checked before it is trusted. A stale
    # cache must be slow, never wrong.
    test "a prepared root for a different text is ignored, not used" do
      other = Commentary.prepare_root("諸行無常是生滅法生滅滅已寂滅為樂")

      assert Commentary.spans(@commentary, @root, prepared_root: other) ==
               Commentary.spans(@commentary, @root)
    end

    test "a prepared root built for a different window size is ignored too" do
      prepared = Commentary.prepare_root(@root, window: 4)

      assert Commentary.spans(@commentary, @root, prepared_root: prepared) ==
               Commentary.spans(@commentary, @root)
    end

    test "carries the root's own characters, so a lemma is cut by index and not by walking" do
      prepared = Commentary.prepare_root(@root)

      assert tuple_size(prepared.chars) == String.length(@root)
      assert prepared.body == @root
    end
  end

  describe "spans/3" do
    test "anchors a quoted lemma to the one place it occurs in the root" do
      root = "如是我聞一時佛在舍衛國祇樹給孤獨園與大比丘眾千二百五十人俱"
      commentary = "釋曰經云如是我聞一時佛在舍衛國者明信成就也"

      assert [span] = Commentary.spans(commentary, root)
      assert span.lemma =~ "如是我聞一時佛在舍衛國"

      assert String.slice(root, span.root_char_start, span.root_char_end - span.root_char_start) ==
               span.lemma
    end

    # The whole method in one test. A phrase appearing twice in the root cannot say which
    # occurrence a commentary is glossing, and picking one would be inventing an
    # alignment — the thing invariant #2 forbids in its own domain.
    test "refuses to anchor a lemma that occurs twice in the root" do
      repeated = "云何為二法所謂名色"
      root = repeated <> "中間隔開一段別的文字以免視窗重疊" <> repeated
      commentary = "論曰" <> repeated <> "者此明二法也"

      assert Commentary.spans(commentary, root) == []
    end

    test "collapses overlapping windows of one quotation into one span" do
      root = "菩薩摩訶薩行深般若波羅蜜多時照見五蘊皆空度一切苦厄"
      commentary = "疏菩薩摩訶薩行深般若波羅蜜多時照見五蘊皆空度一切苦厄者總標也"

      assert [span] = Commentary.spans(commentary, root)
      # One continuous quotation, not the twenty-odd overlapping 8-windows of it.
      assert span.root_char_end - span.root_char_start == String.length(root)
    end

    test "finds nothing between texts that share no long phrase" do
      assert Commentary.spans("一切有為法如夢幻泡影如露亦如電應作如是觀", "諸行無常是生滅法生滅滅已寂滅為樂") == []
    end

    # texts.body joins printed lines with newlines, and the break is typographic — the
    # edition prints no space, since classical Chinese has none. A lemma running across a
    # break is one lemma, and the first version of this stored it as two, each beginning
    # with the newlines it had matched on.
    test "matches across a printed line break as one lemma" do
      root = "菩薩摩訶薩\n行深般若波羅蜜多時\n照見五蘊皆空"
      commentary = "疏云菩薩摩訶薩行深般若波羅蜜多時照見五蘊皆空者"

      assert [span] = Commentary.spans(commentary, root)
      refute String.contains?(span.lemma, "\n\n")
      # The whole quotation, breaks and all, addressed as one contiguous range.
      assert String.slice(root, span.root_char_start, span.root_char_end - span.root_char_start) ==
               span.lemma

      assert span.lemma =~ "菩薩摩訶薩"
      assert span.lemma =~ "照見五蘊皆空"
    end

    test "returns spans in the commentary's own order" do
      root = "第一段文字甲乙丙丁戊己庚辛壬癸然後第二段文字子丑寅卯辰巳午未申酉"
      commentary = "先釋第二段文字子丑寅卯辰巳午未申酉後釋第一段文字甲乙丙丁戊己庚辛壬癸"

      starts = Commentary.spans(commentary, root) |> Enum.map(& &1.commentary_char_start)
      assert starts == Enum.sort(starts)
      assert length(starts) == 2
    end
  end

  describe "the density floor" do
    test "is stated in the module rather than buried in a task" do
      # 28.4 is the highest density reached by any of 120 pairs built from a commentary
      # and a root it does not explain. The floor was 25 for an afternoon, calibrated
      # against a 40-pair null set whose maximum nobody had looked at.
      assert Commentary.min_density() > 28.4,
             "the floor must sit above the observed null MAXIMUM, not its p90"

      assert Commentary.window() == 8
    end
  end

  # The measured separation between asserted and unrelated pairs is NOT asserted here.
  # It needs the baked corpus, and the test database holds no corpus — a test that can
  # only run somewhere else is a test that reads as green while asserting nothing, which
  # `test_helper.exs` already refuses for the `:corpus` tag. `mix pramana.commentary.align`
  # prints those numbers on every run, which is where they can be re-checked against real
  # texts rather than against a fixture that would have to be maintained to keep agreeing
  # with them.
end
