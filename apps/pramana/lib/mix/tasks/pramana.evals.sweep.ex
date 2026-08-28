defmodule Mix.Tasks.Pramana.Evals.Sweep do
  @shortdoc "Runs the gold set across a grid of retrieval configurations"

  @moduledoc """
  Sweeps retrieval knobs against the **whole gold set**, one configuration at a time.

      mix pramana.evals.sweep --grid rrf_k=30,60,120
      mix pramana.evals.sweep --grid rrf_k=30,60 --grid rerank_multiplier=3,5,8
      mix pramana.evals.sweep --grid lexical_depth=2,3 --grid semantic_depth=6,9 --only retrieval

  Every run writes a scorecard to `evals/experiments/sweep-<stamp>/`, and the task prints
  a table of every configuration against the baseline at the end. Nothing is adopted
  automatically: this measures, a human decides, and the decision goes in `docs/PLAN.md`.

  ## `--only`, and the rule that comes with it

  `--only retrieval,topical` restricts the sweep to the case types a ranking knob can
  actually move. The other 905 cases — `provenance`, `quote_verify`, `quote_reject`,
  `adversarial`, `absence` — are all at 100% and test the guard and the provenance record
  rather than the order of results, so paying 3x the wall time to re-confirm them at every
  grid point buys nothing.

  **That makes the sweep a proxy, and this project has a scar about proxies.** So the rule
  is: the sweep PROPOSES and the full gate DISPOSES. A configuration that looks better
  here is not adopted until `mix pramana.evals --gate` has run the whole set against it.
  The task prints that rule with its results whenever `--only` was used, because the run
  that skips it will be the one where somebody is in a hurry.

  ## Why a batch and not an agent loop

  The obvious way to do this is a ratchet — try a configuration, keep it if the number
  improves, revert if not, repeat. Three things in this project's history say no.

  **The referee is 21 minutes, not 5.** A ratchet's power comes from hundreds of cheap
  trials; at this cost the loop would run about sixty a day, and `docs/PLAN.md` records
  that eval runs cannot overlap with anything because "they are the measurement;
  contention invalidates every timing". A grid of 8-12 configurations run overnight gets
  the same coverage without pretending to be interactive.

  **A fast proxy metric would industrialise a failure this project has already had.**
  See `docs/PROXIES.md`: a Tibetan LoRA where every cheap
  measurement said it worked and the gold set said `retrieval/tibetan` 0%. A ratchet
  keyed to a proxy does not merely risk drift, it optimises into it.

  **A scalar metric would ratchet in regressions that have already happened.** The
  reranker "was right about Tibetan and wrong about the system", and its first version
  "silently reordered the canons, and only the per-tradition rows caught it". So this
  compares a VECTOR — overall, each per-tradition row, answered-from-any-tradition — and
  a configuration that gains overall while dropping a tradition is reported as what it
  is, not as a win.

  ## What is NOT in the grid, and why

  **Chunk size.** It is a genuine knob — 300 characters of Literary Chinese, 700 of
  romanised Pāli, measured against the tokenizer rather than chosen — but changing it
  means re-chunking and re-embedding the affected source, which is an hour and a GPU
  bill per cell. That is a deliberate experiment, not a grid point.

  **Anything in `evals/gold/`.** The referee is locked. A sweep that could edit the gold
  set is not measuring retrieval, it is measuring its own ability to move a target.
  """

  use Mix.Task

  alias Pramana.Elapsed
  alias Pramana.Evals
  alias Pramana.Evals.Score

  @switches [grid: [:string, :keep], only: :string, dir: :string, out: :string, dry_run: :boolean]

  # Only knobs that change RANKING at query time. Each is already an override the eval
  # harness understands, so a grid point is exactly a flag a human could have typed.
  @sweepable ~w(rrf_k rerank_multiplier lexical_depth semantic_depth depth)a

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _} = OptionParser.parse!(argv, strict: @switches)

    grid = parse_grid!(Keyword.get_values(opts, :grid))
    combos = combinations(grid)

    out = Keyword.get(opts, :out, default_out())
    File.mkdir_p!(out)

    cases = load_cases!(Keyword.get(opts, :dir, "evals/gold"), opts)

    Mix.shell().info("""

    sweeping #{length(combos)} configuration(s) over #{length(cases)} case(s)
      grid:    #{inspect(grid)}
      out:     #{out}
      note:    the shipped default is included as the first run, for a same-session control
    """)

    if opts[:dry_run] do
      for combo <- combos, do: Mix.shell().info("  #{label(combo)}")
      :ok
    else
      results = Enum.map([[] | combos], &run_one(&1, cases, out))
      report(results, out, opts[:only] != nil)
    end
  end

  # The DEFAULT is run first, in the same session, against the same corpus. A baseline
  # from another day measured another corpus — this one grew by 290,392 vectors between
  # the last baseline and this sweep — and comparing across that is how a configuration
  # gets credited with someone else's ingest.
  defp run_one(combo, cases, out) do
    Mix.shell().info("\n  → #{label(combo)}")

    started = System.monotonic_time(:millisecond)
    scorecard = Evals.run(cases, search_override_opts(combo))
    elapsed = System.monotonic_time(:millisecond) - started

    path = Path.join(out, "#{slug(combo)}.json")
    File.write!(path, Jason.encode!(Score.to_map(scorecard), pretty: true))

    Mix.shell().info("     #{fmt_pct(scorecard)} in #{Elapsed.human(elapsed)}")

    %{combo: combo, scorecard: scorecard, elapsed: elapsed, path: path}
  end

  defp search_override_opts([]), do: []
  defp search_override_opts(combo), do: [search_override: combo]

  # A configuration is a win only if it improves something and costs nothing anywhere.
  # `regressions` is the column that decides, and it is per tradition because the whole
  # point is that an overall number hides a canon.
  defp report(results, out, subset?) do
    [control | _] = results

    rows =
      Enum.map(results, fn result ->
        %{
          label: label(result.combo),
          overall: rate(result.scorecard, :overall),
          elapsed: result.elapsed,
          deltas: deltas(control.scorecard, result.scorecard)
        }
      end)

    Mix.shell().info(
      "\n  configuration                          overall   vs control   regressions"
    )

    for row <- rows do
      {gained, lost} = Enum.split_with(row.deltas, fn {_k, d} -> d > 0 end)
      overall_delta = row.overall - hd(rows).overall

      Mix.shell().info(
        "  #{String.pad_trailing(row.label, 38)} " <>
          "#{String.pad_leading(:erlang.float_to_binary(row.overall, decimals: 1), 6)}% " <>
          "#{String.pad_leading(signed(overall_delta), 11)}   " <>
          "#{describe(gained, lost)}"
      )
    end

    Mix.shell().info("""

    scorecards in #{out}

    NOTHING HAS BEEN ADOPTED. A configuration that gains overall while dropping a
    per-tradition row is not a win — see the reranker, which was right about Tibetan and
    wrong about the system. Record the decision, and the rejects with their evidence, in
    docs/PLAN.md.#{subset_warning(subset?)}
    """)
  end

  defp subset_warning(false), do: ""

  defp subset_warning(true),
    do:
      "\n\n    THIS SWEEP SCORED A SUBSET. It is a proxy, and every proxy this project has\n" <>
        "    trusted has lied at least once — see \"Why every proxy lied\". Run\n" <>
        "    `mix pramana.evals --gate` over the WHOLE set before adopting anything here."

  defp describe([], []), do: "identical"
  defp describe(gained, []), do: "+#{length(gained)} row(s) up, none down"

  defp describe(gained, lost),
    do:
      "#{length(gained)} up · DOWN: #{Enum.map_join(lost, ", ", fn {k, d} -> "#{k} #{signed(d)}" end)}"

  defp deltas(control, candidate) do
    control_rows = by_tradition(control)

    candidate
    |> by_tradition()
    |> Enum.map(fn {key, rate} -> {key, rate - Map.get(control_rows, key, 0.0)} end)
    |> Enum.reject(fn {_key, delta} -> abs(delta) < 0.05 end)
  end

  defp by_tradition(scorecard) do
    scorecard
    |> Score.to_map()
    |> Map.get("by_type_tradition", %{})
    |> Map.new(fn {key, stats} -> {key, stats["rate"] || 0.0} end)
  end

  defp rate(scorecard, :overall) do
    scorecard |> Score.to_map() |> get_in(["overall", "rate"]) |> Kernel.||(0.0)
  end

  defp fmt_pct(scorecard),
    do: "#{:erlang.float_to_binary(rate(scorecard, :overall), decimals: 1)}%"

  defp signed(delta) when delta >= 0, do: "+#{:erlang.float_to_binary(delta, decimals: 1)}"
  defp signed(delta), do: :erlang.float_to_binary(delta, decimals: 1)

  defp load_cases!(dir, opts) do
    case Evals.load(dir) do
      {:ok, cases} -> filter_only(cases, opts[:only])
      {:error, {:no_gold_set, dir}} -> Mix.raise("no gold set in #{dir}")
    end
  end

  defp filter_only(cases, nil), do: cases

  defp filter_only(cases, only) do
    wanted = MapSet.new(String.split(only, ",", trim: true))
    Enum.filter(cases, &MapSet.member?(wanted, to_string(&1.type)))
  end

  # `--grid key=a,b,c`, repeatable. Values are integers because every sweepable knob is
  # one; a knob that is not gets rejected here rather than deep inside a retriever.
  defp parse_grid!([]), do: Mix.raise("nothing to sweep — pass at least one --grid key=v1,v2")
  defp parse_grid!(specs), do: Map.new(specs, &parse_spec!/1)

  defp parse_spec!(spec) do
    case String.split(spec, "=", parts: 2) do
      [key, values] ->
        {sweepable!(key), Enum.map(String.split(values, ",", trim: true), &parse_int!(&1, key))}

      _ ->
        Mix.raise("--grid expects key=v1,v2 (got #{inspect(spec)})")
    end
  end

  # A knob nobody can sweep is rejected here, by name, rather than deep inside a
  # retriever where the message would be about an unknown search option.
  defp sweepable!(key) do
    knob = String.to_atom(key)

    unless knob in @sweepable do
      Mix.raise("#{key} is not sweepable; known: #{Enum.join(@sweepable, ", ")}")
    end

    knob
  end

  defp parse_int!(value, key) do
    case Integer.parse(value) do
      {n, ""} -> n
      _ -> Mix.raise("#{key}: #{inspect(value)} is not an integer")
    end
  end

  # The cartesian product, in a stable order so two sweeps of one grid are comparable.
  defp combinations(grid) do
    grid
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.reduce([[]], fn {knob, values}, acc ->
      for combo <- acc, value <- values, do: combo ++ [{knob, value}]
    end)
  end

  defp label([]), do: "shipped default (control)"
  defp label(combo), do: Enum.map_join(combo, " ", fn {k, v} -> "#{k}=#{v}" end)

  defp slug([]), do: "control"
  defp slug(combo), do: Enum.map_join(combo, "-", fn {k, v} -> "#{k}#{v}" end)

  defp default_out do
    stamp = DateTime.utc_now() |> DateTime.to_iso8601(:basic) |> String.slice(0, 15)
    Path.join("evals/experiments", "sweep-#{stamp}")
  end
end
