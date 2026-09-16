defmodule Pramana.GlossaryTest do
  @moduledoc """
  Pinned term renderings, imported from a hand-built translation glossary.

  The mapping is the least interesting part. These tests are mostly about the three
  things that make the import worth doing at all: the reasoning is preserved verbatim,
  rejected renderings are extracted (**a decision recorded is not a decision applied**),
  and a reading that could not be verified is representable rather than silently absent.
  """
  use Pramana.DataCase, async: true

  alias Pramana.Glossary

  @markdown """
  # Glossary — 測試

  Preamble prose that is not a table.

  ## People

  | Chinese | Pinyin | Canonical English | Notes |
  |---|---|---|---|
  | 道隱 | — | Master Dōin (道隱) | Japanese. Author of the *Discerning Commentary*. **Not** "Daoyin" — swept 2026-08-06. |
  | 日溪 | Rìxī | Master Rixi (日溪) | Japanese, but **reading unverified** — pinyin retained rather than inventing a reading. |
  | 元曉 | — | Master Wŏnhyo (元曉) | Korean (Silla), not Japanese. |
  | 黃念祖 | Huáng Niànzǔ | Huang Nianzu | Author of the commentary. |

  ## Core doctrinal terms

  | Chinese | Pinyin | Canonical English | Notes |
  |---|---|---|---|
  | 無量 | wúliàng | measureless | **Not** "immeasurable" — swept. |
  | 實相 | shíxiàng | ultimate reality | |

  ## Open questions

  | Chinese | Context first seen | Status |
  |---|---|---|
  | 際 family (實際 / 本際) | `ch01.md` | RESOLVED — render 際 as "limit". |
  """

  describe "parse/1" do
    test "reads terms out of every table" do
      terms = Glossary.parse(@markdown)
      assert length(terms) == 6
      assert "道隱" in Enum.map(terms, & &1.term)
      assert "無量" in Enum.map(terms, & &1.term)
    end

    test "takes the section heading as the category, without its markdown prefix" do
      terms = Glossary.parse(@markdown)
      by_term = Map.new(terms, &{&1.term, &1})

      assert by_term["道隱"].category == "People"
      assert by_term["無量"].category == "Core doctrinal terms"
    end

    test "skips Open questions, which is keyed by topic rather than by term" do
      # "際 family (實際 / 本際)" is a discussion thread. Importing it would put an entry
      # in the glossary that no lookup could match and that a compliance check would then
      # treat as canonical.
      terms = Glossary.parse(@markdown)
      refute Enum.any?(terms, &String.contains?(&1.term, "family"))
    end

    test "skips header and separator rows" do
      terms = Glossary.parse(@markdown)
      refute Enum.any?(terms, &(&1.term == "Chinese"))
      refute Enum.any?(terms, &String.starts_with?(&1.term, "-"))
    end

    test "keeps the notes verbatim, because the reasoning is the valuable part" do
      term = Glossary.parse(@markdown) |> Enum.find(&(&1.term == "道隱"))

      assert term.notes =~ "swept 2026-08-06"
      assert term.notes =~ "Discerning Commentary"
    end

    test "treats an em dash as an absent pinyin rather than a value" do
      term = Glossary.parse(@markdown) |> Enum.find(&(&1.term == "道隱"))
      assert term.pinyin == nil
    end
  end

  describe "rejected renderings" do
    test "extracts the forms the glossary explicitly refuses" do
      # A decision recorded is not a decision applied: knowing 道隱 must not be "Daoyin"
      # is what lets a checker find the places still saying it.
      term = Glossary.parse(@markdown) |> Enum.find(&(&1.term == "道隱"))
      assert term.rejected_forms == ["Daoyin"]
    end

    test "a term with no rejection has an empty list, not nil" do
      term = Glossary.parse(@markdown) |> Enum.find(&(&1.term == "實相"))
      assert term.rejected_forms == []
    end
  end

  describe "reading status" do
    test "an unverified reading is recorded, not dropped" do
      term = Glossary.parse(@markdown) |> Enum.find(&(&1.term == "日溪"))

      assert term.reading_status == "unverified"
      # The pinyin is kept precisely because the Japanese reading is unknown.
      assert term.pinyin == "Rìxī"
    end

    test "silence is never read as verification" do
      # Absence of the phrase means "no reading question here", not "someone checked".
      term = Glossary.parse(@markdown) |> Enum.find(&(&1.term == "黃念祖"))
      assert term.reading_status == "not_applicable"
    end
  end

  describe "language origin" do
    test "is taken only from an explicit statement" do
      by_term = Glossary.parse(@markdown) |> Map.new(&{&1.term, &1})

      assert by_term["道隱"].language_origin == "japanese"
      assert by_term["元曉"].language_origin == "korean"
    end

    test "is nil when the notes do not say, rather than guessed from the characters" do
      # Which reading tradition a name belongs to is exactly what the characters cannot
      # tell you — 元曉 is Korean, not Japanese, and nothing in the glyphs says so.
      by_term = Glossary.parse(@markdown) |> Map.new(&{&1.term, &1})

      assert by_term["黃念祖"].language_origin == nil
      assert by_term["實相"].language_origin == nil
    end
  end

  describe "import/2 and queries" do
    setup do
      Pramana.Repo.insert!(%Pramana.Corpus.Source{
        id: "local-test",
        name: "test",
        license_class: "restricted",
        redistributable: false
      })

      {:ok, _} = Glossary.import("local-test", Glossary.parse(@markdown))
      :ok
    end

    test "stores every term against its source" do
      assert length(Glossary.for_source("local-test")) == 6
    end

    test "is idempotent — re-importing converges rather than duplicating" do
      {:ok, _} = Glossary.import("local-test", Glossary.parse(@markdown))
      assert length(Glossary.for_source("local-test")) == 6
    end

    test "looks up a pinned rendering" do
      assert Glossary.lookup("local-test", "元曉").canonical_english == "Master Wŏnhyo (元曉)"
      assert Glossary.lookup("local-test", "不存在") == nil
    end

    test "surfaces unverified readings on their own" do
      assert [term] = Glossary.unverified_readings("local-test")
      assert term.term == "日溪"
    end

    test "returns rejected renderings as term/form pairs, ready for a compliance check" do
      pairs = Glossary.rejected_forms("local-test")

      assert {"道隱", "Daoyin"} in pairs
      assert {"無量", "immeasurable"} in pairs
    end

    test "stats count what a reviewer needs to see" do
      stats = Glossary.stats("local-test")

      assert stats.total == 6
      assert stats.unverified_readings == 1
      assert stats.with_rejected_forms == 2
      assert stats.by_language_origin == %{"japanese" => 2, "korean" => 1}
    end
  end
end
