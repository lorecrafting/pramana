defmodule Pramana.TranslatorsTest do
  @moduledoc """
  The lexical choices two translators made for the same Indic original.

  The tests that matter are about the confound, not the arithmetic. Punctuation dominated
  every result until it was stripped — CBETA's punctuation is a modern editorial addition
  and not in the witness, so a punctuation difference between two editions is the *editor's*
  and never the translator's. With it in, the top results for T0099 against T0100 were
  `？謂`, `、苦`, `、鼻`, `、舌`. With it out they are 入處, 覺分, 緣生, 道跡.
  """
  use Pramana.DataCase, async: true

  import Ecto.Query

  alias Pramana.Corpus.GlossaryEntry
  alias Pramana.Corpus.Source
  alias Pramana.Corpus.Text
  alias Pramana.Corpus.Work
  alias Pramana.Corpus.WorkRelation
  alias Pramana.Repo
  alias Pramana.Translators

  doctest Pramana.Translators

  defp work!(id, body) do
    Repo.insert!(%Work{id: id, title: id})
    Repo.insert!(%Pramana.Corpus.Witness{id: "w-#{id}", name: "w"})

    Repo.insert!(%Pramana.Corpus.Source{
      id: "s-#{id}",
      name: "s",
      license_spdx: "CC0-1.0",
      license_class: "cc0",
      commercial_use: true,
      redistributable: true
    })

    Repo.insert!(%Text{
      work_id: id,
      witness_id: "w-#{id}",
      source_id: "s-#{id}",
      urn_prefix: "pramana:s.w:#{id}",
      body: body,
      body_sha256: "x",
      meta: %{}
    })
  end

  describe "preferences/3" do
    test "finds a term one translation uses and the other does not" do
      work!("A", String.duplicate("入處者謂眼入處", 20))
      work!("B", String.duplicate("諸入者謂眼根也", 20))

      {:ok, [top | _]} = Translators.preferences("A", "B", min_count: 5)

      assert top.term == "入處"
      assert top.other_count == 0
    end

    # THE CONFOUND. CBETA punctuation is the editor's, not the translator's, and comparing
    # two editions on it reports an editorial decision as a lexical one.
    test "ignores punctuation entirely" do
      work!("A", String.duplicate("眼、耳、鼻、舌，身。", 20))
      work!("B", String.duplicate("眼耳鼻舌身", 20))

      {:ok, prefs} = Translators.preferences("A", "B", min_count: 5)

      # Identical vocabulary, differently punctuated. Every term therefore appears in both
      # at the same rate — skew 1.0, which is the shape of "no preference". An empty list
      # would be the wrong assertion: the terms are there, they are simply not skewed.
      assert prefs != []
      assert Enum.all?(prefs, &(&1.skew == 1.0)), "punctuation must not create a preference"

      # And specifically: nothing containing punctuation survives to be compared.
      refute Enum.any?(prefs, &String.contains?(&1.term, ["、", "，", "。"]))
    end

    # The two works are different lengths — T0099 is 1.7x T0100 — and comparing raw counts
    # would report that difference as a preference of the longer one.
    test "compares rates, not counts, so length is not a preference" do
      work!("A", String.duplicate("如是我聞", 100))
      work!("B", String.duplicate("如是我聞", 20))

      {:ok, prefs} = Translators.preferences("A", "B", min_count: 5)

      assert Enum.all?(prefs, &(&1.skew < 2.0)),
             "same vocabulary at 5x the length must not read as a preference"
    end

    test "returns the counts, so a reader can see what they are looking at" do
      work!("A", String.duplicate("入處者謂眼入處", 20))
      work!("B", String.duplicate("諸入者謂眼根也", 20))

      {:ok, [top | _]} = Translators.preferences("A", "B", min_count: 5)

      assert top.count > 0
      assert is_float(top.rate) and is_float(top.other_rate)
    end

    test "is not_found rather than empty for a work that is not here" do
      work!("A", "入處")
      assert Translators.preferences("A", "nope") == {:error, :not_found}
      assert Translators.preferences("nope", "A") == {:error, :not_found}
    end
  end

  describe "normalize_sanskrit/1" do
    test "normalizes parenthesized variants, tildes, dashes, and whitespace" do
      assert Translators.normalize_sanskrit("apasmāraka~ (v.l. apasmāra-rūpa~)") == "apasmāraka"
      assert Translators.normalize_sanskrit("Sukha-vihāra-") == "sukha-vihāra"
      assert Translators.normalize_sanskrit("  -Dharma-  ") == "dharma"
    end
  end

  describe "attested/3" do
    test "compares lexical choices for shared Sanskrit headwords across glossaries" do
      Repo.insert!(%Source{
        id: "dila-glossaries",
        name: "dila",
        license_spdx: "CC0-1.0",
        license_class: "cc0",
        commercial_use: true,
        redistributable: true
      })

      # Entry 1: Agreed headword, brackets stripped
      Repo.insert!(%GlossaryEntry{
        gloss_id: "g1",
        source_id: "dila-glossaries",
        sanskrit: "prajñā",
        chinese: "[智慧]",
        meta: %{"glossary" => "g_a"}
      })

      Repo.insert!(%GlossaryEntry{
        gloss_id: "g2",
        source_id: "dila-glossaries",
        sanskrit: "prajñā",
        chinese: "智慧",
        meta: %{"glossary" => "g_b"}
      })

      # Entry 2: Diverged headword
      Repo.insert!(%GlossaryEntry{
        gloss_id: "g3",
        source_id: "dila-glossaries",
        sanskrit: "sukhavatī",
        chinese: "安樂",
        meta: %{"glossary" => "g_a"}
      })

      Repo.insert!(%GlossaryEntry{
        gloss_id: "g4",
        source_id: "dila-glossaries",
        sanskrit: "sukhavatī",
        chinese: "極樂",
        meta: %{"glossary" => "g_b"}
      })

      # Entry 3: Illegible witness mark skipped
      Repo.insert!(%GlossaryEntry{
        gloss_id: "g5",
        source_id: "dila-glossaries",
        sanskrit: "***",
        chinese: "空",
        meta: %{"glossary" => "g_a"}
      })

      result = Translators.attested("g_a", "g_b", source: "dila-glossaries")

      assert result.terms_a == 2
      assert result.terms_b == 2
      assert result.shared == 2
      assert result.agreed == 1
      assert result.diverged == 1
      assert [%{sanskrit: "sukhavatī", a: "安樂", b: "極樂"}] = result.examples
    end
  end

  describe "compare_hands/3" do
    test "returns error when no shared parallel exists between authorities" do
      assert Translators.compare_hands("A000001", "A000002") == {:error, :no_shared_parallel}
    end

    test "finds preferences across works connected by parallel_of" do
      work!("W1", String.duplicate("入處者謂眼入處", 20))
      work!("W2", String.duplicate("諸入者謂眼根也", 20))

      Repo.update_all(from(w in Work, where: w.id == "W1"), set: [authority_id: "AUTH_1"])
      Repo.update_all(from(w in Work, where: w.id == "W2"), set: [authority_id: "AUTH_2"])

      %WorkRelation{}
      |> WorkRelation.changeset(%{
        source_work_id: "W1",
        target_work_id: "W2",
        relation: "parallel_of",
        method: "manifest",
        confidence: "certain"
      })
      |> Repo.insert!()

      {:ok, %{pairs: pairs, preferences: [top | _]}} =
        Translators.compare_hands("AUTH_1", "AUTH_2", min_count: 5)

      assert pairs == [{"W1", "W2"}]
      assert top.term == "入處"
      assert top.other_count == 0
    end
  end
end
