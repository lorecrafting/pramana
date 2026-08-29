defmodule Pramana.AuthorityPersonTest do
  @moduledoc """
  `Authority.person/1` — the record a byline resolves to.

  The distinctions under test are all about *not collapsing* things: an unknown id is not a
  person with nothing recorded, a missing date is not an empty range, and a range known to
  the day is not the same evidence as one known to the year. Each of those collapses is
  irreversible once it reaches a caller.
  """
  use Pramana.DataCase, async: true

  alias Pramana.Authority
  alias Pramana.Corpus.AuthorityPerson
  alias Pramana.Corpus.AuthorityRelation
  alias Pramana.Repo

  defp insert!(attrs) do
    %AuthorityPerson{}
    |> Ecto.Changeset.change(Map.put_new(attrs, :source, "dila-authority"))
    |> Repo.insert!()
  end

  defp relate!(from, to, name, type) do
    %AuthorityRelation{}
    |> Ecto.Changeset.change(%{
      person_id: from,
      related_id: to,
      related_name: name,
      type: type,
      source: "dila-authority"
    })
    |> Repo.insert!()
  end

  test "an unknown id is nil, not an empty person" do
    refute Authority.person("A999999")
  end

  test "returns the record, with alternative names separated from the head name" do
    insert!(%{id: "A1", name: "了貞", names: ["了貞", "昭月", "高旻了貞"], dynasty: "清"})

    person = Authority.person("A1")

    assert person.name == "了貞"
    assert person.also_known_as == ["昭月", "高旻了貞"]
    assert person.dynasty == "清"
  end

  describe "dates" do
    test "no recorded date is nil, never an empty range" do
      insert!(%{id: "A2", name: "無名"})
      person = Authority.person("A2")

      # An empty range reads as "a date whose ends happen to be missing", which invites a
      # caller to fill them in. `nil` says the authority records nothing.
      assert person.birth == nil
      assert person.death == nil
    end

    test "keeps both ends, and says whether they are the same day" do
      insert!(%{
        id: "A3",
        name: "了貞",
        birth_earliest: ~D[1729-01-01],
        birth_latest: ~D[1729-12-31],
        birth_note: "依記錄推算。",
        death_earliest: ~D[1785-11-08],
        death_latest: ~D[1785-11-08]
      })

      person = Authority.person("A3")

      # A year inferred from records and a day given by a colophon are different evidence.
      # Flattening both to 1729 and 1785 destroys the difference with nothing recording it.
      refute person.birth.exact
      assert person.birth.earliest == ~D[1729-01-01]
      assert person.birth.latest == ~D[1729-12-31]
      assert person.birth.note == "依記錄推算。"
      assert person.death.exact
    end

    test "half a bound is still a bound" do
      insert!(%{
        id: "A4",
        name: "性起",
        death_earliest: ~D[1798-03-01],
        death_latest: ~D[1798-03-01]
      })

      person = Authority.person("A4")

      assert person.birth == nil
      assert person.death.exact
    end
  end

  describe "lineage" do
    test "reports teachers and students as DILA states them, with the source" do
      insert!(%{id: "A5", name: "甲"})
      relate!("A5", "A6", "乙", "teacher")
      relate!("A5", "A7", "丙", "student")

      lineage = Authority.person("A5").lineage

      assert [%{id: "A6", name: "乙", source: "dila-authority"}] = lineage.teachers
      assert [%{id: "A7", name: "丙"}] = lineage.students
    end

    test "a cycle stops the chain rather than being walked" do
      # Two people each recorded as the other's teacher. This is REAL DATA — authority
      # editors record what sources say and sources disagree — so the chain must terminate
      # and report why, not treat it as corrupt input.
      insert!(%{id: "A8", name: "甲"})
      insert!(%{id: "A9", name: "乙"})
      relate!("A8", "A9", "乙", "teacher")
      relate!("A9", "A8", "甲", "teacher")

      assert %{stopped: :cycle, chain: chain} = Authority.teacher_chain("A8", depth: 10)
      assert length(chain) == 1
    end

    test "several recorded teachers follow the first and say the path branched" do
      insert!(%{id: "B1", name: "甲"})
      relate!("B1", "B2", "乙", "teacher")
      relate!("B1", "B3", "丙", "teacher")

      assert %{branched: true, stopped: :no_teacher_recorded} = Authority.teacher_chain("B1")
    end
  end

  test "external ids pass through untouched" do
    insert!(%{id: "C1", name: "甲", external_ids: %{"wikidata" => "Q1363621"}})

    assert Authority.person("C1").external_ids == %{"wikidata" => "Q1363621"}
  end
end
