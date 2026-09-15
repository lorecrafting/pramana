defmodule Mix.Tasks.Pramana.Evals do
  @shortdoc "Scores retrieval, citation and provenance against the gold set"

  @moduledoc """
  Runs `evals/gold/*.jsonl` and prints a scorecard.

      mix pramana.evals
      mix pramana.evals --only retrieval
      mix pramana.evals --json evals/scorecard.json
      mix pramana.evals --gate            # non-zero exit on a regression
      mix pramana.evals --gate --accept   # ...and adopt this run as the new baseline
      mix pramana.evals --per-tradition   # experiment: retrieve per canon, then merge
      mix pramana.evals --only retrieval --tradition tibetan --depth 200
      mix pramana.evals --rrf-k 30 --rerank-multiplier 8 --json evals/experiments/k30m8.json

  Retrieval cases need the embedding model, so run with `PRAMANA_EMBEDDING=1`; without
  it the harness says so and scores the lexical path only, rather than reporting a
  number that quietly measures half the system.

  ## The gate

  `--gate` compares against `evals/baseline.json` and exits non-zero if any case type
  drops. It is a **ratchet**, like the coverage threshold: a number that goes up gets
  recorded, and one that goes down fails the build rather than being explained away.

  ## ▸ A NUMBER THAT GOES UP WAS NOT ACTUALLY GETTING RECORDED — 2026-09-03

  The paragraph above described an intent. `gate/2` writes `evals/baseline.json` **only
  when none exists**; with one present it compares and never updates. So a run scoring
  **1,364 of 1,472 passed against a baseline recording 1,359**, the five-case gain was
  never adopted, and a later regression back to 1,359 would have been measured against the
  old number and passed in silence. A ratchet that only ever holds its first position is a
  floor, not a ratchet.

  **A pass now says so**, naming every case type that moved and in which direction —
  because a net figure alone would hide the real displacement inside an improvement, which
  is what `topical/chinese` +6 and `retrieval/pali` −1 actually were.

  **`--accept` adopts the run**, and it is a separate flag on purpose. Advancing
  automatically on every pass would ratchet a run nobody reviewed; failing the gate when
  the system improves would train everyone to ignore it. So the gate reports, a person
  looks at the movements, and one command records them. `docs/PLAN.md` item 9.
  """

  use Mix.Task

  alias Pramana.Embed.Serving
  alias Pramana.Evals
  alias Pramana.Evals.Case, as: GoldCase
  alias Pramana.Evals.Score

  @switches [
    only: :string,
    json: :string,
    gate: :boolean,
    dir: :string,
    baseline: :string,
    # ADOPTING the current run as the new ratchet. Separate from `--gate` because it is a
    # decision: `gate/2` writes a baseline only when none exists, so every improvement
    # since the first run has gone unadopted and a later regression to the old number
    # would pass in silence. `docs/PLAN.md` item 9.
    accept: :boolean,
    # Experiment flags. They OVERRIDE every case's own search options, so a run that
    # uses them is measuring a configuration rather than the shipped default — which is
    # the point, and why the header says so.
    vector_kinds: :string,
    balance: :string,
    per_tradition: :boolean,
    depth: :integer,
    lexical_depth: :integer,
    semantic_depth: :integer,
    expand_terms: :boolean,
    rerank: :boolean,
    rrf_k: :integer,
    rerank_multiplier: :integer,
    # Not an override — a FILTER. Scoring one tradition is how an experiment aimed at one
    # canon stays affordable; the decision still needs the whole set.
    tradition: :string
  ]

  @default_baseline "evals/baseline.json"

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _} = OptionParser.parse!(argv, strict: @switches)

    dir = Keyword.get(opts, :dir, "evals/gold")

    cases =
      case Evals.load(dir) do
        {:ok, cases} ->
          cases

        {:error, {:no_gold_set, dir}} ->
          Mix.raise("no gold set in #{dir} — run mix pramana.evals.derive")
      end

    validate_tradition!(opts, cases)
    refuse_narrowed_gate!(opts)

    warn_if_no_embeddings()

    started = System.monotonic_time(:millisecond)
    scorecard = Evals.run(cases, run_opts(opts))
    elapsed = System.monotonic_time(:millisecond) - started

    Mix.shell().info(Score.render(scorecard))

    # Printed even on a green run. Two runtimes were published as measurements in
    # `docs/CHECKS.md` and both were wrong — one extrapolated from a case count, one read
    # off a wall clock across a sleeping laptop. A task that times itself cannot produce
    # either, and the RATE is what stays comparable when the gold set grows, which it did
    # 5.6x in a day.
    # `scorecard.total`, not `length(cases)`: with `--only` those differ by the whole gold
    # set, and the run that motivated this reported "ran 1400 case(s) ... 3.5 cases/s" for
    # a run that scored 49 — a rate 28x off. The same class of error as the two runtimes
    # `docs/CHECKS.md` had to correct; a task that times itself must also count itself.
    Mix.shell().info(
      "  ran #{scorecard.total} case(s) in #{Pramana.Elapsed.human(elapsed)} " <>
        "(#{Pramana.Elapsed.rate(scorecard.total, elapsed)} cases/s)\n"
    )

    if path = opts[:json], do: write_json(path, scorecard)

    if opts[:gate],
      do:
        gate(
          scorecard,
          Keyword.get(opts, :baseline, @default_baseline),
          Keyword.get(opts, :accept, false)
        )
  end

  # A misspelled tradition selects nothing, and "0 case(s)" is a weak signal next to a
  # scorecard that otherwise looks normal. `--only` already raises on an unknown case
  # type; this is the same rule for the same reason.
  defp validate_tradition!(opts, cases) do
    case opts[:tradition] do
      nil ->
        :ok

      tradition ->
        known = cases |> Enum.map(& &1.tradition) |> Enum.reject(&is_nil/1) |> Enum.uniq()

        unless tradition in known do
          Mix.raise(
            "unknown tradition #{inspect(tradition)}; the gold set has: " <>
              Enum.join(Enum.sort(known), ", ")
          )
        end
    end
  end

  # The gate is a RATCHET ON THE SHIPPED DEFAULT, and neither a narrowed run nor an
  # experiment is that.
  #
  # `--tradition` narrows the set while leaving the by_type rows the gate compares, so
  # `--tradition tibetan --gate` reads 20 hits against a baseline of 327 and reports a
  # 307-case regression that did not happen. `--only` is safe by contrast: a type absent
  # from the run is skipped rather than counted as zero.
  #
  # An override is worse than noisy. `gate/2` WRITES the current run as the baseline when
  # none exists, so `--per-tradition --gate` on a fresh checkout would install an
  # experiment as the thing every future run is measured against.
  defp refuse_narrowed_gate!(opts) do
    cond do
      !opts[:gate] ->
        :ok

      opts[:tradition] ->
        Mix.raise(
          "--gate cannot be combined with --tradition: the gate compares by case TYPE " <>
            "against a full-set baseline, so a narrowed run reports a regression that " <>
            "did not happen. Run the gate on the whole set."
        )

      experiment?(opts) ->
        Mix.raise(
          "--gate cannot be combined with an experiment flag (--depth, --per-tradition, " <>
            "--vector-kinds, --balance): the gate is a ratchet on the SHIPPED default, " <>
            "and with no baseline present it would write this configuration as one."
        )

      true ->
        :ok
    end
  end

  defp experiment?(opts) do
    Enum.any?(
      [:depth, :lexical_depth, :semantic_depth, :per_tradition, :vector_kinds, :balance],
      &(opts[&1] != nil)
    )
  end

  defp run_opts(opts) do
    only(opts) ++ tradition(opts) ++ overrides(opts) ++ [on_progress: &progress/3]
  end

  # A heartbeat on one line, rewritten in place. The full set takes hours and printed
  # nothing at all until it finished — so "how far along is it" had no answer, and a run
  # that had died was indistinguishable from one still working. Both happened today.
  #
  # Every 10 cases rather than every case: the point is to show liveness and a projection,
  # not to compete with the scorecard for the terminal.
  @progress_every 10

  # PROJECTED FROM A TRAILING WINDOW, NOT FROM THE AVERAGE — and the difference is a
  # factor of three.
  #
  # The 1,472 cases are two populations about 175x apart in cost. The ~930 that touch no
  # embedder finish in **twelve seconds**, roughly 13 ms each; the ~540 after them embed a
  # query and run a hybrid search at ~2.3 s. Dividing total elapsed by cases done averages
  # across both and predicts neither: measured on 2026-09-01 the estimate read
  # `~2m01s left` at case 1,310 while the marginal rate said six minutes, and it took
  # 4m47s.
  #
  # That is rule 69 — a figure pooled over unlike populations — in this project's own
  # tooling, and in the flattering direction, which is the one this codebase keeps having
  # to correct.
  #
  # The window is the gap between two ticks, so `@progress_every` sets it: ten cases, which
  # is noisy on its own and is being read once a second by a person watching a bar rather
  # than recorded as a measurement. An estimate that tracks what the run is doing NOW and
  # jitters is more use than a smooth one that is wrong by 3x.

  defp progress(done, total, elapsed_ms) do
    if rem(done, @progress_every) == 0 or done == total do
      IO.write(
        :stderr,
        "\r  #{done}/#{total} cases · #{Pramana.Elapsed.human(elapsed_ms)} elapsed · " <>
          "~#{Pramana.Elapsed.human(remaining_ms(done, total, elapsed_ms))} left    "
      )
    end

    if done == total, do: IO.write(:stderr, "\n")
    :ok
  end

  # Held in the process dictionary rather than threaded through `Evals.run/1`: this is a
  # terminal heartbeat, and giving the scoring loop an accumulator so its progress printer
  # can be smarter would be the reporting tail wagging the measurement.
  defp remaining_ms(done, total, elapsed_ms) do
    prior = Process.get(:evals_progress_window)
    Process.put(:evals_progress_window, {done, elapsed_ms})

    case prior do
      {prior_done, prior_ms} when done > prior_done and elapsed_ms > prior_ms ->
        rate = (done - prior_done) * 1000 / (elapsed_ms - prior_ms)
        if rate > 0, do: round((total - done) / rate * 1000), else: 0

      _ ->
        # First tick, or a window with no elapsed time in it — fall back to the average,
        # which is all there is to go on before two samples exist.
        rate = done * 1000 / max(elapsed_ms, 1)
        if rate > 0, do: round((total - done) / rate * 1000), else: 0
    end
  end

  defp tradition(opts) do
    case opts[:tradition] do
      nil -> []
      tradition -> [tradition: tradition]
    end
  end

  defp overrides(opts) do
    kinds = opts[:vector_kinds] && String.split(opts[:vector_kinds], ",", trim: true)
    balance = opts[:balance] && String.to_existing_atom(opts[:balance])

    override =
      [
        vector_kinds: kinds,
        balance: balance,
        per_tradition: opts[:per_tradition],
        depth: opts[:depth],
        lexical_depth: opts[:lexical_depth],
        semantic_depth: opts[:semantic_depth],
        expand_terms: opts[:expand_terms],
        rerank: opts[:rerank],
        rrf_k: opts[:rrf_k],
        rerank_multiplier: opts[:rerank_multiplier]
      ]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    if override == [] do
      []
    else
      Mix.shell().info([
        :yellow,
        "  CONFIGURATION OVERRIDE: #{inspect(override)}\n" <>
          "  This is an experiment, not the shipped default.\n",
        :reset
      ])

      [search_override: override]
    end
  end

  defp only(opts) do
    case opts[:only] do
      nil ->
        []

      name ->
        case Enum.find(GoldCase.types(), &(&1 == name)) do
          nil -> Mix.raise("unknown case type #{inspect(name)}")
          _ -> [only: GoldCase.type_atom(name)]
        end
    end
  end

  # Semantic search is opt-in because loading BGE-M3 costs ~80s and 2.2GB. A retrieval
  # score measured without it is a score for the lexical retriever alone — a real number,
  # but not the one the README quotes, so the difference is stated rather than left to be
  # inferred from a lower figure.
  defp warn_if_no_embeddings do
    unless Serving.available?() do
      Mix.shell().info([
        :yellow,
        "\n  NOTE: the embedding serving is not running, so retrieval cases score the\n" <>
          "  LEXICAL path only. Re-run with PRAMANA_EMBEDDING=1 for the full number.\n",
        :reset
      ])
    end
  end

  defp write_json(path, scorecard) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(Score.to_map(scorecard), pretty: true) <> "\n")
    Mix.shell().info("  wrote #{path}")
  end

  defp write_json_map(path, map) do
    File.write!(path, Jason.encode!(map, pretty: true) <> "\n")
    Mix.shell().info("  wrote #{path}")
  end

  defp gate(scorecard, baseline_path, accept?) do
    refuse_errored_gate!(scorecard)

    case File.read(baseline_path) do
      {:error, :enoent} ->
        Mix.shell().info("  no baseline at #{baseline_path} — writing this run as the baseline")
        write_json(baseline_path, scorecard)

      {:ok, contents} ->
        compare(Score.to_map(scorecard), Jason.decode!(contents), baseline_path, accept?)
    end
  end

  # An errored case is a hit the run never got to attempt, so the gate would read it as a
  # retrieval regression that never happened — or, with no baseline on disk, WRITE the
  # under-measured run as the thing every future run is ratcheted against. Neither is
  # recoverable by squinting at the number afterwards, so the gate refuses to run at all.
  defp refuse_errored_gate!(%{errors: []}), do: :ok

  defp refuse_errored_gate!(%{errors: errors}) do
    detail =
      Enum.map_join(Enum.take(errors, 5), "\n", fn %{case: kase, outcome: {:error, d}} ->
        "  #{kase.id}: #{d.kind} — #{String.slice(d.message, 0, 160)}"
      end)

    Mix.raise(
      "--gate refuses a run with #{length(errors)} errored case(s). They are missing " <>
        "hits, so the gate would report a regression that did not happen, or install an " <>
        "under-measured run as the baseline. Fix the errors and re-run.\n" <> detail
    )
  end

  # A gate that trips on one case flipping gets ignored, and an ignored gate is worse
  # than none. Approximate nearest-neighbour search with `relaxed_order` does not return
  # a fixed ordering, and two runs of the identical build differed by exactly one case in
  # each of `retrieval` (68.0 -> 66.7) and `topical` (60.0 -> 57.5). So the threshold is
  # in CASES, not percentage points: one may flip, two is a real regression.
  #
  # This also means a genuine one-case improvement will not be caught by the ratchet.
  # That is the right trade — a benchmark's job is to catch a system getting worse, and
  # crying wolf costs more than missing a small win.
  @tolerated_case_drop 1

  @doc """
  How far the baseline on disk has fallen behind the run that just passed.

  **A green gate is not evidence that the baseline is current, and on 2026-09-03 it was
  neither.** `gate/2` writes `evals/baseline.json` only when none exists; with one present
  it compares and never updates. So a run scoring 1,364 of 1,472 passed against a baseline
  recording 1,359, the five-case gain was never adopted, and a later regression down to
  1,359 would have been measured against the old number and passed in silence.

  Reported rather than failed, deliberately: **a benchmark that goes red when the system
  improves gets ignored, and an ignored gate is worse than none.** What was missing is the
  sentence saying the ratchet has drifted and the one command that advances it. Pure so it
  can be tested — `docs/PLAN.md` item 9 asks for a test that a pass cannot quietly retain
  an obsolete baseline, and a function that writes to `Mix.shell()` cannot provide one.
  """
  @spec drift(map(), map()) :: map()
  def drift(current, baseline) do
    types =
      for {type, %{"hits" => was}} <- baseline["by_type"] || %{},
          is_number(was),
          now = get_in(current, ["by_type", type, "hits"]),
          is_number(now),
          now != was,
          do: {type, was, now}

    gained = types |> Enum.filter(fn {_t, was, now} -> now > was end) |> Enum.map(&elem(&1, 0))
    lost = types |> Enum.filter(fn {_t, was, now} -> now < was end) |> Enum.map(&elem(&1, 0))

    %{
      stale?: types != [],
      types: Enum.sort(types),
      net: Enum.reduce(types, 0, fn {_t, was, now}, acc -> acc + now - was end),
      gained: Enum.sort(gained),
      lost: Enum.sort(lost)
    }
  end

  defp report_drift(%{stale?: false}, _path, _accept?, _current), do: :ok

  # ADOPTING A BASELINE IS A DECISION, so it is a flag rather than a side effect of
  # passing. The five-case gain of 2026-09-03 went unadopted because nothing said it
  # could be; installing it automatically would be the opposite error, quietly ratcheting
  # a run nobody reviewed.
  defp report_drift(drift, path, true, current) do
    write_json_map(path, current)

    Mix.shell().info(
      "  ▸ baseline advanced — net #{sign(drift.net)} case(s), now #{current["total"]} total"
    )
  end

  defp report_drift(drift, path, false, _current) do
    detail =
      Enum.map_join(drift.types, "\n", fn {type, was, now} ->
        "    #{type}: #{was} -> #{now} case(s)"
      end)

    Mix.shell().info(
      "\n  ▸ THE BASELINE IS NOW OBSOLETE — net #{sign(drift.net)} case(s) against " <>
        "#{path}:\n" <>
        detail <>
        "\n\n  This run PASSED and the baseline was NOT advanced; that is what --gate " <>
        "does.\n  Until it is, a later regression is measured against the old number and " <>
        "can\n  pass in silence. Review the movements above, then adopt them:\n\n" <>
        "      mix pramana.evals --gate --accept\n"
    )
  end

  defp sign(n) when n > 0, do: "+#{n}"
  defp sign(n), do: "#{n}"

  defp compare(current, baseline, baseline_path, accept?) do
    regressions =
      for {type, %{"hits" => was_hits, "rate" => was}} <- baseline["by_type"] || %{},
          is_number(was_hits),
          now_hits = get_in(current, ["by_type", type, "hits"]),
          is_number(now_hits),
          was_hits - now_hits > @tolerated_case_drop do
        now = get_in(current, ["by_type", type, "rate"])
        "  #{type}: #{was}% -> #{now}%  (#{was_hits} -> #{now_hits} cases)"
      end

    moved = moved_cases(current, baseline)

    if regressions == [] do
      Mix.shell().info(
        "  gate OK — no case type regressed against #{inspect(baseline["total"])} baseline cases"
      )

      # A PASS CAN STILL HAVE MOVED. Equal rates are consistent with one case flipping to
      # a hit and another to a miss, which is exactly the substitution a rate cannot see —
      # `docs/PLAN.md` audit item 7 says so and had no way to check it. Reported, not
      # failed: a swap is not a regression, it is a thing to look at.
      unless moved == [], do: report_moved(moved)

      current
      |> drift(baseline)
      |> report_drift(baseline_path, accept?, current)
    else
      Mix.raise(
        "retrieval regression:\n" <>
          Enum.join(regressions, "\n") <> "\n\n" <> moved_detail(moved)
      )
    end
  end

  # Which individual cases changed outcome. Empty when the baseline predates per-case
  # detail, and says so rather than reporting every case as new.
  defp moved_cases(current, baseline) do
    was = baseline["cases"] || %{}
    now = current["cases"] || %{}

    if map_size(was) == 0 do
      []
    else
      for {id, now_outcome} <- now,
          was_outcome = Map.get(was, id),
          was_outcome != nil,
          was_outcome != now_outcome,
          do: {id, was_outcome, now_outcome}
    end
  end

  defp report_moved(moved) do
    Mix.shell().info(
      "  #{length(moved)} case(s) changed outcome without changing any rate:\n" <>
        moved_detail(moved)
    )
  end

  defp moved_detail([]),
    do: "  (no per-case detail — the baseline predates it; re-record to enable)"

  defp moved_detail(moved) do
    moved
    |> Enum.sort()
    |> Enum.take(20)
    |> Enum.map_join("\n", fn {id, was, now} -> "    #{id}: #{was} -> #{now}" end)
  end
end
