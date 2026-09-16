defmodule Pramana.Readings.BuildTest do
  @moduledoc """
  The derivation, and specifically its four rejections.

  What the dictionary *contains* is only half of what makes it trustworthy; the other
  half is what it refuses to contain. Each filter here throws away a different kind of
  wrong answer, and each was added because the unfiltered output contained that answer.
  """
  use ExUnit.Case, async: true

  alias Pramana.Readings.Build

  # Real Unihan lines, in the format the file actually uses.
  @unihan_lines [
    "U+4F5B\tkMandarin\tfú\n",
    "U+4F5B\tkHanyuPinyin\t50262.030:fó,fú,bì,bó\n",
    "U+822C\tkMandarin\tbān\n",
    "U+822C\tkHanyuPinyin\t53057.080:pán,bān,bǎn,bō\n",
    "U+82E5\tkMandarin\truò\n",
    "U+82E5\tkXHC1983\t0957.010:rě 0978.040:ruò\n",
    "U+8449\tkMandarin\tyè\n",
    "U+8449\tkHanyuPinyin\t53243.150:yè,shè\n",
    "U+8B58\tkMandarin\tshí\n",
    "U+77E5\tkMandarin\tzhī\n",
    "U+8AAA\tkMandarin\tshuō\n"
  ]

  defp unihan, do: Build.unihan(@unihan_lines)

  describe "unihan" do
    test "kMandarin gives the preferred reading" do
      assert unihan()["佛"].preferred == "fú"
    end

    test "the attested set is the union across every reading field" do
      # This is the finding the whole task rests on: the Buddhist readings ARE in
      # Unicode. 佛 is listed as fó — just not in the one field a generic library reads.
      assert MapSet.member?(unihan()["佛"].attested, "fó")
      assert MapSet.member?(unihan()["葉"].attested, "shè")
      assert MapSet.member?(unihan()["般"].attested, "bō")
      assert MapSet.member?(unihan()["若"].attested, "rě")
    end

    test "the preferred reading is itself attested" do
      for {_char, %{preferred: preferred, attested: attested}} <- unihan() do
        assert MapSet.member?(attested, preferred)
      end
    end
  end

  describe "cedict" do
    test "splits singles from compounds and flags context-bound glosses" do
      {singles, compounds} =
        Build.cedict([
          "般 般 [ban1] /sort/kind/class/\n",
          "般 般 [bo1] /used in 般若[bo1 re3]/\n",
          "般若 般若 [bo1 re3] /(Buddhism) wisdom/\n"
        ])

      assert [{%{reading: "bān"}, false}, {%{reading: "bō"}, true}] = singles["般"]
      assert [%{form: "般若", reading: "bō rě"}] = compounds
    end

    test "skips a line whose syllable count does not match its characters" do
      # Without this the zip is misaligned and every character is credited with another
      # character's reading.
      {singles, compounds} = Build.cedict(["般若 般若 [bo1] /malformed/\n"])
      assert singles == %{}
      assert compounds == []
    end

    test "skips non-Han entries" do
      {singles, compounds} = Build.cedict(["3Q 3Q [san1 Q] /thank you/\n"])
      assert singles == %{}
      assert compounds == []
    end
  end

  describe "the four filters" do
    defp exceptions(cedict_lines) do
      Build.exceptions(unihan(), Build.cedict(cedict_lines), fn _ -> true end)
    end

    test "1. a polyphonic character is skipped, not resolved" do
      result =
        exceptions([
          "說 說 [shuo1] /to speak/\n",
          "說 說 [shui4] /to persuade/\n"
        ])

      assert result.rejected.polyphonic == 1
      assert result.exceptions == []
    end

    test "1. a character whose OTHER reading is context-bound is still usable" do
      # 佛 survives where 說 does not: CC-CEDICT glosses fu2 as "used in 仿佛", which is a
      # fact about one word rather than about the character.
      result =
        exceptions([
          "佛 佛 [Fo2] /Buddha/\n",
          "佛 佛 [fu2] /used in 仿佛[fang3 fu2]/\n"
        ])

      assert [%{form: "佛", reading: "fó", naive: "fú"}] = result.exceptions
    end

    test "2. a neutral-tone-only divergence is rejected" do
      result = exceptions(["知識 知识 [zhi1 shi5] /knowledge/\n"])

      assert result.rejected.neutral_tone == 1
      assert result.exceptions == []
    end

    test "3. a syllable Unihan does not attest is rejected" do
      result = exceptions(["般若 般若 [ban1 zzz1] /nonsense/\n"])

      assert result.rejected.unattested == 1
      assert result.exceptions == []
    end

    test "4. the occurrence filter drops forms the corpus never uses" do
      result =
        Build.exceptions(
          unihan(),
          Build.cedict(["般若 般若 [bo1 re3] /(Buddhism) wisdom/\n"]),
          fn _form -> false end
        )

      assert result.exceptions == []
    end

    test "a genuine Buddhist exception survives all four" do
      result = exceptions(["般若 般若 [bo1 re3] /(Buddhism) wisdom; prajñā/\n"])

      assert [%{form: "般若", reading: "bō rě", naive: "bān ruò", buddhist?: true}] =
               result.exceptions
    end

    test "a compound that agrees with the naive reading is not an exception" do
      # 波羅蜜 needs no help. Recording it would be noise the lookup has to filter, and
      # would overstate how much of the corpus this layer is doing work on.
      result = exceptions(["說說 说说 [shuo1 shuo1] /to talk/\n"])
      assert result.exceptions == []
    end
  end

  describe "attested?" do
    test "accepts readings assembled from what Unihan records" do
      assert Build.attested?(unihan(), "般若", "bō rě")
      assert Build.attested?(unihan(), "佛", "fó")
    end

    test "rejects an unrecorded syllable" do
      refute Build.attested?(unihan(), "般若", "bān zzz")
    end

    test "rejects a character Unihan has never heard of" do
      refute Build.attested?(unihan(), "龘", "dá")
    end

    test "rejects a syllable count that does not match" do
      refute Build.attested?(unihan(), "般若", "bō")
    end
  end
end
