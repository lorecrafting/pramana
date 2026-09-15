defmodule Pramana.Repo.Migrations.CreateAuthorityPeople do
  @moduledoc """
  DILA's person authority, and the lineage between its people.

  Reference data, not corpus. These rows describe people who appear across every canon a
  translator worked in, which is why `Pramana.Sources` gives the source `tradition:
  "reference"` rather than filing it under one — a translator is not Chinese material
  because his bylines are.

  ## Why a table rather than parsing the 49 MB file per query

  `works.authority_id` already links a byline to a person. Answering *"who taught him"* or
  *"what is his Wikidata id"* from that link means having the person, and re-parsing a 49 MB
  TEI document to answer one question is not a query. 49,259 people and 46,165 relations
  fit comfortably.

  ## The lineage is DILA's claim, not ours

  `<relation type="teacher" active="A000242"/>` is an assertion by the authority's editors,
  and it is stored as one: `source` says where it came from, so a chain walked through these
  rows can be reported as *DILA says* rather than as fact. **We do not infer lineage** —
  from co-occurrence, from dates, from anything. Inferred lineage is how a scholarly claim
  gets manufactured, and `CLAUDE.md` invariant #5 puts the deterministic source first
  precisely so the difference stays visible.
  """

  use Ecto.Migration

  def change do
    create table(:authority_people, primary_key: false) do
      add :id, :string, primary_key: true
      add :name, :string
      # Every spelling the authority records, so a caller can see why a byline matched.
      add :names, {:array, :string}, null: false, default: []
      add :dynasty, :string

      # BOTH ENDS OF EACH RANGE. DILA writes `+0383-01-01 ~ +0383-12-31` for "sometime in
      # 383" and `+0442-01-28 ~ +0443-02-15` for a death whose lunar date crosses a Julian
      # year — a range of one day and a range of thirteen months are different claims, and
      # a single year makes them look the same. `works.date_start`/`date_end` have been null
      # for every text in the corpus; these are what can finally fill them.
      add :birth_earliest, :date
      add :birth_latest, :date
      add :birth_note, :text
      add :death_earliest, :date
      add :death_latest, :date
      add :death_note, :text

      # 臨濟宗 楊岐派 — school and branch, as one string because that is how DILA states it
      # and splitting it would be our taxonomy rather than theirs.
      add :sect, :string
      add :place_of_origin, :string
      # The id in DILA's PLACE authority, so the two databases join without re-matching on
      # a place name — the same reason `authority_id` exists for a byline.
      add :place_id, :string
      add :active_at, {:array, :string}, null: false, default: []
      add :monk, :boolean
      add :concise, :text
      # Wikidata, CBDB and whatever else appears upstream. A map so a new authority needs
      # no migration.
      add :external_ids, :map, null: false, default: %{}
      add :source, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:authority_people, [:name])
    create index(:authority_people, [:dynasty])
    create index(:authority_people, [:sect])
    create index(:authority_people, [:place_id])
    # "who was working in the 5th century" is a range query over both ends.
    create index(:authority_people, [:birth_earliest])
    create index(:authority_people, [:death_latest])

    create table(:authority_relations) do
      add :person_id, references(:authority_people, type: :string, on_delete: :delete_all),
        null: false

      add :related_id, :string, null: false
      # `teacher` and `student`, as DILA states them. Both directions are stored because
      # DILA states both, and deriving one from the other would silently drop the pairs
      # where it recorded only one.
      add :type, :string, null: false
      add :related_name, :string
      add :source, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:authority_relations, [:person_id, :related_id, :type])
    create index(:authority_relations, [:related_id])

    create constraint(:authority_relations, :relation_type_known,
             check: "type IN ('teacher', 'student')"
           )
  end
end
