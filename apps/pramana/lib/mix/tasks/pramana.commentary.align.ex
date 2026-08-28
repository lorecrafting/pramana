defmodule Mix.Tasks.Pramana.Commentary.Align do
  @shortdoc "Aligns commentaries to their root texts, lemma by lemma"

  @moduledoc """
  Passage-level 科文 alignment for every asserted `comments_on` relation.

      mix pramana.commentary.align
      mix pramana.commentary.align --work T1789
      mix pramana.commentary.align --dry-run

  Reads `work_relations`, never writes to it. A relation says which work a commentary
  explains; this says which *line*, and it has nothing to say about whether the relation
  itself is right — see `Pramana.Commentary` for why a pair below the density floor is not
  a refuted relation.

  ## Options

    * `--work` — one commentary only, by work id
    * `--dry-run` — measure and report, write nothing
    * `--min-density` — override the floor (spans per 10k commentary characters)

  ## What the report is for

  Every pair is printed with its numbers whether or not it qualified, because the
  interesting rows are the ones that did not. A commentary with thousands of spans that
  still fails the floor is a long commentary on a long root and worth looking at; one with
  four spans is a relation the text does not support in any visible way.
  """

  use Mix.Task

  import Ecto.Query

  alias Pramana.Bake
  alias Pramana.Commentary
  alias Pramana.Repo

  @switches [work: :string, dry_run: :boolean, min_density: :float]

  @impl Mix.Task
  def run(argv) do
    {opts, _} = OptionParser.parse!(argv, strict: @switches)
    Mix.Task.run("app.start")

    pairs = pairs(opts[:work])
    bake_id = Bake.current_id()

    Mix.shell().info("""

      commentary alignment — #{length(pairs)} asserted relation(s)

      window        #{Commentary.window()} characters, unique in the root
      floor         #{opts[:min_density] || Commentary.min_density()} spans per 10k commentary characters
      #{if opts[:dry_run], do: "DRY RUN — nothing will be written", else: "bake          #{bake_id}"}
    """)

    results =
      Enum.map(pairs, fn pair ->
        result = run_pair(pair, opts[:dry_run], bake_id)
        report(result)
        result
      end)

    summarise(results)
  end

  defp run_pair({commentary, root}, true, _bake_id),
    do: Commentary.measure(commentary, root)

  # `{:skip, report}` is not an error: a pair below the density floor is a commentary that
  # paraphrases rather than quotes, which this method cannot see and which says nothing
  # about whether the relation is right. Both shapes carry the same numbers.
  defp run_pair({commentary, root}, _dry_run, bake_id) do
    case Commentary.align(commentary, root, bake_id: bake_id) do
      {:ok, report} -> report
      {:skip, report} -> report
      {:error, reason} -> {:error, commentary, root, reason}
    end
  end

  defp pairs(nil) do
    Repo.all(
      from r in "work_relations",
        where: r.relation == "comments_on" and not is_nil(r.target_work_id),
        select: {r.source_work_id, r.target_work_id},
        order_by: [asc: r.source_work_id, asc: r.target_work_id]
    )
  end

  defp pairs(work) do
    Repo.all(
      from r in "work_relations",
        where:
          r.relation == "comments_on" and not is_nil(r.target_work_id) and
            r.source_work_id == ^work,
        select: {r.source_work_id, r.target_work_id},
        order_by: [asc: r.target_work_id]
    )
  end

  defp report({:error, commentary, root, reason}),
    do: Mix.shell().error("  #{commentary} -> #{root}  #{inspect(reason)}")

  defp report({:error, reason}), do: Mix.shell().error("  #{inspect(reason)}")

  defp report(r) when is_map(r) do
    mark = if r.aligned, do: "✓", else: " "

    Mix.shell().info(
      "  #{mark} #{String.pad_trailing("#{r.commentary_work_id} -> #{r.root_work_id}", 20)}" <>
        " density #{String.pad_leading(fmt(r.density), 7)}" <>
        "  spans #{String.pad_leading("#{r.spans}", 5)}" <>
        "  root #{String.pad_leading(fmt(r.root_pct), 5)}%" <>
        "  forward #{String.pad_leading(fmt(r.forward_pct), 5)}%" <>
        written(r)
    )
  end

  defp written(%{written: n}), do: "  wrote #{n}"
  defp written(_), do: ""

  defp fmt(f), do: :erlang.float_to_binary(f * 1.0, decimals: 1)

  defp summarise(results) do
    reports = Enum.filter(results, &is_map/1)
    aligned = Enum.filter(reports, & &1.aligned)
    written = reports |> Enum.map(&Map.get(&1, :written, 0)) |> Enum.sum()

    forward = fn rs ->
      case Enum.map(rs, & &1.forward_pct) do
        [] -> 0.0
        vs -> Float.round(Enum.sum(vs) / length(vs), 1)
      end
    end

    Mix.shell().info("""

      aligned       #{length(aligned)} of #{length(reports)} pair(s)
      alignments    #{written}
      forward       #{forward.(aligned)}% mean over aligned pairs, #{forward.(reports -- aligned)}% over the rest

    A pair below the floor is NOT a refuted relation. A commentary may paraphrase its
    root, and several here plainly do; this method can only see verbatim quotation.
    """)
  end
end
