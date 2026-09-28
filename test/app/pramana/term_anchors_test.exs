defmodule Pramana.TermAnchorsTest do
  @moduledoc """
  The same term as three traditions name it.

  Two things are load-bearing. A term does not have *a* translation — the Tibetans
  rendered one Sanskrit word several ways and this must never pick a winner — and the
  Sanskrit is usually a reconstruction, which a caller must be told without having to ask.
  """
  use Pramana.DataCase, async: true

  alias Pramana.Corpus.GlossaryEntry
  alias Pramana.Corpus.Source
  alias Pramana.Repo
  alias Pramana.TermAnchors

  setup do
    Repo.insert!(%Source{
      id: "84000",
      name: "84000",
      license_spdx: "CC-BY-NC-ND-3.0",
      license_class: "nc",
      commercial_use: false,
      redistributable: false
    })

    :ok
  end

  defp entry(attrs) do
    now = DateTime.utc_now()

    Repo.insert!(
      struct(
        GlossaryEntry,
        Map.merge(
          %{
            source_id: "84000",
            gloss_id: "g#{System.unique_integer([:positive])}",
            inserted_at: now,
            updated_at: now
          },
          Map.new(attrs)
        )
      )
    )
  end

  describe "one Sanskrit term, several Tibetan renderings" do
    setup do
      entry(
        sanskrit: "parivrājaka",
        tibetan: "ཀུན་ཏུ་རྒྱུ་བ།",
        wylie: "kun tu rgyu ba",
        english: "wandering mendicant",
        work_id: nil
      )

      entry(
        sanskrit: "parivrājaka",
        tibetan: "ཀུན་དུ་རྒྱུ།",
        wylie: "kun du rgyu",
        english: "wanderer"
      )

      entry(
        sanskrit: "parivrājaka",
        tibetan: "པ་རི་པ་ར་ཙ་ཀ",
        wylie: "pa ri pa ra tsa ka",
        english: "parivrājaka"
      )

      :ok
    end

    test "returns every rendering rather than choosing one" do
      renderings = TermAnchors.renderings("parivrājaka")

      assert length(renderings) == 3
      assert "ཀུན་ཏུ་རྒྱུ་བ།" in Enum.map(renderings, & &1.tibetan)
      assert "པ་རི་པ་ར་ཙ་ཀ" in Enum.map(renderings, & &1.tibetan)
    end

    test "a term rendered more than one way is reported as divergent" do
      assert [%{sanskrit: "parivrājaka", renderings: 3}] = TermAnchors.divergent()
    end

    test "a term rendered one way is not" do
      entry(sanskrit: "buddha", tibetan: "སངས་རྒྱས།", english: "buddha")
      entry(sanskrit: "buddha", tibetan: "སངས་རྒྱས།", english: "Buddha")

      refute "buddha" in Enum.map(TermAnchors.divergent(), & &1.sanskrit)
    end
  end

  describe "attestation" do
    setup do
      entry(
        sanskrit: "yūpa",
        sanskrit_attestation: "unspecified",
        tibetan: "མཆོད་སྡོང་།",
        tibetan_attestation: "source",
        english: "pillar"
      )

      entry(
        sanskrit: "sūtra",
        sanskrit_attestation: "source",
        tibetan: "མདོ།",
        tibetan_attestation: "source",
        english: "sūtra"
      )

      :ok
    end

    test "every returned anchor says where its Sanskrit came from" do
      # A caller holding `yūpa` with no note that it is reconstructed will cite it as
      # though a Sanskrit manuscript said so.
      [anchor] = TermAnchors.lookup(:sanskrit, "yūpa")

      assert anchor.attestation.sanskrit == "unspecified"
      assert anchor.attestation.tibetan == "source"
    end

    test "attested_only narrows to what a witness actually says" do
      assert TermAnchors.lookup(:sanskrit, "yūpa", attested_only: true) == []
      assert [%{sanskrit: "sūtra"}] = TermAnchors.lookup(:sanskrit, "sūtra", attested_only: true)
    end
  end

  describe "across traditions" do
    test "an entry carrying all three languages is a three-way anchor" do
      entry(sanskrit: "dharma", tibetan: "ཆོས།", chinese: "法", english: "dharma")
      entry(sanskrit: "abhijñā", tibetan: "མངོན་པར་ཤེས་པ།", english: "higher knowledge")

      assert [%{sanskrit: "dharma", chinese: "法", tibetan: "ཆོས།"}] = TermAnchors.three_way()
    end

    test "a term can be looked up from any of its languages" do
      entry(sanskrit: "dharma", tibetan: "ཆོས།", chinese: "法", english: "dharma")

      assert [%{sanskrit: "dharma"}] = TermAnchors.lookup(:chinese, "法")
      assert [%{sanskrit: "dharma"}] = TermAnchors.lookup(:tibetan, "ཆོས།")
    end

    test "lookup is exact, because a substring match returns every compound" do
      entry(sanskrit: "dharma", tibetan: "ཆོས།", english: "dharma")
      entry(sanskrit: "dharmakāya", tibetan: "ཆོས་སྐུ།", english: "dharma body")

      assert [%{sanskrit: "dharma"}] = TermAnchors.lookup(:sanskrit, "dharma")
    end
  end

  test "stats report how much of the Sanskrit is reconstructed" do
    entry(sanskrit: "yūpa", sanskrit_attestation: "unspecified", tibetan: "མཆོད་སྡོང་།")
    entry(sanskrit: "sūtra", sanskrit_attestation: "source", tibetan: "མདོ།")

    stats = TermAnchors.stats()

    assert stats.entries == 2
    assert stats.sanskrit == 2
    assert stats.sanskrit_attested_in_a_source == 1
  end
end
