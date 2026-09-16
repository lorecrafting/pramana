defmodule Pramana.TranslatorsAttestedTest do
  @moduledoc """
  Comparing two translators from a philologist's glossary rather than from n-gram rates.

  The join is the whole risk. Two glossaries agree on a Sanskrit headword only after that
  headword has been normalised, and a normaliser that collapses too much invents
  divergences between terms that were never the same word.
  """
  use Pramana.DataCase, async: false

  alias Pramana.Corpus.GlossaryEntry
  alias Pramana.Corpus.Source
  alias Pramana.Repo
  alias Pramana.Translators

  defp entry(glossary, chinese, sanskrit) do
    now = DateTime.utc_now()

    Repo.insert!(%GlossaryEntry{
      source_id: "test-glossaries",
      gloss_id: "#{glossary}:#{chinese}",
      chinese: chinese,
      sanskrit: sanskrit,
      english: "x",
      meta: %{"glossary" => glossary},
      inserted_at: now,
      updated_at: now
    })
  end

  setup do
    Repo.insert!(%Source{
      id: "test-glossaries",
      name: "test",
      tradition: "reference",
      license_spdx: "CC0-1.0",
      license_class: "cc0",
      commercial_use: true,
      redistributable: true
    })

    :ok
  end

  test "a Sanskrit headword both glossed, rendered differently, is a divergence" do
    entry("a", "增上慢", "adhimāna-prāpta~")
    entry("b", "貢高", "adhimāna-prāpta~")

    assert %{shared: 1, diverged: 1, agreed: 0, examples: [example]} =
             Translators.attested("a", "b", source: "test-glossaries")

    assert example.sanskrit == "adhimāna-prāpta"
    assert example.a == "增上慢"
    assert example.b == "貢高"
  end

  # AGREEMENT IS THE DENOMINATOR. Much of this vocabulary was settled before either
  # translator was born, and a divergence count quoted without it says nothing.
  test "the same rendering on both sides is agreement, and is counted" do
    entry("a", "涅槃", "nirvāṇa~")
    entry("b", "涅槃", "nirvāṇa")

    assert %{shared: 1, agreed: 1, diverged: 0} =
             Translators.attested("a", "b", source: "test-glossaries")
  end

  test "a term only one of them glossed is not a comparison" do
    entry("a", "方便", "upāyakauśalya~")
    entry("b", "涅槃", "nirvāṇa~")

    assert %{shared: 0, diverged: 0, terms_a: 1, terms_b: 1} =
             Translators.attested("a", "b", source: "test-glossaries")
  end

  describe "normalize_sanskrit/1" do
    test "drops the stem marker, the variant reading and the edge hyphens" do
      assert Translators.normalize_sanskrit("apasmāraka~ (v.l. apasmāra-rūpa~)") ==
               "apasmāraka"

      assert Translators.normalize_sanskrit("Sukha-vihāra-") == "sukha-vihāra"
      assert Translators.normalize_sanskrit("  Avīci  ") == "avīci"
    end

    # UNDER-JOINING IS THE SAFE DIRECTION. Two entries differing in an elided middle stay
    # separate, which loses a comparison; collapsing them would invent one.
    test "an elision is not collapsed away" do
      refute Translators.normalize_sanskrit("arjakasya ... mañjarī") ==
               Translators.normalize_sanskrit("arjakasya")
    end
  end

  # Karashima writes `***` where the witness is illegible. Joining on it paired terms that
  # have nothing to do with each other, and the first divergence this module ever reported
  # was `***` against `***` — two unread words agreeing that neither could be read.
  test "an illegible witness is not a headword to join on" do
    entry("a", "畢力迦", "***")
    entry("b", "將順", "***")

    assert %{shared: 0} = Translators.attested("a", "b", source: "test-glossaries")
  end
end
