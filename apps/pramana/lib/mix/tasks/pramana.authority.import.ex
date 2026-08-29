defmodule Mix.Tasks.Pramana.Authority.Import do
  @shortdoc "Imports DILA authority people, their lineage, and their external ids"

  @moduledoc """
  Loads DILA's person authority into `authority_people` and `authority_relations`.

      mix pramana.authority.import

  Reference data, not corpus: these are people who appear across every canon they worked
  in. Run `mix pramana.authority.link` afterwards to attach them to work bylines.

  ## What arrives

  49,259 people, 46,165 teacher/student relations DILA states, and roughly 3,800 external
  ids — Wikidata and CBDB. Of the ~830 people this corpus actually cites, about a third
  have a recorded lineage and a quarter a Wikidata id.

  **The lineage is DILA's claim and is stored as one.** Nothing here is inferred from
  co-occurrence or dates; `source` rides on every row so a chain is reportable as *DILA
  says* rather than as fact.
  """

  use Mix.Task

  alias Pramana.Acquire.Lockfile
  alias Pramana.Authority
  alias Pramana.Corpus.AuthorityPerson
  alias Pramana.Corpus.AuthorityPlace
  alias Pramana.Corpus.AuthorityRelation
  alias Pramana.Repo

  @switches [file: :string, places_file: :string]
  @default "authority_person/Buddhist_Studies_Person_Authority.xml"
  @places_default "authority_place/Buddhist_Studies_Place_Authority.xml"
  @source "dila-authority"

  @impl Mix.Task
  def run(argv) do
    {opts, _} = OptionParser.parse!(argv, strict: @switches)
    Mix.Task.run("app.start")

    path = opts[:file] || Path.join([Lockfile.raw_dir(), @source, @default])
    people = path |> File.read!() |> Authority.parse_people()
    now = DateTime.utc_now()

    import_places(
      opts[:places_file] || Path.join([Lockfile.raw_dir(), @source, @places_default]),
      now
    )

    person_rows =
      Enum.map(people, fn p ->
        %{
          id: p.id,
          name: List.first(p.names),
          names: p.names,
          dynasty: p.dynasty,
          birth_earliest: p.birth && p.birth.earliest,
          birth_latest: p.birth && p.birth.latest,
          birth_note: p.birth && p.birth.note,
          death_earliest: p.death && p.death.earliest,
          death_latest: p.death && p.death.latest,
          death_note: p.death && p.death.note,
          sect: p.sect,
          place_of_origin: p.place_of_origin,
          place_id: p.place_id,
          active_at: p.active_at,
          monk: p.monk,
          concise: p.concise,
          external_ids: p.external_ids,
          source: @source,
          inserted_at: now,
          updated_at: now
        }
      end)

    relation_rows =
      Enum.flat_map(people, fn p ->
        Enum.map(p.relations, fn r ->
          %{
            person_id: p.id,
            related_id: r.person_id,
            type: r.type,
            related_name: r.name,
            source: @source,
            inserted_at: now,
            updated_at: now
          }
        end)
      end)
      # DILA records a relation twice where two of its people are each other's teacher and
      # student. The unique index would reject the second; de-duplicating here keeps the
      # insert one statement rather than a fallback per row.
      |> Enum.uniq_by(&{&1.person_id, &1.related_id, &1.type})

    Repo.transaction(
      fn ->
        Repo.delete_all(AuthorityRelation)
        Repo.delete_all(AuthorityPerson)

        insert_all(AuthorityPerson, person_rows)
        # Only relations whose BOTH ends are people we hold. DILA's file references ids it
        # does not itself define, and a foreign key to a person who is not there is a link
        # nobody can follow.
        known = MapSet.new(person_rows, & &1.id)
        kept = Enum.filter(relation_rows, &MapSet.member?(known, &1.related_id))
        insert_all(AuthorityRelation, kept)

        Mix.shell().info("""

          #{length(person_rows)} person(s)
          #{length(kept)} relation(s), #{length(relation_rows) - length(kept)} dropped for naming a person the file does not define
          #{Enum.count(person_rows, &(&1.external_ids != %{}))} with an external id
          #{Enum.count(person_rows, & &1.birth_earliest)} with a birth date, #{Enum.count(person_rows, & &1.death_earliest)} with a death date
          #{Enum.count(person_rows, & &1.sect)} with a sect, #{Enum.count(person_rows, & &1.place_id)} with a place
        """)
      end,
      timeout: :infinity
    )
  end

  # WHAT `place_id` HAS BEEN POINTING AT. 12,134 people carry one and it resolved to nothing
  # until this ran. Skipped rather than failed when the file is absent: the person authority
  # was acquired alone for a while, and an import that refuses to run because a second file
  # is missing makes the first one unusable.
  defp import_places(path, now) do
    if File.exists?(path) do
      places = path |> File.read!() |> Authority.parse_places()

      rows =
        Enum.map(places, fn p ->
          %{
            id: p.id,
            name: p.name,
            names: p.names,
            name_en: p.name_en,
            district: p.district,
            district_path: p.district_path,
            country: p.country,
            region_id: p.region_id,
            region_name: p.region_name,
            lon: p.lon,
            lat: p.lat,
            geo_cert: p.geo_cert,
            note: p.note,
            source: @source,
            inserted_at: now,
            updated_at: now
          }
        end)

      Repo.transaction(
        fn ->
          Repo.delete_all(AuthorityPlace)
          insert_all(AuthorityPlace, rows)

          # Reported with its denominator. `country` at roughly two thirds is the figure that
          # decides whether a historical-region query is worth writing, and quoting only the
          # total would hide it.
          Mix.shell().info("""

            #{length(rows)} place(s)
            #{Enum.count(rows, & &1.lon)} with coordinates, #{Enum.count(rows, & &1.district)} with a district
            #{Enum.count(rows, & &1.country)} with a historical region, #{Enum.count(rows, & &1.name_en)} with an English name
          """)
        end,
        timeout: :infinity
      )
    else
      Mix.shell().info("  no place authority at #{path} — skipping places")
    end
  end

  # `insert_all` binds one parameter per column per row, so the batch size is a function of
  # row width — rule 14, learned the hard way on a wider table than this one.
  defp insert_all(schema, rows) do
    rows
    |> Enum.chunk_every(2_000)
    |> Enum.each(&Repo.insert_all(schema, &1))
  end
end
