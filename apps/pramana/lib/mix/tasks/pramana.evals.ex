defmodule Mix.Tasks.Pramana.Evals do
  @shortdoc "Scores retrieval, citation and provenance against the gold set"

  @moduledoc """
  Runs `evals/gold/*.jsonl` and prints a scorecard.

      mix pramana.evals
      mix pramana.evals --only retrieval
      mix pramana.evals --json evals/scorecard.json
      mix pramana.evals --gate            # non-zero exit on a regression

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
    balance: :string
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

    warn_if_no_embeddings()

    scorecard = Evals.run(cases, run_opts(opts))
    Mix.shell().info(Score.render(scorecard))

    if path = opts[:json], do: write_json(path, scorecard)
    if opts[:gate], do: gate(scorecard, Keyword.get(opts, :baseline, @default_baseline))
  end

  defp run_opts(opts) do
    only(opts) ++ overrides(opts)
  end

  defp overrides(opts) do
    kinds = opts[:vector_kinds] && String.split(opts[:vector_kinds], ",", trim: true)
    balance = opts[:balance] && String.to_existing_atom(opts[:balance])

    override =
      [vector_kinds: kinds, balance: balance]
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
