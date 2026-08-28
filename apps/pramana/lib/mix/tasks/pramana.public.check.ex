defmodule Mix.Tasks.Pramana.Public.Check do
  @shortdoc "Says whether this database is safe to expose publicly"

  @moduledoc """
  What a public deployment of *this* database would serve, and under whose licence.

      mix pramana.public.check

  `CLAUDE.md` is unambiguous: **we publish the pipeline, not the corpus**, and a public
  demo serves the CC0/CC-BY subset only. Today that rule is enforced by a caller
  remembering to pass `license_class:` — an option, on some queries, which is not an
  enforcement mechanism. A URN resolve takes no such option at all.

  So this task does not try to prove the code is safe. It asks the only question that can
  actually be answered: **is there anything in this database that must not be served?**
  If the answer is no, no code path can leak it, because it is not there. That is the same
  reasoning as invariant #3 — reproducibility is a property of the artefact, not of anyone
  remembering the rules.

  ## What it does not do

  It does not modify anything, and it is **not** a deployment gate on its own. A database
  holding restricted text is the normal case for local research; this only says you cannot
  point the public at it. Building the public artefact is a separate bake, from a lockfile
  containing only redistributable sources.
  """

  use Mix.Task

  import Ecto.Query

  alias Pramana.Corpus.Source
  alias Pramana.Corpus.Text
  alias Pramana.Repo

  @impl Mix.Task
  def run(_argv) do
    Mix.Task.run("app.start")

    rows =
      Repo.all(
        from t in Text,
          join: s in Source,
          on: s.id == t.source_id,
          group_by: [s.id, s.name, s.license_spdx, s.license_class, s.redistributable],
          order_by: [desc: count(t.id)],
          select: %{
            id: s.id,
            name: s.name,
            spdx: s.license_spdx,
            class: s.license_class,
            redistributable: s.redistributable,
            texts: count(t.id)
          }
      )

    {public, held} = Enum.split_with(rows ++ translation_rows(), & &1.redistributable)

    # THREE BUCKETS, NOT TWO. The `redistributable` flag answers "may we serve this",
    # and it is false for two completely different reasons: a licence that forbids it,
    # and a licence we could not confirm. Reporting them together said 110,737 rows
    # "must not be served" when 76,040 of those are CC0 text — public domain — flagged
    # only because the ingest could not match the publication record exactly and chose
    # the safe direction. That is the right default and the wrong headline: one is a
    # legal boundary, the other is a data task.
    {uncertain, forbidden} = Enum.split_with(held, &permissive?/1)

    Mix.shell().info("\n  SAFE TO SERVE PUBLICLY\n")
    Enum.each(public, &line/1)
    if public == [], do: Mix.shell().info("    (nothing)")

    Mix.shell().info("\n  FORBIDDEN BY LICENCE — a public bake must not contain these\n")
    Enum.each(forbidden, &line/1)
    if forbidden == [], do: Mix.shell().info("    (nothing)")

    Mix.shell().info("\n  WITHHELD BY UNCERTAINTY — permissively licensed, not confirmed\n")
    Enum.each(uncertain, &line/1)
    if uncertain == [], do: Mix.shell().info("    (nothing)")

    verdict(public, forbidden, uncertain)
  end

  # Licences under which redistribution is permitted outright. A row carrying one of these
  # and still flagged not-redistributable was withheld by OUR uncertainty, not by its
  # terms — see `mix pramana.sc.translations`, which stores `redistributable: false`
  # whenever the licence was inferred from a sibling rather than matched to the file.
  @permissive ~w(CC0-1.0 CC-PDM-1.0 CC-BY-4.0 CC-BY-SA-4.0)

  defp permissive?(%{spdx: spdx}), do: spdx in @permissive

  # TRANSLATIONS ARE NOT IN `texts` AND CARRY THEIR OWN FLAG.
  #
  # The first version of this counted `texts` alone and reported the corpus safe or unsafe
  # on that basis — while `translations` holds thousands of rows with a `redistributable`
  # column of their own, precisely because a rendering's licence is not its source text's.
  # A check that answers "what would leak" from one table, when the leak can come from
  # two, is the coverage-denominator failure again (rule 44).
  defp translation_rows do
    Repo.all(
      from t in "translations",
        group_by: [t.translator_id, t.redistributable, t.license_spdx],
        order_by: [desc: count(t.id)],
        select: %{
          id: t.translator_id,
          name: "translation layer",
          spdx: t.license_spdx,
          class: nil,
          redistributable: t.redistributable,
          texts: count(t.id)
        }
    )
  end

  defp line(r) do
    Mix.shell().info(
      "    #{String.pad_trailing(r.id, 18)} #{String.pad_leading("#{r.texts}", 6)} text(s)  " <>
        "#{String.pad_trailing(r.spdx || "—", 24)} #{r.name}"
    )
  end

  defp verdict(public, [], uncertain) do
    Mix.shell().info("""

      ✓ SAFE. Nothing here is forbidden by its licence (#{total(public)} rows servable).
    """)

    unclaimed(uncertain)
  end

  defp verdict(public, forbidden, uncertain) do
    all = total(public) + total(forbidden) + total(uncertain)

    Mix.shell().info("""

      ✗ NOT SAFE TO EXPOSE. #{total(forbidden)} of #{all} rows come from #{length(forbidden)} source(s)
        whose licence forbids redistribution.

        This is the normal state for local research and is not a defect. It means a
        public deployment must run against a SEPARATE bake, from a lockfile holding only
        redistributable sources — not against this one behind a query filter. A filter is
        something a caller can forget to pass, and `Corpus.resolve/1` takes no filter at
        all: a public URN endpoint over this database serves every text in it.
    """)

    unclaimed(uncertain)
  end

  defp unclaimed([]), do: :ok

  defp unclaimed(uncertain) do
    Mix.shell().info("""
        #{total(uncertain)} further rows carry a permissive licence and are still withheld,
        because the ingest inferred that licence rather than matching it and stored the
        safe answer. Nothing legal is blocking those; confirming them is a data task, and
        it is the single largest thing standing between this corpus and a public demo.
    """)
  end

  defp total(rows), do: rows |> Enum.map(& &1.texts) |> Enum.sum()
end
