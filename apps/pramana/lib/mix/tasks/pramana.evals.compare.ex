defmodule Mix.Tasks.Pramana.Evals.Compare do
  @shortdoc "Diffs two eval scorecards, and says which differences mean nothing"

  @moduledoc """
  Compares two scorecards written by `mix pramana.evals --json`.

      mix pramana.evals.compare evals/baseline.json evals/scorecard-j.json
      mix pramana.evals.compare a.json b.json --rebuilt   # an index rebuild sits between them

  ## Why this is a task and not a script

  Because it was a script, four times in one day, each time slightly different — and the
  differences mattered. A comparison written fresh each time is a comparison whose
  thresholds are chosen after seeing the numbers, which is the one thing a measurement
  must not allow.

  ## What it knows that a diff does not

  **A delta smaller than the noise floor is not a result.** Two runs of the identical
  configuration against the identical index differ by about one case, concentrated in
  `retrieval/pali`. One case is 0.67 percentage points on a 150-case row and 1.6 on a
  64-case one, so the same absolute difference is noise on one row and possibly signal on
  another. Rows are flagged per row, against their own size.

  **`--rebuilt` widens that considerably, and you usually need it.** An HNSW rebuild is
  not deterministic: the graph is built with randomisation, so reindexing the same vectors
  gives slightly different approximate neighbourhoods. Adding vectors does the same thing
  to queries that have nothing to do with them. **Tibetan is where this shows** — BGE-M3
  packs it at 0.9727 mean pairwise cosine against 0.84 for Pāli, so its candidates are
  near-ties by construction and a small graph perturbation reorders them while the other
  traditions hold position.

  Every import, re-embed and chunk-size experiment involves a rebuild. If one sits between
  the two runs, pass `--rebuilt` and the tool will refuse to call a small Tibetan movement
  a result.
  """

  use Mix.Task

  @switches [rebuilt: :boolean]

  # One case, measured by running the identical configuration twice against the identical
  # index. It is a count rather than a percentage on purpose: the same one case is 0.67pp
  # of `retrieval/pali` and 1.6pp of `retrieval/tibetan`.
  @same_index_noise_cases 1

  # Unmeasured as of 2026-08-27, and known to be larger. Two cases is the observed
  # movement in `retrieval/tibetan` across one rebuild that also added unrelated vectors;
  # it is a floor on the floor, not the floor.
  @rebuild_noise_cases 2

  @impl Mix.Task
  def run(argv) do
    {opts, paths, _} = OptionParser.parse(argv, switches: @switches)

    {before_path, after_path} =
      case paths do
        [a, b] -> {a, b}
        _ -> Mix.raise("usage: mix pramana.evals.compare <before.json> <after.json>")
      end

    before = read!(before_path)
    later = read!(after_path)
    noise = if opts[:rebuilt], do: @rebuild_noise_cases, else: @same_index_noise_cases

    Mix.shell().info("""

      #{before_path}
      #{after_path}
      treating a movement of #{noise} case(s) or fewer as noise#{if opts[:rebuilt], do: " (an index rebuild sits between them)", else: ""}
    """)

    section("OVERALL", [{"overall", before["overall"], later["overall"]}], noise)
    section("BY CASE TYPE", paired(before, later, "by_type"), noise)
    section("BY TYPE / TRADITION", paired(before, later, "by_type_tradition"), noise)

    answered(before, later)
    verdict(before, later, noise, opts[:rebuilt])
  end

  defp read!(path) do
    case File.read(path) do
      {:ok, body} -> Jason.decode!(body)
      {:error, reason} -> Mix.raise("cannot read #{path}: #{inspect(reason)}")
    end
  end

  defp paired(before, later, key) do
    keys = Map.keys(before[key] || %{}) ++ Map.keys(later[key] || %{})

    keys
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map(fn k -> {k, get_in(before, [key, k]), get_in(later, [key, k])} end)
  end

  defp section(title, rows, noise) do
    Mix.shell().info("  #{title}")

    for {name, b, a} <- rows do
      Mix.shell().info("    " <> row(name, b, a, noise))
    end

    Mix.shell().info("")
  end

  defp row(name, nil, a, _noise), do: "#{pad(name)} — -> #{fmt(a)}   NEW"

  defp row(name, b, nil, _noise),
    do: "#{pad(name)} #{fmt(b)} -> —   GONE"

  defp row(name, b, a, noise) do
    cases = a["hits"] - b["hits"]

    label =
      cond do
        cases == 0 -> ""
        noise?(cases, a["scored"], noise) -> "  (#{signed(cases)} case — within noise)"
        cases > 0 -> "  #{signed(cases)} cases"
        true -> "  #{signed(cases)} cases   REGRESSION"
      end

    "#{pad(name)} #{fmt(b)} -> #{fmt(a)}#{label}"
  end

  # NOISE IS A COUNT AND A PROPORTION, and the first version of this used only the count —
  # which reported `absence 1/4 -> 3/4` as within noise. That is a fifty-point move on a
  # four-case row. The docstring already said "the same absolute difference is noise on one
  # row and possibly signal on another"; the code did not do it, and the tool caught itself
  # on its first real run.
  #
  # A movement is noise only if it is BOTH within the measured case count AND at most 5% of
  # the row. On a row too small for that, every case is signal — which is the honest answer
  # for a four-case row, not a limitation.
  defp noise?(cases, scored, noise_cases) do
    abs(cases) <= noise_cases and scored >= noise_cases * 20
  end

  defp answered(before, later) do
    b = before["answered_any_tradition"]
    a = later["answered_any_tradition"]

    if b && a do
      Mix.shell().info("  ANSWERED FROM ANY TRADITION  #{b["rate"]}% -> #{a["rate"]}%\n")
    end
  end

  # The summary a reader acts on, and the caveat that stops them acting on the wrong part.
  defp verdict(before, later, noise, rebuilt?) do
    cases = later["overall"]["hits"] - before["overall"]["hits"]

    regressions =
      for {name, b, a} <- paired(before, later, "by_type_tradition"),
          b && a,
          a["hits"] - b["hits"] < 0,
          not noise?(a["hits"] - b["hits"], a["scored"], noise),
          do: name

    Mix.shell().info(summary(cases, regressions, noise))

    if rebuilt? do
      Mix.shell().info("""
        An index rebuild sits between these runs, so a small `retrieval/tibetan` movement
        is not evidence of anything. BGE-M3 packs Tibetan at 0.9727 mean pairwise cosine;
        its candidates are near-ties, and a rebuilt HNSW graph reorders them on its own.
      """)
    end
  end

  defp summary(cases, [], noise) when cases > noise,
    do: "  #{signed(cases)} cases overall, no per-tradition regression beyond noise.\n"

  defp summary(cases, [], _noise),
    do: "  #{signed(cases)} cases overall, nothing regressed.\n"

  defp summary(cases, regressions, _noise),
    do:
      "  #{signed(cases)} cases overall, but DOWN on: #{Enum.join(regressions, ", ")}.\n" <>
        "  A configuration that gains overall while dropping a tradition is not a win —\n" <>
        "  see the reranker, which was right about Tibetan and wrong about the system.\n"

  defp pad(name), do: String.pad_trailing(name, 26)

  defp fmt(%{"rate" => rate, "hits" => hits, "scored" => scored}),
    do: "#{:erlang.float_to_binary(rate * 1.0, decimals: 1)}% (#{hits}/#{scored})"

  defp signed(n) when n >= 0, do: "+#{n}"
  defp signed(n), do: Integer.to_string(n)
end
