defmodule Mix.Tasks.Pramana.Authority.Link do
  @shortdoc "Links work bylines to DILA authority persons"

  @moduledoc """
  Resolves every work's byline to a DILA authority id, where it can be resolved confidently.

      mix pramana.authority.link
      mix pramana.authority.link --dry-run

  `works.attributed_author` is a byline as the edition printed it. This adds the identity
  beside it — one person across spellings, with dates and a stable external reference — and
  never touches the byline itself, because the byline is what the witness says and the link
  is an inference about it.

  ## Refusing is the common outcome

  Roughly half of all bylines resolve. The rest name someone DILA does not record under that
  spelling, name several people, or carry a dynasty no namesake shares. Each of those is a
  refusal rather than a best guess: a wrong authority link merges two people into one
  identity, and every later question about "the same translator" inherits the error
  silently. See `Pramana.Authority` for the rule and what it measures.

  ## Options

    * `--dry-run` — report the counts, write nothing
    * `--file` — path to the person authority XML (defaults under `raw/dila-authority/`)
  """

  use Mix.Task

  import Ecto.Query

  alias Pramana.Acquire.Lockfile
  alias Pramana.Authority
  alias Pramana.Corpus.Work
  alias Pramana.Repo

  @switches [dry_run: :boolean, file: :string]
  @default "authority_person/Buddhist_Studies_Person_Authority.xml"

  @impl Mix.Task
  def run(argv) do
    {opts, _} = OptionParser.parse!(argv, strict: @switches)
    Mix.Task.run("app.start")

    path = opts[:file] || Path.join([Lockfile.raw_dir(), "dila-authority", @default])

    unless File.exists?(path) do
      Mix.raise("""
      no DILA person authority at #{path}.

      Acquire it first, or pass --file. The data is CC BY-SA 3.0 from
      https://github.com/DILA-edu/Authority-Databases.
      """)
    end

    people = path |> File.read!() |> Authority.parse_people()
    index = Authority.index(people)
    Mix.shell().info("\n  #{length(people)} authority record(s) from #{Path.basename(path)}")

    works =
      Repo.all(
        from w in Work,
          where: not is_nil(w.attributed_author),
          select: %{id: w.id, byline: w.attributed_author}
      )

    linked = Enum.map(works, &{&1, Authority.link_byline(&1.byline, index)})
    report(linked)

    unless opts[:dry_run], do: write(linked)
  end

  defp report(linked) do
    by_method =
      linked
      |> Enum.map(fn {_w, l} -> (l && l.method) || "refused" end)
      |> Enum.frequencies()
      |> Enum.sort_by(&(-elem(&1, 1)))

    Enum.each(by_method, fn {m, n} ->
      Mix.shell().info("    #{String.pad_trailing(m, 26)} #{n}")
    end)

    found = Enum.count(linked, fn {_w, l} -> l end)
    total = length(linked)

    Mix.shell().info("""

      #{found} of #{total} works linked (#{Float.round(100 * found / max(total, 1), 1)}%),
      #{length(Enum.uniq_by(Enum.filter(linked, &elem(&1, 1)), fn {_w, l} -> l.authority_id end))} distinct people.

    A refusal is not a failure. Half of these bylines name someone the authority does not
    record under that spelling, name several people at once, or carry a dynasty no namesake
    shares — and a wrong link merges two people into one identity for good.
    """)
  end

  # Clears every link before writing, so a re-run converges rather than leaving a stale link
  # on a work whose byline now resolves differently. Same discipline as `Corpus.Loader`.
  defp write(linked) do
    Repo.update_all(Work,
      set: [authority_id: nil, authority_method: nil, authority_confidence: nil]
    )

    # Only the dates this task itself derived. A `catalogue` or `colophon` date is a
    # stronger claim from another source and must not be cleared by a re-link.
    Repo.update_all(from(w in Work, where: w.date_basis == "authority_lifespan"),
      set: [date_start: nil, date_end: nil, date_basis: nil]
    )

    linked
    |> Enum.filter(fn {_w, l} -> l end)
    |> Enum.chunk_every(500)
    |> Enum.each(fn batch ->
      Enum.each(batch, fn {w, l} ->
        Repo.update_all(from(x in Work, where: x.id == ^w.id),
          set: [
            authority_id: l.authority_id,
            authority_method: l.method,
            authority_confidence: l.confidence
          ]
        )
      end)
    end)

    dated = write_dates()
    Mix.shell().info("  written. #{dated} work(s) also gained a date bound.\n")
  end

  # A PERSON'S LIFESPAN IS A BOUND, NOT A DATE. Amoghavajra was born in 705 and did not
  # translate at birth, so his dates say only that his works fall between them. That is
  # enough to answer "Tang or Ming" and not enough to answer "which year", and `date_basis`
  # records which kind of claim this is so nothing downstream mistakes it for a colophon.
  #
  # AN OPEN BOUND IS HONEST; A FALSE POINT IS NOT. The first version of this coalesced the
  # two ends, so a person with only a death date produced `772 – 772` — which reads as "made
  # in 772" and means "made no later than 772". 217 works said that. Half a bound is stored
  # as half a bound: unknown birth leaves `date_start` null, and the CHECK constraint permits
  # exactly that as long as the basis is stated.
  defp write_dates do
    {count, _} =
      Repo.update_all(
        from(w in Work,
          join: p in "authority_people",
          on: p.id == w.authority_id,
          where: not is_nil(p.birth_earliest) or not is_nil(p.death_latest),
          update: [
            set: [
              date_start: fragment("extract(year from ?)::int", p.birth_earliest),
              date_end: fragment("extract(year from ?)::int", p.death_latest),
              date_basis: "authority_lifespan"
            ]
          ]
        ),
        []
      )

    count
  end
end
