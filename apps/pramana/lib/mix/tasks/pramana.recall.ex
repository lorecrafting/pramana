defmodule Mix.Tasks.Pramana.Recall do
  @shortdoc "Measures retrieval against the corpus's own verbatim quotations"

  @moduledoc """
  Retrieval recall, measured against ground truth nobody had to label.

      mix pramana.recall                          # 200 pairs
      mix pramana.recall --sample 2000 --seed 0.7 # reproducible

  See `Pramana.Recall`: 141,073 verbatim quotations are 141,073 statements that a passage
  occurs in two named works, and a search for that passage should surface both.

  **`--seed` makes it a measurement rather than an anecdote.** Without one the sample changes
  every run and no figure can be compared with the one before it.
  """

  use Mix.Task

  alias Pramana.Embed.Serving
  alias Pramana.Recall

  @switches [sample: :integer, limit: :integer, seed: :float, parallels: :boolean, mode: :string]

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _} = OptionParser.parse!(argv, strict: @switches)

    if opts[:parallels], do: parallels(opts), else: quotations(opts)
  end

  # THE AXIS THAT HAS NEVER MOVED. `topical/chinese` is 0% of twelve gold cases, and twelve
  # cases cannot be steered on. SuttaCentral's curated parallels are 10,493 Pāli↔Chinese
  # relevance judgements made by scholars — the same free ground truth, pointed at the weak
  # axis instead of the strong one.
  defp parallels(opts) do
    opts =
      opts
      |> Keyword.update(:mode, :hybrid, &mode/1)
      |> Keyword.put(:serving, Serving.name())

    result = Recall.parallels(opts)

    Mix.shell().info("""

      mode #{result.mode}, limit #{result.limit}

      control (same language)   #{show(result.control)}
      cross-lingual             #{show(result.cross_lingual)}
    """)

    case result.verdict do
      :void ->
        Mix.shell().error("""
          VOID — the same-language control did not find its own pairs, so the cross-lingual
          figure is not interpretable. That is a broken probe or an absent embedding serving,
          NOT evidence about cross-lingual retrieval. Run with PRAMANA_EMBEDDING=1.
        """)

      :measured ->
        for miss <- result.misses do
          Mix.shell().info("    miss  #{miss.from} -> #{miss.to}  #{miss.target_work}")
        end
    end
  end

  # An explicit map, not `String.to_existing_atom/1`: the atom for a mode nobody has mentioned
  # this run does not exist yet, and the failure is an ArgumentError about atoms rather than
  # a sentence about modes.
  defp mode("lexical"), do: :lexical
  defp mode("semantic"), do: :semantic
  defp mode("hybrid"), do: :hybrid
  defp mode(other), do: Mix.raise("unknown --mode #{inspect(other)}; use lexical|semantic|hybrid")

  defp show(%{found: found, decided: decided, rate: rate}) do
    pct = if rate, do: "#{Float.round(rate * 100, 1)}%", else: "n/a"
    "#{found}/#{decided} decided  #{pct}"
  end

  defp quotations(opts) do
    result = Recall.run(opts)

    Mix.shell().info("""

      sampled     #{result.sampled} quotation pair(s), limit #{result.limit}
      decided     #{result.decided}
      both works  #{result.both}
      one only    #{result.one}
      neither     #{result.neither}
      undecided   #{result.undecided}  (result set filled the cap — absence is not evidence)
    """)

    case result.recall do
      nil -> Mix.shell().info("  no decidable cases in this sample")
      recall -> Mix.shell().info("  recall #{Float.round(recall * 100, 1)}% over decided cases")
    end

    for miss <- result.misses do
      Mix.shell().info(
        "    #{miss.outcome}  #{miss.a_work} / #{miss.b_work}  #{miss.length} chars"
      )
    end
  end
end
