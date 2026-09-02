defmodule Pramana.SourcesTest do
  @moduledoc """
  The tradition axis on the source registry.

  This exists because `Pramana.Retrieval.Semantic` kept its own copy of the mapping and
  it listed 4 of the 8 registered sources. A source in no group is not ranked lower under
  `per_tradition: true` — it is never queried at all, so it returns nothing and says
  nothing, which is the shape of absence this project refuses everywhere else.
  """
  use ExUnit.Case, async: true

  alias Pramana.Sources

  describe "every source declares which canon it belongs to" do
    test "no registered source is left out of a tradition" do
      grouped = Sources.by_tradition() |> Map.values() |> List.flatten() |> Enum.sort()

      assert grouped == Enum.sort(Sources.ids()),
             "a registered source belongs to no tradition, so per_tradition search " <>
               "will never query it: #{inspect(Sources.ids() -- grouped)}"
    end

    # Written out in full rather than counted, so ADDING a source has to be a deliberate
    # edit here. `sc-data` and `sc-translations` are separate entries for the same
    # repository, exactly as `84000` and `84000-rdf` are: same upstream, different
    # licences, and one entry would have to state the weakest of them about all three.
    test "the canons are the three the corpus holds, plus reference data that is none of them" do
      assert Sources.by_tradition() == %{
               # `sc-lzh` is bilara-data's Chinese half, and it is filed by the CANON it
               # transmits rather than by the repository it came from. SuttaCentral is
               # mostly Pāli; `root/lzh/sct` is the Chinese Āgamas, and a per-tradition
               # search for the Chinese canon that skipped it would skip the only English
               # route into the Taishō.
               "chinese" => ["cbeta", "sat", "sc-lzh"],
               "pali" => ["sc", "sc-data", "sc-translations"],
               "tibetan" => ["84000", "84000-rdf", "bdrc-derge", "derge", "derge-tengyur"],
               # NOT a canon. DILA's authority databases describe people who appear across
               # all three — a translator is not Chinese material because his bylines are —
               # so grouping them under any canon would make `per_tradition` search
               # reference data as though it were scripture.
               #
               # `sat-teihon` is here for the same reason and a sharper one: it is a survey
               # of the manuscripts SAT edited the Japanese-composed section FROM, for 144
               # of the 547 works this corpus cannot show at all. It describes texts that
               # are absent. Filing it under "chinese" would let a per-tradition search
               # return bibliography where a reader asked for scripture.
               # `dila-glossaries` is here rather than under `chinese` because a
               # dictionary describes words, not a canon — and because the Mahāvyutpatti
               # inside it bridges Sanskrit, Chinese and Tibetan, so any one canon would
               # be wrong about part of the source.
               "reference" => ["dila-authority", "dila-glossaries", "sat-teihon"]
             }
    end

    # The case that motivated all of this: `sat` is registered, blocked on acquisition
    # (#14), and was absent from the hand-written map. It has to be grouped BEFORE the
    # text arrives, because the day it arrives nothing will fail to point this out.
    test "sat is grouped with the Chinese canon before its text exists" do
      assert Sources.tradition("sat") == "chinese"
    end

    # Origin is where a text was composed; tradition is which collection transmits it.
    # Taishō 56–84 are Japanese-composed works in the Chinese canon, and the Pāli and
    # Tibetan canons are both `indic` in origin, so neither direction of substitution
    # works.
    test "tradition is not composition_origin" do
      assert Sources.tradition("sc") != Sources.tradition("derge")
      assert Sources.tradition("sat") == Sources.tradition("cbeta")
    end
  end

  describe "locally-added texts" do
    test "an unregistered id becomes its own tradition rather than nil or a guess" do
      assert Sources.tradition("local-huangnianzu") == "local-huangnianzu"
    end

    test "a local id is never folded into a canon it was not declared part of" do
      refute Sources.tradition("local-anything") in Map.keys(Sources.by_tradition())
    end
  end
end
