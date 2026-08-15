defmodule Mix.Tasks.Pramana.Glossary.Import do
  @shortdoc "Imports a markdown glossary as pinned term renderings"

  @moduledoc """
  Loads a hand-built glossary into `glossary_terms`.

      mix pramana.glossary.import ~/dev/huangnianzu-translation/glossary/glossary.md \\
        --source local-huang-nianzu-jie

      mix pramana.glossary.import <file> --source <id> --dry-run

  Seed data for glossary-pinned translation (#26) and the reading-exception dictionary
  (#24). The glossary belongs to a **source**, so licence gating follows it: a glossary
  derived from a restricted text inherits that restriction and never reaches a public
  surface.

  ## What it keeps, and why

  The mapping is the least interesting part. `notes` is stored verbatim because it
  carries the reasoning; `rejected_forms` is extracted from the glossary's own
  `**Not** "X"` markers because **a decision recorded is not a decision applied**, and
  knowing which rendering is wrong is what lets a checker find the places still using
  it; `reading_status` records a reading the source could not verify, rather than
  dropping the row or inventing the reading.
  """

  use Mix.Task

  alias Pramana.Glossary
  alias Pramana.Sources

  @switches [source: :string, dry_run: :boolean]

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, args, _} = OptionParser.parse(argv, switches: @switches)

    path =
      List.first(args) || Mix.raise("usage: mix pramana.glossary.import <file> --source <id>")

    source_id = opts[:source] || Mix.raise("--source is required")

    unless File.exists?(path), do: Mix.raise("no such file: #{path}")

    terms = path |> File.read!() |> Glossary.parse()

    report(terms, path, source_id, opts[:dry_run])

    unless opts[:dry_run] do
      ensure_source!(source_id)
      {:ok, result} = Glossary.import(source_id, terms)
      Mix.shell().info("  imported #{result.imported} of #{result.total} term(s)\n")
    end
  end

  defp ensure_source!(source_id) do
    unless Pramana.Repo.get(Pramana.Corpus.Source, source_id) do
      Mix.raise("""
      no source #{inspect(source_id)} in the corpus.

      A glossary belongs to a source so that licence gating follows it. Add the text
      first with `mix pramana.local.add`, or pass an existing source id
      (#{Enum.join(Sources.ids(), ", ")} plus any local-* already added).
      """)
    end
  end

  defp report(terms, path, source_id, dry_run?) do
    unverified = Enum.filter(terms, &(&1.reading_status == "unverified"))
    rejected = Enum.filter(terms, &(&1.rejected_forms != []))

    origins =
      terms
      |> Enum.reject(&is_nil(&1.language_origin))
      |> Enum.frequencies_by(& &1.language_origin)

    Mix.shell().info("""

    #{if dry_run?, do: "DRY RUN — nothing written", else: "importing glossary"}
      file:   #{path}
      source: #{source_id}
      terms:  #{length(terms)}

      by category: #{terms |> Enum.frequencies_by(& &1.category) |> Enum.map_join(", ", fn {c, n} -> "#{c} #{n}" end)}
      reading origin stated: #{inspect(origins)}
    """)

    if rejected != [] do
      Mix.shell().info("  REJECTED RENDERINGS (a decision recorded is not a decision applied):")

      for t <- Enum.take(rejected, 8) do
        Mix.shell().info(
          "    #{t.term} → #{t.canonical_english} — not #{inspect(t.rejected_forms)}"
        )
      end

      Mix.shell().info("")
    end

    if unverified != [] do
      Mix.shell().info("  READING UNVERIFIED (kept as data, not dropped):")

      for t <- unverified do
        Mix.shell().info("    #{t.term} → #{t.canonical_english} (pinyin #{t.pinyin || "—"})")
      end

      Mix.shell().info("")
    end
  end
end
