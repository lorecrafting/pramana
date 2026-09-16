defmodule Pramana.Repo.Migrations.CreateAuthorityPlaces do
  @moduledoc """
  DILA's place authority: what `authority_people.place_id` has been pointing at.

  12,134 people carry a `place_id` and it has resolved to nothing since the person authority
  was imported without the place file beside it. What it resolves to is a **region in two
  independent schemes**, and the pair is the point:

  - `district` — the MODERN administrative path, `中國-浙江省-杭州市-下城區`. Kept whole and
    also split into `district_path`, because a collapsed path cannot be grouped by province
    and a split one loses the spelling DILA published. Rule 61.
  - `country` — the HISTORICAL unit: 江南東道, 隴右道, 西突厥. Tang circuits, not modern
    states, and the one a scholar actually wants.

  Coordinates are present on 98.6% of the file and on **every place this bake cites**, but
  they are stored as an attribute of the record rather than as its purpose. `geo_cert` rides
  beside them: a coordinate whose stated confidence has been dropped is one nobody can argue
  with.

  **`lon` and `lat` are separate columns, in that order in the source.** DILA publishes
  `<geo>` as longitude first, which is the reverse of TEI's own convention — 于闐 reads
  `79.828 36.9881` and Khotan is 37.1°N 79.9°E. Naming the columns is the fix: a `geo` string
  column would carry the ambiguity forever.
  """

  use Ecto.Migration

  def change do
    create table(:authority_places, primary_key: false) do
      add :id, :string, primary_key: true

      add :name, :string
      add :names, {:array, :string}, default: []
      add :name_en, :string

      # `:text`, not `:string`. A district runs to 536 bytes where a place spans modern
      # borders — `中國;蒙古;俄羅斯-遠東聯邦管區：Дальневосточный…-Sakhalin` — with Cyrillic
      # and parenthesised English inside it. 255 was chosen from what a Chinese county name
      # looks like, which is the assumption the 257 multi-region entries break.
      add :district, :text
      # Populated ONLY where the district is a single hyphen path. 257 entries are
      # semicolon-separated LISTS of regions, and splitting those on `-` yields fragments
      # that look like a hierarchy and are not — rule 33: accept or refuse a whole group.
      # The raw string is always kept, so nothing is lost by the refusal.
      add :district_path, {:array, :string}, default: []
      add :country, :string

      # The containing record DILA points at — `PLD000926` (a district) or `PLA000002` (a
      # country). Not a foreign key: the ids live in a second file and a place may name a
      # region that file does not define, which is upstream's business to fix, not ours to
      # refuse an import over.
      add :region_id, :string
      add :region_name, :string

      add :lon, :float
      add :lat, :float
      add :geo_cert, :string

      add :note, :text
      add :source, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    # Grouping is what this table is for: "translators from Jiangnan", "Indian-born
    # translators". Both schemes get an index because both are asked.
    create index(:authority_places, [:country])
    create index(:authority_places, [:district])
    create index(:authority_places, [:region_id])
    create index(:authority_places, [:district_path], using: :gin)

    # A coordinate must not be half-present. One end without the other is not a location,
    # and storing it invites a reader to supply the other from somewhere else.
    create constraint(:authority_places, :geo_is_whole_or_absent,
             check: "(lon IS NULL) = (lat IS NULL)"
           )

    # Longitude and latitude have real ranges and a swapped pair usually violates them —
    # this is the check that would have caught reading `<geo>` as TEI documents it, since
    # 79.828 is not a latitude anywhere on Earth's populated surface.
    create constraint(:authority_places, :geo_is_on_earth,
             check: "lon IS NULL OR (lon BETWEEN -180 AND 180 AND lat BETWEEN -90 AND 90)"
           )
  end
end
