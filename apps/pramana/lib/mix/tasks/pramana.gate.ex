defmodule Mix.Tasks.Pramana.Gate do
  @shortdoc "Runs every checkpoint check, cheapest first, and stops at the first failure"

  @moduledoc """
  The ⛔ checkpoint gate, as one command.

      mix pramana.gate           # everything
      mix pramana.gate --quick   # the fast half: format, credo, tests, lockfile
      mix pramana.gate --from integrity   # resume at a step, after fixing one

  ## Why this exists

  `docs/CHECKS.md` specifies a phase gate as six things a person has to remember, in an
  order that matters, some of which take half an hour. Runnable-in-principle is not the
  same as run: the CBETA X ingest went out with `mix pramana.verify` green and
  `mix pramana.integrity` never executed, and integrity had been failing on 1,228 texts
  the whole time. Nobody skipped it on purpose — it was one more command at the end of a
  long day.

  So the gate is one command, ordered cheapest-first, and it stops at the first failure.
  A formatting error should not cost you the 27 minutes it takes to discover it after the
  eval run.

  ## The steps, and why in this order

  | | step | typical | why here |
  |---|---|---|---|
  | 1 | `mix format --check-formatted` | 2 s | costs nothing, fails often |
  | 2 | `mix credo --strict` | 3 s | same |
  | 3 | `mix test` | 6 s | proves behaviour before anything touches the corpus |
  | 4 | lockfile verify, **every source** | 30 s | the bake is meaningless if `sources.lock.json` cannot reproduce it |
  | 5 | `mix pramana.verify --all` | minutes | reproducibility: the pipeline is deterministic |
  | 6 | `mix pramana.integrity` | ~13 min | fidelity: nothing printed was lost |
  | 7 | `mix pramana.evals --gate` | ~27 min | the ratchet against `evals/baseline.json` |

  Steps 5 and 6 prove the pipeline is deterministic and that nothing printed was lost.
  **`mix pramana.coherence` asks the third question — whether independently derived facts
  about one work agree** — and it exists because both of those were green over 122 works
  labelled Japanese that are Chinese compositions. Faithfully and reproducibly mislabelled.
  See `Pramana.Coherence`.

  Steps 5 and 6 answer **different questions** and running only the first is how a real
  defect survived a passing gate: `verify` re-runs the pipeline and compares, so anything
  dropped deterministically is dropped on both sides and the check passes. Step 4 is in
  because both of them work from paths recorded at ingest and stay green when the lockfile
  itself is wrong — and "wrong" includes incomplete, which is exactly how the Taishō's
  2,471 file records went missing while every check stayed green.

  ## What this does NOT do

  It does not replace the **architecture review** (`docs/CHECKS.md` §2) or the docs sync.
  A codebase can be fully green and have quietly stopped being the thing it was designed
  to be, and no task detects that. This runs the checks that are mechanical; the ones that
  need judgement stay with a person, and the closing summary says so.
  """

  use Mix.Task

  alias Pramana.Acquire.Lockfile
  alias Pramana.Bake
  alias Pramana.Elapsed
  alias Pramana.Sources

  @switches [quick: :boolean, from: :string, serial: :boolean]

  # Cheapest first, so a two-second failure is found in two seconds. `env` is the MIX_ENV
  # each step needs; the corpus steps must run against dev, where the corpus is.
  # CHEAPEST FIRST, and this list is `docs/CHECKS.md` § "1. Code" plus the data checks.
  #
  # It ran three of that document's seven commands for two phases. `compile
  # --warnings-as-errors`, `dialyzer` and `deps.audit` were all specified as gate checks and
  # none of them was in the gate — so "mix pramana.gate passed" and "the phase gate passed"
  # were different statements that read identically. Dialyzer found a real defect the day
  # after it was first run by hand.
  #
  # `hex.outdated` is deliberately absent: CHECKS.md asks for it to *note drift*, and a
  # dependency being upgradable is not a failure. A gate step that cannot fail is noise.
  @steps [
    %{id: "format", cmd: ~w(mix format --check-formatted), env: "dev", quick: true, stage: 1},
    %{
      id: "compile",
      cmd: ~w(mix compile --warnings-as-errors --force),
      env: "dev",
      quick: true,
      stage: 2
    },
    %{id: "credo", cmd: ~w(mix credo --strict), env: "dev", quick: true, stage: 3},
    %{id: "audit", cmd: ~w(mix deps.audit), env: "dev", quick: true, stage: 3},
    %{id: "test", cmd: ~w(mix test --cover), env: "test", quick: true, stage: 3},
    # Slow enough to sit behind the cheap checks and fast enough not to be `quick: false`:
    # ~45 s once the PLT is built, against 26 minutes for `verify --all`.
    %{id: "dialyzer", cmd: ~w(mix dialyzer), env: "dev", quick: true, stage: 3},
    %{id: "lockfile", cmd: :lockfile, env: "dev", quick: true, stage: 3},
    # 3 s, and it belongs with the cheap checks rather than the corpus ones: it reads a few
    # aggregates and re-derives nothing. A check that lives outside the gate is decorative —
    # the coverage ratchet was configured for four phases and enforced for none.
    %{id: "coherence", cmd: ~w(mix pramana.coherence), env: "dev", quick: true, stage: 3},
    %{id: "verify", cmd: ~w(mix pramana.verify --all), env: "dev", quick: false, stage: 4},
    %{id: "integrity", cmd: ~w(mix pramana.integrity), env: "dev", quick: false, stage: 4},
    %{
      id: "evals",
      cmd: ~w(mix pramana.evals --gate),
      env: "dev",
      quick: false,
      embedding: true,
      stage: 5
    }
  ]

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _} = OptionParser.parse!(argv, strict: @switches)

    steps = steps_for(opts)
    started = System.monotonic_time(:millisecond)

    Mix.shell().info("""

    running #{length(steps)} check(s): #{Enum.map_join(steps, " -> ", & &1.id)}
    """)

    result =
      steps
      |> Enum.chunk_by(& &1.stage)
      |> Enum.reduce_while(:ok, &run_stage(&1, &2, opts))

    report(result, System.monotonic_time(:millisecond) - started)
  end

  # STAGES, BECAUSE HALF THE ARROWS CARRIED NO DATA.
  #
  # The gate was ten steps in a line, and most of the waits were an artefact of the order
  # somebody typed them in: `credo` does not read `dialyzer`'s output, `integrity` does not
  # read `verify`'s. Only three orderings are real, and each is here for its own reason:
  #
  #   1  format      alone and first, because it is two seconds and fails often. A
  #                  formatting error must not cost a compile.
  #   2  compile     alone, because every later step assumes built beams — and because
  #                  concurrent `mix` invocations in one MIX_ENV contend on the build lock,
  #                  so compiling once up front is what makes stage 3 safe to fan out.
  #   3  cheap       credo, audit, test, dialyzer, lockfile — mutually independent. `test`
  #                  is MIX_ENV=test and takes a different build lock again.
  #   4  corpus      verify and integrity: both read-only over the same bake, and they
  #                  answer DIFFERENT questions, which is why both are here at all.
  #   5  evals       ALONE, and this one is not an oversight. docs/PLAN.md § "Can these run
  #                  at the same time?": *eval runs are the measurement; contention
  #                  invalidates every timing*. Fanning this in with stage 4 would buy
  #                  thirteen minutes and cost the meaning of the number.
  #
  # A stage runs every step even after one fails, and reports all of them. The old
  # first-failure halt was right for a line and wrong here: three cheap checks that all
  # fail should be seen in one pass, not across three runs of the gate.
  defp run_stage(stage, _acc, opts) do
    solo? = length(stage) == 1 or opts[:serial]
    stage = Enum.map(stage, &Map.put(&1, :solo, solo?))

    failures =
      if solo? do
        stage |> Enum.map(&run_step/1) |> Enum.reject(&(&1 == :ok))
      else
        stage
        |> Task.async_stream(&run_step/1, timeout: :infinity, ordered: false)
        |> Enum.map(fn {:ok, result} -> result end)
        |> Enum.reject(&(&1 == :ok))
      end

    case failures do
      [] -> {:cont, :ok}
      failures -> {:halt, {:error, failures}}
    end
  end

  defp steps_for(opts) do
    @steps
    |> then(fn steps -> if opts[:quick], do: Enum.filter(steps, & &1.quick), else: steps end)
    |> from(opts[:from])
  end

  # `--from integrity` after fixing what integrity found, rather than paying for verify
  # again. Named rather than numbered: a step's position changes and its name does not.
  defp from(steps, nil), do: steps

  defp from(steps, id) do
    case Enum.find_index(steps, &(&1.id == id)) do
      nil ->
        Mix.raise("unknown step #{inspect(id)}; known: #{Enum.map_join(@steps, ", ", & &1.id)}")

      index ->
        Enum.drop(steps, index)
    end
  end

  # A CONCURRENT STEP BUFFERS ITS OUTPUT; A LONE ONE STREAMS.
  #
  # Five steps streaming into one terminal at once is not a log, it is a race condition made
  # of text. So a step that shares its stage captures its output and prints it only on
  # failure, where it is the whole point. A stage of one — `format`, `compile`, `evals` —
  # streams live, which keeps the eval scores scrolling past as they always have.
  defp run_step(step) do
    started = System.monotonic_time(:millisecond)
    {status, output} = execute(step)
    elapsed = System.monotonic_time(:millisecond) - started

    case status do
      :ok ->
        Mix.shell().info([
          :green,
          "  ok       ",
          :reset,
          step.id,
          "  (#{Elapsed.human(elapsed)})"
        ])

        :ok

      {:error, detail} ->
        Mix.shell().error("  FAILED   #{step.id}  (#{Elapsed.human(elapsed)})")
        if output != "", do: Mix.shell().error(output)
        {step.id, detail}
    end
  end

  # The lockfile check has lived in `docs/CHECKS.md` as a snippet to paste into IEx, which
  # means it ran when someone remembered to paste it. EVERY source, not the one just
  # touched: the Tengyur landed with all 213 paths recorded as absolute paths on one
  # laptop, and that is invisible from the machine that wrote them.
  defp execute(%{cmd: :lockfile}) do
    {lockfile_check(), ""}
  end

  defp execute(%{cmd: cmd, env: env} = step) do
    [exe | args] = cmd

    env_vars =
      [{"MIX_ENV", env}] ++ if(step[:embedding], do: [{"PRAMANA_EMBEDDING", "1"}], else: [])

    into = if step[:solo], do: IO.stream(:stdio, :line), else: ""

    case System.cmd(exe, args, env: env_vars, into: into, stderr_to_stdout: true) do
      {_, 0} -> {:ok, ""}
      {output, code} -> {{:error, {:exit, code}}, to_string(output)}
    end
  end

  defp lockfile_check do
    results = Map.new(Sources.ids(), &{&1, Lockfile.verify(&1)})

    # `:not_locked` is NOT a failure. A source can be registered and deliberately not
    # acquired — SAT is, and has been for phases, because #14 is blocked on an email
    # rather than on code. Failing the gate on it would make the gate permanently red,
    # and a permanently red check is one nobody reads, which is the same failure mode as
    # `integrity` crying wolf over 1,228 X texts.
    {unacquired, checked} =
      Enum.split_with(results, fn {_id, result} -> result == {:error, :not_locked} end)

    broken = for {id, {:error, reason}} <- checked, do: {id, reason}

    for {id, n} <- for({id, {:ok, n}} <- checked, do: {id, n}) do
      Mix.shell().info("    #{String.pad_trailing(id, 20)} #{n} file(s)")
    end

    for {id, _} <- unacquired do
      Mix.shell().info("    #{String.pad_trailing(id, 20)} declared, never acquired")
    end

    case broken do
      [] ->
        recorded_bake_matches_inputs()

      broken ->
        for {id, reason} <- broken do
          Mix.shell().error("    #{id}: #{inspect(reason, limit: 3)}")
        end

        {:error, :lockfile}
    end
  end

  # A BAKE ID THAT NO LONGER DESCRIBES ITS INPUTS IS WORSE THAN NO BAKE ID.
  #
  # `bake_id = sha256(sources.lock + pipeline_version + config)`, and every MCP response is
  # stamped with the RECORDED one so an answer can be tied to the dataset that produced it.
  # But acquisition rewrites `sources.lock.json` and only a bake records a new row — so
  # between the two, every response carries an id for inputs that no longer exist, and a
  # `replay` record cites a corpus nobody can reconstruct.
  #
  # Found 2026-08-28 after acquiring DILA's place files: not one byte of corpus text changed
  # and the computed id moved anyway, which is correct — the answers changed. What was wrong
  # is that nothing said so. Acquiring the person authority had done the same thing weeks
  # earlier and passed every gate.
  #
  # `Bake.record/1` is the fix and it is cheap: it writes a row, it does not re-bake.
  defp recorded_bake_matches_inputs do
    case Bake.current() do
      nil ->
        Mix.shell().error("    no bake recorded — run `mix pramana.bake`")
        {:error, :no_bake_recorded}

      bake ->
        compare_bake(bake, Bake.bake_id(bake.config))
    end
  end

  # RECOMPUTED UNDER THE BAKE'S OWN CONFIG, not under `%{}`. `bake_id` digests the config
  # alongside the lockfile, so comparing against a default-config id reports divergence for
  # every bake that was built with one — this check's first version did exactly that and
  # failed against a perfectly current bake.
  defp compare_bake(bake, computed) do
    case {computed, bake} do
      {{:ok, id, _lock}, %{id: id}} ->
        :ok

      {{:ok, id, _lock}, %{id: recorded}} ->
        Mix.shell().error("""
            recorded bake  #{String.slice(recorded, 0, 16)}
            these inputs   #{String.slice(id, 0, 16)}

            sources.lock.json has changed since the bake was recorded, so every response is
            stamped with an id for inputs that no longer exist. If only reference data moved,
            `Pramana.Bake.record/1` re-records without re-baking; if a source's text moved,
            re-bake.
        """)

        {:error, :bake_id_diverged}

      {error, _} ->
        {:error, error}
    end
  end

  defp report(:ok, elapsed) do
    Mix.shell().info([
      :green,
      "\n  GATE PASSED",
      :reset,
      " in #{Elapsed.human(elapsed)}\n",
      """

      Mechanical checks only. Still owed by a person, and no task can do them:

        - the architecture review (docs/CHECKS.md §2) — a codebase can be fully green and
          have quietly stopped being the thing it was designed to be
        - the docs sync: STATUS and PLAN updated in the same commit as the work
      """
    ])
  end

  defp report({:error, failures}, elapsed) do
    {first, _} = hd(failures)

    listed =
      Enum.map_join(failures, "\n", fn {id, detail} -> "      #{id} (#{inspect(detail)})" end)

    Mix.raise("""
    gate FAILED after #{Elapsed.human(elapsed)}:

    #{listed}

    Every step in that stage ran, so this is all of them, not the first one. Fix them,
    then resume without repaying for the stages that passed:

        mix pramana.gate --from #{first}
    """)
  end
end
