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
  alias Pramana.Elapsed
  alias Pramana.Sources

  @switches [quick: :boolean, from: :string]

  # Cheapest first, so a two-second failure is found in two seconds. `env` is the MIX_ENV
  # each step needs; the corpus steps must run against dev, where the corpus is.
  @steps [
    %{id: "format", cmd: ~w(mix format --check-formatted), env: "dev", quick: true},
    %{id: "credo", cmd: ~w(mix credo --strict), env: "dev", quick: true},
    %{id: "test", cmd: ~w(mix test), env: "test", quick: true},
    %{id: "lockfile", cmd: :lockfile, env: "dev", quick: true},
    %{id: "verify", cmd: ~w(mix pramana.verify --all), env: "dev", quick: false},
    %{id: "integrity", cmd: ~w(mix pramana.integrity), env: "dev", quick: false},
    %{id: "evals", cmd: ~w(mix pramana.evals --gate), env: "dev", quick: false, embedding: true}
  ]

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _, _} = OptionParser.parse(argv, switches: @switches)

    steps = steps_for(opts)
    started = System.monotonic_time(:millisecond)

    Mix.shell().info("""

    running #{length(steps)} check(s): #{Enum.map_join(steps, " -> ", & &1.id)}
    """)

    result = Enum.reduce_while(steps, :ok, &run_step/2)

    report(result, System.monotonic_time(:millisecond) - started)
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

  defp run_step(step, _acc) do
    Mix.shell().info([:bright, "\n  ▸ #{step.id}", :reset])
    started = System.monotonic_time(:millisecond)

    status = execute(step)
    elapsed = System.monotonic_time(:millisecond) - started

    case status do
      :ok ->
        Mix.shell().info([:green, "    ok", :reset, "  (#{Elapsed.human(elapsed)})"])
        {:cont, :ok}

      {:error, detail} ->
        Mix.shell().error("    FAILED after #{Elapsed.human(elapsed)}")
        {:halt, {:error, step.id, detail}}
    end
  end

  # The lockfile check has lived in `docs/CHECKS.md` as a snippet to paste into IEx, which
  # means it ran when someone remembered to paste it. EVERY source, not the one just
  # touched: the Tengyur landed with all 213 paths recorded as absolute paths on one
  # laptop, and that is invisible from the machine that wrote them.
  defp execute(%{cmd: :lockfile}) do
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
        :ok

      broken ->
        for {id, reason} <- broken do
          Mix.shell().error("    #{id}: #{inspect(reason, limit: 3)}")
        end

        {:error, :lockfile}
    end
  end

  defp execute(%{cmd: cmd, env: env} = step) do
    [exe | args] = cmd

    env_vars =
      [{"MIX_ENV", env}] ++ if(step[:embedding], do: [{"PRAMANA_EMBEDDING", "1"}], else: [])

    case System.cmd(exe, args,
           env: env_vars,
           into: IO.stream(:stdio, :line),
           stderr_to_stdout: true
         ) do
      {_, 0} -> :ok
      {_, code} -> {:error, {:exit, code}}
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

  defp report({:error, id, detail}, elapsed) do
    Mix.raise("""
    gate FAILED at #{id} after #{Elapsed.human(elapsed)} (#{inspect(detail)}).

    Fix it, then resume without repaying for the steps that passed:

        mix pramana.gate --from #{id}
    """)
  end
end
