defmodule Mix.Tasks.Pramana.Commentary.Align do
  @shortdoc "Aligns commentaries to their root texts, lemma by lemma"

  @moduledoc """
  Passage-level 科文 alignment for every asserted `comments_on` and `subcommentary_of`
  relation.

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

    # ROOT-MAJOR, AND THAT IS THE WHOLE OPTIMISATION.
    #
    # The cost is linear in characters and the expensive half depends only on the root, so
    # the order pairs are visited in decides how much work is repeated. On 2026-09-03 the
    # 155 asserted pairs covered 60 distinct roots: **41.7M root characters to window 11.0M
    # distinct ones**, against 21.4M on the commentary side. Sorting by root and carrying
    # one prepared root forward pays 32.4M instead of 63.1M — measured at 1,946 chars/s on
    # `T1509`, that is 4.6 hours instead of 9.0.
    #
    # One root, not all of them: a prepared root holds a map entry per character, so the 60
    # of them cannot be resident at once. Sorting is what makes holding one sufficient.
    results =
      pairs
      |> Enum.sort_by(fn {commentary, root} -> {root, commentary} end)
      |> Enum.reduce({[], nil}, fn {_, root} = pair, {acc, cached} ->
        held = prepared_for(root, cached)
        result = run_pair(pair, opts[:dry_run], bake_id, elem(held, 1))
        report(result)
        {[result | acc], held}
      end)
      |> then(fn {acc, _} -> Enum.reverse(acc) end)

    summarise(results)
  end

  # Keyed on the work id, which sorting has already made consecutive. `prepare_root/2` also
  # checks the body before trusting a prepared form, so a mistake here would be slow rather
  # than wrong.
  defp prepared_for(root, {root, _} = held), do: held

  defp prepared_for(root, _other) do
    case Commentary.prepare_root_by_work(root) do
      {:ok, prepared} -> {root, prepared}
      _ -> {root, nil}
    end
  end

  # A prepared root is an optimisation and never an input to the answer: `nil` here takes
  # the slow path to the same result, which is what makes the cache safe to get wrong.
  defp run_pair(pair, dry_run, bake_id, prepared) do
    opts = if prepared, do: [prepared_root: prepared], else: []
    run_pair(pair, dry_run, bake_id, opts, :ready)
  end

  defp run_pair({commentary, root}, true, _bake_id, opts, :ready),
    do: Commentary.measure(commentary, root, opts)

  # `{:skip, report}` is not an error: a pair below the density floor is a commentary that
  # paraphrases rather than quotes, which this method cannot see and which says nothing
  # about whether the relation is right. Both shapes carry the same numbers.
  defp run_pair({commentary, root}, _dry_run, bake_id, opts, :ready) do
    case Commentary.align(commentary, root, Keyword.put(opts, :bake_id, bake_id)) do
      {:ok, report} -> report
      {:skip, report} -> report
      {:error, reason} -> {:error, commentary, root, reason}
    end
  end

  # THE METHOD IS CHINESE, AND THE PAIR LIST IS NOT.
  #
  # 科文 alignment works because a Chinese commentary quotes a phrase of its root and then
  # glosses it, and because an eight-CHARACTER window is a substantial phrase whose
  # uniqueness in the root is the whole method (`Pramana.Commentary`). Eight characters of
  # Tibetan is about two syllables, which recur constantly — the uniqueness rule does not
  # hold, so the method has no basis there.
  #
  # This reads every asserted relation, and on 2026-09-02 `mix pramana.derge.relations`
  # added 93 Tibetan ones.
  #
  # **The original reason for this guard was that a Tibetan pair ran five minutes without
  # finishing. That was a defect, not the method** — `String.slice/3` walking the binary
  # once per span, fixed 2026-09-03. The same pairs now run in 0.01-0.05 s.
  #
  # **The real reason is stronger, and the fix is what made it visible.** Measured on three
  # Tibetan pairs the day the speed excuse went away:
  #
  #     toh2231 -> toh2229   density 554.1   forward 57.4%
  #     toh1900 -> toh1901   density 297.1   forward 60.7%
  #     toh1900 -> toh1367   density 373.7   forward 51.9%
  #
  # Forward order is at chance — 50% — against **84.3% over accepted Chinese pairs**, which
  # is exactly what "eight characters is about two Tibetan syllables" predicts: the windows
  # match everywhere and in no order. And the densities are 10-18x the floor, so **the
  # floor would wave every one of them through.** Unguarded, this would now write thousands
  # of alignments whose uniqueness premise was never true, quickly.
  #
  # So the guard is more necessary since it got fast, not less. See `docs/PLAN.md` item 2:
  # a Tibetan aligner needs syllable windows, its own floor, AND the discriminator actually
  # enforced rather than reported.
  #
  # So the filter is on the SOURCE, not on the relation: a pair is alignable when both
  # sides are Chinese. A Tibetan equivalent needs syllable windows and its own measured
  # floor, which is a different piece of work and not a parameter of this one.
  @alignable_sources ~w(cbeta sat local-huang-nianzu-jie)

  # `subcommentary_of` was excluded until 2026-09-03, when there were nine of them. There
  # are now 38, and 29 are Chinese pairs of exactly the shape this method is for: a 論疏
  # quotes a phrase of its śāstra and glosses it, the same 科文 structure as a 經疏 over a
  # sūtra. Nothing in the method cares which the target is.
  #
  # **Most of them will not clear the floor, and that was measured before including them.**
  # Of twelve, one does — `T1820` 佛遺教經論疏節要 at density 108.5. But the rest are not
  # noise: forward order runs 66–83% against ~50% for chance, which is the discriminator
  # `docs/COMMENTARY.md` uses to tell real structure from overlap. Śāstra exegesis has the
  # structure and quotes less verbatim than sūtra exegesis, and a floor calibrated on 120
  # null pairs of the latter rejects nearly all of the former. Whether that floor is right
  # for this population is a separate question needing its own null set; including the
  # pairs is what puts the numbers in front of anyone who asks it.
  @alignable_relations ~w(comments_on subcommentary_of)

  defp pairs(work) do
    from(r in "work_relations",
      join: cs in "texts",
      on: cs.work_id == r.source_work_id,
      join: rt in "texts",
      on: rt.work_id == r.target_work_id,
      where:
        r.relation in ^@alignable_relations and not is_nil(r.target_work_id) and
          cs.source_id in ^@alignable_sources and rt.source_id in ^@alignable_sources,
      distinct: true,
      select: {r.source_work_id, r.target_work_id},
      order_by: [asc: r.source_work_id, asc: r.target_work_id]
    )
    |> then(fn q -> if work, do: where(q, [r], r.source_work_id == ^work), else: q end)
    |> Repo.all()
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
