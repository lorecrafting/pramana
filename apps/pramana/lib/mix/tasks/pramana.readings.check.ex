defmodule Mix.Tasks.Pramana.Readings.Check do
  @shortdoc "Scores the reading layer against the Buddhist test set"

  @moduledoc """
  Runs `priv/readings/buddhist_test_set.tsv` and reports both methods.

      mix pramana.readings.check
      mix pramana.readings.check --verbose

  The exit criterion for #24 is *"line-by-line readings correct on a Buddhist-vocabulary
  test set that a generic library fails"*, so the generic method is scored **in the same
  run** rather than asserted. `naive` is Unihan's `kMandarin` applied character by
  character, which is what a per-character library does; its score is the claim being
  tested, and if it ever rises the claim needs revisiting rather than defending.
  """

  use Mix.Task

  alias Pramana.Readings

  @switches [verbose: :boolean]

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _} = OptionParser.parse!(argv, strict: @switches)

    results = Readings.score_test_set()

    if opts[:verbose] do
      Mix.shell().info("")
      Enum.each(results.rows, &Mix.shell().info(line(&1)))
    end

    total = length(results.rows)

    Mix.shell().info("""

    Buddhist reading test set — #{total} form(s), #{results.occurrences} corpus occurrence(s)

      per-character (Unihan kMandarin):  #{results.naive_correct}/#{total}  #{pct(results.naive_correct, total)}
      reading dictionary:                #{results.correct}/#{total}  #{pct(results.correct, total)}

      of the #{total - results.naive_correct} forms the per-character method gets wrong,
      the dictionary gets #{results.fixed} right#{if results.broken > 0, do: " and BREAKS #{results.broken} it had right", else: ", breaking none it had right"}.
    """)

    if results.correct < total do
      Mix.raise("#{total - results.correct} form(s) read incorrectly — run with --verbose")
    end
  end

  # `×` marks the rows the per-character method gets wrong — the ones this layer exists
  # for. The rest are controls, and they must keep passing.
  defp line(row) do
    flag = if row.correct?, do: "ok  ", else: "FAIL"
    naive = if row.naive_correct?, do: " ", else: "×"

    "  #{flag} #{naive} #{String.pad_trailing(row.form, 12)} " <>
      "#{String.pad_trailing(row.actual, 24)} naive=#{row.naive}"
  end

  defp pct(_n, 0), do: "—"
  defp pct(n, total), do: "#{Float.round(n * 100 / total, 1)}%"
end
