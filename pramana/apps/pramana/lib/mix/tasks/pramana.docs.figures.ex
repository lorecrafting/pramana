defmodule Mix.Tasks.Pramana.Docs.Figures do
  @shortdoc "Regenerates the corpus figures embedded in documentation, or checks them"

  @moduledoc """
      mix pramana.docs.figures            # check; non-zero when a figure is stale
      mix pramana.docs.figures --write    # regenerate

  **`CLAUDE.md` says never write down a number the code computes, and the documentation
  does it anyway** — because a file whose job is *what is true now* is made of numbers.
  The rule loses to the need, so the numbers stay and stop being written down: they live in
  marked blocks and this regenerates them.

  It is `mix format --check-formatted` for facts. In one week `work_relations` said 249
  when it was 269, `docs/ROADMAP.md` said 27,254 commentary alignments when there were
  72,120, and `docs/PLAN.md` said 17 MCP tools while `docs/STATUS.md` said 18 and the
  directory said 18. Every one was found by a person reading carefully, which is not a
  mechanism.

  ## What it will not do

  **It only checks what is inside a block.** A figure in prose is still a person's
  assertion, and the obligation to date it is unchanged — see `Pramana.Docs.Sync` on why a
  scanner over all numbers would be wrong constantly and learned-to-ignore.

  **It refuses on an empty corpus rather than rewriting to zero.** Every figure is a
  count, so a checkout with no bake would regenerate a documentation of zeroes and call it
  current. That is why this is a gate step and not a test: `mix test` runs against a
  sandbox with no corpus in it.
  """

  use Mix.Task

  alias Pramana.Docs.Figures
  alias Pramana.Docs.Sync

  @switches [write: :boolean]

  @impl Mix.Task
  def run(argv) do
    # Nine counts and a directory listing. The gate runs this alongside six other steps,
    # each of which would otherwise take a 25-connection pool out of Postgres's 100 —
    # which is how adding this step first failed, as `FAILED test` with every test passing.
    Pramana.Runtime.use_small_pool!(2)
    Mix.Task.run("app.start")
    {opts, _} = OptionParser.parse!(argv, strict: @switches)

    if Figures.available?() do
      # `opts[:write]` is nil when the switch is absent, and `not nil` raises rather than
      # meaning false. The check then crashed instead of reporting staleness — found by
      # editing a figure to a wrong value on purpose, which is the only way to learn that
      # a check can fail.
      roots = Application.fetch_env!(:pramana, :documentation_roots)
      check(roots, Figures.blocks(), opts[:write] == true)
    else
      Mix.shell().info("""

        no corpus loaded — figures NOT checked and NOT written.

        Every figure here is a count, so an empty database would regenerate the
        documentation to zeroes and report itself green. Bake first, or run this where a
        bake exists.
      """)
    end
  end

  defp check(root, blocks, write?) do
    results =
      for path <- Sync.documents(root) do
        content = File.read!(path)

        case Sync.rewrite(content, blocks) do
          {:ok, _same, []} -> {:ok, path, []}
          {:ok, updated, changed} -> apply_change(path, updated, changed, write?)
          {:error, reason} -> {:error, path, reason}
        end
      end

    report(results, write?)
  end

  defp apply_change(path, updated, changed, true) do
    File.write!(path, updated)
    {:written, path, changed}
  end

  defp apply_change(path, _updated, changed, _), do: {:stale, path, changed}

  defp report(results, write?) do
    stale = Enum.filter(results, &match?({:stale, _, _}, &1))
    errors = Enum.filter(results, &match?({:error, _, _}, &1))
    written = Enum.filter(results, &match?({:written, _, _}, &1))

    Enum.each(written, fn {_, path, keys} ->
      Mix.shell().info("  updated  #{relative(path)}  (#{Enum.join(keys, ", ")})")
    end)

    Enum.each(errors, fn {_, path, reason} ->
      Mix.shell().error("  BROKEN   #{relative(path)}  #{inspect(reason)}")
    end)

    cond do
      errors != [] ->
        Mix.raise("a figure block names something nothing generates, or is unterminated")

      stale != [] and not write? ->
        Enum.each(stale, fn {_, path, keys} ->
          Mix.shell().error("  STALE    #{relative(path)}  (#{Enum.join(keys, ", ")})")
        end)

        Mix.raise("""
        documentation figures are out of date. Run:

            mix pramana.docs.figures --write

        These are generated blocks — nothing is lost by regenerating them, and the numbers
        in them were describing a corpus that no longer exists.
        """)

      true ->
        Mix.shell().info("  figures up to date in #{length(results)} document(s)")
    end
  end

  defp relative(path), do: Path.relative_to(path, File.cwd!())
end
