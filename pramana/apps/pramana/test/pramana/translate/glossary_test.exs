defmodule Pramana.Translate.GlossaryTest do
  @moduledoc """
  The pinned term table, and the filters that decide what is allowed to be a pin.

  Every one of these filters was written after looking at what the unfiltered table
  produced. A glossary is a reference work, not a style guide: most of what it holds
  explains a term rather than renders it, and pinning an explanation into a prompt is
  worse than pinning nothing at all.
  """
  use Pramana.DataCase, async: true

  alias Pramana.Corpus.GlossaryEntry
  alias Pramana.Repo
  alias Pramana.Translate.Glossary

  setup do
    Repo.insert!(%Pramana.Corpus.Source{
      id: "dila-glossaries",
      name: "DILA glossaries",
      license_spdx: "CC-BY-4.0",
      license_class: "cc-by",
      commercial_use: true,
      redistributable: true
    })

    :ok
  end

  defp entry!(attrs) do
    Repo.insert!(
      struct(
        GlossaryEntry,
        Map.merge(
          %{source_id: "dila-glossaries", gloss_id: "g#{System.unique_integer([:positive])}"},
          attrs
        )
      )
    )
  end

  describe "table/0" do
    test "keeps a term-like rendering" do
      entry!(%{chinese: "四念處", english: "four applications of mindfulness"})

      assert {"四念處", "four applications of mindfulness"} in Glossary.table()
    end

    test "drops a definition, which is what most entries are" do
      # Real shapes from `glossary_entries`. Pinning any of these tells the model to write
      # a dictionary entry where a translation belongs.
      entry!(%{chinese: "娑婆世界", english: "a transliteration of Sabhā, the world we live in"})
      entry!(%{chinese: "孫陀羅難陀", english: "name of a disciple of the Buddha"})
      entry!(%{chinese: "隨意所欲", english: "according to one’s wish, as one likes it"})

      assert Glossary.table() == []
    end

    test "drops two-character terms, where the function words are" do
      # `云何` is "how" or "what is" at least as often as "why", and `比丘` rendered as
      # `bhikṣu` moves the English away from the "monk" a reader would type.
      entry!(%{chinese: "云何", english: "why?"})
      entry!(%{chinese: "比丘", english: "bhikṣu"})

      assert Glossary.table() == []
    end

    test "resolves a contested term to its most frequent rendering" do
      for _ <- 1..3, do: entry!(%{chinese: "四聖諦", english: "four noble truths"})
      entry!(%{chinese: "四聖諦", english: "truths of the noble ones"})

      assert {"四聖諦", "four noble truths"} in Glossary.table()
      refute Enum.any?(Glossary.table(), &match?({"四聖諦", "truths of the noble ones"}, &1))
    end

    test "orders longest first, so a compound wins over its own parts" do
      entry!(%{chinese: "四無量心", english: "four immeasurable minds"})
      entry!(%{chinese: "無量心", english: "immeasurable mind"})

      assert [{"四無量心", _}, {"無量心", _}] = Glossary.table()
    end
  end

  describe "pins_for/2" do
    @table [
      {"四無量心", "four immeasurable minds"},
      {"四念處", "four applications of mindfulness"},
      {"無量心", "immeasurable mind"}
    ]

    test "pins only terms the passage actually contains" do
      assert Glossary.pins_for("修四念處者", @table) == [
               {"四念處", "four applications of mindfulness"}
             ]
    end

    test "does not pin a term inside a term it already pinned" do
      # Both `四無量心` and `無量心` match this passage. Pinning both hands the model two
      # instructions for one span, and they do not agree.
      assert Glossary.pins_for("修四無量心", @table) == [{"四無量心", "four immeasurable minds"}]
    end

    test "a passage with no listed term pins nothing" do
      assert Glossary.pins_for("如是我聞一時佛住", @table) == []
    end
  end

  describe "instruction/2" do
    test "names each pinned term and asks for the translation only" do
      instruction = Glossary.instruction("修四念處者", [{"四念處", "four applications of mindfulness"}])

      assert instruction =~ "四念處 = four applications of mindfulness"
      assert instruction =~ "translation only"
    end

    test "is nil when nothing is pinned, so the prompt matches an unpinned run exactly" do
      # If a passage with no terms still got a preamble, the A/B would be measuring the
      # preamble rather than the terms.
      assert Glossary.instruction("如是我聞", [{"四念處", "x"}]) == nil
    end
  end
end
