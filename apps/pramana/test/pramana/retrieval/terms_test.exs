defmodule Pramana.Retrieval.TermsTest do
  @moduledoc """
  Query-side English→Chinese doctrinal term expansion.

  Measured verdict: the MECHANISM works and the TERM SOURCE does not carry it. Enabling
  this moved `topical/chinese` 0% → 16.7% (2/12) while `answered from any tradition` went
  72.7% → 63.6%, so it stays opt-in and off. The tests below pin behaviour, not a win.
  """
  use Pramana.DataCase, async: true

  alias Pramana.Corpus.Loader
  alias Pramana.Retrieval.Terms

  setup do
    # Through the loader, so the row matches `Pramana.Sources` rather than a literal
    # invented here — rule 12: a test that hardcodes a value the registry owns will fight
    # the registry the next time a licence is corrected.
    Loader.ensure_source!("84000")
    :ok
  end

  defp glossary!(english, chinese) do
    Pramana.Repo.insert_all("glossary_entries", [
      %{
        source_id: "84000",
        gloss_id: "test-#{System.unique_integer([:positive])}",
        english: english,
        chinese: chinese,
        inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
        updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
      }
    ])

    :ok
  end

  describe "expand/1" do
    test "maps an English doctrinal term to the Chinese the canon prints" do
      glossary!("four noble truths", "四聖諦")

      assert Terms.expand("What are the four noble truths?") == ["四聖諦"]
    end

    test "returns EVERY attested register, which is the argument for a glossary" do
      # A translation model must gamble on one rendering, and choosing the register this
      # corpus does not print costs ~50 points (measured: 91.7% -> 41.7%). A glossary can
      # expand to both and let the index decide.
      glossary!("applications of mindfulness", "念處")
      glossary!("applications of mindfulness", "念住")

      expanded = Terms.expand("How are the applications of mindfulness taught?")

      assert "念處" in expanded
      assert "念住" in expanded
    end

    test "a Chinese query is left alone" do
      glossary!("four noble truths", "四聖諦")

      # The corpus already answers its own language at mean rank 1.25. Expanding here
      # would add nothing and could only add noise.
      assert Terms.expand("何謂四聖諦？") == []
    end

    test "prefers the maximal headword over one contained in it" do
      # `dependent` maps to 依他起[相], an unrelated Yogācāra term, and would ride along on
      # any question about dependent origination if generic matches were kept.
      glossary!("twelve links of dependent origination", "十二因緣")
      glossary!("dependent origination doctrine", "緣起")

      expanded = Terms.expand("What are the twelve links of dependent origination?")

      assert "十二因緣" in expanded
    end

    test "a paraphrase naming no term expands to nothing" do
      # THE KNOWN LIMIT, pinned so it is not mistaken for a bug. A glossary fires on
      # vocabulary; a question that names no doctrinal term gets nothing from it. This is
      # why glossary expansion cannot replace query translation — measured directly:
      # "What are the 4 things the buddha said when he was enlightened" expands to [] and
      # never reaches 四聖諦, while the semantic arm answers it correctly from the Pāli.
      glossary!("four noble truths", "四聖諦")

      assert Terms.expand("What are the 4 things the buddha said when he was enlightened") == []
    end

    test "a short generic headword does not fire" do
      # `god`, `path`, `mind` appear inside unrelated questions, and a precision failure
      # here is invisible to the reader — the same reasoning Variants uses to exclude
      # kSemanticVariant.
      glossary!("god", "天")

      assert Terms.expand("What is the goddess of the mountain?") == []
    end

    test "handles a non-binary query without raising" do
      assert Terms.expand(nil) == []
    end
  end
end
