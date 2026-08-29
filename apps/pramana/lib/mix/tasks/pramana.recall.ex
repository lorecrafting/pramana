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

  alias Pramana.Recall

  @switches [sample: :integer, limit: :integer, seed: :float]

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _} = OptionParser.parse!(argv, strict: @switches)

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
