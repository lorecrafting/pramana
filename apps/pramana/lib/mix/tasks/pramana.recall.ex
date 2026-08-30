defmodule Mix.Tasks.Pramana.Recall do
  @shortdoc "Measures retrieval against the corpus's own verbatim quotations"

  @moduledoc """
  Retrieval recall, measured against ground truth nobody had to label.

      mix pramana.recall                          # 200 pairs
      mix pramana.recall --sample 2000 --seed 0.7 # reproducible
      mix pramana.recall --parallels              # the cross-lingual axis instead
      mix pramana.recall --parallels --concurrency 1   # ...serially, to compare against

  See `Pramana.Recall`: 141,073 verbatim quotations are 141,073 statements that a passage
  occurs in two named works, and a search for that passage should surface both.

  **`--seed` makes it a measurement rather than an anecdote.** Without one the sample changes
  every run and no figure can be compared with the one before it.
  """

  use Mix.Task

  alias Pramana.Embed.Serving
  alias Pramana.Recall
  alias Pramana.Retrieval

  # `--concurrency` exists to be able to PROVE the concurrency changed nothing: same seed at
  # 1 and at 6, compared case by case. A speedup that moves the numbers is not a speedup.
  @switches [
    sample: :integer,
    limit: :integer,
    seed: :float,
    parallels: :boolean,
    mode: :string,
    concurrency: :integer
  ]

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
      |> Keyword.put(:on_progress, progress())

    result = Recall.parallels(opts)

    Mix.shell().info("""

      mode #{result.mode}, limit #{result.limit}

      control (same language)   #{show(result.control)}
      cross-lingual             #{show(result.cross_lingual)}
      cross vs same             #{relative(result.relative)}
    """)

    case result.verdict do
      :void ->
        Mix.shell().error("""
          VOID — the same-language control did not find its own pairs, so the cross-lingual
          figure is not interpretable. That is a broken probe or an absent embedding serving,
          NOT evidence about cross-lingual retrieval. Run with PRAMANA_EMBEDDING=1.
        """)

      :measured ->
        # HITS FIRST, AND THAT IS THE POINT OF PRINTING THEM. At 0.4% the misses are the
        # whole distribution and carry no information; the two that landed are the only
        # evidence this run holds about what crosses the language barrier.
        for hit <- result.hits do
          Mix.shell().info("""
              hit   rank #{hit.rank}, #{on_target(hit)}  #{hit.from} -> #{hit.to}  #{hit.target_work}
                    query    #{excerpt(hit.query)}
                    matched  #{excerpt(hit.matched_text)}
                    at       #{hit.matched_urn}
          """)
        end

        for miss <- result.misses do
          Mix.shell().info("    miss  #{miss.from} -> #{miss.to}  #{miss.target_work}")
        end
    end
  end

  # Recall here is WORK-level, so a hit means one of two very different things and printing
  # them identically would overstate the weaker one. See `Pramana.Recall.hit/4`.
  defp on_target(%{exact_rank: nil}), do: "the work but NOT the parallel line"
  defp on_target(%{exact_rank: rank}), do: "the parallel line itself at rank #{rank}"

  # `String.slice/3`, never `binary_part/3`: these are CJK and Tibetan passages, and a byte
  # slice cuts a codepoint in half.
  defp excerpt(text) do
    flat = String.replace(text, "\n", " ")
    if String.length(flat) > 70, do: String.slice(flat, 0, 70) <> "…", else: flat
  end

  # SIXTY-TWO MINUTES, PRINTING NOTHING. That is how long a run of 500 takes, and the first
  # version reported only at the end — so a broken printer wasted an entire run before it
  # could be seen, and the answer to "how much longer" was a guess that was wrong twice.
  #
  # Throughput is what makes it answerable, so the line carries seconds-per-case and an ETA
  # derived from THIS run rather than from the last one.
  @every 25

  defp progress do
    started = System.monotonic_time(:millisecond)
    found = :counters.new(1, [])

    fn %{phase: phase, done: done, total: total} = p ->
      # The two phases run in sequence and share the counter, so it resets on each first case.
      if done == 1, do: :counters.put(found, 1, 0)
      if p.outcome == :found, do: :counters.add(found, 1, 1)

      if rem(done, @every) == 0 or done == total do
        # Rate and ETA span the WHOLE run, not this phase: `eta` for the cross phase alone
        # read 22m with 125 control cases still queued behind it.
        per_case = (System.monotonic_time(:millisecond) - started) / p.overall_done
        left = (p.overall_total - p.overall_done) * per_case

        Mix.shell().info(
          "    #{phase}  #{done}/#{total}  found #{:counters.get(found, 1)}  " <>
            "#{Float.round(per_case / 1000, 1)} s/case  eta #{eta(left)} (whole run)"
        )
      end
    end
  end

  defp eta(ms) when ms < 60_000, do: "#{round(ms / 1000)}s"
  defp eta(ms), do: "#{round(ms / 60_000)}m"

  # VALIDATED AGAINST THE REAL LIST, not a hand-written one.
  #
  # This offered `lexical`, which is **not a mode**: `Pramana.Retrieval`'s table is hybrid,
  # semantic, auto, phrase, ngram, terms, and an unrecognised name falls back to `:hybrid`
  # deliberately — a mode is a preference and an unknown one has an obviously right answer.
  #
  # So `--mode lexical` ran HYBRID while printing "lexical", and the 3.6 s per query it cost
  # was hybrid without a serving, not a slow lexical path. A second list of modes maintained
  # beside the first is how a task ends up offering something that does not exist.
  defp mode(name) do
    if name in Retrieval.modes() do
      Retrieval.mode(name)
    else
      Mix.raise(
        "unknown --mode #{inspect(name)}; use one of #{Enum.join(Retrieval.modes(), ", ")}"
      )
    end
  end

  # The control is the REFERENCE, not the bar. Cross-lingual recall alone is moved by the
  # corpus, the cap and the sheer difficulty of retrieving a paraphrase; against the same task
  # in one language it becomes a statement about the language barrier specifically.
  defp relative(nil), do: "n/a — no same-language baseline to compare against"
  defp relative(ratio), do: "#{Float.round(ratio * 100, 1)}% of same-language recall"

  # TWO NUMBERS, because the first one overcredits. `found` is work-level and a stock
  # formula can earn it; `on line` requires the parallel's own target line. See
  # `Pramana.Recall.score/1`.
  defp show(%{found: found, decided: decided, rate: rate} = s) do
    pct = if rate, do: "#{Float.round(rate * 100, 1)}%", else: "n/a"
    line_pct = if s.line_rate, do: "#{Float.round(s.line_rate * 100, 1)}%", else: "n/a"
    "#{found}/#{decided} decided  #{pct}   on line #{s.on_line}  #{line_pct}"
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
