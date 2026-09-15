defmodule Mix.Tasks.Pramana.Glossary.Anchor do
  @shortdoc "Resolves glossary citations to URNs this corpus can open"

  @moduledoc """
  Anchors the Taishō citations Karashima's glossaries carry.

      mix pramana.glossary.anchor
      mix pramana.glossary.anchor --dry-run
      mix pramana.glossary.anchor --source dila-glossaries

  `mix pramana.glossary.dila` stores the citations a gloss rests on as the glossary prints
  them — `T.262` at `59b7`. This resolves them against the bake, so a dictionary entry
  becomes something a reader can open rather than something they take on trust.
  `Pramana.Glossary.Anchors` argues the design; the short version is that **absence is a
  status rather than a failure**, because thousands of these are a scholar having checked
  a line and recorded that the word is not there.
  """

  use Mix.Task

  import Ecto.Query

  alias Pramana.Corpus.GlossaryAnchor
  alias Pramana.Glossary.Anchors
  alias Pramana.Repo

  @switches [source: :string, dry_run: :boolean]
  @default_source "dila-glossaries"

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _} = OptionParser.parse!(argv, strict: @switches)

    source = Keyword.get(opts, :source, @default_source)

    {us, tally} =
      :timer.tc(fn -> Anchors.resolve_source(source, dry_run: opts[:dry_run]) end)

    report(source, tally, us, opts[:dry_run])
  end

  defp report(source, tally, us, dry_run?) do
    resolved = Map.get(tally, "resolved", 0)
    absent = Map.get(tally, "absent", 0)
    unresolved = Map.get(tally, "unresolved", 0)

    Mix.shell().info("""

    #{if dry_run?, do: "DRY RUN — ", else: ""}anchored #{source} in #{Pramana.Elapsed.human(div(us, 1000))}
      citations:  #{tally.total}
      resolved:   #{resolved}#{percent(resolved, tally.total)} — a line this bake holds
      absent:     #{absent}#{percent(absent, tally.total)} — a scholar checked and the term is NOT there
      unresolved: #{unresolved}#{percent(unresolved, tally.total)} — no such line here, or unparseable
      stored:     #{if dry_run?, do: "nothing (dry run)", else: Repo.aggregate(GlossaryAnchor, :count)}
    """)

    if unresolved > 0 and dry_run? != true, do: show_unresolved()
  end

  # NAMED, not just counted. An unresolved citation is either a bug in the parser or a
  # work this bake does not hold, and those want opposite responses — rules 22 and 44 say
  # publish the gap, and a gap with no examples cannot be acted on.
  defp show_unresolved do
    samples =
      from(a in GlossaryAnchor,
        where: a.status == "unresolved",
        select: a.citation,
        order_by: a.citation,
        limit: 6
      )
      |> Repo.all()

    Mix.shell().info("  unresolved examples: #{Enum.join(samples, " · ")}\n")
  end

  defp percent(_n, 0), do: ""
  defp percent(n, total), do: " (#{Float.round(n * 100 / total, 1)}%)"
end
