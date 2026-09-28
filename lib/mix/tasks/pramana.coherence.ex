defmodule Mix.Tasks.Pramana.Coherence do
  @shortdoc "Cross-checks independently derived facts about the same works"

  @moduledoc """
  The third data check, beside `verify` and `integrity`.

      mix pramana.coherence          # every check, exits non-zero if one fails
      mix pramana.coherence --report # print and always exit 0

  `verify` proves the pipeline is deterministic. `integrity` proves nothing printed was lost.
  Both were green over 122 works labelled Japanese that are Chinese compositions, because
  those works were faithfully and reproducibly mislabelled. This asks the question neither
  can: **do two independently derived facts about the same work agree?**

  See `Pramana.Coherence` for why every check is a rate with a floor and a minimum
  population, and why a disagreement is a question for a person rather than an instruction
  to a script.

  ## Reading the output

  `undecided` is a real result. A check whose population is under the minimum has not passed
  — it has declined to judge, and saying so is the difference between this and a check that
  reports success it never earned.
  """

  use Mix.Task

  alias Pramana.Coherence

  @switches [report: :boolean]

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _} = OptionParser.parse!(argv, strict: @switches)

    results = Coherence.run()

    Enum.each(results, &print/1)

    failed = Enum.filter(results, &(&1.status == :failed))

    cond do
      opts[:report] ->
        :ok

      failed == [] ->
        Mix.shell().info([:green, "\n  coherence OK", :reset, " — #{length(results)} check(s)"])

      true ->
        Mix.raise("""
        #{length(failed)} coherence check(s) below their floor:

        #{Enum.map_join(failed, "\n", &"      #{&1.id}  #{percent(&1.rate)} < #{percent(&1.floor)}")}

        A disagreement is a question, not a defect by itself — read the detail above and
        decide which of the two sources is wrong. `--report` prints without failing.
        """)
    end
  end

  defp print(result) do
    Mix.shell().info([
      "\n  ",
      colour(result.status),
      String.pad_trailing(to_string(result.status), 10),
      :reset,
      result.id
    ])

    Mix.shell().info("      #{result.question}")

    Mix.shell().info(
      "      #{result.agreed}/#{result.total}" <>
        case result.rate do
          nil -> "  (under the minimum population — not judged)"
          rate -> "  #{percent(rate)}, floor #{percent(result.floor)}"
        end
    )

    for line <- result.detail, do: Mix.shell().info("        #{line}")
  end

  defp colour(:ok), do: :green
  defp colour(:failed), do: :red
  defp colour(:undecided), do: :yellow

  defp percent(nil), do: "n/a"
  defp percent(rate), do: "#{Float.round(rate * 100, 1)}%"
end
