defmodule Pramana.ApparatusTest do
  @moduledoc """
  Where the witnesses disagree, and who exactly disagrees.

  The property that carries the weight is attribution. A variant reading is only worth
  shipping if the witness attached to it is the right one, and CBETA's witness ids are
  declared per file: `wit1` means 宋 in 832 works, 明 in 375, 甲 in 322. A global lookup
  would state a Ming variant as a Song one, in the tradition's own sigla, with nothing
  about the answer looking wrong.
  """
  use Pramana.DataCase, async: true

  alias Pramana.Apparatus
  alias Pramana.Corpus.Segment
  alias Pramana.Corpus.Source
  alias Pramana.Corpus.Text
  alias Pramana.Corpus.Witness
  alias Pramana.Corpus.Work
  alias Pramana.Repo

  @urn "pramana:cbeta.T:T0001_001@p0001a01"

  defp seed_text!(work_id, witnesses) do
    Repo.insert!(%Work{id: work_id, title: work_id})

    Repo.insert!(%Text{
      work_id: work_id,
      source_id: "cbeta",
      witness_id: "T",
      urn_prefix: "pramana:cbeta.T:#{work_id}",
      body: "x",
      body_sha256: "x",
      volume: "1",
      meta: if(witnesses, do: %{"witnesses" => witnesses}, else: %{})
    })
  end

  defp seed_segment!(text, urn, content, apparatus) do
    Repo.insert!(%Segment{
      text_id: text.id,
      urn: urn,
      ordinal: 0,
      content: content,
      content_sha256: "y",
      char_start: 0,
      char_end: String.length(content),
      byte_start: 0,
      byte_end: byte_size(content),
      meta: if(apparatus, do: %{"apparatus" => apparatus}, else: %{})
    })
  end

  setup do
    Repo.insert!(%Source{
      id: "cbeta",
      name: "CBETA",
      license_spdx: "LicenseRef-CBETA-NC",
      license_class: "nc",
      commercial_use: false,
      redistributable: false
    })

    Repo.insert!(%Witness{id: "T", name: "Taishō"})
    :ok
  end

  describe "naming the witness" do
    test "resolves a reading to the sigil this text declares" do
      text = seed_text!("T0001", %{"wit1" => "【宋】", "wit2" => "【元】"})

      seed_segment!(text, @urn, "消融一念間", [
        %{"lem" => "消", "rdgs" => [%{"wit" => "#wit1 #wit2", "text" => "銷"}]}
      ])

      {:ok, result} = Apparatus.at(@urn)

      assert Enum.map(result.variants, & &1.witness) == ["【宋】", "【元】"]
      assert Enum.all?(result.variants, &(&1.lemma == "消" and &1.reading == "銷"))
    end

    test "the SAME id resolves differently in a different text, which is the whole point" do
      a = seed_text!("T0001", %{"wit1" => "【宋】"})
      b = seed_text!("T0002", %{"wit1" => "【明】"})

      rdg = [%{"lem" => "消", "rdgs" => [%{"wit" => "#wit1", "text" => "銷"}]}]
      seed_segment!(a, @urn, "消", rdg)
      seed_segment!(b, "pramana:cbeta.T:T0002_001@p0001a01", "消", rdg)

      {:ok, first} = Apparatus.at(@urn)
      {:ok, second} = Apparatus.at("pramana:cbeta.T:T0002_001@p0001a01")

      # wit1 is 宋 in 832 CBETA files and 明 in 375. A global table would report one of
      # these two answers for both.
      assert hd(first.variants).witness == "【宋】"
      assert hd(second.variants).witness == "【明】"
    end

    test "an unresolvable id is reported as such, never guessed" do
      text = seed_text!("T0001", %{"wit1" => "【宋】"})

      seed_segment!(text, @urn, "消", [
        %{"lem" => "消", "rdgs" => [%{"wit" => "#wit9", "text" => "銷"}]}
      ])

      {:ok, result} = Apparatus.at(@urn)
      [variant] = result.variants

      assert variant.witness == nil
      assert variant.witness_id == "#wit9"
    end

    test "a text with no imported witness map yields no invented sigla" do
      text = seed_text!("T0001", nil)

      seed_segment!(text, @urn, "消", [
        %{"lem" => "消", "rdgs" => [%{"wit" => "#wit1", "text" => "銷"}]}
      ])

      {:ok, result} = Apparatus.at(@urn)

      assert hd(result.variants).witness == nil
      assert result.witnesses == %{}
    end
  end

  describe "the shape of a variant" do
    test "an omission is distinguished from a substitution" do
      text = seed_text!("T0001", %{"wit1" => "【宋】", "wit2" => "【元】"})

      seed_segment!(text, @urn, "消融", [
        %{
          "lem" => "消",
          "rdgs" => [
            %{"wit" => "#wit1", "text" => "銷", "omitted" => false},
            %{"wit" => "#wit2", "text" => "", "omitted" => true}
          ]
        }
      ])

      {:ok, result} = Apparatus.at(@urn)
      [substitution, omission] = result.variants

      # "reads something else" and "has nothing here" are different claims about a
      # manuscript, and collapsing them turns an omission into a substitution.
      refute substitution.omitted
      assert omission.omitted
    end

    test "one row per lemma per witness, because that is the claim being checked" do
      text = seed_text!("T0001", %{"wit1" => "【宋】", "wit2" => "【元】", "wit3" => "【明】"})

      seed_segment!(text, @urn, "消融一念間至心", [
        %{"lem" => "消", "rdgs" => [%{"wit" => "#wit1 #wit2 #wit3", "text" => "銷"}]},
        %{"lem" => "至", "rdgs" => [%{"wit" => "#wit1", "text" => "志"}]}
      ])

      {:ok, result} = Apparatus.at(@urn)

      assert result.lemma_count == 2
      assert length(result.variants) == 4
    end
  end

  describe "honest absence" do
    test "a line with no recorded variants says the witnesses agree" do
      text = seed_text!("T0001", %{"wit1" => "【宋】"})
      seed_segment!(text, @urn, "如是我聞", nil)

      {:ok, result} = Apparatus.at(@urn)

      assert result.variants == []
      assert result.note =~ "agree here"
    end

    test "a range is refused rather than answered for one line of it" do
      text = seed_text!("T0001", %{"wit1" => "【宋】"})
      seed_segment!(text, @urn, "消", nil)
      seed_segment!(text, "pramana:cbeta.T:T0001_001@p0001a02", "融", nil)

      assert {:error, :not_a_single_line} =
               Apparatus.at("pramana:cbeta.T:T0001_001@p0001a01-p0001a02")
    end

    test "a URN addressing nothing is not found" do
      assert {:error, :not_found} = Apparatus.at("pramana:cbeta.T:T9999_001@p0001a01")
    end
  end

  describe "coverage" do
    test "reports how much apparatus exists and how much of it is legible" do
      text = seed_text!("T0001", %{"wit1" => "【宋】"})

      seed_segment!(text, @urn, "消", [
        %{"lem" => "消", "rdgs" => [%{"wit" => "#wit1", "text" => "銷"}]}
      ])

      coverage = Apparatus.coverage()

      # The second number is the one that matters: a variant whose witness cannot be
      # named is data we hold and cannot serve.
      assert coverage.segments_with_apparatus == 1
      assert coverage.texts_with_witness_map == 1
    end
  end
end
