defmodule Mix.Tasks.Pramana.Readings.Build do
  @shortdoc "Derives the reading dictionary from Unihan and CC-CEDICT"

  @moduledoc """
  Builds `priv/readings/*.tsv` from the two raw dictionaries.

      mix pramana.readings.build
      mix pramana.readings.build --corpus      # keep only forms the canon actually uses
      mix pramana.readings.build --dry-run

  Reads `raw/unihan/Unihan_Readings.txt` and `raw/cedict/*.txt`, applies the four filters
  in `Pramana.Readings.Build`, checks the hand-curated overrides against Unihan, and
  writes the result as TSV. The TSVs are committed; the raw dictionaries are not, exactly
  as with every other source.

  ## The overrides are checked, not trusted

  `buddhist_overrides.tsv` is the one hand-written file in the pipeline, so it gets the
  strictest treatment: every syllable must be attested by Unihan for that character, and
  a single unattested syllable **aborts the build**. A hand-written line is where an
  invented reading would enter, and the point of a derivation is that nothing enters
  without a source.
  """

  use Mix.Task

  import Ecto.Query

  alias Pramana.Corpus.Segment
  alias Pramana.Readings.Build
  alias Pramana.Repo

  @switches [corpus: :boolean, dry_run: :boolean]

  @unihan "raw/unihan/Unihan_Readings.txt"
  @cedict "raw/cedict"
  @out "apps/pramana/priv/readings"

  @impl Mix.Task
  def run(argv) do
    {opts, _} = OptionParser.parse!(argv, strict: @switches)
    if opts[:corpus], do: Mix.Task.run("app.start")

    unihan = @unihan |> path!() |> File.stream!() |> Build.unihan()
    Mix.shell().info("  unihan:  #{map_size(unihan)} character(s) with readings")

    cedict = @cedict |> path!() |> cedict_file!() |> File.stream!() |> Build.cedict()
    {singles, compounds} = cedict
    Mix.shell().info("  cedict:  #{map_size(singles)} single, #{length(compounds)} compound")

    overrides = load_overrides!(unihan)
    Mix.shell().info("  curated: #{length(overrides)} override(s), all attested")

    %{exceptions: derived, rejected: rejected} =
      Build.exceptions(unihan, cedict, fn _ -> true end)

    report(derived, rejected, overrides)
    if opts[:corpus], do: coverage(derived ++ overrides)

    unless opts[:dry_run] do
      write_characters(unihan)
      write_exceptions(derived, overrides)
      Mix.shell().info("\n  wrote #{@out}/character_readings.tsv and exceptions.tsv\n")
    end
  end

  defp report(derived, rejected, overrides) do
    buddhist = Enum.count(derived, & &1.buddhist?)

    Mix.shell().info("""

    reading exceptions
      derived:           #{length(derived)}
        Buddhist-marked: #{buddhist}
      curated:           #{length(overrides)}

      rejected
        polyphonic:      #{rejected.polyphonic}  (character has >1 context-free reading — cannot be resolved without context)
        neutral tone:    #{rejected.neutral_tone}  (modern 輕聲 erosion, not a fact about Literary Chinese)
        unattested:      #{rejected.unattested}  (CC-CEDICT syllable Unihan does not record for that character)
    """)
  end

  # Loaded and validated here rather than at import, so a bad line fails the build that
  # produces the artifact instead of the run that consumes it.
  defp load_overrides!(unihan) do
    rows =
      Path.join(@out, "buddhist_overrides.tsv")
      |> path!()
      |> File.stream!()
      |> Stream.map(&String.trim_trailing(&1, "\n"))
      |> Stream.reject(&(&1 == "" or String.starts_with?(&1, "#")))
      |> Enum.map(fn line ->
        case String.split(line, "\t") do
          [form, reading, basis] -> %{form: form, reading: reading, basis: basis}
          _ -> Mix.raise("malformed override line: #{inspect(line)}")
        end
      end)

    case Enum.reject(rows, &Build.attested?(unihan, &1.form, &1.reading)) do
      [] ->
        rows

      bad ->
        Mix.raise("""
        #{length(bad)} override(s) assert a reading Unihan does not attest:

        #{Enum.map_join(bad, "\n", &"  #{&1.form}\t#{&1.reading}")}

        Every syllable must appear in that character's attested set. If the reading is
        genuinely right and Unihan lacks it, the entry needs a different authority
        recorded — not a relaxed check.
        """)
    end
  end

  # How much of the canon this dictionary actually speaks to. Reported, not enforced: a
  # reading dictionary describes the language, and scoping the artifact to whichever texts
  # happen to be loaded today would make it wrong the moment a corpus is added.
  #
  # ONE PASS, not one query per form. The obvious version — `LIKE '%form%'` per form,
  # leaning on the pg_bigm index — measured 1.3 SECONDS each, because a form that does
  # NOT occur is the expensive case: the index has to be walked to prove absence. At
  # 13,000 forms that is three and a half hours to answer a question the corpus can
  # answer in one read. Index-per-item beats a scan only when the items are few.
  defp coverage(rows) do
    forms = Map.new(rows, &{&1.form, 0})
    starts = MapSet.new(Map.keys(forms), &String.first/1)

    # Repo.stream only holds a cursor open inside a transaction; reducing outside one
    # would silently fall back to loading every segment.
    {:ok, counts} =
      Repo.transaction(
        fn ->
          from(s in Segment, select: s.content)
          |> Repo.stream(max_rows: 10_000)
          |> Enum.reduce(forms, fn content, acc ->
            count_in(String.graphemes(content), starts, acc)
          end)
        end,
        timeout: :infinity
      )

    present = counts |> Map.values() |> Enum.count(&(&1 > 0))

    Mix.shell().info("""
      corpus coverage
        forms occurring:   #{present} of #{map_size(counts)}
        occurrences:       #{counts |> Map.values() |> Enum.sum()}
    """)
  end

  defp count_in([], _starts, acc), do: acc

  defp count_in([char | rest] = chars, starts, acc) do
    acc = if MapSet.member?(starts, char), do: count_at(chars, acc), else: acc
    count_in(rest, starts, acc)
  end

  # Every window starting here, longest first. Overlapping windows all count: a form
  # occurring inside a longer form is still an occurrence of it.
  defp count_at(chars, acc) do
    Enum.reduce(min(8, length(chars))..1//-1, acc, fn len, acc ->
      form = chars |> Enum.take(len) |> Enum.join()
      if Map.has_key?(acc, form), do: Map.update!(acc, form, &(&1 + 1)), else: acc
    end)
  end

  defp write_characters(unihan) do
    rows =
      unihan
      |> Enum.filter(fn {_char, %{preferred: preferred}} -> preferred end)
      |> Enum.sort()
      |> Enum.map(fn {char, %{preferred: preferred, attested: attested}} ->
        # The preferred reading must be in its own attested set; kMandarin contributes to
        # it, so this holds by construction and the database constraint re-checks it.
        [char, preferred, attested |> MapSet.to_list() |> Enum.sort() |> Enum.join("|")]
        |> Enum.join("\t")
      end)

    write!("character_readings.tsv", ["# character\treading\tattested" | rows])
  end

  defp write_exceptions(derived, overrides) do
    curated =
      Enum.map(overrides, fn row ->
        Enum.join([row.form, row.reading, "", "curated", row.basis], "\t")
      end)

    rows =
      Enum.map(derived, fn row ->
        kind = if row.buddhist?, do: "cc-cedict-buddhist", else: "cc-cedict"
        Enum.join([row.form, row.reading, row.naive, kind, String.slice(row.gloss, 0, 120)], "\t")
      end)

    # Curated LAST: `Pramana.Readings.import_dictionary/1` keeps the last row for a form,
    # so a hand-checked entry beats the derived one where both cover the same word.
    write!("exceptions.tsv", ["# form\treading\tnaive\tauthority\tnote" | rows ++ curated])
  end

  defp write!(name, lines) do
    File.mkdir_p!(@out)
    File.write!(Path.join(@out, name), Enum.join(lines, "\n") <> "\n")
  end

  defp path!(relative) do
    expanded = Path.expand(relative, File.cwd!())
    unless File.exists?(expanded), do: Mix.raise("missing #{relative} — see docs/SOURCES.md")
    expanded
  end

  defp cedict_file!(dir) do
    case Path.wildcard(Path.join(dir, "*.txt")) do
      [file | _] -> file
      [] -> Mix.raise("no CC-CEDICT .txt in #{dir}")
    end
  end
end
