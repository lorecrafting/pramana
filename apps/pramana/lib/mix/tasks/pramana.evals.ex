defmodule Mix.Tasks.Pramana.Evals do
  @shortdoc "Scores retrieval, citation and provenance against the gold set"

  @moduledoc """
  Runs `evals/gold/*.jsonl` and prints a scorecard.

      mix pramana.evals
      mix pramana.evals --only retrieval
      mix pramana.evals --json evals/scorecard.json
      mix pramana.evals --gate            # non-zero exit on a regression
      mix pramana.evals --per-tradition   # experiment: retrieve per canon, then merge
      mix pramana.evals --only retrieval --tradition tibetan --depth 200

  Retrieval cases need the embedding model, so run with `PRAMANA_EMBEDDING=1`; without
  it the harness says so and scores the lexical path only, rather than reporting a
  number that quietly measures half the system.

  ## The gate

  `--gate` compares against `evals/baseline.json` and exits non-zero if any case type
  drops. It is a **ratchet**, like the coverage threshold: a number that goes up gets
  recorded, and one that goes down fails the build rather than being explained away.
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
    # Experiment flags. They OVERRIDE every case's own search options, so a run that
    # uses them is measuring a configuration rather than the shipped default — which is
    # the point, and why the header says so.
    vector_kinds: :string,
    balance: :string,
    per_tradition: :boolean,
    depth: :integer,
    # Not an override — a FILTER. Scoring one tradition is how an experiment aimed at one
    # canon stays affordable; the decision still needs the whole set.
    tradition: :string
  ]

  @default_baseline "evals/baseline.json"

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _, _} = OptionParser.parse(argv, switches: @switches)

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
    if opts[:gate], do: gate(scorecard, Keyword.get(opts, :baseline, @default_baseline))
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
    Enum.any?([:depth, :per_tradition, :vector_kinds, :balance], &(opts[&1] != nil))
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

  defp progress(done, total, elapsed_ms) do
    if rem(done, @progress_every) == 0 or done == total do
      rate = done * 1000 / max(elapsed_ms, 1)
      remaining = if rate > 0, do: round((total - done) / rate), else: 0

      IO.write(
        :stderr,
        "\r  #{done}/#{total} cases · #{Pramana.Elapsed.human(elapsed_ms)} elapsed · " <>
          "~#{Pramana.Elapsed.human(remaining * 1000)} left    "
      )
    end

    if done == total, do: IO.write(:stderr, "\n")
    :ok
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
        depth: opts[:depth]
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

  defp gate(scorecard, baseline_path) do
    case File.read(baseline_path) do
      {:error, :enoent} ->
        Mix.shell().info("  no baseline at #{baseline_path} — writing this run as the baseline")
        write_json(baseline_path, scorecard)

      {:ok, contents} ->
        compare(Score.to_map(scorecard), Jason.decode!(contents))
    end
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

  defp compare(current, baseline) do
    regressions =
      for {type, %{"hits" => was_hits, "rate" => was}} <- baseline["by_type"] || %{},
          is_number(was_hits),
          now_hits = get_in(current, ["by_type", type, "hits"]),
          is_number(now_hits),
          was_hits - now_hits > @tolerated_case_drop do
        now = get_in(current, ["by_type", type, "rate"])
        "  #{type}: #{was}% -> #{now}%  (#{was_hits} -> #{now_hits} cases)"
      end

    if regressions == [] do
      Mix.shell().info(
        "  gate OK — no case type regressed against #{inspect(baseline["total"])} baseline cases"
      )
    else
      Mix.raise("retrieval regression:\n" <> Enum.join(regressions, "\n"))
    end
  end
end
