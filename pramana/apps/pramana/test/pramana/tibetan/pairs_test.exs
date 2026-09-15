defmodule Mix.Tasks.Pramana.Tibetan.PairsTest do
  @moduledoc """
  The training set for a Tibetan embedder.

  A pair that is not really parallel teaches the model something false, and unlike a bad
  citation nothing downstream will flag it. So the filters are the substance here.
  """
  use ExUnit.Case, async: true

  alias Mix.Tasks.Pramana.Tibetan.Pairs

  describe "which pairs are usable" do
    test "a proportionate pair is kept" do
      # The real distribution: folio-level en/bo runs about 1.14.
      assert Pairs.usable?(%{
               bo: String.duplicate("ཆོས་", 60),
               en: String.duplicate("dharma ", 40)
             })
    end

    test "a pair whose sides are wildly disproportionate is refused" do
      # Not a translation of that folio — an alignment error. Keeping it would teach the
      # model that a long passage and a fragment mean the same thing.
      long = String.duplicate("ཆོས་", 400)

      refute Pairs.usable?(%{bo: long, en: "Chapter 1."})
      refute Pairs.usable?(%{bo: "ཆོས་ཉིད", en: String.duplicate("dharma ", 400)})
    end

    test "a fragment on either side is refused" do
      # Below the floor a "rendering" is a heading or a folio marker, not a translation.
      refute Pairs.usable?(%{bo: "ཆོས", en: "The"})
      refute Pairs.usable?(%{bo: "", en: ""})
    end
  end
end
