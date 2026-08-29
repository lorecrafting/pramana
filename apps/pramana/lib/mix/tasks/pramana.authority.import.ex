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
  alias Pramana.Corpus.AuthorityRelation
  alias Pramana.Repo

  @switches [file: :string]
  @default "authority_person/Buddhist_Studies_Person_Authority.xml"
  @source "dila-authority"

  @impl Mix.Task
  def run(argv) do
    {opts, _} = OptionParser.parse!(argv, strict: @switches)
    Mix.Task.run("app.start")

    path = opts[:file] || Path.join([Lockfile.raw_dir(), @source, @default])
    people = path |> File.read!() |> Authority.parse_people()
    now = DateTime.utc_now()

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

  # `insert_all` binds one parameter per column per row, so the batch size is a function of
  # row width — rule 14, learned the hard way on a wider table than this one.
  defp insert_all(schema, rows) do
    rows
    |> Enum.chunk_every(2_000)
    |> Enum.each(&Repo.insert_all(schema, &1))
  end
end
