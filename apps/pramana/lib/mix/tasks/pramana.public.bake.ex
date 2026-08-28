defmodule Mix.Tasks.Pramana.Public.Bake do
  @shortdoc "Bakes the redistributable-only corpus into a separate database"

  @moduledoc """
  Builds the public artefact: only sources whose licence permits redistribution, in a
  database of their own, verified before it is called done.

      PRAMANA_DATABASE=pramana_public mix pramana.public.bake
      PRAMANA_DATABASE=pramana_public mix pramana.public.bake --dry-run

  ## Why a separate database and not a query filter

  `license_class:` is an option on some retrieval queries and `Pramana.Corpus.resolve/1`
  takes no such option at all, so a public URN endpoint over the research database serves
  every text in it, CBETA included. **Options are things a caller can forget.** Here
  safety is a property of what is present: a public deployment cannot leak CBETA because
  this database does not contain it.

  Same reasoning as invariant #3. Reproducibility is a property of the artefact rather
  than of anyone following the rules, and so is this.

  ## It writes its own lockfile, so `bake_id` separates the two corpora

  `bake_id = sha256(lockfile + pipeline_version + config)`. A public bake reads
  `sources.public.lock.json` — the research lockfile with non-redistributable sources
  removed — so it gets a different id automatically and **cannot be mistaken for the full
  corpus in a citation**. The public lockfile is derived, never hand-edited, and is
  written on every run so it cannot drift from what was acquired.

  ## It refuses to declare success on an unsafe result

  The last step is `Pramana.Publishing.audit/0`, and a non-empty `forbidden` bucket fails
  the task. A build step that produces a public artefact and does not check it is a build
  step that will eventually publish the wrong thing quietly — which is precisely the
  failure mode `mix pramana.public.check` was written after finding.

  ## What it does not do

  It does not acquire. `raw/` is shared, append-only and licence-blind: having CBETA on
  disk is not publishing it. Acquire as normal, then bake here.
  """

  use Mix.Task

  import Ecto.Query

  alias Pramana.Acquire.Lockfile
  alias Pramana.Corpus.Text
  alias Pramana.Publishing
  alias Pramana.Repo

  @switches [dry_run: :boolean, force: :boolean]

  # Each redistributable source, the task that loads it, and HOW MANY ROWS IT MUST PRODUCE.
  # Declared here rather than discovered, because `docs/ADDING_TEXTS.md` is explicit that a
  # source arrives in one of two shapes and only one of them is dispatchable: CBETA
  # implements the Pipeline behaviours, every other source has a task of its own. Nothing
  # here is CBETA.
  #
  # THE FLOOR IS NOT DECORATION. The first version passed `--source derge-tengyur` to a
  # task whose switch is `--collection`, and `OptionParser.parse/2` — without the bang —
  # drops an unknown switch silently. So the Tengyur ingest re-ran the Kangyur, the public
  # corpus held 1,195 Tibetan texts instead of 4,575, and the bake reported "✓ safe to
  # expose", because it verified that nothing forbidden was present and never asked whether
  # anything expected was missing. That is the coverage doctrine failing inside the artefact
  # built to embody it: **a public bake must prove what it contains, not only what it
  # does not.**
  #
  # The floors are deliberately round numbers well under the true counts. They exist to
  # catch a stage that did nothing or loaded the wrong thing, not to pin a corpus size that
  # legitimately grows.
  @ingests [
    %{source: "sc", task: "pramana.sc.ingest", args: [], table: :texts, at_least: 8_000},
    %{
      source: "derge",
      task: "pramana.derge.ingest",
      args: ["--collection", "kangyur"],
      table: :texts,
      at_least: 1_000
    },
    %{
      source: "derge-tengyur",
      task: "pramana.derge.ingest",
      args: ["--collection", "tengyur"],
      table: :texts,
      at_least: 3_000
    },
    %{
      source: "sc-translations",
      task: "pramana.sc.translations",
      args: [],
      table: :translations,
      at_least: 100_000
    }
  ]

  @impl Mix.Task
  def run(argv) do
    {opts, _} = OptionParser.parse!(argv, strict: @switches)
    Mix.Task.run("app.start")

    with :ok <- refuse_research_database(opts[:force]),
         {:ok, lock} <- public_lockfile() do
      report_plan(lock, opts)

      if opts[:dry_run] do
        Mix.shell().info("\n  DRY RUN — nothing ingested.\n")
      else
        Enum.each(@ingests, &ingest/1)
        verify!()
      end
    else
      {:error, message} -> Mix.raise(message)
    end
  end

  # THE ONE IRREVERSIBLE MISTAKE THIS TASK COULD MAKE.
  #
  # Every ingest here replaces what it loads, so running against the research database
  # would not corrupt it — but it would spend hours re-loading a subset over a superset
  # and leave someone believing the result was the full corpus. Refusing by default costs
  # one environment variable and removes a whole class of confusion.
  defp refuse_research_database(force) do
    database = Repo.config()[:database]

    cond do
      force ->
        :ok

      is_binary(database) and String.contains?(database, "public") ->
        :ok

      true ->
        {:error,
         """
         refusing to bake the public corpus into #{inspect(database)}.

         The public artefact belongs in a database of its own — that separation is the
         whole point, since a public deployment must not be able to reach CBETA at all.

             createdb pramana_public
             PRAMANA_DATABASE=pramana_public mix ecto.migrate
             PRAMANA_DATABASE=pramana_public mix pramana.public.bake

         Pass --force only if this database really is the public one under another name.
         """}
    end
  end

  # The research lockfile with non-redistributable sources removed. Derived on every run:
  # a hand-maintained second lockfile is a list that goes stale, and this one decides what
  # a public bake contains.
  defp public_lockfile do
    with {:ok, lock} <- Lockfile.read() do
      kept = Enum.filter(lock["sources"] || [], &Publishing.publishable?(&1["id"]))
      public = Map.put(lock, "sources", kept)
      path = Path.join(Path.dirname(Lockfile.path()), "sources.public.lock.json")
      File.write!(path, Jason.encode!(public, pretty: true))
      {:ok, public}
    end
  end

  defp report_plan(lock, opts) do
    Mix.shell().info("""

      public bake — #{Repo.config()[:database]}

      lockfile      sources.public.lock.json (derived, #{length(lock["sources"])} source(s))
      publishable   #{Enum.join(Publishing.sources(), ", ")}
      ingesting     #{@ingests |> Enum.map(& &1.source) |> Enum.join(", ")}
      #{if opts[:dry_run], do: "DRY RUN", else: ""}
    """)
  end

  defp ingest(%{source: source, task: task, args: args}) do
    Mix.shell().info("\n  → #{source} (mix #{task} #{Enum.join(args, " ")})")
    Mix.Task.rerun(task, args)
  end

  # WHAT IS MISSING, not only what must not be here. Checked from the corpus after every
  # stage has run, so a stage that silently did nothing is caught by counting rather than
  # by trusting it returned :ok.
  defp completeness! do
    shortfalls =
      Enum.filter(@ingests, fn ingest ->
        loaded(ingest) < ingest.at_least
      end)

    Enum.each(@ingests, fn ingest ->
      Mix.shell().info(
        "      #{String.pad_trailing(ingest.source, 18)} #{String.pad_leading("#{loaded(ingest)}", 8)} " <>
          "#{ingest.table} (floor #{ingest.at_least})"
      )
    end)

    unless shortfalls == [] do
      Mix.raise("""
      the public bake is INCOMPLETE:

      #{Enum.map_join(shortfalls, "\n", &"  #{&1.source}: #{loaded(&1)} #{&1.table}, expected at least #{&1.at_least}")}

      A stage ran and loaded less than it should have. Do not deploy this — a corpus
      missing a canon answers "the tradition is silent" to questions it simply was not
      given the text for.
      """)
    end
  end

  defp loaded(%{table: :texts, source: source}) do
    Repo.aggregate(from(t in Text, where: t.source_id == ^source), :count)
  end

  defp loaded(%{table: :translations}) do
    Repo.aggregate(from(t in "translations", select: t.id), :count)
  end

  # The artefact checks itself. A build step that produces something public and does not
  # verify it is one that will eventually publish the wrong thing quietly.
  defp verify! do
    Mix.shell().info("\n    loaded per source\n")
    completeness!()

    audit = Publishing.audit()

    Mix.shell().info("""

      servable    #{Publishing.total(audit.servable)} row(s)
      withheld    #{Publishing.total(audit.withheld)} row(s) — permissive licence, no publication record
      forbidden   #{Publishing.total(audit.forbidden)} row(s)
    """)

    if audit.safe? do
      Mix.shell().info(
        "  ✓ safe to expose. Run `mix pramana.public.check` any time to re-verify.\n"
      )
    else
      Mix.raise("""
      the public bake produced a database that is NOT safe to expose:

      #{Enum.map_join(audit.forbidden, "\n", &"  #{&1.id}  #{&1.rows} row(s)  #{&1.spdx}")}

      Something loaded content it should not have. Do not deploy this.
      """)
    end
  end
end
