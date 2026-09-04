defmodule Mix.Tasks.Pramana.Recall do
  @shortdoc "Measures retrieval against the corpus's own verbatim quotations"

  @moduledoc """
  Retrieval recall, measured against ground truth nobody had to label.

      mix pramana.recall                          # 200 pairs
      mix pramana.recall --sample 2000 --seed 0.7 # reproducible
      mix pramana.recall --parallels              # the cross-lingual axis instead
      mix pramana.recall --renderings             # ...against true translations, not correspondences
      mix pramana.recall --parallels --concurrency 1   # ...serially, to compare against
      mix pramana.recall --renderings --to cbeta.T     # ...one canon, when it is a small share
      mix pramana.recall --renderings --translators model:mitra --translation-chunks-of model:qwen

  See `Pramana.Recall`: 141,073 verbatim quotations are 141,073 statements that a passage
  occurs in two named works, and a search for that passage should surface both.

  **`--seed` makes it a measurement rather than an anecdote.** Without one the sample changes
  every run and no figure can be compared with the one before it.

  **`--to` restricts `--renderings` to one target namespace** — `cbeta.T`, `sc.ms`,
  `derge.D` — and every figure it produces says so. It exists because a canon that is a
  small share of the rendering pool cannot otherwise be scored: English over the Chinese
  canon arrived as 3,354 renderings against 241,409, and an unfiltered 500-pair sample
  draws about seven of them.
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
    renderings: :boolean,
    mode: :string,
    concurrency: :integer,
    to: :string,
    translators: :string,
    # WHICH CHUNKS AN ARM'S ENGLISH COVERS, named by a translator that covers exactly
    # them. `--translators` stopped naming a fixed arm on 2026-09-03: the tranche grew
    # `model:mitra` from the ladder's 205 pilot chunks to 27,956 over 14 works under the
    # same id, so re-running the ladder by translator alone would compare a dense arm
    # against sparse ones and call the difference the model.
    translation_chunks_of: :string,
    # A vector-only control. The second stage reads renderings, so a run that means to
    # measure the vector index alone has to be able to switch it off — and until
    # 2026-09-03 it could not, which is why every arm was reranked against the whole
    # English layer. `Pramana.Retrieval.RenderingScope`.
    rerank: :boolean
  ]

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _} = OptionParser.parse!(argv, strict: @switches)

    require_semantic_arm!(opts, argv)

    cond do
      opts[:renderings] -> renderings(opts)
      opts[:parallels] -> parallels(opts)
      true -> quotations(opts)
    end
  end

  # A MEASUREMENT WITH ITS MAIN RETRIEVER MISSING IS NOT A LOW SCORE, IT IS NO SCORE.
  #
  # The serving is started only when `PRAMANA_EMBEDDING=1` or `config :pramana,
  # :embedding_serving`, and `Pramana.Retrieval` degrades to lexical-only without it —
  # deliberately, because a search should not crash. For a *probe* that is the wrong
  # trade: every English query then misses, because English words are not in the Chinese
  # or Pāli source text, and the run prints a confident **0.0%**.
  #
  # That is not hypothetical. `--renderings --to cbeta.T` was run this way on 2026-09-02
  # and returned `0/200 decided 0.0%`, against a baseline of 63.0%, and it read as a
  # catastrophic regression in the layer that had just been fixed. `Pramana.Retrieval`'s
  # own comment records the same failure arriving through a different door. Rule 17: a
  # dependency that degrades has to be loud somewhere, and the somewhere is here.
  defp require_semantic_arm!(opts, argv) do
    mode = if opts[:mode], do: mode(opts[:mode]), else: :hybrid

    if mode in [:hybrid, :semantic] and not Serving.available?() do
      Mix.raise("""
      mode #{mode} needs the embedding serving and it is not running, so only the lexical
      arm would answer and every cross-language case would miss. This prints 0.0%, which
      is not a result.

          PRAMANA_EMBEDDING=1 mix pramana.recall #{Enum.join(argv, " ")}

      Or set `config :pramana, :embedding_serving, true`. Use `--mode phrase` (or another
      lexical mode) if a lexical-only measurement is what you meant.
      """)
    end
  end

  # WHOSE ENGLISH IS IN THE INDEX WHILE THE PROBE RUNS — the option that makes one model
  # arm comparable with another.
  #
  # `--translators model:mitra` scores a corpus holding that arm's English and no other
  # translator's, queried with the HUMAN renderings the probe always samples. An arm
  # cannot be queried with its own output: its own vector is then the nearest neighbour
  # and every case is a hit by identity. `--translators none` removes every translation
  # vector, which is the control — what retrieval does with no English layer at all.
  defp translators(opts) do
    case opts[:translators] do
      nil -> opts
      "none" -> Keyword.put(opts, :translators, [])
      list -> Keyword.put(opts, :translators, String.split(list, ",", trim: true))
    end
  end

  # RESOLVED HERE, NOT IN THE RETRIEVAL LAYER. The task speaks translator ids because that
  # is what an experiment arm is named by; `Pramana.Retrieval.RenderingScope` speaks chunk
  # ids because that is what both stages can filter on. Resolving at the boundary keeps the
  # retrieval layer from having to know that an arm is a translator at all.
  #
  # It RAISES on an empty set rather than restricting to nothing, because "this translator
  # covers no chunks" is a typo in a translator id far more often than it is a measurement,
  # and the silent form of it scores every arm at the floor.
  defp translation_chunks(opts) do
    case opts[:translation_chunks_of] do
      nil ->
        opts

      translator ->
        ids = Pramana.Translations.chunks_covered(translator)

        if ids == [] do
          Mix.raise(
            "--translation-chunks-of #{inspect(translator)} covers no chunks; " <>
              "is that a translator id this corpus holds?"
          )
        end

        Mix.shell().info(
          "    English restricted to the #{length(ids)} chunk(s) #{translator} covers"
        )

        opts
        |> Keyword.delete(:translation_chunks_of)
        |> Keyword.put(:translation_chunks, ids)
    end
  end

  # `--translators none` now genuinely means no English anywhere in the path. It used to
  # mean "no English vectors, and rerank against every rendering in the corpus", which is
  # not a no-English control and was reported as one.

  # THE EXPERIMENT THAT DECIDES WHETHER § F'S TERM TABLE IS THE RIGHT BUILD.
  #
  # `--parallels` measures retrieval of a discourse CORRESPONDENCE across languages and gets
  # 0.4%. MITRA's benchmark scores BGE-M3 — this corpus's embedder — at 51% P@10 on
  # cross-lingual retrieval. Either the task is harder than theirs, or the retrieval path is
  # broken; the two call for opposite work and this tells them apart, by probing pairs that
  # really are translations of one another.
  defp renderings(opts) do
    opts =
      opts
      |> Keyword.update(:mode, :hybrid, &mode/1)
      |> Keyword.put(:serving, Serving.name())
      |> Keyword.put(:on_progress, progress())
      |> translators()
      |> translation_chunks()

    result = Recall.renderings(opts)

    Mix.shell().info("""

      mode #{result.mode}, limit #{result.limit}

      renderings -> their own source line   #{show(result.renderings)}#{scope(result.to)}
      by target language
    #{by_language(result.by_language)}

      Compare with `--parallels`. A high number here beside a low one there means the
      barrier is PARAPHRASE, not language, and § F's framing needs the rewrite rather than
      its retrieval. Low in both implicates the retrieval path.
    """)

    for hit <- result.hits do
      Mix.shell().info("""
          hit   rank #{hit.rank}, #{on_target(hit)}  -> #{hit.to}  #{hit.target_work}
                english  #{excerpt(hit.query)}
                matched  #{excerpt(hit.matched_text)}
      """)
    end

    for miss <- result.misses do
      Mix.shell().info("    miss  -> #{miss.to}  #{miss.target_work}  #{excerpt(miss.text)}")
    end
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
  defp scope(nil), do: ""
  defp scope(to), do: "\n      SAMPLED FROM #{to} ONLY — not the whole pool"

  # Every namespace with its own denominator. A bare hit count here is the failure this
  # project is most prone to; see `Pramana.Recall.by_language/1`'s comment.
  defp by_language(by_language) do
    by_language
    |> Enum.sort_by(fn {namespace, _} -> namespace end)
    |> Enum.map_join("\n    ", fn {namespace, scored} ->
      "  #{String.pad_trailing(namespace, 12)} #{show(scored)}"
    end)
  end

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
