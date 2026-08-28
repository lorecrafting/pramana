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

  alias Pramana.Corpus.Text
  alias Pramana.Corpus.Work
  alias Pramana.Repo
  alias Pramana.Translators

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
end
